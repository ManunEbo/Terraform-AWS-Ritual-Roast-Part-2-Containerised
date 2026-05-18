# --- STAGE 1: Builder ---
FROM python:3.11-slim AS builder
WORKDIR /build

# Add 'curl' to download the cert during the build
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Download the RDS Global Bundle during build
RUN curl -sS --fail -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt



# --- STAGE 2: Runner ---
FROM python:3.11-slim AS runner
RUN groupadd -r ritualuser && useradd -r -g ritualuser ritualuser
WORKDIR /app

# Copy libraries AND the SSL certificate from the builder
COPY --from=builder /root/.local /home/ritualuser/.local
COPY --from=builder /build/global-bundle.pem /app/global-bundle.pem
COPY . .

ENV PATH=/home/ritualuser/.local/bin:$PATH
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Hardened Permissions: Root owns the cert, user can only read it
RUN chown root:root /app/global-bundle.pem && chmod 444 /app/global-bundle.pem
RUN chown -R ritualuser:ritualuser /app && chmod 755 /app

USER ritualuser
EXPOSE 5000

CMD ["gunicorn", "--worker-tmp-dir", "/dev/shm", "--bind", "0.0.0.0:5000", "--workers", "4", "--threads", "2", "app:app"]