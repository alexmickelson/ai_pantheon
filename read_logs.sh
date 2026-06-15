#!/usr/bin/env bash
set -euo pipefail

APP_CONTAINER="${APP_CONTAINER:-ai_pantheon-app-1}"
LINES=${LINES:-500}

# Read last N lines of app logs
docker logs "$APP_CONTAINER" --tail "$LINES" 2>&1 || true
