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

# Copy libraries AND the SSL certificate from the builder.
# COPY creates everything owned by root, which is what we want:
# the app user can read and run its code, but cannot change it.
COPY --from=builder /root/.local /home/ritualuser/.local
COPY --from=builder /build/global-bundle.pem /app/global-bundle.pem
COPY . .

ENV PATH=/home/ritualuser/.local/bin:$PATH
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Hardened permissions: root owns /app and everything in it.
#  - Directories 755, files 644: the app user can read and traverse, never write.
#    (Normalised here so files copied from the build machine can't arrive
#    unreadable, e.g. 600, or writable by others.)
#  - Certificate 444: read-only for everyone, root included.
# Because root also owns the DIRECTORY, the app user cannot delete or replace
# the certificate either. Directory ownership controls delete and rename.
RUN chmod -R u=rwX,go=rX /app && chmod 444 /app/global-bundle.pem

USER ritualuser
EXPOSE 5000

CMD ["gunicorn", "--worker-tmp-dir", "/dev/shm", "--bind", "0.0.0.0:5000", "--workers", "4", "--threads", "2", "app:app"]