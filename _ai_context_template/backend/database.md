# 🗄️ Backend — Database
**Status:** 🟢 Fresh · **Updated:** [DATE] · **Invalidated by:** `prisma/schema.prisma`, new migration in `prisma/migrations/`

---

## Setup
```
ORM:        Prisma [VERSION]
Database:   [PostgreSQL / MySQL / SQLite]
Host:       [e.g. Supabase / Railway / local]
Client:     src/lib/prisma.ts → import { prisma } from '@/lib/prisma'
            ← NEVER use new PrismaClient() directly
```

---

## Schema Overview
> Claude: Update this table whenever `schema.prisma` changes.

```
User
├── id (String, cuid)
├── email (String, unique)
├── name (String?)
├── createdAt, updatedAt
├── → Session[] (1:n, NextAuth)
└── → [YourModel][] (1:n)

[YourModel]
├── id (String, cuid)
├── [fields...]
├── userId (FK → User)
└── createdAt, updatedAt
```

**Relations:**
```
User ──< [Model1]
     ──< [Model2] ──< [Model3]
```

---

## Prisma Patterns
```typescript
// Standard queries:
await prisma.[model].findMany({
  where: { userId: session.user.id },
  orderBy: { createdAt: 'desc' },
  take: 20,
})

await prisma.[model].create({
  data: { ...validatedData, userId: session.user.id }
})

// Transactions:
await prisma.$transaction([
  prisma.[model1].update(...),
  prisma.[model2].delete(...),
])
```

---

## Migrations Log
> Claude: Add new migrations here.

| Date | Migration Name | What Changed |
|---|---|---|
| [DATE] | `init` | Initial schema |
| [DATE] | `add_[field]_to_[model]` | [Description] |

---

## Prisma Commands (Reference)
```bash
npx prisma migrate dev --name [description]   # Apply schema (dev)
npx prisma migrate deploy                      # Apply schema (prod)
npx prisma generate                            # Regenerate client after schema change
npx prisma studio                              # GUI
npx prisma migrate reset                       # Reset DB (dev only!)
```

---

## Gotchas
```
- [e.g. "CASCADE delete configured: User → Posts (onDelete: Cascade)"]
- [e.g. "Prisma returns DateTime as JS Date — handle when serializing to JSON"]
- [e.g. "Supabase: DATABASE_URL (pooled) vs DIRECT_URL (direct) — both needed"]
- [e.g. "After schema.prisma change: ALWAYS run 'prisma generate'"]
```

---

## Update Log
```
[DATE] — Initial setup
```
