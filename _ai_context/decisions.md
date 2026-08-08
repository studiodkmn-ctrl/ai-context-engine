# 🏛️ Architecture Decision Records (ADRs)
**Status:** ✅ Fresh · **Updated:** 2026-07-09 · **Invalidated by:** `package.json`, `requirements.txt` changes (new lib = potential new decision)

> Claude: Load this file for refactoring, new feature planning, or "why was X built this way?" questions.
> **Writeback:** Neue ADR sofort anlegen wenn Architekturentscheidung getroffen wird.
> ⇒ Wie/wann eine ADR schreiben + Template: `decisions_guide.md`
> ⇒ Ältere ADRs (002–005): `decisions_archive.md`

---

## Decisions

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

### ADR-007: semantischer locate()-Fallback über die bestehende Ollama-Infrastruktur
**Date:** 2026-08-09 | **Status:** Accepted

**Context:** `locate()` findet bei falschem Vokabular nichts ("Anmeldung
kaputt" statt "login"). Die Embedding-Infrastruktur (`ai-rag-cache.sh`,
SQLite-Query-Cache, `nomic-embed-text`) existierte bereits vollständig,
war aber nie mit `locate()` verbunden.
**Decision:** `locate.ts` ruft `ai-rag-cache.sh --find` per `execFileSync`
NUR wenn Keyword-Matching nichts fand (`!anyHit`) UND
`~/.ai-context/edition == "pro"` — fail-open bei jedem Fehler (Timeout,
Ollama down, Simple-Edition). Beim Bauen fiel auf, dass `--find` zwei
Tabellenformate hat: `[OLLAMA]` (frischer Vergleich, mit `sim:%`) und
`[CACHE-HIT]` (aus dem Query-Cache, OHNE `sim:%`) — ein Parser, der nur
`[OLLAMA]` erkennt, verwirft wiederholte Anfragen (dem Kernzweck des
Caches) still. Beide Formate werden jetzt geparst, Cache-Treffer als
"gecacht" statt Prozentzahl markiert.
**Consequences:**
  + Simple-Edition-Nutzer bemerken keinen Unterschied (Guard greift vorher,
    kein Ollama-Aufruf).
  + Kein neuer State, keine neue Datei — reine Verdrahtung Bestehendem.
  - Embedding-Qualität auf diesem kleinen, kurzen Gotcha-Korpus ist
    mittelmäßig (beobachtete Similarity-Werte 56-63% für Treffer und
    Nicht-Treffer ähnlich nah beieinander) — Fallback hilft bei
    Vokabular-Mismatch, ersetzt aber keine echte Relevanz-Sortierung.

---

<!-- #demo_content -->
### ADR-008: Demo-Inhalte sichtbar machen statt automatisch löschen
**Date:** 2026-08-09 | **Status:** Accepted

**Context:** Die ersten echten Benchmark-Zahlen (BENCHMARKS.md) zeigten,
dass das System bei Vollanalyse-Aufgaben Tokens KOSTET statt spart. Eine
Ursache war messbar: das Engine-Repo beschrieb sich selbst als
`Project: test, Stack: Next.js + Prisma`, 7 von 10 Wissens-Chunks waren
unveränderte Demo-Beispiele aus dem Template, und die komplette
Domain-Ebene (backend/auth.md, frontend/routing.md, architecture.md)
beschrieb eine fiktive Next.js-App. locate() matchte damit gegen Fiktion —
der v9-b-Prompt-Router injizierte deshalb bei generischen Prompts
irrelevante Gotchas. `setup_ai_context.sh` verteilt diese Demo-Inhalte an
JEDES neue Projekt, und nichts erinnerte je daran, sie zu ersetzen.
**Decision:** (a) Engine-Repo bereinigt (Demo-Chunks entfernt, echte
Identität, Domain-Dateien ehrlich als "nicht zutreffend" markiert statt
Fiktion). (b) Neuer Doctor-Check `demo_content` mit drei Teilen:
chunk-identisch zum Template, Datei besteht nur aus Vorlagen-Hinweisen
(≥3 `[z.B. ...]`), und `_quick_facts.md`-Projektname ≠ Verzeichnisname.
Ergebnis ist bewusst `WARN`/`CLAUDE`, nie `AUTO`: Demo-Regeln können in
echten Next.js-Projekten zufällig zutreffen — automatisches Löschen von
Wissensdateien wäre schwer umkehrbar und manchmal falsch.
**Consequences:**
  + Der Zustand kann in keinem Projekt mehr unbemerkt bleiben; die 8
    Nutzerprojekte WARNen nach dem Rollout erwartungsgemäß (gewollt).
  + Vorlagen-Hinweis-Erkennung fängt auch ganze Dateien ohne Anker, die
    Teil 1 (Chunk-Vergleich) prinzipiell nicht sehen kann.
  - Der Check kann bei Projekten, deren Stack zufällig zum Template passt,
    einen legitim übernommenen Chunk melden — akzeptiert, weil WARN
    (nicht FAIL) und weil die Alternative unsichtbare Fiktion ist.
<!-- /demo_content -->

---

## ❌ Rejected Alternatives
> So Claude (and you) don't fall into the same trap again.
> Bisher keine — Template: `decisions_guide.md`
