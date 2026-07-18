#!/usr/bin/env bash
set -uo pipefail
RESULT_FILE="${1:?result file required}"
shift
set +e
"$@"
code=$?
set -e
printf '%s\n' "$code" > "${RESULT_FILE}.tmp"
chmod 0600 "${RESULT_FILE}.tmp"
mv "${RESULT_FILE}.tmp" "$RESULT_FILE"
exit "$code"
