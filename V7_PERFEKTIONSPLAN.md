# V7 Perfektionsplan — "Locate Layer" + Schubladen-Manifest
> Erstellt: 2026-07-07 · Basis: Analyse von v6.5/v6.6 (alle Scripts, MCP, Registry, Hooks)
> Ziel: Claude Code weiß in **1 Lookup** wo die gesuchte Stelle liegt — statt in 4–6 Datei-Reads.

---

## 1. Wie das System heute funktioniert (Ist-Analyse)

**Kernidee:** Statt dass Claude ganze Quelldateien liest, gibt es einen vorverdichteten
Wissens-Layer in `_ai_context/`, der bei Session-Start zu einer einzigen `_SESSION.md`
(~2000 Token Budget) zusammengebaut wird.

**Die Lookup-Ketten heute:**

| Frage | Kette | Dateien |
|---|---|---|
| "Wo ist Funktion X?" | `_idx/symbols.md` → Datei:Zeile | 1 |
| "Welche Felder hat Typ Y?" | `_idx/interfaces.md` | 1 |
| "Button Z kaputt" | `_interaction_map.md` → Element→Datei:Zeile→Handler→State→Endpoint | 1 (aber: **leer**, nie gescannt) |
| "Bekannter Fehler?" | `_gotchas.md` / `debug_patterns.md` (ID + P1/2/3 + Symptom `?` + Dateien `@`) | 1–2 |
| "Was bricht wenn ich X ändere?" | `impact-graph.yaml` (gelernte Co-Changes) + `invariants.yaml` | Hook-seitig |
| Thema/Domain | `_ai_index.md` → `_idx/{frontend,backend,infra,project}.md` → `datei.md` | 3 |
| Semantisch | MCP `memory_search()` (Keyword-Scoring über Markdown-Blöcke, cross-project) | 0 (Tool) |

**Datums-/Frische-Modell heute:** verstreut über 5 Orte — `Zuletzt`-Spalte in Indizes,
`updated:` in registry.yaml, `Generiert:` in _SESSION.md, Git-Hash-Vergleich in
session-prep, Status-Emojis (🟢/⚠️/🔴). Kein einheitliches Konzept "ist dieser
Eintrag älter als der Code, den er beschreibt?".

**Stärken (behalten!):**
- Code-Format statt Prosa (→ ✗ ✓ ? @ ⇒) — extrem tokendicht
- Pointer-Prinzip (⇒) + P1/P2/P3-Prioritäten + Token-Budget mit Kompression
- Symbol Map mit `used_in` — echter Ersatz für Explorations-Reads
- Post-commit-Lernen (capture_from_diff, Impact Graph, Gap Detection)
- Invariants als maschinenlesbare Systemregeln

---

## 2. Schwachstellen (nach Impact sortiert)

**S1 — Kein einziger Einstiegspunkt.** Claude muss 6+ Spezialdateien und deren
Semantik kennen (symbols, interfaces, interaction_map, gotchas, debug_patterns,
hot_paths, Domain-Indizes). Die Behavior Rules in _SESSION.md erklären das, aber
jede Regel kostet Befolgungs-Wahrscheinlichkeit. Ein Modell, das EINE Aktion kennen
muss ("frag `locate()`"), ist zuverlässiger und billiger als eines mit 6 Regeln.

**S2 — Die Interaction Map (deine Schubladen-Idee für Buttons/Menüs) ist leer.**
Das wertvollste Stück für UI-Bugfixes existiert nur als Template. `ai-context-map.sh`
läuft nicht automatisch beim Setup und der Scan ist nicht robust genug.

**S3 — Kein einheitliches Frische-Modell.** Datum eines Fixes/Eintrags vs. Datum
der letzten Code-Änderung wird nirgends systematisch verglichen. Claude kann nicht
entscheiden: "Gotcha von 2026-04, aber auth.ts wurde 2026-06 refactored → misstrauen."

**S4 — Doppelte Codepfade + Drift.** v5.2-Fallback vs. v6.0-Registry-Pfad in
session-prep (beide gepflegt), `_ai_context/` vs. `_ai_context_template/` driften
(git status zeigt Parallel-Edits), Token-Zählung 3× dupliziert als Inline-Python.
Für neue Nutzer: ~20 Scripts, hohe Adoptionshürde.

**S5 — Suchqualität.** Registry-Tags enthalten Stopwort-Müll ("erzeugt", "voll",
"schl" — abgeschnittene deutsche Wörter). memory_search und symptom-router nutzen
naives Keyword-Overlap; Synonyme (Button/Schaltfläche, login/anmelden) matchen nicht.

**S6 — _SESSION.md muss aktiv gelesen werden.** CLAUDE.md sagt "lade _SESSION.md" —
das ist 1 Read + 1 Regel-Befolgung. Ein SessionStart-Hook kann den Inhalt direkt
injizieren (0 Reads, 100% Zuverlässigkeit).

**S7 — Schubladen sind nur Overflow-Management.** `ai-context-drawer.sh` archiviert
P3 und splittet große Dateien — gut, aber das ist keine *inhaltliche* Taxonomie.
Deine eigentliche Idee (Frontend-Schublade, Button-Schublade, Nav-Schublade …)
ist heute auf 4 fixe Domains begrenzt und nicht erweiterbar.

---

## 3. Ziel-Architektur v7 — drei Bausteine

### Baustein A: `locate()` — der eine Griff für alle Schubladen (höchster Impact)

Ein neues MCP-Tool, das ALLE bestehenden Indizes hinter einer Abfrage vereint:

```
locate("login button reagiert nicht")
→
┌─ TREFFER (confidence 0.92, Quelle: interaction_map) ──────────
│ 🔘 LoginButton  src/components/LoginForm.tsx:47
│   handler: handleLogin (LoginForm.tsx:31)
│   state:   useAuthStore.login
│   endpoint: POST /api/auth/login → src/app/api/auth/login/route.ts:12
│ 📅 Frische: Eintrag 2026-06-30 · Code zuletzt 2026-06-28 → AKTUELL ✅
│ ⚡ Verwandte Gotchas: auth_version [P2] (2026-04-14 — Code neuer, prüfen!)
│ 🔒 Invariante: auth_first (hard) — Auth-Check vor state-ändernden Routes
│ 🕸 Impact: auth.ts ändert sich meist mit middleware.ts, login.tsx (4× co-changed)
└──────────────────────────────────────────────────────────────
```

Intern fächert `locate()` über: interaction_map → symbols → interfaces →
gotchas/debug_patterns (Symptom-Zeilen 3× gewichtet) → invariants → impact-graph →
hot_paths. Rückgabe: max ~150 Token Antwortkarte. Kein Treffer → sagt es ehrlich
("kein Index-Treffer, grep nach: <vorgeschlagene Begriffe>").

Der bestehende `ai-symptom-router.sh` wird zur CLI-Variante desselben Kerns
(gemeinsame Logik in `mcp/src/lib/locate.ts`, CLI ruft `node dist/locate-cli.js`).

**Neue Behavior Rule (ersetzt Regeln 1+2a/b):**
> Bei jeder Frage "wo/warum/fix": ZUERST `locate("<beschreibung>")`.
> Nur wenn locate nichts liefert → grep/Read.

### Baustein B: Schubladen-Manifest `drawers.yaml` (deine Idee, generalisiert)

Statt 4 fixer Domains ein deklaratives Manifest — jede Schublade ist ein
benannter Ort mit Zuordnungsregeln und eigenem Datums-Stempel:

```yaml
# _ai_context/drawers.yaml
version: "7.0"
drawers:
  - id: ui_controls          # Buttons, Menüs, Nav — deine Kernidee
    label: "Interaktive UI-Elemente"
    index: _interaction_map.md
    match: { globs: ["src/components/**", "src/app/**/page.tsx"],
             keywords: [button, nav, menu, link, form, click, dropdown] }
  - id: api
    index: backend/endpoints.md
    match: { globs: ["src/app/api/**"], keywords: [endpoint, route, fetch, api] }
  - id: auth
    index: backend/auth.md
    match: { globs: ["src/lib/auth*", "src/middleware*"], keywords: [login, session, jwt, auth] }
  - id: data
    index: backend/database.md
    match: { globs: ["prisma/**", "src/lib/prisma*"], keywords: [schema, migration, db, query] }
  # Nutzer/Auto-Setup kann eigene Schubladen ergänzen (payments, emails, cron, …)
```

- `setup_ai_context.sh` erzeugt das Manifest automatisch aus der Projektstruktur
  (erkennt Next.js/Express/Python-Layouts) — Nutzer kann erweitern.
- `locate()` nutzt das Manifest als Routing-Tabelle: Query-Keywords → Schublade →
  nur DEREN Index durchsuchen (schneller, präziser).
- Der Drawer-Overflow (`ai-context-drawer.sh`) bleibt, arbeitet aber pro Schublade.
- Writeback-Regel wird trivial: neuer Eintrag → Schublade per Manifest bestimmen,
  nicht mehr 8 Zeilen Zuordnungstabelle in CLAUDE.md.

### Baustein C: Einheitliches Frische-Modell (deine Datums-Idee, systematisiert)

Jeder Eintrag in jeder Schublade bekommt zwei Stempel und einen abgeleiteten Status:

```
ID: auth_version
P: 2
seen: 2026-04-14            ← wann Eintrag geschrieben/bestätigt wurde
@ src/lib/auth.ts
# abgeleitet (auto, nie manuell):
# code_touched: 2026-06-28  ← git log -1 --format=%as -- src/lib/auth.ts
# status: STALE?            ← code_touched > seen ⇒ Code hat sich seit dem Fix geändert
```

Regeln:
- `code_touched` kommt aus Git — kein manueller Pflegeaufwand, immer korrekt.
- Status-Logik: `seen >= code_touched` → ✅ FRISCH · `code_touched > seen` → ⚠️ PRÜFEN
  · `seen` älter als 90 Tage UND Datei weg/umbenannt → 🔴 VERWAIST (Doctor räumt auf).
- `locate()` zeigt den Status in jeder Antwortkarte (siehe Baustein A).
- Wird ein Gotcha in einer Session bestätigt ("ja, war dieser Fehler"),
  aktualisiert der Writeback `seen:` — Frische ist damit selbstheilend.
- registry.yaml bekommt `seen` + `code_touched` als Felder; der Registry-Scan
  berechnet `code_touched` bei jedem `--scan` neu.

---

## 4. Aufräum-Maßnahmen (macht das System adoptierbar)

1. **SessionStart-Hook statt Lese-Anweisung:** `.claude/settings.json` Hook
   `SessionStart` → `cat _ai_context/_SESSION.md` als additionalContext injizieren.
   CLAUDE.md schrumpft auf ~10 Zeilen (Sprache + "nutze locate() zuerst" + Writeback-Pointer).
2. **Einen Codepfad:** v5.2-Fallback aus session-prep entfernen — Registry ist Pflicht,
   Setup erzeugt sie immer. Inline-Python-Blöcke (Token-Zählung, Chunk-Extraktion)
   in EIN `_ai_context/scripts/lib/ctx.py` konsolidieren.
3. **Template = Single Source:** `_ai_context/` in DIESEM Repo wird aus
   `_ai_context_template/` generiert (Symlink oder Sync-Check im Doctor), nie mehr
   parallel editiert.
4. **Tag-Qualität fixen:** Registry-Scan: deutsche+englische Stopwortliste, keine
   abgeschnittenen Wörter, Wortstamm-Minimum 4 Zeichen, Synonym-Aliase
   (button↔schaltfläche, login↔anmelden↔signin) in `_ai_context/scripts/lib/synonyms.txt`.
5. **Interaction Map beim Setup füllen:** `setup_ai_context.sh` ruft
   `ai-context-map.sh` einmal auf; post-commit regeneriert nur bei Komponenten-Diffs
   (existiert schon, nur verdrahten + Scanner robust machen: JSX `onClick|onSubmit|href`,
   Vue `@click`, Svelte `on:click`).
6. **Doctor erweitert:** prüft drawers.yaml-Konsistenz, verwaiste Einträge
   (Datei existiert nicht mehr), Frische-Status-Verteilung, leere Interaction Map.

## 5. Was NICHT gebaut wird (bewusst)

- Kein Embedding-/Vektor-Store als Pflicht (Ollama bleibt optionales Add-on) —
  Keyword+Synonym+Schubladen-Routing reicht für <50k LOC und braucht keine Infra.
- Kein eigener Sprachserver/AST-Parser — regex-basierte Symbol Map ist gut genug,
  `used_in` deckt den Rest.
- Keine neuen Pflichtdateien für den Nutzer — alles auto-generiert oder optional.

---

## 6. Erwarteter Effekt

| Szenario | v6.5 | v7 |
|---|---|---|
| UI-Bug ("Button X kaputt") | 3–5 Reads (Map leer → grep) | 1 locate() ≈ 150 Tok |
| "Ist dieser Fix noch gültig?" | unentscheidbar | Frische-Status in Karte |
| Session-Start | 1 Read _SESSION.md + Regelbefolgung | 0 Reads (Hook injiziert) |
| Writeback-Ziel finden | 8-Zeilen-Tabelle interpretieren | Manifest-Lookup |
| Neues Projekt onboarden | ~20 Scripts verstehen | setup + locate, fertig |

---
---

# SONNET-5-PROMPT (Copy-Paste zum Umsetzen)

```
Du arbeitest im Repo ai-context-engine (Arbeitsverzeichnis = Repo-Root).
Lies zuerst V7_PERFEKTIONSPLAN.md komplett — er ist die Spezifikation.
Kommunikation Deutsch, Code/Identifier Englisch. Arbeite die Phasen strikt
in Reihenfolge ab, committe nach jeder Phase einzeln (conventional commits,
Prefix feat(v7-phaseN): …). Führe nach jeder Phase die genannten Checks aus.

PHASE 1 — Shared Lib + Tag-Qualität
1. Erstelle _ai_context_template/scripts/lib/ctx.py: Funktionen count_tokens(text),
   extract_chunk(file, id), parse_registry(path), git_last_touched(path) →
   (nutzt: git log -1 --format=%as -- <path>). Ersetze ALLE Inline-Python-
   Duplikate in ai-session-prep.sh, ai-context-drawer.sh, ai-symptom-router.sh,
   check_context_hash.sh durch Aufrufe dieser Lib (python3 lib/ctx.py <cmd> …).
2. Fixe die Tag-Generierung in ai-context-registry.sh: DE+EN-Stopwortliste,
   min. 4 Zeichen, keine abgeschnittenen Wörter. Lege scripts/lib/synonyms.txt
   an (Format: wort=alias1,alias2 — mindestens: button=schaltfläche,btn;
   login=anmelden,signin,sign-in; nav=navigation,menu,menü; fehler=error,bug).
   Registry-Scan expandiert Tags über Synonyme.
CHECK: bash ai-context-registry.sh --scan auf diesem Repo → registry.yaml
enthält keine Tags <4 Zeichen und keine deutschen Stopwörter mehr.

PHASE 2 — Frische-Modell
1. Erweitere das Chunk-Format: neue Zeile `seen: YYYY-MM-DD` in _gotchas.md /
   debug_patterns.md / security.md Templates + Legende. Migration: Registry-Scan
   trägt bei Chunks ohne seen das updated-Datum aus registry.yaml ein.
2. ai-context-registry.sh --scan berechnet pro Chunk code_touched = max
   git_last_touched über alle @-Dateien und schreibt seen, code_touched und
   status (fresh|check|orphan) in registry.yaml. orphan = alle @-Dateien
   existieren nicht mehr. check = code_touched > seen.
3. ai-context-doctor.sh: neue Sektion "Frische" — zählt fresh/check/orphan,
   listet orphans zum Aufräumen.
CHECK: Scan auf diesem Repo → registry.yaml hat seen/code_touched/status
für jeden Chunk; Doctor zeigt die Verteilung.

PHASE 3 — drawers.yaml (Schubladen-Manifest)
1. Erstelle _ai_context_template/drawers.yaml exakt nach Plan-Schema (Abschnitt 3B),
   mit den Default-Schubladen ui_controls, api, auth, data, state, infra.
2. setup_ai_context.sh: generiert drawers.yaml projektspezifisch — erkennt
   Next.js (src/app|pages), Express (routes/), Python (app/|api/) und passt
   die globs an; unbekannte Struktur → Defaults mit TODO-Kommentar.
3. ai-context-drawer.sh: liest drawers.yaml, wendet Overflow-Regeln pro
   Schublade an (bestehende Logik generalisieren, keine hartkodierten Pfade).
CHECK: setup in einem temporären Next.js-Dummy-Projekt (lege es unter
/tmp selbst an: nur package.json + src/app/api/x/route.ts + src/components/A.tsx)
→ drawers.yaml globs zeigen auf src/app/api/** und src/components/**.

PHASE 4 — locate() Kern + MCP-Tool + CLI
1. mcp/src/lib/locate.ts: locateQuery(query) fächert über (a) _interaction_map.md,
   (b) _idx/symbols.md, (c) _idx/interfaces.md, (d) Registry-Chunks (Symptom-
   Zeile ? dreifach gewichtet — Scoring-Logik aus ai-symptom-router.sh portieren),
   (e) invariants.yaml (scope-Glob-Match auf Treffer-Dateien), (f) impact-graph.yaml
   (~/.ai-context/projects/<id>/), (g) hot_paths.md. Routing: Query-Keywords →
   drawers.yaml → passende Schublade zuerst, Rest als Fallback. Synonym-Expansion
   aus lib (portiere synonyms.txt-Parsing nach TS).
   Rückgabe: kompakte Markdown-Karte (max ~150 Tokens): Top-Treffer mit
   Datei:Zeile, Handler/Felder, Frische-Status (seen vs code_touched),
   verwandte Gotchas (mit Frische-Warnung), betroffene Invarianten, Impact-Nachbarn.
   Kein Treffer: "kein Index-Treffer" + 3 grep-Begriff-Vorschläge.
2. Registriere als MCP-Tool locate in mcp/src/server.ts (Beschreibung:
   "Findet Code-Stelle/Ursache für eine Frage oder Bug-Beschreibung in 1 Lookup.
   IMMER zuerst aufrufen bevor Dateien gelesen oder gegrept werden.").
3. mcp/src/locate-cli.ts als CLI-Einstieg; ai-symptom-router.sh wird zum
   dünnen Wrapper (node dist/locate-cli.js "$@"), Fallback auf alte Bash-Logik
   nur wenn node/dist fehlt.
4. npm run build im mcp/-Ordner; erweitere mcp/test/smoke.mjs um einen
   locate-Testfall (Query "prisma connection" muss den debug-Chunk
   prisma_connection finden).
CHECK: node mcp/test/smoke.mjs grün; node mcp/dist/locate-cli.js
"prisma pool voll" liefert eine Karte mit prisma_singleton.

PHASE 5 — Interaction Map real füllen
1. Härte ai-context-map.sh: scanne .tsx/.jsx/.vue/.svelte nach onClick/onSubmit/
   href/@click/on:click, extrahiere Element-Label (Button-Text/aria-label),
   Handler-Name, verwendete Stores (use*Store, useContext), gefetchte Endpoints
   (fetch/axios URL-Literale). Schreibe die 5-Spalten-Tabelle.
2. setup_ai_context.sh ruft den Scan einmalig auf; der post-commit Hook
   regeneriert nur wenn der Commit Komponenten-Dateien enthält.
CHECK: Im /tmp-Dummy-Projekt (A.tsx mit <button onClick={handleSave}>Speichern
</button> + fetch('/api/x')) → Map enthält Zeile mit A.tsx:Zeile, handleSave,
/api/x. locate("speichern button") findet sie.

PHASE 6 — Session-Start entschlacken
1. _ai_context_template/.claude/settings.json: SessionStart-Hook, der
   _SESSION.md-Inhalt als Kontext ausgibt (hooks → SessionStart → command:
   "cat _ai_context/_SESSION.md 2>/dev/null || true").
2. Kürze die Behavior Rules in ai-session-prep.sh: Regel 1+2 ersetzen durch
   EINE Regel: "Bei wo/warum/fix-Fragen: ZUERST MCP-Tool locate(<beschreibung>).
   Nur wenn kein Treffer: grep/Read. Danach normal fortfahren." Regeln 3–6 behalten.
3. Entferne den v5.2-Gotchas-Fallback aus ai-session-prep.sh (Registry ist
   Pflicht; setup erzeugt sie). Prüfe dass --minimal/--full weiter funktionieren.
4. Sync-Disziplin: ai-context-doctor.sh warnt, wenn _ai_context/scripts/*
   von _ai_context_template/scripts/* abweicht (diff -q Liste).
CHECK: bash _ai_context/scripts/ai-session-prep.sh läuft fehlerfrei,
_SESSION.md ≤ 2000 Tokens, enthält die neue locate-Regel.

PHASE 7 — Doku + Version
1. README.md: locate() als Haupt-Feature dokumentieren (Beispielkarte aus dem
   Plan), drawers.yaml und Frische-Modell erklären, Roadmap-Häkchen setzen.
2. CLAUDE.md (Repo + Template): auf Kurzform bringen — Sprache, locate-first-Regel,
   Writeback via drawers.yaml, Verweis auf _SESSION.md.
3. VERSION → 7.0.0. migrate.sh: v6.x→v7-Migration (seen-Felder nachtragen,
   drawers.yaml erzeugen, Hook eintragen).
CHECK: Alle Smoke-Tests grün, ai-context-doctor.sh ohne Fehler, dann
finaler Commit.

WICHTIGE REGELN:
- Bestehende Formate (Code-Format →✗✓?@⇒, P1/2/3, Chunk-Anker <!-- #id -->)
  NICHT brechen — nur erweitern. Bestehende Nutzer-Daten müssen weiter parsen.
- Bash: set -euo pipefail beibehalten, macOS+Linux (stat/sed-Varianten wie im
  Bestandscode behandeln).
- Kein neues npm-Package ohne Not; MCP-SDK ist vorhanden.
- Wenn eine Spezifikationslücke auftaucht: triff die einfachste Entscheidung,
  die die Ziel-Tabelle in Plan-Abschnitt 6 erfüllt, und dokumentiere sie in
  decisions.md.
```
