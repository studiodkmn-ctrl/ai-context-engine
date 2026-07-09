---
name: ai-doctor
description: >-
  Prüft und repariert die Gesundheit des AI-Context-Systems. Nutzen wenn der
  Kontext unzuverlässig wirkt, nach größeren Umbauten, oder wenn der
  SessionStart-Hinweis "/ai-doctor" anzeigt. Behebt mechanische Defekte
  automatisch und löst die semantischen (kaputte Verweise, Platzhalter,
  veraltete Referenzen) gezielt auf.
---

# ai-doctor — Selbst-Reparatur des Kontext-Systems

Das System kann eigene Defekte erkennen. Mechanische repariert es selbst;
die semantischen brauchen dich.

## Schritt 1 — Diagnose + mechanischer Auto-Fix
Führe aus:

```
bash _ai_context/scripts/ai-context-doctor.sh --fix
```

Der Doctor repariert mechanische Defekte sofort (fehlende Anker, veraltete
Interaction Map) und listet den Rest als `FLAGGED-FOR-CLAUDE`.

## Schritt 2 — Semantische Defekte auflösen
Für jeden `[WARN]` im Report, der nach dem Auto-Fix bleibt:

- **pointers** (kaputte `⇒`-Verweise) — Verweis-Ziel prüfen: Anker umbenannt
  oder Datei verschoben? Den `⇒`-Verweis auf das korrekte Ziel zeigen lassen,
  oder entfernen wenn das Ziel bewusst weg ist.
- **placeholders** (Platzhalter-Reste wie `[PROJECT_NAME]`) — mit echten
  Projektwerten füllen. Werte aus `_quick_facts.md`, `package.json` o.ä.
- **deadrefs** (`@`-Referenzen auf fehlenden Code) — Datei wurde verschoben/
  gelöscht: `@`-Zeile im Gotcha/Pattern auf den neuen Pfad setzen, oder den
  Eintrag entfernen wenn er gegenstandslos ist.
- **index** (Index-Eintrag ohne Datei) — Datei fehlt: Index-Zeile entfernen,
  oder die Datei anlegen falls sie fehlen sollte.
- **oversize** (Datei > 600 Tokens) — gemäß Split-Regel in kleinere
  Domain-Dateien teilen (`_core.md` + `_extended.md`).
- **conflicts** (widersprüchliche Regeln) — die beiden genannten Einträge
  lesen; der neuere/spezifischere gewinnt, den veralteten anpassen oder löschen.

Behebe nur, was der Report nennt. Keine Spekulation.

## Schritt 3 — Re-Check
Nach den Korrekturen erneut:

```
bash _ai_context/scripts/ai-context-doctor.sh --check
```

Ziel: `✅ System gesund`. Melde dem Nutzer kurz, was repariert wurde.
