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

// Traffic Accident structures
type TrafficAccident struct {
	LaneYn1          string   `json:"laneYn1"`
	LaneYn2          string   `json:"laneYn2"`
	LaneYn3          string   `json:"laneYn3"`
	LaneYn4          string   `json:"laneYn4"`
	LaneYn5          string   `json:"laneYn5"`
	LaneYn6          string   `json:"laneYn6"`
	LateLength       *string  `json:"lateLength"`
	AccHour          string   `json:"accHour"`
	AccDate          string   `json:"accDate"`
	AccTypeCode      string   `json:"accTypeCode"`
	AccType          string   `json:"accType"`
	StartEndTypeCode string   `json:"startEndTypeCode"`
	SmsText          string   `json:"smsText"`
	AccProcessCode   string   `json:"accProcessCode"`
	AccPointNM       string   `json:"accPointNM"`
	NosunNM          string   `json:"nosunNM"`
	RoadNM           string   `json:"roadNM"`
	AccProcessNM     string   `json:"accProcessNM"`
	Latitude         *float64 `json:"latitude"`
	Altitude         *float64 `json:"altitude"`
	SeriesNM         int      `json:"seriesNM"`
	ShldroadYn       string   `json:"shldroadYn"`
	Message          *string  `json:"message"`
	Code             *string  `json:"code"`
}

type AccidentAPIResponse struct {
	Count           int               `json:"count"`
	PageNo          int               `json:"pageNo"`
	NumOfRows       int               `json:"numOfRows"`
	PageSize        int               `json:"pageSize"`
	RealTimeSMSList []TrafficAccident `json:"realTimeSMSList"`
	Message         string            `json:"message"`
	Code            string            `json:"code"`
}

// Tollgate Traffic structures
type TollgateTraffic struct {
	ExDivCode     string `json:"exDivCode"`
	ExDivName     string `json:"exDivName"`
	UnitCode      string `json:"unitCode"`
	UnitName      string `json:"unitName"`
	InoutType     string `json:"inoutType"`
	InoutName     string `json:"inoutName"`
	TmType        string `json:"tmType"`
	TmName        string `json:"tmName"`
	TcsType       string `json:"tcsType"`
	TcsName       string `json:"tcsName"`
	CarType       string `json:"carType"`
	TrafficAmount string `json:"trafficAmout"` // Note: API typo
	SumDate       string `json:"sumDate"`
	SumTm         string `json:"sumTm"`
}

type TollgateAPIResponse struct {
	Code      string            `json:"code"`
	Message   string            `json:"message"`
	Count     int               `json:"count"`
	PageNo    int               `json:"pageNo"`
	NumOfRows int               `json:"numOfRows"`
	PageSize  int               `json:"pageSize"`
	TrafficIc []TollgateTraffic `json:"trafficIc"`
}

// Road Traffic Status structures
type RoadTrafficStatus struct {
	RouteNo        string `json:"routeNo"`
	RouteName      string `json:"routeName"`
	ConzoneID      string `json:"conzoneId"`
	ConzoneName    string `json:"conzoneName"`
	VdsID          string `json:"vdsId"`
	UpdownTypeCode string `json:"updownTypeCode"`
	TrafficAmount  string `json:"trafficAmout"` // Note: API typo
	Speed          string `json:"speed"`
	ShareRatio     string `json:"shareRatio"`
	TimeAvg        string `json:"timeAvg"`
	Grade          string `json:"grade"`
	StdDate        string `json:"stdDate"`
	StdHour        string `json:"stdHour"`
}

type RoadStatusAPIResponse struct {
	Code    string              `json:"code"`
	Message string              `json:"message"`
	Count   int                 `json:"count"`
	List    []RoadTrafficStatus `json:"list"`
}

type Config struct {
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	ServerPort string
}

type ProxyAPI struct {
	config Config
	db     *sql.DB
}

func loadConfig() Config {
	dbHost := os.Getenv("DB_HOST")
	if dbHost == "" {
		dbHost = "localhost"
	}

	dbPort := os.Getenv("DB_PORT")
	if dbPort == "" {
		dbPort = "3306"
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

	serverPort := os.Getenv("SERVER_PORT")
	if serverPort == "" {
		serverPort = "8080"
	}

	return Config{
		DBHost:     dbHost,
		DBPort:     dbPort,
		DBUser:     dbUser,
		DBPassword: dbPassword,
		DBName:     dbName,
		ServerPort: serverPort,
	}
}

func NewProxyAPI(config Config) (*ProxyAPI, error) {
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&charset=utf8mb4",
		config.DBUser, config.DBPassword, config.DBHost, config.DBPort, config.DBName)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(time.Hour)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := db.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	log.Printf("Connected to database at %s:%s/%s", config.DBHost, config.DBPort, config.DBName)

	return &ProxyAPI{
		config: config,
		db:     db,
	}, nil
}

// Traffic Accident handlers
func (p *ProxyAPI) getAccidents(ctx context.Context, numOfRows, pageNo int, sortType string) ([]TrafficAccident, int, error) {
	// Get total count
	var totalCount int
	countQuery := "SELECT COUNT(*) FROM traffic_accidents_cache"
	if err := p.db.QueryRowContext(ctx, countQuery).Scan(&totalCount); err != nil {
		return nil, 0, fmt.Errorf("failed to get count: %w", err)
	}

	// Build query with pagination and sorting
	query := `
		SELECT
			lane_yn1, lane_yn2, lane_yn3, lane_yn4, lane_yn5, lane_yn6,
			late_length, acc_hour, acc_date, acc_type_code, acc_type,
			start_end_type_code, sms_text, acc_process_code, acc_point_nm,
			nosun_nm, road_nm, acc_process_nm, latitude, altitude,
			series_nm, shldr_road_yn
		FROM traffic_accidents_cache
	`

	// Add sorting
	if sortType == "desc" {
		query += " ORDER BY collected_at DESC, id DESC"
	} else {
		query += " ORDER BY collected_at ASC, id ASC"
	}

	// Add pagination
	offset := (pageNo - 1) * numOfRows
	query += fmt.Sprintf(" LIMIT %d OFFSET %d", numOfRows, offset)

	rows, err := p.db.QueryContext(ctx, query)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to query accidents: %w", err)
	}
	defer rows.Close()

	var accidents []TrafficAccident
	seriesNum := 1

	for rows.Next() {
		var acc TrafficAccident
		err := rows.Scan(
			&acc.LaneYn1, &acc.LaneYn2, &acc.LaneYn3, &acc.LaneYn4, &acc.LaneYn5, &acc.LaneYn6,
			&acc.LateLength, &acc.AccHour, &acc.AccDate, &acc.AccTypeCode, &acc.AccType,
			&acc.StartEndTypeCode, &acc.SmsText, &acc.AccProcessCode, &acc.AccPointNM,
			&acc.NosunNM, &acc.RoadNM, &acc.AccProcessNM, &acc.Latitude, &acc.Altitude,
			&acc.SeriesNM, &acc.ShldroadYn,
		)
		if err != nil {
			log.Printf("Failed to scan accident: %v", err)
			continue
		}

		// Override series number for response
		acc.SeriesNM = seriesNum
		seriesNum++

		accidents = append(accidents, acc)
	}

	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("error iterating rows: %w", err)
	}

	return accidents, totalCount, nil
}

func (p *ProxyAPI) handleRealTimeSMS(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// Parse query parameters
	query := r.URL.Query()

	// API key (ignored for now, but could be validated)
	_ = query.Get("key")

	// Response type (only support json)
	responseType := query.Get("type")
	if responseType == "" {
		responseType = "json"
	}

	// Number of rows
	numOfRows := 100
	if numStr := query.Get("numOfRows"); numStr != "" {
		if num, err := strconv.Atoi(numStr); err == nil && num > 0 {
			numOfRows = num
		}
	}

	// Page number
	pageNo := 1
	if pageStr := query.Get("pageNo"); pageStr != "" {
		if page, err := strconv.Atoi(pageStr); err == nil && page > 0 {
			pageNo = page
		}
	}

	// Sort type
	sortType := query.Get("sortType")
	if sortType == "" {
		sortType = "desc"
	}

	// Get accidents from database
	accidents, totalCount, err := p.getAccidents(ctx, numOfRows, pageNo, sortType)
	if err != nil {
		log.Printf("[Accident] Failed to get accidents: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Calculate page size
	pageSize := (totalCount + numOfRows - 1) / numOfRows
	if pageSize == 0 {
		pageSize = 1
	}

	// Build response
	response := AccidentAPIResponse{
		Count:           totalCount,
		PageNo:          pageNo,
		NumOfRows:       numOfRows,
		PageSize:        pageSize,
		RealTimeSMSList: accidents,
		Message:         "인증키가 유효합니다.",
		Code:            "SUCCESS",
	}

	// Set headers
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)

	// Encode response
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("[Accident] Failed to encode response: %v", err)
	}

	log.Printf("[Accident] Served %d accidents (page %d/%d, total %d)", len(accidents), pageNo, pageSize, totalCount)
}

// Tollgate Traffic handlers
func (p *ProxyAPI) getTollgate(ctx context.Context, tmType, carType, inoutType, tcsType string, numOfRows, pageNo int) ([]TollgateTraffic, int, error) {
	// Build WHERE clause
	where := "WHERE 1=1"
	args := []interface{}{}

	if tmType != "" {
		where += " AND tm_type = ?"
		args = append(args, tmType)
	}
	if carType != "" {
		where += " AND car_type = ?"
		args = append(args, carType)
	}
	if inoutType != "" {
		where += " AND inout_type = ?"
		args = append(args, inoutType)
	}
	if tcsType != "" {
		where += " AND tcs_type = ?"
		args = append(args, tcsType)
	}

	// Get total count
	var totalCount int
	countQuery := "SELECT COUNT(*) FROM tollgate_traffic_cache " + where
	if err := p.db.QueryRowContext(ctx, countQuery, args...).Scan(&totalCount); err != nil {
		return nil, 0, fmt.Errorf("failed to get count: %w", err)
	}

	// Build query with pagination
	query := `
		SELECT
			ex_div_code, ex_div_name, unit_code, unit_name, inout_type, inout_name,
			tm_type, tm_name, tcs_type, tcs_name, car_type, traffic_amount,
			sum_date, sum_tm
		FROM tollgate_traffic_cache
		` + where + `
		ORDER BY collected_at DESC, id DESC
		LIMIT ? OFFSET ?
	`

	offset := (pageNo - 1) * numOfRows
	queryArgs := append(args, numOfRows, offset)

	rows, err := p.db.QueryContext(ctx, query, queryArgs...)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to query tollgate: %w", err)
	}
	defer rows.Close()

	var traffic []TollgateTraffic

	for rows.Next() {
		var t TollgateTraffic
		err := rows.Scan(
			&t.ExDivCode, &t.ExDivName, &t.UnitCode, &t.UnitName, &t.InoutType, &t.InoutName,
			&t.TmType, &t.TmName, &t.TcsType, &t.TcsName, &t.CarType, &t.TrafficAmount,
			&t.SumDate, &t.SumTm,
		)
		if err != nil {
			log.Printf("[Tollgate] Failed to scan: %v", err)
			continue
		}

		traffic = append(traffic, t)
	}

	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("error iterating rows: %w", err)
	}

	return traffic, totalCount, nil
}

func (p *ProxyAPI) handleTollgateTraffic(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// Parse query parameters
	query := r.URL.Query()

	tmType := query.Get("tmType")
	carType := query.Get("carType")
	inoutType := query.Get("inoutType")
	tcsType := query.Get("tcsType")

	// Number of rows
	numOfRows := 100
	if numStr := query.Get("numOfRows"); numStr != "" {
		if num, err := strconv.Atoi(numStr); err == nil && num > 0 {
			numOfRows = num
		}
	}

	// Page number
	pageNo := 1
	if pageStr := query.Get("pageNo"); pageStr != "" {
		if page, err := strconv.Atoi(pageStr); err == nil && page > 0 {
			pageNo = page
		}
	}

	// Get tollgate data from database
	traffic, totalCount, err := p.getTollgate(ctx, tmType, carType, inoutType, tcsType, numOfRows, pageNo)
	if err != nil {
		log.Printf("[Tollgate] Failed to get data: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Calculate page size
	pageSize := (totalCount + numOfRows - 1) / numOfRows
	if pageSize == 0 {
		pageSize = 1
	}

	// Build response
	response := TollgateAPIResponse{
		Code:      "SUCCESS",
		Message:   "인증키가 유효합니다.",
		Count:     totalCount,
		PageNo:    pageNo,
		NumOfRows: numOfRows,
		PageSize:  pageSize,
		TrafficIc: traffic,
	}

	// Set headers
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)

	// Encode response
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("[Tollgate] Failed to encode response: %v", err)
	}

	log.Printf("[Tollgate] Served %d records (page %d/%d, total %d)", len(traffic), pageNo, pageSize, totalCount)
}

// Road Traffic Status handlers
func (p *ProxyAPI) getRoadStatus(ctx context.Context) ([]RoadTrafficStatus, int, error) {
	// Get latest collected_at time
	var latestTime time.Time
	timeQuery := "SELECT MAX(collected_at) FROM road_traffic_status_cache"
	if err := p.db.QueryRowContext(ctx, timeQuery).Scan(&latestTime); err != nil {
		return nil, 0, fmt.Errorf("failed to get latest time: %w", err)
	}

	// Get all data from latest collection
	query := `
		SELECT
			route_no, route_name, conzone_id, conzone_name, vds_id, updown_type_code,
			traffic_amount, speed, share_ratio, time_avg, grade, std_date, std_hour
		FROM road_traffic_status_cache
		WHERE collected_at = ?
		ORDER BY route_no, vds_id
	`

	rows, err := p.db.QueryContext(ctx, query, latestTime)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to query road status: %w", err)
	}
	defer rows.Close()

	var statusList []RoadTrafficStatus

	for rows.Next() {
		var status RoadTrafficStatus
		err := rows.Scan(
			&status.RouteNo, &status.RouteName, &status.ConzoneID, &status.ConzoneName,
			&status.VdsID, &status.UpdownTypeCode,
			&status.TrafficAmount, &status.Speed, &status.ShareRatio, &status.TimeAvg, &status.Grade,
			&status.StdDate, &status.StdHour,
		)
		if err != nil {
			log.Printf("[RoadStatus] Failed to scan: %v", err)
			continue
		}

		statusList = append(statusList, status)
	}

	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("error iterating rows: %w", err)
	}

	return statusList, len(statusList), nil
}

func (p *ProxyAPI) handleRoadStatus(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// Get road status data from database
	statusList, totalCount, err := p.getRoadStatus(ctx)
	if err != nil {
		log.Printf("[RoadStatus] Failed to get data: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Build response
	response := RoadStatusAPIResponse{
		Code:    "SUCCESS",
		Message: "인증키가 유효합니다.",
		Count:   totalCount,
		List:    statusList,
	}

	// Set headers
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)

	// Encode response
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("[RoadStatus] Failed to encode response: %v", err)
	}

	log.Printf("[RoadStatus] Served %d records", len(statusList))
}

// Health check handler
func (p *ProxyAPI) healthHandler(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	if err := p.db.PingContext(ctx); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"status": "unhealthy", "error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func (p *ProxyAPI) Start() error {
	mux := http.NewServeMux()

	// OpenAPI endpoints
	mux.HandleFunc("/openapi/burstInfo/realTimeSms", p.handleRealTimeSMS)
	mux.HandleFunc("/openapi/trafficapi/trafficIc", p.handleTollgateTraffic)
	mux.HandleFunc("/openapi/odtraffic/trafficAmountByRealtime", p.handleRoadStatus)

	// Health check endpoint
	mux.HandleFunc("/health", p.healthHandler)

	addr := ":" + p.config.ServerPort
	log.Printf("Starting OpenAPI Proxy Server v2.0")
	log.Printf("  - Traffic Accident API: /openapi/burstInfo/realTimeSms")
	log.Printf("  - Tollgate Traffic API: /openapi/trafficapi/trafficIc")
	log.Printf("  - Road Status API: /openapi/odtraffic/trafficAmountByRealtime")
	log.Printf("Listening on %s", addr)

	server := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	return server.ListenAndServe()
}

func (p *ProxyAPI) Close() error {
	return p.db.Close()
}

func main() {
	config := loadConfig()

	log.Printf("========================================")
	log.Printf("OpenAPI Proxy Server v2.0")
	log.Printf("========================================")
	log.Printf("Database: %s:%s/%s", config.DBHost, config.DBPort, config.DBName)
	log.Printf("Server Port: %s", config.ServerPort)
	log.Printf("========================================")

	api, err := NewProxyAPI(config)
	if err != nil {
		log.Fatalf("Failed to create proxy API: %v", err)
	}
	defer api.Close()

	if err := api.Start(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
