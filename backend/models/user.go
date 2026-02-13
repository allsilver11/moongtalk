package models

import "time"

type User struct {
	ID               int       `json:"id"`
	Username         string    `json:"username"`
	Phone            string    `json:"phone"`
	PasswordHash     string    `json:"-"`
	Name             string    `json:"name"`
	ProfileImage     []byte    `json:"-"`
	ProfileImageMime string    `json:"profile_image_mime,omitempty"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type RegisterRequest struct {
	Username string `json:"username" binding:"required,min=3,max=50"`
	Phone    string `json:"phone" binding:"required"`
	Password string `json:"password" binding:"required,min=6"`
	Name     string `json:"name" binding:"required"`
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type LoginResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

type SendCodeRequest struct {
	Phone string `json:"phone" binding:"required"`
}

type VerifyCodeRequest struct {
	Phone string `json:"phone" binding:"required"`
	Code  string `json:"code" binding:"required,len=6"`
}

type UpdateProfileRequest struct {
	Name string `json:"name" binding:"required"`
}

type SearchUserRequest struct {
	Query string `form:"q" binding:"required"`
}
