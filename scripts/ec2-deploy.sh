#!/bin/bash
set -euo pipefail

IMAGE_TAG="${1:?Usage: ec2-deploy.sh <git-sha>}"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$APP_DIR"

if [ ! -f .env ]; then
  echo "Missing $APP_DIR/.env — create it before deploying." >&2
  echo "Required: DOCKERHUB_USERNAME, DOCKERHUB_TOKEN, POSTGRES_*, BACKEND_PORT, FRONTEND_PORT" >&2
  exit 1
fi

if [ ! -f compose.prod.yaml ]; then
  echo "Missing $APP_DIR/compose.prod.yaml" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

FRONTEND_PORT="${FRONTEND_PORT:-3000}"
BACKEND_PORT="${BACKEND_PORT:-5000}"

if [ -z "${DOCKERHUB_USERNAME:-}" ] || [ -z "${DOCKERHUB_TOKEN:-}" ]; then
  echo "DOCKERHUB_USERNAME and DOCKERHUB_TOKEN must be set in .env" >&2
  exit 1
fi

echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin

export DOCKERHUB_USERNAME
export IMAGE_TAG

if ss -ltn 2>/dev/null | grep -q ":${FRONTEND_PORT} "; then
  echo "ERROR: Port ${FRONTEND_PORT} is already in use on this host." >&2
  echo "Set FRONTEND_PORT to a free port in $APP_DIR/.env" >&2
  sudo ss -ltnp 2>/dev/null | grep ":${FRONTEND_PORT} " || true
  exit 1
fi

docker compose -f compose.prod.yaml pull
docker compose -f compose.prod.yaml up -d --remove-orphans

echo "Waiting for application to respond..."
DEPLOY_OK=false
for attempt in $(seq 1 24); do
  if docker compose -f compose.prod.yaml exec -T backend wget -qO- http://127.0.0.1:5000/health 2>/dev/null | grep -q '"status":"healthy"'; then
    if docker compose -f compose.prod.yaml exec -T frontend curl -sf http://127.0.0.1/ >/dev/null 2>&1; then
      DEPLOY_OK=true
      echo "Deploy verified on attempt $attempt"
      break
    fi
  fi
  echo "Attempt $attempt/24 — services not ready yet, waiting 5s..."
  sleep 5
done

docker compose -f compose.prod.yaml ps -a

if [ "$DEPLOY_OK" != "true" ]; then
  echo "=== Deploy verification failed ===" >&2
  for id in $(docker compose -f compose.prod.yaml ps -q); do
    name=$(docker inspect --format='{{.Name}}' "$id" | sed 's/^\///')
    state=$(docker inspect --format='{{.State.Status}}' "$id")
    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$id")
    echo "$name -> state=$state health=$health" >&2
  done
  docker compose -f compose.prod.yaml logs --no-color --tail=100 database >&2
  docker compose -f compose.prod.yaml logs --no-color --tail=100 backend >&2
  docker compose -f compose.prod.yaml logs --no-color --tail=100 frontend >&2
  exit 1
fi

docker image prune -f

echo "Deployed image tag: $IMAGE_TAG"
docker compose -f compose.prod.yaml ps
