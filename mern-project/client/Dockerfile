# syntax=docker/dockerfile:1.6

# ---------- build stage ----------
FROM node:18-alpine AS build

WORKDIR /app

# Install deps first (better layer caching)
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# Build CRA bundle
COPY public ./public
COPY src ./src
# REACT_APP_API_URL is baked at build time. Empty default → relative URLs (proxied by nginx).
ARG REACT_APP_API_URL=""
ENV REACT_APP_API_URL=$REACT_APP_API_URL
RUN npm run build

# ---------- runtime stage ----------
FROM nginx:1.27-alpine AS runtime

# Drop default site and ship our own
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/app.conf

COPY --from=build /app/build /usr/share/nginx/html

# Run nginx as the non-root "nginx" user that ships with the image.
# Pre-create writable dirs and bind on an unprivileged port.
RUN sed -i 's/listen       80;/listen       8080;/g' /etc/nginx/conf.d/app.conf 2>/dev/null || true \
 && chown -R nginx:nginx /var/cache/nginx /var/log/nginx /usr/share/nginx/html \
 && touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid

USER nginx
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/ >/dev/null || exit 1

CMD ["nginx", "-g", "daemon off;"]
