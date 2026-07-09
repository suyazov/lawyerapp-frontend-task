import { BarChart3, List, ShieldAlert, SquarePen, UserRoundCheck, type LucideIcon } from "lucide-react";

export type NavItem = { label: string; href: string; icon: LucideIcon };

export const NAV: NavItem[] = [
  { label: "Реестр договоров", href: "/", icon: List },
  { label: "Клиенты", href: "/clients", icon: UserRoundCheck },
  { label: "Мои правки", href: "/my", icon: SquarePen },
  { label: "Блокеры", href: "/blockers", icon: ShieldAlert },
  { label: "Отчёты", href: "/reports", icon: BarChart3 },
];
