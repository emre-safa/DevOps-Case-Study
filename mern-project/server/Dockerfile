# syntax=docker/dockerfile:1.6
FROM node:18-alpine

# tini gives proper signal handling so SIGTERM from K8s reaches Node.
RUN apk add --no-cache tini wget

WORKDIR /app

# Install only production deps from the lockfile
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

# Copy source last for max layer caching
COPY server.mjs loadEnvironment.mjs ./
COPY routes ./routes
COPY db ./db

# Use the unprivileged "node" user that ships with the official image
USER node

ENV NODE_ENV=production \
    PORT=5050

EXPOSE 5050

HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
  CMD wget -qO- http://127.0.0.1:5050/healthcheck/ >/dev/null || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.mjs"]
