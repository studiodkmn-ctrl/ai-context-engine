# 🌐 Endpoints — [PROJECT_NAME]
> **Laden bei API-Route-Tasks. Pointer: Auth → `backend/auth.md`**
> Aktualisiert: [DATE]

## Config
```
base:    /api/v1
auth:    ⇒ backend/auth.md
errors:  { error: string, code: number }
validate: ⇒ security.md#input_validation
```

## Routes
| Method | Path | Auth | Beschreibung |
|---|---|---|---|
| GET | /api/health | - | Health-Check |

## Response-Pattern
```
✓ { data: T, meta?: { total } }
✗ { users: [...] }              ← kein Wrapper
✗ { message: "ok", result: T }  ← inkonsistent
```

> Writeback: Neuer Endpoint → Tabelle. Auth → `backend/auth.md`
