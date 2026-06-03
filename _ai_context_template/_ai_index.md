# 🧠 AI Context Index — [PROJECT_NAME]
> **~200 Tokens. Immer laden. Erst Datei-Tabelle scannen → dann gezielt laden.**

## Projekt
```
Stack:    [PROJECT_STACK]
Phase:    [MVP / Beta / Production]
Git:      bae4ce0d64b4e9074ca08c3e0af7930345c45c4e
Session:  2026-04-29
```

## 📚 Datei-Tabelle (was steht wo drin?)
> Status: 🟢 aktuell · 🟡 leicht veraltet · 🔴 stark veraltet
> "Enthält"-Spalte zeigt was drin ist — entscheide damit ob Laden lohnt.

| Datei | Enthält | Status | Zuletzt |
|---|---|---|---|
| `architecture.md` | Stack, Struktur, Datenfluss | 🟢 | [DATE] |
| `decisions.md` | ADRs, verworfene Ansätze | 🟢 | [DATE] |
| `frontend/components.md` | UI-Komponenten, Patterns | 🟢 | [DATE] |
| `frontend/state.md` | Stores, Hooks, Context | 🟢 | [DATE] |
| `frontend/routing.md` | Routes, Nav, Pages | 🟢 | [DATE] |
| `backend/endpoints.md` | API-Routen, Methods, Auth | 🟢 | [DATE] |
| `backend/auth.md` | Auth-Strategie, Middleware | 🟢 | [DATE] |
| `backend/database.md` | Schema, Models, Migrations | 🟢 | [DATE] |
| `security.md` | Security-Rules (P1/P2/P3) | 🟢 | [DATE] |
| `testing.md` | Test-Strategie, Coverage | 🟢 | [DATE] |
| `_gotchas.md` | Bekannte Fallstricke (max 15) | 🟢 | [DATE] |
| `debug_patterns.md` | Bewährte Debug-Strategien | 🟢 | [DATE] |
| `current_sprint.md` | Aktive Tasks, Sprint-Stand | 🟢 | [DATE] |
| `_temp_notes.md` | Recent Changes, lose Notizen | 🟢 | [DATE] |
| `HANDOFF.md` | Session-Übergabe (wenn unfertig) | ⚪ | — |

## 🗂️ Domain-Router (zweistufig — für Routing)
| Domain | Index | Lade wenn... |
|---|---|---|
| Frontend | `_idx/frontend.md` | UI, Styling, State |
| Backend | `_idx/backend.md` | API, DB, Auth |
| Infra | `_idx/infra.md` | Tests, Security, Bugs |
| Projekt | `_idx/project.md` | Architektur, Planung |

## ⚡ Staleness
```
[Automatisch befüllt durch post-commit Hook]
```

## 📝 Letzte Änderungen (max 5)
```
- [DATE]: [Was sich geändert hat]
```

## 📦 Schubladen (Archiv-Pointer)
```
[Automatisch befüllt durch ai-context-drawer.sh wenn Overflow erkannt]
```
