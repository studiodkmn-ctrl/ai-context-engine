# 🏛️ Architecture Decision Records (ADRs)
**Status:** ✅ Fresh · **Updated:** 2026-07-09 · **Invalidated by:** `package.json`, `requirements.txt` changes (new lib = potential new decision)

> Claude: Load this file for refactoring, new feature planning, or "why was X built this way?" questions.
> **Writeback:** Neue ADR sofort anlegen wenn Architekturentscheidung getroffen wird.

---

## Wann eine neue ADR schreiben?
```
- Wenn eine Technologie gewählt oder ausgetauscht wird (ORM, Auth, State, Hosting).
- Wenn ein Pattern eingeführt wird, das projektweit gelten soll.
- Wenn ein vorheriger Ansatz bewusst verworfen wird.
- Faustregel: Wenn zukünftige Claude-Sessions fragen würden "warum ist das so?" → ADR.
```

## ADR Template
```
### ADR-[NR]: [Short Title]
**Date:** 2026-04-14  |  **Status:** Accepted / Superseded by ADR-[NR] / In Discussion

**Context:** [Why did this decision need to be made?]
**Decision:** [What was decided?]
**Consequences:**
  + [Advantage]
  - [Trade-off]
```

---

## Decisions

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

---

### ADR-004: Selbst-Update via install.sh --refresh statt Update-Logik-Duplikat
**Date:** 2026-07-11 | **Status:** Accepted

**Context:** v8 Baustein A braucht einen Apply-Mechanismus für den
Selbst-Update-Loop (`ai-context-selfcheck.sh`). Optionen: (a) Kopier-Logik
aus install.sh im Selfcheck duplizieren, (b) install.sh komplett erneut
laufen lassen (interaktiv bei --pro/Ollama, schreibt Shell-RC um), (c) ein
nicht-interaktiver `--refresh`-Modus in install.sh.
**Decision:** (c) — `install.sh --refresh` aktualisiert nur Dateien
(Templates, Scripts, MCP-Build, VERSION, Hooks in settings.json), behält
die installierte Edition bei und fasst weder Ollama noch `.zshrc`/`.bashrc`
an. Der Selfcheck ruft ihn nach Backup + Trusted-Origin-Prüfung auf, danach
`auto-update-all.sh` für die registrierten Projekte.
**Consequences:**
  + Eine einzige Quelle für die Install-Kopierlogik — kein Drift.
  + Automatisierte Läufe schreiben nie Nutzer-Dotfiles um.
  - Änderungen am Shell-Alias-Block propagieren nur über manuelles
    `bash install.sh` (bewusst: Least-Surprise für Auto-Updates).

---

### ADR-005: Trusted-Origin-Guard mit First-Use-Trust
**Date:** 2026-07-11 | **Status:** Accepted

**Context:** Auto-Update ist ein Supply-Chain-Risiko: ein manipulierter
Checkout unter `.source-path` könnte sonst unbemerkt Skripte in alle
registrierten Projekte verteilen.
**Decision:** `install.sh` schreibt `~/.ai-context/.trusted-origin`
(Remote-URL) genau einmal beim Erstinstall; `ai-context-selfcheck.sh`
verweigert jede Update-Anwendung, wenn die aktuelle origin-URL der Quelle
davon abweicht. Fehlt die Datei (Alt-Installation), wird sie einmalig aus
der aktuellen origin initialisiert (First-Use-Trust — dasselbe Modell wie
SSH known_hosts). Kein Netzwerkzugriff, wenn keine Git-Quelle bekannt ist.
**Consequences:**
  + Quellwechsel schlägt laut fehl statt still zu aktualisieren.
  + Offline-/Nicht-Git-Installationen bleiben komplett update-frei (kein
    stiller curl).
  - Bewusster Repo-Umzug erfordert manuelles Anpassen von .trusted-origin.

---

## ❌ Rejected Alternatives
> So Claude (and you) don't fall into the same trap again.

```
### [Approach] — Rejected 2026-04-14
Tried:    [What was attempted]
Problem:  [Why it didn't work]
Solution: [What was done instead]
Remember: [Concrete hint for the future]
```

---

## 📝 Update Log

### 2026-07-09 — v7 "Locate Layer"
- ADR-002: seen-Feld-Speicherort (registry.yaml primär, .md-Zeile hat Vorrang)
- ADR-003: drawers.yaml/invariants.yaml-Parsing ohne neues YAML-Package

### 2026-04-14 — Initial setup
- ADR file created, first decisions pending
