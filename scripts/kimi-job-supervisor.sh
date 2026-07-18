#!/usr/bin/env bash
# Owns one Kimi run from systemd scope creation through process cleanup.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=kimi-lifecycle-lib.sh
source "$SCRIPT_DIR/kimi-lifecycle-lib.sh"

usage() {
  echo "usage: $0 name REPOSITORY TASK-ID RUN-ID | run REPOSITORY TASK-ID RUN-ID BRANCH WORKTREE ENVIRONMENT KIND PROJECT_LOCK ENV_LOCK -- COMMAND..." >&2
  exit 2
}

[ "$#" -gt 0 ] || usage
MODE="$1"; shift
if [ "$MODE" = name ]; then
  [ "$#" -eq 3 ] || usage
  kimi_scope_name "$1" "$2" "$3"
  exit 0
fi
[ "$MODE" = run ] || usage
[ "$#" -ge 11 ] || usage
REPOSITORY="$1"; TASK_ID="$2"; RUN_ID="$3"; BRANCH="$4"; WORKTREE="$5"; ENVIRONMENT="$6"; KIND="$7"; PROJECT_LOCK="$8"; ENV_LOCK="$9"
[[ "$RUN_ID" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "invalid_run_id" >&2; exit 2; }
shift 9
[ "${1:-}" = -- ] || usage
shift
[ "$#" -gt 0 ] || usage

SCOPE_NAME="$(kimi_scope_name "$REPOSITORY" "$TASK_ID" "$RUN_ID")"
STATE_ROOT="${KIMI_RUN_STATE_ROOT:-/var/lib/kimi-runs-state}"
CAPACITY_ROOT="${KIMI_CAPACITY_ROOT:-/var/lock/kimi-capacity}"
WORKER_LIMIT="${KIMI_WORKER_LIMIT:-4}"
HEARTBEAT_SECONDS="${KIMI_HEARTBEAT_SECONDS:-15}"
GRACE_SECONDS="${KIMI_SCOPE_GRACE_SECONDS:-30}"
case "$KIND" in
  primary) TIMEOUT_SECONDS="${KIMI_TIMEOUT_PRIMARY:-4500}" ;;
  feedback) TIMEOUT_SECONDS="${KIMI_TIMEOUT_FEEDBACK:-4500}" ;;
  manual) TIMEOUT_SECONDS="${KIMI_TIMEOUT_MANUAL:-3600}" ;;
  test) TIMEOUT_SECONDS="${KIMI_TIMEOUT_TEST:-60}" ;;
  *) echo "invalid_job_kind:$KIND" >&2; exit 2 ;;
esac
[[ "$WORKER_LIMIT" =~ ^[1-9][0-9]*$ ]] || exit 2
[[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || exit 2

kimi_state_init
install -d -m 0700 -o root -g root "$CAPACITY_ROOT"
RECORD="$STATE_ROOT/$RUN_ID.json"
RESULT_FILE="$STATE_ROOT/.result-$RUN_ID"
STARTED_AT="$(kimi_timestamp)"
START_EPOCH="$(date +%s)"

exec 7>"$CAPACITY_ROOT/.allocation.lock"
flock 7
SLOT_FD=''
SLOT=''
for ((slot=1; slot<=WORKER_LIMIT; slot++)); do
  exec {candidate_fd}>"$CAPACITY_ROOT/slot-$slot.lock"
  if flock -n "$candidate_fd"; then SLOT_FD="$candidate_fd"; SLOT="$slot"; break; fi
  eval "exec ${candidate_fd}>&-"
done
ACTIVE_SCOPES="$(systemctl list-units --type=scope --state=running 'kimi-job-*.scope' --no-legend 2>/dev/null | awk 'NF {n++} END {print n+0}')"
if [ -z "$SLOT_FD" ] || [ "$ACTIVE_SCOPES" -ge "$WORKER_LIMIT" ]; then
  flock -u 7
  jq -n --arg repository "$REPOSITORY" --arg task_id "$TASK_ID" --arg run_id "$RUN_ID" \
    --arg branch "$BRANCH" --arg worktree "$WORKTREE" --arg scope_name "$SCOPE_NAME" \
    --arg started_at "$STARTED_AT" --arg environment "$ENVIRONMENT" \
    '{repository:$repository,task_id:$task_id,run_id:$run_id,branch:$branch,worktree:$worktree,scope_name:$scope_name,main_pid:null,started_at:$started_at,started_by:"capacity-guard",last_heartbeat:$started_at,status:"blocked",reason:"worker_capacity_exhausted",environment:$environment}' \
    > "$RECORD"
  chmod 0600 "$RECORD"; chown root:root "$RECORD"
  kimi_event run_blocked "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" worker_capacity_exhausted
  printf 'status=blocked\nreason=worker_capacity_exhausted\n' >&2
  exit 79
fi
flock -u 7

jq -n --arg repository "$REPOSITORY" --arg task_id "$TASK_ID" --arg run_id "$RUN_ID" \
  --arg branch "$BRANCH" --arg worktree "$WORKTREE" --arg scope_name "$SCOPE_NAME" \
  --arg started_at "$STARTED_AT" --arg started_by "${GITHUB_ACTOR:-${USER:-root}}" \
  --arg environment "$ENVIRONMENT" --arg kind "$KIND" --argjson main_pid "$$" --argjson slot "$SLOT" \
  '{repository:$repository,task_id:$task_id,run_id:$run_id,branch:$branch,worktree:$worktree,scope_name:$scope_name,main_pid:$main_pid,started_at:$started_at,started_by:$started_by,last_heartbeat:$started_at,status:"starting",reason:"",environment:$environment,kind:$kind,capacity_slot:$slot,git_state:"unchecked"}' \
  > "$RECORD"
chmod 0600 "$RECORD"; chown root:root "$RECORD"
SUPERVISOR_FINISHED=false
emergency_cleanup() {
  $SUPERVISOR_FINISHED && return 0
  systemctl kill --kill-who=all --signal=CONT "$SCOPE_NAME" 2>/dev/null || true
  kimi_scope_terminate "$SCOPE_NAME" "$GRACE_SECONDS" "$REPOSITORY" "$TASK_ID" "$RUN_ID" || true
  if [ -f "$RECORD" ]; then
    kimi_record_update "$RECORD" '.status="blocked" | .reason="supervisor_interrupted" | .finished_at=$finished | .last_heartbeat=$finished' \
      --arg finished "$(kimi_timestamp)" || true
  fi
  kimi_event run_blocked "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" supervisor_interrupted || true
}
trap emergency_cleanup EXIT INT TERM
LOCK_METADATA="$(jq -c '{run_id,scope_name,main_pid,task_id,repository,worktree,started_at}' "$RECORD")"
printf '%s\n' "$LOCK_METADATA" > "$PROJECT_LOCK"
[ -z "$ENV_LOCK" ] || printf '%s\n' "$LOCK_METADATA" > "$ENV_LOCK"
kimi_event run_started "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" "kind=$KIND;slot=$SLOT"

DESCRIPTION="Kimi managed job; repository=$REPOSITORY; task_id=$TASK_ID; run_id=$RUN_ID"
set +e
systemd-run --quiet --scope --unit="$SCOPE_NAME" --property="Description=$DESCRIPTION" -- \
  "$SCRIPT_DIR/kimi-job-command-wrapper.sh" "$RESULT_FILE" "$@" &
SYSTEMD_RUN_PID=$!
set -e
kimi_record_update "$RECORD" '.status="running" | .last_heartbeat=$heartbeat' --arg heartbeat "$(kimi_timestamp)"
kimi_event scope_created "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" "systemd_run_pid=$SYSTEMD_RUN_PID"

TIMED_OUT=false
while [ ! -s "$RESULT_FILE" ]; do
  NOW_EPOCH="$(date +%s)"
  if [ $((NOW_EPOCH - START_EPOCH)) -ge "$TIMEOUT_SECONDS" ]; then TIMED_OUT=true; break; fi
  if ! kill -0 "$SYSTEMD_RUN_PID" 2>/dev/null && [ "$(kimi_scope_pid_count "$SCOPE_NAME")" -eq 0 ]; then break; fi
  kimi_record_update "$RECORD" '.last_heartbeat=$heartbeat' --arg heartbeat "$(kimi_timestamp)"
  kimi_event heartbeat "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" ''
  sleep "$HEARTBEAT_SECONDS"
done

if $TIMED_OUT; then
  systemctl kill --kill-who=all --signal=STOP "$SCOPE_NAME" 2>/dev/null || true
  COMMAND_CODE=124
  REASON=executor_timeout
else
  COMMAND_CODE="$(cat "$RESULT_FILE" 2>/dev/null || printf '1')"
  [[ "$COMMAND_CODE" =~ ^[0-9]+$ ]] || COMMAND_CODE=1
  REASON="command_exit_$COMMAND_CODE"
fi
kimi_event command_finished "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" "$REASON"

GIT_STATE=not_a_worktree
if git -C "$WORKTREE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HEAD="$(git -C "$WORKTREE" rev-parse HEAD)"
  DIRTY="$(git -C "$WORKTREE" status --porcelain)"
  REMOTE_HEAD="$(git -C "$WORKTREE" ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | awk 'NR==1 {print $1}' || true)"
  if [ -n "$DIRTY" ]; then GIT_STATE=unpushed_dirty
  elif [ -n "$REMOTE_HEAD" ] && [ "$HEAD" = "$REMOTE_HEAD" ]; then GIT_STATE=confirmed_push
  else GIT_STATE=unpushed_commit
  fi
fi
kimi_record_update "$RECORD" '.git_state=$git_state' --arg git_state "$GIT_STATE"
kimi_event git_state_checked "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" "$GIT_STATE"
if [[ "$GIT_STATE" == unpushed_* ]]; then
  kimi_event worktree_preserved "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" "$GIT_STATE"
fi

systemctl kill --kill-who=all --signal=CONT "$SCOPE_NAME" 2>/dev/null || true
if ! kimi_scope_terminate "$SCOPE_NAME" "$GRACE_SECONDS" "$REPOSITORY" "$TASK_ID" "$RUN_ID"; then
  kimi_record_update "$RECORD" '.status="blocked" | .reason="scope_cleanup_failed" | .last_heartbeat=$heartbeat' --arg heartbeat "$(kimi_timestamp)"
  kimi_event run_blocked "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" scope_cleanup_failed
  printf 'status=blocked\nreason=scope_cleanup_failed\n' >&2
  exit 80
fi
wait "$SYSTEMD_RUN_PID" 2>/dev/null || true
unlink "$RESULT_FILE" 2>/dev/null || true

if $TIMED_OUT; then
  FINAL_STATUS=blocked
elif [ "$COMMAND_CODE" -eq 0 ]; then
  FINAL_STATUS=completed
else
  FINAL_STATUS=blocked
fi
kimi_record_update "$RECORD" '.status=$status | .reason=$reason | .finished_at=$finished | .last_heartbeat=$finished' \
  --arg status "$FINAL_STATUS" --arg reason "$REASON" --arg finished "$(kimi_timestamp)"
if [ "$FINAL_STATUS" = completed ]; then
  kimi_event run_completed "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" "$REASON"
else
  kimi_event run_blocked "$REPOSITORY" "$TASK_ID" "$RUN_ID" "$SCOPE_NAME" "$REASON"
fi
printf 'run_id=%s\nscope_name=%s\ngit_state=%s\nstatus=%s\nreason=%s\n' "$RUN_ID" "$SCOPE_NAME" "$GIT_STATE" "$FINAL_STATUS" "$REASON"
SUPERVISOR_FINISHED=true
exit "$COMMAND_CODE"
