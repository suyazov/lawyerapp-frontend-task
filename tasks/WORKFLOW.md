# Рабочий процесс ChatGPT → GitHub → Kimi

Этот каталог хранит исполняемые технические TASK-файлы. Управленческий источник задач — AFFiNE `Tasks` проекта.

## Источники правды

Перед созданием или выполнением задачи обязательны:

1. актуальные канонические регламенты;
2. `Context` проекта в AFFiNE или актуальном mirror `suyazov/affine-pages-backup`;
3. AFFiNE `Tasks` или её актуальный mirror;
4. `Access Map`, если нужны внешние сервисы или доступы;
5. `AGENTS.md`, `tasks/ACTIVE.md` и активный TASK-файл.

Кодовый репозиторий не обязан содержать отдельный проектный `Context`. При отсутствии AFFiNE MCP ChatGPT обязан искать его в `affine-pages-backup/affine/clients/`, а не объявлять Context отсутствующим после проверки только этого репозитория.

## Роли

- **Артём** определяет приоритет и принимает результат.
- **ChatGPT** проводит preflight, создаёт карточку AFFiNE с `Task ID`, формулирует ТЗ и публикует его.
- **Kimi** на модели `kimi-code/k3` выполняет только активную готовую задачу в ветке `kimi/<TASK-ID>`.
- **Codex** используется для короткой проверки, инфраструктуры и аварийных случаев, а не для основной реализации.

## Статусы

- `draft` — ТЗ формируется или preflight не завершён;
- `ready` — все обязательные проверки подтверждены;
- `in_progress` — Kimi начал работу;
- `blocked` — работа остановлена с конкретной причиной;
- `review` — создан результат для проверки;
- `done` — задача принята после проверки и merge;
- `cancelled` — задача отменена.

## Обязательный preflight перед `ready`

В TASK frontmatter должны быть подтверждены:

```yaml
preflight_context: true
preflight_tasks: true
preflight_access: true
preflight_regulations: true
```

Также обязательны:

- `task_id`, совпадающий с карточкой AFFiNE;
- `model: kimi-code/k3`;
- `repository`, `branch`, `affine_project`, `affine_task_id`;
- источники Context, Tasks и Access Map;
- отсутствие дубликата задачи;
- раздел `Canonical regulations` в `AGENTS.md`;
- нормализованные доступы по пути `/root/.config/client-access/<client-slug>/<service>.env` или shared-access;
- явный запрет production/delete, если они не утверждены Артёмом.

Если AFFiNE MCP недоступен, разрешено использовать только актуальный GitHub mirror. Если недоступны и MCP, и mirror, задача остаётся `draft` или `blocked`; `ready` запрещён.

## Правила ChatGPT

1. Создать TASK по `tasks/TASK_TEMPLATE.md`.
2. Сначала создать или обновить карточку AFFiNE с тем же `Task ID`.
3. Указать точный `base_commit`.
4. Не использовать старый frontmatter `id:` как основной; каноническое поле — `task_id:`.
5. Не ставить `ready`, пока preflight-флаги не подтверждены фактически.
6. Обновить `tasks/ACTIVE.md` только после завершения preflight.
7. Не выполнять основную реализацию вместо Kimi.
8. Новые уточнения добавлять в тот же TASK.

## Правила Kimi

1. Читать канонические регламенты, `AGENTS.md`, WORKFLOW, ACTIVE и TASK.
2. Работать только на `kimi-code/k3`.
3. Работать только в `kimi/<TASK-ID>`; `main` не менять.
4. До кода поставить `in_progress` и сделать `task(TASK-XXX): start`.
5. Менять только разрешённые файлы.
6. При противоречии, отсутствии доступа или данных поставить `blocked` и остановиться.
7. Production, перенос и удаление staging выполнять только отдельной задачей с подтверждением Артёма.
8. После реализации выполнить проверки, заполнить отчёт, поставить `review` и создать/обновить один PR.
9. `done` и merge не выполнять.

## Проверка

После команды Артёма `Проверь TASK-XXX` ChatGPT/Codex читает только TASK, отчёт Kimi, PR diff, тесты и затронутые файлы. Решение: `accepted`, `changes_required` или `blocked`.

При замечаниях используется тот же TASK, ветка и PR. Основную доработку снова выполняет Kimi.

## Важное правило

Зелёный workflow, commit TASK или сообщение ChatGPT не доказывают, что задача запущена или выполнена. Отдельно подтверждаются: workflow run, ветка, PR и итоговый статус.

## SHA, ветка и повторные итерации

- `actual_start_sha` вычисляет wrapper перед стартовым metadata commit; Kimi это поле не меняет.
- `result_commit` вычисляет wrapper после commit реализации и отчёта; затем создаётся отдельный metadata commit.
- SHA должен состоять ровно из 40 hex-символов, существовать в Git и быть предком текущего HEAD.
- Если в отчёте указан итоговый SHA, он обязан совпадать с `result_commit`.
- Исполнительская задача до принятия не завершается в `main`.
- Для одного `TASK-ID` используются одна ветка `kimi/<TASK-ID>` и один Pull Request.
- Повторная итерация продолжает существующую remote-ветку без `checkout -B`, force push или переписывания истории.
- Изменения и замечания из `main` синхронизируются перед новой итерацией.
- При конфликте в кодовом файле merge останавливается без автоматического разрешения.


<!-- KIMI-EXECUTION-V2:START -->
## Execution safety v2

Primary TASK и повторная команда `/kimi-fix` используют один execution layer:

- `kimi-code/k3` явно;
- project lock на репозиторий;
- environment lock из `environment_lock`, `environment` или `deploy_url`;
- отдельный worktree каждого запуска;
- общий SHA validator;
- существующая ветка `kimi/TASK-ID` и один PR;
- cleanup worktree и locks через trap.

TASK со статусом `ready` запускается только при шести подтверждённых preflight-флагах: context, tasks, access, regulations, executor и environment. Kimi не ставит `done`, не мержит PR и не меняет production без отдельного разрешения.

`/kimi-fix` исправляет только замечание в том же TASK, той же ветке и том же PR. Второй PR запрещён.
<!-- KIMI-EXECUTION-V2:END -->
