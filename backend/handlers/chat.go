package handlers

import (
	"database/sql"
	"messenger/config"
	"messenger/middleware"
	"messenger/models"
	"messenger/websocket"
	"net/http"
	"sort"
	"strconv"

	"github.com/gin-gonic/gin"
)

func GetRooms(c *gin.Context) {
	userID := middleware.GetUserID(c)

	rows, err := config.DB.Query(`
		SELECT DISTINCT cr.id, cr.type, cr.name, cr.created_at,
			(SELECT COUNT(*) FROM chat_room_members WHERE room_id = cr.id AND left_at IS NULL) as member_count
		FROM chat_rooms cr
		JOIN chat_room_members crm ON cr.id = crm.room_id
		WHERE crm.user_id = $1 AND crm.left_at IS NULL
	`, userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get rooms"})
		return
	}
	defer rows.Close()

	var rooms []models.ChatRoomListItem
	for rows.Next() {
		var room models.ChatRoomListItem
		var name sql.NullString
		var createdAt sql.NullTime
		if err := rows.Scan(&room.ID, &room.Type, &name, &createdAt, &room.MemberCount); err == nil {
			if name.Valid {
				room.Name = name.String
			}
			if createdAt.Valid {
				room.LastTime = &createdAt.Time
			}

			var lastMsg sql.NullString
			var lastSender sql.NullString
			var lastMsgType sql.NullString
			var lastMsgTime sql.NullTime
			config.DB.QueryRow(`
				SELECT m.content, u.name, m.type, m.created_at
				FROM messages m
				LEFT JOIN users u ON m.sender_id = u.id
				WHERE m.room_id = $1
				ORDER BY m.created_at DESC
				LIMIT 1
			`, room.ID).Scan(&lastMsg, &lastSender, &lastMsgType, &lastMsgTime)

			if lastMsg.Valid {
				room.LastMessage = lastMsg.String
			} else if lastMsgType.Valid {
				switch lastMsgType.String {
				case "image":
					room.LastMessage = "사진을 보냈습니다"
				case "video":
					room.LastMessage = "동영상을 보냈습니다"
				}
			}
			if lastSender.Valid {
				room.LastSender = lastSender.String
			}
			if lastMsgTime.Valid {
				room.LastTime = &lastMsgTime.Time
			}

			var isMuted bool
			config.DB.QueryRow(`
				SELECT EXISTS(SELECT 1 FROM notification_mutes WHERE user_id = $1 AND room_id = $2)
			`, userID, room.ID).Scan(&isMuted)
			room.IsMuted = isMuted

			rooms = append(rooms, room)
		}
	}

	if rooms == nil {
		rooms = []models.ChatRoomListItem{}
	}

	sort.Slice(rooms, func(i, j int) bool {
		if rooms[i].LastTime == nil {
			return false
		}
		if rooms[j].LastTime == nil {
			return true
		}
		return rooms[i].LastTime.After(*rooms[j].LastTime)
	})

	c.JSON(http.StatusOK, rooms)
}

func CreateRoom(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req models.CreateRoomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	allMembers := append(req.MemberIDs, userID)

	if req.Type == "direct" && len(allMembers) == 2 {
		var existingRoomID int
		err := config.DB.QueryRow(`
			SELECT cr.id FROM chat_rooms cr
			WHERE cr.type = 'direct'
			AND (SELECT COUNT(*) FROM chat_room_members WHERE room_id = cr.id AND left_at IS NULL) = 2
			AND EXISTS (SELECT 1 FROM chat_room_members WHERE room_id = cr.id AND user_id = $1 AND left_at IS NULL)
			AND EXISTS (SELECT 1 FROM chat_room_members WHERE room_id = cr.id AND user_id = $2 AND left_at IS NULL)
		`, userID, req.MemberIDs[0]).Scan(&existingRoomID)

		if err == nil {
			c.JSON(http.StatusOK, gin.H{"room_id": existingRoomID, "existing": true})
			return
		}
	}

	tx, err := config.DB.Begin()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}
	defer tx.Rollback()

	var roomID int
	err = tx.QueryRow(`
		INSERT INTO chat_rooms (type, name) VALUES ($1, $2) RETURNING id
	`, req.Type, sql.NullString{String: req.Name, Valid: req.Name != ""}).Scan(&roomID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create room"})
		return
	}

	for _, memberID := range allMembers {
		_, err = tx.Exec(`
			INSERT INTO chat_room_members (room_id, user_id) VALUES ($1, $2)
			ON CONFLICT (room_id, user_id) DO UPDATE SET left_at = NULL
		`, roomID, memberID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add members"})
			return
		}
	}

	if err = tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create room"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"room_id": roomID})
}

func LeaveRoom(c *gin.Context) {
	userID := middleware.GetUserID(c)
	roomIDStr := c.Param("id")

	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	_, err = config.DB.Exec(`
		UPDATE chat_room_members SET left_at = NOW()
		WHERE room_id = $1 AND user_id = $2 AND left_at IS NULL
	`, roomID, userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to leave room"})
		return
	}

	var activeMembers int
	err = config.DB.QueryRow(`
		SELECT COUNT(*) FROM chat_room_members
		WHERE room_id = $1 AND left_at IS NULL
	`, roomID).Scan(&activeMembers)

	if err == nil && activeMembers == 0 {
		config.DB.Exec("DELETE FROM messages WHERE room_id = $1", roomID)
		config.DB.Exec("DELETE FROM chat_room_members WHERE room_id = $1", roomID)
		config.DB.Exec("DELETE FROM chat_rooms WHERE id = $1", roomID)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Left room successfully"})
}

func GetRoomMembers(c *gin.Context) {
	roomIDStr := c.Param("id")

	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	rows, err := config.DB.Query(`
		SELECT crm.id, crm.room_id, crm.user_id, u.username, u.name, crm.joined_at, COALESCE(crm.last_read_message_id, 0)
		FROM chat_room_members crm
		JOIN users u ON crm.user_id = u.id
		WHERE crm.room_id = $1 AND crm.left_at IS NULL
	`, roomID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get members"})
		return
	}
	defer rows.Close()

	var members []models.RoomMember
	for rows.Next() {
		var m models.RoomMember
		if err := rows.Scan(&m.ID, &m.RoomID, &m.UserID, &m.Username, &m.Name, &m.JoinedAt, &m.LastReadMessageID); err == nil {
			members = append(members, m)
		}
	}

	if members == nil {
		members = []models.RoomMember{}
	}

	c.JSON(http.StatusOK, members)
}

func ToggleMute(c *gin.Context) {
	userID := middleware.GetUserID(c)
	roomIDStr := c.Param("id")

	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var isMuted bool
	err = config.DB.QueryRow(`
		SELECT EXISTS(SELECT 1 FROM notification_mutes WHERE user_id = $1 AND room_id = $2)
	`, userID, roomID).Scan(&isMuted)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	if isMuted {
		_, err = config.DB.Exec(`
			DELETE FROM notification_mutes WHERE user_id = $1 AND room_id = $2
		`, userID, roomID)
	} else {
		_, err = config.DB.Exec(`
			INSERT INTO notification_mutes (user_id, room_id) VALUES ($1, $2)
			ON CONFLICT (user_id, room_id) DO NOTHING
		`, userID, roomID)
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update mute setting"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"is_muted": !isMuted})
}

func MarkRead(c *gin.Context) {
	userID := middleware.GetUserID(c)
	roomIDStr := c.Param("id")

	roomID, err := strconv.Atoi(roomIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid room ID"})
		return
	}

	var req struct {
		MessageID int `json:"message_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.MessageID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message_id required"})
		return
	}

	_, err = config.DB.Exec(`
		UPDATE chat_room_members
		SET last_read_message_id = GREATEST(COALESCE(last_read_message_id, 0), $1)
		WHERE room_id = $2 AND user_id = $3 AND left_at IS NULL
	`, req.MessageID, roomID, userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark read"})
		return
	}

	websocket.BroadcastToRoom(roomID, models.WebSocketMessage{
		Type: "messages_read",
		Payload: gin.H{
			"room_id":              roomID,
			"user_id":              userID,
			"last_read_message_id": req.MessageID,
		},
	})

	c.JSON(http.StatusOK, gin.H{"success": true})
}
