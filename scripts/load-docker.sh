#!/usr/bin/env bash
# Load the image from a tar file on an intranet host (no internet required).
# Usage: ./scripts/load-docker.sh [image.tar]
set -euo pipefail
cd "$(dirname "$0")/.."

TAR_FILE="${1:-deepwiki-open.tar}"
if [ ! -f "${TAR_FILE}" ]; then
  echo "!! Image tar not found: ${TAR_FILE}" >&2
  exit 1
fi

echo ">> Loading image from ${TAR_FILE} ..."
docker load -i "${TAR_FILE}"
echo ">> Done. Now copy .env.example to .env, fill in your internal AI/embed"
echo "   endpoints, then run deploy.sh."
