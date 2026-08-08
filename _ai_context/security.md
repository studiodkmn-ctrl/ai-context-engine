# 🔒 Security — ai-context-engine
> **Max 10 Regeln. Code-Format. Laden bei API/Auth-Tasks.**
> Aktualisiert: 2026-04-14
> P: 1=kritisch (nie löschen) | 2=wichtig (default) | 3=nice-to-know (zuerst archiviert)

## Regeln

<!-- #auth_first -->
```
RULE: auth_first
P: 1
scope: POST PUT PATCH DELETE
pattern:
  const session = await auth()
  if (!session?.user) return error(401)
  // ... dann Logik
violates: Auth-Check weglassen, nur auf Middleware verlassen
```
<!-- /auth_first -->

<!-- #no_secret_frontend -->
```
RULE: no_secret_frontend
P: 1
scope: client components, public API responses
pattern:
  ✗ process.env.SECRET_KEY     ← nur server-side
  ✓ process.env.NEXT_PUBLIC_*  ← nur diese im Client
violates: Secret in client bundle / API response
```
<!-- /no_secret_frontend -->

<!-- #input_validation -->
```
RULE: input_validation
P: 2
scope: alle Endpoints mit User-Input
pattern:
  const parsed = schema.safeParse(input)
  if (!parsed.success) return error(400, parsed.error)
  // ... nur parsed.data verwenden
violates: req.body direkt nutzen ohne Validation
```
<!-- /input_validation -->

<!-- #scope_to_user -->
```
RULE: scope_to_user
P: 2
scope: alle DB-Queries mit User-Daten
pattern:
  prisma.item.findMany({ where: { userId: session.user.id } })
  // NEVER: prisma.item.findMany() ohne user-scope
violates: Daten anderer User sichtbar/editierbar
```
<!-- /scope_to_user -->

<!-- #error_format -->
```
RULE: error_format
P: 2
scope: alle API-Responses
pattern:
  ✓ return { error: "message", code: 400 }
  ✗ return { message: e.message }   ← leakt Internals
  ✗ throw e                          ← roher Stack-Trace
```
<!-- /error_format -->

> REGELN: P1-Regeln niemals löschen. Überlauf >10 → P3 zuerst, dann prüfe ob älteste P2-Regel Framework-Default ist.
> seen: [YYYY-MM-DD] optional pro Regel (nach P: einfügen) — Frische-Status (fresh/check/orphan) landet in registry.yaml, siehe _gotchas.md#legende.
