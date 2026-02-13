package handlers

import (
	"database/sql"
	"io"
	"messenger/config"
	"messenger/middleware"
	"messenger/models"
	"messenger/websocket"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

func GetMessages(c *gin.Context) {
	userID := middleware.GetUserID(c)
	roomIDStr := c.Param("id")

	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var isMember bool
	err = config.DB.QueryRow(`
		SELECT EXISTS(SELECT 1 FROM chat_room_members WHERE room_id = $1 AND user_id = $2 AND left_at IS NULL)
	`, roomID, userID).Scan(&isMember)

	if !isMember {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not a member of this room"})
		return
	}

	limit := 50
	if l := c.Query("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 100 {
			limit = parsed
		}
	}

	offset := 0
	if o := c.Query("offset"); o != "" {
		if parsed, err := strconv.Atoi(o); err == nil && parsed >= 0 {
			offset = parsed
		}
	}

	rows, err := config.DB.Query(`
		SELECT m.id, m.room_id, m.sender_id, u.name, m.content, m.type, m.created_at,
			(SELECT mf.id FROM message_files mf WHERE mf.message_id = m.id LIMIT 1) as file_id
		FROM messages m
		LEFT JOIN users u ON m.sender_id = u.id
		WHERE m.room_id = $1
		ORDER BY m.created_at DESC
		LIMIT $2 OFFSET $3
	`, roomID, limit, offset)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get messages"})
		return
	}
	defer rows.Close()

	var messages []models.Message
	for rows.Next() {
		var m models.Message
		var senderName sql.NullString
		var content sql.NullString
		var fileID sql.NullInt64

		if err := rows.Scan(&m.ID, &m.RoomID, &m.SenderID, &senderName, &content, &m.Type, &m.CreatedAt, &fileID); err == nil {
			if senderName.Valid {
				m.SenderName = senderName.String
			}
			if content.Valid {
				m.Content = content.String
			}
			if fileID.Valid {
				fid := int(fileID.Int64)
				m.FileID = &fid
			}
			messages = append(messages, m)
		}
	}

	if messages == nil {
		messages = []models.Message{}
	}

	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	c.JSON(http.StatusOK, messages)
}

func SendMessage(c *gin.Context) {
	userID := middleware.GetUserID(c)
	roomIDStr := c.Param("id")

	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var isMember bool
	err = config.DB.QueryRow(`
		SELECT EXISTS(SELECT 1 FROM chat_room_members WHERE room_id = $1 AND user_id = $2 AND left_at IS NULL)
	`, roomID, userID).Scan(&isMember)

	if !isMember {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not a member of this room"})
		return
	}

	var req models.SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var messageID int
	err = config.DB.QueryRow(`
		INSERT INTO messages (room_id, sender_id, content, type)
		VALUES ($1, $2, $3, 'text')
		RETURNING id
	`, roomID, userID, req.Content).Scan(&messageID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to send message"})
		return
	}

	var senderName string
	config.DB.QueryRow("SELECT name FROM users WHERE id = $1", userID).Scan(&senderName)

	var createdAt string
	config.DB.QueryRow("SELECT created_at FROM messages WHERE id = $1", messageID).Scan(&createdAt)

	message := gin.H{
		"id":          messageID,
		"room_id":     roomID,
		"sender_id":   userID,
		"sender_name": senderName,
		"content":     req.Content,
		"type":        "text",
		"created_at":  createdAt,
	}

	websocket.BroadcastToRoom(roomID, models.WebSocketMessage{
		Type:    "new_message",
		Payload: message,
	})

	c.JSON(http.StatusCreated, message)
}

func SendFile(c *gin.Context) {
	userID := middleware.GetUserID(c)
	roomIDStr := c.Param("id")

	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var isMember bool
	err = config.DB.QueryRow(`
		SELECT EXISTS(SELECT 1 FROM chat_room_members WHERE room_id = $1 AND user_id = $2 AND left_at IS NULL)
	`, roomID, userID).Scan(&isMember)

	if !isMember {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not a member of this room"})
		return
	}

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File required"})
		return
	}
	defer file.Close()

	fileData, err := io.ReadAll(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read file"})
		return
	}

	mimeType := header.Header.Get("Content-Type")
	messageType := "image"
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}
	if len(mimeType) > 5 && mimeType[:5] == "video" {
		messageType = "video"
	}

	tx, err := config.DB.Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}
	defer tx.Rollback()

	var messageID int
	err = tx.QueryRow(`
		INSERT INTO messages (room_id, sender_id, type)
		VALUES ($1, $2, $3)
		RETURNING id
	`, roomID, userID, messageType).Scan(&messageID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create message"})
		return
	}

	var fileID int
	err = tx.QueryRow(`
		INSERT INTO message_files (message_id, filename, mime_type, file_data, file_size)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id
	`, messageID, header.Filename, mimeType, fileData, len(fileData)).Scan(&fileID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save file"})
		return
	}

	if err = tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to send file"})
		return
	}

	var senderName string
	config.DB.QueryRow("SELECT name FROM users WHERE id = $1", userID).Scan(&senderName)

	var createdAt string
	config.DB.QueryRow("SELECT created_at FROM messages WHERE id = $1", messageID).Scan(&createdAt)

	message := gin.H{
		"id":          messageID,
		"room_id":     roomID,
		"sender_id":   userID,
		"sender_name": senderName,
		"type":        messageType,
		"file_id":     fileID,
		"filename":    header.Filename,
		"created_at":  createdAt,
	}

	websocket.BroadcastToRoom(roomID, models.WebSocketMessage{
		Type:    "new_message",
		Payload: message,
	})

	c.JSON(http.StatusCreated, message)
}

func GetFile(c *gin.Context) {
	fileIDStr := c.Param("id")

	fileID, err := strconv.Atoi(fileIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid file ID"})
		return
	}

	var file models.MessageFile
	err = config.DB.QueryRow(`
		SELECT id, filename, mime_type, file_data, file_size
		FROM message_files WHERE id = $1
	`, fileID).Scan(&file.ID, &file.Filename, &file.MimeType, &file.FileData, &file.FileSize)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "File not found"})
		return
	}

	c.Header("Content-Disposition", "inline; filename=\""+file.Filename+"\"")
	c.Data(http.StatusOK, file.MimeType, file.FileData)
}
