package handlers

import (
	"database/sql"
	"encoding/base64"
	"io"
	"messenger/config"
	"messenger/middleware"
	"messenger/models"
	"net/http"

	"github.com/gin-gonic/gin"
)

func GetProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var user models.User
	var profileImage []byte
	var profileImageMime sql.NullString

	err := config.DB.QueryRow(`
		SELECT id, username, phone, name, profile_image, profile_image_mime, created_at, updated_at
		FROM users WHERE id = $1
	`, userID).Scan(
		&user.ID, &user.Username, &user.Phone, &user.Name,
		&profileImage, &profileImageMime, &user.CreatedAt, &user.UpdatedAt,
	)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get profile"})
		return
	}

	response := gin.H{
		"id":         user.ID,
		"username":   user.Username,
		"phone":      user.Phone,
		"name":       user.Name,
		"created_at": user.CreatedAt,
		"updated_at": user.UpdatedAt,
	}

	if profileImage != nil && profileImageMime.Valid {
		response["profile_image"] = base64.StdEncoding.EncodeToString(profileImage)
		response["profile_image_mime"] = profileImageMime.String
	}

	c.JSON(http.StatusOK, response)
}

func UpdateProfile(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req models.UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := config.DB.Exec(`
		UPDATE users SET name = $1, updated_at = NOW() WHERE id = $2
	`, req.Name, userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update profile"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Profile updated successfully"})
}

func UpdateProfileImage(c *gin.Context) {
	userID := middleware.GetUserID(c)

	file, header, err := c.Request.FormFile("image")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Image file required"})
		return
	}
	defer file.Close()

	imageData, err := io.ReadAll(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read image"})
		return
	}

	mimeType := header.Header.Get("Content-Type")
	if mimeType == "" {
		mimeType = "image/jpeg"
	}

	_, err = config.DB.Exec(`
		UPDATE users SET profile_image = $1, profile_image_mime = $2, updated_at = NOW()
		WHERE id = $3
	`, imageData, mimeType, userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update profile image"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Profile image updated successfully"})
}

func GetProfileImage(c *gin.Context) {
	userID := c.Param("id")

	var imageData []byte
	var mimeType sql.NullString

	err := config.DB.QueryRow(`
		SELECT profile_image, profile_image_mime FROM users WHERE id = $1
	`, userID).Scan(&imageData, &mimeType)

	if err != nil || imageData == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Profile image not found"})
		return
	}

	contentType := "image/jpeg"
	if mimeType.Valid {
		contentType = mimeType.String
	}

	c.Data(http.StatusOK, contentType, imageData)
}

func SearchUser(c *gin.Context) {
	var req models.SearchUserRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	currentUserID := middleware.GetUserID(c)

	rows, err := config.DB.Query(`
		SELECT id, username, name FROM users
		WHERE (username = $1 OR phone = $1) AND id != $2
		LIMIT 10
	`, req.Query, currentUserID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Search failed"})
		return
	}
	defer rows.Close()

	var users []gin.H
	for rows.Next() {
		var id int
		var username, name string
		if err := rows.Scan(&id, &username, &name); err == nil {
			users = append(users, gin.H{
				"id":       id,
				"username": username,
				"name":     name,
			})
		}
	}

	if users == nil {
		users = []gin.H{}
	}

	c.JSON(http.StatusOK, users)
}
