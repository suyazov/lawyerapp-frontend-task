#!/usr/bin/env bash
# Запускает Kimi Code CLI над активной задачей из tasks/ACTIVE.md.
# Работает в ветке kimi/<TASK-ID>, пушит результат и создаёт PR.
# Идемпотентен: задача не в статусе ready — тихий выход без изменений.
set -uo pipefail

cd "$(dirname "$0")/.."

# Runner-сервис может иметь урезанное окружение — чиним HOME/PATH.
if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then export HOME=/root; fi
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

log() { echo "[kimi-task] $*"; }

# --- 1. Определяем активную задачу ---
ACTIVE="tasks/ACTIVE.md"
TASK_ID="$(grep -oP '(?<=^- ID: `)[^`]+' "$ACTIVE" 2>/dev/null | head -1 || true)"
TASK_FILE="$(grep -oP '(?<=^- Файл: `)[^`]+' "$ACTIVE" 2>/dev/null | head -1 || true)"

if [ -z "$TASK_ID" ] || [ -z "$TASK_FILE" ] || [ ! -f "$TASK_FILE" ]; then
  log "Активная задача не найдена — выход."
  exit 0
fi

STATUS="$(sed -n 's/^status:[[:space:]]*//p' "$TASK_FILE" | head -1 | tr -d '[:space:]')"
if [ "$STATUS" != "ready" ]; then
  log "Статус задачи $TASK_ID — '$STATUS' (нужен 'ready') — выход."
  exit 0
fi

BRANCH="kimi/$TASK_ID"
BASE_BRANCH="$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -1)"
BASE_BRANCH="${BASE_BRANCH:-main}"

log "Задача: $TASK_ID ($TASK_FILE)"
log "Ветка:  $BRANCH (база: $BASE_BRANCH)"

git config user.name "${GIT_AUTHOR_NAME:-kimi-bot}"
git config user.email "${GIT_AUTHOR_EMAIL:-kimi-bot@users.noreply.github.com}"

git fetch origin "$BASE_BRANCH"
git checkout -B "$BRANCH" "origin/$BASE_BRANCH"

# --- 2. Запускаем Kimi ---
PROMPT="$(cat <<EOF
Прочитай AGENTS.md, tasks/WORKFLOW.md, tasks/ACTIVE.md и файл задачи $TASK_FILE.

Выполни ровно одну задачу $TASK_ID, строго по её ТЗ.

Правила:
- ты уже в ветке $BRANCH; в main ничего не мержить и не пушить (push сделает внешний скрипт);
- первым делом обнови в $TASK_FILE: status на in_progress, started_at, actual_start_sha (текущий HEAD), закоммить: task($TASK_ID): start
- меняй только то, что разрешено в ТЗ (разделы «Разрешено менять» / «Не менять»);
- если ТЗ противоречит коду или не хватает данных — не додумывай: опиши блокер в разделе «Блокеры» файла задачи, поставь status: blocked, закоммить task($TASK_ID): blocked и остановись;
- после выполнения заполни раздел «Результат выполнения» (commit SHA, изменённые файлы, проверки, известные ограничения), поставь status: review, закоммить task($TASK_ID): review;
- status: done не ставить;
- секреты и токены не коммитить.
EOF
)"

log "Запуск Kimi CLI (таймаут ${KIMI_TIMEOUT:-75m})..."
KIMI_EXIT=0
timeout "${KIMI_TIMEOUT:-75m}" kimi --print --work-dir "$PWD" --prompt "$PROMPT" || KIMI_EXIT=$?
log "Kimi завершился с кодом $KIMI_EXIT"

# --- 3. Если Kimi упал/таймаут и не выставил финальный статус — фиксируем blocked ---
FINAL_STATUS="$(sed -n 's/^status:[[:space:]]*//p' "$TASK_FILE" | head -1 | tr -d '[:space:]')"
if [ "$KIMI_EXIT" -ne 0 ] && [ "$FINAL_STATUS" != "review" ] && [ "$FINAL_STATUS" != "blocked" ]; then
  log "Kimi завершился аварийно, статус '$FINAL_STATUS' — помечаю задачу blocked."
  if grep -q '^status:' "$TASK_FILE"; then
    sed -i "0,/^status:.*/s//status: blocked/" "$TASK_FILE"
  fi
  printf '\n## Блокеры\n\n- Автоматический запуск: Kimi CLI завершился с кодом %s (ошибка или таймаут). Требуется повторный запуск или ручная доработка.\n' "$KIMI_EXIT" >> "$TASK_FILE"
fi

# --- 4. Докоммичиваем всё, что Kimi не закоммитил сам ---
git add -A
if ! git diff --cached --quiet; then
  git commit -m "task($TASK_ID): kimi execution (auto-commit)"
fi

if [ "$(git rev-list --count "origin/$BASE_BRANCH..HEAD")" = "0" ]; then
  log "Нет новых коммитов — пушить нечего, выход."
  exit 0
fi

# --- 5. Пушим ветку и создаём PR ---
git push -u origin "$BRANCH"

PR_URL="$(gh pr view "$BRANCH" --json url --jq .url 2>/dev/null || true)"
if [ -n "$PR_URL" ]; then
  log "PR уже существует: $PR_URL"
else
  TITLE="$(sed -n 's/^title:[[:space:]]*//p' "$TASK_FILE" | head -1)"
  if ! PR_URL="$(gh pr create --base "$BASE_BRANCH" --head "$BRANCH" \
    --title "$TASK_ID: ${TITLE:-kimi task}" \
    --body "Автоматический PR по задаче \`$TASK_ID\`.

- Файл ТЗ: \`$TASK_FILE\`
- Статус и отчёт: раздел «Результат выполнения» в файле задачи
- Слияние в main — только после проверки (Артём/ChatGPT)")"; then
    log "ОШИБКА: не удалось создать PR (проверь Settings → Actions → 'Allow GitHub Actions to create pull requests')."
    exit 1
  fi
  log "Создан PR: $PR_URL"
fi

# Красим прогон в красный, если Kimi завершился аварийно (ветка и PR при этом сохранены).
exit "$KIMI_EXIT"
