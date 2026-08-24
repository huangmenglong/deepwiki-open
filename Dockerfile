# syntax=docker/dockerfile:1-labs

# ---------------------------------------------------------------------------
# Build-time network overrides for intranet / corporate environments.
# Defaults keep the public build unchanged; pass --build-arg to adapt, e.g.:
#   docker build --build-arg NPM_REGISTRY=https://registry.npmmirror.com \
#                --build-arg APT_MIRROR=http://10.0.0.1/debian \
#                --build-arg HTTP_PROXY=http://proxy:8080 ... .
# ---------------------------------------------------------------------------

# Directory holding custom CA certificates (e.g. corporate TLS-interception
# roots). Files placed here are trusted by npm/pip during the build and by the
# runtime container. The directory is git-ignored; absent = no-op.
ARG CUSTOM_CERT_DIR="certs"

# npm / PyPI registries
ARG NPM_REGISTRY="https://registry.npmjs.org"
ARG PYPI_INDEX_URL="https://pypi.org/simple"
ARG PIP_TRUSTED_HOST=""

# Corporate HTTP(S) proxy (used by npm / pip / poetry during the build).
ARG HTTP_PROXY=""
ARG HTTPS_PROXY=""
ARG NO_PROXY=""

# Debian apt mirror (base images are Debian bookworm). Point at a LAN/intranet
# mirror when deb.debian.org is unreachable.
ARG APT_MIRROR="http://deb.debian.org/debian"
ARG APT_SECURITY_MIRROR="http://deb.debian.org/debian-security"
ARG DEBIAN_CODENAME="bookworm"

# Debian-based node image whose `node` binary is copied into the runtime image
# (avoids the external nodesource apt repository).
ARG NODE_RUNTIME_IMAGE="node:20-bookworm-slim"

FROM node:20-alpine3.22 AS node_base

# ---- Build the Next.js standalone app ----
FROM node_base AS node_deps
WORKDIR /app
COPY package.json package-lock.json ./

# Inject a custom CA bundle (no-op when the certs/ directory is absent). Node
# only warns, never fails, if the CA file is missing.
ARG CUSTOM_CERT_DIR
RUN if [ -n "${CUSTOM_CERT_DIR}" ] && [ -d "${CUSTOM_CERT_DIR}" ]; then \
        mkdir -p /certs && cp -r "${CUSTOM_CERT_DIR}"/. /certs/ 2>/dev/null || true; \
    fi
ENV NODE_EXTRA_CA_CERTS=/certs/ca-certificates.crt

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ENV HTTP_PROXY=${HTTP_PROXY}
ENV HTTPS_PROXY=${HTTPS_PROXY}
ENV NO_PROXY=${NO_PROXY}

ARG NPM_REGISTRY
RUN npm ci --legacy-peer-deps --registry="${NPM_REGISTRY}"

FROM node_base AS node_builder
WORKDIR /app
COPY --from=node_deps /app/node_modules ./node_modules
# Copy only necessary files for Next.js build
COPY package.json package-lock.json next.config.ts tsconfig.json tailwind.config.js postcss.config.mjs ./
COPY src/ ./src/
COPY public/ ./public/
# Increase Node.js memory limit for build and disable telemetry
ENV NODE_OPTIONS="--max-old-space-size=4096"
ENV NEXT_TELEMETRY_DISABLED=1
RUN NODE_ENV=production npm run build

# ---- Build the Python environment ----
FROM python:3.11-slim-bookworm AS py_deps
WORKDIR /api
COPY api/pyproject.toml .
COPY api/poetry.lock .

ARG APT_MIRROR
ARG APT_SECURITY_MIRROR
ARG DEBIAN_CODENAME
# Point apt at the configured mirror so `ca-certificates` can be installed.
RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources \
        /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list 2>/dev/null || true; \
    printf 'deb %s %s main\ndeb %s %s-updates main\ndeb %s %s-security main\n' \
        "${APT_MIRROR}" "${DEBIAN_CODENAME}" \
        "${APT_MIRROR}" "${DEBIAN_CODENAME}" \
        "${APT_SECURITY_MIRROR}" "${DEBIAN_CODENAME}" > /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Inject the custom CA bundle into the system trust store so pip/poetry can
# verify TLS through a corporate proxy. No-op when certs/ is absent.
ARG CUSTOM_CERT_DIR
RUN if [ -n "${CUSTOM_CERT_DIR}" ] && [ -d "${CUSTOM_CERT_DIR}" ]; then \
        cp -r "${CUSTOM_CERT_DIR}"/. /usr/local/share/ca-certificates/ 2>/dev/null || true; \
        update-ca-certificates; \
    fi

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ENV HTTP_PROXY=${HTTP_PROXY}
ENV HTTPS_PROXY=${HTTPS_PROXY}
ENV NO_PROXY=${NO_PROXY}

ARG PYPI_INDEX_URL
ARG PIP_TRUSTED_HOST
# Note: `poetry config repositories.pypi.url` is intentionally NOT set here -
# poetry 2.0.1 crashes with "unhashable type: 'dict'" when the pypi source URL
# is explicitly configured. Poetry's default source (pypi.org) is already used.
RUN python -m pip install poetry==2.0.1 --no-cache-dir \
        ${PIP_TRUSTED_HOST:+--trusted-host "${PIP_TRUSTED_HOST}"} \
        --index-url "${PYPI_INDEX_URL}" && \
    poetry config virtualenvs.create true --local && \
    poetry config virtualenvs.in-project true --local && \
    poetry config virtualenvs.options.always-copy --local true && \
    POETRY_MAX_WORKERS=10 poetry install --no-interaction --no-ansi --only main && \
    poetry cache clear --all .

# ---- Debian-based node runtime (glibc) to copy into the final image ----
FROM ${NODE_RUNTIME_IMAGE} AS node_runtime

# ---- Final runtime image ----
FROM python:3.11-slim-bookworm

# Set working directory
WORKDIR /app

ARG APT_MIRROR
ARG APT_SECURITY_MIRROR
ARG DEBIAN_CODENAME
# Point apt at the configured mirror and install the runtime tools (git for
# cloning, subversion for SVN checkouts, curl for the healthcheck).
RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources \
        /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list 2>/dev/null || true; \
    printf 'deb %s %s main\ndeb %s %s-updates main\ndeb %s %s-security main\n' \
        "${APT_MIRROR}" "${DEBIAN_CODENAME}" \
        "${APT_MIRROR}" "${DEBIAN_CODENAME}" \
        "${APT_SECURITY_MIRROR}" "${DEBIAN_CODENAME}" > /etc/apt/sources.list && \
    apt-get update && apt-get install -y \
        curl \
        git \
        subversion \
        ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Update certificates if custom ones were provided and copied successfully
ARG CUSTOM_CERT_DIR
RUN if [ -n "${CUSTOM_CERT_DIR}" ] && [ -d "${CUSTOM_CERT_DIR}" ]; then \
        cp -r "${CUSTOM_CERT_DIR}"/. /usr/local/share/ca-certificates/ 2>/dev/null || true; \
        update-ca-certificates; \
        echo "Custom certificates installed successfully."; \
    else \
        echo "No custom certs provided; using default CA store."; \
    fi

# Node.js runtime (copied from a Debian-based node image; avoids the external
# nodesource apt repository).
COPY --from=node_runtime /usr/local/bin/node /usr/local/bin/node
COPY --from=node_runtime /usr/local/bin/npm /usr/local/bin/npm
COPY --from=node_runtime /usr/local/bin/npx /usr/local/bin/npx
COPY --from=node_runtime /usr/local/lib/node_modules /usr/local/lib/node_modules

ENV PATH="/opt/venv/bin:$PATH"
ENV TIKTOKEN_CACHE_DIR=/opt/tiktoken_cache/

# Copy Python dependencies
COPY --from=py_deps /api/.venv /opt/venv
# Pre-seed the tiktoken BPE cache (may need the proxy on intranet networks).
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
RUN mkdir -p "$TIKTOKEN_CACHE_DIR" && \
    HTTP_PROXY=${HTTP_PROXY} HTTPS_PROXY=${HTTPS_PROXY} NO_PROXY=${NO_PROXY} \
    python -c "import tiktoken; tiktoken.get_encoding('cl100k_base')"
COPY api/ ./api/

# Copy Node app
COPY --from=node_builder /app/public ./public
COPY --from=node_builder /app/.next/standalone ./
COPY --from=node_builder /app/.next/static ./.next/static

# Expose the port the app runs on
EXPOSE 8001 3000

# Create a script to run both backend and frontend
RUN echo '#!/bin/bash\n\
# Load environment variables from .env file if it exists\n\
if [ -f .env ]; then\n\
  export $(grep -v "^#" .env | xargs -r)\n\
fi\n\
\n\
# Check for required environment variables\n\
if [ -z "$OPENAI_API_KEY" ] && [ -z "$GOOGLE_API_KEY" ]; then\n\
  echo "Warning: neither OPENAI_API_KEY nor GOOGLE_API_KEY is set."\n\
  echo "DeepWiki needs at least one LLM/embedding credential to function."\n\
  echo "For intranet deployments, set OPENAI_API_KEY and point OPENAI_BASE_URL"\n\
  echo "at your internal OpenAI-compatible gateway (see .env.example)."\n\
fi\n\
\n\
# Start the API server in the background with the configured port\n\
python -m api.main --port ${PORT:-8001} &\n\
PORT=3000 HOSTNAME=0.0.0.0 node server.js &\n\
wait -n\n\
exit $?' > /app/start.sh && chmod +x /app/start.sh

# Set environment variables
ENV PORT=8001
ENV NODE_ENV=production
ENV SERVER_BASE_URL=http://localhost:${PORT:-8001}

# Create empty .env file (will be overridden if one exists at runtime)
RUN touch .env

# Command to run the application
CMD ["/app/start.sh"]
