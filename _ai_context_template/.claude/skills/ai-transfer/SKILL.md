---
name: ai-transfer
description: >-
  Zeigt Ideen und Techniken aus deinen anderen Projekten, die im aktuellen
  Projekt auch nützen könnten. Nutzen wenn der SessionStart-Hinweis
  "Cross-Projekt-Ideen" erscheint, oder wenn du wissen willst, was du aus
  einem Projekt in ein anderes übernehmen kannst.
---

# ai-transfer — Cross-Projekt-Ideen bewerten

Das System hat erkannt, dass in einem anderen Projekt eine Technik entstand,
die hier passen könnte. Deine Aufgabe: jeden Vorschlag prüfen und konkret
einschätzen — das Skript kann das nicht, es liefert nur die Kandidaten.

## Schritt 1 — Vorschläge laden

```
bash _ai_context/scripts/ai-context-transfer.sh --inbox
```

Liefert pro Vorschlag: `id`, `chunk`, `from_project`, `type`, `file`, `tags`.
Keine Vorschläge → dem Nutzer kurz sagen, fertig.

## Schritt 2 — Quell-Chunk lesen

Für jeden Vorschlag den echten Inhalt aus dem Quellprojekt-Store lesen:

```
~/.ai-context/projects/<from_project>/_ai_context/<file>
```

Den Block mit der `chunk`-ID darin finden (zwischen `<!-- #id -->` und
`<!-- /id -->`, oder den ```-Block mit `ID: <chunk>`).

## Schritt 3 — Aktuelles Projekt einschätzen

Kurz prüfen, was das aktuelle Projekt im betroffenen Bereich schon kann —
relevante Kontextdatei lesen (z.B. `_gotchas.md`, passende Domain-Datei).
So erkennst du, ob die Idee wirklich fehlt oder nur anders gelöst ist.

## Schritt 4 — Pro Vorschlag in diesem Format antworten

```
💡 Vorschlag: <chunk> (aus Projekt <from_project>)

  Was dieses Projekt aktuell kann:
    <1-2 Sätze — Ist-Zustand im betroffenen Bereich>

  Idee aus <from_project>:
    <1-2 Sätze — was die Technik löst>

  Konkret hier:
    <kurzes Code-/Struktur-Beispiel, an dieses Projekt angepasst>

  Aufwand: niedrig | mittel | hoch
    <1 Satz Begründung>
```

Ehrlich bleiben: Passt der Vorschlag **nicht** (anderer Anwendungsfall,
schon gelöst, Stack-Detail unpassend), sag das klar und empfiehl `--dismiss`.
Kein Vorschlag um des Vorschlags willen (Apple-Prinzip).

## Schritt 5 — Aktion

Pro Vorschlag den Nutzer fragen:
- **Übernehmen** → die Technik an dieses Projekt angepasst umsetzen und als
  Gotcha/Pattern in die passende Kontextdatei eintragen (Dedup-Check vorher).
- **Verwerfen** → `bash _ai_context/scripts/ai-context-transfer.sh --dismiss <id>`

Verworfene Vorschläge kommen nicht wieder.
