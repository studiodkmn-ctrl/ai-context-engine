# 🔄 Frontend — State Management
**Status:** 🟢 Fresh · **Updated:** [DATE] · **Invalidated by:** `store/**`, `context/**`, `lib/store*`, `src/hooks/**`

---

## State Architecture
```
Global client state:  [e.g. Zustand / Redux Toolkit / Jotai / Context API]
Server state/cache:   [e.g. React Query / SWR — staleTime: 5min, retry: 2]
Form state:           [e.g. React Hook Form + Zod]
URL state:            [e.g. nuqs / useSearchParams]
Auth state:           [e.g. useSession() via NextAuth]
```

---

## Store Inventory
> Claude: Add new stores here as soon as they're created.

| Store | Path | Manages |
|---|---|---|
| `useUserStore` | `store/user.store.ts` | Logged-in user, preferences |
| `use[Name]Store` | `store/[name].store.ts` | [What it manages] |

---

## Store Pattern (Zustand)
```typescript
// Convention: always with devtools + immer middleware
import { create } from 'zustand'
import { devtools, persist } from 'zustand/middleware'

interface [Name]Store {
  [field]: [type]
  [action]: ([params]) => void
}

export const use[Name]Store = create<[Name]Store>()(
  devtools((set) => ({
    [field]: [initialValue],
    [action]: ([params]) => set((state) => ({ ... })),
  }))
)
```

---

## React Query Pattern
```typescript
const queryKeys = {
  [resource]: {
    all: [[resource]],
    list: (filters) => [[resource], 'list', filters],
    detail: (id) => [[resource], 'detail', id],
  }
}
// staleTime: 5 * 60 * 1000  |  retry: 2  |  refetchOnWindowFocus: false
```

---

## Auth State Access
```typescript
// Server Component:
import { auth } from '@/lib/auth'
const session = await auth()

// Client Component:
import { useSession } from 'next-auth/react'
const { data: session, status } = useSession()

// Protected routes: middleware.ts handles (dashboard)/** automatically
```

---

## Policy
```
- Zustand-Stores NUR in Client Components verwenden ('use client').
- Server Components greifen nur über auth() oder direkte DB-Queries auf Daten zu.
- Sensible Daten (Tokens, Passwörter) NIEMALS in persist()-Stores speichern.
- React Query Provider muss im Root-Layout eingebunden sein.
```

## Gotchas
```
- [e.g. "Zustand stores NOT in Server Components"]
- [e.g. "React Query Provider in root layout"]
- [e.g. "persist() writes to localStorage — avoid for sensitive data"]
```

---

## Update Log
```
[DATE] — Initial setup
```
