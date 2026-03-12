package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
)

type Response struct {
	Message string `json:"message"`
}

type Status struct {
	URL        string    `json:"url"`
	StatusCode int       `json:"status_code"`
	CheckedAt  time.Time `json:"checked_at"`
}

var (
	devAccessStatus Status
	mu              sync.RWMutex
)

func main() {
	url := "https://dev.sandbox.loginproxy.gov.bc.ca" // Replace with your target URL

	// Start a ticker that triggers every minute
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	// Run immediately before waiting for the first tick
	go accessCheck(url)

	// HTTP server
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Server is running and checking %s every minute.\n", url)
	})

	// API
	http.HandleFunc("/api/hello", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(Response{Message: "Hello from Go API!"})
	})

	http.HandleFunc("/api/dev/access", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		mu.RLock()
		defer mu.RUnlock()
		json.NewEncoder(w).Encode(devAccessStatus)
	})

	go func() {
		log.Println("Starting HTTP server on :8080")
		log.Fatal(http.ListenAndServe(":8080", nil))
	}()

	// Loop for periodic checks
	for range ticker.C {
		accessCheck(url)
		// Run the individual checks
		// TODO MULTI THREAD THIS

	}
}

func accessCheck(url string) {
	resp, err := http.Get(url)
	mu.Lock()
	defer mu.Unlock()

	if err != nil {
		log.Printf("Error fetching %s: %v", url, err)
		return
	}
	defer resp.Body.Close()

	devAccessStatus = Status{URL: url, StatusCode: resp.StatusCode, CheckedAt: time.Now()}
	log.Printf("Checked %s - Status Code: %d", url, resp.StatusCode)
}
