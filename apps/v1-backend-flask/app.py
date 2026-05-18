from flask import Flask, jsonify, request
import mysql.connector
from mysql.connector import pooling
from flask_cors import CORS
import json
import boto3
import os
import sys
import time
import logging

# Set up logging for CloudWatch compatibility
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

# 1. CORS: Locked to your frontend via environment variables
CORS(app, resources={r"/api/*": {"origins": os.getenv("FRONTEND_URL", "*")}})

# Global variable for the connection pool
db_pool = None

def get_mysql_secrets():
    """Fetches DB credentials from AWS Secrets Manager using the injected ARN."""
    region = os.getenv("AWS_REGION", "eu-west-2")
    
    # Fetch the exact ARN we injected in tasks.tf
    secret_arn = os.getenv("SECRET_ARN")
    
    if not secret_arn:
        logger.error("❌ SECRET_ARN environment variable is missing!")
        return None
    
    session = boto3.Session()
    client = session.client(service_name="secretsmanager", region_name=region)
    
    try:
        response = client.get_secret_value(SecretId=secret_arn)
        return json.loads(response["SecretString"])
    except Exception as e:
        logger.error(f"❌ Error fetching secrets: {e}")
        return None

def init_connection_pool():
    """Initializes the pool and ensures the table exists."""
    global db_pool
    secrets = get_mysql_secrets()
    if not secrets:
        return False
    
    try:
        # Initialize the Pool (Handles multiple Fargate users)
        db_pool = mysql.connector.pooling.MySQLConnectionPool(
            pool_name="ritual_pool",
            pool_size=5,
            host=secrets["host"],
            user=secrets["username"],
            password=secrets["password"],
            database=secrets["dbname"],
            port=int(secrets.get("port", 3306)),
            autocommit=True,
            # --- SSL ENFORCEMENT START ---
            ssl_ca='/app/global-bundle.pem', 
            ssl_verify_cert=True 
            # --- SSL ENFORCEMENT END ---
        )
        
        # Verify the table exists
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
    except Exception as e:
        logger.error(f"❌ Database initialization failed: {e}")
        return False

def startup_db_connection():
    """Retry logic for initializing the DB connection on container start."""
    for attempt in range(3):
        if init_connection_pool():
            return True
        logger.warning(f"⚠️ Attempt {attempt+1} failed, retrying in 5 seconds...")
        time.sleep(5)
    logger.error("❌ CRITICAL: DB connection failed after retries.")
    return False

# Initialize the DB connection globally so WSGI/Gunicorn catches it.
startup_db_connection()

# --- ROUTES ---

@app.route('/api/get_recipe', methods=['GET'])
def get_recipes():
    if not db_pool:
        return jsonify({"error": "DB not ready"}), 503
    
    try:
        conn = db_pool.get_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM recipes ORDER BY id DESC")
        rows = cursor.fetchall()
        
        # Data Distillation: Align DB column names to Frontend keys
        recipes = [{
            'id': r['id'],
            'name': r['name'],
            'email': r['email'],
            'recipe_name': r['recipe_name'],
            'ingredients': r['ingredients'],
            'recipe_details': r['description_main'], # Match Table.tsx key
            'created_at': r['created_at'].isoformat() if r['created_at'] else None
        } for r in rows]
        
        cursor.close()
        conn.close()
        return jsonify(recipes)
    except Exception as e:
        logger.error(f"Error fetching recipes: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/add_recipe', methods=['POST'])
def add_recipe():
    if not db_pool:
        return jsonify({"error": "DB not ready"}), 503
    
    data = request.get_json()
    try:
        conn = db_pool.get_connection()
        cursor = conn.cursor()
        query = """
            INSERT INTO recipes (name, email, recipe_name, ingredients, description_main)
            VALUES (%s, %s, %s, %s, %s)
        """
        cursor.execute(query, (
            data.get('name'),
            data.get('email'),
            data.get('recipe_name'),
            data.get('ingredients'),
            data.get('description_main')
        ))
        cursor.close()
        conn.close()
        return jsonify({'status': 'success'}), 201
    except Exception as e:
        logger.error(f"Error adding recipe: {e}")
        return jsonify({'error': str(e)}), 400

# --- FIX: Match the Internal ALB Target Group Path ---
@app.route('/health')
def health_check():
    """Fargate Health Check"""
    global db_pool
    # Self-healing: Try to reconnect if the pool died or failed at startup
    if not db_pool:
        init_connection_pool()
        
    if db_pool:
        return "OK", 200
    return "Disconnected", 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)