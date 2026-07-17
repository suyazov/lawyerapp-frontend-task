#!/usr/bin/env bash
# Читает tasks/ACTIVE.md и файл активной задачи.
# Печатает task_id / task_file / status / runnable в stdout
# и (если задан $GITHUB_OUTPUT) дублирует туда для workflow.
set -euo pipefail

cd "$(dirname "$0")/.."

ACTIVE="tasks/ACTIVE.md"
TASK_ID=""
TASK_FILE=""
STATUS="none"
RUNNABLE="false"

if [ -f "$ACTIVE" ]; then
  TASK_ID="$(grep -oP '(?<=^- ID: `)[^`]+' "$ACTIVE" | head -1 || true)"
  TASK_FILE="$(grep -oP '(?<=^- Файл: `)[^`]+' "$ACTIVE" | head -1 || true)"

  if [ -n "$TASK_ID" ] && [ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ]; then
    STATUS="$(sed -n 's/^status:[[:space:]]*//p' "$TASK_FILE" | head -1 | tr -d '[:space:]')"
    [ "$STATUS" = "ready" ] && RUNNABLE="true"
  else
    TASK_ID=""
    TASK_FILE=""
  fi
fi

echo "task_id=$TASK_ID"
echo "task_file=$TASK_FILE"
echo "status=$STATUS"
echo "runnable=$RUNNABLE"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "task_id=$TASK_ID"
    echo "task_file=$TASK_FILE"
    echo "status=$STATUS"
    echo "runnable=$RUNNABLE"
  } >> "$GITHUB_OUTPUT"
fi
