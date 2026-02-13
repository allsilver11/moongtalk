package services

import (
	"fmt"
	"log"
	"math/rand"
	"messenger/config"
	"time"
)

func init() {
	rand.Seed(time.Now().UnixNano())
}

func GenerateVerificationCode() string {
	return fmt.Sprintf("%06d", rand.Intn(1000000))
}

func SendSMS(phone, code string) error {
	if config.AppConfig.SMSMode == "mock" {
		log.Printf("[MOCK SMS] Phone: %s, Code: %s", phone, code)
		return nil
	}

	// TODO: Twilio 또는 NHN Cloud 연동
	// 프로덕션 환경에서 실제 SMS 발송 구현
	return nil
}

func SaveVerificationCode(phone, code string) error {
	expiresAt := time.Now().Add(5 * time.Minute)

	_, err := config.DB.Exec(`
		INSERT INTO phone_verifications (phone, code, expires_at)
		VALUES ($1, $2, $3)
	`, phone, code, expiresAt)

	return err
}

func VerifyCode(phone, code string) (bool, error) {
	var verified bool
	var id int

	err := config.DB.QueryRow(`
		SELECT id, verified FROM phone_verifications
		WHERE phone = $1 AND code = $2 AND expires_at > NOW()
		ORDER BY created_at DESC
		LIMIT 1
	`, phone, code).Scan(&id, &verified)

	if err != nil {
		return false, err
	}

	if verified {
		return true, nil
	}

	_, err = config.DB.Exec(`
		UPDATE phone_verifications SET verified = true WHERE id = $1
	`, id)

	return err == nil, err
}

func IsPhoneVerified(phone string) bool {
	var verified bool
	err := config.DB.QueryRow(`
		SELECT verified FROM phone_verifications
		WHERE phone = $1 AND verified = true AND expires_at > NOW()
		ORDER BY created_at DESC
		LIMIT 1
	`, phone).Scan(&verified)

	return err == nil && verified
}
