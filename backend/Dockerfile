FROM golang:1.21-alpine AS builder

WORKDIR /app

# 소스 코드 전체 복사
COPY . .

# 의존성 다운로드 및 빌드
RUN go mod tidy && CGO_ENABLED=0 GOOS=linux go build -o main .

# 실행 이미지
FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /root/

COPY --from=builder /app/main .

EXPOSE 8080

CMD ["./main"]
