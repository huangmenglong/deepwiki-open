#!/usr/bin/env bash
# Start DeepWiki via docker compose.
# Requires .env (copy from .env.example and fill in internal AI/embed endpoints).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo ">> No .env found. Copying .env.example -> .env ..."
  cp .env.example .env
  echo "!! Please edit .env and set OPENAI_BASE_URL / DEEPWIKI_EMBED_MODEL /"
  echo "   DEEPWIKI_DEFAULT_MODEL etc., then re-run this script." >&2
  exit 1
fi

if ! docker image inspect deepwiki-open:latest >/dev/null 2>&1; then
  echo "!! Image deepwiki-open:latest is not present locally."
  echo "   On an intranet host, load it first:  ./scripts/load-docker.sh deepwiki-open.tar"
  echo "   (or build it on an internet-connected machine with ./scripts/build-docker.sh)."
fi

echo ">> Starting DeepWiki with docker compose ..."
docker compose up -d

PORT="${PORT:-8001}"
echo ">> DeepWiki is starting."
echo "   Web UI: http://localhost:3000/"
echo "   API:    http://localhost:${PORT}/"
echo "   Logs:   docker compose logs -f deepwiki"
