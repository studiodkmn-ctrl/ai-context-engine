# ⚡ Quick Facts — [PROJECT_NAME]
> **Always load this file. Target: ≤150 tokens. Never grows — permanent facts only.**
> Last updated: [DATE]
> Temporary sprint info → `_temp_notes.md` | Technical pitfalls → `_gotchas.md`

---

## Identity
```
Project:  [PROJECT_NAME]
Stack:    [e.g. Next.js 14 App Router + Prisma + PostgreSQL + NextAuth v5]
Phase:    [MVP / Beta / Production]
Repo:     [local path or GitHub URL]
Verify-Command:  [optional — z.B. "npm run typecheck". Leer = auto-detect]
```
> `Verify-Command` nutzt der Verify-Loop (ai-verify.sh) nach einem Fix.
> Leer lassen für Auto-Erkennung; eintragen wenn ein bestimmtes (schnelles,
> nicht-interaktives) Kommando erzwungen werden soll.

---

## 📍 Key File Paths + Impact-Radius
> "Genutzt von"-Spalte zeigt welche Kontextdateien betroffen sind wenn diese Code-Datei geändert wird.
> ai-session-prep.sh nutzt diese Map für Cascade-Markierungen in _ai_index.md.

| Code-Datei | Zweck | Genutzt von (Kontext-Dateien) |
|---|---|---|
| `prisma/schema.prisma` | DB Schema | backend/database.md, backend/endpoints.md |
| `src/lib/auth.ts` | Auth Config | backend/auth.md, backend/endpoints.md, security.md |
| `src/lib/prisma.ts` | DB-Client Singleton | backend/database.md, backend/endpoints.md |
| `src/store/` | Global State | frontend/state.md, frontend/components.md |
| `src/app/api/` | API Routes | backend/endpoints.md |
| `src/components/` | UI Components | frontend/components.md |
| `src/types/` | Geteilte Types | frontend/components.md, backend/endpoints.md |
| `.env.example` | Env Vars Template | _quick_facts.md (diese Datei) |

---

## 🔑 Environment Variables (required to run)
```
DATABASE_URL        ← Prisma connection string
NEXTAUTH_SECRET     ← Min 32 chars
NEXTAUTH_URL        ← e.g. http://localhost:3000
[OTHER_KEY]         ← [what it's for]
```

---

## 🔗 Quick References (pointers — no content here)
```
Active sprint / current task  → _temp_notes.md
Technical gotchas             → _gotchas.md
Top debug patterns            → debug_patterns.md
Security rules                → security.md
Test strategy                 → testing.md
```

---
> RULE: This file is PERMANENT. No sprint info, no recent changes, no gotchas.
> Those belong in _temp_notes.md and _gotchas.md respectively.
