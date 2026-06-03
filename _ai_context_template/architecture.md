# 🏗️ Architecture Overview
**Status:** 🟢 Fresh · **Updated:** [DATE] · **Invalidated by:** `package.json`, `next.config.*`, `vite.config.*`

---

## Stack

| Ebene | Technologie | Anmerkung |
|---|---|---|
| Frontend | [z.B. Next.js 14 (App Router)] | Server Components wo möglich |
| Styling | [z.B. Tailwind CSS v4] | Utility-first, kaum Custom CSS |
| UI-Library | [z.B. shadcn/ui + Radix] | Nur via `npx shadcn add` installieren |
| Backend | [z.B. Next.js API Routes] | Co-located im App Router |
| ORM | [z.B. Prisma 5] | Singleton in `lib/prisma.ts` |
| Datenbank | [z.B. PostgreSQL (Supabase)] | Connection Pooling beachten |
| Auth | [z.B. NextAuth v5] | JWT Strategy, NICHT v4 |
| State | [z.B. Zustand + React Query] | Client- + Server-State getrennt |
| Deployment | [z.B. Vercel + Railway] | CI/CD später ergänzen |

---

## Project Structure
```
[PROJECT_NAME]/
├── src/
│   ├── app/                    → Next.js App Router
│   │   ├── (auth)/             → Auth group (login, register)
│   │   ├── (dashboard)/        → Protected pages
│   │   ├── api/                → API Routes
│   │   └── layout.tsx          → Root Layout
│   ├── components/
│   │   ├── ui/                 → Base components (Button, Input...)
│   │   ├── layout/             → Header, Footer, Sidebar
│   │   └── features/           → Feature components
│   ├── lib/
│   │   ├── prisma.ts           → Prisma singleton ← NEVER new PrismaClient()
│   │   ├── auth.ts             → Auth config
│   │   └── utils.ts            → Shared utilities
│   ├── store/                  → Global state (Zustand)
│   └── types/                  → TypeScript types
├── prisma/
│   ├── schema.prisma           → DB schema (single source of truth)
│   └── migrations/             → Migration history
└── _ai_context/                → Claude context files (this folder)
```

---

## Module Responsibilities

| Module / Folder | Responsible for |
|---|---|
| `src/app/api/` | HTTP handlers, request validation, response formatting |
| `src/lib/prisma.ts` | DB connection, singleton pattern |
| `src/lib/auth.ts` | Session management, auth config |
| `src/store/` | Global client-side state |
| `src/components/features/` | Business logic in components |
| `prisma/schema.prisma` | Single source of truth for DB structure |

---

## Data Flow

**Beispiel: Authentifizierter API-Call**
```
User klickt Button im Dashboard
  → Client Component ruft React Query Hook auf
  → Hook trifft Next.js API Route /api/[resource]
  → Route: auth-check → Zod-Validierung → prisma.[model].findMany(...)
  → PostgreSQL Query
  ← Prisma Result
  ← JSON Response { data: [...] }
  ← UI re-render mit neuen Daten
```

---

## Key Architecture Decisions (details → decisions.md)
```
- [e.g. App Router over Pages Router → Server Components, smaller bundle]
- [e.g. Prisma over Drizzle → TypeScript integration, schema-as-source-of-truth]
- [e.g. Zustand over Redux → less boilerplate, simpler API]
```

---

## Update Log
```
[DATE] — Initial setup: architecture file created
```
