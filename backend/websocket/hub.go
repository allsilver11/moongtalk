package websocket

import (
	"encoding/json"
	"log"
	"messenger/config"
	"messenger/middleware"
	"messenger/models"
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

type Client struct {
	UserID int
	Conn   *websocket.Conn
	Send   chan []byte
}

type Hub struct {
	clients    map[int]*Client
	broadcast  chan []byte
	register   chan *Client
	unregister chan *Client
	mutex      sync.RWMutex
}

var hub = &Hub{
	clients:    make(map[int]*Client),
	broadcast:  make(chan []byte),
	register:   make(chan *Client),
	unregister: make(chan *Client),
}

func init() {
	go hub.run()
}

func (h *Hub) run() {
	for {
		select {
		case client := <-h.register:
			h.mutex.Lock()
			h.clients[client.UserID] = client
			h.mutex.Unlock()
			log.Printf("Client connected: user_id=%d", client.UserID)

		case client := <-h.unregister:
			h.mutex.Lock()
			if _, ok := h.clients[client.UserID]; ok {
				delete(h.clients, client.UserID)
				close(client.Send)
			}
			h.mutex.Unlock()
			log.Printf("Client disconnected: user_id=%d", client.UserID)

		case message := <-h.broadcast:
			h.mutex.RLock()
			for _, client := range h.clients {
				select {
				case client.Send <- message:
				default:
					close(client.Send)
					delete(h.clients, client.UserID)
				}
			}
			h.mutex.RUnlock()
		}
	}
}

func HandleWebSocket(c *gin.Context) {
	userID := middleware.GetUserID(c)

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}

	client := &Client{
		UserID: userID,
		Conn:   conn,
		Send:   make(chan []byte, 256),
	}

	hub.register <- client

	go client.writePump()
	go client.readPump()
}

func (c *Client) readPump() {
	defer func() {
		hub.unregister <- c
		c.Conn.Close()
	}()

	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}

		var wsMsg models.WebSocketMessage
		if err := json.Unmarshal(message, &wsMsg); err != nil {
			continue
		}

		switch wsMsg.Type {
		case "ping":
			response, _ := json.Marshal(models.WebSocketMessage{Type: "pong"})
			c.Send <- response
		}
	}
}

func (c *Client) writePump() {
	defer c.Conn.Close()

	for message := range c.Send {
		if err := c.Conn.WriteMessage(websocket.TextMessage, message); err != nil {
			break
		}
	}
}

func BroadcastToRoom(roomID int, message models.WebSocketMessage) {
	rows, err := config.DB.Query(`
		SELECT user_id FROM chat_room_members
		WHERE room_id = $1 AND left_at IS NULL
	`, roomID)

	if err != nil {
		return
	}
	defer rows.Close()

	msgBytes, _ := json.Marshal(message)

	hub.mutex.RLock()
	defer hub.mutex.RUnlock()

	for rows.Next() {
		var userID int
		if err := rows.Scan(&userID); err == nil {
			if client, ok := hub.clients[userID]; ok {
				select {
				case client.Send <- msgBytes:
				default:
				}
			}
		}
	}
}

func BroadcastToUser(userID int, message models.WebSocketMessage) {
	msgBytes, _ := json.Marshal(message)

	hub.mutex.RLock()
	defer hub.mutex.RUnlock()

	if client, ok := hub.clients[userID]; ok {
		select {
		case client.Send <- msgBytes:
		default:
		}
	}
}
