#!/usr/bin/env bash
# Controlled manual runs use exactly the same guard and lifecycle supervisor.
set -euo pipefail
[ "$#" -ge 6 ] || { echo "usage: $0 TASK-ID BRANCH BASE ENVIRONMENT -- COMMAND..." >&2; exit 2; }
TASK_ID="$1"; BRANCH="$2"; BASE="$3"; ENVIRONMENT="$4"; shift 4
[ "${1:-}" = -- ] || exit 2
shift
KIMI_JOB_KIND=manual exec "$(dirname "$0")/kimi-execution-guard.sh" run "$TASK_ID" "$BRANCH" "$BASE" "$ENVIRONMENT" -- "$@"
