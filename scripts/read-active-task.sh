#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ACTIVE=tasks/ACTIVE.md; TASK_ID=""; TASK_FILE=""; STATUS=none; MODEL=""; RUNNABLE=false; REASON=no_active_task
field(){ sed -n "s/^$1:[[:space:]]*//p" "$2"|head -1|xargs|sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"; }
if [ -f "$ACTIVE" ] && ! grep -Fqx 'Нет активной задачи.' "$ACTIVE"; then
 TASK_ID="$(grep -oP '(?<=^- ID: `)[^`]+' "$ACTIVE"|head -1||true)"; TASK_FILE="$(grep -oP '(?<=^- Файл: `)[^`]+' "$ACTIVE"|head -1||true)"
 if [ -n "$TASK_ID" ] && [ -f "$TASK_FILE" ]; then
  FILE_ID="$(field task_id "$TASK_FILE")"; STATUS="$(field status "$TASK_FILE"|tr -d '[:space:]')"; MODEL="$(field model "$TASK_FILE")"
  REPO="$(field repository "$TASK_FILE")"; BRANCH="$(field branch "$TASK_FILE")"; AFFINE_ID="$(field affine_task_id "$TASK_FILE")"; AFFINE_PROJECT="$(field affine_project "$TASK_FILE")"
  if [ "$FILE_ID" != "$TASK_ID" ]; then REASON=task_id_mismatch
  elif [ "$STATUS" != ready ]; then REASON=status_not_ready
  elif [ "$MODEL" != kimi-code/k3 ]; then REASON=model_not_kimi_code_k3
  elif [ -z "$REPO" ]; then REASON=repository_not_set
  elif [ "$BRANCH" != "kimi/$TASK_ID" ]; then REASON=branch_not_kimi_task_id
  elif [ -z "$AFFINE_PROJECT" ]; then REASON=affine_project_not_set
  elif [ "$AFFINE_ID" != "$TASK_ID" ]; then REASON=affine_task_id_mismatch
  elif [ "$(field preflight_context "$TASK_FILE")" != true ]; then REASON=context_not_verified
  elif [ "$(field preflight_tasks "$TASK_FILE")" != true ]; then REASON=affine_tasks_not_verified
  elif [ "$(field preflight_access "$TASK_FILE")" != true ]; then REASON=access_not_verified
  elif [ "$(field preflight_regulations "$TASK_FILE")" != true ]; then REASON=regulations_not_verified
  elif [ "$(field preflight_executor "$TASK_FILE")" != true ]; then REASON=executor_not_verified
  elif [ "$(field preflight_environment "$TASK_FILE")" != true ]; then REASON=environment_not_verified
  elif ! grep -Fqx '  - 1. Архитектура AFFiNE GitHub Bridge' "$TASK_FILE" || ! grep -Fqx '  - 2. Клиентский workflow' "$TASK_FILE" || ! grep -Fqx '  - 3. Автоматизация задач ChatGPT GitHub Kimi' "$TASK_FILE" || ! grep -Fqx '  - 4. Работа с Kimi' "$TASK_FILE"; then REASON=required_regulations_not_listed
  elif [ "$(grep -c '^## Canonical regulations$' AGENTS.md 2>/dev/null||true)" != 1 ]; then REASON=agents_canonical_regulations_count_invalid
  else RUNNABLE=true; REASON=ready; fi
 else REASON=active_task_file_missing; fi
fi
for pair in "task_id=$TASK_ID" "task_file=$TASK_FILE" "status=$STATUS" "model=$MODEL" "runnable=$RUNNABLE" "reason=$REASON"; do echo "$pair"; done
if [ -n "${GITHUB_OUTPUT:-}" ]; then for pair in "task_id=$TASK_ID" "task_file=$TASK_FILE" "status=$STATUS" "model=$MODEL" "runnable=$RUNNABLE" "reason=$REASON"; do echo "$pair"; done >> "$GITHUB_OUTPUT"; fi
