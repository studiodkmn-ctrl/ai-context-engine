# 🏛️ Architecture Decision Records (ADRs)
**Status:** ✅ Fresh · **Updated:** 2026-07-09 · **Invalidated by:** `package.json`, `requirements.txt` changes (new lib = potential new decision)

> Claude: Load this file for refactoring, new feature planning, or "why was X built this way?" questions.
> **Writeback:** Neue ADR sofort anlegen wenn Architekturentscheidung getroffen wird.
> ⇒ Wie/wann eine ADR schreiben + Template: `decisions_guide.md`
> ⇒ Ältere ADRs (002 Frische-Feld, 003 YAML-Parsing): `decisions_archive.md`

---

## Decisions

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

### ADR-006: knowledge.manifest.yaml als einzige Quelle der Wahrheit für Wissensdateien
**Date:** 2026-08-08 | **Status:** Accepted

**Context:** playbooks.md (v8.1) musste an 6 Stellen von Hand eingetragen
werden (locate.ts, ai-context-registry.sh, ai-context-doctor.sh,
hooks/post-commit, migrate.sh, CLAUDE.md). migrate.sh wurde dabei vergessen
und blieb unbemerkt, bis 9 Projekte bereits ohne die Datei liefen. Beim
Gegenlesen zeigte sich zusätzlich, dass die bestehenden Listen schon vorher
inkonsistent waren (architecture.md/decisions.md fehlten in locate.ts und
ai-context-doctor.sh, obwohl ai-context-registry.sh sie längst scannte).
**Decision:** `_ai_context/knowledge.manifest.yaml` (+ identische Kopie im
Template) listet jede Wissensdatei einmal mit path/type/markers/
max_entries/archive/seed. Ein neuer Parser `ctx.py::load_knowledge_manifest`
(minimaler zeilenbasierter Parser, kein PyYAML, gleicher Stil wie
`list_drawer_indexes`) wird von allen fünf Code-Stellen genutzt; migrate.sh
seedet `seed:true`-Dateien generisch statt Datei-für-Datei-Sonderfällen.
Jede Stelle behält einen hartcodierten Fallback, falls das Manifest fehlt
(alte/fremde Installation) — kein Totalausfall bei Downgrade.
**Consequences:**
  + Neue Wissensdatei = eine Manifest-Zeile statt sechs Code-Stellen
    (playbooks.md#add_knowledge_file zeigt den geschrumpften Prozess).
  + `ai-verify-self.sh` Check 7 beweist die Migrations-Parität automatisch
    (seed-Datei löschen → migrate.sh → muss wieder da sein) — die
    v8.1-Fehlerklasse kann strukturell nicht wiederkehren.
  + Behebt nebenbei die architecture.md/decisions.md-Lücke in locate.ts/
    ai-context-doctor.sh.
  - Ein zusätzlicher indirekter Layer (Manifest → Parser → Verhalten) statt
    direkt lesbarer hartcodierter Listen — Trade-off akzeptiert, weil die
    Alternative (Drift) real und teuer war.

---

## ❌ Rejected Alternatives
> So Claude (and you) don't fall into the same trap again.
> Bisher keine — Template: `decisions_guide.md`
