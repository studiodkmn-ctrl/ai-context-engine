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
  1. Zeile in knowledge.manifest.yaml ergänzen (_ai_context/ UND
     _ai_context_template/ — identischer Inhalt, kein Stack-spezifisches
     Feld wie bei drawers.yaml): path, type, markers, optional
     max_entries/archive/seed. Datei im Anchor-Block-Format anlegen (wie
     _gotchas.md), falls sie noch nicht existiert.
  2. Fertig — locate.ts, ai-context-registry.sh, ai-context-doctor.sh,
     hooks/post-commit und migrate.sh lesen alle aus dem Manifest (v9-a,
     siehe decisions.md#knowledge_manifest). Bei seed:true legt migrate.sh
     die Datei in bestehenden Projekten automatisch additiv an.
learned_from: Session 2026-08-08 (v9-a — Manifest-Umbau ersetzt die
  ursprünglichen 7 manuellen Schritte, mit denen dieses Playbook selbst
  zuerst angelegt wurde)
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
