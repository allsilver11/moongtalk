# 메신저 앱 개발 계획

## 기술 스택
- **Frontend**: Flutter (Android/iOS 크로스플랫폼)
- **Backend**: Go (Gin Framework)
- **Database**: PostgreSQL
- **실시간 통신**: WebSocket (gorilla/websocket)
- **인프라**: Docker Compose

## 테마 색상
- Primary: 초록색 (`#4CAF50`)
- Secondary: 개나리색 (`#FFD700`)

---

## 프로젝트 구조

```
messenger/
├── docker-compose.yml
├── backend/
│   ├── Dockerfile
│   ├── go.mod
│   ├── main.go
│   ├── config/
│   │   └── config.go
│   ├── handlers/
│   │   ├── auth.go          # 회원가입, 로그인, SMS 인증
│   │   ├── user.go          # 프로필 관리
│   │   ├── friend.go        # 친구 추가/목록
│   │   ├── chat.go          # 채팅방 관리
│   │   └── message.go       # 메시지/파일 전송
│   ├── models/
│   │   ├── user.go
│   │   ├── friend.go
│   │   ├── chat.go
│   │   └── message.go
│   ├── middleware/
│   │   └── auth.go          # JWT 인증 미들웨어
│   ├── services/
│   │   ├── sms.go           # SMS 인증코드 발송
│   │   └── crypto.go        # 비밀번호 암호화 (bcrypt)
│   └── websocket/
│       └── hub.go           # 실시간 채팅 허브
├── frontend/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── config/
│   │   │   └── theme.dart   # 초록+개나리 테마
│   │   ├── models/
│   │   ├── screens/
│   │   │   ├── auth/
│   │   │   │   ├── login_screen.dart
│   │   │   │   ├── register_screen.dart
│   │   │   │   └── sms_verify_screen.dart
│   │   │   ├── profile_screen.dart
│   │   │   ├── friends_screen.dart
│   │   │   ├── chat_list_screen.dart
│   │   │   └── chat_screen.dart
│   │   ├── widgets/
│   │   ├── services/
│   │   │   ├── api_service.dart
│   │   │   └── websocket_service.dart
│   │   └── providers/
│   │       └── auth_provider.dart
│   └── pubspec.yaml
└── database/
    └── init.sql
```

---

## 데이터베이스 테이블 설계

### 1. users (사용자)
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,      -- 로그인 ID
    phone VARCHAR(20) UNIQUE NOT NULL,         -- 휴대폰번호
    password_hash VARCHAR(255) NOT NULL,       -- bcrypt 암호화
    name VARCHAR(100) NOT NULL,                -- 실명 (프로필 노출)
    profile_image BYTEA,                       -- 프로필 사진 (1장)
    profile_image_mime VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### 2. phone_verifications (SMS 인증)
```sql
CREATE TABLE phone_verifications (
    id SERIAL PRIMARY KEY,
    phone VARCHAR(20) NOT NULL,
    code VARCHAR(6) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 3. friends (친구 관계)
```sql
CREATE TABLE friends (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    friend_id INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, friend_id)
);
```

### 4. chat_rooms (채팅방)
```sql
CREATE TABLE chat_rooms (
    id SERIAL PRIMARY KEY,
    type VARCHAR(10) NOT NULL,                 -- 'direct' or 'group'
    name VARCHAR(100),                         -- 그룹 채팅방 이름
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 5. chat_room_members (채팅방 멤버)
```sql
CREATE TABLE chat_room_members (
    id SERIAL PRIMARY KEY,
    room_id INTEGER REFERENCES chat_rooms(id),
    user_id INTEGER REFERENCES users(id),
    joined_at TIMESTAMP DEFAULT NOW(),
    left_at TIMESTAMP,                         -- 나간 시간 (NULL이면 활성)
    UNIQUE(room_id, user_id)
);
```

### 6. messages (메시지)
```sql
CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    room_id INTEGER REFERENCES chat_rooms(id),
    sender_id INTEGER REFERENCES users(id),
    content TEXT,                              -- 텍스트 메시지
    type VARCHAR(10) NOT NULL,                 -- 'text', 'image', 'video'
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 7. message_files (미디어 파일)
```sql
CREATE TABLE message_files (
    id SERIAL PRIMARY KEY,
    message_id INTEGER REFERENCES messages(id),
    filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_data BYTEA NOT NULL,                  -- 파일 바이너리 저장
    file_size INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## 구현 단계

### Phase 1: 프로젝트 초기 설정
1. 프로젝트 디렉토리 구조 생성
2. Docker Compose 설정 (PostgreSQL + Go 백엔드)
3. Go 프로젝트 초기화 (go.mod, 의존성)
4. Flutter 프로젝트 초기화
5. 데이터베이스 초기화 스크립트 (init.sql)

### Phase 2: 백엔드 - 인증 시스템
1. 데이터베이스 연결 설정
2. SMS 인증코드 발송 서비스 (Mock 모드 포함)
3. 회원가입 API (bcrypt 비밀번호 암호화)
4. 로그인 API (JWT 토큰 발급)
5. JWT 인증 미들웨어

### Phase 3: 백엔드 - 사용자/친구 기능
1. 프로필 조회/수정 API
2. 프로필 사진 업로드 API (BYTEA 저장)
3. 친구 추가 API (ID 또는 휴대폰번호)
4. 친구 목록 API

### Phase 4: 백엔드 - 채팅 기능
1. WebSocket 허브 구현
2. 채팅방 생성 API (1:1, 그룹)
3. 채팅방 목록 API
4. 채팅방 나가기 API (전원 퇴장 시 삭제 로직)
5. 메시지 전송 API (텍스트)
6. 미디어 파일 전송 API (사진/영상)
7. 메시지 내역 조회 API

### Phase 5: Flutter 앱 - 기본 구조
1. 테마 설정 (초록 + 개나리)
2. 라우팅 설정
3. API 서비스 클래스
4. 상태 관리 (Provider)

### Phase 6: Flutter 앱 - 인증 화면
1. 로그인 화면
2. 회원가입 화면
3. SMS 인증 화면
4. 갤러리 접근 권한 설정

### Phase 7: Flutter 앱 - 메인 화면
1. 프로필 화면 (사진 변경 가능)
2. 친구 목록 화면 (친구 추가 기능)
3. 채팅 목록 화면
4. 채팅 화면 (실시간 메시지, 미디어 전송)

---

## API 엔드포인트

### 인증
- `POST /api/auth/send-code` - SMS 인증코드 발송
- `POST /api/auth/verify-code` - 인증코드 확인
- `POST /api/auth/register` - 회원가입
- `POST /api/auth/login` - 로그인

### 사용자
- `GET /api/users/me` - 내 프로필 조회
- `PUT /api/users/me` - 프로필 수정
- `PUT /api/users/me/profile-image` - 프로필 사진 변경
- `GET /api/users/search?q=` - 사용자 검색 (ID/휴대폰)

### 친구
- `GET /api/friends` - 친구 목록
- `POST /api/friends` - 친구 추가
- `DELETE /api/friends/:id` - 친구 삭제

### 채팅
- `GET /api/rooms` - 채팅방 목록
- `POST /api/rooms` - 채팅방 생성
- `DELETE /api/rooms/:id/leave` - 채팅방 나가기
- `GET /api/rooms/:id/messages` - 메시지 내역
- `POST /api/rooms/:id/messages` - 메시지 전송
- `POST /api/rooms/:id/files` - 파일 전송
- `GET /api/files/:id` - 파일 다운로드

### WebSocket
- `WS /ws` - 실시간 채팅 연결

---

## 주요 Flutter 패키지
```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.0           # 상태 관리
  http: ^1.1.0               # HTTP 클라이언트
  web_socket_channel: ^2.4.0 # WebSocket
  image_picker: ^1.0.0       # 갤러리 접근
  shared_preferences: ^2.2.0 # 로컬 저장소
  jwt_decoder: ^2.0.0        # JWT 디코딩
```

---

## 실행 방법

### 1. Docker Compose 실행
```bash
cd messenger
docker-compose up --build
```

### 2. Flutter 앱 실행
```bash
cd frontend
flutter run
```

---

## 기능 테스트 체크리스트
- [ ] 회원가입 (SMS 인증 → 가입 완료)
- [ ] 로그인
- [ ] 프로필 사진 설정/변경
- [ ] 친구 추가 (ID/휴대폰번호)
- [ ] 1:1 채팅방 생성 및 메시지 전송
- [ ] 그룹 채팅방 생성 및 메시지 전송
- [ ] 사진/영상 전송
- [ ] 채팅방 나가기 (전원 퇴장 시 삭제 확인)

---

## SMS 인증 (개발 모드)

개발 환경에서는 실제 SMS 발송 대신 Mock 모드 사용:
- 인증코드가 콘솔에 출력됨
- 프로덕션 시 Twilio/NHN Cloud 등 연동 가능
