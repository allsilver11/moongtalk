package models

import "time"

type Message struct {
	ID         int       `json:"id"`
	RoomID     int       `json:"room_id"`
	SenderID   int       `json:"sender_id"`
	SenderName string    `json:"sender_name,omitempty"`
	Content    string    `json:"content,omitempty"`
	Type       string    `json:"type"`
	FileID     *int      `json:"file_id,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}

type MessageFile struct {
	ID        int       `json:"id"`
	MessageID int       `json:"message_id"`
	Filename  string    `json:"filename"`
	MimeType  string    `json:"mime_type"`
	FileData  []byte    `json:"-"`
	FileSize  int       `json:"file_size"`
	CreatedAt time.Time `json:"created_at"`
}

type SendMessageRequest struct {
	Content string `json:"content" binding:"required"`
}

type WebSocketMessage struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
}
