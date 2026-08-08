# CLAUDE.md — AI Context System v8
> Lebt in `~/.claude/CLAUDE.md` oder `/projekt/CLAUDE.md`. Details: `README.md`.

## Sprache
Kommunikation: **Deutsch** | Code + Architektur: **Englisch**

## Session-Kontext
`_ai_context/_SESSION.md` wird per SessionStart-Hook automatisch injiziert —
kein manueller Read nötig. Fehlt sie dennoch? `bash _ai_context/scripts/ai-session-prep.sh`.

## Immer zuerst: locate()
```
Bei wo/warum/fix-Fragen: ZUERST MCP-Tool locate("<beschreibung>") aufrufen.
Fächert über Interaction Map, Symbol Map, Interfaces, Gotchas/Debug-Patterns
(mit Frische-Status), Invarianten, Impact-Graph — ein Lookup statt vieler Reads.
Kein MCP verfügbar? Fallback: bash _ai_context/scripts/ai-symptom-router.sh "<beschreibung>"
Kein Treffer → normal grep/Read.
```

## Writeback
```
Ziel-Datei per Schublade bestimmen: siehe _ai_context/drawers.yaml
(ui_controls/api/auth/data/state/infra → jeweilige index:-Datei).
Playbook (wiederkehrende Aufgabe, >3 Schritte, Rezept statt Fakt)
  → playbooks.md (PLAYBOOK:-Block, gleiches Format wie _gotchas.md)
Neue Wissensdatei? → _ai_context/knowledge.manifest.yaml, nicht einzeln
  verdrahten (siehe playbooks.md#add_knowledge_file).
Vor neuem Eintrag: bash _ai_context/check_context_hash.sh --dedup <datei>
  → DUPLICATE:id → bestehenden Eintrag updaten statt neu anlegen
Code-Format (→ ✗ ✓ ? @ ⇒), P: 1=kritisch 2=wichtig 3=nice-to-know,
optional seen: YYYY-MM-DD (Frische — siehe _gotchas.md#legende).
Overflow (Archivierung/Split) läuft automatisch via post-commit Hook.
```

## Gedächtnis (MCP, ergänzend zu locate)
```
memory_search("<begriffe>")  → Schnipsel, auch aus anderen Projekten
session_context()            → kompakter Projektkontext
memory_save(content, type)   → type: gotcha|debug|security|decision|endpoint|auth|component|note
capture_from_diff() läuft automatisch im post-commit-Hook.
```
