#!/usr/bin/env bash
# Build the DeepWiki Docker image.
#
# NOTE: building requires network access (npm ci + poetry install + base
# images). Build once on an internet-connected machine, then use save-docker.sh
# to transfer the image to your intranet hosts.
#
# Intranet/corporate overrides (all optional, pass as env vars):
#   NPM_REGISTRY=...          npm registry, e.g. https://registry.npmmirror.com
#   HTTP_PROXY/HTTPS_PROXY    corporate proxy used by npm/pip during the build
#   APT_MIRROR=...            Debian apt mirror, e.g. http://10.0.0.1/debian
#   APT_SECURITY_MIRROR=...   Debian security mirror
#   PIP_TRUSTED_HOST=...      pip trusted host for a plain-http mirror
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE_NAME="${IMAGE_NAME:-deepwiki-open:latest}"

args=()
[ -n "${NPM_REGISTRY:-}" ] && args+=(--build-arg NPM_REGISTRY="$NPM_REGISTRY")
[ -n "${HTTP_PROXY:-}" ] && args+=(--build-arg HTTP_PROXY="$HTTP_PROXY")
[ -n "${HTTPS_PROXY:-}" ] && args+=(--build-arg HTTPS_PROXY="$HTTPS_PROXY")
[ -n "${NO_PROXY:-}" ] && args+=(--build-arg NO_PROXY="$NO_PROXY")
[ -n "${APT_MIRROR:-}" ] && args+=(--build-arg APT_MIRROR="$APT_MIRROR")
[ -n "${APT_SECURITY_MIRROR:-}" ] && args+=(--build-arg APT_SECURITY_MIRROR="$APT_SECURITY_MIRROR")
[ -n "${PIP_TRUSTED_HOST:-}" ] && args+=(--build-arg PIP_TRUSTED_HOST="$PIP_TRUSTED_HOST")

echo ">> Building image ${IMAGE_NAME} ..."
docker build "${args[@]}" -t "${IMAGE_NAME}" .
echo ">> Done: ${IMAGE_NAME}"
