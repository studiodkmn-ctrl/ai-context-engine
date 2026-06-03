# 🔄 Frontend — State Management — Extended
> Erweiterte Einträge. Core: `frontend/state_core.md`

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
2026-04-14 — Initial setup
```
