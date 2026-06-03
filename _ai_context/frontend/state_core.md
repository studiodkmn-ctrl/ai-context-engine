# 🔄 Frontend — State Management — Core
> Automatisch gesplittet aus `frontend/state.md` (      97 Zeilen > 80).
> Extended-Einträge: `frontend/state_extended.md`

**Status:** 🟢 Fresh · **Updated:** 2026-04-14 · **Invalidated by:** `store/**`, `context/**`, `lib/store*`, `src/hooks/**`

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
