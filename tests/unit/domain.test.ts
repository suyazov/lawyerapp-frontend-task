import { describe, expect, it } from "vitest";
import { EDITS, PROJECTS, projHealth, isApproved } from "@/lib/fixtures";
import { TODAY, dayStatus, isOpenEdit, isOverdue } from "@/lib/domain";
import type { Edit, EditStatus } from "@/lib/types";

const baseEdit: Edit = {
  id: "test",
  docId: "d1",
  date: TODAY,
  clause: "п. 1.1 Тест",
  type: "commercial",
  tier: "responsible",
  before: "было",
  after: "стало",
  authorId: "assist",
  responsibleId: "lawyer",
  argument: "",
  privateNote: "",
  deadline: null,
  bitrix: null,
  proof: null,
  status: "draft",
  approverId: null,
  appliedIn: null,
};

const d1Edits = EDITS.filter((e) => e.docId === "d1");

describe("isOpenEdit", () => {
  it.each<[EditStatus, boolean]>([
    ["draft", true],
    ["in_review", true],
    ["rework", true],
    ["accepted", false],
    ["rejected", false],
    ["applied", false],
  ])("status %s -> open=%s", (status, expected) => {
    expect(isOpenEdit({ ...baseEdit, status })).toBe(expected);
  });
});

describe("isOverdue", () => {
  it("returns true when deadline is before TODAY and edit is open", () => {
    expect(isOverdue({ ...baseEdit, status: "in_review", deadline: "2026-06-01" })).toBe(true);
  });

  it("returns false for closed edits even with old deadline", () => {
    expect(isOverdue({ ...baseEdit, status: "rejected", deadline: "2026-06-01" })).toBe(false);
  });

  it("returns false when deadline is today", () => {
    expect(isOverdue({ ...baseEdit, status: "in_review", deadline: TODAY })).toBe(false);
  });

  it("returns false when deadline is in the future", () => {
    expect(isOverdue({ ...baseEdit, status: "in_review", deadline: "2026-12-31" })).toBe(false);
  });

  it("returns false when there is no deadline", () => {
    expect(isOverdue({ ...baseEdit, status: "in_review", deadline: null })).toBe(false);
  });
});

describe("dayStatus", () => {
  it("reports closed when no open edits", () => {
    expect(dayStatus([{ ...baseEdit, status: "applied" }])).toMatchObject({
      label: "Закрыта",
      dot: "bg-emerald-500",
    });
  });

  it("reports overdue count when an open edit is overdue", () => {
    expect(dayStatus([{ ...baseEdit, status: "in_review", deadline: "2026-06-01" }])).toMatchObject({
      label: "Просрочка · 1",
      dot: "bg-red-500",
    });
  });

  it("reports open count when nothing is overdue", () => {
    expect(dayStatus([{ ...baseEdit, status: "in_review", deadline: "2026-12-31" }])).toMatchObject({
      label: "Открыто 1",
      dot: "bg-amber-500",
    });
  });
});

describe("fixture-derived summaries", () => {
  it("d1 has the expected number of open/closed/overdue/blocker edits", () => {
    expect(d1Edits.filter(isOpenEdit)).toHaveLength(4);
    expect(d1Edits.filter((e) => !isOpenEdit(e))).toHaveLength(3);
    expect(d1Edits.filter(isOverdue)).toHaveLength(1);
    expect(d1Edits.filter((e) => e.tier === "blocker" && isOpenEdit(e))).toHaveLength(2);
  });

  it("projHealth aggregates project-level risk for p1", () => {
    const h = projHealth("p1");
    expect(h.total).toBe(d1Edits.length);
    expect(h.open).toBe(4);
    expect(h.blockers).toBe(2);
    expect(h.overdue).toBe(1);
  });

  it("p1 is not approved because open edits remain", () => {
    expect(isApproved(PROJECTS.find((p) => p.id === "p1")!)).toBe(false);
  });

  it("p7 is approved: active and all edits closed", () => {
    expect(isApproved(PROJECTS.find((p) => p.id === "p7")!)).toBe(true);
  });

  it("p3 is not approved: draft project with no edit history", () => {
    expect(isApproved(PROJECTS.find((p) => p.id === "p3")!)).toBe(false);
  });
});
