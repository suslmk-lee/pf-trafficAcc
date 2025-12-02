package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/joho/godotenv"
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
	// Common
	APIKey  string
	DBHost  string
	DBPort  string
	DBUser  string
	DBPassword string
	DBName  string

	// API URLs
	AccidentAPIURL     string
	TollgateAPIURL     string
	RoadStatusAPIURL   string

	// Collection intervals
	AccidentInterval   time.Duration
	TollgateInterval   time.Duration
	RoadStatusInterval time.Duration
}

type Collector struct {
	config     Config
	db         *sql.DB
	httpClient *http.Client
}

func loadConfig() Config {
	apiKey := os.Getenv("OPENAPI_KEY")
	if apiKey == "" {
		apiKey = "8771969304"
	}

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

	accidentAPIURL := os.Getenv("ACCIDENT_API_URL")
	if accidentAPIURL == "" {
		accidentAPIURL = "https://data.ex.co.kr/openapi/burstInfo/realTimeSms"
	}

	tollgateAPIURL := os.Getenv("TOLLGATE_API_URL")
	if tollgateAPIURL == "" {
		tollgateAPIURL = "https://data.ex.co.kr/openapi/trafficapi/trafficIc"
	}

	roadStatusAPIURL := os.Getenv("ROAD_STATUS_API_URL")
	if roadStatusAPIURL == "" {
		roadStatusAPIURL = "https://data.ex.co.kr/openapi/odtraffic/trafficAmountByRealtime"
	}

	accidentInterval := 5 * time.Minute
	if env := os.Getenv("ACCIDENT_INTERVAL"); env != "" {
		if d, err := time.ParseDuration(env); err == nil {
			accidentInterval = d
		}
	}

	tollgateInterval := 15 * time.Minute
	if env := os.Getenv("TOLLGATE_INTERVAL"); env != "" {
		if d, err := time.ParseDuration(env); err == nil {
			tollgateInterval = d
		}
	}

	roadStatusInterval := 5 * time.Minute
	if env := os.Getenv("ROAD_STATUS_INTERVAL"); env != "" {
		if d, err := time.ParseDuration(env); err == nil {
			roadStatusInterval = d
		}
	}

	return Config{
		APIKey:             apiKey,
		DBHost:             dbHost,
		DBPort:             dbPort,
		DBUser:             dbUser,
		DBPassword:         dbPassword,
		DBName:             dbName,
		AccidentAPIURL:     accidentAPIURL,
		TollgateAPIURL:     tollgateAPIURL,
		RoadStatusAPIURL:   roadStatusAPIURL,
		AccidentInterval:   accidentInterval,
		TollgateInterval:   tollgateInterval,
		RoadStatusInterval: roadStatusInterval,
	}
}

func NewCollector(config Config) (*Collector, error) {
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&charset=utf8mb4",
		config.DBUser, config.DBPassword, config.DBHost, config.DBPort, config.DBName)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(time.Hour)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := db.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	log.Printf("Connected to database at %s:%s/%s", config.DBHost, config.DBPort, config.DBName)

	return &Collector{
		config: config,
		db:     db,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}, nil
}

// Traffic Accident Collection
func (c *Collector) fetchAccidents(ctx context.Context) (*AccidentAPIResponse, error) {
	url := fmt.Sprintf("%s?key=%s&type=json&numOfRows=1000&pageNo=1&sortType=desc&pagingYn=Y",
		c.config.AccidentAPIURL, c.config.APIKey)

	log.Printf("[Accident] Fetching from: %s", url)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch data: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(body))
	}

	var apiResp AccidentAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &apiResp, nil
}

func (c *Collector) saveAccidentsToCache(ctx context.Context, accidents []TrafficAccident) error {
	if len(accidents) == 0 {
		return nil
	}

	query := `INSERT INTO traffic_accidents_cache (
		lane_yn1, lane_yn2, lane_yn3, lane_yn4, lane_yn5, lane_yn6,
		late_length, acc_hour, acc_date, acc_type_code, acc_type,
		start_end_type_code, sms_text, acc_process_code, acc_point_nm,
		nosun_nm, road_nm, acc_process_nm, latitude, altitude,
		series_nm, shldr_road_yn, collected_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	ON DUPLICATE KEY UPDATE
		lane_yn1 = VALUES(lane_yn1),
		lane_yn2 = VALUES(lane_yn2),
		lane_yn3 = VALUES(lane_yn3),
		lane_yn4 = VALUES(lane_yn4),
		lane_yn5 = VALUES(lane_yn5),
		lane_yn6 = VALUES(lane_yn6),
		late_length = VALUES(late_length),
		acc_type_code = VALUES(acc_type_code),
		acc_type = VALUES(acc_type),
		start_end_type_code = VALUES(start_end_type_code),
		acc_process_code = VALUES(acc_process_code),
		acc_point_nm = VALUES(acc_point_nm),
		acc_process_nm = VALUES(acc_process_nm),
		latitude = VALUES(latitude),
		altitude = VALUES(altitude),
		series_nm = VALUES(series_nm),
		shldr_road_yn = VALUES(shldr_road_yn),
		collected_at = VALUES(collected_at),
		created_at = CURRENT_TIMESTAMP`

	tx, err := c.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	stmt, err := tx.PrepareContext(ctx, query)
	if err != nil {
		return fmt.Errorf("failed to prepare statement: %w", err)
	}
	defer stmt.Close()

	collectedAt := time.Now()
	saved := 0

	for _, acc := range accidents {
		_, err := stmt.ExecContext(ctx,
			acc.LaneYn1, acc.LaneYn2, acc.LaneYn3, acc.LaneYn4, acc.LaneYn5, acc.LaneYn6,
			acc.LateLength, acc.AccHour, acc.AccDate, acc.AccTypeCode, acc.AccType,
			acc.StartEndTypeCode, acc.SmsText, acc.AccProcessCode, acc.AccPointNM,
			acc.NosunNM, acc.RoadNM, acc.AccProcessNM, acc.Latitude, acc.Altitude,
			acc.SeriesNM, acc.ShldroadYn, collectedAt,
		)
		if err != nil {
			log.Printf("[Accident] Failed to save: %v", err)
			continue
		}
		saved++
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	log.Printf("[Accident] Saved %d/%d records to cache", saved, len(accidents))
	return nil
}

func (c *Collector) collectAccidents(ctx context.Context) error {
	data, err := c.fetchAccidents(ctx)
	if err != nil {
		return fmt.Errorf("fetch failed: %w", err)
	}

	log.Printf("[Accident] Fetched %d records", len(data.RealTimeSMSList))

	if err := c.saveAccidentsToCache(ctx, data.RealTimeSMSList); err != nil {
		return fmt.Errorf("save failed: %w", err)
	}

	return nil
}

// Tollgate Traffic Collection
func (c *Collector) fetchTollgate(ctx context.Context, pageNo int) (*TollgateAPIResponse, error) {
	url := fmt.Sprintf("%s?key=%s&type=json&tmType=2&numOfRows=100&pageNo=%d&carType=1&inoutType=0&tcsType=2",
		c.config.TollgateAPIURL, c.config.APIKey, pageNo)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch data: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(body))
	}

	var apiResp TollgateAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &apiResp, nil
}

func (c *Collector) saveTollgateToCache(ctx context.Context, traffic []TollgateTraffic) error {
	if len(traffic) == 0 {
		return nil
	}

	query := `INSERT INTO tollgate_traffic_cache (
		ex_div_code, ex_div_name, unit_code, unit_name, inout_type, inout_name,
		tm_type, tm_name, tcs_type, tcs_name, car_type, traffic_amount,
		sum_date, sum_tm, collected_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	ON DUPLICATE KEY UPDATE
		traffic_amount = VALUES(traffic_amount),
		collected_at = VALUES(collected_at),
		created_at = CURRENT_TIMESTAMP`

	tx, err := c.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	stmt, err := tx.PrepareContext(ctx, query)
	if err != nil {
		return fmt.Errorf("failed to prepare statement: %w", err)
	}
	defer stmt.Close()

	loc, _ := time.LoadLocation("Asia/Seoul")
	saved := 0

	for _, t := range traffic {
		collectedAt, err := time.ParseInLocation("20060102 1504", t.SumDate+" "+t.SumTm, loc)
		if err != nil {
			log.Printf("[Tollgate] Failed to parse time: %v", err)
			continue
		}

		trafficAmount := t.TrafficAmount
		if trafficAmount == "" {
			trafficAmount = "0"
		}

		_, err = stmt.ExecContext(ctx,
			t.ExDivCode, t.ExDivName, t.UnitCode, t.UnitName, t.InoutType, t.InoutName,
			t.TmType, t.TmName, t.TcsType, t.TcsName, t.CarType, trafficAmount,
			t.SumDate, t.SumTm, collectedAt,
		)
		if err != nil {
			log.Printf("[Tollgate] Failed to save: %v", err)
			continue
		}
		saved++
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	log.Printf("[Tollgate] Saved %d/%d records to cache", saved, len(traffic))
	return nil
}

func (c *Collector) collectTollgate(ctx context.Context) error {
	log.Printf("[Tollgate] Starting collection...")

	// Fetch first page to get total count
	firstPage, err := c.fetchTollgate(ctx, 1)
	if err != nil {
		return fmt.Errorf("failed to fetch first page: %w", err)
	}

	if firstPage.Code != "SUCCESS" {
		return fmt.Errorf("API error: %s - %s", firstPage.Code, firstPage.Message)
	}

	log.Printf("[Tollgate] Total %d records, %d pages", firstPage.Count, firstPage.PageSize)

	totalSaved := 0

	// Process all pages
	for pageNo := 1; pageNo <= firstPage.PageSize; pageNo++ {
		var pageData *TollgateAPIResponse

		if pageNo == 1 {
			pageData = firstPage
		} else {
			pageData, err = c.fetchTollgate(ctx, pageNo)
			if err != nil {
				log.Printf("[Tollgate] Failed to fetch page %d: %v", pageNo, err)
				continue
			}
		}

		if err := c.saveTollgateToCache(ctx, pageData.TrafficIc); err != nil {
			log.Printf("[Tollgate] Failed to save page %d: %v", pageNo, err)
			continue
		}

		totalSaved += len(pageData.TrafficIc)

		if pageNo%10 == 0 || pageNo == firstPage.PageSize {
			log.Printf("[Tollgate] Progress: %d/%d pages, %d records saved", pageNo, firstPage.PageSize, totalSaved)
		}
	}

	log.Printf("[Tollgate] Collection completed: %d total records saved", totalSaved)
	return nil
}

// Road Status Collection
func (c *Collector) fetchRoadStatus(ctx context.Context) (*RoadStatusAPIResponse, error) {
	url := fmt.Sprintf("%s?key=%s&type=json", c.config.RoadStatusAPIURL, c.config.APIKey)

	log.Printf("[RoadStatus] Fetching from: %s", url)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch data: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(body))
	}

	var apiResp RoadStatusAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &apiResp, nil
}

func (c *Collector) saveRoadStatusToCache(ctx context.Context, statusList []RoadTrafficStatus) error {
	if len(statusList) == 0 {
		return nil
	}

	query := `INSERT INTO road_traffic_status_cache (
		route_no, route_name, conzone_id, conzone_name, vds_id, updown_type_code,
		traffic_amount, speed, share_ratio, time_avg, grade, std_date, std_hour, collected_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	ON DUPLICATE KEY UPDATE
		traffic_amount = VALUES(traffic_amount),
		speed = VALUES(speed),
		share_ratio = VALUES(share_ratio),
		time_avg = VALUES(time_avg),
		grade = VALUES(grade),
		collected_at = VALUES(collected_at),
		created_at = CURRENT_TIMESTAMP`

	tx, err := c.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	stmt, err := tx.PrepareContext(ctx, query)
	if err != nil {
		return fmt.Errorf("failed to prepare statement: %w", err)
	}
	defer stmt.Close()

	loc, _ := time.LoadLocation("Asia/Seoul")
	saved := 0

	for _, status := range statusList {
		collectedAt, err := time.ParseInLocation("20060102 1504", status.StdDate+" "+status.StdHour, loc)
		if err != nil {
			log.Printf("[RoadStatus] Failed to parse time: %v", err)
			continue
		}

		// Handle empty values
		trafficAmount := status.TrafficAmount
		if trafficAmount == "" {
			trafficAmount = "0"
		}
		speed := status.Speed
		if speed == "" {
			speed = "0"
		}
		shareRatio := status.ShareRatio
		if shareRatio == "" {
			shareRatio = "0"
		}
		timeAvg := status.TimeAvg
		if timeAvg == "" {
			timeAvg = "0"
		}
		grade := status.Grade
		if grade == "" {
			grade = "0"
		}

		_, err = stmt.ExecContext(ctx,
			status.RouteNo, status.RouteName, status.ConzoneID, status.ConzoneName,
			status.VdsID, status.UpdownTypeCode,
			trafficAmount, speed, shareRatio, timeAvg, grade,
			status.StdDate, status.StdHour, collectedAt,
		)
		if err != nil {
			log.Printf("[RoadStatus] Failed to save: %v", err)
			continue
		}
		saved++
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	log.Printf("[RoadStatus] Saved %d/%d records to cache", saved, len(statusList))
	return nil
}

func (c *Collector) collectRoadStatus(ctx context.Context) error {
	data, err := c.fetchRoadStatus(ctx)
	if err != nil {
		return fmt.Errorf("fetch failed: %w", err)
	}

	log.Printf("[RoadStatus] Fetched %d records", len(data.List))

	if err := c.saveRoadStatusToCache(ctx, data.List); err != nil {
		return fmt.Errorf("save failed: %w", err)
	}

	return nil
}

// Goroutine starters
func (c *Collector) startAccidentCollector(ctx context.Context) {
	log.Printf("[Accident] Collector started (Interval: %v)", c.config.AccidentInterval)

	ticker := time.NewTicker(c.config.AccidentInterval)
	defer ticker.Stop()

	// Collect immediately
	if err := c.collectAccidents(ctx); err != nil {
		log.Printf("[Accident] Initial collection failed: %v", err)
	}

	for {
		select {
		case <-ctx.Done():
			log.Println("[Accident] Collector stopped")
			return
		case <-ticker.C:
			if err := c.collectAccidents(ctx); err != nil {
				log.Printf("[Accident] Collection error: %v", err)
			}
		}
	}
}

func (c *Collector) startTollgateCollector(ctx context.Context) {
	log.Printf("[Tollgate] Collector started (Interval: %v)", c.config.TollgateInterval)

	ticker := time.NewTicker(c.config.TollgateInterval)
	defer ticker.Stop()

	// Collect immediately
	if err := c.collectTollgate(ctx); err != nil {
		log.Printf("[Tollgate] Initial collection failed: %v", err)
	}

	for {
		select {
		case <-ctx.Done():
			log.Println("[Tollgate] Collector stopped")
			return
		case <-ticker.C:
			if err := c.collectTollgate(ctx); err != nil {
				log.Printf("[Tollgate] Collection error: %v", err)
			}
		}
	}
}

func (c *Collector) startRoadStatusCollector(ctx context.Context) {
	log.Printf("[RoadStatus] Collector started (Interval: %v)", c.config.RoadStatusInterval)

	ticker := time.NewTicker(c.config.RoadStatusInterval)
	defer ticker.Stop()

	// Collect immediately
	if err := c.collectRoadStatus(ctx); err != nil {
		log.Printf("[RoadStatus] Initial collection failed: %v", err)
	}

	for {
		select {
		case <-ctx.Done():
			log.Println("[RoadStatus] Collector stopped")
			return
		case <-ticker.C:
			if err := c.collectRoadStatus(ctx); err != nil {
				log.Printf("[RoadStatus] Collection error: %v", err)
			}
		}
	}
}

func (c *Collector) Close() error {
	return c.db.Close()
}

func main() {
	// Load .env file if exists
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using environment variables or defaults")
	} else {
		log.Println("Loaded configuration from .env file")
	}

	config := loadConfig()

	log.Printf("========================================")
	log.Printf("OpenAPI Multi-Collector v2.0")
	log.Printf("========================================")
	log.Printf("Database: %s:%s/%s", config.DBHost, config.DBPort, config.DBName)
	log.Printf("Accident API: %s (Interval: %v)", config.AccidentAPIURL, config.AccidentInterval)
	log.Printf("Tollgate API: %s (Interval: %v)", config.TollgateAPIURL, config.TollgateInterval)
	log.Printf("RoadStatus API: %s (Interval: %v)", config.RoadStatusAPIURL, config.RoadStatusInterval)
	log.Printf("========================================")

	collector, err := NewCollector(config)
	if err != nil {
		log.Fatalf("Failed to create collector: %v", err)
	}
	defer collector.Close()

	ctx := context.Background()

	// Start all collectors in parallel
	go collector.startAccidentCollector(ctx)
	go collector.startTollgateCollector(ctx)
	go collector.startRoadStatusCollector(ctx)

	// Block forever
	select {}
}
