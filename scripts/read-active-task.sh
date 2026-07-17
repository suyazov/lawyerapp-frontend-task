#!/usr/bin/env bash
# Reads tasks/ACTIVE.md and validates the active TASK preflight.
# Prints task_id / task_file / status / model / runnable / reason.
set -euo pipefail

cd "$(dirname "$0")/.."

ACTIVE="tasks/ACTIVE.md"
TASK_ID=""
TASK_FILE=""
STATUS="none"
MODEL=""
RUNNABLE="false"
REASON="no_active_task"

frontmatter_value() {
  local key="$1" file="$2"
  sed -n "s/^${key}:[[:space:]]*//p" "$file"     | head -1     | xargs     | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

has_regulation() {
  local name="$1" file="$2"
  grep -Fqx "  - $name" "$file"
}

if [ -f "$ACTIVE" ] && ! grep -Fqx 'Нет активной задачи.' "$ACTIVE"; then
  TASK_ID="$(grep -oP '(?<=^- ID: `)[^`]+' "$ACTIVE" | head -1 || true)"
  TASK_FILE="$(grep -oP '(?<=^- Файл: `)[^`]+' "$ACTIVE" | head -1 || true)"

  if [ -n "$TASK_ID" ] && [ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ]; then
    FILE_TASK_ID="$(frontmatter_value task_id "$TASK_FILE")"
    [ -z "$FILE_TASK_ID" ] && FILE_TASK_ID="$(frontmatter_value id "$TASK_FILE")"
    STATUS="$(frontmatter_value status "$TASK_FILE" | tr -d '[:space:]')"
    MODEL="$(frontmatter_value model "$TASK_FILE")"
    REPOSITORY="$(frontmatter_value repository "$TASK_FILE")"
    BRANCH="$(frontmatter_value branch "$TASK_FILE")"
    AFFINE_PROJECT="$(frontmatter_value affine_project "$TASK_FILE")"
    AFFINE_TASK_ID="$(frontmatter_value affine_task_id "$TASK_FILE")"
    CONTEXT_OK="$(frontmatter_value preflight_context "$TASK_FILE")"
    TASKS_OK="$(frontmatter_value preflight_tasks "$TASK_FILE")"
    ACCESS_OK="$(frontmatter_value preflight_access "$TASK_FILE")"
    REGULATIONS_OK="$(frontmatter_value preflight_regulations "$TASK_FILE")"

    if [ "$FILE_TASK_ID" != "$TASK_ID" ]; then
      REASON="task_id_mismatch"
    elif [ "$STATUS" != "ready" ]; then
      REASON="status_not_ready"
    elif [ "$MODEL" != "kimi-code/k3" ]; then
      REASON="model_not_kimi_code_k3"
    elif [ -z "$REPOSITORY" ]; then
      REASON="repository_not_set"
    elif [ "$BRANCH" != "kimi/$TASK_ID" ]; then
      REASON="branch_not_kimi_task_id"
    elif [ -z "$AFFINE_PROJECT" ]; then
      REASON="affine_project_not_set"
    elif [ "$AFFINE_TASK_ID" != "$TASK_ID" ]; then
      REASON="affine_task_id_mismatch"
    elif [ "$CONTEXT_OK" != "true" ]; then
      REASON="context_not_verified"
    elif [ "$TASKS_OK" != "true" ]; then
      REASON="affine_tasks_not_verified"
    elif [ "$ACCESS_OK" != "true" ]; then
      REASON="access_map_or_access_storage_not_verified"
    elif [ "$REGULATIONS_OK" != "true" ]; then
      REASON="canonical_regulations_not_verified"
    elif ! has_regulation "1. Архитектура AFFiNE GitHub Bridge" "$TASK_FILE"       || ! has_regulation "2. Клиентский workflow" "$TASK_FILE"       || ! has_regulation "3. Автоматизация задач ChatGPT GitHub Kimi" "$TASK_FILE"       || ! has_regulation "4. Работа с Kimi" "$TASK_FILE"; then
      REASON="required_regulations_not_listed"
    elif [ "$(grep -c '^## Canonical regulations$' AGENTS.md 2>/dev/null || true)" != "1" ]; then
      REASON="agents_canonical_regulations_count_invalid"
    else
      RUNNABLE="true"
      REASON="ready"
    fi
  elif [ -n "$TASK_ID" ] || [ -n "$TASK_FILE" ]; then
    REASON="active_task_file_missing"
  fi
fi

echo "task_id=$TASK_ID"
echo "task_file=$TASK_FILE"
echo "status=$STATUS"
echo "model=$MODEL"
echo "runnable=$RUNNABLE"
echo "reason=$REASON"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "task_id=$TASK_ID"
    echo "task_file=$TASK_FILE"
    echo "status=$STATUS"
    echo "model=$MODEL"
    echo "runnable=$RUNNABLE"
    echo "reason=$REASON"
  } >> "$GITHUB_OUTPUT"
fi
