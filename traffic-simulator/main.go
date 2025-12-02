package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

type RealTimeSMS struct {
	AccDate    string  `json:"accDate"`
	AccHour    string  `json:"accHour"`
	AccPointNM string  `json:"accPointNM"`
	LinkID     string  `json:"linkId"`
	AccInfo    string  `json:"smsText"`  // Match real API field name
	AccType    string  `json:"accType"`
	Latitude   float64 `json:"latitude"` // Match real API type
	Longitude  float64 `json:"altitude"` // Match real API field name (altitude = longitude)
	RoadNM     string  `json:"roadNM"`
	NosunNM    string  `json:"nosunNM"`
}

type Response struct {
	RealTimeSMSList []RealTimeSMS `json:"realTimeSMSList"`
}

type Config struct {
	DBHost     string
	DBUser     string
	DBPassword string
	DBName     string
	Port       string
}

type Simulator struct {
	config              Config
	db                  *sql.DB
	rand                *rand.Rand
	currentTarget       int       // Current 5-minute target
	currentCount        int       // How many generated in current 5-min window
	windowStartTime     time.Time // When current 5-min window started
}

func loadConfig() Config {
	dbHost := os.Getenv("DB_HOST")
	if dbHost == "" {
		dbHost = "localhost:3306"
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

	port := os.Getenv("PORT")
	if port == "" {
		port = "8083"
	}

	return Config{
		DBHost:     dbHost,
		DBUser:     dbUser,
		DBPassword: dbPassword,
		DBName:     dbName,
		Port:       port,
	}
}

func NewSimulator(config Config) (*Simulator, error) {
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

	simulator := &Simulator{
		config:          config,
		db:              db,
		rand:            rand.New(rand.NewSource(time.Now().UnixNano())),
		windowStartTime: time.Now(),
	}

	// Set initial target
	simulator.setNewTarget()

	return simulator, nil
}

// setNewTarget sets a new 5-minute target based on realistic patterns
// Weighted towards 2-4 accidents per 5 minutes (most common)
func (s *Simulator) setNewTarget() {
	// Weighted array: 2-4 are most common, 5-7 less common
	weights := []int{2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 5, 5, 6, 7}
	s.currentTarget = weights[s.rand.Intn(len(weights))]
	s.currentCount = 0
	s.windowStartTime = time.Now()
	log.Printf("New 5-minute window: target %d accidents", s.currentTarget)
}

// getRemainingCount calculates how many accidents to generate in this call
func (s *Simulator) getRemainingCount() int {
	// Check if 5 minutes passed
	elapsed := time.Since(s.windowStartTime)
	if elapsed >= 5*time.Minute {
		s.setNewTarget()
	}

	// Calculate how many are left to reach target
	remaining := s.currentTarget - s.currentCount
	if remaining <= 0 {
		return 0
	}

	// Called every 30 seconds, 10 times per 5 minutes
	// Distribute remaining evenly over remaining calls
	secondsElapsed := int(elapsed.Seconds())
	callsElapsed := secondsElapsed / 30
	totalCalls := 10 // 5 minutes / 30 seconds
	callsRemaining := totalCalls - callsElapsed

	if callsRemaining <= 0 {
		return remaining // Give all remaining if this is last call
	}

	// Average distribution with some randomness
	avgPerCall := (remaining + callsRemaining - 1) / callsRemaining
	if avgPerCall == 0 {
		return 0
	}

	// Add randomness: ±1 from average, but not negative or more than remaining
	variance := s.rand.Intn(3) - 1 // -1, 0, or 1
	count := avgPerCall + variance

	if count < 0 {
		count = 0
	}
	if count > remaining {
		count = remaining
	}

	return count
}

func (s *Simulator) getRandomAccidents(count int) ([]RealTimeSMS, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Get random accidents from seed data
	query := `
		SELECT acc_point_nm, sms_text, acc_type, latitude, altitude, road_nm, nosun_nm
		FROM simulator_seed_data
		ORDER BY RAND()
		LIMIT ?
	`

	rows, err := s.db.QueryContext(ctx, query, count)
	if err != nil {
		return nil, fmt.Errorf("failed to query seed data: %w", err)
	}
	defer rows.Close()

	now := time.Now()
	accDate := now.Format("2006.01.02") // YYYY.MM.DD format
	accHour := now.Format("15:04:05")   // HH:MM:SS format

	var accidents []RealTimeSMS
	for rows.Next() {
		var acc RealTimeSMS
		var lat, lon sql.NullFloat64
		var nosunNM sql.NullString

		err := rows.Scan(&acc.AccPointNM, &acc.AccInfo, &acc.AccType, &lat, &lon, &acc.RoadNM, &nosunNM)
		if err != nil {
			log.Printf("Error scanning row: %v", err)
			continue
		}

		// Set current date and time (all accidents use current time)
		acc.AccDate = accDate
		acc.AccHour = accHour

		// Set location (with null handling)
		if lat.Valid {
			acc.Latitude = lat.Float64
		}
		if lon.Valid {
			acc.Longitude = lon.Float64
		}
		if nosunNM.Valid {
			acc.NosunNM = nosunNM.String
		}

		// Generate random link ID
		acc.LinkID = fmt.Sprintf("LINK%05d", s.rand.Intn(99999))

		accidents = append(accidents, acc)
	}

	return accidents, nil
}

func (s *Simulator) trafficHandler(w http.ResponseWriter, r *http.Request) {
	// Enable CORS
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	w.Header().Set("Content-Type", "application/json")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	// Use intelligent distribution based on 5-minute windows
	count := s.getRemainingCount()

	accidents, err := s.getRandomAccidents(count)
	if err != nil {
		log.Printf("Error getting random accidents: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Update count
	s.currentCount += len(accidents)

	response := Response{
		RealTimeSMSList: accidents,
	}

	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding response: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	log.Printf("Generated %d accidents (window: %d/%d)", len(accidents), s.currentCount, s.currentTarget)
}

func (s *Simulator) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func (s *Simulator) Start() error {
	http.HandleFunc("/api/traffic", s.trafficHandler)
	http.HandleFunc("/health", s.healthHandler)

	addr := ":" + s.config.Port
	log.Printf("Traffic Simulator starting on %s", addr)
	log.Printf("Generating 1-3 accidents per call (targeting 8-12 per 5 minutes)")

	return http.ListenAndServe(addr, nil)
}

func (s *Simulator) Close() error {
	return s.db.Close()
}

func main() {
	config := loadConfig()

	log.Printf("Configuration:")
	log.Printf("  DB Host: %s", config.DBHost)
	log.Printf("  DB Name: %s", config.DBName)
	log.Printf("  Port: %s", config.Port)

	simulator, err := NewSimulator(config)
	if err != nil {
		log.Fatalf("Failed to create simulator: %v", err)
	}
	defer simulator.Close()

	if err := simulator.Start(); err != nil {
		log.Fatalf("Simulator failed: %v", err)
	}
}
