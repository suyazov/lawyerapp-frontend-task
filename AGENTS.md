<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->


<!-- KIMI-AUTOMATION:START -->
## Canonical regulations

Перед каждой задачей прочитать актуальные документы из:

- `/var/lib/bridge-sy9/affine-pages-backup/affine/infrastructure/Регламент/1. Архитектура AFFiNE GitHub Bridge.md`
- `/var/lib/bridge-sy9/affine-pages-backup/affine/infrastructure/Регламент/Регламент- клиентский workflow.md`
- `/var/lib/bridge-sy9/affine-pages-backup/affine/infrastructure/Регламент/3. Автоматизация задач ChatGPT GitHub Kimi.md`
- `/var/lib/bridge-sy9/affine-pages-backup/affine/infrastructure/Регламент/Регламент- работа с Kimi.md`

Для WordPress-задач дополнительно прочитать:

- `/var/lib/bridge-sy9/affine-pages-backup/affine/infrastructure/Регламент/6. WordPress проекты.md`

Если хотя бы один обязательный файл недоступен, неактуален или противоречит TASK-файлу, поставить `status: blocked`, описать причину и остановиться.

## Kimi automation

1. Перед работой прочитать `tasks/WORKFLOW.md`, `tasks/ACTIVE.md` и файл активной задачи.
2. Выполнять только активную задачу со `status: ready` и четырьмя подтверждёнными preflight-флагами.
3. Обязательная модель: `kimi-code/k3`.
4. Не изменять `main` напрямую; работать в `kimi/<TASK-ID>`.
5. При конфликте требований, отсутствии Context, Tasks, Access Map, регламентов или доступа поставить `status: blocked` и остановиться.
6. Менять только разрешённый TASK scope; не выполнять production deploy или удаление без отдельного подтверждения Артёма.
7. После выполнения заполнить результат, поставить `status: review` и обновить один Pull Request.
8. `status: done` и merge выполняются только после внешней проверки.
9. Секреты, токены и пароли не коммитить и не печатать.
10. `actual_start_sha` и `result_commit` вычисляет wrapper; Kimi не заполняет их вручную.
11. Повторная итерация продолжает существующую `kimi/<TASK-ID>` и тот же Pull Request без force reset.
12. Конфликт с `main` в кодовом файле не разрешать автоматически: остановиться и запросить ручное решение.
<!-- KIMI-AUTOMATION:END -->
