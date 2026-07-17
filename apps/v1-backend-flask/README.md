# V1 Backend Flask

This directory houses the V1 backend flask application. It comprises two files:

1. app.py
   - This concists of the backend logic that handles requests from the frontend and communication to and fro
     with the database.
2. Dockerfile
   - This packages our application into a lean secure lightweight production ready image.

# app.py

This files is a collection of python functions that perform specific tasks:

### 1. Configuring Python built-in logging system

```
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)
```

1. ### 1. setup logging for CloudWatch compatibility

In production backend, using logging is a critical best practice. It provides timestamped, formatted and level-filtered(importance of logs) system logs that are easy to monitor.

```
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
```

This sets up the global rules for how the application outputs messages.

1. **level=logging.INFO:** This sets the severity threshold. Only log messages at this level or higher will be printed.
   - **How it works:** The order is `DEBUG` (lowest) ---> `INFO` ---> `WARNING` ---> `ERROR` ---> `CRITICAL` (highest)
     By setting it to `INFO`, the application will ignore noisy `DEBUG` logs but will capture everything else.
2. **format='...':** This defines exactly what each log line will look like in the console or log files.
   - **%(asctime)s:** inserts a human-readable date and timestamp e.g. `2026-07-15 16:28:15`
   - **%(levelname)s:** Shows the severity level of the message (e.g., `INFO` or `ERROR`).
   - **%(message)s:** The actual message.

```
Python
logger = logging.getLogger(__name__)

``

This creates a dedicated logging "agent" specifically for the file it is written in.
1. **__name__:** This is a special built-in variable that automatically evaluates to the name of the current file or module (e.g. `app` or `__main__`)
2. **Why this is important:** As the project grows into multiple backend files seing a meaningful log message e.g. `INFO - Database connected` is useful
   as it will be unknown which file generated it. However, by using `__name__` every log message is automatically tagged with the exact file it came from

3. **What it looks like in practice:**
   Lets say we have the following log
```

Python
logger.info("Flask application started successfully!")

```

The following will be printed to the log file or terminal

```

Plaintext
2026-07-15 16:28:15,312 - INFO - Flask application started successfully!

```

As can be seen, this is so much easier to read, especially when debugging.

### 2. Instantiating the application

```

app = Flask(**name**)

````

Essentially, this assembles the flask engine but doesn't start it, that comes later (`app.run(host='0.0.0.0', port=5000)`).
  - **Flask:** This is also known as the class constructor, it consists of several python functions grouped under the name flask, hence why we import from flask `from flask import Flask`
  - **app:** This is the object we create, to refer to that instance, it becomes our main application controller. All routes  and configurations will be attached to it e.g. `@app.route('/recipes'`.
  - **__name__:** The built-in python variable that passes the name of the current file/module. In the background `__name__` is associated with the file path `__file__` this helps flask find other related files such as html templates or css static files etc.


### 3. **Cross-Origin Resource Sharing (CORS):**

```python
CORS(app, resources={r"/api/*": {"origins": os.getenv("FRONTEND_URL", "*")}})
````

- In a decoupled architecture, the Next.js frontend and the Flask backend run on **different origins** (different scheme, host, or port — e.g. `http://localhost:3000` vs `http://localhost:5000`). By default, browsers enforce a _same-origin policy_: JavaScript on one origin is not allowed to read responses from another. This protects users — it stops a malicious site from quietly reading data from other services you're logged into.
- CORS is how the backend grants a controlled exception. It tells the browser _which_ other origins are trusted to read its responses. Important: this is a **browser-only** rule. It does not secure the API against non-browser clients (scripts, `curl`, server-to-server calls) — that's what authentication is for. CORS just decides which frontends a browser will let talk to the API.

- **`CORS(app, ...)`** — Attaches the `flask-cors` extension to the Flask app. It adds the necessary `Access-Control-Allow-*` headers to responses so the browser knows the request is permitted.
- **`resources={r"/api/*": {...}}`** — Applies the CORS policy only to routes under `/api/` (e.g. `/api/users`, `/api/orders/42`), leaving other routes untouched.
- **`{"origins": os.getenv("FRONTEND_URL", "*")}`** — Defines which origins are allowed. The value comes from the `FRONTEND_URL` environment variable. In production, set it to the deployed frontend's origin (e.g. `https://app.example.com`) so only that frontend can call the API from a browser. If unset, it falls back to `"*"` (any origin) — convenient for local development.

> **Note:** The `"*"` wildcard cannot be combined with credentialed requests
> (cookies or auth headers) — browsers reject it. If your `/api/*` routes rely
> on cookies or sessions, always set `FRONTEND_URL` to a concrete origin and
> add `supports_credentials=True`.

---

### 4. Retrieve database credentials

**`def get_mysql_secrets()`:**
This function retrieves DB credentials from Secrets Managerat runtime instead of hardcoding them or reading them from local environment variables. Hence this is a more secure way to retrieve DB credentials.

**`db_pool = None`:**

- This is a module(global) level placeholder for a database connection pool that will be created later. Declaring it here ensures that it is in the scope, to be populated later.

**`region = os.getenv("AWS_REGION", "eu-west-2")`:**

- The AWS region is injected into the container at runtime. Above, we retrieve that value from the environment variable and assign it to `region`. If the environment variable is not set then it defaults to `eu-west-2`.

**`secret_arn = os.getenv("SECRET_ARN")`:**

- Like the AWS region, the AWS Secet ARN (Amazon Resource Name) is passed into the container at runtime. This value is retrieved from the environment variable and assigned to `secret_arn`, a local variable.

```
    if not secret_arn:
      logger.error("❌ SECRET_ARN environment variable is missing!")
      return None
```

This ensures that if the ARN is not populated, that event is logged as an error, and returns `None`. This is a more informative fail fast mechanism than a less helpful exception.

**`boto3_config = Config()`:**

- This is a fix that configures Boto3 client to send TCP keepalives to prevent AWS from silently dropping the connection pool.
- **`tcp_keepalive=True`:** This is what actually makes the underlying TCP connection send periodic keep alive packets, so its not mistaken for dead and dropped.

```
        retries = {
          'max_attempts': 3,
          'mode': 'standard'
      }
```

- This is the fix for unpredictable connection time outs with up to 3 automatic retry attempts using boto3's standard backoff strategy.

- **`session = boto3.Session()` / `client = session.client(...)`:**
- This creates an AWS session and a Secrets Manager client configured with the boto3 config above. Note this session is facilitated by an AWS IAM Role with the right policy attached permitting the client to accomplish the following:

```
    try:
      response = client.get_secret_value(SecretId=secret_arn)
      return json.loads(response["SecretString"])
  except Exception as e:
      logger.error(f"❌ Error fetching secrets: {e}")
      return None
```

- Here the client performs a get request, for this to happen, the client assumes the IAM execution role. If the role is absent or has insuffient policies attached, then this throws an error, logs the error and returns `None`.

### 5. db connection pooling

Opening and closing database connections is very costly:

- It creates too many database authentication request for the database to handle, simultaneously, in high traffic
- Since the database can only handle a finite number of connections in additions to the sla for processing database queries this leads to a back log of requests not handled.
- A database can crash due to this pressure leading to the whole application becoming unavailable.
- Note in our setup this would mean each single query must also retrieve database credentials from Secrets Manager, adding to latency cost as well as AWS financial cost.
- Further MySQL traffic on port 3306 is unencrypted, meaning data packets are sent as plain text, any one listening can read it.

Connection pooling mitigates this.

Below is the configuration of connection pooling:

- **`secrets = get_mysql_secrets()`:** Database credentials are fetched once from Secrets Manager then split into the various credentials for `db_pool` configuration, no more latency cost.

```
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

- **`pool_size=5`:** A predetermined number of connections to the database, 5 in our case, are kept open using the credentials retrieved from secrets manager
- All new queries are funneled into these connection pools, once the database processes a query, the connection is not closed it just returns to the pool ready and available
- **`autocommit=True`:** This ensures that every insert or update to the database is made permanent (committed).
- **`connection_timeout=5`:** A connection times out if idle for 5 seconds.
- **`ssl_ca='/app/global-bundle.pem'` & `ssl_verify_cert=True` :** This is used to encrypt the traffic through the connection pool; note, this is not a feature of the connection pooling, rather it is added to it.

- Once the `db_pool` is configured, the configuration can be used to instantiate/establish connection with the database.

```
     conn = db_pool.get_connection()
     cursor = conn.cursor()
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
     cursor.close()
     conn.close()
     logger.info("✅ Database pool initialized and table verified.")
     return True
```

- **`conn = db_pool.get_connection()`** this instantiates the connection using the `db_pool` configuration. Once the connection is established, it's time to test the connection; the cursor executes a create table command to create the database table if it doesn't exist.
- **`cursor.close()` & `conn.close()`** Once the database connection pooling is initialized and the table is verified then the cursor and the connection close; essentially this closes the query but the connection is returned to the pool.
- **`logger.info()`** A message is logged and at this point the connection is a success and the try method returns true (1).
- **`except Exception as e:`** If an error occurs then the it is handled by the exception which logs the incident and exits with false (0)

```
 except Exception as e:
     logger.error(f"❌ Database initialization failed: {e}")
     return False
```

### 6. Start db connection

### 7. Retrieve recipes from db

### 8. Add recipe to db

### 9. health check route
