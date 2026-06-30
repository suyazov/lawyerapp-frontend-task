"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  ArrowLeft,
  Clock,
  Download,
  ExternalLink,
  Layers,
  MoreVertical,
  ShieldAlert,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Meta } from "@/components/ui-bits";
import { CreateVersionDialog } from "@/components/create-version-dialog";
import { DOCUMENTS, EDITS, PROJECTS, U, VERSIONS } from "@/lib/fixtures";
import { ST, TIER, TYPE, dmy, isOpenEdit, isOverdue } from "@/lib/domain";
import { buildEditRows, computeEditSummary } from "@/lib/timeline-helpers";
import type { RowItem } from "@/lib/timeline-helpers";
import type { Edit, EditStatus, Version } from "@/lib/types";
import { cn } from "@/lib/utils";

const iso = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

const pravkaWord = (n: number) => {
  const a = n % 10;
  const b = n % 100;
  if (a === 1 && b !== 11) return "правка";
  if (a >= 2 && a <= 4 && (b < 10 || b >= 20)) return "правки";
  return "правок";
};

export function TimelineView({ id }: { id: string }) {
  const router = useRouter();
  const doc = DOCUMENTS.find((x) => x.id === id);
  const [edits, setEdits] = useState<Edit[]>(() => EDITS.filter((e) => e.docId === id));
  const [vers, setVers] = useState<Version[]>(() => VERSIONS.filter((v) => v.docId === id));
  const [zrsId, setZrsId] = useState<string | null>(null);
  const [verOpen, setVerOpen] = useState(false);

  if (!doc) return <div className="text-sm text-muted-foreground">Документ не найден.</div>;

  const proj = PROJECTS.find((p) => p.id === doc.projectId)!;
  const current = vers.length ? [...vers].sort((a, b) => b.number - a.number)[0] : null;

  const { openCount, closedCount, candidates, blockers, overdue, conflicts } =
    computeEditSummary(edits);

  const downloadVersion = (v: Version) => {
    const lines = [
      `ДОКУМЕНТ — ${doc.title}`,
      `Проект: ${proj.title} (${proj.code})`,
      `Версия: ${v.code} · v${v.number} · от ${dmy(v.date)}`,
      `Файл-источник: ${v.note || "—"}`,
      "",
      "".padEnd(60, "="),
      "(прототип: здесь будет реальный файл версии — это демо-заглушка)",
    ];
    const blob = new Blob([lines.join("\r\n")], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${v.code}.txt`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  };

  const decide = (eid: string, status: EditStatus) => {
    setEdits((es) =>
      es.map((e) =>
        e.id === eid ? { ...e, status, approverId: status === "accepted" ? "ceo" : e.approverId } : e
      )
    );
    setZrsId(null);
    toast.success("Статус: " + ST[status].label + " · доказательство приложено");
  };
  const escalate = () => {
    setZrsId(null);
    toast("Эскалировано команде");
  };

  const nextNumber = vers.reduce((m, v) => Math.max(m, v.number), 0) + 1;
  const addVersion = ({
    note,
    fileName,
    appliedIds,
  }: {
    note: string;
    fileName: string;
    appliedIds: string[];
  }) => {
    const number = nextNumber;
    const code = `${proj.code}.${doc.code}.v${number}`;
    const v: Version = {
      id: `v-new-${number}`,
      docId: id,
      number,
      code,
      date: iso(new Date()),
      source: "uploaded",
      hash: "—",
      note: note || fileName,
    };
    setVers((vs) => [v, ...vs]);
    setEdits((es) => es.map((e) => (appliedIds.includes(e.id) ? { ...e, status: "applied", appliedIn: number } : e)));
    toast.success(`Версия ${code} добавлена`);
  };

  const rows: RowItem[] = buildEditRows(edits);

  const zrs = edits.find((e) => e.id === zrsId) || null;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">{doc.title}</h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            {proj.title} · {proj.counterparty} · история правок
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <Button variant="outline" size="sm" onClick={() => router.push(`/projects/${proj.id}`)}>
            <ArrowLeft className="size-4" />
            Назад
          </Button>
          <CreateVersionDialog
            nextCode={`${proj.code}.${doc.code}.v${nextNumber}`}
            candidates={candidates}
            onCreate={addVersion}
            open={verOpen}
            onOpenChange={setVerOpen}
          />
          {current && (
            <DropdownMenu>
              <DropdownMenuTrigger
                aria-label="Действия с версиями"
                className="flex h-8 w-8 items-center justify-center rounded-md border hover:bg-accent data-popup-open:bg-accent"
              >
                <MoreVertical className="size-4" />
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-64">
                <DropdownMenuItem onClick={() => downloadVersion(current)}>
                  <Download />
                  Скачать текущую версию
                  <span className="ml-auto font-mono text-xs text-muted-foreground">{current.code}</span>
                </DropdownMenuItem>
                <DropdownMenuSub>
                  <DropdownMenuSubTrigger>
                    <Download />
                    Скачать другую версию
                  </DropdownMenuSubTrigger>
                  <DropdownMenuSubContent className="w-52">
                    {[...vers].sort((a, b) => b.number - a.number).map((v) => (
                      <DropdownMenuItem key={v.id} onClick={() => downloadVersion(v)}>
                        <span className="font-mono text-xs">{v.code}</span>
                        <span className="ml-auto text-xs text-muted-foreground">{dmy(v.date)}</span>
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuSubContent>
                </DropdownMenuSub>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => setVerOpen(true)}>
                  <Layers />
                  Собрать новую версию
                  {candidates.length > 0 && (
                    <span className="ml-auto text-xs text-amber-600">
                      {candidates.length} {pravkaWord(candidates.length)}
                    </span>
                  )}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          )}
        </div>
      </div>

      <div className="grid grid-cols-5 gap-3">
        <SummaryCard
          label="Текущая версия"
          value={current ? current.code : "—"}
          sub={current ? `v${current.number} · ${dmy(current.date)}` : "нет версий"}
          tone="neutral"
        />
        <SummaryCard
          label="Открыто / закрыто"
          value={`${openCount} / ${closedCount}`}
          sub={candidates.length > 0 ? `${candidates.length} принято, не внесено` : undefined}
          tone={openCount > 0 ? "amber" : "emerald"}
        />
        <SummaryCard
          testId="summary-blockers"
          label="Блокеры"
          value={blockers}
          tone={blockers > 0 ? "red" : "neutral"}
        />
        <SummaryCard
          testId="summary-overdue"
          label="Просрочка"
          value={overdue}
          tone={overdue > 0 ? "red" : "neutral"}
        />
        <SummaryCard
          testId="summary-conflicts"
          label="Конфликты"
          value={conflicts.length}
          tone={conflicts.length > 0 ? "red" : "neutral"}
        />
      </div>

      <div>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="text-sm font-semibold">Правки</h2>
          <span className="text-xs text-muted-foreground">
            {edits.length} {pravkaWord(edits.length)}
          </span>
        </div>
        <div className="overflow-hidden rounded-lg border">
          <div className="grid grid-cols-[1fr_160px_150px_150px_110px] gap-4 border-b bg-muted/50 px-4 py-2.5 text-[11px] uppercase tracking-wide text-muted-foreground">
            <div>Пункт</div>
            <div>Ответственный</div>
            <div>Уровень</div>
            <div>Статус</div>
            <div>Дедлайн</div>
          </div>
          {edits.length === 0 && (
            <div className="px-4 py-10 text-center text-sm text-muted-foreground">Правок пока нет.</div>
          )}
          {rows.map((row) => {
            if (row.kind === "conflict-header") {
              const names = row.edits.map((e) => U(e.responsibleId));
              return (
                <div
                  key={`conflict-${row.clause}`}
                  className="border-b border-amber-200 bg-amber-50/60 px-4 py-2"
                >
                  <div className="flex items-center gap-2 text-xs text-amber-800">
                    <AlertTriangle className="size-3.5 shrink-0" />
                    <span className="font-medium">Конфликт · {row.clause}</span>
                    <span className="text-amber-700/70">{names.join(" vs ")}</span>
                  </div>
                </div>
              );
            }

            const e = row.edit;
            const closed = !isOpenEdit(e);
            return (
              <div
                key={e.id}
                data-testid={`edit-row-${e.id}`}
                onClick={() => setZrsId(e.id)}
                className={cn(
                  "grid cursor-pointer grid-cols-[1fr_160px_150px_150px_110px] items-center gap-4 border-b px-4 py-3 last:border-0 hover:bg-muted/40",
                  closed && "text-muted-foreground/60"
                )}
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-1.5 text-sm font-medium">
                    {e.clause}
                    {e.tier === "blocker" && isOpenEdit(e) && (
                      <ShieldAlert className="size-3.5 shrink-0 text-red-500" />
                    )}
                    {isOverdue(e) && <Clock className="size-3.5 shrink-0 text-red-500" />}
                  </div>
                  <div className="mt-0.5 truncate text-xs text-muted-foreground">{TYPE[e.type]}</div>
                </div>
                <div className="truncate text-sm">{U(e.responsibleId)}</div>
                <div className="min-w-0">
                  <Meta m={TIER[e.tier]} className={closed ? "opacity-60" : ""} />
                </div>
                <div className="min-w-0">
                  <Meta m={ST[e.status]} className={closed ? "opacity-60" : ""} />
                </div>
                <div
                  className={cn(
                    "text-sm tabular-nums",
                    isOverdue(e) && "font-medium text-red-600",
                    closed && "text-muted-foreground/60"
                  )}
                >
                  {dmy(e.deadline)}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      <Dialog open={!!zrs} onOpenChange={(o) => !o && setZrsId(null)}>
        <DialogContent className="max-w-2xl">
          {zrs && <ZrsBody edit={zrs} onDecide={decide} onEscalate={escalate} />}
        </DialogContent>
      </Dialog>
    </div>
  );
}

function SummaryCard({
  label,
  value,
  sub,
  tone = "neutral",
  testId,
}: {
  label: string;
  value: React.ReactNode;
  sub?: React.ReactNode;
  tone?: "neutral" | "amber" | "red" | "emerald";
  testId?: string;
}) {
  const toneClass = {
    neutral: "text-foreground",
    amber: "text-amber-600",
    red: "text-red-600",
    emerald: "text-emerald-600",
  }[tone];

  return (
    <Card size="sm" data-testid={testId}>
      <CardContent className="space-y-1">
        <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</div>
        <div className={cn("text-lg font-semibold leading-tight", toneClass)}>{value}</div>
        {sub && <div className="text-xs text-muted-foreground">{sub}</div>}
      </CardContent>
    </Card>
  );
}

function ZrsBody({
  edit,
  onDecide,
  onEscalate,
}: {
  edit: Edit;
  onDecide: (id: string, s: EditStatus) => void;
  onEscalate: () => void;
}) {
  const tier = TIER[edit.tier];
  const blocker = edit.tier === "blocker";

  return (
    <>
      <DialogHeader>
        <div className="text-[11px] uppercase tracking-wide text-muted-foreground">
          ЗРС · законченная работа сотрудника
        </div>
        <DialogTitle className="text-base">{edit.clause}</DialogTitle>
        <div className="mt-1.5 flex items-center gap-3">
          <Meta m={ST[edit.status]} />
          <span className="text-border">·</span>
          <Meta m={tier} />
        </div>
      </DialogHeader>

      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-px overflow-hidden rounded-lg border bg-border text-sm">
          <div className="bg-background p-3">
            <div className="mb-1 text-[11px] uppercase tracking-wide text-muted-foreground">Было</div>
            <div className="text-muted-foreground">{edit.before || <span className="italic">новый пункт</span>}</div>
          </div>
          <div className="bg-background p-3">
            <div className="mb-1 text-[11px] uppercase tracking-wide text-muted-foreground">Стало</div>
            <div>{edit.after}</div>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          {(
            [
              ["Тип", TYPE[edit.type]],
              ["Ответственный", U(edit.responsibleId)],
              ["Автор", U(edit.authorId)],
              ["Дедлайн", dmy(edit.deadline)],
            ] as [string, string][]
          ).map(([k, v]) => (
            <div key={k}>
              <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{k}</div>
              <div className={cn("font-medium", k === "Дедлайн" && isOverdue(edit) && "text-red-600")}>
                {v}
              </div>
            </div>
          ))}
        </div>

        <div>
          <div className="mb-1 text-[11px] uppercase tracking-wide text-muted-foreground">Аргументация</div>
          <div className="rounded-md bg-muted p-3 text-sm text-foreground/80">{edit.argument}</div>
        </div>
        {edit.privateNote && (
          <div>
            <div className="mb-1 text-[11px] uppercase tracking-wide text-muted-foreground">
              Приватная заметка юриста
            </div>
            <div className="rounded-md bg-muted p-3 text-sm text-foreground/80">{edit.privateNote}</div>
          </div>
        )}
        <div className="flex flex-wrap gap-2 text-xs text-muted-foreground">
          {edit.bitrix && (
            <span className="inline-flex items-center gap-1 rounded-md border px-2 py-1">
              <ExternalLink className="size-3" />
              Битрикс
            </span>
          )}
          {edit.proof && <span className="rounded-md border px-2 py-1">{edit.proof}</span>}
          {edit.appliedIn && <span className="rounded-md border px-2 py-1">в версии v{edit.appliedIn}</span>}
        </div>
      </div>

      <div className="mt-2 border-t pt-4">
        {blocker ? (
          <>
            <div className="mb-3 flex items-start gap-2 text-xs text-muted-foreground">
              <AlertTriangle className="mt-0.5 size-3.5 shrink-0 text-red-500" />
              <span>{tier.hint}</span>
            </div>
            <div className="flex gap-2">
              <Button className="flex-1" onClick={onEscalate}>
                Эскалировать команде
              </Button>
              <Button variant="outline" className="flex-1" onClick={() => onDecide(edit.id, "rework")}>
                На доработку
              </Button>
            </div>
          </>
        ) : (
          <>
            <div className="mb-2 text-xs text-muted-foreground">{tier.hint}</div>
            <div className="flex gap-2">
              <Button className="flex-1" onClick={() => onDecide(edit.id, "accepted")}>
                Принято
              </Button>
              <Button variant="outline" className="flex-1" onClick={() => onDecide(edit.id, "rework")}>
                На доработку
              </Button>
              <Button
                variant="outline"
                className="flex-1 text-red-600"
                onClick={() => onDecide(edit.id, "rejected")}
              >
                Отклонено
              </Button>
            </div>
          </>
        )}
      </div>
    </>
  );
}
