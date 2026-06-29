FROM node:20-alpine AS builder
WORKDIR /app
# NOTE: package-lock.json must be generated locally (run `npm install` in
#       this app dir) and committed before this build will succeed.
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
RUN rm -rf /usr/share/nginx/html/*
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 3000
CMD ["nginx", "-g", "daemon off;"]
