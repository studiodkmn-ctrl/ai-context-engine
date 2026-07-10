# V8 — Autonomie-Plan: Selbstheilend, selbstaktualisierend, für jeden nutzbar
> Erstellt: 2026-07-10 · Basis: v7.0.0 (siehe V7_PERFEKTIONSPLAN.md), Live-Rollout auf
> 7 reale Projekte, Produktionsreife-Härtetest (frischer Clone, Migration, install.sh)

---

## 1. Ziel des Systems — worum es wirklich geht

Nicht "mehr Dateien" oder "mehr Regeln". Das eigentliche Problem:
**KI-Coding-Agenten haben kein Langzeitgedächtnis und keine Navigationskarte.**
Jede Session fängt bei null an — der Agent liest sich blind durch Dateien, um
Dinge wiederzufinden, die er (oder ein anderer Agent) schon einmal wusste.
AI Context Engine macht dieses Wissen explizit, durchsuchbar (`locate()`) und
selbstprüfend (Frische-Modell, Invarianten). Das spart nicht nur Tokens —
es macht Agenten *korrekter*, weil sie Systemregeln nicht mehr raten müssen.

**Der Nordstern für v8:** Der Nutzer installiert einmal — und danach passiert
alles Weitere von selbst. Kein `ai-migrate` von Hand, kein Prüfen ob die
globale Kopie veraltet ist, kein Wissen nötig, was `drawers.yaml` überhaupt
ist. Das System repariert und aktualisiert sich selbst, sichtbar aber ohne
Zutun.

---

## 2. Was wir übersehen haben (verifiziert, nicht vermutet)

Diese Session hat gezeigt: **die 6 Nutzerprojekte liefen wochenlang auf einem
veralteten Stand, ohne dass irgendein Mechanismus das gemeldet hätte.** Das
ist kein Einzelfall, sondern strukturell — hier die Belege:

| Lücke | Befund | Warum es wichtig ist |
|---|---|---|
| **Kein Selbst-Update** | `grep -rl "curl.*github\|version.*check"` → nur `install.sh` selbst, kein Update-Checker. `~/.ai-context` war einen Monat alt. | Genau das hat heute 6 echte Projekte betroffen. Ohne diese Session wäre es nie aufgefallen. |
| **`--fix` ist kein echtes Self-Healing** | Gated hinter `~/.ai-context/edition == pro` (eine lokale Textdatei, kein echtes Paywall — aber trotzdem: Default-Nutzer bekommt nie automatische Reparatur). Muss manuell aufgerufen werden. | "Selbstheilend" ist aktuell nur ein manuelles Kommando für eine Minderheit der Installationen. |
| **Keine CI / kein Testnetz für die Bash-Skripte** | `.github/workflows/` existiert nicht. Nur `mcp/test/smoke.mjs` (8 Assertions) deckt die TS-Schicht ab. Die 17 Bash-Skripte haben null automatisierte Tests. | Genau deshalb sind die `set -e`/pipefail-Abstürze, der TODO-Regex-Bug und die 4 nie committeten Template-Dateien überhaupt bis in diese Session durchgerutscht — kein CI hätte sie vorher gefangen. |
| **Kein `uninstall.sh`** | Existiert nicht. | Vertrauens-Lücke: Nutzer, die nicht wissen wie sie rückgängig machen, installieren erst gar nicht. |
| **`drawers.yaml` nur für JS/Next.js wirklich sinnvoll** | `path_to_glob()` in `setup_ai_context.sh` nutzt zwar erkannte Pfade, aber ohne stack-spezifische Sonderfälle wie `detect_stack()` sie für Django/FastAPI/Go schon hat. Bei Nicht-JS-Projekten sind die generierten Globs oft nur ungefähr richtig. | "Für jeden nutzbar" heißt auch: nicht nur für Next.js-Projekte gut funktionieren. |
| **Kein Windows/WSL** | Keine Erwähnung im gesamten Repo. Reines bash+md5/stat-Portabilitäts-Geflecht (schon macOS/Linux-Unterschiede sind an mehreren Stellen mit Fallback-Ketten gepatcht). | Ein großer Teil potenzieller Nutzer fällt komplett raus. |
| **Auto-Update wäre ein neues Vertrauens-/Sicherheits-Risiko** | Aktuell macht niemand automatisch `git pull` + Skript-Ausführung. Führt man das ein, braucht es Integritätsprüfung + Rollback — sonst ist es ein Supply-Chain-Risiko, das schlimmer ist als das Problem, das es löst. | Muss von Anfang an sicher designt werden, nicht nachträglich. |

---

## 3. Ist "für jeden brauchbar" realistisch?

**Ja, mit klarem Scope — nicht als Blanko-Versprechen.** Der Weg dahin ist
kein Rewrite, sondern vier saubere Ausbaustufen auf dem bestehenden Fundament
(Bausteine unten). Was NICHT realistisch ist in einem Schritt: vollwertige
Windows-Unterstützung UND Auto-Update UND CI UND Onboarding gleichzeitig
perfekt machen. Deshalb: explizite Priorität A→D unten, A ist der Hebel mit
dem größten Verhältnis von Wirkung zu Risiko.

---

## 4. Bausteine v8 (in Prioritätsreihenfolge)

### A — Selbst-Update-Loop (höchste Priorität, behebt den Befund von heute)

Ziel: nie wieder "6 Projekte liefen einen Monat auf altem Stand, ohne dass
es jemand merkt".

- **Versions-Manifest**: `VERSION` im Repo bleibt Quelle der Wahrheit. Neuer
  leichter Check (`ai-context-selfcheck.sh`): vergleicht lokale
  `~/.ai-context/VERSION` gegen die Remote-Version — per `git -C
  <install-quelle> fetch --tags && git describe` wenn die Installation aus
  einem Git-Checkout kam (wie bei diesem Nutzer), sonst optional gegen einen
  GitHub-Release-Tag via `curl` (nur mit explizitem Opt-in, nie automatisch
  im Hintergrund Netzwerk ohne Zustimmung).
- **Wo geprüft wird**: NICHT bei jedem SessionStart (zu langsam/lästig).
  Stattdessen: rate-limitiertes Cron-artiges Intervall (z.B. max. 1×/7 Tage),
  getriggert entweder über die bereits vorhandene Claude-Code-`schedule`-
  Fähigkeit (Routine, die `auto-update-all.sh --check-only` aufruft) oder
  einen leichten Zeitstempel-Guard im post-commit-Hook.
- **Anwenden, nicht nur melden**: wenn eine neue Version verfügbar ist,
  automatisch `migrate.sh` je registriertem Projekt ausführen (wie heute
  manuell demonstriert) — IMMER additiv, NIE `git add`/`commit`/`push` im
  Zielprojekt (das bleibt Nutzer-Entscheidung).
- **Integrität**: vor dem Anwenden prüfen, dass die Quelle (Git-Remote-URL)
  mit der beim Erstinstall gespeicherten übereinstimmt — verhindert, dass
  ein manipuliertes `~/.ai-context/_ai_context_template` unbemerkt
  durchrutscht.
- **Rollback**: vor jedem Auto-Update ein Backup von `~/.ai-context/
  _ai_context_template` + `~/.ai-context/mcp/dist` als `.backup-<timestamp>`
  behalten (letzte 3), plus ein `ai-context-rollback.sh`.
- **Sichtbarkeit**: eine Zeile im SessionStart-Hook-Output
  ("🔄 Update auf v7.1 verfügbar — wird beim nächsten Commit angewendet"),
  nie stumm im Hintergrund etwas Verhaltensänderndes tun ohne Hinweis.

### B — Echtes Self-Healing (macht `--fix` zum Standard, nicht zum Pro-Privileg)

- `--fix`-Gate entfernen für die Checks, die nachweislich sicher/mechanisch
  sind (anchors, mapdrift, orphans aus dem Frische-Modell archivieren nach
  N Tagen `orphan`-Status). Bleibt lesbar/nachvollziehbar: jede Auto-Reparatur
  hinterlässt eine Zeile in `_temp_notes.md` ("Auto-Fix: 2 Anker injiziert,
  1 Orphan-Gotcha archiviert — 2026-07-15").
  Als klare Grenze: Auto-Fix schreibt niemals Fließtext-Inhalt (Gotcha-Body,
  Regel-Text) — nur strukturelle/mechanische Reparaturen. Inhaltliche Fixes
  bleiben "für Claude" (CLAUDE-fixkind), wie heute.
- SessionStart-Hook ruft künftig `ai-context-doctor.sh --session-autofix`
  statt nur `--session` — still, mechanisch, protokolliert.

### C — CI + Testnetz (verhindert, dass v7-artige Bugs nochmal live gehen)

- `.github/workflows/ci.yml`: bei jedem Push/PR → `shellcheck` über alle
  `*.sh` (mit begründeten Ausnahmen wo nötig), `npm run build` + `node
  test/smoke.mjs` für `mcp/`, plus ein neuer, minimaler Bash-Testharness
  (kein neues Framework nötig — Muster: Dummy-Projekt in `/tmp` anlegen,
  `setup_ai_context.sh` laufen lassen, `ai-context-doctor.sh --check`
  erwartet 0 FAIL, `locate()` erwartet einen bekannten Treffer — exakt die
  manuellen Checks aus dieser Session, nur automatisiert und reproduzierbar).
- Das hätte 3 der 4 in dieser Session gefundenen Produktionsbugs
  (fehlende Template-Dateien, TODO-Regex-Overmatch, drawer-Split von
  `decisions.md`) vor dem ersten Nutzer-Kontakt gefangen.

### D — Onboarding + Reichweite

- `uninstall.sh`: entfernt `~/.ai-context`, Shell-Block aus `.zshrc`/
  `.bashrc`, Git-Hooks aus registrierten Projekten (mit Bestätigung, listet
  vorher genau was gelöscht wird).
- SessionStart-Auto-Bootstrap: wenn Claude Code in einem Git-Repo ohne
  `_ai_context/` startet UND `~/.ai-context` global installiert ist,
  einmalig fragen ("Dieses Projekt hat noch kein AI Context — einrichten?")
  statt dass der Nutzer wissen muss, dass `ai-context-setup` existiert.
- `drawers.yaml`-Generierung für Django/FastAPI/Express/Go/Rails erweitern
  (dieselbe Fallunterscheidung, die `detect_stack()` schon hat, in
  `generate_drawers_yaml()` nachziehen statt generischer Next.js-Pfade).
- Windows: keine Portierung — stattdessen ehrlich im README als
  "macOS/Linux, WSL ungetestet" scopen, damit niemand stundenlang debuggt,
  was strukturell nicht unterstützt ist.

---

## 5. Was bewusst NICHT gebaut wird

- Kein vollautomatisches, unsichtbares Auto-Update ohne jede Nutzer-
  Sichtbarkeit — das ist ein Sicherheits- und Vertrauensproblem, kein Feature.
- Keine Windows-Portierung in diesem Schritt (Aufwand/Nutzen aktuell nicht
  begründbar; zuerst A–C, dann neu bewerten).
- Kein Rewrite von Bash nach Python/Node — die bestehende Architektur ist
  tragfähig, das Problem war Testabdeckung, nicht Sprachwahl.

---
---

# PROMPT FÜR FABLE 5 (Copy-Paste zum Umsetzen)

```
Du arbeitest im Repo ai-context-engine (Arbeitsverzeichnis = Repo-Root,
lokal umbenannt von ai-context-v6.5, GitHub-Remote heißt bereits
ai-context-engine, Stand v7.0.0). Lies zuerst V8_AUTONOMY_PLAN.md
komplett — er ist die Spezifikation samt Begründung. Kommunikation
Deutsch, Code/Identifier Englisch. Arbeite die Bausteine A→D strikt in
Reihenfolge ab (A hat die höchste Wirkung — es behebt den konkreten
Vorfall aus der letzten Session: 6 registrierte Nutzerprojekte liefen
unbemerkt einen Monat auf veraltetem Stand). Committe nach jedem
Baustein einzeln (conventional commits, Prefix feat(v8-<letter>): …).
Führe nach jedem Baustein die genannten Checks aus. Push nach jedem
Commit zu origin/main (Remote ist bereits konfiguriert, main ist der
Ziel-Branch, kein Force-Push nötig).

WICHTIG — bevor du irgendetwas an Auto-Update/Self-Healing baust:
Verstehe zuerst wirklich, wie der bestehende Stand funktioniert.
Lies mindestens: install.sh, migrate.sh, auto-update-all.sh,
_ai_context_template/scripts/ai-context-doctor.sh (besonders
apply_mechanical_fixes() und die --fix/Pro-Gating-Logik ab Zeile 42),
hooks/post-commit, mcp/src/lib/locate.ts. Rate nichts — grep/lies nach,
bevor du eine Annahme über bestehendes Verhalten triffst.

BAUSTEIN A — Selbst-Update-Loop
1. Neues Skript _ai_context_template/scripts/ai-context-selfcheck.sh:
   vergleicht die lokal installierte Version (~/.ai-context/VERSION —
   lege diese Datei an, falls sie fehlt, install.sh muss VERSION mit
   ausliefern) gegen die Quelle. Erkenne den Installationstyp: wenn
   ~/.ai-context aus einem git-Checkout stammt (prüfe ob der
   Ursprungs-Ordner, aus dem install.sh lief, noch ein .git enthält —
   die Quelle dafür in ~/.ai-context/.source-path ablegen, von
   install.sh geschrieben), dann `git fetch` + `git rev-list
   HEAD..origin/main --count` dort. Sonst: kein Update-Check (kein
   Silent-Netzwerkzugriff ohne bekannte Quelle), stattdessen Hinweis
   "Update-Check nicht verfügbar für diese Installationsart".
2. Rate-Limiting: Zeitstempel in ~/.ai-context/.last-selfcheck,
   frühestens alle 7 Tage erneut prüfen.
3. Integritäts-Guard: die in .source-path hinterlegte Remote-URL muss
   mit der beim allerersten Install gespeicherten übereinstimmen
   (Datei ~/.ai-context/.trusted-origin, einmalig bei install.sh
   geschrieben, danach nie überschrieben ohne explizite Nutzer-
   Bestätigung) — sonst Update-Anwendung verweigern und warnen.
4. Wenn Update verfügbar + vertraute Quelle: Backup von
   ~/.ai-context/_ai_context_template und ~/.ai-context/mcp/dist nach
   ~/.ai-context/.backups/<timestamp>/ (max. 3 behalten, älteste
   löschen), dann automatisch bash auto-update-all.sh ausführen (das
   ruft migrate.sh pro Projekt — bereits getestet in der letzten
   Session, NICHT neu erfinden).
5. ai-context-rollback.sh: stellt das jüngste Backup wieder her.
6. SessionStart-Hook (.claude/settings.json, Repo + Template):
   dritten/vierten Hook-Eintrag der ai-context-selfcheck.sh im
   Hintergrund/still aufruft (Ergebnis nur ausgeben wenn Update
   angewendet wurde oder fehlschlug — bei "alles aktuell" keine
   zusätzliche Zeile, Session-Start darf nicht langsamer/lauter werden).
CHECK: Simuliere ein "altes" ~/.ai-context (setze .last-selfcheck auf
vor 8 Tagen, VERSION künstlich auf 6.9), lass selfcheck laufen, prüfe
dass Backup angelegt wird und danach VERSION korrekt aktuell ist.
Prüfe dass ein zweiter Lauf innerhalb der 7 Tage nichts tut (Rate-Limit
greift). Prüfe dass eine gefälschte .trusted-origin die Anwendung
verweigert.

BAUSTEIN B — Self-Healing als Standard
1. Analysiere apply_mechanical_fixes() in ai-context-doctor.sh genau:
   was repariert es heute schon (vermutlich anchors, evtl. mapdrift)?
   Erweitere um: Orphan-Gotchas (status: orphan im Frische-Modell aus
   Phase 2/v7) nach konfigurierbarer Frist (Default 30 Tage seit
   `seen`) automatisch nach _gotchas_archive.md verschieben — NIE
   löschen, nur archivieren, mit Log-Zeile.
2. Entferne das Pro-Gate für die rein mechanischen Fixes (anchors,
   mapdrift, orphan-archivierung) — das Gate war ohnehin nur eine
   lokale Textdatei ohne echte Durchsetzung. CLAUDE-fixkind-Checks
   (inhaltliche Probleme) bleiben wie heute für Claude, kein Autofix.
3. Jede Auto-Reparatur schreibt eine Zeile in _temp_notes.md
   (Format an bestehende "Recent Changes"-Konvention anpassen — lies
   nach wie capture_from_diff.ts das heute macht).
4. SessionStart-Hook: ai-context-doctor.sh --session ruft die
   mechanischen Fixes jetzt automatisch mit auf (neuer interner Modus
   oder Erweiterung des bestehenden --session-Modus — deine
   Entscheidung nach Lektüre des bestehenden case "$MODE" in Blocks).
CHECK: Lege einen künstlich alten Gotcha an (seen: vor 40 Tagen,
@-Datei die es nicht gibt → status orphan), lass den Session-Hook
laufen, prüfe dass er nach _gotchas_archive.md wandert und eine
Log-Zeile entsteht, NICHT dass der Original-Text verloren geht.

BAUSTEIN C — CI + Testnetz
1. .github/workflows/ci.yml: shellcheck über alle scripts/*.sh und
   check_context_hash.sh (SC-Ausnahmen nur mit Kommentar-Begründung
   direkt im Skript, nicht pauschal im Workflow). npm ci + npm run
   build + node test/smoke.mjs im mcp/-Ordner.
2. Neuer Bash-Testharness _ai_context_template/scripts/ai-verify-self.sh
   (Name so wählen, dass er nicht mit dem bestehenden ai-verify.sh
   kollidiert, das etwas anderes tut — vorher prüfen!): baut ein
   Dummy-Next.js-Projekt in einem temp-Verzeichnis (Muster aus dieser
   Session: package.json mit next-Dependency, ein Component mit
   Button+Handler+fetch, eine API-Route), führt setup_ai_context.sh
   aus, prüft: drawers.yaml korrekt, _interaction_map.md hat den
   erwarteten Eintrag, ai-context-doctor.sh --check hat 0 FAIL,
   locate() (via mcp/dist/locate-cli.js) findet den Button. Exit-Code
   0/1 je nach Ergebnis, räumt das temp-Verzeichnis danach auf.
3. CI ruft dieses Skript nach dem MCP-Build auf.
CHECK: Workflow lokal simulierbar prüfen (act, falls installiert, sonst
manuell jeden Schritt einzeln ausführen und Exit-Codes verifizieren).

BAUSTEIN D — Onboarding + Reichweite
1. uninstall.sh: entfernt ~/.ai-context komplett, den Shell-Block aus
   .bashrc/.zshrc (gleiche awk-Marker-Logik wie install.sh's Entferner
   — wiederverwenden, nicht neu schreiben), und bietet an, aus jedem
   in ~/.ai-context/projects/ registrierten Projekt den Git-Hook
   post-commit zu entfernen (nur falls Inhalt exakt dem bekannten
   AI-Context-Hook entspricht — nie fremde Hooks überschreiben/löschen).
   Zeigt vor jeder Löschung genau was betroffen ist, fragt einmal global
   nach Bestätigung.
2. SessionStart-Auto-Bootstrap: neuer Hook-Eintrag, der bei fehlendem
   _ai_context/ UND vorhandenem ~/.ai-context (globale Installation
   existiert) einmalig eine Ja/Nein-Einladung ausgibt statt stumm
   nichts zu tun. Kein automatisches Einrichten ohne Zustimmung (anders
   als die reinen Wartungs-/Fix-Aufgaben aus A/B, die additiv und
   risikofrei sind — ein komplettes Projekt-Setup ist ein größerer
   Eingriff und braucht explizites Ja).
3. generate_drawers_yaml() in setup_ai_context.sh: Django/FastAPI/
   Express/Go/Rails-Sonderfälle ergänzen (analog zu detect_stack()s
   bestehender Fallunterscheidung, nicht neu erfinden — Globs und
   Keywords pro Stack sinnvoll anpassen, z.B. Django: api-Schublade →
   **/views.py, **/urls.py).
4. README: Abschnitt "Unterstützte Plattformen" ergänzen — macOS/Linux
   getestet, WSL ungetestet, natives Windows nicht unterstützt.
CHECK: uninstall.sh in einer Wegwerf-Testumgebung (nicht auf der
echten ~/.ai-context!) durchlaufen lassen und verifizieren, dass
nichts außerhalb des AI-Context-Bereichs angefasst wird. Dummy-Django-
Projekt durch setup_ai_context.sh laufen lassen, drawers.yaml auf
sinnvolle (nicht Next.js-generische) Globs prüfen.

WICHTIGE REGELN (gelten für alle vier Bausteine):
- Sicherheit vor Bequemlichkeit: JEDE automatische Aktion, die Dateien
  außerhalb von _ai_context/**, .claude/settings.json, hooks/**
  anfasst, ist verboten. Niemals git add/commit/push in einem
  Zielprojekt automatisch auslösen — das bleibt immer Nutzer-Handlung.
- Jede automatische Aktion muss sichtbar/nachvollziehbar sein (Log-
  Zeile, Hook-Output) — "leise im Hintergrund" ist für Reparaturen
  okay, für inhaltliche Änderungen nie.
- Bestehende, funktionierende Skripte (migrate.sh, auto-update-all.sh,
  ai-context-doctor.sh) sind das Fundament — erweitern, nicht ersetzen.
  Wenn du eine Funktion für redundant hältst, prüfe zweimal ob sie
  wirklich unbenutzt ist (siehe die deleted-dead-code-Lektion aus der
  vorigen Session), bevor du sie entfernst.
- Bei jeder Spezifikationslücke: die sicherste, am wenigsten
  überraschende Option wählen und die Entscheidung in
  _ai_context/decisions.md festhalten (ADR-Format, das existiert schon).
```
