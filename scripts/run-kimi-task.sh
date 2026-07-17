#!/usr/bin/env bash
# Запускает Kimi Code CLI над активной задачей из tasks/ACTIVE.md.
# Работает в ветке kimi/<TASK-ID>, пушит результат и создаёт PR.
set -uo pipefail

cd "$(dirname "$0")/.."

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then export HOME=/root; fi
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

log() { echo "[kimi-task] $*"; }

ACTIVE="tasks/ACTIVE.md"
TASK_ID="$(grep -oP '(?<=^- ID: `)[^`]+' "$ACTIVE" 2>/dev/null | head -1 || true)"
TASK_FILE="$(grep -oP '(?<=^- Файл: `)[^`]+' "$ACTIVE" 2>/dev/null | head -1 || true)"

if [ -z "$TASK_ID" ] || [ -z "$TASK_FILE" ] || [ ! -f "$TASK_FILE" ]; then
  log "Активная задача не найдена — выход."
  exit 0
fi

VALIDATION="$(./scripts/read-active-task.sh)"
echo "$VALIDATION"
RUNNABLE="$(printf '%s\n' "$VALIDATION" | sed -n 's/^runnable=//p')"
REASON="$(printf '%s\n' "$VALIDATION" | sed -n 's/^reason=//p')"

if [ "$RUNNABLE" != "true" ]; then
  log "Preflight не пройден: $REASON"
  exit 2
fi

MODEL="${KIMI_MODEL:-kimi-code/k3}"
if [ "$MODEL" != "kimi-code/k3" ]; then
  log "Недопустимая модель: $MODEL"
  exit 2
fi

BRANCH="kimi/$TASK_ID"
BASE_BRANCH="$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -1)"
BASE_BRANCH="${BASE_BRANCH:-main}"

log "Задача: $TASK_ID ($TASK_FILE)"
log "Ветка: $BRANCH; модель: $MODEL"

git config user.name "${GIT_AUTHOR_NAME:-kimi-bot}"
git config user.email "${GIT_AUTHOR_EMAIL:-kimi-bot@users.noreply.github.com}"
git fetch origin "$BASE_BRANCH"
git checkout -B "$BRANCH" "origin/$BASE_BRANCH"

PROMPT="$(cat <<EOF
Сначала прочитай канонические регламенты из AGENTS.md, затем AGENTS.md, tasks/WORKFLOW.md, tasks/ACTIVE.md и $TASK_FILE.

Выполни ровно одну задачу $TASK_ID на модели $MODEL.

Правила:
- ты уже в ветке $BRANCH; main не менять и не мержить;
- первым делом поставить status: in_progress, заполнить started_at и actual_start_sha, commit: task($TASK_ID): start;
- менять только разрешённый scope;
- если регламент недоступен, доступ отсутствует или данные не подтверждены — поставить blocked и остановиться;
- production, перенос и удаление staging запрещены без отдельной задачи и подтверждения Артёма;
- после выполнения заполнить отчёт, поставить review, commit: task($TASK_ID): review;
- done не ставить;
- секреты и токены не коммитить и не печатать.
EOF
)"

log "Запуск Kimi CLI (таймаут ${KIMI_TIMEOUT:-75m})..."
KIMI_EXIT=0
timeout "${KIMI_TIMEOUT:-75m}" kimi --print --model "$MODEL" --work-dir "$PWD" --prompt "$PROMPT" || KIMI_EXIT=$?
log "Kimi завершился с кодом $KIMI_EXIT"

FINAL_STATUS="$(sed -n 's/^status:[[:space:]]*//p' "$TASK_FILE" | head -1 | tr -d '[:space:]')"
if [ "$KIMI_EXIT" -ne 0 ] && [ "$FINAL_STATUS" != "review" ] && [ "$FINAL_STATUS" != "blocked" ]; then
  log "Kimi завершился аварийно, помечаю задачу blocked."
  sed -i "0,/^status:.*/s//status: blocked/" "$TASK_FILE"
  printf '\n## Блокеры\n\n- Автоматический запуск завершился с кодом %s. Требуется проверка.\n' "$KIMI_EXIT" >> "$TASK_FILE"
fi

git add -A
if ! git diff --cached --quiet; then
  git commit -m "task($TASK_ID): kimi execution (auto-commit)"
fi

if [ "$(git rev-list --count "origin/$BASE_BRANCH..HEAD")" = "0" ]; then
  log "Нет новых коммитов — выход."
  exit "$KIMI_EXIT"
fi

git push -u origin "$BRANCH"

PR_URL="$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null || true)"
if [ -z "$PR_URL" ]; then
  TITLE="$(sed -n 's/^title:[[:space:]]*//p' "$TASK_FILE" | head -1)"
  PR_URL="$(gh pr create --base "$BASE_BRANCH" --head "$BRANCH" \
    --title "$TASK_ID: ${TITLE:-kimi task}" \
    --body "Автоматический PR по задаче \`$TASK_ID\`. Слияние в main — только после проверки Артёмом/ChatGPT.")" || exit 1
fi

log "PR: $PR_URL"
exit "$KIMI_EXIT"