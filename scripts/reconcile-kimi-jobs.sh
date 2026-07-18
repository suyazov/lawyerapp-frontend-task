#!/usr/bin/env bash
# Reconcile managed records, scopes and locks. Unknown processes are reported, never globally killed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=kimi-lifecycle-lib.sh
source "$SCRIPT_DIR/kimi-lifecycle-lib.sh"
kimi_state_init
STALE_SECONDS="${KIMI_HEARTBEAT_STALE_SECONDS:-180}"
NOW="$(date +%s)"

for record in "$KIMI_RUN_STATE_ROOT"/*.json; do
  [ -f "$record" ] || continue
  scope="$(jq -r '.scope_name // empty' "$record")"
  status="$(jq -r '.status // empty' "$record")"
  repository="$(jq -r '.repository // empty' "$record")"
  task_id="$(jq -r '.task_id // empty' "$record")"
  run_id="$(jq -r '.run_id // empty' "$record")"
  heartbeat="$(jq -r '.last_heartbeat // .started_at // empty' "$record")"
  heartbeat_epoch="$(date -d "$heartbeat" +%s 2>/dev/null || printf '0')"
  pids="$(kimi_scope_pid_count "$scope")"
  if [[ "$status" =~ ^(starting|running)$ ]] && [ "$pids" -eq 0 ]; then
    kimi_record_update "$record" '.status="blocked" | .reason="lost_scope" | .finished_at=$now' --arg now "$(kimi_timestamp)"
    kimi_event run_blocked "$repository" "$task_id" "$run_id" "$scope" lost_scope
    echo "record_without_scope:$run_id"
  elif [ "$pids" -gt 0 ] && { [[ "$status" =~ ^(completed|blocked)$ ]] || [ $((NOW - heartbeat_epoch)) -gt "$STALE_SECONDS" ]; }; then
    if kimi_scope_is_managed "$scope"; then
      reason=terminal_scope_leak; [[ "$status" =~ ^(starting|running)$ ]] && reason=heartbeat_stale
      kimi_scope_terminate "$scope" "${KIMI_SCOPE_GRACE_SECONDS:-30}" "$repository" "$task_id" "$run_id"
      kimi_record_update "$record" '.status="blocked" | .reason=$reason | .finished_at=$now' --arg reason "$reason" --arg now "$(kimi_timestamp)"
      kimi_event reconciliation_cleanup "$repository" "$task_id" "$run_id" "$scope" "$reason"
      echo "cleaned:$scope:$reason"
    fi
  fi
done

while read -r scope _; do
  [ -n "$scope" ] || continue
  matched="$(jq -r --arg scope "$scope" 'select(.scope_name==$scope) | .run_id' "$KIMI_RUN_STATE_ROOT"/*.json 2>/dev/null | head -1 || true)"
  [ -z "$matched" ] || continue
  description="$(systemctl show "$scope" -p Description --value 2>/dev/null || true)"
  if [[ "$description" =~ ^Kimi\ managed\ job\;\ repository=([^;]+)\;\ task_id=([^;]+)\;\ run_id=([^;]+)$ ]]; then
    repository="${BASH_REMATCH[1]}"; task_id="${BASH_REMATCH[2]}"; run_id="${BASH_REMATCH[3]}"
    kimi_scope_terminate "$scope" "${KIMI_SCOPE_GRACE_SECONDS:-30}" "$repository" "$task_id" "$run_id"
    kimi_event reconciliation_cleanup "$repository" "$task_id" "$run_id" "$scope" orphan_managed_scope
    echo "cleaned_orphan_scope:$scope"
  else
    echo "manual_review_required:unowned_scope:$scope" >&2
  fi
done < <(systemctl list-units --type=scope --state=running 'kimi-job-*.scope' --no-legend 2>/dev/null || true)

while read -r pid unit args; do
  [ -n "$pid" ] || continue
  [[ "$unit" == kimi-job-*.scope ]] && continue
  echo "manual_review_required:unmanaged_process:pid=$pid:unit=$unit:command=${args%% *}" >&2
done < <(ps -eo pid=,unit=,args= | grep -E 'kimi-code-worker|chrome-devtools-mcp|python3 -m http.server|php -S|vite|webpack' | grep -vE 'grep -E|reconcile-kimi-jobs' || true)
