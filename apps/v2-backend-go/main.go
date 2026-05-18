package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/go-sql-driver/mysql"
)

var db *sql.DB

type SecretData struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Host     string `json:"host"`
	Port     int    `json:"port"`
	DBName   string `json:"dbname"`
}

type Recipe struct {
	ID            int    `json:"id"`
	Name          string `json:"name"`
	Email         string `json:"email"`
	RecipeName    string `json:"recipe_name"`
	Ingredients   string `json:"ingredients"`
	RecipeDetails string `json:"recipe_details"`
	CreatedAt     string `json:"created_at"`
}

func getMySQLSecrets() (*SecretData, error) {
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "eu-west-2"
	}
	secretArn := os.Getenv("SECRET_ARN")
	if secretArn == "" {
		return nil, fmt.Errorf("SECRET_ARN environment variable is missing")
	}

	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	if err != nil {
		return nil, err
	}

	client := secretsmanager.NewFromConfig(cfg)
	input := &secretsmanager.GetSecretValueInput{
		SecretId: &secretArn,
	}

	result, err := client.GetSecretValue(context.TODO(), input)
	if err != nil {
		return nil, err
	}

	var secretData SecretData
	err = json.Unmarshal([]byte(*result.SecretString), &secretData)
	if err != nil {
		return nil, err
	}

	return &secretData, nil
}

func initDB() error {
	secrets, err := getMySQLSecrets()
	if err != nil {
		return fmt.Errorf("failed to fetch secrets: %v", err)
	}

	// Register RDS SSL Certificate
	rootCertPool := x509.NewCertPool()
	pem, err := os.ReadFile("/app/global-bundle.pem")
	if err != nil {
		return fmt.Errorf("failed to read RDS SSL bundle: %v", err)
	}
	if ok := rootCertPool.AppendCertsFromPEM(pem); !ok {
		return fmt.Errorf("failed to append PEM")
	}
	mysql.RegisterTLSConfig("rds-tls", &tls.Config{
		RootCAs: rootCertPool,
	})

	dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?tls=rds-tls&parseTime=true",
		secrets.Username, secrets.Password, secrets.Host, secrets.Port, secrets.DBName)

	db, err = sql.Open("mysql", dsn)
	if err != nil {
		return err
	}

	// Connection Pooling Settings (Go handles this natively)
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	// Verify connection and create table
	err = db.Ping()
	if err != nil {
		return err
	}

	createTableQuery := `
	CREATE TABLE IF NOT EXISTS recipes (
		id INT AUTO_INCREMENT PRIMARY KEY,
		name VARCHAR(255) NOT NULL,
		email VARCHAR(255) NOT NULL,
		recipe_name VARCHAR(255) NOT NULL,
		ingredients TEXT,
		description_main TEXT,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);`
	_, err = db.Exec(createTableQuery)
	if err != nil {
		return fmt.Errorf("failed to create table: %v", err)
	}

	log.Println("✅ Database pool initialized and table verified.")
	return nil
}

// CORS Middleware
func enableCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	}
}

func healthCheck(w http.ResponseWriter, r *http.Request) {
	if db == nil {
		if err := initDB(); err != nil {
			http.Error(w, "Disconnected", http.StatusServiceUnavailable)
			return
		}
	}
	if err := db.Ping(); err != nil {
		http.Error(w, "Disconnected", http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func getRecipes(w http.ResponseWriter, r *http.Request) {
	if db == nil {
		http.Error(w, "DB not ready", http.StatusServiceUnavailable)
		return
	}

	rows, err := db.Query("SELECT id, name, email, recipe_name, ingredients, description_main, created_at FROM recipes ORDER BY id DESC")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var recipes []Recipe
	for rows.Next() {
		var rec Recipe
		var createdAt time.Time
		var ingredients, desc sql.NullString

		err := rows.Scan(&rec.ID, &rec.Name, &rec.Email, &rec.RecipeName, &ingredients, &desc, &createdAt)
		if err != nil {
			continue
		}
		rec.Ingredients = ingredients.String
		rec.RecipeDetails = desc.String
		rec.CreatedAt = createdAt.Format(time.RFC3339)
		recipes = append(recipes, rec)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(recipes)
}

func addRecipe(w http.ResponseWriter, r *http.Request) {
	if db == nil {
		http.Error(w, "DB not ready", http.StatusServiceUnavailable)
		return
	}

	var data map[string]string
	if err := json.NewDecoder(r.Body).Decode(&data); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	query := `INSERT INTO recipes (name, email, recipe_name, ingredients, description_main) VALUES (?, ?, ?, ?, ?)`
	_, err := db.Exec(query, data["name"], data["email"], data["recipe_name"], data["ingredients"], data["description_main"])
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"status": "success"})
}

func main() {
	// Attempt initial DB connection
	for i := 0; i < 3; i++ {
		if err := initDB(); err == nil {
			break
		}
		log.Printf("⚠️ Attempt %d failed, retrying in 5 seconds...", i+1)
		time.Sleep(5 * time.Second)
	}

	http.HandleFunc("/health", healthCheck)
	http.HandleFunc("/api/get_recipe", enableCORS(getRecipes))
	http.HandleFunc("/api/add_recipe", enableCORS(addRecipe))

	log.Println("🚀 Server starting on port 5000...")
	log.Fatal(http.ListenAndServe("0.0.0.0:5000", nil))
}
