package handlers

import (
	"database/sql"
	"messenger/config"
	"messenger/middleware"
	"messenger/models"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

func GetFriends(c *gin.Context) {
	userID := middleware.GetUserID(c)

	rows, err := config.DB.Query(`
		SELECT f.id, f.friend_id, u.username, u.name, f.created_at
		FROM friends f
		JOIN users u ON f.friend_id = u.id
		WHERE f.user_id = $1
		ORDER BY u.name
	`, userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get friends"})
		return
	}
	defer rows.Close()

	var friends []models.FriendWithUser
	for rows.Next() {
		var f models.FriendWithUser
		if err := rows.Scan(&f.ID, &f.FriendID, &f.Username, &f.Name, &f.CreatedAt); err == nil {
			friends = append(friends, f)
		}
	}

	if friends == nil {
		friends = []models.FriendWithUser{}
	}

	c.JSON(http.StatusOK, friends)
}

func AddFriend(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req models.AddFriendRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var friendID int
	err := config.DB.QueryRow(`
		SELECT id FROM users WHERE (username = $1 OR phone = $1) AND id != $2
	`, req.Query, userID).Scan(&friendID)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	var exists bool
	err = config.DB.QueryRow(`
		SELECT EXISTS(SELECT 1 FROM friends WHERE user_id = $1 AND friend_id = $2)
	`, userID, friendID).Scan(&exists)

	if exists {
		c.JSON(http.StatusConflict, gin.H{"error": "Already friends"})
		return
	}

	_, err = config.DB.Exec(`
		INSERT INTO friends (user_id, friend_id) VALUES ($1, $2)
	`, userID, friendID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add friend"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": "Friend added successfully"})
}

func DeleteFriend(c *gin.Context) {
	userID := middleware.GetUserID(c)
	friendIDStr := c.Param("id")

	friendID, err := strconv.Atoi(friendIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid friend ID"})
		return
	}

	result, err := config.DB.Exec(`
		DELETE FROM friends WHERE user_id = $1 AND friend_id = $2
	`, userID, friendID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete friend"})
		return
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "Friend not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Friend deleted successfully"})
}
