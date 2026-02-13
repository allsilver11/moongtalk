package main

import (
	"log"
	"messenger/config"
	"messenger/handlers"
	"messenger/middleware"
	"messenger/websocket"

	"github.com/gin-gonic/gin"
)

func main() {
	if err := config.Load(); err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}
	defer config.DB.Close()

	r := gin.Default()

	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	api := r.Group("/api")
	{
		auth := api.Group("/auth")
		{
			auth.POST("/send-code", handlers.SendCode)
			auth.POST("/verify-code", handlers.VerifyCode)
			auth.POST("/register", handlers.Register)
			auth.POST("/login", handlers.Login)
		}

		users := api.Group("/users")
		users.Use(middleware.AuthRequired())
		{
			users.GET("/me", handlers.GetProfile)
			users.PUT("/me", handlers.UpdateProfile)
			users.PUT("/me/profile-image", handlers.UpdateProfileImage)
			users.GET("/search", handlers.SearchUser)
			users.GET("/:id/profile-image", handlers.GetProfileImage)
		}

		friends := api.Group("/friends")
		friends.Use(middleware.AuthRequired())
		{
			friends.GET("", handlers.GetFriends)
			friends.POST("", handlers.AddFriend)
			friends.DELETE("/:id", handlers.DeleteFriend)
		}

		rooms := api.Group("/rooms")
		rooms.Use(middleware.AuthRequired())
		{
			rooms.GET("", handlers.GetRooms)
			rooms.POST("", handlers.CreateRoom)
			rooms.DELETE("/:id/leave", handlers.LeaveRoom)
			rooms.GET("/:id/members", handlers.GetRoomMembers)
			rooms.GET("/:id/messages", handlers.GetMessages)
			rooms.POST("/:id/messages", handlers.SendMessage)
			rooms.POST("/:id/files", handlers.SendFile)
			rooms.POST("/:id/mute", handlers.ToggleMute)
			rooms.POST("/:id/read", handlers.MarkRead)
		}

		files := api.Group("/files")
		files.Use(middleware.AuthRequired())
		{
			files.GET("/:id", handlers.GetFile)
		}
	}

	r.GET("/ws", middleware.AuthRequired(), websocket.HandleWebSocket)

	log.Println("Server starting on :8080")
	if err := r.Run(":8080"); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
