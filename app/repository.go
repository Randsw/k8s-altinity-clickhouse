package main

import (
	"context"
	"math/rand"
	"time"

	"github.com/ClickHouse/clickhouse-go/v2"
)

type CartRow struct {
	UserID       uint32    `ch:"user_id"`
	ItemID       uint32    `ch:"item_id"`
	ItemCategory string    `ch:"item_category"`
	Price        float64   `ch:"price"`
	CreatedAt    time.Time `ch:"created_at"`
}

type AnalyticsResult struct {
	Category   string  `ch:"item_category"`
	TotalSales float64 `ch:"total_sales"`
	AvgPrice   float64 `ch:"avg_price"`
}

type Repository struct {
	conn clickhouse.Conn // Используем нативный интерфейс вместо *sql.DB
}

func NewRepository(dsn string) (*Repository, error) {
	// Парсим DSN в опции драйвера
	opts, err := clickhouse.ParseDSN(dsn)
	if err != nil {
		return nil, err
	}

	conn, err := clickhouse.Open(opts)
	if err != nil {
		return nil, err
	}

	if err := conn.Ping(context.Background()); err != nil {
		return nil, err
	}

	return &Repository{conn: conn}, nil
}

func (r *Repository) InitSchema(ctx context.Context) error {
	query := `
	CREATE TABLE IF NOT EXISTS shop_cart (
		user_id UInt32,
		item_id UInt32,
		item_category String,
		price Float64,
		created_at DateTime
	) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/shop_cart', '{replica}')
	ORDER BY (item_category, created_at);`

	return r.conn.Exec(ctx, query)
}

func (r *Repository) GenerateMockData(ctx context.Context) error {
	categories := []string{"Electronics", "Clothing", "Books", "Home", "Sports"}

	// Инициализируем правильный Batch (секция VALUES не нужна)
	batch, err := r.conn.PrepareBatch(ctx, "INSERT INTO shop_cart")
	if err != nil {
		return err
	}

	rng := rand.New(rand.NewSource(time.Now().UnixNano()))

	for i := 0; i < 100; i++ {
		userId := uint32(rng.Intn(1000) + 1)
		itemId := uint32(rng.Intn(5000) + 1)
		category := categories[rng.Intn(len(categories))]
		price := mathRound(rng.Float64()*(500-5)+5, 2)
		createdAt := time.Now().Add(-time.Duration(rng.Intn(24*7)) * time.Hour)

		// Добавляем строку в буфер батча
		err = batch.Append(userId, itemId, category, price, createdAt)
		if err != nil {
			return err
		}
	}

	// Отправляем все 100 строк одним сетевым пакетом
	return batch.Send()
}

func (r *Repository) GetRows(ctx context.Context) ([]CartRow, error) {
	query := "SELECT user_id, item_id, item_category, price, created_at FROM shop_cart ORDER BY created_at DESC LIMIT 100"

	var result []CartRow
	// Нативный метод Select автоматически сканирует строки в слайс структур
	if err := r.conn.Select(ctx, &result, query); err != nil {
		return nil, err
	}

	return result, nil
}

func (r *Repository) GetAnalytics(ctx context.Context) ([]AnalyticsResult, error) {
	query := `
		SELECT 
			item_category, 
			round(sum(price), 2) as total_sales, 
			round(avg(price), 2) as avg_price 
		FROM shop_cart 
		GROUP BY item_category 
		ORDER BY total_sales DESC`

	var result []AnalyticsResult
	if err := r.conn.Select(ctx, &result, query); err != nil {
		return nil, err
	}

	return result, nil
}

func mathRound(val float64, precision int) float64 {
	p := 1.0
	for i := 0; i < precision; i++ {
		p *= 10
	}
	return float64(int(val*p)) / p
}
