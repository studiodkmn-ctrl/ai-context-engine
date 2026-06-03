# 🧠 _SESSION.md — Pre-assembled Context (Auto-Generated)
> **Diese Datei wurde automatisch generiert. Nicht manuell editieren.**
> Neu generieren: `bash _ai_context/scripts/ai-session-prep.sh`

---

## 🎯 Behavior Rules (MUST apply)

Diese Regeln überschreiben das Default-Verhalten und müssen strikt angewendet werden:

1. **Bei Fehlerberichten / Stack-Traces / Bug-Meldungen**:
   BEVOR du antwortest, scanne `_gotchas.md` und `debug_patterns.md` nach einer passenden ID.
   Bei Match antworte zuerst mit: `Bekannter Fehler gefunden (Priorität: P{N}): {ID}`
   Dann zeige den Fix. Bei mehreren betroffenen Dateien biete Auto-Fix für alle an.

2. **Bei Code-Aufgaben** (Route/Komponente/Schema erstellen):
   Sage zuerst explizit welche Kontextdateien du liest, z.B.:
   `Ich lese backend/endpoints.md und backend/database.md...`
   Dann erstelle den Code mit automatisch angewendeten Projektregeln aus Quick Facts.

3. **Bei Sprint-/Status-Fragen** ("Was haben wir diese Woche gemacht?"):
   Lade `_temp_notes.md` + `git log --since='7 days ago' --oneline`.
   Zeige im Format:
   ```
   ✅ Abgeschlossen: <bullet list>
   🔨 In Arbeit:    <bullet list>
   📋 Offen:         <bullet list>
   ```

4. **Projektregeln sind verbindlich**: Auth-Check, Prisma-Singleton, etc. aus Quick Facts
   wendest du bei neuem Code automatisch an — kein Disclaimer, keine Nachfrage nötig.

5. **Sprachregel**: Kommunikation Deutsch, Code & Identifier Englisch.

6. **Session-Übergabe** (HANDOFF.md):
   → Bei Session-Start: Falls HANDOFF-Sektion unten "Status: in_progress" zeigt,
     LIES sie zuerst und setze die Arbeit dort fort.
   → Bei Session-Ende: Wenn Aufgabe NICHT fertig ist, schreibe Zustand
     in `HANDOFF.md` (Status, Was läuft, Nächster Schritt, Geänderte Dateien).
     Wenn Aufgabe FERTIG ist: HANDOFF.md leeren oder `Status: done` setzen.

---

## ⚡ Quick Facts

## Identity
```
Project:  [PROJECT_NAME]
Stack:    [e.g. Next.js 14 App Router + Prisma + PostgreSQL + NextAuth v5]
Phase:    [MVP / Beta / Production]
Repo:     [local path or GitHub URL]
```

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


---

## 📊 Session Status
```
Generiert:      2026-04-29 18:44
Git Hash:       bae4ce0d64b4
Letzter Commit: feat: v6.1 — HANDOFF.md + erweiterter _ai_index.md mit Datei-Tabelle
Domain-Fokus:   auto-detect
```

### 📝 Letzte Commits
```
bae4ce0 feat: v6.1 — HANDOFF.md + erweiterter _ai_index.md mit Datei-Tabelle
fafdd24 feat: v6.0.1 — block-mode PII hook, regex edge-case fixes, English README
698f2fb feat: universal IDE integration + behavior rules + session tracking
80c43d6 feat: clean terminal output + local data anonymization (ai-anon.sh)
7f6703b docs: fix clone URL to match actual repo name
```

---

## 🗂️ Kontext-Router (Zweistufig)

## 🗂️ Domain-Router (zweistufig — für Routing)
| Domain | Index | Lade wenn... |
|---|---|---|
| Frontend | `_idx/frontend.md` | UI, Styling, State |
| Backend | `_idx/backend.md` | API, DB, Auth |
| Infra | `_idx/infra.md` | Tests, Security, Bugs |
| Projekt | `_idx/project.md` | Architektur, Planung |

## ⚡ Staleness

### Domain-Indizes (alle)

#### backend
| Datei | Status | Tokens | TL;DR |
|---|---|---|---|
| `backend/endpoints.md` | ✅ | ~250 | [API-Routen, Methods, Auth-Requirements] |
| `backend/auth.md` | ✅ | ~200 | [Auth-Strategie, Token-Handling, Middleware] |
| `backend/database.md` | ✅ | ~370 | [Schema, Relationen, Migrations-Status] |


#### frontend
| Datei | Status | Tokens | TL;DR |
|---|---|---|---|
| `frontend/components.md` | ✅ | ~290 | [Komponenten-Inventar, Key-Components] |
| `frontend/state.md` | ✅ | ~445 | [State-Strategie, Stores, Hooks] |
| `frontend/routing.md` | ✅ | ~150 | [Routing-Struktur, geschützte Routen] |


#### infra
| Datei | Status | Tokens | TL;DR |
|---|---|---|---|
| `security.md` | ✅ | ~540 | [Sicherheitsregeln, Auth-Constraints] |
| `testing.md` | ✅ | ~546 | [Test-Framework, Coverage-Ziel, Patterns] |
| `debug_patterns.md` | ✅ | ~490 | [Wiederkehrende Fehler + Lösungen] |


#### project
| Datei | Status | Tokens | TL;DR |
|---|---|---|---|
| `architecture.md` | ✅ | ~498 | [Stack-Überblick, Module, Datenfluss] |
| `decisions.md` | ✅ | ~297 | [ADRs, abgelehnte Alternativen] |
| `_temp_notes.md` | ✅ | ~258 | [Sprint-Ziel, aktive Tasks, Recent Changes] |

---

## ⚡ Gotchas (2 total, P1 inline)

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
```
RULE: no_secret_frontend
P: 1
scope: client components, public API responses
pattern:
  ✗ process.env.SECRET_KEY     ← nur server-side
  ✓ process.env.NEXT_PUBLIC_*  ← nur diese im Client
violates: Secret in client bundle / API response
```



## 📋 Runtime-Regeln
```
ROUTER:   Micro-Index → Domain-Index → Kontextdatei (max 3 Dateien pro Kette)
LADEN:    Max 4 Dateien pro Session gesamt
GOTCHAS:  Immer bei Coding-Tasks (oben inline wenn vorhanden)
WRITE:    Nach jeder Aufgabe → relevante Kontextdatei + Domain-Index Status aktualisieren
DEDUP:    Vor Writeback IDs prüfen → Update statt Duplikat
LIMITS:   _gotchas.md/debug_patterns.md max 15 | security.md/testing.md max 10 | _temp_notes max 5
SPLIT:    Datei > 500 Tokens? → Aufteilen in kleinere Domain-Dateien
SCAN:     Domain-Router beachten — nur Dateien aus relevanter Domain laden
NIE:      Ganzen Codebase laden | Alle Kontextdateien auf einmal | Stack raten
```
