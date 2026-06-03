# CLAUDE.md — AI Context System
> Lebt in `~/.claude/CLAUDE.md` oder `/projekt/CLAUDE.md`
> Aktuelle Version: siehe `README.md`

## Sprache
- Kommunikation: **Deutsch** | Code + Architektur: **Englisch**

## Session Start
1. Lade `_ai_context/_SESSION.md` — enthält alles.
2. Folge den Regeln darin.

> Fehlt _SESSION.md? → `bash _ai_context/scripts/ai-session-prep.sh`

## Kontext-Routing
```
_ai_index.md (~150 Tok) → _idx/domain.md (~80 Tok) → datei.md (~200 Tok)
Max 3 Dateien pro Kette. Max 4 Dateien pro Session.
```

## Kontext-Format (Code statt Prosa)
```
Gotchas/Rules/Patterns nutzen Code-Format:
  → Beschreibung    ✗ FALSCH    ✓ RICHTIG
  ? Symptom          @ Dateien   ⇒ Verweis (Pointer)

⇒ = Pointer. Nicht kopieren, nur referenzieren.
  Beispiel: auth: ⇒ security.md#auth_first
  Claude lädt die referenzierte Datei nur bei Bedarf.
```

## Writeback
```
Gotcha         → _gotchas.md (Code-Format, max 15, P: 1/2/3)
Debug Pattern  → debug_patterns.md (Code-Format, max 15, P: 1/2/3)
Endpoint       → backend/endpoints.md
Auth           → backend/auth.md
Komponente     → frontend/components.md
Architektur    → decisions.md
Sprint         → _temp_notes.md (max 5 Recent Changes)
Security       → security.md (Code-Format, max 10, P: 1/2/3)
```
Immer: Domain-Index Status aktualisieren. Pointer (⇒) statt Inhalt kopieren.

## Writeback-Protokoll (v5.2 Dedup-Check)
```
VOR jedem neuen Eintrag in _gotchas.md / debug_patterns.md / security.md:
  bash _ai_context/check_context_hash.sh --dedup _ai_context/_gotchas.md
  → DUPLICATE:id  → Update existierenden Eintrag statt neu anlegen
  → NEW           → Neuen Eintrag hinzufügen

Priorität setzen:
  P: 1 = kritisch (niemals löschen, immer inline in SESSION.md)
  P: 2 = wichtig  (default — bei Overflow: neueste bleiben)
  P: 3 = nice-to-know (bei Overflow: zuerst → _gotchas_archive.md)

Konflikte prüfen nach Writeback:
  bash _ai_context/check_context_hash.sh --conflicts
```

## Schubladen (v5.2 Overflow-Management)
```
Automatisch via post-commit Hook:
  P3-Gotchas > 5     → _gotchas_archive.md (auto-erstellt)
  Domain-Datei >80Z  → _core.md + _extended.md (auto-split)

Manuell: bash _ai_context/scripts/ai-context-drawer.sh
```
