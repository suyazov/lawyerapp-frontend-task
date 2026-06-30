import { isOpenEdit, isOverdue } from "./domain";
import type { Edit } from "./types";

/** One visual row in the edits table. */
export type RowItem =
  | { kind: "conflict-header"; clause: string; edits: Edit[] }
  | { kind: "edit"; edit: Edit; conflictClause: string | null };

/** Aggregated counters shown in the document summary cards. */
export type EditSummary = {
  openCount: number;
  closedCount: number;
  candidates: Edit[];
  blockers: number;
  overdue: number;
  conflicts: [string, Edit[]][];
};

/** Return all clauses that have more than one *open* edit — these are conflicts. */
export function findConflicts(edits: Edit[]): [string, Edit[]][] {
  const byClause: Record<string, Edit[]> = {};
  edits.filter(isOpenEdit).forEach((e) => {
    byClause[e.clause] = byClause[e.clause] || [];
    byClause[e.clause].push(e);
  });
  return Object.entries(byClause).filter(([, arr]) => arr.length > 1);
}

/** Compute the summary numbers for the top-of-page cards. */
export function computeEditSummary(edits: Edit[]): EditSummary {
  const openCount = edits.filter(isOpenEdit).length;
  return {
    openCount,
    closedCount: edits.length - openCount,
    candidates: edits.filter((e) => e.status === "accepted" && !e.appliedIn),
    blockers: edits.filter((e) => e.tier === "blocker" && isOpenEdit(e)).length,
    overdue: edits.filter(isOverdue).length,
    conflicts: findConflicts(edits),
  };
}

/**
 * Build the ordered list of rows for the edits table.
 *
 * Rules:
 * 1. Open conflicts are shown first, each as a header followed by its edits
 *    sorted by date descending.
 * 2. Remaining edits are sorted by: open first, then risk score
 *    (blocker +2, overdue +1), then date descending.
 * 3. Closed edits stay visible (append-only) but fall to the bottom.
 */
export function buildEditRows(edits: Edit[]): RowItem[] {
  const conflicts = findConflicts(edits);
  const handled = new Set<string>();
  const conflictRows: RowItem[] = [];

  conflicts.forEach(([clause, ces]) => {
    conflictRows.push({ kind: "conflict-header", clause, edits: ces });
    ces
      .slice()
      .sort((a, b) => b.date.localeCompare(a.date))
      .forEach((e) => {
        conflictRows.push({ kind: "edit", edit: e, conflictClause: clause });
        handled.add(e.id);
      });
  });

  const remaining = edits.filter((e) => !handled.has(e.id));
  const sortedRemaining = remaining.slice().sort((a, b) => {
    const aOpen = isOpenEdit(a) ? 1 : 0;
    const bOpen = isOpenEdit(b) ? 1 : 0;
    if (aOpen !== bOpen) return bOpen - aOpen;

    const aRisk = (a.tier === "blocker" ? 2 : 0) + (isOverdue(a) ? 1 : 0);
    const bRisk = (b.tier === "blocker" ? 2 : 0) + (isOverdue(b) ? 1 : 0);
    if (aRisk !== bRisk) return bRisk - aRisk;

    return b.date.localeCompare(a.date);
  });

  return [
    ...conflictRows,
    ...sortedRemaining.map((e) => ({ kind: "edit", edit: e, conflictClause: null } as const)),
  ];
}
