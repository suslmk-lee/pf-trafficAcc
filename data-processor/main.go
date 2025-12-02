package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/redis/go-redis/v9"
)

type RealTimeSMS struct {
	AccDate    string  `json:"accDate"`
	AccHour    string  `json:"accHour"`
	AccPointNM string  `json:"accPointNM"`
	LinkID     string  `json:"linkId"`
	AccInfo    string  `json:"smsText"`    // 고속도로 API uses smsText
	AccType    string  `json:"accType"`
	Latitude   float64 `json:"latitude"`   // Always float64 from API
	Longitude  float64 `json:"altitude"`   // 고속도로 API uses "altitude" for longitude
	RoadNM     string  `json:"roadNM"`     // Road name
}

type Config struct {
	DBHost       string
	DBUser       string
	DBPassword   string
	DBName       string
	RedisAddr    string
	StreamKey    string
	ConsumerGroup string
	ConsumerName  string
}

type Processor struct {
	config      Config
	db          *sql.DB
	redisClient *redis.Client
}

func loadConfig() Config {
	dbHost := os.Getenv("DB_HOST")
	if dbHost == "" {
		dbHost = "mariadb-central.default.svc.cluster.local:3306"
	}

	dbUser := os.Getenv("DB_USER")
	if dbUser == "" {
		dbUser = "trafficuser"
	}

	dbPassword := os.Getenv("DB_PASSWORD")
	if dbPassword == "" {
		dbPassword = "trafficpass"
	}

	dbName := os.Getenv("DB_NAME")
	if dbName == "" {
		dbName = "trafficdb"
	}

	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr == "" {
		redisAddr = "redis-central.default.svc.cluster.local:6379"
	}

	consumerName := os.Getenv("CONSUMER_NAME")
	if consumerName == "" {
		hostname, _ := os.Hostname()
		consumerName = fmt.Sprintf("processor-%s", hostname)
	}

	return Config{
		DBHost:        dbHost,
		DBUser:        dbUser,
		DBPassword:    dbPassword,
		DBName:        dbName,
		RedisAddr:     redisAddr,
		StreamKey:     "traffic-stream",
		ConsumerGroup: "processor-group",
		ConsumerName:  consumerName,
	}
}

func NewProcessor(config Config) (*Processor, error) {
	// Connect to MariaDB
	dsn := fmt.Sprintf("%s:%s@tcp(%s)/%s?parseTime=true",
		config.DBUser, config.DBPassword, config.DBHost, config.DBName)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(time.Minute * 5)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := db.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	log.Printf("Connected to MariaDB at %s", config.DBHost)

	// Connect to Redis
	rdb := redis.NewClient(&redis.Options{
		Addr: config.RedisAddr,
	})

	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	log.Printf("Connected to Redis at %s", config.RedisAddr)

	processor := &Processor{
		config:      config,
		db:          db,
		redisClient: rdb,
	}

	// Initialize consumer group
	if err := processor.initConsumerGroup(ctx); err != nil {
		log.Printf("Warning: Failed to initialize consumer group: %v", err)
	}

	return processor, nil
}

func (p *Processor) initConsumerGroup(ctx context.Context) error {
	// Try to create consumer group (MKSTREAM creates stream if not exists)
	err := p.redisClient.XGroupCreateMkStream(ctx, p.config.StreamKey, p.config.ConsumerGroup, "0").Err()
	if err != nil && err.Error() != "BUSYGROUP Consumer Group name already exists" {
		return err
	}

	log.Printf("Consumer group '%s' initialized for stream '%s'",
		p.config.ConsumerGroup, p.config.StreamKey)

	return nil
}

func (p *Processor) isDuplicate(ctx context.Context, accident RealTimeSMS) (bool, error) {
	// Convert date and hour to match database format
	accDate := formatDate(accident.AccDate)
	accHour := formatHour(accident.AccHour)

	var count int
	query := `SELECT COUNT(*) FROM traffic_accidents
	          WHERE acc_date = ? AND acc_hour = ? AND acc_point_nm = ? AND sms_text = ?`

	err := p.db.QueryRowContext(ctx, query,
		accDate, accHour, accident.AccPointNM, accident.AccInfo).Scan(&count)

	if err != nil {
		return false, fmt.Errorf("failed to check duplicate: %w", err)
	}

	return count > 0, nil
}

func (p *Processor) insertAccident(ctx context.Context, accident RealTimeSMS) error {
	// Convert date format: "2025.10.28" -> "20251028"
	accDate := formatDate(accident.AccDate)

	// Convert hour format: "16:10:23" -> "1610"
	accHour := formatHour(accident.AccHour)

	// Use INSERT ... ON DUPLICATE KEY UPDATE to update created_at for existing accidents
	query := `INSERT INTO traffic_accidents
	          (acc_date, acc_hour, acc_point_nm, sms_text, acc_type, latitude, altitude, road_nm, nosun_nm, created_at)
	          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
	          ON DUPLICATE KEY UPDATE created_at = NOW()`

	_, err := p.db.ExecContext(ctx, query,
		accDate, accHour, accident.AccPointNM,
		accident.AccInfo, accident.AccType,
		accident.Latitude, accident.Longitude,
		accident.RoadNM, "")

	if err != nil {
		return fmt.Errorf("failed to insert accident: %w", err)
	}

	log.Printf("Inserted/Updated: %s - %s at %s (road: %s)",
		accident.AccType, accident.AccPointNM, accDate+" "+accHour, accident.RoadNM)

	return nil
}

// formatDate converts "2025.10.28" or "2023.07.05" to "20251028" or "20230705"
func formatDate(date string) string {
	// Remove all non-digit characters
	cleaned := ""
	for _, ch := range date {
		if ch >= '0' && ch <= '9' {
			cleaned += string(ch)
		}
	}
	// Ensure it's exactly 8 digits
	if len(cleaned) > 8 {
		cleaned = cleaned[:8]
	}
	return cleaned
}

// formatHour converts "16:10:23" to "1610"
func formatHour(hour string) string {
	// Extract only digits (HHMM format)
	cleaned := ""
	for _, ch := range hour {
		if ch >= '0' && ch <= '9' {
			cleaned += string(ch)
		}
	}
	// Return first 4 digits (HHMM)
	if len(cleaned) >= 4 {
		return cleaned[:4]
	}
	return cleaned
}

func (p *Processor) processMessage(ctx context.Context, msg redis.XMessage) error {
	dataStr, ok := msg.Values["data"].(string)
	if !ok {
		return fmt.Errorf("invalid message format: missing 'data' field")
	}

	var accidents []RealTimeSMS
	if err := json.Unmarshal([]byte(dataStr), &accidents); err != nil {
		return fmt.Errorf("failed to unmarshal accidents: %w", err)
	}

	source := msg.Values["source"]
	log.Printf("Processing message ID %s with %d accidents (source: %v)",
		msg.ID, len(accidents), source)

	processedCount := 0

	for _, accident := range accidents {
		// Always insert or update to refresh created_at timestamp
		if err := p.insertAccident(ctx, accident); err != nil {
			log.Printf("Error upserting accident %s: %v", accident.AccPointNM, err)
			continue
		}
		processedCount++
	}

	log.Printf("Processed message %s: %d upserted, %d total",
		msg.ID, processedCount, len(accidents))

	return nil
}

func (p *Processor) aggregateDailyStats(ctx context.Context, date string) error {
	log.Printf("Starting daily aggregation for date: %s", date)

	// Aggregate accident counts by type for the given date
	query := `
		INSERT INTO daily_accident_stats (stat_date, acc_type, accident_count)
		SELECT
			DATE(created_at) as stat_date,
			acc_type,
			COUNT(*) as accident_count
		FROM traffic_accidents
		WHERE DATE(created_at) = ?
		GROUP BY DATE(created_at), acc_type
		ON DUPLICATE KEY UPDATE
			accident_count = VALUES(accident_count),
			updated_at = CURRENT_TIMESTAMP
	`

	result, err := p.db.ExecContext(ctx, query, date)
	if err != nil {
		return fmt.Errorf("failed to aggregate daily stats: %w", err)
	}

	rowsAffected, _ := result.RowsAffected()
	log.Printf("Daily aggregation completed for %s: %d records processed", date, rowsAffected)

	return nil
}

func (p *Processor) runDailyAggregation(ctx context.Context) {
	// Calculate next midnight
	now := time.Now()
	nextMidnight := time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, now.Location())
	durationUntilMidnight := nextMidnight.Sub(now)

	log.Printf("Next daily aggregation scheduled at: %s (in %s)",
		nextMidnight.Format("2006-01-02 15:04:05"), durationUntilMidnight)

	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()

	// Initial wait until midnight
	timer := time.NewTimer(durationUntilMidnight)
	defer timer.Stop()

	for {
		select {
		case <-ctx.Done():
			log.Println("Daily aggregation routine stopped")
			return
		case <-timer.C:
			// First execution at midnight
			yesterday := time.Now().AddDate(0, 0, -1).Format("2006-01-02")
			if err := p.aggregateDailyStats(ctx, yesterday); err != nil {
				log.Printf("Error in daily aggregation: %v", err)
			}
			// Reset timer to run every 24 hours
			timer.Reset(24 * time.Hour)
		case <-ticker.C:
			// Subsequent executions
			yesterday := time.Now().AddDate(0, 0, -1).Format("2006-01-02")
			if err := p.aggregateDailyStats(ctx, yesterday); err != nil {
				log.Printf("Error in daily aggregation: %v", err)
			}
		}
	}
}

func (p *Processor) Start(ctx context.Context) error {
	log.Printf("Data Processor started (Consumer: %s, Group: %s)",
		p.config.ConsumerName, p.config.ConsumerGroup)

	// Start daily aggregation routine in a separate goroutine
	go p.runDailyAggregation(ctx)

	for {
		select {
		case <-ctx.Done():
			log.Println("Processor stopped")
			return nil
		default:
		}

		// Read from stream using consumer group
		streams, err := p.redisClient.XReadGroup(ctx, &redis.XReadGroupArgs{
			Group:    p.config.ConsumerGroup,
			Consumer: p.config.ConsumerName,
			Streams:  []string{p.config.StreamKey, ">"},
			Count:    1,
			Block:    2 * time.Second,
		}).Result()

		if err != nil {
			if err == redis.Nil {
				// No new messages, continue
				continue
			}
			log.Printf("Error reading from stream: %v", err)
			time.Sleep(1 * time.Second)
			continue
		}

		for _, stream := range streams {
			for _, msg := range stream.Messages {
				if err := p.processMessage(ctx, msg); err != nil {
					log.Printf("Error processing message %s: %v", msg.ID, err)
					continue
				}

				// Acknowledge the message
				if err := p.redisClient.XAck(ctx, p.config.StreamKey, p.config.ConsumerGroup, msg.ID).Err(); err != nil {
					log.Printf("Error acknowledging message %s: %v", msg.ID, err)
				} else {
					log.Printf("Acknowledged message %s", msg.ID)
				}
			}
		}
	}
}

func (p *Processor) Close() error {
	if err := p.db.Close(); err != nil {
		log.Printf("Error closing database: %v", err)
	}
	if err := p.redisClient.Close(); err != nil {
		log.Printf("Error closing Redis client: %v", err)
	}
	return nil
}

func main() {
	config := loadConfig()

	log.Printf("Configuration:")
	log.Printf("  DB Host: %s", config.DBHost)
	log.Printf("  DB Name: %s", config.DBName)
	log.Printf("  Redis Address: %s", config.RedisAddr)
	log.Printf("  Stream Key: %s", config.StreamKey)
	log.Printf("  Consumer Group: %s", config.ConsumerGroup)
	log.Printf("  Consumer Name: %s", config.ConsumerName)

	processor, err := NewProcessor(config)
	if err != nil {
		log.Fatalf("Failed to create processor: %v", err)
	}
	defer processor.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle shutdown gracefully
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		log.Println("Shutdown signal received")
		cancel()
	}()

	if err := processor.Start(ctx); err != nil {
		log.Fatalf("Processor failed: %v", err)
	}
}
