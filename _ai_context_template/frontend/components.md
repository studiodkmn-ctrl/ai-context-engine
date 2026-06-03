# 🎨 Frontend — Components
**Status:** 🟢 Fresh · **Updated:** [DATE] · **Invalidated by:** `src/components/**`, `src/app/**/page.tsx`, `tailwind.config.*`

---

## Component Inventory

> **Pflicht-Regel:**
> - Neue sichtbare UI-Komponente erstellt → **sofort hier eintragen**.
> - Komponente gelöscht/umbenannt → **Tabelle sofort aktualisieren**.
> - Claude: Diese Tabelle ist der Grund, warum du keine Ordner scannen musst.

| Component | Path | Purpose | Key Props |
|---|---|---|---|
| `Button` | `components/ui/button.tsx` | Base button | `variant`, `size`, `onClick` |
| `Header` | `components/layout/header.tsx` | Top navigation | `user`, `onLogout` |
| `[NAME]` | `components/features/[...].tsx` | [Purpose] | [Props] |

---

## Pages & Routing
```
src/app/
├── (auth)/
│   ├── login/page.tsx          → Login form
│   └── register/page.tsx       → Registration
├── (dashboard)/
│   ├── layout.tsx              → Dashboard layout (auth guard)
│   ├── page.tsx                → Dashboard overview
│   └── [feature]/page.tsx      → Feature page
└── layout.tsx                  → Root layout (providers, theme)
```

---

## Styling Conventions
```
System:       Tailwind CSS utility-first
Dark mode:    [class / media / disabled]
Breakpoints:  mobile-first (sm: md: lg: xl: 2xl:)
Components:   [e.g. card-based, rounded-xl shadow-sm]

Custom CSS:   ONLY in globals.css (resets + CSS vars)
              Exception: complex animations only
```

---

## Gotchas
```
- [e.g. "Next.js Image always needs width+height or fill+sizes"]
- [e.g. "'use client' only when truly needed — default is Server Component"]
- [e.g. "Suspense boundaries around all async Server Components"]
- [e.g. "shadcn components via 'npx shadcn add [name]' — never manually"]
```

---

## Update Log
```
[DATE] — Initial setup
```
