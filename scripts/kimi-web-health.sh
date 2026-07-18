#!/usr/bin/env bash
set -euo pipefail
URL="${KIMI_WEB_HEALTH_URL:-http://127.0.0.1:5494/}"
TIMEOUT="${KIMI_WEB_HEALTH_TIMEOUT:-5}"
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$URL" || true)"
if [[ "$code" =~ ^[234][0-9][0-9]$ ]]; then
  echo "healthy:http_status=$code"
  exit 0
fi
echo "unhealthy:http_status=${code:-timeout}:port_may_still_be_open" >&2
exit 1
