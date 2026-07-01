import { describe, expect, it } from "vitest";
import { EDITS } from "@/lib/fixtures";
import { buildEditRows, computeEditSummary, findConflicts } from "@/lib/timeline-helpers";
import type { Edit } from "@/lib/types";

const d1Edits = EDITS.filter((e) => e.docId === "d1");

const today = "2026-06-11";
const baseEdit: Edit = {
  id: "x",
  docId: "d1",
  date: today,
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
  status: "in_review",
  approverId: null,
  appliedIn: null,
};

describe("computeEditSummary", () => {
  it("matches the d1 fixture state", () => {
    const s = computeEditSummary(d1Edits);

    expect(s.openCount).toBe(4);
    expect(s.closedCount).toBe(3);
    expect(s.candidates).toHaveLength(1);
    expect(s.candidates[0].id).toBe("e1");
    expect(s.blockers).toBe(2);
    expect(s.overdue).toBe(1);
    expect(s.conflicts).toHaveLength(1);
    expect(s.conflicts[0][0]).toBe("п. 7.1 Неустойка");
  });

  it("counts only open blockers", () => {
    const edits: Edit[] = [
      { ...baseEdit, id: "b1", tier: "blocker" },
      { ...baseEdit, id: "b2", tier: "blocker", status: "applied" },
    ];
    const s = computeEditSummary(edits);
    expect(s.blockers).toBe(1);
    expect(s.openCount).toBe(1);
  });
});

describe("findConflicts", () => {
  it("detects one conflict on clause п. 7.1 Неустойка for d1", () => {
    const conflicts = findConflicts(d1Edits);
    expect(conflicts).toHaveLength(1);
    const [clause, edits] = conflicts[0];
    expect(clause).toBe("п. 7.1 Неустойка");
    expect(edits.map((e) => e.id).sort()).toEqual(["e2", "e7"]);
  });

  it("ignores closed edits when looking for conflicts", () => {
    const edits: Edit[] = [
      { ...baseEdit, id: "a", clause: "п. 1.1", status: "applied" },
      { ...baseEdit, id: "b", clause: "п. 1.1", status: "accepted" },
    ];
    expect(findConflicts(edits)).toHaveLength(0);
  });
});

describe("buildEditRows", () => {
  it("places the conflict group before regular rows", () => {
    const rows = buildEditRows(d1Edits);
    expect(rows[0].kind).toBe("conflict-header");
    expect(rows[0].kind === "conflict-header" && rows[0].clause).toBe("п. 7.1 Неустойка");
  });

  it("keeps closed edits visible (append-only) at the end", () => {
    const rows = buildEditRows(d1Edits);
    const tail = rows.slice(-3);
    expect(tail.every((r) => r.kind === "edit")).toBe(true);
    const tailIds = tail.map((r) => (r.kind === "edit" ? r.edit.id : ""));
    expect(tailIds).toEqual(["e1", "e3", "e4"]);
  });

  it("sorts remaining open edits by risk: overdue before non-overdue", () => {
    const rows = buildEditRows(d1Edits);
    const editIds = rows
      .filter((r) => r.kind === "edit")
      .map((r) => (r.kind === "edit" ? r.edit.id : ""));

    // Conflict block first (e7/e2), then overdue responsible edit e5, then open e6.
    expect(editIds.indexOf("e5")).toBeLessThan(editIds.indexOf("e6"));
  });

  it("marks conflict edits with the matching clause", () => {
    const rows = buildEditRows(d1Edits);
    const conflictEdits = rows.filter(
      (r): r is Extract<typeof r, { kind: "edit" }> =>
        r.kind === "edit" && r.conflictClause === "п. 7.1 Неустойка"
    );
    expect(conflictEdits.map((r) => r.edit.id).sort()).toEqual(["e2", "e7"]);
  });

  it("does not mark non-conflict edits with a conflict clause", () => {
    const rows = buildEditRows(d1Edits);
    const nonConflict = rows.filter(
      (r): r is Extract<typeof r, { kind: "edit" }> =>
        r.kind === "edit" && r.conflictClause !== "п. 7.1 Неустойка"
    );
    expect(nonConflict.every((r) => r.conflictClause === null)).toBe(true);
  });
});
