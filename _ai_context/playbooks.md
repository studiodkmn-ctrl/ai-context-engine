# playbooks.md — Prozedurales Gedächtnis
> Schritt-Rezepte für wiederkehrende Aufgaben. Architektur-Entscheidung
> (Reihenfolge, Dateien, Invariante) einmal treffen, hier festhalten,
> danach nur noch befolgen — spart Grübeln bei jedem neuen Turn.
> Format wie `_gotchas.md` (Anchor-Block, Registry/Freshness/`locate()`
> verwalten es automatisch). Writeback: nach >3-Schritt-Aufgabe eintragen.
> P: 1=kritisch 2=Standard 3=nice-to-know.

## Aktiv

<!-- #add_knowledge_file -->
```
PLAYBOOK: add_knowledge_file
P: 2
trigger: neue wissensdatei, neue schublade, playbook hinzufügen, gotcha-artige datei
steps:
  1. Datei im Anchor-Block-Format anlegen (wie _gotchas.md).
  2. mcp/src/lib/locate.ts::KNOWLEDGE_FILES eintragen (Fallback ohne registry.yaml).
  3. ai-context-registry.sh::KNOWLEDGE_FILES eintragen (Freshness beim --scan).
  4. ai-context-doctor.sh an allen Stellen ergänzen, wo _gotchas.md/
     debug_patterns.md/security.md gelistet sind (per grep suchen, nicht raten).
  5. hooks/post-commit::knowledge_files-Dict mit Limit ergänzen (Priority-Trim).
  6. Alle Schritte identisch im _ai_context_template/-Pendant nachziehen.
  7. CLAUDE.md-Writeback-Tabelle um eine Zeile ergänzen.
learned_from: Session 2026-08-08 (dogfooding — playbooks.md selbst so gebaut)
```
<!-- /add_knowledge_file -->

## Vorlage (zum Kopieren, kein Anchor — wird von locate()/Registry ignoriert)

```
PLAYBOOK: _template
P: 2
trigger: [Suchbegriffe]
steps:
  1. [Schritt]
  2. [Schritt]
learned_from: manuell | Commit <hash> | Session <datum>
```
