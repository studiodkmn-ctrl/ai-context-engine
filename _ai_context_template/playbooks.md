# playbooks.md — Prozedurales Gedächtnis — [PROJECT_NAME]
> Schritt-für-Schritt-Rezepte für wiederkehrende Aufgabentypen. Die
> architektonische Entscheidung (Reihenfolge, betroffene Dateien, welche
> Invariante zuerst greift) wird EINMAL getroffen und hier festgehalten —
> danach wird sie nur noch befolgt, nicht bei jedem Turn neu erdacht.
>
> Format wie bei `_gotchas.md`: Anchor-Block (`<!-- #id -->...<!-- /id -->`),
> damit Registry-Scan, Freshness-Modell (`seen`/`code_touched`/`status`)
> und `locate()` sie automatisch mitverwalten.
>
> Writeback: nach Abschluss einer mehrschrittigen (>3 Schritte)
> wiederkehrenden Aufgabe hier eintragen — analog zum Gotcha-Writeback.
> P: 1=kritisch 2=Standard 3=nice-to-know. `learned_from:` referenziert
> den Commit/die Session, aus der das Rezept stammt (`manuell`, wenn direkt
> geschrieben statt aus einer Aufgabe abgeleitet).

## Aktiv

_Noch keine Einträge — wird beim ersten wiederkehrenden Aufgabentyp befüllt._

## Vorlage (zum Kopieren, kein Anchor — wird von locate()/Registry ignoriert)

```
PLAYBOOK: _template
P: 2
trigger: [Suchbegriffe, die diese Aufgabe typischerweise auslösen]
steps:
  1. [Erster Schritt — welche Datei zuerst]
  2. [Zweiter Schritt — welche Regel/Invariante hier greift]
  3. [Dritter Schritt — wo eingetragen/getestet wird]
learned_from: manuell | Commit <hash> | Session <datum>
```
