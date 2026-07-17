#!/usr/bin/env bash
# Validate ACTIVE.md and the active TASK metadata.
# Usage: bash scripts/validate-task-state.sh [pre|post]
set -euo pipefail

cd "$(dirname "$0")/.."
PHASE="${1:-pre}"
ACTIVE="tasks/ACTIVE.md"

fail() { echo "[task-validator] ERROR: $*" >&2; exit 1; }
info() { echo "[task-validator] $*"; }
field() {
  sed -n "s/^$1:[[:space:]]*//p" "$TASK_FILE" | head -1 | xargs \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}
validate_sha_or_null() {
  local name="$1" value="$2"
  if [ -z "$value" ] || [ "$value" = "null" ]; then return 0; fi
  [[ "$value" =~ ^[0-9a-fA-F]{40}$ ]] || fail "$name must be null or an exact 40-character SHA"
  git cat-file -e "$value^{commit}" 2>/dev/null || fail "$name does not exist in git: $value"
}

case "$PHASE" in pre|post) ;; *) fail "phase must be pre or post" ;; esac
[ -f "$ACTIVE" ] || fail "$ACTIVE not found"

TASK_ID="$(grep -oP '(?<=^- ID: `)[^`]+' "$ACTIVE" | head -1 || true)"
TASK_FILE="$(grep -oP '(?<=^- Файл: `)[^`]+' "$ACTIVE" | head -1 || true)"
[ -n "$TASK_ID" ] || fail "ACTIVE.md does not contain an ID"
[ -n "$TASK_FILE" ] || fail "ACTIVE.md does not contain a TASK file"
[ -f "$TASK_FILE" ] || fail "TASK file not found: $TASK_FILE"

FILE_TASK_ID="$(field task_id)"
[ -z "$FILE_TASK_ID" ] && FILE_TASK_ID="$(field id)"
STATUS="$(field status | tr -d '[:space:]')"
BASE_COMMIT="$(field base_commit | tr -d '[:space:]')"
ACTUAL_START_SHA="$(field actual_start_sha | tr -d '[:space:]')"
RESULT_COMMIT="$(field result_commit | tr -d '[:space:]')"

[ "$FILE_TASK_ID" = "$TASK_ID" ] || fail "ACTIVE ID ($TASK_ID) differs from TASK ID ($FILE_TASK_ID)"
case "$STATUS" in
  draft|ready|in_progress|blocked|review|done|cancelled) ;;
  *) fail "invalid status: $STATUS" ;;
esac

validate_sha_or_null base_commit "$BASE_COMMIT"
validate_sha_or_null actual_start_sha "$ACTUAL_START_SHA"
validate_sha_or_null result_commit "$RESULT_COMMIT"

if grep -Eq 'RESULT_COMMIT_PLACEHOLDER|[0-9a-fA-F]{41,}' "$TASK_FILE"; then
  fail "TASK contains a placeholder or a SHA longer than 40 characters"
fi

case "$STATUS" in
  ready|in_progress|blocked|review|done)
    [ -n "$BASE_COMMIT" ] && [ "$BASE_COMMIT" != "null" ] || fail "status=$STATUS requires base_commit"
    ;;
esac
case "$STATUS" in
  in_progress|blocked|review|done)
    [ -n "$ACTUAL_START_SHA" ] && [ "$ACTUAL_START_SHA" != "null" ] || fail "status=$STATUS requires actual_start_sha"
    git merge-base --is-ancestor "$ACTUAL_START_SHA" HEAD || fail "actual_start_sha is not an ancestor of HEAD"
    ;;
esac

if [ "$STATUS" = "review" ] || [ "$STATUS" = "done" ]; then
  [ -n "$RESULT_COMMIT" ] && [ "$RESULT_COMMIT" != "null" ] || fail "status=$STATUS requires result_commit"
  git merge-base --is-ancestor "$RESULT_COMMIT" HEAD || fail "result_commit is not an ancestor of HEAD"
  if [ "$PHASE" = "post" ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse "$RESULT_COMMIT")" ]; then
    fail "result_commit must be followed by a separate metadata commit"
  fi
  REPORT_SHA="$(grep 'Итоговый commit SHA:' "$TASK_FILE" 2>/dev/null | grep -oE '[0-9a-fA-F]{40}' | head -1 | tr '[:upper:]' '[:lower:]' || true)"
  NORMALIZED_RESULT="$(printf '%s' "$RESULT_COMMIT" | tr '[:upper:]' '[:lower:]')"
  if [ -n "$REPORT_SHA" ] && [ "$REPORT_SHA" != "$NORMALIZED_RESULT" ]; then
    fail "report SHA ($REPORT_SHA) differs from result_commit ($NORMALIZED_RESULT)"
  fi
fi

CURRENT_BRANCH="$(git branch --show-current || true)"
if [ "$PHASE" = "post" ] && [ "$STATUS" != "done" ] && [ "$CURRENT_BRANCH" = "main" ]; then
  fail "an executor TASK must not finish directly in main"
fi

info "OK: $TASK_ID status=$STATUS phase=$PHASE branch=${CURRENT_BRANCH:-detached}"
