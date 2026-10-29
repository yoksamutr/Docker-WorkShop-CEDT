# syntax=docker/dockerfile:1.7

# =============================================================================
# Builder stage — installs production dependencies only, on a fresh Node base.
# =============================================================================

FROM node:20.11-slim AS builder

WORKDIR /app

COPY app/package.json app/package-lock.json ./
# Install from the lockfile, then bump transitive deps that have published
# CVE fixes within their semver range (e.g. proxy-addr) so Trivy stays clean.
RUN npm ci --omit=dev  && npm update --omit=dev proxy-addr

COPY app/ ./

# =============================================================================
# Runtime stage — slim final image. Nothing from builder's caches leaks in.
# =============================================================================

FROM node:20.11-slim

# Apply Debian security updates and drop npm/yarn/corepack: the runtime only
# needs `node`, and npm's bundled packages (e.g. tar) carry CRITICAL CVEs.
RUN apt-get update  && apt-get upgrade -y --no-install-recommends  && rm -rf /var/lib/apt/lists/*  && rm -rf /usr/local/lib/node_modules /opt/yarn-*  && rm -f /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack /usr/local/bin/yarn /usr/local/bin/yarnpkg

WORKDIR /app

COPY --from=builder /app /app

ENV NODE_ENV=production
EXPOSE 3000

# node:20.11-slim does NOT ship with curl or wget, so probe with Node's http module.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
  CMD node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode===200?0:1)).on('error', () => process.exit(1))"

CMD ["node", "src/index.js"]
