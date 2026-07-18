#!/usr/bin/env bash
# Reconcile run records, managed scopes, lock metadata, linked worktrees and GitHub activity.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=kimi-lifecycle-lib.sh
source "$SCRIPT_DIR/kimi-lifecycle-lib.sh"
kimi_state_init

PROJECT_LOCK_ROOT="${KIMI_PROJECT_LOCK_ROOT:-/var/lock/kimi-projects}"
ENVIRONMENT_LOCK_ROOT="${KIMI_ENVIRONMENT_LOCK_ROOT:-/var/lock/kimi-environments}"
WORKTREE_ROOT="${KIMI_WORKTREE_ROOT:-/var/lib/kimi-worktrees}"
STALE_SECONDS="${KIMI_HEARTBEAT_STALE_SECONDS:-180}"
GRACE_SECONDS="${KIMI_SCOPE_GRACE_SECONDS:-30}"
NOW="$(date +%s)"
install -d -m 0700 -o root -g root "$PROJECT_LOCK_ROOT" "$ENVIRONMENT_LOCK_ROOT" "$WORKTREE_ROOT"

declare -A GITHUB_CACHE
github_activity() {
  local repository="$1" runs prs
  if [ -n "${KIMI_GITHUB_ACTIVITY_OVERRIDE:-}" ]; then
    printf '%s\n' "$KIMI_GITHUB_ACTIVITY_OVERRIDE"
    return 0
  fi
  if [ -n "${GITHUB_CACHE[$repository]+x}" ]; then printf '%s\n' "${GITHUB_CACHE[$repository]}"; return 0; fi
  set +e
  runs="$(gh run list -R "$repository" --limit 30 --json status,name --jq '[.[]|select((.status=="in_progress" or .status=="queued" or .status=="pending") and (.name|test("Kimi";"i")))]|length' 2>/dev/null)"; runs_code=$?
  prs="$(gh pr list -R "$repository" --state open --json headRefName --jq '[.[]|select(.headRefName|startswith("kimi/"))]|length' 2>/dev/null)"; prs_code=$?
  set -e
  if [ "$runs_code" -ne 0 ] || [ "$prs_code" -ne 0 ]; then GITHUB_CACHE[$repository]=error
  elif [ "${runs:-0}" -gt 0 ]; then GITHUB_CACHE[$repository]=workflow
  elif [ "${prs:-0}" -gt 0 ]; then GITHUB_CACHE[$repository]=open_pr
  else GITHUB_CACHE[$repository]=inactive
  fi
  printf '%s\n' "${GITHUB_CACHE[$repository]}"
}

record_for_run() {
  local run_id="$1" record
  for record in "$KIMI_RUN_STATE_ROOT"/*.json; do
    [ -f "$record" ] || continue
    [ "$(jq -r '.run_id // empty' "$record")" = "$run_id" ] && { printf '%s\n' "$record"; return 0; }
  done
  return 1
}

task_status() {
  local worktree="$1" task_id="$2" task_file
  [ -d "$worktree/tasks" ] || { echo unknown; return; }
  task_file="$(find "$worktree/tasks" -maxdepth 1 -type f -name "${task_id}-*.md" -print -quit 2>/dev/null || true)"
  [ -n "$task_file" ] || { echo unknown; return; }
  sed -n 's/^status:[[:space:]]*//p' "$task_file" | head -1 | tr -d '[:space:]'
}

emit_manual_review() {
  local repository="$1" task_id="$2" run_id="$3" scope="$4" reason="$5"
  kimi_event manual_review_required "$repository" "$task_id" "$run_id" "$scope" "$reason"
  echo "manual_review_required:$reason:repository=$repository:task_id=$task_id:run_id=$run_id" >&2
}

worktree_reconcile() {
  local repository="$1" task_id="$2" run_id="$3" scope="$4" branch="$5" worktree="$6" reason_prefix="$7"
  local root_real worktree_real dirty head remote common repo_root
  [ -n "$worktree" ] && [ -d "$worktree" ] || { echo worktree_missing; return 0; }
  root_real="$(realpath -m "$WORKTREE_ROOT")"; worktree_real="$(realpath -m "$worktree")"
  if [[ "$worktree_real" != "$root_real/"* ]] || [ ! -f "$worktree/.git" ]; then
    emit_manual_review "$repository" "$task_id" "$run_id" "$scope" worktree_outside_managed_root
    echo manual_review; return 0
  fi
  if ! git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    emit_manual_review "$repository" "$task_id" "$run_id" "$scope" worktree_not_git
    echo manual_review; return 0
  fi
  dirty="$(git -C "$worktree" status --porcelain)"
  if [ -n "$dirty" ]; then
    kimi_event worktree_preserved "$repository" "$task_id" "$run_id" "$scope" orphan_worktree_unpushed_dirty
    echo orphan_worktree_unpushed_dirty; return 0
  fi
  head="$(git -C "$worktree" rev-parse HEAD)"
  remote="$(git -C "$worktree" ls-remote origin "refs/heads/$branch" 2>/dev/null | awk 'NR==1{print $1}' || true)"
  if [ -z "$remote" ] || [ "$head" != "$remote" ]; then
    kimi_event worktree_preserved "$repository" "$task_id" "$run_id" "$scope" orphan_worktree_unpushed_commit
    echo orphan_worktree_unpushed_commit; return 0
  fi
  common="$(git -C "$worktree" rev-parse --path-format=absolute --git-common-dir)"
  repo_root="$(dirname "$common")"
  git -C "$repo_root" worktree remove --force "$worktree"
  git -C "$repo_root" worktree prune
  kimi_event reconciliation_cleanup "$repository" "$task_id" "$run_id" "$scope" "${reason_prefix:-orphan_worktree_confirmed_push}"
  echo orphan_worktree_confirmed_push
}

lock_reconcile() {
  local lock="$1" expected_run="${2:-}" reason="${3:-stale_lock_without_run}" metadata run_id repository task_id scope pid worktree branch activity record fd
  [ -f "$lock" ] || return 0
  exec {fd}<>"$lock"
  if ! flock -n "$fd"; then eval "exec ${fd}>&-"; echo "active_lock:$lock"; return 0; fi
  metadata="$(cat "$lock" 2>/dev/null || true)"
  if ! jq -e . >/dev/null 2>&1 <<<"$metadata"; then
    flock -u "$fd"; eval "exec ${fd}>&-"; emit_manual_review unknown unknown unknown '' lock_metadata_invalid; return 0
  fi
  run_id="$(jq -r '.run_id // empty' <<<"$metadata")"; repository="$(jq -r '.repository // empty' <<<"$metadata")"
  task_id="$(jq -r '.task_id // empty' <<<"$metadata")"; scope="$(jq -r '.scope_name // empty' <<<"$metadata")"
  pid="$(jq -r '.main_pid // 0' <<<"$metadata")"; worktree="$(jq -r '.worktree // empty' <<<"$metadata")"
  [ -z "$expected_run" ] || [ "$run_id" = "$expected_run" ] || { flock -u "$fd"; eval "exec ${fd}>&-"; emit_manual_review "$repository" "$task_id" "$run_id" "$scope" lock_run_id_conflict; return 0; }
  if [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ] && kill -0 "$pid" 2>/dev/null; then
    flock -u "$fd"; eval "exec ${fd}>&-"; echo "preserved_lock_live_pid:$lock"; return 0
  fi
  if [ "$(kimi_scope_pid_count "$scope")" -gt 0 ]; then
    flock -u "$fd"; eval "exec ${fd}>&-"; echo "preserved_lock_live_scope:$lock"; return 0
  fi
  activity="$(github_activity "$repository")"
  if [ "$activity" != inactive ]; then
    flock -u "$fd"; eval "exec ${fd}>&-"; emit_manual_review "$repository" "$task_id" "$run_id" "$scope" "cleanup_blocked_github_$activity"; return 0
  fi
  record="$(record_for_run "$run_id" 2>/dev/null || true)"
  branch="$(jq -r '.branch // empty' "$record" 2>/dev/null || true)"
  [ -n "$branch" ] || branch="kimi/$task_id"
  worktree_reconcile "$repository" "$task_id" "$run_id" "$scope" "$branch" "$worktree" "$reason" >/dev/null
  unlink "$lock"
  flock -u "$fd" 2>/dev/null || true; eval "exec ${fd}>&-"
  kimi_event reconciliation_cleanup "$repository" "$task_id" "$run_id" "$scope" "$reason"
  echo "cleaned_lock:$lock:$reason"
}

for record in "$KIMI_RUN_STATE_ROOT"/*.json; do
  [ -f "$record" ] || continue
  repository="$(jq -r '.repository // empty' "$record")"; task_id="$(jq -r '.task_id // empty' "$record")"; run_id="$(jq -r '.run_id // empty' "$record")"
  scope="$(jq -r '.scope_name // empty' "$record")"; status="$(jq -r '.status // empty' "$record")"; branch="$(jq -r '.branch // empty' "$record")"
  worktree="$(jq -r '.worktree // empty' "$record")"; heartbeat="$(jq -r '.last_heartbeat // .started_at // empty' "$record")"
  heartbeat_epoch="$(date -d "$heartbeat" +%s 2>/dev/null || printf '0')"; pids="$(kimi_scope_pid_count "$scope")"; activity="$(github_activity "$repository")"
  project_lock="$PROJECT_LOCK_ROOT/$(kimi_sanitize "$repository").lock"
  environment="$(jq -r '.environment // empty' "$record")"; env_lock=''
  [ -z "$environment" ] || [ "$environment" = none ] || env_lock="$ENVIRONMENT_LOCK_ROOT/$(kimi_sanitize "$environment").lock"
  status_task="$(task_status "$worktree" "$task_id")"

  if [[ "$status" =~ ^(starting|running)$ ]] && [ "$pids" -gt 0 ]; then
    lock_run="$(jq -r '.run_id // empty' "$project_lock" 2>/dev/null || true)"
    if [ "$lock_run" = "$run_id" ] && [ -d "$worktree" ] && [[ "$status_task" =~ ^(ready|in_progress|review|unknown)$ ]]; then
      echo "active_run_preserved:$run_id"; continue
    fi
    emit_manual_review "$repository" "$task_id" "$run_id" "$scope" active_run_resource_conflict
    continue
  fi

  if [[ "$status" =~ ^(starting|running)$ ]] && [ "$pids" -eq 0 ]; then
    kimi_record_update "$record" '.status="blocked" | .reason="run_scope_missing" | .finished_at=$now' --arg now "$(kimi_timestamp)"
    kimi_event run_blocked "$repository" "$task_id" "$run_id" "$scope" run_scope_missing
    status=blocked
  fi

  if [ "$pids" -gt 0 ]; then
    if [ "$activity" != inactive ]; then emit_manual_review "$repository" "$task_id" "$run_id" "$scope" "cleanup_blocked_github_$activity"; continue; fi
    if kimi_scope_is_managed "$scope"; then
      reason=completed_task_resources_remaining
      [ $((NOW - heartbeat_epoch)) -le "$STALE_SECONDS" ] || reason=heartbeat_stale
      kimi_scope_terminate "$scope" "$GRACE_SECONDS" "$repository" "$task_id" "$run_id"
      kimi_event reconciliation_cleanup "$repository" "$task_id" "$run_id" "$scope" "$reason"
    else emit_manual_review "$repository" "$task_id" "$run_id" "$scope" unknown_scope_owner; continue
    fi
  fi

  if [ "$activity" = inactive ]; then
    worktree_reconcile "$repository" "$task_id" "$run_id" "$scope" "$branch" "$worktree" completed_task_resources_remaining >/dev/null
    lock_reconcile "$project_lock" "$run_id" completed_task_resources_remaining
    [ -z "$env_lock" ] || lock_reconcile "$env_lock" "$run_id" completed_task_resources_remaining
  elif [ -e "$project_lock" ] || [ -d "$worktree" ]; then
    emit_manual_review "$repository" "$task_id" "$run_id" "$scope" "cleanup_blocked_github_$activity"
  fi
done

for lock in "$PROJECT_LOCK_ROOT"/*.lock "$ENVIRONMENT_LOCK_ROOT"/*.lock; do
  [ -f "$lock" ] || continue
  run_id="$(jq -r '.run_id // empty' "$lock" 2>/dev/null || true)"
  [ -n "$run_id" ] && record_for_run "$run_id" >/dev/null 2>&1 && continue
  lock_reconcile "$lock" '' stale_lock_without_run
done

while read -r scope _; do
  [ -n "$scope" ] || continue
  matched="$(jq -r --arg scope "$scope" 'select(.scope_name==$scope)|.run_id' "$KIMI_RUN_STATE_ROOT"/*.json 2>/dev/null | head -1 || true)"
  [ -z "$matched" ] || continue
  description="$(systemctl show "$scope" -p Description --value 2>/dev/null || true)"
  if [[ "$description" =~ ^Kimi\ managed\ job\;\ repository=([^;]+)\;\ task_id=([^;]+)\;\ run_id=([^;]+)$ ]]; then
    repository="${BASH_REMATCH[1]}"; task_id="${BASH_REMATCH[2]}"; run_id="${BASH_REMATCH[3]}"; activity="$(github_activity "$repository")"
    if [ "$activity" = inactive ]; then
      kimi_scope_terminate "$scope" "$GRACE_SECONDS" "$repository" "$task_id" "$run_id"
      kimi_event reconciliation_cleanup "$repository" "$task_id" "$run_id" "$scope" orphan_scope_without_run
      echo "cleaned_orphan_scope:$scope"
    else emit_manual_review "$repository" "$task_id" "$run_id" "$scope" "cleanup_blocked_github_$activity"
    fi
  else
    emit_manual_review unknown unknown unknown "$scope" unknown_systemd_scope
  fi
done < <(systemctl list-units --type=scope --state=running 'kimi-job-*.scope' --no-legend 2>/dev/null || true)

while read -r pid unit args; do
  [ -n "$pid" ] || continue
  [[ "$unit" == kimi-job-*.scope ]] && continue
  echo "manual_review_required:unmanaged_process:pid=$pid:unit=$unit:command=${args%% *}" >&2
done < <(ps -eo pid=,unit=,args= | grep -E 'kimi-code-worker|chrome-devtools-mcp|python3 -m http.server|php -S|vite|webpack' | grep -vE 'grep -E|reconcile-kimi-jobs' || true)
