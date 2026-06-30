# Тестирование LawyerApp

Этот документ описывает, что и как проверяется в тестовом задании, и как запускать проверки локально.

## Что проверяем и зачем

Основной экран — `/documents/d1`. В нём собраны все ключевые состояния, которые должны быть видны юристу:

| Что проверяем | Зачем |
|---------------|-------|
| Сводка карточек (текущая версия, открыто/закрыто, блокеры, просрочка, конфликты) | Первый взгляд должен показывать состояние документа и риски. |
| Конфликт по `п. 7.1 Неустойка` (Петров vs Орлов) | Конфликт не должен теряться как две похожие строки. |
| Просроченная правка (`30.05.2026`) | Дедлайн в прошлом должен быть заметен и влиять на сортировку. |
| Сортировка/группировка строк | Конфликты и высокорисковые открытые правки должны идти первыми. |
| Append-only visibility | Закрытые/отклонённые правки остаются в истории, но уходят вниз. |
| Клик по правке открывает детали | Вся аргументация, было/стало, заметки доступны в диалоге. |

## Структура тестов

```text
tests/unit/domain.test.ts            # чистая доменная логика (статусы, просрочка, сводки)
tests/unit/timeline-helpers.test.ts  # сортировка/группировка строк и сводка правок
e2e/documents.spec.ts                # Playwright-smoke для /documents/d1
playwright.config.ts                 # конфигурация E2E
vitest.config.ts                     # конфигурация unit-тестов
```

## Запуск локально

```bash
# Установить зависимости (включая браузер Playwright)
npm install
npx playwright install chromium

# Линт и типизация
npm run lint
npm run typecheck

# Unit-тесты
npm run test:unit

# Сборка
npm run build

# E2E-smoke (запускает dev-сервер автоматически)
npm run test:e2e

# Всё сразу (тяжёлая команда: lint + typecheck + unit + build + e2e)
npm run test:all
```

E2E можно запускать и против уже поднятого сервера:

```bash
PORT=3456 npm run dev
# в другом терминале
PLAYWRIGHT_BASE_URL=http://localhost:3456 npm run test:e2e
```

## Что прошло

- `npm run lint` — без ошибок.
- `npm run typecheck` (`tsc --noEmit`) — без ошибок.
- `npm run test:unit` — покрывает `domain.ts` и `timeline-helpers.ts`.
- `npm run build` — production-сборка проходит.
- `npm run test:e2e` — smoke-тест `/documents/d1` проходит в Chromium.

## CI-ready templates

- `docs/ci/github-actions-ci.yml` — install, lint, typecheck, unit tests, build.
- `docs/ci/github-actions-e2e.yml` — production-сборка и Playwright-smoke в Chromium.

Файлы лежат как готовые GitHub Actions templates. Включение реальных `.github/workflows/*.yml`
требует GitHub token с правом `workflow`; текущий deployment token репозитория не имеет
этого scope, поэтому workflow-шаблоны не публикуются как активные Actions в рамках этой сдачи.
E2E вынесен в отдельный workflow-шаблон, чтобы основная проверка оставалась быстрой.

## Скриншоты

Скриншоты ключевых состояний лежат в `docs/screenshots/`:

- `docs/screenshots/document-d1.png` — основной кейс с конфликтом и просрочкой.
- `docs/screenshots/document-d5.png` — кейс без открытых рисков.
