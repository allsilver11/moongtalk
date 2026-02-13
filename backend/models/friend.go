package models

import "time"

type Friend struct {
	ID        int       `json:"id"`
	UserID    int       `json:"user_id"`
	FriendID  int       `json:"friend_id"`
	CreatedAt time.Time `json:"created_at"`
}

type FriendWithUser struct {
	ID        int       `json:"id"`
	FriendID  int       `json:"friend_id"`
	Username  string    `json:"username"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

type AddFriendRequest struct {
	Query string `json:"query" binding:"required"`
}
