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
	"github.com/redis/go-redis/v9"
)

type RealTimeSMS struct {
	AccDate    string  `json:"accDate"`
	AccHour    string  `json:"accHour"`
	AccPointNM string  `json:"accPointNM"`
	LinkID     string  `json:"linkId"`
	AccInfo    string  `json:"smsText"` // 고속도로 API uses smsText
	AccType    string  `json:"accType"`
	Latitude   float64 `json:"latitude"` // Always float64 from API
	Longitude  float64 `json:"altitude"` // 고속도로 API uses "altitude" for longitude
	RoadNM     string  `json:"roadNM"`   // Road name
}

type APIResponse struct {
	RealTimeSMSList []RealTimeSMS `json:"realTimeSMSList"`
}

// Tollgate Traffic API structures
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
	TrafficAmount string `json:"trafficAmout"` // Note: API has typo "Amout" instead of "Amount"
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

// Road Traffic Status API structures
type RoadTrafficStatus struct {
	RouteNo        string `json:"routeNo"`
	RouteName      string `json:"routeName"`
	ConzoneID      string `json:"conzoneId"`
	ConzoneName    string `json:"conzoneName"`
	VdsID          string `json:"vdsId"`
	UpdownTypeCode string `json:"updownTypeCode"`
	TrafficAmount  string `json:"trafficAmout"` // Note: API has typo "Amout"
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
	// Accident data collection
	DataSourceMode  string // "real" or "sim"
	RedisAddr       string
	SimulatorURL    string
	RealAPIURL      string
	RealAPIKey      string
	CollectInterval time.Duration

	// Tollgate traffic collection
	TollgateAPIURL          string
	TollgateAPIKey          string
	TollgateCollectInterval time.Duration // 15 minutes

	// Road traffic status collection
	RoadStatusAPIURL          string
	RoadStatusAPIKey          string
	RoadStatusCollectInterval time.Duration // 5 minutes

	// Database
	DBHost     string
	DBUser     string
	DBPassword string
	DBName     string
}

type Collector struct {
	config      Config
	redisClient *redis.Client
	db          *sql.DB
	httpClient  *http.Client
}

func loadConfig() Config {
	mode := os.Getenv("DATA_SOURCE_MODE")
	if mode == "" {
		mode = "sim"
	}

	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr == "" {
		redisAddr = "redis-central.default.svc.cluster.local:6379"
	}

	simulatorURL := os.Getenv("SIMULATOR_API_URL")
	if simulatorURL == "" {
		simulatorURL = "http://traffic-simulator.default.svc.cluster.local:8080/api/traffic"
	}

	realAPIURL := os.Getenv("REAL_OPENAPI_URL")
	if realAPIURL == "" {
		realAPIURL = "https://data.ex.co.kr/openapi/burstInfo/realTimeSms"
	}

	realAPIKey := os.Getenv("REAL_OPENAPI_KEY")
	if realAPIKey == "" {
		realAPIKey = "8771969304"
	}

	interval := 10 * time.Second
	if envInterval := os.Getenv("COLLECT_INTERVAL"); envInterval != "" {
		if d, err := time.ParseDuration(envInterval); err == nil {
			interval = d
		}
	}

	// Tollgate traffic API
	tollgateAPIURL := os.Getenv("TOLLGATE_API_URL")
	if tollgateAPIURL == "" {
		tollgateAPIURL = "https://data.ex.co.kr/openapi/trafficapi/trafficIc"
	}

	tollgateAPIKey := os.Getenv("TOLLGATE_API_KEY")
	if tollgateAPIKey == "" {
		tollgateAPIKey = "8771969304"
	}

	tollgateInterval := 15 * time.Minute
	if envTollgateInterval := os.Getenv("TOLLGATE_COLLECT_INTERVAL"); envTollgateInterval != "" {
		if d, err := time.ParseDuration(envTollgateInterval); err == nil {
			tollgateInterval = d
		}
	}

	// Road status API
	roadStatusAPIURL := os.Getenv("ROAD_STATUS_API_URL")
	if roadStatusAPIURL == "" {
		roadStatusAPIURL = "https://data.ex.co.kr/openapi/odtraffic/trafficAmountByRealtime"
	}

	roadStatusAPIKey := os.Getenv("ROAD_STATUS_API_KEY")
	if roadStatusAPIKey == "" {
		roadStatusAPIKey = "8771969304"
	}

	roadStatusInterval := 5 * time.Minute
	if envRoadStatusInterval := os.Getenv("ROAD_STATUS_COLLECT_INTERVAL"); envRoadStatusInterval != "" {
		if d, err := time.ParseDuration(envRoadStatusInterval); err == nil {
			roadStatusInterval = d
		}
	}

	// Database configuration
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

	return Config{
		DataSourceMode:            mode,
		RedisAddr:                 redisAddr,
		SimulatorURL:              simulatorURL,
		RealAPIURL:                realAPIURL,
		RealAPIKey:                realAPIKey,
		CollectInterval:           interval,
		TollgateAPIURL:            tollgateAPIURL,
		TollgateAPIKey:            tollgateAPIKey,
		TollgateCollectInterval:   tollgateInterval,
		RoadStatusAPIURL:          roadStatusAPIURL,
		RoadStatusAPIKey:          roadStatusAPIKey,
		RoadStatusCollectInterval: roadStatusInterval,
		DBHost:                    dbHost,
		DBUser:                    dbUser,
		DBPassword:                dbPassword,
		DBName:                    dbName,
	}
}

func NewCollector(config Config) (*Collector, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr: config.RedisAddr,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	log.Printf("Connected to Redis at %s", config.RedisAddr)

	// Connect to MariaDB
	dsn := fmt.Sprintf("%s:%s@tcp(%s)/%s?parseTime=true&loc=Asia%%2FSeoul",
		config.DBUser, config.DBPassword, config.DBHost, config.DBName)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(time.Minute * 5)

	if err := db.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	log.Printf("Connected to MariaDB at %s", config.DBHost)

	return &Collector{
		config:      config,
		redisClient: rdb,
		db:          db,
		httpClient: &http.Client{
			Timeout: 30 * time.Second, // Increased for tollgate API pagination
		},
	}, nil
}

func (c *Collector) fetchData(ctx context.Context) (*APIResponse, error) {
	var url string

	if c.config.DataSourceMode == "real" {
		// 고속도로 공공데이터 포털 API
		url = fmt.Sprintf("%s?key=%s&type=json&numOfRows=100&pageNo=1&sortType=desc&pagingYn=Y",
			c.config.RealAPIURL, c.config.RealAPIKey)
		log.Printf("Fetching from REAL OpenAPI (고속도로 공공데이터): %s", url)
	} else {
		url = c.config.SimulatorURL
		//log.Printf("Fetching from SIMULATOR: %s", url)
	}

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Add User-Agent header for 고속도로 API (mimics real browser)
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	// Add Accept header for JSON response
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

	var apiResp APIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &apiResp, nil
}

func (c *Collector) publishToStream(ctx context.Context, data *APIResponse) error {
	if len(data.RealTimeSMSList) == 0 {
		//log.Println("No accidents to publish")
		return nil
	}

	jsonData, err := json.Marshal(data.RealTimeSMSList)
	if err != nil {
		return fmt.Errorf("failed to marshal data: %w", err)
	}

	streamKey := "traffic-stream"
	args := &redis.XAddArgs{
		Stream: streamKey,
		Values: map[string]interface{}{
			"data":      string(jsonData),
			"timestamp": time.Now().Unix(),
			"source":    c.config.DataSourceMode,
		},
	}

	id, err := c.redisClient.XAdd(ctx, args).Result()
	if err != nil {
		return fmt.Errorf("failed to add to stream: %w", err)
	}

	log.Printf("Published %d accidents to stream %s (ID: %s, Mode: %s)",
		len(data.RealTimeSMSList), streamKey, id, c.config.DataSourceMode)

	return nil
}

func (c *Collector) collectOnce(ctx context.Context) error {
	data, err := c.fetchData(ctx)
	if err != nil {
		return fmt.Errorf("fetch failed: %w", err)
	}

	if err := c.publishToStream(ctx, data); err != nil {
		return fmt.Errorf("publish failed: %w", err)
	}

	return nil
}

func (c *Collector) Start(ctx context.Context) {
	log.Printf("Data Collector started (Mode: %s, Interval: %v)",
		c.config.DataSourceMode, c.config.CollectInterval)

	ticker := time.NewTicker(c.config.CollectInterval)
	defer ticker.Stop()

	// Collect immediately on start
	if err := c.collectOnce(ctx); err != nil {
		log.Printf("Initial collection failed: %v", err)
	}

	for {
		select {
		case <-ctx.Done():
			log.Println("Collector stopped")
			return
		case <-ticker.C:
			if err := c.collectOnce(ctx); err != nil {
				log.Printf("Collection error: %v", err)
			}
		}
	}
}

func (c *Collector) Close() error {
	if c.db != nil {
		c.db.Close()
	}
	return c.redisClient.Close()
}

// Tollgate traffic collection functions
func (c *Collector) fetchTollgateTraffic(ctx context.Context, pageNo int) (*TollgateAPIResponse, error) {
	url := fmt.Sprintf("%s?key=%s&type=json&tmType=2&numOfRows=100&pageNo=%d&carType=1&inoutType=0&tcsType=2",
		c.config.TollgateAPIURL, c.config.TollgateAPIKey, pageNo)

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

func (c *Collector) saveTollgateTraffic(ctx context.Context, traffic *TollgateTraffic) error {
	// Parse collected_at from sum_date and sum_tm with Asia/Seoul timezone
	loc, err := time.LoadLocation("Asia/Seoul")
	if err != nil {
		loc = time.FixedZone("KST", 9*60*60) // Fallback to UTC+9
	}

	collectedAt, err := time.ParseInLocation("20060102 1504", traffic.SumDate+" "+traffic.SumTm, loc)
	if err != nil {
		return fmt.Errorf("failed to parse time: %w", err)
	}

	// Handle empty traffic amount (convert to 0)
	trafficAmount := traffic.TrafficAmount
	if trafficAmount == "" {
		trafficAmount = "0"
	}

	query := `INSERT INTO tollgate_traffic_history
		(ex_div_code, ex_div_name, unit_code, unit_name, inout_type, inout_name,
		 tm_type, tm_name, tcs_type, tcs_name, car_type, traffic_amount,
		 sum_date, sum_tm, collected_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE
		traffic_amount = VALUES(traffic_amount),
		created_at = CURRENT_TIMESTAMP`

	_, err = c.db.ExecContext(ctx, query,
		traffic.ExDivCode, traffic.ExDivName, traffic.UnitCode, traffic.UnitName,
		traffic.InoutType, traffic.InoutName, traffic.TmType, traffic.TmName,
		traffic.TcsType, traffic.TcsName, traffic.CarType, trafficAmount,
		traffic.SumDate, traffic.SumTm, collectedAt)

	if err != nil {
		return fmt.Errorf("failed to insert traffic data: %w", err)
	}

	return nil
}

func (c *Collector) upsertTollgateMaster(ctx context.Context, traffic *TollgateTraffic) error {
	query := `INSERT INTO tollgate_master
		(unit_code, unit_name, ex_div_code, ex_div_name, first_collected_at, last_collected_at)
		VALUES (?, ?, ?, ?, NOW(), NOW())
		ON DUPLICATE KEY UPDATE
		unit_name = VALUES(unit_name),
		ex_div_name = VALUES(ex_div_name),
		last_collected_at = NOW()`

	_, err := c.db.ExecContext(ctx, query,
		traffic.UnitCode, traffic.UnitName, traffic.ExDivCode, traffic.ExDivName)

	return err
}

func (c *Collector) collectTollgateTrafficOnce(ctx context.Context) error {
	log.Println("Starting tollgate traffic collection...")

	// First page to get total count
	firstPage, err := c.fetchTollgateTraffic(ctx, 1)
	if err != nil {
		return fmt.Errorf("failed to fetch first page: %w", err)
	}

	if firstPage.Code != "SUCCESS" {
		return fmt.Errorf("API error: %s - %s", firstPage.Code, firstPage.Message)
	}

	log.Printf("Total tollgate traffic records: %d (pages: %d)", firstPage.Count, firstPage.PageSize)

	totalSaved := 0
	totalPages := firstPage.PageSize

	// Process all pages
	for pageNo := 1; pageNo <= totalPages; pageNo++ {
		var pageData *TollgateAPIResponse

		if pageNo == 1 {
			pageData = firstPage
		} else {
			pageData, err = c.fetchTollgateTraffic(ctx, pageNo)
			if err != nil {
				log.Printf("Failed to fetch page %d: %v", pageNo, err)
				continue
			}
		}

		// Save each traffic record
		for i, traffic := range pageData.TrafficIc {
			// Debug: log first few records to see actual traffic amounts
			if pageNo == 1 && i < 3 {
				log.Printf("DEBUG: Unit=%s, Time=%s %s, TrafficAmount='%s'",
					traffic.UnitName, traffic.SumDate, traffic.SumTm, traffic.TrafficAmount)
			}

			if err := c.saveTollgateTraffic(ctx, &traffic); err != nil {
				log.Printf("Failed to save traffic data (unit: %s, time: %s %s): %v",
					traffic.UnitCode, traffic.SumDate, traffic.SumTm, err)
				continue
			}

			// Update tollgate master
			if err := c.upsertTollgateMaster(ctx, &traffic); err != nil {
				log.Printf("Failed to update tollgate master (unit: %s): %v", traffic.UnitCode, err)
			}

			totalSaved++
		}

		if pageNo%10 == 0 || pageNo == totalPages {
			log.Printf("Progress: %d/%d pages processed, %d records saved", pageNo, totalPages, totalSaved)
		}
	}

	log.Printf("Tollgate traffic collection completed: %d records saved", totalSaved)
	return nil
}

func (c *Collector) startTollgateCollection(ctx context.Context) {
	log.Printf("Tollgate traffic collector started (Interval: %v)", c.config.TollgateCollectInterval)

	ticker := time.NewTicker(c.config.TollgateCollectInterval)
	defer ticker.Stop()

	// Collect immediately on start
	if err := c.collectTollgateTrafficOnce(ctx); err != nil {
		log.Printf("Initial tollgate collection failed: %v", err)
	}

	for {
		select {
		case <-ctx.Done():
			log.Println("Tollgate collector stopped")
			return
		case <-ticker.C:
			if err := c.collectTollgateTrafficOnce(ctx); err != nil {
				log.Printf("Tollgate collection error: %v", err)
			}
		}
	}
}

// Road traffic status collection functions
func (c *Collector) fetchRoadStatus(ctx context.Context) (*RoadStatusAPIResponse, error) {
	url := fmt.Sprintf("%s?key=%s&type=json", c.config.RoadStatusAPIURL, c.config.RoadStatusAPIKey)

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch data: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	var apiResp RoadStatusAPIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &apiResp, nil
}

func (c *Collector) saveRoadStatus(ctx context.Context, status *RoadTrafficStatus) error {
	// Parse collected_at from std_date and std_hour
	loc, err := time.LoadLocation("Asia/Seoul")
	if err != nil {
		loc = time.FixedZone("KST", 9*60*60) // Fallback to UTC+9
	}

	collectedAt, err := time.ParseInLocation("20060102 1504", status.StdDate+" "+status.StdHour, loc)
	if err != nil {
		return fmt.Errorf("failed to parse time: %w", err)
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

	query := `INSERT INTO road_traffic_status
		(route_no, route_name, conzone_id, conzone_name, vds_id, updown_type_code,
		 traffic_amount, speed, share_ratio, time_avg, grade, std_date, std_hour, collected_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE
		traffic_amount = VALUES(traffic_amount),
		speed = VALUES(speed),
		share_ratio = VALUES(share_ratio),
		time_avg = VALUES(time_avg),
		grade = VALUES(grade),
		created_at = CURRENT_TIMESTAMP`

	_, err = c.db.ExecContext(ctx, query,
		status.RouteNo, status.RouteName, status.ConzoneID, status.ConzoneName,
		status.VdsID, status.UpdownTypeCode,
		trafficAmount, speed, shareRatio, timeAvg, grade,
		status.StdDate, status.StdHour, collectedAt)

	if err != nil {
		return fmt.Errorf("failed to save road status: %w", err)
	}

	return nil
}

func (c *Collector) aggregateRouteSummary(ctx context.Context) error {
	// Get the latest collected_at time
	var latestCollectedAt time.Time
	err := c.db.QueryRowContext(ctx, `
		SELECT MAX(collected_at) FROM road_traffic_status
	`).Scan(&latestCollectedAt)
	if err != nil {
		return fmt.Errorf("failed to get latest collected_at: %w", err)
	}

	// Aggregate by route
	query := `
		INSERT INTO road_route_summary
		(route_no, route_name, total_sections, smooth_sections, slow_sections,
		 congested_sections, avg_speed, avg_traffic_amount, collected_at)
		SELECT
			route_no,
			route_name,
			COUNT(*) as total_sections,
			SUM(CASE WHEN grade = 1 THEN 1 ELSE 0 END) as smooth_sections,
			SUM(CASE WHEN grade = 2 THEN 1 ELSE 0 END) as slow_sections,
			SUM(CASE WHEN grade = 3 THEN 1 ELSE 0 END) as congested_sections,
			ROUND(AVG(CASE WHEN speed >= 0 THEN speed END), 1) as avg_speed,
			ROUND(AVG(CASE WHEN traffic_amount >= 0 THEN traffic_amount END), 1) as avg_traffic_amount,
			? as collected_at
		FROM road_traffic_status
		WHERE collected_at = ?
			AND speed >= 0 AND grade > 0
		GROUP BY route_no, route_name
		ON DUPLICATE KEY UPDATE
			total_sections = VALUES(total_sections),
			smooth_sections = VALUES(smooth_sections),
			slow_sections = VALUES(slow_sections),
			congested_sections = VALUES(congested_sections),
			avg_speed = VALUES(avg_speed),
			avg_traffic_amount = VALUES(avg_traffic_amount)
	`

	result, err := c.db.ExecContext(ctx, query, latestCollectedAt, latestCollectedAt)
	if err != nil {
		return fmt.Errorf("failed to aggregate route summary: %w", err)
	}

	rowsAffected, _ := result.RowsAffected()
	log.Printf("Route summary aggregation completed: %d routes processed", rowsAffected)
	return nil
}

func (c *Collector) collectRoadStatusOnce(ctx context.Context) error {
	log.Println("Starting road status collection...")

	apiResp, err := c.fetchRoadStatus(ctx)
	if err != nil {
		return fmt.Errorf("failed to fetch road status: %w", err)
	}

	log.Printf("Total road status records: %d", apiResp.Count)

	savedCount := 0
	for _, status := range apiResp.List {
		if err := c.saveRoadStatus(ctx, &status); err != nil {
			log.Printf("Failed to save road status (VDS: %s): %v", status.VdsID, err)
			continue
		}
		savedCount++
	}

	log.Printf("Road status collection completed: %d/%d records saved", savedCount, len(apiResp.List))

	// Aggregate by route after saving all status data
	if err := c.aggregateRouteSummary(ctx); err != nil {
		log.Printf("Failed to aggregate route summary: %v", err)
		// Don't return error, as the main data collection was successful
	}

	return nil
}

func (c *Collector) startRoadStatusCollection(ctx context.Context) {
	log.Printf("Road status collector started (Interval: %v)", c.config.RoadStatusCollectInterval)

	ticker := time.NewTicker(c.config.RoadStatusCollectInterval)
	defer ticker.Stop()

	// Collect immediately on start
	if err := c.collectRoadStatusOnce(ctx); err != nil {
		log.Printf("Initial road status collection failed: %v", err)
	}

	for {
		select {
		case <-ctx.Done():
			log.Println("Road status collector stopped")
			return
		case <-ticker.C:
			if err := c.collectRoadStatusOnce(ctx); err != nil {
				log.Printf("Road status collection error: %v", err)
			}
		}
	}
}

func main() {
	config := loadConfig()

	log.Printf("Configuration:")
	log.Printf("  [Accident Data]")
	log.Printf("    Data Source Mode: %s", config.DataSourceMode)
	log.Printf("    Redis Address: %s", config.RedisAddr)
	log.Printf("    Simulator URL: %s", config.SimulatorURL)
	log.Printf("    Real API URL: %s", config.RealAPIURL)
	log.Printf("    Collection Interval: %v", config.CollectInterval)
	log.Printf("  [Tollgate Traffic]")
	log.Printf("    API URL: %s", config.TollgateAPIURL)
	log.Printf("    Collection Interval: %v", config.TollgateCollectInterval)
	log.Printf("  [Road Traffic Status]")
	log.Printf("    API URL: %s", config.RoadStatusAPIURL)
	log.Printf("    Collection Interval: %v", config.RoadStatusCollectInterval)
	log.Printf("  [Database]")
	log.Printf("    Host: %s", config.DBHost)
	log.Printf("    Database: %s", config.DBName)

	collector, err := NewCollector(config)
	if err != nil {
		log.Fatalf("Failed to create collector: %v", err)
	}
	defer collector.Close()

	ctx := context.Background()

	// Start all collectors in separate goroutines
	go collector.Start(ctx)
	go collector.startTollgateCollection(ctx)
	go collector.startRoadStatusCollection(ctx)

	// Block forever
	select {}
}
