# 🗺️ Routing — /Users/adnandikmen/Desktop/test-kontext
> **~150 Tokens. Laden bei Routing/Navigation-Aufgaben.**
> Zuletzt aktualisiert: 2026-04-14

## Routing-Typ
```
Framework:    [z.B. Next.js App Router / React Router v6 / Vue Router]
Strategie:    [z.B. file-based / config-based]
```

## Routen-Struktur
```
/                    → Landing/Home
/dashboard           → geschützt (user+)
/admin               → geschützt (admin)
/auth/login          → öffentlich
/auth/register       → öffentlich
/api/*               → API-Routen (siehe backend/endpoints.md)
```

## Geschützte Routen
```
Middleware:    [z.B. middleware.ts prüft auf / dashboard, /admin]
Redirect:     [z.B. → /auth/login wenn nicht authentifiziert]
```

---
> Writeback: Neue Route → Struktur oben ergänzen.
