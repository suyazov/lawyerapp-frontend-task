#!/usr/bin/env bash
# Shared helpers for managed Kimi systemd scopes. This file must not print secrets.

kimi_sanitize() {
  printf '%s' "$1" | tr '/:' '--' | tr -cd '[:alnum:]_.-'
}

kimi_scope_name() {
  local repository="$1" task_id="$2" run_id="$3" repo task digest
  repo="$(kimi_sanitize "$repository")"; repo="${repo:0:32}"
  task="$(kimi_sanitize "$task_id")"; task="${task:0:24}"
  digest="$(printf '%s\0%s\0%s' "$repository" "$task_id" "$run_id" | sha256sum | cut -c1-12)"
  printf 'kimi-job-%s-%s-%s.scope\n' "$repo" "$task" "$digest"
}

kimi_state_init() {
  KIMI_RUN_STATE_ROOT="${KIMI_RUN_STATE_ROOT:-/var/lib/kimi-runs-state}"
  KIMI_RUN_EVENTS="${KIMI_RUN_EVENTS:-$KIMI_RUN_STATE_ROOT/events.jsonl}"
  install -d -m 0700 -o root -g root "$KIMI_RUN_STATE_ROOT"
  touch "$KIMI_RUN_EVENTS"
  chmod 0600 "$KIMI_RUN_EVENTS"
}

kimi_timestamp() { date --iso-8601=seconds; }

kimi_event() {
  local event="$1" repository="$2" task_id="$3" run_id="$4" scope_name="$5" reason="${6:-}"
  kimi_state_init
  jq -cn \
    --arg event "$event" --arg repository "$repository" --arg task_id "$task_id" \
    --arg run_id "$run_id" --arg scope_name "$scope_name" --arg timestamp "$(kimi_timestamp)" \
    --arg reason "$reason" \
    '{event:$event,repository:$repository,task_id:$task_id,run_id:$run_id,scope_name:$scope_name,timestamp:$timestamp,reason:$reason}' \
    >> "$KIMI_RUN_EVENTS"
}

kimi_record_update() {
  local record="$1" filter="$2" tmp
  shift 2
  tmp="${record}.tmp.$$"
  jq "$@" "$filter" "$record" > "$tmp"
  chmod 0600 "$tmp"
  chown root:root "$tmp"
  mv "$tmp" "$record"
}

kimi_scope_control_group() {
  systemctl show "$1" -p ControlGroup --value 2>/dev/null || true
}

kimi_scope_pids() {
  local scope="$1" cg
  cg="$(kimi_scope_control_group "$scope")"
  [ -n "$cg" ] && [ -d "/sys/fs/cgroup$cg" ] || return 0
  find "/sys/fs/cgroup$cg" -name cgroup.procs -type f -exec cat {} + 2>/dev/null | sort -un
}

kimi_scope_pid_count() {
  kimi_scope_pids "$1" | awk 'NF {n++} END {print n+0}'
}

kimi_scope_is_managed() {
  local description
  description="$(systemctl show "$1" -p Description --value 2>/dev/null || true)"
  [[ "$description" == 'Kimi managed job;'* ]]
}

kimi_scope_terminate() {
  local scope="$1" grace="${2:-30}" repository="$3" task_id="$4" run_id="$5" count i
  count="$(kimi_scope_pid_count "$scope")"
  [ "$count" -gt 0 ] || return 0
  systemctl kill --kill-who=all --signal=TERM "$scope" 2>/dev/null || true
  kimi_event scope_term_sent "$repository" "$task_id" "$run_id" "$scope" "pids=$count"
  for ((i=0; i<grace; i++)); do
    [ "$(kimi_scope_pid_count "$scope")" -eq 0 ] && break
    sleep 1
  done
  count="$(kimi_scope_pid_count "$scope")"
  if [ "$count" -gt 0 ]; then
    systemctl kill --kill-who=all --signal=KILL "$scope" 2>/dev/null || true
    kimi_event scope_kill_sent "$repository" "$task_id" "$run_id" "$scope" "pids=$count"
    for ((i=0; i<10; i++)); do
      [ "$(kimi_scope_pid_count "$scope")" -eq 0 ] && break
      sleep 1
    done
  fi
  [ "$(kimi_scope_pid_count "$scope")" -eq 0 ] || return 1
  systemctl reset-failed "$scope" >/dev/null 2>&1 || true
  kimi_event scope_empty_confirmed "$repository" "$task_id" "$run_id" "$scope" ''
}
