import { expect, test } from "@playwright/test";

test.describe("/documents/d1 smoke", () => {
  test("opens the user menu without crashing the page", async ({ page }) => {
    await page.goto("/documents/d1");

    await page.getByRole("button", { name: /Аня Ю\.|АЮ/ }).click();

    await expect(page.getByText("Помощник юриста", { exact: true })).toBeVisible();
    await expect(page.getByText("Профиль", { exact: true })).toBeVisible();
    await expect(page.getByText("Выйти", { exact: true })).toBeVisible();
    await expect(page.getByText("This page couldn't load")).toBeHidden();
  });

  test("renders summary cards, conflict, overdue date and edit details", async ({ page }) => {
    await page.goto("/documents/d1");

    // Page title and project context.
    await expect(page.getByText("Основной договор").first()).toBeVisible();
    await expect(page.getByText("Договор поставки №12").first()).toBeVisible();

    // Summary cards show the expected risk numbers for the d1 fixture.
    const blockersCard = page.getByTestId("summary-blockers");
    await expect(blockersCard).toContainText("Блокеры");
    await expect(blockersCard).toContainText("2");

    const overdueCard = page.getByTestId("summary-overdue");
    await expect(overdueCard).toContainText("Просрочка");
    await expect(overdueCard).toContainText("1");

    const conflictsCard = page.getByTestId("summary-conflicts");
    await expect(conflictsCard).toContainText("Конфликты");
    await expect(conflictsCard).toContainText("1");

    // Conflict group for п. 7.1 Неустойка with the two responsible persons.
    await expect(page.getByText("Конфликт · п. 7.1 Неустойка")).toBeVisible();
    await expect(page.getByText("Петров vs Орлов")).toBeVisible();

    // Overdue date is rendered (e5 deadline).
    await expect(page.getByText("30.05.2026")).toBeVisible();

    // Clicking an edit row opens the detail dialog with "before/after" and argument.
    const editRow = page.getByTestId("edit-row-e2");
    await expect(editRow).toContainText("п. 7.1 Неустойка");
    await editRow.click();

    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText("Было")).toBeVisible();
    await expect(dialog.getByText("Стало")).toBeVisible();
    await expect(dialog.getByText("Аргументация")).toBeVisible();
    await expect(dialog.getByText("Контрагент просит снизить ставку неустойки вдвое.")).toBeVisible();
    await expect(dialog.getByRole("link", { name: "Битрикс" })).toHaveAttribute(
      "href",
      "https://bitrix.example/task/4822"
    );
  });
});
