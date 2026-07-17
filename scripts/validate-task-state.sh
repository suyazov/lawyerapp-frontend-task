#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PHASE="${1:-pre}"; EXPLICIT_FILE="${2:-}"; EXPLICIT_ID="${3:-}"
fail(){ echo "[task-validator] ERROR: $*" >&2; exit 1; }
field(){ sed -n "s/^$1:[[:space:]]*//p" "$TASK_FILE"|head -1|xargs|sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"; }
if [ -n "$EXPLICIT_FILE" ]; then TASK_FILE="$EXPLICIT_FILE"; TASK_ID="$EXPLICIT_ID"; else TASK_ID="$(grep -oP '(?<=^- ID: `)[^`]+' tasks/ACTIVE.md|head -1||true)"; TASK_FILE="$(grep -oP '(?<=^- Файл: `)[^`]+' tasks/ACTIVE.md|head -1||true)"; fi
[ -n "$TASK_ID" ] && [ -f "$TASK_FILE" ] || fail task_not_found
[ "$(field task_id)" = "$TASK_ID" ] || fail task_id_mismatch
[ "$(field model)" = kimi-code/k3 ] || fail model_not_k3
[ "$(field branch)" = "kimi/$TASK_ID" ] || fail branch_mismatch
validate_sha(){ local n="$1" v; v="$(field "$n"|tr -d '[:space:]')"; [ -z "$v" ]||[ "$v" = null ]||{ [[ "$v" =~ ^[0-9a-fA-F]{40}$ ]]||fail "$n invalid"; git cat-file -e "$v^{commit}" 2>/dev/null||fail "$n missing"; }; }
for n in base_commit actual_start_sha result_commit; do validate_sha "$n"; done
STATUS="$(field status|tr -d '[:space:]')"; case "$STATUS" in draft|ready|in_progress|blocked|review|done|cancelled) ;; *) fail "invalid status:$STATUS";; esac
RESULT="$(field result_commit|tr -d '[:space:]')"; if [ "$STATUS" = review ]||[ "$STATUS" = done ]; then [ -n "$RESULT" ]&&[ "$RESULT" != null ]||fail result_commit_required; git merge-base --is-ancestor "$RESULT" HEAD||fail result_not_ancestor; fi
echo "[task-validator] OK: $TASK_ID status=$STATUS phase=$PHASE"
