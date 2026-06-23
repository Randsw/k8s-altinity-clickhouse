package main

import (
	"fmt"
	"os"
)

type Config struct {
	Port          string
	ClickHouseDSN string
}

func LoadConfig() Config {
	// Application port
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	// Build DSN prioritising explicit DSN, then URL, then components
	dsn := os.Getenv("CLICKHOUSE_DSN")
	if dsn == "" {
		// If a full URL is provided, use it directly
		dsn = os.Getenv("CLICKHOUSE_URL")
	}
	if dsn == "" {
		// Assemble DSN from individual parts if available
		user := os.Getenv("CLICKHOUSE_USER")
		password := os.Getenv("CLICKHOUSE_PASSWORD")
		host := os.Getenv("CLICKHOUSE_HOST")
		if host == "" {
			host = "localhost:9000"
		}
		database := os.Getenv("CLICKHOUSE_DATABASE")
		if database == "" {
			database = "default"
		}
		// Build the DSN string only when user and password are set; otherwise omit credentials
		if user != "" && password != "" {
			dsn = fmt.Sprintf("clickhouse://%s:%s@%s/%s?dial_timeout=200ms", user, password, host, database)
		} else {
			dsn = fmt.Sprintf("clickhouse://%s/%s?dial_timeout=200ms", host, database)
		}
	}

	return Config{
		Port:          port,
		ClickHouseDSN: dsn,
	}
}
