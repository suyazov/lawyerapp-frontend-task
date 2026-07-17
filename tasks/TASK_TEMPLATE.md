---
task_id: TASK-XXX
title: Краткое название
status: draft
priority: medium
model: kimi-code/k3
repository: suyazov/lawyerapp-frontend-task
branch: kimi/TASK-XXX
affine_project: "Project: <Имя проекта>"
affine_task_id: TASK-XXX
affine_row_id: null
context_source: null
tasks_source: null
access_map_source: null
preflight_context: false
preflight_tasks: false
preflight_access: false
preflight_regulations: false
environment: none
environment_lock: none
preflight_executor: false
preflight_environment: false
created_at: YYYY-MM-DD HH:MM MSK
updated_at: YYYY-MM-DD HH:MM MSK
created_by: ChatGPT
worker: null
base_commit: null
actual_start_sha: null
started_at: null
finished_at: null
accepted_at: null
result_commit: null
deploy_url: null
regulations:
  - 1. Архитектура AFFiNE GitHub Bridge
  - 2. Клиентский workflow
  - 3. Автоматизация задач ChatGPT GitHub Kimi
  - 4. Работа с Kimi
---

# TASK-XXX — Название

## Preflight

До `status: ready` подтвердить:

- [ ] найден и прочитан `Context` проекта через AFFiNE MCP или актуальный GitHub mirror;
- [ ] проверена AFFiNE `Tasks` или её актуальный mirror, дубликат отсутствует;
- [ ] создана/обновлена карточка AFFiNE с тем же `Task ID`;
- [ ] проверен `Access Map`, если задача требует внешних сервисов или учётных данных;
- [ ] доступы находятся по каноническому пути `/root/.config/client-access/<client-slug>/<service>.env` или `/root/.config/shared-access/<service>.env`;
- [ ] `AGENTS.md` содержит раздел `Canonical regulations`;
- [ ] перечисленные регламенты доступны;
- [ ] модель `kimi-code/k3` доступна;
- [ ] production/deploy/delete-операции явно разрешены или запрещены.

Если хотя бы один обязательный пункт не подтверждён, использовать `status: draft` или `status: blocked`, но не `ready`.

## Контекст

Почему задача появилась, какую проблему решает и откуда получены подтверждённые данные.

## Цель

Какой пользовательский или бизнес-результат должен быть достигнут.

## Объём работ

1. ...
2. ...

## Разрешено менять

- `path/to/file`

## Не менять

- production без отдельного подтверждения;
- секреты и `.env`;
- unrelated-файлы;
- ...

## Технические требования

### 1. Раздел

...

## Критерии приёмки

- [ ] ...

## Обязательные проверки

- [ ] `git diff --check`.
- [ ] PHP/JS/CSS lint по изменённым файлам.
- [ ] Console errors = 0.
- [ ] Overflow-x = 0.
- [ ] Проверка контрольных разрешений.
- [ ] Проверка форм/аналитики, если затронуты.
- [ ] Проверка отсутствия секретов и unrelated-изменений.

## Формат отчёта Kimi

- Модель: `kimi-code/k3`
- Версия/ветка:
- Итоговый commit SHA:
- Изменённые файлы:
- Что сделано:
- Результаты тестов:
- Deploy:
- Известные ограничения:
- Скриншоты/видео:

## Блокеры

Нет.

## Уточнения

Нет.

## Результат выполнения

Заполняет Kimi.

## Проверка Codex

Статус: pending

- Scope:
- Diff:
- Tests:
- Acceptance:
- Secrets:
- Решение: `accepted` / `changes_required` / `blocked`

## Замечания при проверке

Заполняет Артём/ChatGPT.