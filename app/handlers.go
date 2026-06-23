package main

import (
	"html/template"
	"log"
	"net/http"
)

type Handlers struct {
	repo *Repository
}

const htmlTemplate = `
<!DOCTYPE html>
<html>
<head>
    <title>ClickHouse Data Viewer</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 30px; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .nav { margin-bottom: 20px; }
        .nav a { margin-right: 15px; text-decoration: none; color: #333; font-weight: bold; }
    </style>
</head>
<body>
    <div class="nav">
        <a href="/generate">⚡ Сгенерировать 100 строк</a>
        <a href="/show">📋 Показать данные</a>
        <a href="/calc">📊 Аналитика</a>
    </div>

    {{if .Rows}}
    <h2>Последние 100 записей из ClickHouse</h2>
    <table>
        <tr>
            <th>User ID</th>
            <th>Item ID</th>
            <th>Category</th>
            <th>Price</th>
            <th>Created At</th>
        </tr>
        {{range .Rows}}
        <tr>
            <td>{{.UserID}}</td>
            <td>{{.ItemID}}</td>
            <td>{{.ItemCategory}}</td>
            <td>${{.Price}}</td>
            <td>{{.CreatedAt.Format "2006-01-02 15:04:05"}}</td>
        </tr>
        {{end}}
    </table>
    {{end}}

    {{if .Analytics}}
    <h2>Аналитика по категориям</h2>
    <table>
        <tr>
            <th>Категория</th>
            <th>Общие продажи</th>
            <th>Средний чек</th>
        </tr>
        {{range .Analytics}}
        <tr>
            <td>{{.Category}}</td>
            <td>${{.TotalSales}}</td>
            <td>${{.AvgPrice}}</td>
        </tr>
        {{end}}
    </table>
    {{end}}

    {{if .Message}}
    <p style="color: green; font-size: 18px;">{{.Message}}</p>
    {{end}}
</body>
</html>
`

func NewHandlers(repo *Repository) *Handlers {
	return &Handlers{repo: repo}
}

func (h *Handlers) GenerateHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if err := h.repo.GenerateMockData(ctx); err != nil {
		log.Printf("Error generating data: %v", err)
		http.Error(w, "Failed to generate data", http.StatusInternalServerError)
		return
	}

	tmpl := template.Must(template.New("web").Parse(htmlTemplate))
	tmpl.Execute(w, map[string]interface{}{"Message": "Успешно сгенерировано и записано 100 строк в ClickHouse!"})
}

func (h *Handlers) ShowHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	rows, err := h.repo.GetRows(ctx)
	if err != nil {
		log.Printf("Error fetching data: %v", err)
		http.Error(w, "Failed to fetch data", http.StatusInternalServerError)
		return
	}

	tmpl := template.Must(template.New("web").Parse(htmlTemplate))
	tmpl.Execute(w, map[string]interface{}{"Rows": rows})
}

func (h *Handlers) CalcHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	analytics, err := h.repo.GetAnalytics(ctx)
	if err != nil {
		log.Printf("Error calculating analytics: %v", err)
		http.Error(w, "Failed to calculate analytics", http.StatusInternalServerError)
		return
	}

	tmpl := template.Must(template.New("web").Parse(htmlTemplate))
	tmpl.Execute(w, map[string]interface{}{"Analytics": analytics})
}
