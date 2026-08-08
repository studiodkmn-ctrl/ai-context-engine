# V9 — Unverzichtbar-Plan: Automatisch statt auf Zuruf, bewiesen statt behauptet, überall statt nur Claude Code
> **Status: ENTWURF** — erstellt 2026-08-08 auf Basis der v8.1-Session
> (Graphify-Analyse → Read-Guard + playbooks.md → Rollout auf 9 Projekte).
> Umsetzung: phasenweise, jede Phase einzeln committbar und verifizierbar.

---

## 1. Ausgangslage — was die letzte Session gezeigt hat

**Erreicht (v8.1):**
- Read-Guard (PreToolUse-Hook): blockt redundante Reads → messbare Token-Ersparnis pro Session
- playbooks.md: prozedurales Gedächtnis (Rezepte statt nur Fakten) — der Hebel, mit dem
  ein kleineres Modell bei bekannten Aufgabentypen wie ein größeres arbeitet
- Rollout-Pipeline funktioniert (9 Projekte, migrate.sh-Lücke gefunden + gefixt)

**Die 6 ehrlichen Schwächen (aus der Session-Analyse, Reihenfolge = Wichtigkeit):**

| # | Schwäche | Kern des Problems |
|---|---|---|
| 1 | Playbooks bleiben leer | Mechanismus existiert, füllt sich aber nicht von selbst |
| 2 | Kein Beweis in Zahlen | "80% Ersparnis" ist Schätzung, nie A/B gemessen |
| 3 | Alles läuft auf Zuruf | /ai-fix, /ai-doctor, locate() — der Nutzer muss dran denken |
| 4 | Reichweite = nur Claude Code | Graphify bedient 15+ Agents, wir 1 |
| 5 | Selbstreferenzialität fragil | migrate.sh vergaß playbooks.md — 6 Eintrag-Stellen pro neuer Wissensdatei |
| 6 | locate() versteht nur Keywords | Falsches Vokabular → kein Treffer → Vorteil weg |

**Nordstern für v9:** Der Nutzer merkt das System nur noch an zwei Stellen:
(a) Claude ist sofort orientiert und wird von Session zu Session besser,
(b) die Session-Statistik zeigt gemessene, nicht behauptete Ersparnis.
Alles andere — Erfassen, Routen, Konsolidieren, Verteilen — passiert ohne Kommando.

---

## 2. Leitidee: das Hermes-Gedächtnismodell vollständig machen

Kognitive Agent-Architekturen (Hermes u.ä.) unterscheiden vier Gedächtnisarten.
Stand heute haben wir 2,5 davon — v9 vervollständigt den Kreislauf:

| Gedächtnisart | Bedeutung | Heute | v9 |
|---|---|---|---|
| Arbeitsgedächtnis | aktueller Session-Zustand | _SESSION.md, HANDOFF.md (manuell) | HANDOFF **automatisch** bei Stop/PreCompact |
| Episodisch | "was ist in dieser Session passiert" | fehlt (nur git log) | Session-Journal aus Transcript, auto |
| Semantisch | Fakten/Regeln | Gotchas, Decisions, Security ✅ | unverändert, wird aus Episoden **konsolidiert** |
| Prozedural | "wie macht man X" | playbooks.md (manuell befüllt) | **Auto-Capture** aus abgeschlossenen Aufgaben |

Der fehlende Schritt ist überall derselbe: **Konsolidierung am Session-Ende** —
Episoden werden automatisch zu semantischem und prozeduralem Wissen destilliert.
Genau das machen Stop-/PreCompact-Hooks möglich (Claude Code übergibt
`transcript_path` im Hook-JSON — die komplette Session ist maschinenlesbar).

---

## 3. Die fünf Bausteine

### Baustein A — Session-Reflexion: automatisches Lernen am Session-Ende (Schwäche 1 + 3)

**Neu: `_ai_context/scripts/ai-session-reflect.sh`** — läuft als **Stop-Hook**
(und PreCompact-Hook, damit vor einer Kompaktierung nichts verloren geht).

Mechanik:
1. Hook-JSON von stdin lesen → `transcript_path` (JSONL der Session).
2. Aus dem Transcript extrahieren (rein heuristisch, kein LLM-Call nötig):
   - **Gelesene Dateien + Reihenfolge** → Kandidat für Impact-Graph-Kanten
     (Dateien, die in einer Aufgabe zusammen angefasst wurden — ergänzt die
     Git-Co-Change-Sicht um die Session-Sicht)
   - **Edit/Write-Sequenzen mit ≥4 Schritten, die mit erfolgreichem
     Test/Build enden** → Playbook-Kandidat (Trigger = User-Prompt-Anfang,
     Steps = Datei-Reihenfolge) → als `PLAYBOOK:`-Vorschlag mit
     `learned_from: session <datum>` in eine **Inbox-Datei**
     `_ai_context/.session/reflect-inbox.md` schreiben — NICHT direkt in
     playbooks.md (Vorschlag ≠ Wahrheit)
   - **Fehlermeldungs-Muster** (gleicher Fehler-String 2×+ im Transcript,
     danach gelöst) → Debug-Pattern-Vorschlag
3. **HANDOFF.md automatisch schreiben** wenn die Session mitten in einer
   Aufgabe endet (Heuristik: letzte Assistant-Message enthält kein
   Abschluss-Signal, uncommittete Änderungen vorhanden): Status, geänderte
   Dateien, letzter Stand. Ersetzt die heutige "Session-Übergabe"-Regel,
   die nur funktioniert, wenn das Modell dran denkt.
4. Beim **nächsten SessionStart** zeigt ai-session-prep.sh die Inbox an
   ("2 Playbook-Vorschläge aus letzter Session — übernehmen?"), Claude
   bestätigt/verwirft mit einem Satz. Übernahme = normaler Writeback mit
   Dedup. So bleibt der Mensch/Agent Kurator, aber die Erfassung ist gratis.

Ergebnis: **playbooks.md und debug_patterns.md füllen sich von selbst** —
die Schwäche Nr. 1 verschwindet strukturell, nicht durch Disziplin-Appelle.

### Baustein B — Auto-Routing: locate() ohne Kommando (Schwäche 3 + 6)

**B1 — UserPromptSubmit-Hook wird zum stillen Router.**
Neu: `_ai_context/scripts/ai-prompt-router.sh` als UserPromptSubmit-Hook.
- Liest den Prompt aus dem Hook-JSON. Matcht Symptom-Sprache
  (Bug-Verben, "wo ist", "warum", Fehlermeldungs-Fragmente, Stack-Trace-Zeilen)
  mit derselben Tokenizer/Stopword-Logik wie locate().
- Bei Treffer: ruft `locate-cli.js` auf und gibt das Ergebnis auf **stdout**
  aus → Claude Code injiziert es als Kontext VOR der Antwort. Claude startet
  also bereits mit "🔎 locate: LoginButton src/…:47, Gotcha auth_version [P2]"
  im Kontext — ohne dass irgendjemand /ai-fix getippt hat.
- Bei Nicht-Treffer: kein Output (still, kostet nichts). Rate-Limit: max 1
  Injektion pro Prompt, nie bei trivialen Prompts (<6 Wörter ohne Symptomwort).
- /ai-fix bleibt als explizites Skill bestehen, wird aber zur Ausnahme.

**B2 — locate() bekommt semantischen Fallback (Pro-Edition).**
Die Ollama-Embedding-Infrastruktur existiert schon vollständig
(ai-rag-cache.sh, nomic-embed-text, SQLite-Cache). Sie ist nur nicht mit
locate() verbunden. Änderung in `mcp/src/lib/locate.ts`:
- Wenn Keyword-Score aller Chunks < Schwelle UND `~/.ai-context/edition == pro`
  UND Ollama erreichbar → `ai-rag-cache.sh --find "<query>"` als Fallback,
  Ergebnis in die Antwortkarte mergen (Quelle markieren: `[semantisch]`).
- Damit trifft locate() auch bei falschem Vokabular ("Anmeldung kaputt"
  findet "login"), lokal, ohne Cloud-Call. Schwäche 6 halbiert sich.

### Baustein C — Beweis-Harness: messen statt behaupten (Schwäche 2)

**Neu: `bench/ai-bench.sh`** — A/B-Vergleich auf Knopfdruck:
1. Nimmt ein Zielprojekt + eine Aufgabenliste (`bench/tasks.yaml`, pro Task:
   Prompt + Verifikations-Kommando, z.B. "Fix X" + `npm test`).
2. Läuft jede Aufgabe zweimal headless via `claude -p --output-format json`:
   - Arm A: Projekt wie es ist (mit _ai_context + Hooks)
   - Arm B: temporäre Kopie/Worktree mit deaktiviertem System
     (Hooks raus, _ai_context umbenannt)
3. Misst pro Lauf aus dem JSON-Output: Input-/Output-Tokens, Kosten, Dauer,
   Anzahl Tool-Calls, und ob das Verifikations-Kommando danach grün ist.
4. Schreibt `BENCHMARKS.md` (Tabelle + Rohdaten als JSONL) — dieselbe Waffe,
   mit der Graphify sein "71.5x fewer tokens" belegt.
5. Zweite Achse (das eigentliche Versprechen): gleiche Aufgabe,
   `--model sonnet` mit System vs. `--model opus` ohne System →
   Qualität (Verify grün?) + Kosten nebeneinander.
6. README-Tabelle ("~63.000 vs ~11.000 Tokens") durch gemessene Zahlen
   ersetzen — oder ehrlich korrigieren, falls die Messung weniger zeigt.

Zusätzlich: `ai-session-log.sh` erweitern — der Read-Guard zählt ab jetzt
geblockte Reads + deren Dateigröße in Tokens → die Session-Statistik zeigt
**real verhinderte** Verschwendung, nicht den heutigen Pauschalfaktor 6,5.

### Baustein D — Ein Manifest statt sechs Eintrag-Stellen (Schwäche 5)

Die migrate.sh-Lücke der letzten Session war kein Einzelfall, sondern eine
Strukturschwäche: eine neue Wissensdatei muss heute an ~6 Stellen registriert
werden (locate.ts, registry.sh, doctor.sh, post-commit, migrate.sh, CLAUDE.md)
— das dokumentiert sogar unser eigenes Playbook `add_knowledge_file`.

**Neu: `_ai_context/knowledge.manifest.yaml`** — einzige Quelle der Wahrheit:
```yaml
files:
  - path: _gotchas.md        # Typ, Limit, ob Anker-Pflicht, ob migrierbar
    type: gotcha
    max_entries: 15
    archive: _gotchas_archive.md
  - path: playbooks.md
    type: playbook
    max_entries: 15
  # ...
```
Umbau (schrittweise, jede Stelle einzeln testbar):
- `locate.ts` (KNOWLEDGE_FILES-Fallback), `ai-context-registry.sh`,
  `ai-context-doctor.sh`, `hooks/post-commit` (Trim-Limits) und
  `migrate.sh` (additives Anlegen neuer Dateien) lesen alle das Manifest.
- `ai-verify-self.sh` bekommt einen neuen Check: "Manifest-Datei existiert
  in Template UND wird von Migration verteilt" — ein frisches Temp-Projekt
  wird per setup aufgesetzt, per migrate aktualisiert, und die Dateilisten
  verglichen. Die migrate.sh-Fehlerklasse kann danach nicht mehr entstehen.
- Das Playbook `add_knowledge_file` schrumpft auf: "eine Zeile ins Manifest,
  fertig" — bester Beweis, dass der Umbau gelungen ist.

### Baustein E — Reichweite: dieselbe Intelligenz für 10+ Agents (Schwäche 4)

Graphifys Trick ist simpel: **eine Wissensbasis, viele dünne Adapter**
(skill-codex.md, skill-cursor.md, always_on/*.md …). Unsere Wissensbasis
(_ai_context/) ist bereits agent-neutral — nur die Anbindung ist Claude-only.

**Neu: `_ai_context/scripts/ai-agents-sync.sh`** (+ Aufruf in setup/migrate):
generiert aus _SESSION.md-Kern + locate()-Anleitung die Standard-Dateien
der anderen Agents — als schlanke Pointer, nicht als Kopien:
- `AGENTS.md` (offener Standard: Codex, Cursor, Gemini CLI, Jules, Amp, …
  lesen ihn nativ) — enthält: Kontext-Karte, "rufe `bash
  _ai_context/scripts/ai-symptom-router.sh '<frage>'` vor Datei-Suche auf",
  Writeback-Regeln. Der CLI-Wrapper existiert schon — er IST der universelle
  Adapter, denn jeder Agent kann Bash.
- `.cursor/rules/ai-context.mdc`, `GEMINI.md`, `.github/copilot-instructions.md`
  — jeweils <20 Zeilen, verweisen auf dieselben Mechanismen.
- MCP-Server läuft protokollbedingt schon heute in Cursor/anderen
  MCP-Clients — `mcp/README.md` um die Konfigurationsblöcke ergänzen.
- Sync-Regel: Dateien tragen einen `<!-- ai-context:managed -->`-Marker;
  nur markierte Blöcke werden bei Migration aktualisiert (nie fremde
  Inhalte überschreiben).

Damit: ~10 Agents mit einem Script, ohne eine zweite Codebasis zu pflegen.
(Hooks/Read-Guard bleiben Claude-Code-exklusiv — das ist okay: dort sind
wir am tiefsten integriert, anderswo immerhin präsent.)

---

## 4. Reihenfolge & Schnitt (für die Umsetzung durch Sonnet)

| Phase | Inhalt | Warum zuerst | Fertig wenn |
|---|---|---|---|
| **v9-a** | Baustein D (Manifest) | Fundament — A und E legen sonst neue Dateien an und vergrößern das 6-Stellen-Problem | ai-verify-self-Paritäts-Check grün; add_knowledge_file-Playbook auf 1 Schritt geschrumpft |
| **v9-b** | Baustein B1 (Prompt-Router) | Größter Spürbarkeits-Gewinn pro Aufwand; nur 1 Script + 1 Hook-Eintrag | Bug-Prompt in Testprojekt injiziert locate()-Karte ohne Kommando; triviale Prompts bleiben still |
| **v9-c** | Baustein A (Session-Reflexion) | Braucht B nicht, aber D (Inbox-Datei via Manifest) | Nach einer echten Session liegen Vorschläge in der Inbox; HANDOFF.md entsteht bei abgebrochener Aufgabe automatisch |
| **v9-d** | Baustein C (Benchmark) | Braucht stabile v9-b/c, sonst misst man den alten Stand | BENCHMARKS.md mit ≥5 Tasks × 2 Armen; README-Zahlen ersetzt |
| **v9-e** | Baustein B2 (semantisches locate) + E (Agents-Sync) | Unabhängig voneinander, beide additiv | "Anmeldung kaputt" findet login-Chunk; AGENTS.md + 3 Adapter in Testprojekt generiert |

Regeln für jede Phase (gelten unverändert weiter):
- Template + _ai_context/ immer symmetrisch; Verteilung über migrate.sh im
  selben Commit mitdenken (Lehre aus v8.1: die Lücke entstand genau dort).
- Jeder Hook fail-open (Fehler → still, exit 0) — ein Kontext-System darf
  nie die eigentliche Arbeit blockieren. Ausnahme bleibt bewusst: Read-Guard
  deny und harte Invarianten.
- Jede Phase endet mit: mcp-Smoke-Test grün, ai-context-doctor ohne neue
  Warnungen, Rollout via `install.sh --pro --migrate-all`, Stichprobe in
  2 Zielprojekten.

## 5. Woran wir "unverzichtbar" danach messen

1. **Kaltstart-Test:** Neues Projekt, 10 typische Aufgaben, kein einziges
   manuelles ai-*-Kommando nötig → System hat trotzdem gelernt (Inbox gefüllt,
   Playbooks übernommen, HANDOFF geschrieben).
2. **Zahlen-Test:** BENCHMARKS.md zeigt gemessene Ersparnis + Sonnet-mit-System
   erreicht Verify-grün-Quote von Opus-ohne-System bei niedrigeren Kosten.
   (Falls nicht: das Ergebnis ehrlich publizieren und die Lücke benennen —
   Glaubwürdigkeit ist Teil des Produkts.)
3. **Entzugs-Test:** System in einem aktiven Projekt eine Woche deaktivieren.
   Wenn es niemand vermisst, sind wir nicht unverzichtbar — dann zurück ans
   Reißbrett mit den Daten aus dem Session-Log.
