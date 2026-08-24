#!/usr/bin/env bash
# Save the built image to a tar file so it can be copied onto an intranet host.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE_NAME="${IMAGE_NAME:-deepwiki-open:latest}"
OUT_FILE="${OUT_FILE:-deepwiki-open.tar}"

echo ">> Saving ${IMAGE_NAME} -> ${OUT_FILE} ..."
docker save -o "${OUT_FILE}" "${IMAGE_NAME}"
echo ">> Done. Transfer ${OUT_FILE} to the intranet host, then run load-docker.sh there."
