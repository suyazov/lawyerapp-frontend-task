#!/usr/bin/env bash
# Run one validated Kimi TASK in one persistent kimi/<TASK-ID> branch and PR.
set -euo pipefail

cd "$(dirname "$0")/.."
if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then export HOME=/root; fi
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

log() { echo "[kimi-task] $*"; }
set_field() {
  local key="$1" value="$2"
  grep -q "^${key}:" "$TASK_FILE" || { log "Missing TASK field: $key"; exit 2; }
  sed -i "0,/^${key}:.*/s||${key}: ${value}|" "$TASK_FILE"
}

ACTIVE="tasks/ACTIVE.md"
TASK_ID="$(grep -oP '(?<=^- ID: `)[^`]+' "$ACTIVE" 2>/dev/null | head -1 || true)"
TASK_FILE="$(grep -oP '(?<=^- Файл: `)[^`]+' "$ACTIVE" 2>/dev/null | head -1 || true)"
if [ -z "$TASK_ID" ] || [ -z "$TASK_FILE" ] || [ ! -f "$TASK_FILE" ]; then
  log "No active TASK; exiting."
  exit 0
fi

VALIDATION="$(./scripts/read-active-task.sh)"
echo "$VALIDATION"
RUNNABLE="$(printf '%s\n' "$VALIDATION" | sed -n 's/^runnable=//p')"
REASON="$(printf '%s\n' "$VALIDATION" | sed -n 's/^reason=//p')"
[ "$RUNNABLE" = "true" ] || { log "Preflight failed: $REASON"; exit 2; }

MODEL="${KIMI_MODEL:-kimi-code/k3}"
[ "$MODEL" = "kimi-code/k3" ] || { log "Unsupported model: $MODEL"; exit 2; }
bash scripts/validate-task-state.sh pre

BRANCH="kimi/$TASK_ID"
BASE_BRANCH="$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -1)"
BASE_BRANCH="${BASE_BRANCH:-main}"
SYNC_DIR="$(mktemp -d /tmp/kimi-task-sync.XXXXXX)"
trap 'rm -rf "$SYNC_DIR"' EXIT
cp "$TASK_FILE" "$SYNC_DIR/task.md"
cp "$ACTIVE" "$SYNC_DIR/ACTIVE.md"

git config user.name "${GIT_AUTHOR_NAME:-kimi-bot}"
git config user.email "${GIT_AUTHOR_EMAIL:-kimi-bot@users.noreply.github.com}"
git fetch origin "$BASE_BRANCH"

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git fetch origin "$BRANCH"
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git checkout "$BRANCH"
    git merge --ff-only "origin/$BRANCH" || { log "Local TASK branch diverged; refusing reset."; exit 3; }
  else
    git checkout -b "$BRANCH" --track "origin/$BRANCH"
  fi

  if ! git merge --no-edit "origin/$BASE_BRANCH"; then
    mapfile -t CONFLICTS < <(git diff --name-only --diff-filter=U)
    for file in "${CONFLICTS[@]}"; do
      if [ "$file" != "$TASK_FILE" ] && [ "$file" != "$ACTIVE" ]; then
        log "Code conflict with $BASE_BRANCH in $file; manual resolution required."
        git merge --abort
        exit 3
      fi
    done
    cp "$SYNC_DIR/task.md" "$TASK_FILE"
    cp "$SYNC_DIR/ACTIVE.md" "$ACTIVE"
    git add "$TASK_FILE" "$ACTIVE"
    git commit --no-edit
  fi

  cp "$SYNC_DIR/task.md" "$TASK_FILE"
  cp "$SYNC_DIR/ACTIVE.md" "$ACTIVE"
  git add "$TASK_FILE" "$ACTIVE"
  if ! git diff --cached --quiet; then
    git commit -m "task($TASK_ID): sync main feedback"
  fi
else
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    log "Local TASK branch exists without a remote branch; refusing reset."
    exit 3
  fi
  git checkout -b "$BRANCH" "origin/$BASE_BRANCH"
fi

[ "$(git branch --show-current)" = "$BRANCH" ] || { log "Unexpected branch"; exit 3; }
ACTUAL_START_SHA="$(git rev-parse HEAD)"
NOW="$(TZ=Europe/Moscow date '+%Y-%m-%d %H:%M MSK')"
set_field status in_progress
set_field worker "$MODEL"
set_field started_at "\"$NOW\""
set_field actual_start_sha "$ACTUAL_START_SHA"
set_field result_commit null
git add "$TASK_FILE"
git commit -m "task($TASK_ID): start iteration"

PROMPT="$(cat <<EOF
Read the canonical regulations listed in AGENTS.md, then AGENTS.md, tasks/WORKFLOW.md, $ACTIVE and $TASK_FILE.

Execute exactly one TASK: $TASK_ID, using model $MODEL.

Rules:
- remain in $BRANCH; do not merge or push main;
- the wrapper owns status=in_progress, actual_start_sha, started_at and result_commit; do not edit these fields;
- change only the allowed TASK scope;
- on a blocker, set status: blocked, document the blocker and stop;
- on success, fill the execution report and set status: review;
- do not write an "Итоговый commit SHA" value; the wrapper records it after the implementation commit;
- do not set done, merge, deploy production, print or commit secrets.
EOF
)"

log "Starting Kimi CLI on $BRANCH (timeout ${KIMI_TIMEOUT:-75m})"
KIMI_EXIT=0
timeout "${KIMI_TIMEOUT:-75m}" kimi --print --model "$MODEL" --work-dir "$PWD" --prompt "$PROMPT" || KIMI_EXIT=$?
log "Kimi exited with code $KIMI_EXIT"

FINAL_STATUS="$(sed -n 's/^status:[[:space:]]*//p' "$TASK_FILE" | head -1 | tr -d '[:space:]')"
if [ "$KIMI_EXIT" -ne 0 ] && [ "$FINAL_STATUS" != "review" ] && [ "$FINAL_STATUS" != "blocked" ]; then
  set_field status blocked
  printf '\n## Блокеры\n\n- Automatic Kimi run exited with code %s. Manual review is required.\n' "$KIMI_EXIT" >> "$TASK_FILE"
  FINAL_STATUS=blocked
fi

git add -A
if ! git diff --cached --quiet; then
  git commit -m "task($TASK_ID): execution result"
fi

FINAL_STATUS="$(sed -n 's/^status:[[:space:]]*//p' "$TASK_FILE" | head -1 | tr -d '[:space:]')"
if [ "$FINAL_STATUS" = "review" ]; then
  IMPLEMENTATION_SHA="$(git rev-parse HEAD)"
  set_field result_commit "$IMPLEMENTATION_SHA"
  set_field finished_at "\"$(TZ=Europe/Moscow date '+%Y-%m-%d %H:%M MSK')\""
  git add "$TASK_FILE"
  git commit -m "task($TASK_ID): record result commit"
elif [ "$FINAL_STATUS" != "blocked" ]; then
  log "TASK ended with unsupported status: $FINAL_STATUS"
  exit 2
fi

bash scripts/validate-task-state.sh post
git push -u origin "$BRANCH"

PR_URL="$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null || true)"
if [ -z "$PR_URL" ]; then
  TITLE="$(sed -n 's/^title:[[:space:]]*//p' "$TASK_FILE" | head -1)"
  PR_URL="$(gh pr create --base "$BASE_BRANCH" --head "$BRANCH" \
    --title "$TASK_ID: ${TITLE:-Kimi task}" \
    --body "Automatic PR for \`$TASK_ID\`. Merge only after Artem/ChatGPT review.")"
fi
log "PR: $PR_URL"
exit "$KIMI_EXIT"
