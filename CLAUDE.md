# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Korean-language messenger application (메신저 앱) with a Go backend, Flutter frontend, and PostgreSQL database. Real-time chat via WebSocket. Deployed with Docker Compose behind nginx reverse proxy.

## Build & Run Commands

### Full stack (Docker Compose)
```bash
docker-compose up --build        # start all services (nginx:80, backend:8080, postgres:5432)
docker-compose down              # stop all
docker-compose down -v           # stop and remove volumes (resets DB)
```

### Backend (Go)
```bash
cd backend
go build -o main .               # build
go run .                         # run (needs postgres running)
go mod tidy                      # sync dependencies
```

### Frontend (Flutter)
```bash
cd frontend
flutter pub get                  # install dependencies
flutter run                      # run on connected device/emulator
flutter build web                # build for web deployment (output: build/web/)
dart analyze                     # lint
flutter test                     # run all tests
flutter test test/widget_test.dart  # run single test
```

## Architecture

### Backend (`backend/`) — Go + Gin

**`main.go`** — All route definitions and CORS middleware. Server on `:8080`.

**API Routes:**
- `POST /api/auth/send-code`, `POST /api/auth/verify-code`, `POST /api/auth/register`, `POST /api/auth/login` — no auth required
- `GET/PUT /api/users/me`, `PUT /api/users/me/profile-image`, `GET /api/users/search?q=`, `GET /api/users/:id/profile-image`
- `GET/POST /api/friends`, `DELETE /api/friends/:id`
- `GET/POST /api/rooms`, `DELETE /api/rooms/:id/leave`, `GET /api/rooms/:id/members`
- `GET /api/rooms/:id/messages` — paginated (default 50, max 100, supports `offset`)
- `POST /api/rooms/:id/messages`, `POST /api/rooms/:id/files` — send text/file message
- `POST /api/rooms/:id/mute` — toggle mute for room
- `POST /api/rooms/:id/read` — mark messages read (updates `last_read_message_id`)
- `GET /api/files/:id` — download file by ID (returns raw bytes with MIME type)
- `GET /ws?token=<jwt>` — WebSocket upgrade

**`config/`** — DB connection and env-based config. Required env vars: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `JWT_SECRET`, `SMS_MODE` (use `mock` for dev).

**`handlers/`** — One file per domain: `auth.go`, `user.go`, `friend.go`, `chat.go`, `message.go`.

**`middleware/auth.go`** — JWT middleware; supports both `Authorization: Bearer` header and `?token=` query param (needed for WebSocket, since browsers can't set headers on WS upgrade).

**`models/`** — Go structs matching DB tables + JSON tags.

**`services/`** — `crypto.go` (bcrypt), `sms.go` (mock mode prints 6-digit code to console; TODO: real SMS provider).

**`websocket/hub.go`** — Singleton Hub. Keeps `map[userID]*Client`. Methods: `BroadcastToRoom(roomID, msg)` queries DB for active members then delivers; `BroadcastToUser(userID, msg)` for unicast. WebSocket message types:
- `ping` → `pong` (client sends every 30s)
- `new_message` — full message payload broadcast to room members
- `messages_read` — broadcast when user marks messages read (triggers read receipt UI update)

Auth flow: SMS send → verify → register (checks verified phone) → login returns JWT (24h) → JWT required for all `/api/*` except `/api/auth/*`.

### Frontend (`frontend/`) — Flutter + Provider

**Key dependencies** (`pubspec.yaml`): `provider`, `http`, `web_socket_channel`, `image_picker`, `shared_preferences`, `jwt_decoder`, `intl`, `google_fonts` (Noto Sans KR for Korean text), `flutter_local_notifications`.

**`lib/config/api_config.dart`** — URL strategy: Web builds use `Uri.base.origin` (auto-adapts to hosting server); mobile uses hardcoded IP `http://16.8.32.84`. Update the mobile URL when changing deployment targets.

**`lib/config/theme.dart`** — Green (`#2E7D32` primary, `#4CAF50` light) + Gold (`#FFD700`) theme; soft green background `#F6F7F2`.

**`lib/providers/auth_provider.dart`** — Auth state (`ChangeNotifier`): `isLoggedIn`, current `User`, error string. Handles login/register/logout, persists JWT in `SharedPreferences`, auto-connects WebSocket on login.

**`lib/providers/notification_provider.dart`** — Tracks `activeRoomId` (suppresses notifications for open room), `mutedRoomIds`, emits `InAppNotification` stream. Filters out own messages, active room messages, and muted rooms. Shows both OS notifications and in-app slide-down banners (4-second auto-dismiss).

**`lib/services/api_service.dart`** — Static HTTP client; auto-adds `Authorization: Bearer` header from stored JWT.

**`lib/services/websocket_service.dart`** — Singleton; auto-reconnects on disconnect (5s delay); exposes `messageStream` for listeners.

**Screens:**
- `screens/auth/` — `login_screen`, `register_screen`, `sms_verify_screen`
- `screens/friends_screen` — Friend list with search-and-add dialog, swipe-to-delete
- `screens/chat_list_screen` — Room list sorted by last message time; create 1:1 or group rooms; listens to WebSocket to refresh; syncs mute state with `NotificationProvider`
- `screens/chat_screen` — Infinite-scroll message list; real-time updates via WebSocket; read receipts shown as "✓" count under own messages; image/video display with thumbnails
- `screens/profile_screen` — Edit name, upload profile image, logout

### Database (`database/init.sql`) — 8 tables

`users`, `phone_verifications` (6-digit codes, 5-min expiry), `friends` (unidirectional), `chat_rooms`, `chat_room_members` (with `left_at` nullable + `last_read_message_id` for read receipts), `messages`, `message_files` (binary data as `BYTEA`), `notification_mutes`.

Media files and profile images stored as `BYTEA` directly in the database (not on filesystem).

### Infrastructure

- **`docker-compose.yml`** — `web` (nginx:80), `backend` (Go:8080), `postgres` (15-alpine:5432, 1GB shm). Backend waits for postgres health check.
- **`nginx.conf`** — `/` → Flutter web static files (JS/CSS/WASM cached 1 year immutable; `index.html` no-cache); `/api/` and `/ws` → backend proxy (with WebSocket upgrade headers).

## Key Conventions

- UI text is in Korean (한국어). Message previews: `"사진을 보냈습니다"` (image), `"동영상을 보냈습니다"` (video).
- Chat rooms: `direct` (1:1, deduplicated — creating a duplicate returns the existing room) or `group`.
- When all members leave a room, it and all its messages are deleted automatically.
- Message types: `text` (content field), `image` or `video` (content NULL, `file_id` set).
- Read receipts: `last_read_message_id` per member; own messages show count of members who haven't read yet.
- Friends are unidirectional (adding doesn't require acceptance).
- Profile images transmitted as base64 in HTTP responses, stored as BYTEA in DB.
