# Hot Paths — ai-context-engine
> Kritische Nicht-Offensichtliche Muster. 1× manuell schreiben, selten ändern.
> Verhindert Re-Lesen stabiler Invarianten (~20% Token-Ersparnis pro Session).
> Format: PATTERN_NAME (datei.ts:zeile) + Kurzbeschreibung + Entscheidungsbaum

---

## [EXAMPLE_PATTERN_1] ([file.ts:LINE])
```
BESCHREIBUNG:  Was hier passiert und warum es nicht-offensichtlich ist

ENTSCHEIDUNGSBAUM:
  Bedingung A  → Ergebnis 1
  Bedingung B  → Ergebnis 2
  Fallback     → Ergebnis 3

GOTCHA:  Was schief geht wenn man das ignoriert
```

---

## [EXAMPLE_PATTERN_2] ([file.ts:LINE])
```
BESCHREIBUNG:  ...

FLOW:
  Schritt 1 → Schritt 2 → Schritt 3
  Nur wenn: <Bedingung>
  No-op wenn: <Bedingung>

ENV:  ENV_VAR=true nötig
```

---
> HINWEIS: Maximal 6 Patterns. Mehr → _gotchas.md oder debug_patterns.md.
> Nur echte Invarianten (die sich kaum ändern). Temporäres → _temp_notes.md.
