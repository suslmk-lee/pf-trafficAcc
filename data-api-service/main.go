package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

type Accident struct {
	ID         int       `json:"id"`
	AccDate    string    `json:"accDate"`
	AccHour    string    `json:"accHour"`
	AccPointNM string    `json:"accPointNM"`
	RoadNM     string    `json:"roadNM"`
	NosunNM    string    `json:"nosunNM"`
	SmsText    string    `json:"smsText"`
	AccType    string    `json:"accType"`
	Latitude   *float64  `json:"latitude"`
	Altitude   *float64  `json:"altitude"`
	CreatedAt  time.Time `json:"createdAt"`
}

type TollgateTrafficData struct {
	CollectedAt   time.Time `json:"collectedAt"`
	TrafficAmount int       `json:"trafficAmount"`
}

type TollgateTraffic struct {
	UnitCode    string                `json:"unitCode"`
	UnitName    string                `json:"unitName"`
	ExDivName   string                `json:"exDivName"`
	TrafficData []TollgateTrafficData `json:"trafficData"`
	LastUpdated time.Time             `json:"lastUpdated"`
}

type RoadStatus struct {
	RouteNo        string    `json:"routeNo"`
	RouteName      string    `json:"routeName"`
	ConzoneID      string    `json:"conzoneId"`
	ConzoneName    string    `json:"conzoneName"`
	VdsID          string    `json:"vdsId"`
	UpdownTypeCode string    `json:"updownTypeCode"`
	TrafficAmount  int       `json:"trafficAmount"`
	Speed          int       `json:"speed"`
	ShareRatio     int       `json:"shareRatio"`
	TimeAvg        int       `json:"timeAvg"`
	Grade          int       `json:"grade"` // 0:판정불가, 1:원활, 2:서행, 3:정체
	CollectedAt    time.Time `json:"collectedAt"`
}

type RoadRouteSummary struct {
	RouteNo          string    `json:"routeNo"`
	RouteName        string    `json:"routeName"`
	TotalSections    int       `json:"totalSections"`
	SmoothSections   int       `json:"smoothSections"`
	SlowSections     int       `json:"slowSections"`
	CongestedSections int      `json:"congestedSections"`
	AvgSpeed         float64   `json:"avgSpeed"`
	AvgTrafficAmount float64   `json:"avgTrafficAmount"`
	CollectedAt      time.Time `json:"collectedAt"`
}

type Config struct {
	DBHost     string
	DBUser     string
	DBPassword string
	DBName     string
	Port       string
}

type Server struct {
	config Config
	db     *sql.DB
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

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	return Config{
		DBHost:     dbHost,
		DBUser:     dbUser,
		DBPassword: dbPassword,
		DBName:     dbName,
		Port:       port,
	}
}

func NewServer(config Config) (*Server, error) {
	dsn := fmt.Sprintf("%s:%s@tcp(%s)/%s?parseTime=true&loc=Asia%%2FSeoul",
		config.DBUser, config.DBPassword, config.DBHost, config.DBName)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(time.Minute * 5)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := db.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	log.Printf("Connected to MariaDB at %s", config.DBHost)

	return &Server{
		config: config,
		db:     db,
	}, nil
}

func (s *Server) getLatestAccidents(w http.ResponseWriter, r *http.Request) {
	// CORS handled by API Gateway

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Get limit from query parameter (default: 100)
	limit := 100
	if limitStr := r.URL.Query().Get("limit"); limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 1000 {
			limit = l
		}
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	// Only show accidents from the last 24 hours (increased from 3 hours for better visibility)
	twentyFourHoursAgo := time.Now().Add(-24 * time.Hour)

	query := `SELECT id, acc_date, acc_hour, acc_point_nm, road_nm, nosun_nm, sms_text, acc_type,
	                 latitude, altitude, created_at
	          FROM traffic_accidents
	          WHERE created_at >= ?
	          ORDER BY acc_date DESC, acc_hour DESC, created_at DESC
	          LIMIT ?`

	log.Printf("Querying accidents with time threshold: %v", twentyFourHoursAgo)
	rows, err := s.db.QueryContext(ctx, query, twentyFourHoursAgo, limit)
	if err != nil {
		log.Printf("Query error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var accidents []Accident

	for rows.Next() {
		var acc Accident
		err := rows.Scan(
			&acc.ID, &acc.AccDate, &acc.AccHour, &acc.AccPointNM,
			&acc.RoadNM, &acc.NosunNM, &acc.SmsText, &acc.AccType,
			&acc.Latitude, &acc.Altitude, &acc.CreatedAt,
		)
		if err != nil {
			log.Printf("Scan error: %v", err)
			continue
		}
		accidents = append(accidents, acc)
	}

	if err = rows.Err(); err != nil {
		log.Printf("Rows error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(accidents); err != nil {
		log.Printf("Encode error: %v", err)
	} else {
		log.Printf("Returned %d accidents (limit: %d)", len(accidents), limit)
	}
}

func (s *Server) getAccidentStats(w http.ResponseWriter, r *http.Request) {
	// CORS handled by API Gateway

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	type Stats struct {
		TotalAccidents int            `json:"totalAccidents"`
		TodayAccidents int            `json:"todayAccidents"`
		ByType         map[string]int `json:"byType"`
	}

	var stats Stats
	stats.ByType = make(map[string]int)

	now := time.Now()
	today := now.Format("2006-01-02")

	// Total accidents - sum from daily_accident_stats for all dates before today
	// plus today's real-time count
	var totalFromHistory int
	err := s.db.QueryRowContext(ctx,
		"SELECT COALESCE(SUM(accident_count), 0) FROM daily_accident_stats WHERE stat_date < ?",
		today).Scan(&totalFromHistory)
	if err != nil {
		log.Printf("Error getting historical total: %v", err)
	}

	// Today's accidents - real-time count from traffic_accidents
	var todayCount int
	err = s.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM traffic_accidents
		 WHERE created_at >= ? AND created_at < ?`,
		today+" 00:00:00", today+" 23:59:59").Scan(&todayCount)
	if err != nil {
		log.Printf("Error getting today's accidents: %v", err)
	}

	stats.TodayAccidents = todayCount
	stats.TotalAccidents = totalFromHistory + todayCount

	// By type - for last 3 hours (current accidents only)
	threeHoursAgo := now.Add(-3 * time.Hour)
	rows, err := s.db.QueryContext(ctx,
		`SELECT acc_type, COUNT(*) as count
		 FROM traffic_accidents
		 WHERE created_at >= ?
		 GROUP BY acc_type`,
		threeHoursAgo)
	if err != nil {
		log.Printf("Error getting accidents by type: %v", err)
	} else {
		defer rows.Close()
		for rows.Next() {
			var accType string
			var count int
			if err := rows.Scan(&accType, &count); err == nil {
				stats.ByType[accType] = count
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

func (s *Server) getTollgateTraffic(w http.ResponseWriter, r *http.Request) {
	// CORS handled by API Gateway

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	// First, get the most recent collected_at time
	var latestTime sql.NullTime
	err := s.db.QueryRowContext(ctx, `
		SELECT MAX(collected_at) FROM tollgate_traffic_history
	`).Scan(&latestTime)

	if err != nil {
		log.Printf("Error getting latest time: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// If no data exists, return empty array
	if !latestTime.Valid {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode([]TollgateTraffic{})
		return
	}

	// Get traffic data from 3 hours before the latest collection time
	threeHoursBeforeLatest := latestTime.Time.Add(-3 * time.Hour)

	query := `
		SELECT unit_code, unit_name, ex_div_name, collected_at, traffic_amount
		FROM tollgate_traffic_history
		WHERE collected_at >= ?
		ORDER BY unit_code, collected_at DESC`

	rows, err := s.db.QueryContext(ctx, query, threeHoursBeforeLatest)
	if err != nil {
		log.Printf("Query error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	// Group by unit_code
	tollgateMap := make(map[string]*TollgateTraffic)

	for rows.Next() {
		var unitCode, unitName, exDivName string
		var collectedAt time.Time
		var trafficAmount int

		err := rows.Scan(&unitCode, &unitName, &exDivName, &collectedAt, &trafficAmount)
		if err != nil {
			log.Printf("Scan error: %v", err)
			continue
		}

		if _, exists := tollgateMap[unitCode]; !exists {
			tollgateMap[unitCode] = &TollgateTraffic{
				UnitCode:    unitCode,
				UnitName:    unitName,
				ExDivName:   exDivName,
				TrafficData: []TollgateTrafficData{},
				LastUpdated: collectedAt,
			}
		}

		tollgateMap[unitCode].TrafficData = append(tollgateMap[unitCode].TrafficData, TollgateTrafficData{
			CollectedAt:   collectedAt,
			TrafficAmount: trafficAmount,
		})

		if collectedAt.After(tollgateMap[unitCode].LastUpdated) {
			tollgateMap[unitCode].LastUpdated = collectedAt
		}
	}

	if err = rows.Err(); err != nil {
		log.Printf("Rows error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Convert map to slice
	var tollgates []TollgateTraffic
	for _, tg := range tollgateMap {
		tollgates = append(tollgates, *tg)
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(tollgates); err != nil {
		log.Printf("Encode error: %v", err)
	} else {
		log.Printf("Returned %d tollgates with traffic data", len(tollgates))
	}
}

func (s *Server) getRoadStatus(w http.ResponseWriter, r *http.Request) {
	// CORS handled by API Gateway

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()

	// Get the most recent data per route, aggregating by conzone
	// Shows latest available data for each route (no time limit)
	// This ensures all routes are displayed even if external API has gaps
	query := `
		WITH LatestByRoute AS (
			SELECT route_no, MAX(collected_at) as max_collected
			FROM road_traffic_status
			GROUP BY route_no
		)
		SELECT
			r.route_no,
			r.route_name,
			r.conzone_id,
			r.conzone_name,
			MIN(r.vds_id) as vds_id,
			r.updown_type_code,
			ROUND(AVG(CASE WHEN r.traffic_amount >= 0 THEN r.traffic_amount END)) as traffic_amount,
			ROUND(AVG(CASE WHEN r.speed >= 0 THEN r.speed END)) as speed,
			ROUND(AVG(CASE WHEN r.share_ratio >= 0 THEN r.share_ratio END)) as share_ratio,
			ROUND(AVG(CASE WHEN r.time_avg >= 0 THEN r.time_avg END)) as time_avg,
			MAX(r.grade) as grade,
			MAX(r.collected_at) as collected_at
		FROM road_traffic_status r
		INNER JOIN LatestByRoute l ON r.route_no = l.route_no AND r.collected_at = l.max_collected
		WHERE r.speed >= 0 AND r.grade > 0
		GROUP BY r.route_no, r.route_name, r.conzone_id, r.conzone_name, r.updown_type_code
		ORDER BY r.route_no, r.conzone_id`

	rows, err := s.db.QueryContext(ctx, query)
	if err != nil {
		log.Printf("Query error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var roadStatuses []RoadStatus

	for rows.Next() {
		var rs RoadStatus

		err := rows.Scan(
			&rs.RouteNo, &rs.RouteName, &rs.ConzoneID, &rs.ConzoneName,
			&rs.VdsID, &rs.UpdownTypeCode,
			&rs.TrafficAmount, &rs.Speed, &rs.ShareRatio, &rs.TimeAvg,
			&rs.Grade, &rs.CollectedAt,
		)
		if err != nil {
			log.Printf("Scan error: %v", err)
			continue
		}

		roadStatuses = append(roadStatuses, rs)
	}

	if err = rows.Err(); err != nil {
		log.Printf("Rows error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(roadStatuses); err != nil {
		log.Printf("Encode error: %v", err)
	} else {
		log.Printf("Returned %d road status records", len(roadStatuses))
	}
}

func (s *Server) getRoadRouteSummary(w http.ResponseWriter, r *http.Request) {
	// CORS handled by API Gateway

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	// Get the latest aggregated route summary data
	query := `
		SELECT
			route_no,
			route_name,
			total_sections,
			smooth_sections,
			slow_sections,
			congested_sections,
			avg_speed,
			avg_traffic_amount,
			collected_at
		FROM road_route_summary
		WHERE collected_at = (SELECT MAX(collected_at) FROM road_route_summary)
		ORDER BY route_no`

	rows, err := s.db.QueryContext(ctx, query)
	if err != nil {
		log.Printf("Query error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var summaries []RoadRouteSummary

	for rows.Next() {
		var summary RoadRouteSummary

		err := rows.Scan(
			&summary.RouteNo, &summary.RouteName,
			&summary.TotalSections, &summary.SmoothSections,
			&summary.SlowSections, &summary.CongestedSections,
			&summary.AvgSpeed, &summary.AvgTrafficAmount,
			&summary.CollectedAt,
		)
		if err != nil {
			log.Printf("Scan error: %v", err)
			continue
		}

		summaries = append(summaries, summary)
	}

	if err = rows.Err(); err != nil {
		log.Printf("Rows error: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(summaries); err != nil {
		log.Printf("Encode error: %v", err)
	} else {
		log.Printf("Returned %d route summary records", len(summaries))
	}
}

func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	if err := s.db.PingContext(ctx); err != nil {
		log.Printf("Health check failed: %v", err)
		http.Error(w, "Unhealthy", http.StatusServiceUnavailable)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func (s *Server) Start() error {
	http.HandleFunc("/api/accidents/latest", s.getLatestAccidents)
	http.HandleFunc("/api/accidents/stats", s.getAccidentStats)
	http.HandleFunc("/api/tollgate/traffic", s.getTollgateTraffic)
	http.HandleFunc("/api/road/status", s.getRoadStatus)
	http.HandleFunc("/api/road/summary", s.getRoadRouteSummary)
	http.HandleFunc("/health", s.healthHandler)

	addr := ":" + s.config.Port
	log.Printf("Data API Service starting on %s", addr)

	return http.ListenAndServe(addr, nil)
}

func (s *Server) Close() error {
	return s.db.Close()
}

func main() {
	config := loadConfig()

	log.Printf("Configuration:")
	log.Printf("  DB Host: %s", config.DBHost)
	log.Printf("  DB Name: %s", config.DBName)
	log.Printf("  Port: %s", config.Port)

	server, err := NewServer(config)
	if err != nil {
		log.Fatalf("Failed to create server: %v", err)
	}
	defer server.Close()

	if err := server.Start(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
