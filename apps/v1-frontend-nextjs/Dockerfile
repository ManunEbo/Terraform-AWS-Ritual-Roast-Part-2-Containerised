# --- STAGE 1: Dependency Manager ---
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Copy package files and install ONLY what is needed to build.
# Deterministic install from the committed lockfile.
# NOTE: package-lock.json must be generated locally (run `npm install` in
#       this app dir) and committed before this build will succeed.
COPY package.json package-lock.json ./
RUN npm ci

# --- STAGE 2: Builder ---
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Next.js telemetry is disabled during build for speed/privacy
ENV NEXT_TELEMETRY_DISABLED=1

# This triggers ESLint, and locks your 3-month contest deadline into the build!
RUN npm run build

# --- STAGE 3: Runner (The "Lean" Final Image) ---
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Create a non-root user for Fargate security
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Set up the Standalone folder structure
COPY --from=builder /app/public ./public

# Ensure the non-root user can write to the cache (vital for Next.js Image Optimization)
RUN mkdir .next
RUN chown nextjs:nodejs .next

# Copy the standalone build and static files
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Switch to the secure non-root user
USER nextjs

EXPOSE 3000
ENV PORT=3000
# Important: Ensure the server listens on all interfaces for the internal ALB
ENV HOSTNAME="0.0.0.0"

# The standalone mode creates a 'server.js' file which is the direct entry point
CMD ["node", "server.js"]