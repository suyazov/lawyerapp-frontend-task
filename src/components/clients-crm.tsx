"use client";

import { FormEvent, useMemo, useState, useSyncExternalStore } from "react";
import { Phone, Plus, Trash2, Users } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

const STORAGE_KEY = "lawyerapp:clients-crm:v1";

const STATUS_LABELS = {
  new: "Новый",
  working: "В работе",
  closed: "Закрыт",
} as const;

type ClientStatus = keyof typeof STATUS_LABELS;

type Client = {
  id: string;
  name: string;
  phone: string;
  status: ClientStatus;
  createdAt: string;
};

const DEMO_CLIENTS: Client[] = [
  {
    id: "demo-1",
    name: "Мария Соколова",
    phone: "+7 903 123-45-67",
    status: "new",
    createdAt: "2026-07-05T09:30:00.000Z",
  },
  {
    id: "demo-2",
    name: "Игорь Петров",
    phone: "+7 915 222-18-40",
    status: "working",
    createdAt: "2026-07-05T10:10:00.000Z",
  },
  {
    id: "demo-3",
    name: "ООО «Север»",
    phone: "+7 495 000-00-10",
    status: "closed",
    createdAt: "2026-07-04T14:45:00.000Z",
  },
  {
    id: "demo-4",
    name: "Андрей Климов",
    phone: "+7 999 800-70-60",
    status: "working",
    createdAt: "2026-07-03T12:15:00.000Z",
  },
];

function statusTone(status: ClientStatus) {
  if (status === "new") return "border-blue-200 bg-blue-50 text-blue-700 dark:border-blue-900/60 dark:bg-blue-950/40 dark:text-blue-300";
  if (status === "working") return "border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-900/60 dark:bg-amber-950/40 dark:text-amber-300";
  return "border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-900/60 dark:bg-emerald-950/40 dark:text-emerald-300";
}

let cachedClients: Client[] = DEMO_CLIENTS;

function refreshClients() {
  if (typeof window === "undefined") return;
  try {
    const saved = window.localStorage.getItem(STORAGE_KEY);
    if (!saved) {
      cachedClients = DEMO_CLIENTS;
      return;
    }
    const parsed = JSON.parse(saved) as Client[];
    cachedClients = Array.isArray(parsed) ? parsed : DEMO_CLIENTS;
  } catch {
    cachedClients = DEMO_CLIENTS;
  }
}

function subscribeClients(callback: () => void) {
  const handler = (event: StorageEvent) => {
    if (event.key === STORAGE_KEY) {
      refreshClients();
      callback();
    }
  };
  window.addEventListener("storage", handler);
  return () => window.removeEventListener("storage", handler);
}

function useClients() {
  return useSyncExternalStore<Client[]>(
    subscribeClients,
    () => cachedClients,
    () => DEMO_CLIENTS
  );
}

function writeClients(clients: Client[]) {
  if (typeof window === "undefined") return;
  cachedClients = clients;
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(clients));
  window.dispatchEvent(new StorageEvent("storage", { key: STORAGE_KEY }));
}

// After hydration refresh the cache from localStorage so persisted data is shown.
if (typeof window !== "undefined" && typeof document !== "undefined") {
  const refresh = () => {
    refreshClients();
    window.dispatchEvent(new StorageEvent("storage", { key: STORAGE_KEY }));
  };
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", refresh, { once: true });
  } else {
    refresh();
  }
}

export function ClientsCrm() {
  const clients = useClients();
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [status, setStatus] = useState<ClientStatus>("new");
  const [error, setError] = useState("");

  const counts = useMemo(() => {
    return clients.reduce(
      (acc, client) => {
        acc[client.status] += 1;
        return acc;
      },
      { new: 0, working: 0, closed: 0 } satisfies Record<ClientStatus, number>
    );
  }, [clients]);

  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!name.trim()) {
      setError("Укажите имя клиента или название компании");
      return;
    }

    const nextClient: Client = {
      id: `client-${Date.now()}`,
      name: name.trim(),
      phone: phone.trim(),
      status,
      createdAt: new Date().toISOString(),
    };

    writeClients([nextClient, ...clients]);
    setName("");
    setPhone("");
    setStatus("new");
    setError("");
  };

  const updateStatus = (clientId: string, nextStatus: ClientStatus) => {
    writeClients(clients.map((client) => (client.id === clientId ? { ...client, status: nextStatus } : client)));
  };

  const removeClient = (clientId: string) => {
    writeClients(clients.filter((client) => client.id !== clientId));
  };

  const resetDemo = () => {
    writeClients(DEMO_CLIENTS);
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <div className="mb-2 inline-flex items-center gap-2 rounded-full border bg-muted/40 px-3 py-1 text-xs text-muted-foreground">
            <Users className="size-3.5" />
            Mini CRM для юриста
          </div>
          <h1 className="text-2xl font-semibold tracking-tight">Клиенты и статусы дел</h1>
          <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
            Быстрый прототип: юрист добавляет клиента, меняет статус дела и сразу видит распределение обращений по воронке.
          </p>
        </div>
        <Button variant="outline" onClick={resetDemo}>
          Вернуть демо-данные
        </Button>
      </div>

      <div className="grid gap-3 md:grid-cols-3">
        {(Object.keys(STATUS_LABELS) as ClientStatus[]).map((key) => (
          <div key={key} className={`rounded-xl border p-4 ${statusTone(key)}`}>
            <div className="text-sm font-medium">{STATUS_LABELS[key]}</div>
            <div className="mt-2 text-3xl font-semibold tabular-nums">{counts[key]}</div>
            <div className="mt-1 text-xs opacity-80">клиентов в статусе</div>
          </div>
        ))}
      </div>

      <form onSubmit={onSubmit} className="rounded-xl border bg-card p-4 shadow-sm">
        <div className="mb-3 flex items-center gap-2 text-sm font-medium">
          <Plus className="size-4" />
          Добавить клиента
        </div>
        <div className="grid gap-3 md:grid-cols-[1fr_180px_160px_auto] md:items-start">
          <div>
            <Input value={name} onChange={(event) => setName(event.target.value)} placeholder="Имя клиента или компания" />
            {error && <div className="mt-1 text-xs text-destructive">{error}</div>}
          </div>
          <Input value={phone} onChange={(event) => setPhone(event.target.value)} placeholder="Телефон" />
          <select
            value={status}
            onChange={(event) => setStatus(event.target.value as ClientStatus)}
            className="h-8 rounded-lg border border-input bg-background px-2.5 text-sm outline-none transition-colors focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
          >
            {(Object.entries(STATUS_LABELS) as [ClientStatus, string][]).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
          <Button type="submit">Добавить</Button>
        </div>
      </form>

      <div className="overflow-hidden rounded-xl border bg-card shadow-sm">
        <div className="grid grid-cols-[1.3fr_160px_160px_44px] gap-4 border-b bg-muted/50 px-4 py-2.5 text-[11px] uppercase tracking-wide text-muted-foreground max-md:hidden">
          <div>Клиент</div>
          <div>Телефон</div>
          <div>Статус</div>
          <div />
        </div>

        {clients.length === 0 ? (
          <div className="px-4 py-10 text-center text-sm text-muted-foreground">Клиентов пока нет. Добавьте первого клиента через форму выше.</div>
        ) : (
          <div className="divide-y">
            {clients.map((client) => (
              <div key={client.id} className="grid gap-3 px-4 py-3 text-sm md:grid-cols-[1.3fr_160px_160px_44px] md:items-center md:gap-4">
                <div className="min-w-0">
                  <div className="truncate font-medium">{client.name}</div>
                  <div className="text-xs text-muted-foreground">
                    Добавлен {new Date(client.createdAt).toLocaleDateString("ru-RU", { day: "2-digit", month: "2-digit", year: "numeric" })}
                  </div>
                </div>
                <div className="flex items-center gap-1.5 text-muted-foreground">
                  <Phone className="size-3.5" />
                  <span className="truncate">{client.phone || "не указан"}</span>
                </div>
                <select
                  value={client.status}
                  onChange={(event) => updateStatus(client.id, event.target.value as ClientStatus)}
                  className="h-8 rounded-lg border border-input bg-background px-2.5 text-sm outline-none transition-colors focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
                  aria-label={`Статус клиента ${client.name}`}
                >
                  {(Object.entries(STATUS_LABELS) as [ClientStatus, string][]).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
                <Button variant="ghost" size="icon" onClick={() => removeClient(client.id)} aria-label={`Удалить ${client.name}`}>
                  <Trash2 className="size-4" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
