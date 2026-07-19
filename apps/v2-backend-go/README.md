# V2 Backend — Go

This is the "challenger" backend for Ritual Roast: a Go rewrite of `apps/v1-backend-flask`, serving the exact same job: store and return recipe submissions from the
shared RDS MySQL database using Go's standard library instead of Flask. It exists to give the canary/blue-green/shadow-traffic exercises in `infrastructure/05-aws-k8s` a real second implementation to route live traffic to, and to demonstrate a subtlety that only shows up once you change languages: **this rewrite's most natural health check is more dangerous than v1's, and the fix is one of the more important design decisions in this whole project.** See "The probe split" below. Read it before touching any health check in this codebase.

## What's in this directory

| File                | Purpose                                                                                          |
| ------------------- | ------------------------------------------------------------------------------------------------ |
| `main.go`           | The entire backend: routes, connection pooling, TLS, Secrets Manager integration, health checks. |
| `Dockerfile`        | Two-stage build producing a fully static, non-root, minimal image.                               |
| `go.mod` / `go.sum` | Module definition and dependency lock.                                                           |

## Walking through `main.go`

### 1. Fetching credentials from Secrets Manager (same idea as v1, AWS SDK v2 flavour)

```go
func getMySQLSecrets() (*SecretData, error) {
	region := os.Getenv("AWS_REGION")
	secretArn := os.Getenv("SECRET_ARN")
	if secretArn == "" {
		return nil, fmt.Errorf("SECRET_ARN environment variable is missing")
	}
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion(region))
	client := secretsmanager.NewFromConfig(cfg)
	result, err := client.GetSecretValue(context.TODO(), &secretsmanager.GetSecretValueInput{SecretId: &secretArn})
	var secretData SecretData
	json.Unmarshal([]byte(*result.SecretString), &secretData)
	return &secretData, nil
}
```

Exactly the same principle as the Flask backend: the database username, password, host, and port are never in the image or a plain environment variable, only `SECRET_ARN`, a pointer into AWS Secrets Manager, is injected at runtime. `config.LoadDefaultConfig` picks up credentials from the container/pod's IAM role automatically (the AWS SDK's standard credential chain), so there's no key material anywhere in this code or its configuration either.

### 2. Manually registering the RDS TLS certificate

```go
rootCertPool := x509.NewCertPool()
pem, _ := os.ReadFile("/app/global-bundle.pem")
rootCertPool.AppendCertsFromPEM(pem)
mysql.RegisterTLSConfig("rds-tls", &tls.Config{RootCAs: rootCertPool})

dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?tls=rds-tls&parseTime=true",
	secrets.Username, secrets.Password, secrets.Host, secrets.Port, secrets.DBName)
```

Go's MySQL driver doesn't accept a certificate file path directly the way Python's connector does (`ssl_ca='/app/...'`), instead the driver wants a named `tls.Config` registered ahead of time, which the DSN (data source name / connection string) then references by name via `tls=rds-tls`. The net effect is identical to v1: MySQL traffic is encrypted, and the server certificate is verified against Amazon's RDS CA bundle rather than trusted blindly. `parseTime=true` makes the driver decode MySQL `DATETIME` columns straight into Go's `time.Time`, instead of raw bytes the app would have to parse itself.

### 3. Connection pooling — built into `database/sql`, no library needed

```go
db, err = sql.Open("mysql", dsn)
db.SetMaxOpenConns(25)
db.SetMaxIdleConns(5)
db.SetConnMaxLifetime(5 * time.Minute)
err = db.Ping()
```

Where the Flask backend reaches for `mysql.connector.pooling.MySQLConnectionPool` as a distinct feature, Go's standard `database/sql` package pools connections natively; `sql.Open` doesn't even connect immediately, it just prepares a pool that connects lazily on first use. `SetConnMaxLifetime(5 * time.Minute)` recycles connections periodically rather than letting them live forever, which avoids the same class of "silently dead connection" problem v1's `tcp_keepalive` fix addresses on the Secrets Manager side. `db.Ping()` forces one real connection immediately at startup so a broken configuration fails fast instead of surfacing on the first user request.

The schema creation that follows (`CREATE TABLE IF NOT EXISTS recipes ...`) is byte-for-byte the same table shape v1 creates. Both backends read and write the same rows in the same database, which is what makes the canary comparison meaningful in the first place.

### 4. The routes: `get_recipe`, `add_recipe`

```go
func getRecipes(w http.ResponseWriter, r *http.Request) {
	rows, _ := db.Query("SELECT id, name, email, recipe_name, ingredients, description_main, created_at FROM recipes ORDER BY id DESC")
	// scan into a slice of Recipe structs, using sql.NullString for nullable text columns
	json.NewEncoder(w).Encode(recipes)
}

func addRecipe(w http.ResponseWriter, r *http.Request) {
	var data map[string]string
	json.NewDecoder(r.Body).Decode(&data)
	db.Exec(`INSERT INTO recipes (name, email, recipe_name, ingredients, description_main) VALUES (?, ?, ?, ?, ?)`,
		data["name"], data["email"], data["recipe_name"], data["ingredients"], data["description_main"])
}
```

Same shape as the Flask routes, same `?` placeholder parameterised query (Go's `database/sql` escapes these itself, exactly like the Python connector: no hand-built SQL strings, no injection surface). `sql.NullString` is used for the two columns that can be empty (`ingredients`, `description_main`) because Go, unlike Python, distinguishes `NULL` from an empty string at the type level, scanning a `NULL` column straight into a plain `string` would panic.

CORS is hand-rolled rather than pulled in from a library, since the whole policy is one function:

```go
func enableCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		if r.Method == "OPTIONS" { w.WriteHeader(http.StatusOK); return }
		next.ServeHTTP(w, r)
	}
}
```

used as `http.HandleFunc("/api/get_recipe", enableCORS(getRecipes))`, a middleware wrapper, which is essentially Go pattern for "run this logic before every request" without a framework.

---

## The probe split — the most important design decision in this service

```go
// livenessCheck is shallow: proves the process/HTTP server is up without touching the DB.
func livenessCheck(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
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
}

// in main():
http.HandleFunc("/health", healthCheck)
http.HandleFunc("/livez", livenessCheck)
```

The Flask backend gets away with a single `/health` endpoint serving both liveness and readiness checks, because Flask's `/health` never touches the database — it's shallow by design. This Go backend's `/health` is **deep**: it actively calls `db.Ping()`, which sends a real packet to RDS and waits for a real reply. That's the right thing for a **readiness** check to do: "should the load balancer or the Kubernetes Service send this pod traffic right now?" is exactly the question `db.Ping()` answers.

It is the wrong thing for a **liveness** check to do, and the reason why is specific to this project's database: `infrastructure/02-aws-rds` runs RDS in **Multi-AZ**, which means a failover whether from an AWS maintenance event, a patch, or an actual fault, is a routine, expected event that makes the database briefly unreachable for roughly 60–120 seconds while the standby is promoted. If `/health` were wired to both readiness and liveness (copying v1's pattern), then during every one of those routine failovers:

1. `db.Ping()` fails (correctly — the DB really is unreachable right now).
2. The **liveness** probe sees that failure and concludes the process itself is broken, not just temporarily unable to reach a dependency.
3. The orchestrator kills and restarts the pod to "fix" it.
4. The new pod boots, tries to connect, and because the failover is still in progress, fails again, and gets killed again.
5. This repeats for the entire failover window, across every replica, at the same time — because they're all pinging the same database and all fail together.

The project's internal shorthand for this is **"container assassination"**: a health check that's too aggressive turns a transient, self-resolving\_ database event into a self-inflicted, fleet-wide outage that can easily outlast the original failover, because the pods never stay up long enough to notice the database has recovered.

The fix is the split above: `/livez` answers only "is the HTTP server itself running?" — something that stays true throughout a database failover, it's the only thing wired to **liveness**. `/health` stays wired to **readiness** only. Now, during a failover the pod is correctly marked "don't send this one traffic," is left running (not restarted), and automatically flips back to ready the moment `db.Ping()` succeeds again — no restart, no crash loop, no compounding outage.

> **The rule this project follows everywhere a v2 manifest is written:** never copy v1's
> single-endpoint probe block onto a v2 deployment. Always wire liveness to the shallow endpoint and
> readiness to the deep one. See `infrastructure/05-aws-k8s/README.md` for how this is actually
> expressed in the Kubernetes Deployment's `livenessProbe` / `readinessProbe` blocks.

## Retry-on-boot, same resilience pattern as v1

```go
func main() {
	for i := 0; i < 3; i++ {
		if err := initDB(); err == nil { break }
		log.Printf("⚠️ Attempt %d failed, retrying in 5 seconds...", i+1)
		time.Sleep(5 * time.Second)
	}
	http.HandleFunc("/health", healthCheck)
	http.HandleFunc("/livez", livenessCheck)
	http.HandleFunc("/api/get_recipe", enableCORS(getRecipes))
	http.HandleFunc("/api/add_recipe", enableCORS(addRecipe))
	log.Fatal(http.ListenAndServe("0.0.0.0:5000", nil))
}
```

Three attempts, five seconds apart, mirroring the Flask backend's boot sequence. Just as in v1, a failure here doesn't stop the process from starting. It starts serving `/livez` immediately either way; `/health` (and therefore readiness) will correctly report "not ready" via the `db == nil` branch until a request finally succeeds in reconnecting, which is exactly the self-healing behaviour the probe split above is designed to allow.

## The Dockerfile

```dockerfile
FROM golang:1.26-alpine AS builder
RUN curl -sS --fail -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
COPY go.mod go.sum ./
RUN go mod download
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -o server main.go

FROM alpine:latest
RUN addgroup -S ritualuser && adduser -S ritualuser -G ritualuser
COPY --from=builder /build/server /app/server
COPY --from=builder /build/global-bundle.pem /app/global-bundle.pem
RUN chown root:root /app/global-bundle.pem && chmod 444 /app/global-bundle.pem
RUN chown -R ritualuser:ritualuser /app && chmod 755 /app
USER ritualuser
EXPOSE 5000
CMD ["./server"]
```

- **`CGO_ENABLED=0`** produces a fully static binary with no dynamic C library dependencies, this is what lets the runtime stage be a bare `alpine` image rather than needing the Go toolchain or any shared libraries present at all.
- **No process manager needed.** Where the Flask image runs Gunicorn in front of the app because Flask's own dev server isn't production-grade, Go's `net/http` server (`http.ListenAndServe`) is already the production server, there's no equivalent extra layer to add here.
- **Same certificate hardening as v1**: the RDS CA bundle is downloaded at build time, owned by `root` and made read-only (`chmod 444`), and the process runs as a dedicated non-root `ritualuser`. This is identical reasoning to `apps/v1-backend-flask`'s Dockerfile, just expressed in Alpine's `addgroup`/`adduser` instead of Debian's `groupadd`/`useradd`.

The result is a considerably smaller image than the Flask equivalent: no Python interpreter, no `pip` packages, just one compiled binary and one certificate file.

## `go.mod` at a glance

```
module ritual-roast-backend
go 1.26.2

require (
	github.com/aws/aws-sdk-go-v2/config
	github.com/aws/aws-sdk-go-v2/service/secretsmanager
	github.com/go-sql-driver/mysql
)
```

Three direct dependencies (everything else in `go.sum` is a transitive dependency of the AWS SDK). Go's standard library covers the HTTP server, JSON encoding, and TLS configuration that Flask needed `flask`, `flask-cors`, and `gunicorn` for.

## Where this fits in the bigger picture

This is the **v2 / challenger** half of a backend comparison, paired with `apps/v2-frontend-vite` and running only on `infrastructure/05-aws-k8s`. It was purpose-built for the Istio canary exercises and was never deployed to `infrastructure/04-aws-ecs`. It answers exactly the same two data routes as `apps/v1-backend-flask` against the same RDS database, which is what makes it possible to shift live traffic between the two and compare them meaningfully — see `infrastructure/05-aws-k8s/README.md` for how the canary, blue-green, and shadow (mirrored-traffic) strategies actually work, and why the backend shadow mode is GET-only (mirroring a `POST` would double-insert every recipe submission into the one shared database both versions write to).
