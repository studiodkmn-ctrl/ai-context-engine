# 🏗️ Architecture — ai-context-engine
> **Laden bei Umbauten am System selbst.**
> Aktualisiert: 2026-08-09

## Stack
```
Bash        _ai_context/scripts/*.sh — Setup, Doctor, Registry, Hooks
Python 3    Inline-Heredocs + scripts/lib/ctx.py (kein PyYAML)
TypeScript  mcp/ — MCP-Server + locate()-Bibliothek (Node, tsc)
Ollama      optional (Pro) — lokale Embeddings, nomic-embed-text
```

## Schichten
```
Wissensbasis  _ai_context/*.md         Gotchas, Playbooks, Decisions, Domains
Manifest      knowledge.manifest.yaml  welche Datei ist Wissensdatei
Index         registry.yaml, _idx/     Chunks+Frische, Symbol-/Interface-Map
Zugriff       locate() (MCP + CLI)     ein Lookup über alle Indizes
Automatik     Hooks                    Session, Prompt, Read, Stop, post-commit
Verteilung    setup/migrate/install    Template → Projekte, additiv+idempotent
```

## Datenfluss
```
Commit        → post-commit: Index invalidieren, trimmen, capture_from_diff,
                _SESSION.md regenerieren
SessionStart  → doctor --session, session-prep, _SESSION.md injizieren
Prompt        → ai-prompt-router.sh: locate() still, injiziert bei Treffer
Read          → ai-read-guard.sh blockt exakte Wiederholungs-Reads
Turn-Ende     → ai-session-reflect.sh: Transcript → reflect-inbox/HANDOFF
```

## Invarianten
```
Template-Symmetrie   _ai_context/scripts ↔ _ai_context_template/scripts
                     (doctor: localtemplatedrift)
Hooks fail-open      Fehler → exit 0, nie die Arbeit blockieren
                     (Ausnahmen: Read-Guard-deny, harte Invarianten)
Verteilung mitdenken jede neue Datei/Hook auch in migrate.sh
                     (Lehre aus v8.1, ai-verify-self.sh Check 7)
```

> Writeback: Architektur-Änderungen hier dokumentieren. ADRs → `decisions.md`.
