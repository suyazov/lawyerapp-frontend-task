#!/usr/bin/env bash
# Shared project/environment locks and isolated worktree for every Kimi execution.
set -euo pipefail

[ "${1:-}" = "run" ] || { echo "usage: $0 run TASK-ID BRANCH BASE ENVIRONMENT -- COMMAND..." >&2; exit 2; }
shift
TASK_ID="${1:?task id required}"; BRANCH="${2:?branch required}"; BASE="${3:?base required}"; ENVIRONMENT="${4:-auto}"
shift 4
[ "${1:-}" = "--" ] || { echo "missing -- before command" >&2; exit 2; }
shift
[ "$#" -gt 0 ] || { echo "command required" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel)"
REPOSITORY="${GITHUB_REPOSITORY:-$(git -C "$ROOT" remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##;s#\.git$##')}"
SAFE_REPO="$(printf '%s' "$REPOSITORY" | tr '/:' '--' | tr -cd '[:alnum:]_.-')"
SAFE_TASK="$(printf '%s' "$TASK_ID" | tr -cd '[:alnum:]_.-')"
RUN_KEY="${GITHUB_RUN_ID:-manual}-${GITHUB_RUN_ATTEMPT:-1}-$$"
PROJECT_LOCK_ROOT="${KIMI_PROJECT_LOCK_ROOT:-/var/lock/kimi-projects}"
ENVIRONMENT_LOCK_ROOT="${KIMI_ENVIRONMENT_LOCK_ROOT:-/var/lock/kimi-environments}"
WORKTREE_ROOT="${KIMI_WORKTREE_ROOT:-/var/lib/kimi-worktrees}"
WORKTREE="$WORKTREE_ROOT/$SAFE_REPO/$SAFE_TASK-$RUN_KEY"
mkdir -p "$PROJECT_LOCK_ROOT" "$ENVIRONMENT_LOCK_ROOT" "$(dirname "$WORKTREE")"

exec 9>"$PROJECT_LOCK_ROOT/$SAFE_REPO.lock"
flock -n 9 || {
  printf 'status=blocked\nreason=executor_busy\nlock=project\nrepository=%s\n' "$REPOSITORY" >&2
  exit 75
}

WORKTREE_CREATED=false
REMOVE_WORKTREE=false
PRESERVE_REASON=execution_interrupted
cleanup() {
  $WORKTREE_CREATED || return 0
  if $REMOVE_WORKTREE; then
    git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
    git -C "$ROOT" worktree prune >/dev/null 2>&1 || true
  else
    printf 'status=blocked\nreason=%s\nworktree=%s\n' "$PRESERVE_REASON" "$WORKTREE" >&2
  fi
}
trap cleanup EXIT INT TERM

git -C "$ROOT" fetch origin "$BASE"
if git -C "$ROOT" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git -C "$ROOT" fetch origin "$BRANCH"
  START="origin/$BRANCH"
else
  START="origin/$BASE"
fi
git -C "$ROOT" worktree add --detach "$WORKTREE" "$START" >/dev/null
WORKTREE_CREATED=true
INITIAL_HEAD="$(git -C "$WORKTREE" rev-parse HEAD)"

if [ "$START" != "origin/$BASE" ]; then
  git -C "$WORKTREE" merge --no-edit "origin/$BASE" || {
    PRESERVE_REASON=main_merge_conflict
    printf 'status=blocked\nreason=main_merge_conflict\nbranch=%s\n' "$BRANCH" >&2
    exit 76
  }
fi

TASK_FILE="$(find "$WORKTREE/tasks" -maxdepth 1 -type f -name "${TASK_ID}-*.md" | head -1 || true)"
if [ -z "$TASK_FILE" ]; then
  TASK_FILE="$(grep -oP '(?<=^- Файл: `)[^`]+' "$WORKTREE/tasks/ACTIVE.md" 2>/dev/null | head -1 || true)"
  [ -z "$TASK_FILE" ] || TASK_FILE="$WORKTREE/$TASK_FILE"
fi
[ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ] || { echo "task_file_not_found:$TASK_ID" >&2; exit 2; }

if [ "$ENVIRONMENT" = "auto" ]; then
  ENVIRONMENT="$(sed -n 's/^environment_lock:[[:space:]]*//p' "$TASK_FILE" | head -1 | xargs || true)"
  [ -n "$ENVIRONMENT" ] && [ "$ENVIRONMENT" != "null" ] || ENVIRONMENT="$(sed -n 's/^environment:[[:space:]]*//p' "$TASK_FILE" | head -1 | xargs || true)"
  if [ -z "$ENVIRONMENT" ] || [ "$ENVIRONMENT" = "null" ]; then
    DEPLOY_URL="$(sed -n 's/^deploy_url:[[:space:]]*//p' "$TASK_FILE" | head -1 | xargs || true)"
    ENVIRONMENT="$(printf '%s' "$DEPLOY_URL" | sed -E 's#^[a-zA-Z]+://([^/]+).*#\1#')"
  fi
fi

if [ -n "$ENVIRONMENT" ] && [ "$ENVIRONMENT" != "none" ] && [ "$ENVIRONMENT" != "null" ]; then
  SAFE_ENV="$(printf '%s' "$ENVIRONMENT" | tr '/:' '--' | tr -cd '[:alnum:]_.-')"
  exec 8>"$ENVIRONMENT_LOCK_ROOT/$SAFE_ENV.lock"
  flock -n 8 || {
    REMOVE_WORKTREE=true
    printf 'status=blocked\nreason=executor_busy\nlock=environment\nenvironment=%s\n' "$ENVIRONMENT" >&2
    exit 75
  }
fi

export KIMI_TASK_WORKTREE="$WORKTREE"
export KIMI_TASK_FILE="${TASK_FILE#"$WORKTREE/"}"
export KIMI_TASK_ID="$TASK_ID"
export KIMI_TASK_BRANCH="$BRANCH"
export KIMI_BASE_BRANCH="$BASE"
cd "$WORKTREE"
set +e
"$@"
COMMAND_CODE=$?
set -e

HEAD="$(git rev-parse HEAD)"
if [ -z "$(git status --porcelain)" ] && [ "$HEAD" = "$INITIAL_HEAD" ]; then
  REMOVE_WORKTREE=true
elif [ -z "$(git status --porcelain)" ]; then
  REMOTE_HEAD="$(git ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | awk 'NR==1 {print $1}')"
  if [ -n "$REMOTE_HEAD" ] && [ "$HEAD" = "$REMOTE_HEAD" ]; then
    REMOVE_WORKTREE=true
  fi
fi

if ! $REMOVE_WORKTREE; then
  PRESERVE_REASON=unpushed_worktree_preserved
  printf 'status=blocked\nreason=unpushed_worktree_preserved\nworktree=%s\n' "$WORKTREE" >&2
  exit 78
fi

exit "$COMMAND_CODE"
