# V1 Backend — Flask

This is the original ("v1") backend for Ritual Roast: a small, deliberately simple Python/Flask API
that stores and serves recipe submissions from a MySQL database (Amazon RDS). It's the **baseline**
service that the newer Go backend (`apps/v2-backend-go`) is measured against during the
canary / blue-green / shadow-traffic exercises described in `infrastructure/05-aws-k8s` — same job,
same database, same three routes, different language and runtime characteristics.

If you've never worked with a decoupled frontend/backend web app before: think of this as the
"kitchen" behind the "dining room" (the Next.js frontend, `apps/v1-frontend-nextjs`). The frontend
never touches the database directly — it asks this Flask service for recipes, and this service is
the *only* thing that ever opens a connection to MySQL.

## What's in this directory

| File | Purpose |
|---|---|
| `app.py` | The entire backend: routes, database connection pooling, AWS Secrets Manager integration, health checks. |
| `Dockerfile` | Multi-stage build that turns `app.py` into a small, non-root, production container image. |
| `requirements.txt` | Pinned Python dependencies. |

## The request path

```
Next.js Server Action  /  Vite's nginx proxy
        │  HTTP, JSON
        ▼
Flask app.py  (port 5000)
        │  fetches DB creds once, then pooled TCP over TLS
        ▼
AWS Secrets Manager  ── credentials only, fetched at boot + on demand
        │
        ▼
Amazon RDS for MySQL  (port 3306, TLS-verified)
```

Nothing in this file ever receives traffic directly from the internet — it always sits behind an
internal load balancer (ECS) or a cluster-internal Service (Kubernetes), and is only ever called by
the frontend, server-side. That's a deliberate security boundary: the database credentials and the
private network path never reach the browser.

---

## Walking through `app.py`

`app.py` is organised as one linear script: configure logging → build the Flask app → fetch secrets
→ pool the database connection → define routes → run. Below is what each part does and, more
importantly, *why* it's built that way.

### 1. Logging, configured for CloudWatch

```python
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)
```

Anything printed with `print()` is just a string with no structure. `logger.info(...)` instead
produces a timestamped, leveled line:

```
2026-07-15 16:28:15,312 - INFO - Flask application started successfully!
```

- **`level=logging.INFO`** sets the noise floor. The severity order is
  `DEBUG < INFO < WARNING < ERROR < CRITICAL`; setting `INFO` means routine chatter (`DEBUG`) is
  suppressed but everything operationally relevant still comes through.
- **`getLogger(__name__)`** tags every line with the module it came from. It makes no visible
  difference with one file today, but it means log lines stay attributable if this ever grows into
  several modules.
- In production this stream is captured by the container runtime — ECS's `awslogs` driver, or on
  Kubernetes whatever scrapes stdout/stderr from the pod — and lands in CloudWatch. That's why the
  comment says "CloudWatch-friendly" rather than "writes a log file": a log file would die with the
  container the moment it's replaced.

### 2. Building the Flask app and locking down CORS

```python
app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": os.getenv("FRONTEND_URL", "*")}})
```

`Flask(__name__)` assembles the application object every route attaches to (`@app.route(...)`) — it
doesn't start a server yet, that happens at the very bottom of the file.

CORS (Cross-Origin Resource Sharing) exists because the frontend and this backend are **different
origins** (different host/port). Browsers refuse to let JavaScript on one origin read a response
from another unless the server explicitly allows it — this is what stops a random website from
silently reading data from other services you happen to be logged into. `flask-cors` adds the
`Access-Control-Allow-*` response headers that grant a *specific* origin (read from the
`FRONTEND_URL` environment variable, injected by whichever platform is running the container)
permission to read `/api/*` responses. In this app the browser never actually calls this backend
directly — v1's frontend calls it server-side, v2's frontend calls it through an nginx proxy — so
this CORS rule is defence in depth rather than the primary security boundary. It costs nothing to
keep correct.

> **Note:** the `"*"` fallback (no origin restriction) only works for *credential-less* requests.
> If a future version of this API needs cookies or auth headers, `FRONTEND_URL` must be set to a
> concrete origin and `supports_credentials=True` added — browsers reject the wildcard for
> credentialed calls.

### 3. Fetching database credentials from Secrets Manager, not the environment

```python
def get_mysql_secrets():
    region = os.getenv("AWS_REGION", "eu-west-2")
    secret_arn = os.getenv("SECRET_ARN")
    if not secret_arn:
        logger.error("❌ SECRET_ARN environment variable is missing!")
        return None

    boto3_config = Config(
        region_name=region,
        tcp_keepalive=True,
        retries={'max_attempts': 3, 'mode': 'standard'}
    )
    session = boto3.Session()
    client = session.client(service_name="secretsmanager", config=boto3_config)

    try:
        response = client.get_secret_value(SecretId=secret_arn)
        return json.loads(response["SecretString"])
    except Exception as e:
        logger.error(f"❌ Error fetching secrets: {e}")
        return None
```

The database username, password, host and port are **never baked into the image or set as plain
environment variables**. Only one thing is injected at deploy time: `SECRET_ARN`, a pointer to where
the real credentials live in AWS Secrets Manager (see `infrastructure/02-aws-rds`). At startup, the
app uses its IAM role — attached to the ECS task or the Kubernetes node, never a static access key —
to fetch the actual secret. That buys three things:

- Credentials can be rotated automatically (see the RDS layer's rotation Lambda) without ever
  touching this container.
- Nobody reading the Terraform, the container definition, or a `docker inspect` ever sees a
  password — only an ARN.
- If the IAM role is missing or misconfigured, this fails loudly (the `SECRET_ARN` log, or the
  exception log) instead of silently falling back to something insecure.

Two small but consequential details in the `boto3_config`:

- **`tcp_keepalive=True`** — without this, a connection that's idle long enough gets silently
  dropped by a NAT gateway or VPC endpoint, and the *next* request just hangs until the OS notices.
  This is a fix for a real production symptom (an idle connection to the Secrets Manager VPC
  endpoint going dead), and it applies equally whether this container is running on ECS Fargate or a
  Kubernetes pod — it isn't ECS-specific despite living next to some Fargate-flavoured comments
  elsewhere in the file (see "Where this fits" below).
- **`retries={'max_attempts': 3, 'mode': 'standard'}`** — absorbs the odd transient network blip
  with boto3's built-in exponential backoff instead of failing the whole boot on the first hiccup.

### 4. Connection pooling (and why it matters more than it looks)

```python
db_pool = mysql.connector.pooling.MySQLConnectionPool(
    pool_name="ritual_pool",
    pool_size=5,
    host=secrets["host"],
    user=secrets["username"],
    password=secrets["password"],
    database=secrets["dbname"],
    port=int(secrets.get("port", 3306)),
    autocommit=True,
    connection_timeout=5,
    ssl_ca='/app/global-bundle.pem',
    ssl_verify_cert=True
)
```

Opening a fresh TCP + MySQL authentication handshake for every single request is expensive, and it
doesn't scale: MySQL can only hold a finite number of connections open, so under any real load a
naive "connect per request" design starts queueing, then times out, then falls over — taking the
whole app down with it. A **pool** solves this by opening `pool_size=5` connections once, handing
them out to whichever request needs one, and returning them to the pool (not closing them) when the
request finishes.

- **`autocommit=True`** — every `INSERT`/`UPDATE` is committed immediately; this app has no need for
  multi-statement transactions, so there's no reason to hold one open.
- **`connection_timeout=5`** — fail fast rather than hang if the database is unreachable.
- **`ssl_ca='/app/global-bundle.pem'` + `ssl_verify_cert=True`** — MySQL traffic is plaintext by
  default. Traffic between this container and RDS on port 3306 is encrypted, and the server
  certificate is verified against Amazon's RDS CA bundle (baked into the image at build time — see
  the Dockerfile below), so credentials and recipe data can't be read by anything sniffing the
  network path.

Once the pool exists, it's used to confirm — and lazily create — the schema:

```python
cursor.execute("""
    CREATE TABLE IF NOT EXISTS recipes (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        email VARCHAR(255) NOT NULL,
        recipe_name VARCHAR(255) NOT NULL,
        ingredients TEXT,
        description_main TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
""")
```

This is intentionally idempotent (`IF NOT EXISTS`) — the app can boot against a brand-new database or
an existing one without a separate migration step.

### 5. Starting the pool, with retries, at import time

```python
def startup_db_connection():
    for attempt in range(3):
        if init_connection_pool():
            return True
        logger.warning(f"⚠️ Attempt {attempt+1} failed, retrying in 5 seconds...")
        time.sleep(5)
    logger.error("❌ CRITICAL: DB connection failed after retries.")
    return False

startup_db_connection()
```

This call sits at module level, so it runs the moment Gunicorn imports `app.py` — before the process
ever accepts a request. RDS isn't always instantly reachable the moment a container starts (a
Multi-AZ failover, a cold VPC endpoint, a security group still propagating), so the app gives it
three tries, five seconds apart, before giving up. Critically, it does **not** crash the process if
all three fail — it logs a critical error and moves on, because the routes themselves have a
second safety net (next section) that can still recover later without the whole container needing
to be replaced.

### 6. `GET /api/get_recipe` — reading recipes, with self-healing

```python
@app.route('/api/get_recipe', methods=['GET'])
def get_recipes():
    global db_pool
    if not db_pool:
        logger.warning("⚠️ Database pool not found during GET. Attempting reconnection...")
        if not init_connection_pool():
            return jsonify({"error": "DB not ready"}), 503

    try:
        conn = db_pool.get_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM recipes ORDER BY id DESC")
        rows = cursor.fetchall()

        recipes = [{
            'id': r['id'],
            'name': r['name'],
            'email': r['email'],
            'recipe_name': r['recipe_name'],
            'ingredients': r['ingredients'],
            'recipe_details': r['description_main'],  # renamed to match the frontend's field name
            'created_at': r['created_at'].isoformat() if r['created_at'] else None
        } for r in rows]

        cursor.close()
        conn.close()
        return jsonify(recipes)
    except Exception as e:
        logger.error(f"Error fetching recipes: {e}")
        return jsonify({"error": str(e)}), 500
```

Two things worth calling out:

1. **The reconnect guard.** If `startup_db_connection()` gave up earlier (say, RDS was mid-failover
   during boot), the pool is `None` — but rather than every request failing forever, the very next
   `GET` retries the connection itself. A transient outage at boot becomes self-healing instead of
   requiring someone to notice and restart the container.
2. **The field rename.** The database column is `description_main`; the frontend expects
   `recipe_details`. That translation happens here, in the API layer, so the database schema and the
   frontend's data contract are free to evolve independently of each other.

### 7. `POST /api/add_recipe` — writing a new submission

```python
@app.route('/api/add_recipe', methods=['POST'])
def add_recipe():
    ...
    data = request.get_json()
    query = """
        INSERT INTO recipes (name, email, recipe_name, ingredients, description_main)
        VALUES (%s, %s, %s, %s, %s)
    """
    cursor.execute(query, (
        data.get('name'), data.get('email'), data.get('recipe_name'),
        data.get('ingredients'), data.get('description_main')
    ))
```

Same reconnect guard as the `GET` route. The detail worth noticing is the **`%s` placeholders passed
as a tuple**, rather than an f-string building raw SQL text. The MySQL connector parameterises the
query and escapes the values itself — that's what prevents SQL injection. Nothing in this route ever
trusts the request body as anything other than data, no matter what a submitter types into the
recipe form.

### 8. `GET /health` — deliberately shallow

```python
@app.route('/health')
def health_check():
    """
    Only proves the network and Flask server are alive.
    Do NOT check the DB here to avoid ALB container assassination.
    """
    return "OK", 200
```

This is the one route that intentionally does almost nothing. It doesn't touch the database — it
only proves the process is running and can answer HTTP requests at all. That's a deliberate design
choice, not an oversight: if this check *did* call the database, and RDS was mid-failover (routine on
a Multi-AZ instance — see `infrastructure/02-aws-rds`), the load balancer or orchestrator would see
the health check fail, conclude the container is broken, and kill and restart it — right as the
database was about to recover on its own. There's a name for that failure mode in this project's
notes: **"container assassination."** Because this endpoint is shallow, v1 can safely reuse the
*same* `/health` route for both **liveness** ("is the process alive?") and **readiness** ("should
traffic be sent here?") checks, on whichever platform is running it — an ECS target-group health
check or a Kubernetes probe.

This choice matters more once you compare it with the Go rewrite: `apps/v2-backend-go`'s `/health` is
*deep* — it calls `db.Ping()` — which is fine for readiness but would trigger exactly the crash-loop
described above if it were also wired to liveness. That's why v2 ships a second, shallow `/livez`
endpoint instead of copying this single-endpoint pattern. See that app's README for the full
contract.

---

## The Dockerfile: a small, non-root, TLS-ready image

The build is two stages, so that compilers and build tooling never ship in the image that actually
runs in production.

```dockerfile
FROM python:3.11-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends build-essential gcc curl
RUN curl -sS --fail -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt
```

**Stage 1 (`builder`)** installs a C compiler (some Python wheels need one to build), downloads
Amazon's RDS certificate bundle once at build time, and installs the pinned dependencies into the
invoking user's local site-packages (`--user`) so the whole tree can be copied into the next stage.

```dockerfile
FROM python:3.11-slim AS runner
RUN groupadd -r ritualuser && useradd -r -g ritualuser ritualuser
COPY --from=builder /root/.local /home/ritualuser/.local
COPY --from=builder /build/global-bundle.pem /app/global-bundle.pem
COPY . .
RUN chown root:root /app/global-bundle.pem && chmod 444 /app/global-bundle.pem
RUN chown -R ritualuser:ritualuser /app && chmod 755 /app
USER ritualuser
EXPOSE 5000
CMD ["gunicorn", "--worker-tmp-dir", "/dev/shm", "--bind", "0.0.0.0:5000", "--workers", "4", "--threads", "2", "app:app"]
```

**Stage 2 (`runner`)** starts from a clean, slim base with no build tools at all — smaller image,
smaller attack surface. It copies over only the already-built dependencies, the RDS certificate, and
the application code.

- **Non-root by construction.** A dedicated `ritualuser` is created and the process runs as that
  user (`USER ritualuser`), never root. If the app were ever compromised, the attacker doesn't
  inherit root inside the container.
- **The certificate is read-only even to the app's own user** (`chmod 444`, owned by `root:root`) —
  the app can read it to verify RDS's certificate, but nothing running as `ritualuser` can tamper
  with it.
- **Gunicorn, not Flask's built-in server.** The `app.run(...)` call at the bottom of `app.py` only
  ever executes when the file is run directly (`python app.py`) for local development. In the
  container, Gunicorn is the real WSGI server, running 4 worker processes × 2 threads each so the
  app can serve several requests concurrently instead of one at a time.
  `--worker-tmp-dir /dev/shm` puts Gunicorn's internal heartbeat files in memory rather than the
  container's (often small, sometimes disk-backed) `/tmp` — a fix for a known class of Gunicorn
  worker-timeout false positives on constrained filesystems.

## `requirements.txt` at a glance

```
Flask==3.1.0                     # the web framework
flask-cors==5.0.0                # CORS headers for /api/*
gunicorn==23.0.0                 # production WSGI server
mysql-connector-python==9.1.0    # MySQL driver + connection pooling
boto3==1.35.0 / botocore==1.35.0 # AWS SDK (Secrets Manager)
python-dotenv==1.0.1             # .env loading for local development
```

Every dependency is pinned to an exact version, not a range — a deliberate choice so a rebuild six
months from now produces the same behaviour as the one tested today, rather than silently picking up
a breaking change from a dependency's minor release.

## Where this fits in the bigger picture

This service is deployment-target-agnostic: the exact same image is run by **both**
`infrastructure/04-aws-ecs` (as a Fargate task behind an internal ALB) **and**
`infrastructure/05-aws-k8s` (as a Kubernetes Deployment behind an Istio-meshed Service) — never both
at once. A few comments still in this file say things like "Fargate" or "Internal ALB Target Group"
even when the container is running on Kubernetes; that's shared-image drift left over from ECS being
the first platform this app ran on, not a bug — the behaviour underneath (a shallow health check, a
platform-neutral TCP keepalive fix) is correct on both.

It's the **v1 / baseline** half of a v1-vs-v2 comparison: `apps/v2-backend-go` implements the same
three routes against the same database, in Go, so the team can see how a rewrite performs under
Istio traffic-shifting — canary, blue-green, and shadow/mirrored traffic. See
`infrastructure/05-aws-k8s/README.md` for how that traffic is actually split between the two.
