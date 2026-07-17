#!/usr/bin/env bash
# Remove only old, clean worktrees whose HEAD is confirmed on an origin branch.
set -euo pipefail

ROOT="${KIMI_WORKTREE_ROOT:-/var/lib/kimi-worktrees}"
HOURS="${1:-24}"
[[ "$HOURS" =~ ^[0-9]+$ ]] || { echo "usage: $0 [older-than-hours]" >&2; exit 2; }
[ -d "$ROOT" ] || exit 0

find "$ROOT" -mindepth 2 -maxdepth 2 -type d -mmin "+$((HOURS * 60))" -print0 |
while IFS= read -r -d '' worktree; do
  git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  [ -z "$(git -C "$worktree" status --porcelain)" ] || {
    echo "preserved_dirty:$worktree"
    continue
  }
  git -C "$worktree" fetch origin --prune >/dev/null 2>&1 || {
    echo "preserved_unverified:$worktree"
    continue
  }
  head="$(git -C "$worktree" rev-parse HEAD)"
  remote="$(git -C "$worktree" for-each-ref --format='%(objectname)' refs/remotes/origin | grep -Fx "$head" | head -1 || true)"
  [ -n "$remote" ] || {
    echo "preserved_unpushed:$worktree"
    continue
  }
  common="$(git -C "$worktree" rev-parse --git-common-dir)"
  repo="$(cd "$worktree" && cd "$common" && pwd)"
  repo="${repo%/.git}"
  git -C "$repo" worktree remove --force "$worktree"
  git -C "$repo" worktree prune
  echo "removed:$worktree"
done
