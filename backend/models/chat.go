package models

import "time"

type ChatRoom struct {
	ID        int        `json:"id"`
	Type      string     `json:"type"`
	Name      string     `json:"name,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
	Members   []RoomMember `json:"members,omitempty"`
	LastMessage *Message  `json:"last_message,omitempty"`
}

type RoomMember struct {
	ID                int        `json:"id"`
	RoomID            int        `json:"room_id"`
	UserID            int        `json:"user_id"`
	Username          string     `json:"username,omitempty"`
	Name              string     `json:"name,omitempty"`
	JoinedAt          time.Time  `json:"joined_at"`
	LeftAt            *time.Time `json:"left_at,omitempty"`
	LastReadMessageID int        `json:"last_read_message_id"`
}

type CreateRoomRequest struct {
	Type      string `json:"type" binding:"required,oneof=direct group"`
	Name      string `json:"name"`
	MemberIDs []int  `json:"member_ids" binding:"required,min=1"`
}

type ChatRoomListItem struct {
	ID           int       `json:"id"`
	Type         string    `json:"type"`
	Name         string    `json:"name"`
	LastMessage  string    `json:"last_message,omitempty"`
	LastSender   string    `json:"last_sender,omitempty"`
	LastTime     *time.Time `json:"last_time,omitempty"`
	MemberCount  int       `json:"member_count"`
	IsMuted      bool      `json:"is_muted"`
}
