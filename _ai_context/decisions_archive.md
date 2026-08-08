# 📦 Decisions Archiv — Ältere ADRs
> Ausgelagert aus `decisions.md` (Overflow-Regel, 600-Token-Split).
> Nur bei Bedarf laden (Parsing-Format, Frische-Feld-Historie). Inhalt
> unverändert — nur räumlich verschoben, keine ADR wurde gekürzt.
> Letzte Archivierung: 2026-08-06

---

### ADR-002: seen-Feld primär in registry.yaml, .md-Zeile hat Vorrang
**Date:** 2026-07-09 | **Status:** Accepted

**Context:** Das v7-Frische-Modell (Phase 2) braucht einen Zeitstempel
"wann wurde dieser Gotcha zuletzt bestätigt" (`seen`), unabhängig vom
automatisch berechneten `code_touched` (git-Historie der `@`-Dateien).
Unklar war, ob `seen` in der `.md`-Quelldatei (nutzer-editierbar) oder
nur in `registry.yaml` (maschinell generiert) geführt wird.
**Decision:** `seen` wird primär in `registry.yaml` gepflegt (jeder
`--scan` schreibt es). Enthält der Chunk-Text in der `.md`-Datei eine
explizite `seen: YYYY-MM-DD`-Zeile, hat dieser Wert Vorrang — das
erlaubt ein manuelles "bestätigt am" direkt im Gotcha-Text, ohne dass
der Nutzer `registry.yaml` von Hand anfassen muss.
**Consequences:**
  + Kein Zwang, jede `.md`-Datei um ein Pflichtfeld zu erweitern —
    additiv, bestehende Chunks parsen unverändert weiter.
  + Manuelles Bestätigen ("ja, dieser Fix gilt noch") ist so einfach
    wie eine Zeile in den Gotcha-Text schreiben.
  - Zwei mögliche Quellen für denselben Wert — bei Inkonsistenz gewinnt
    immer die `.md`-Zeile (definiert in `ai-context-registry.sh --scan`).

---

### ADR-003: drawers.yaml/invariants.yaml ohne PyYAML/npm-yaml-Package
**Date:** 2026-07-09 | **Status:** Accepted

**Context:** `drawers.yaml` (Phase 3) und `invariants.yaml` brauchen
strukturiertes Parsen — sowohl in Python (`ai-context-registry.sh`,
`ai-context-drawer.sh`) als auch in TypeScript (`mcp/src/lib/locate.ts`).
Ein echter YAML-Parser wäre bequemer, aber sowohl `check_context_hash.sh`
als auch `ai-context-registry.sh` lesen `registry.yaml` schon länger
zeilenbasiert (kein `import yaml`) — eine neue Abhängigkeit würde diese
Konsistenz brechen und (im TS-Fall) ein npm-Package erzwingen, das die
Projektregel "kein neues Package ohne Not" verletzt.
**Decision:** Beide Formate bleiben bewusst flach und einfach genug für
zeilenbasiertes Parsen (kein verschachteltes YAML, keine Anker/Referenzen,
keine Multi-Line-Strings außer in Anführungszeichen). `ctx.py` bekommt
`list_drawer_indexes()`, `mcp/src/lib/locate.ts` einen eigenen
Mini-Parser (`parseDrawers`, `parseInvariants`, `parseRegistry`) nach
demselben Muster wie das bestehende `registry.yaml`-Parsing.
**Consequences:**
  + Keine neue Python- oder npm-Abhängigkeit.
  + Konsistent mit dem bestehenden Parsing-Stil im ganzen Projekt.
  - Das Schema muss flach bleiben — echte YAML-Features (Anker, Multi-
    Doc, komplexe verschachtelte Strukturen) würden die Parser brechen.
    Bei Bedarf: `python3 -c "import yaml"` prüfen und dann gezielt auf
    PyYAML umstellen, statt den Parser weiter zu verkomplizieren.
