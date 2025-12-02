package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"time"
)

type Config struct {
	Port              string
	DataAPIServiceURL string
}

func loadConfig() Config {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	dataAPIServiceURL := os.Getenv("DATA_API_SERVICE_URL")
	if dataAPIServiceURL == "" {
		dataAPIServiceURL = "http://data-api-service.default.svc.cluster.local:8080"
	}

	return Config{
		Port:              port,
		DataAPIServiceURL: dataAPIServiceURL,
	}
}

type Gateway struct {
	config      Config
	dataAPIProxy *httputil.ReverseProxy
	httpClient   *http.Client
}

func NewGateway(config Config) (*Gateway, error) {
	dataAPIURL, err := url.Parse(config.DataAPIServiceURL)
	if err != nil {
		return nil, fmt.Errorf("invalid data API service URL: %w", err)
	}

	dataAPIProxy := httputil.NewSingleHostReverseProxy(dataAPIURL)

	// Configure proxy with custom transport
	dataAPIProxy.Transport = &http.Transport{
		MaxIdleConns:        100,
		MaxIdleConnsPerHost: 100,
		IdleConnTimeout:     90 * time.Second,
	}

	// Remove upstream CORS headers and set our own
	dataAPIProxy.ModifyResponse = func(resp *http.Response) error {
		// Delete all CORS headers from upstream
		resp.Header.Del("Access-Control-Allow-Origin")
		resp.Header.Del("Access-Control-Allow-Methods")
		resp.Header.Del("Access-Control-Allow-Headers")
		resp.Header.Del("Access-Control-Allow-Credentials")

		// Set our own CORS headers
		resp.Header.Set("Access-Control-Allow-Origin", "*")
		resp.Header.Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		resp.Header.Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		return nil
	}

	// Custom error handler
	dataAPIProxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("Proxy error for %s: %v", r.URL.Path, err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadGateway)
		w.Write([]byte(`{"error": "Service temporarily unavailable"}`))
	}

	return &Gateway{
		config:       config,
		dataAPIProxy: dataAPIProxy,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}, nil
}

func (g *Gateway) enableCORS(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
}

func (g *Gateway) handleDataAPI(w http.ResponseWriter, r *http.Request) {
	// Handle OPTIONS preflight
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.WriteHeader(http.StatusOK)
		return
	}

	log.Printf("Proxying request: %s %s to %s", r.Method, r.URL.Path, g.config.DataAPIServiceURL)

	// Add forwarding headers
	r.Header.Set("X-Forwarded-Host", r.Host)
	r.Header.Set("X-Forwarded-Proto", "http")

	// Proxy the request (CORS handled in ModifyResponse)
	g.dataAPIProxy.ServeHTTP(w, r)
}

func (g *Gateway) healthHandler(w http.ResponseWriter, r *http.Request) {
	// Simple health check - only check if gateway itself is running
	// Don't check downstream services to avoid circular dependency issues
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func (g *Gateway) infoHandler(w http.ResponseWriter, r *http.Request) {
	g.enableCORS(w)

	hostname, _ := os.Hostname()
	info := fmt.Sprintf(`{
  "service": "api-gateway",
  "version": "1.0.0",
  "hostname": "%s",
  "endpoints": {
    "accidents": "/api/accidents/latest",
    "stats": "/api/accidents/stats",
    "health": "/health"
  },
  "upstreamServices": {
    "dataAPI": "%s"
  }
}`, hostname, g.config.DataAPIServiceURL)

	w.Header().Set("Content-Type", "application/json")
	io.WriteString(w, info)
}

func (g *Gateway) Start() error {
	// Route /api/* to data-api-service
	http.HandleFunc("/api/", g.handleDataAPI)

	// Health and info endpoints
	http.HandleFunc("/health", g.healthHandler)
	http.HandleFunc("/info", g.infoHandler)

	addr := ":" + g.config.Port
	log.Printf("API Gateway starting on %s", addr)
	log.Printf("Routing /api/* to %s", g.config.DataAPIServiceURL)

	return http.ListenAndServe(addr, nil)
}

func main() {
	config := loadConfig()

	log.Printf("Configuration:")
	log.Printf("  Port: %s", config.Port)
	log.Printf("  Data API Service URL: %s", config.DataAPIServiceURL)

	gateway, err := NewGateway(config)
	if err != nil {
		log.Fatalf("Failed to create gateway: %v", err)
	}

	if err := gateway.Start(); err != nil {
		log.Fatalf("Gateway failed: %v", err)
	}
}
