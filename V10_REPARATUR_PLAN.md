# V10 — Reparatur-Plan: Warum das System (noch) keine Tokens spart — und wie es das lernt
> **Status: ENTWURF** — erstellt 2026-08-09 aus der Analyse der ersten echten
> Benchmark-Zahlen (BENCHMARKS.md, n=1) plus Live-Beobachtung der v9-b-Injektionen.
> Umsetzung durch Sonnet, Phase für Phase, jede einzeln committbar/verifizierbar.

---

## 1. Diagnose — vier Ursachen, alle mit Beleg

### Ursache 1: Die Wissensbasis des Engine-Repos ist Demo-Müll (Signal ≈ 0)

**Beleg (verifiziert, nicht vermutet):**
- `_ai_context/_quick_facts.md` im Engine-Repo sagt: `Project: test`,
  `Stack: Next.js + Prisma` — beides falsch. Die "Key File Paths" listen
  `src/lib/auth.ts` und `src/lib/prisma.ts`, die es im Engine-Repo nicht gibt.
- 7 der ~10 Wissens-Chunks (`prisma_singleton`, `hydration_mismatch`,
  `auth_first`, `input_validation`, `scope_to_user`, `error_format`,
  `no_secret_frontend`) sind 1:1 die Demo-Beispiele aus
  `_ai_context_template/` — sie beschreiben ein fiktives Next.js-Projekt,
  nicht diese Engine.

**Wirkung:** Jede locate()-Anfrage matcht gegen Demo-Inhalte. Der
Prompt-Router injiziert deshalb bei fast jedem Prompt irrelevante Gotchas
("test ergebnisse erklären" → `input_validation`, `scope_to_user`). Das
kostet Tokens UND lenkt das Modell ab, statt zu helfen. Das ist zugleich
ein Produktproblem: `setup_ai_context.sh` liefert diese Demo-Chunks an
JEDES neue Projekt aus, und nichts erinnert je daran, sie zu ersetzen.

### Ursache 2: Prompt-Router-Schwelle ist `score > 0` — ein einziges Allerweltswort reicht

**Beleg:** `mcp/src/lib/locate.ts` filtert überall mit `score > 0`
(Zeilen ~390/420/562/582). Query-Tokens wie "test", "system", "ergebnisse"
überlappen mit irgendeinem Chunk-Text → Injektion. Live in dieser Session
dreimal hintereinander reproduziert (alle drei letzten User-Prompts bekamen
irrelevante Injektionen). Zusätzlich verdrängen generische Symbolnamen
(eine Funktion namens `read`) die eigentlich relevante Datei.

**Wirkung:** Die v9-b-Automatik, die Tokens sparen sollte, PRODUZIERT
aktuell bei generischen Prompts Token-Kosten (Injektion + deren
Cache-Re-Read in jedem Folgeturn) ohne Nutzen.

### Ursache 3: Fixkosten × Turns — der Kontext-Layer wird in JEDEM Turn erneut bezahlt

**Beleg (die wichtigste Rechnung aus den Benchmark-Rohdaten):**
- `_SESSION.md` = ~1.842 Tokens, wird bei SessionStart injiziert und danach
  in jedem Turn als Cache-Read erneut gezählt.
- `fixture_5bugs`: beide Arme brauchten exakt 12 Turns. Token-Differenz:
  162.032 − 141.906 = **20.126 Tokens ≈ 12 × ~1.700** — fast exakt die
  _SESSION.md-Größe mal Turn-Anzahl. Der Mehrverbrauch MIT System ist also
  kein Rätsel, sondern schlicht: Fixkosten pro Turn, denen in dieser
  Aufgabe null eingesparte Leseschritte gegenüberstanden.
- Gegenprobe `locate_read_guard`: System sparte 2 Turns (4 statt 6) →
  Ersparnis (75k Tokens) übertraf die Fixkosten deutlich → Netto-Gewinn.

**Formel:** Das System gewinnt nur, wenn
`eingesparte Reads/Turns > SESSION-Overhead × Turn-Anzahl`.
Zwei Hebel: Overhead senken UND Injektion treffsicherer machen.

### Ursache 4: Benchmark misst z.T. die falsche Aufgabe

`fixture_5bugs` ("finde ALLE Bugs") zwingt jedes Modell, ohnehin jede
relevante Datei zu lesen — Routing kann dort prinzipiell keine Reads
sparen, nur die Reihenfolge ändern. Solche Aufgaben messen die Fixkosten,
nicht den Nutzen. Es fehlen Aufgaben der Klasse, für die das System gebaut
ist: "wo ist X", "fixe dieses eine Symptom", Vokabular-Mismatch.

---

## 2. Reparatur in vier Phasen

### Phase R1 — Wissensbasis entgiften + Selbstschutz gegen Wiederholung

1. **Engine-Repo säubern:** Die 7 Demo-Chunks aus `_ai_context/_gotchas.md`,
   `debug_patterns.md`, `security.md` entfernen (sie leben korrekt im
   Template weiter). `_quick_facts.md` mit echter Identität füllen
   (`Project: ai-context-engine`, `Stack: Bash + Python + TypeScript/MCP`,
   echte Key-Files: `mcp/src/lib/locate.ts`, `hooks/post-commit`,
   `_ai_context/scripts/lib/ctx.py`, `knowledge.manifest.yaml`).
   Danach `ai-context-registry.sh --scan` + `ai-session-prep.sh`.
   Die echten, in den letzten Sessions verdienten Chunks
   (`silent_noop_needs_effect_test`, `stopword_lists_incomplete`,
   `add_knowledge_file`-Playbook) bleiben — das IST das echte Wissen.
2. **Doctor-Check "demo_content" (neu):** vergleicht Chunk-Hashes der
   Projekt-Wissensdateien gegen die Template-Pendants (Hash-Logik aus
   `ctx.py` wiederverwenden). Identischer Chunk in beiden → WARN
   "Demo-Inhalt nie ersetzt". Zweiter Teil: `_quick_facts.md`-Projektname
   ≠ Verzeichnisname → WARN. Damit kann dieser Zustand in keinem der 9
   Projekte mehr unbemerkt bleiben (Rollout zeigt sofort, wo überall noch
   Demo-Wissen liegt).

### Phase R2 — Präzision: injizieren nur bei echtem Treffer

In `mcp/src/lib/locate.ts` + `ai-prompt-router.sh`:
1. **Mindest-Score:** Chunk-/Symbol-/Interface-Treffer erst ab **≥2
   getroffenen Inhalts-Tokens** (oder exaktem Namens-Match) werten —
   `score > 0` bleibt nur für den expliziten CLI-/MCP-Aufruf (dort ist ein
   schwacher Treffer besser als keiner), der **Router** bekommt einen
   eigenen strengeren Modus (`locate-cli.js --strict` Flag oder
   `LocateResult` um `strength: 'strong'|'weak'` erweitern; Router
   injiziert nur `strong`).
2. **Generische Symbolnamen dämpfen:** Symbol-Treffer, deren Name <5
   Zeichen ODER in der Stopword-Liste ist (`read`, `get`, `set`, `run`),
   zählen nur bei exaktem Query-Token-Match — behebt die bekannte
   "ƒ read verdrängt die echte Datei"-Schwäche aus v9-b.
3. **Cross-Prompt-Dedup:** Router führt `_ai_context/.session/
   <session_id>.injected.jsonl` (gleiches Ledger-Muster wie Read-Guard):
   bereits injizierte Chunk-IDs werden in derselben Session nicht erneut
   injiziert. Aufräumen über den bestehenden 24h-Sweep (Glob in
   `ai-session-prep.sh` von `*.reads.jsonl` auf `*.jsonl` erweitern).
4. **Abnahmekriterium (Regressionstest im Script-Kommentar + manuell):**
   die drei Live-Rausch-Prompts dieser Session ("weiter mit nächste
   phase", "test ergebnisse …", "schaue mal die test ergebnisse …")
   müssen nach R1+R2 **stille** Router-Läufe ergeben; "login button
   reagiert nicht" (im test-projekt) muss weiter injizieren.

### Phase R3 — Fixkosten senken: _SESSION.md auf Diät

1. `ai-session-prep.sh`: `TOKEN_BUDGET_SOFT` von 2000 → **1200**; die
   Domain-Index-Volltabellen (backend/frontend/infra/project, ~400 Tokens)
   durch eine 4-Zeilen-Pointer-Liste ersetzen ("backend: endpoints, auth —
   Details: _idx/backend.md"); Behavior-Rules-Prosa (~350 Tokens) auf die
   Kurzform komprimieren, die CLAUDE.md ohnehin schon enthält (keine
   Dopplung von Regeln, die in beiden Injektionen landen).
2. Ziel messbar: `__AI_CTX__:<tokens>`-Zeile nach Regenerierung ≤ 1.200.
   Bei 12-Turn-Sessions sinken die Fixkosten damit um ~8.000 Tokens.
3. Template-`_SESSION`-Generierung identisch nachziehen (ein Code-Pfad,
   `ai-session-prep.sh` ist bereits geteilt — nur Budget-Konstante + die
   zwei Sektions-Renderer ändern).

### Phase R4 — Benchmark auf die richtige Frage richten

1. `bench/tasks.yaml` um 2 Aufgaben der Zielklasse erweitern:
   - `fix_one_symptom` (test-projekt): "Der Admin-Endpoint ist ohne Login
     erreichbar — finde die Ursache und nenne die Datei" (ein Symptom,
     Routing soll direkt zu `admin/route.ts` führen, ohne alle 8 Routen
     zu lesen).
   - `vocab_mismatch` (test-projekt): Symptom bewusst in anderem Vokabular
     ("Datenbankverbindungen laufen beim Entwickeln voll") → testet den
     v9-e-Semantik-Fallback End-to-End.
2. Report um **Kosten als Leitmetrik** ergänzen (Input-Tokens sind wegen
   Cache-Read-Preisdifferenz irreführend — $-Spalte prominent, Token-Spalte
   sekundär) und eine Delta-Zeile pro Task (`with − without`, in $ und %).
3. Nach R1–R3: `python3 bench/ai-bench.py --repeat 3` über alle 4 Tasks
   laufen lassen (~$8–10, vorher ankündigen) — erst DIESE Zahlen sind der
   ehrliche Vorher/Nachher-Vergleich gegen die heutige Baseline in
   `bench/results.jsonl` (die bleibt als Vorher-Beleg unangetastet drin).

---

## 3. Reihenfolge & Regeln

| Phase | Warum zuerst | Fertig wenn |
|---|---|---|
| R1 | Ohne saubere Wissensbasis ist jede Präzisions-Messung wertlos | Doctor-Check `demo_content` existiert und meldet im Engine-Repo 0 Treffer; locate("test ergebnisse …") liefert keine Demo-Chunks mehr |
| R2 | Größter Rausch-Stopper; braucht R1 für sinnvolle Schwellen-Tests | 3 Rausch-Prompts still, 1 echter Bug-Prompt injiziert weiter |
| R3 | Unabhängig, aber vor der Messung (sonst misst R4 den alten Overhead) | `__AI_CTX__` ≤ 1200 im Engine-Repo UND in ai-verify-self-Sandbox |
| R4 | Misst das Ergebnis von R1–R3 | BENCHMARKS.md mit n≥3 pro Zelle, $-Delta-Zeilen, 4 Tasks |

Unverändert gültig: Template + `_ai_context/` symmetrisch halten,
Verteilung über `migrate.sh` im selben Commit mitdenken, jede Phase endet
mit `ai-verify-self.sh` PASS + `ai-context-doctor.sh` ohne neue FAILs +
Rollout `install.sh --pro --migrate-all` + Stichprobe in 2 Projekten.
Nach R1-Rollout gezielt prüfen: Der neue `demo_content`-Check wird in den
8 Nutzer-Projekten vermutlich WARNen (auch dort liegen Demo-Chunks) — das
ist gewollt (Sichtbarkeit), aber in der Rollout-Zusammenfassung explizit
berichten, nicht als Fehler werten.

## 4. Erwartetes Ergebnis (ehrlich formuliert)

Nach R1–R3 sollte gelten: Navigations-/Symptom-Aufgaben gewinnen deutlicher
als die bisherigen 27% (weniger Rauschen, kleinere Fixkosten), und
Vollanalyse-Aufgaben (`fixture_5bugs`) nähern sich der Parität (~1.200
statt ~1.842 Tokens Fixkosten × Turns), statt 14% zu verlieren. Wenn R4
das NICHT zeigt, ist die nächste Hypothese die Injektionsstrategie selbst
(SessionStart-Vollinjektion vs. On-Demand) — das wäre dann ein eigener
Plan, nicht vorweggenommen.
