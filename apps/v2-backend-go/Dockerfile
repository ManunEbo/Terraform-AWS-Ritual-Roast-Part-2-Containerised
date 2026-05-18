# --- STAGE 1: Builder ---
FROM golang:1.21-alpine AS builder
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
FROM alpine:latest
WORKDIR /app

# Create a non-root user for security
RUN addgroup -S ritualuser && adduser -S ritualuser -G ritualuser

# Copy the compiled binary and the SSL certificate from the builder stage
COPY --from=builder /build/server /app/server
COPY --from=builder /build/global-bundle.pem /app/global-bundle.pem

# Enforce secure permissions
RUN chown root:root /app/global-bundle.pem && chmod 444 /app/global-bundle.pem
RUN chown -R ritualuser:ritualuser /app && chmod 755 /app

USER ritualuser
EXPOSE 5000

# Run the compiled binary directly
CMD ["./server"]
