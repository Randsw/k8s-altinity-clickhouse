package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	log.Println("Starting application...")
	cfg := LoadConfig()

	// Инициализация репозитория с таймаутом (K8s Best Practice)
	initCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	repo, err := NewRepository(cfg.ClickHouseDSN)
	if err != nil {
		log.Fatalf("Unable to connect to ClickHouse: %v", err)
	}

	if err := repo.InitSchema(initCtx); err != nil {
		log.Fatalf("Failed to initialize database schema: %v", err)
	}
	log.Println("Connected to ClickHouse & Schema initialized")

	// Настройка роутера
	h := NewHandlers(repo)
	mux := http.NewServeMux()

	mux.HandleFunc("/generate", h.GenerateHandler)
	mux.HandleFunc("/show", h.ShowHandler)
	mux.HandleFunc("/calc", h.CalcHandler)

	// Kubernetes Пробы (Health Checks)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	server := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// Канал для перехвата системных сигналов остановки контейнера
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("Server is listening on port %s", cfg.Port)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("Could not listen on %s: %v\n", cfg.Port, err)
		}
	}()

	// Ожидание сигнала от Kubernetes (SIGTERM)
	<-stop
	log.Println("Shutting down server gracefully...")

	// Даем 5 секунд на завершение активных запросов
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server gracefully stopped")
}
