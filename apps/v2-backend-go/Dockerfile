# --- STAGE 1: Builder ---
FROM golang:1.26-alpine AS builder
WORKDIR /build

# Install curl to fetch the RDS SSL bundle
RUN apk add --no-cache curl
RUN curl -sS --fail -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# Copy module files and download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy the source code
COPY main.go .

# Compile the Go app into a statically linked binary named 'server'
RUN CGO_ENABLED=0 GOOS=linux go build -o server main.go

# --- STAGE 2: Runner (The Micro-Image) ---
# Pinned base image: a fixed version gives reproducible builds; "latest" can
# change underneath us between builds.
FROM alpine:3.24
WORKDIR /app

# Create a non-root user for security
RUN addgroup -S ritualuser && adduser -S ritualuser -G ritualuser

# Copy the compiled binary and the SSL certificate from the builder stage.
# COPY creates both owned by root: the app user can run and read them, but
# cannot change them.
COPY --from=builder /build/server /app/server
COPY --from=builder /build/global-bundle.pem /app/global-bundle.pem

# Hardened permissions: root owns /app and everything in it.
#  - Directories 755, files 644, the server binary stays executable (755).
#  - Certificate 444: read-only for everyone, root included.
# Because root also owns the DIRECTORY, the app user cannot delete or replace
# the binary or the certificate. Directory ownership controls delete and rename.
RUN chmod -R u=rwX,go=rX /app && chmod 444 /app/global-bundle.pem

USER ritualuser
EXPOSE 5000

# Run the compiled binary directly
CMD ["./server"]