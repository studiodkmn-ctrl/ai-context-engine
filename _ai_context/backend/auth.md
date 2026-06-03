# 🔐 Auth — /Users/adnandikmen/Desktop/test-kontext
> **Laden bei Auth/Login/Middleware-Tasks.**
> Aktualisiert: 2026-04-14

## Config
```
provider:  [NextAuth v5 / Clerk / Supabase Auth]
session:   [JWT / Cookie]
expires:   [30d]
```

## Pattern
```
# Jede geschützte Route:
const session = await auth()           ← ⇒ security.md#auth_first
if (!session?.user) return error(401)

# Middleware:
matcher: ["/api/:path*"]
exclude: ["/api/public/:path*", "/api/health"]
```

## Rollen
```
admin → /api/admin/*    (alle Methoden)
user  → /api/user/*     (alle Methoden)
-     → /api/public/*   (nur GET)
```

> Writeback: Neue Rolle/Route → hier. Neuer Endpoint → `backend/endpoints.md`
