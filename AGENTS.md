<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

## Автоматизация задач (Kimi Code CLI)

Задачи для Kimi оформляются в `tasks/` (см. `tasks/WORKFLOW.md`). Активная задача — в `tasks/ACTIVE.md`. Push в `main` с изменением `tasks/ACTIVE.md` или `tasks/TASK-*.md` автоматически запускает Kimi через GitHub Action: создаётся ветка `kimi/<TASK-ID>` и Pull Request. Результат проверяется по PR перед merge.
