#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."; export PATH="${HOME:-/root}/.local/bin:/usr/local/bin:$PATH"
if [ "${1:-}" != --inside-worktree ]; then
 V="$(./scripts/read-active-task.sh)"; echo "$V"; [ "$(printf '%s\n' "$V"|sed -n 's/^runnable=//p')" = true ]||exit 2
 TASK_ID="$(printf '%s\n' "$V"|sed -n 's/^task_id=//p')"; BASE="${GITHUB_BASE_REF:-main}"
 exec ./scripts/kimi-execution-guard.sh run "$TASK_ID" "kimi/$TASK_ID" "$BASE" auto -- ./scripts/run-kimi-task.sh --inside-worktree
fi
TASK_ID="${KIMI_TASK_ID:?}"; TASK_FILE="${KIMI_TASK_FILE:?}"; BRANCH="${KIMI_TASK_BRANCH:?}"; BASE="${KIMI_BASE_BRANCH:?}"; MODEL="${KIMI_MODEL:-kimi-code/k3}"
[ "$MODEL" = kimi-code/k3 ]||exit 2; ./scripts/validate-task-state.sh pre "$TASK_FILE" "$TASK_ID"
git config user.name "${GIT_AUTHOR_NAME:-kimi-bot}"; git config user.email "${GIT_AUTHOR_EMAIL:-kimi-bot@users.noreply.github.com}"
setf(){ sed -i "0,/^$1:.*/s||$1: $2|" "$TASK_FILE"; }
setf status in_progress; setf worker "$MODEL"; setf actual_start_sha "$(git rev-parse HEAD)"; setf started_at "\"$(TZ=Europe/Moscow date '+%Y-%m-%d %H:%M MSK')\""; setf result_commit null
git add "$TASK_FILE"; git commit -m "task($TASK_ID): start iteration"
PROMPT="Read AGENTS.md, tasks/WORKFLOW.md and $TASK_FILE. Execute only $TASK_ID in this isolated worktree. Keep branch $BRANCH, preserve scope, use model $MODEL, never merge main. On success set review; on a blocker set blocked. Never set done or expose secrets."
code=0; timeout "${KIMI_TIMEOUT:-75m}" kimi --print --afk --model "$MODEL" --work-dir "$PWD" --prompt "$PROMPT"||code=$?
STATUS="$(sed -n 's/^status:[[:space:]]*//p' "$TASK_FILE"|head -1|tr -d '[:space:]')"; if { [ "$code" -ne 0 ]||[ "$STATUS" != review ]; }&&[ "$STATUS" != blocked ]; then setf status blocked; STATUS=blocked; fi
git add -A; git diff --cached --quiet||git commit -m "task($TASK_ID): execution result"
STATUS="$(sed -n 's/^status:[[:space:]]*//p' "$TASK_FILE"|head -1|tr -d '[:space:]')"; if [ "$STATUS" = review ]; then RESULT="$(git rev-parse HEAD)"; setf result_commit "$RESULT"; setf finished_at "\"$(TZ=Europe/Moscow date '+%Y-%m-%d %H:%M MSK')\""; git add "$TASK_FILE"; git commit -m "task($TASK_ID): record result commit"; fi
./scripts/validate-task-state.sh post "$TASK_FILE" "$TASK_ID"; git push origin "HEAD:refs/heads/$BRANCH"
PR="$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null||true)"; [ -n "$PR" ]||PR="$(gh pr create --base "$BASE" --head "$BRANCH" --title "$TASK_ID: Kimi task" --body "Automatic PR for $TASK_ID. Merge only after review.")"; echo "PR: $PR"; exit "$code"
