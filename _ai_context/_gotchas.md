# ⚠️ Gotchas — ai-context-engine
> **Max 15. Code-Format. Laden bei jedem Coding-Task.**
> Aktualisiert: 2026-08-06
> P: 1=kritisch (nie löschen) | 2=wichtig (default) | 3=nice-to-know (zuerst archiviert)

## Aktiv

<!-- #silent_noop_needs_effect_test -->
```
ID: silent_noop_needs_effect_test
P: 1
seen: 2026-08-06
→ Hook/Skript kann fehlerfrei durchlaufen und trotzdem nichts bewirken
  (falsches Zielmuster/Pfad) — kein Fehler beweist keine Wirkung
✗ Test prüft nur Exit-Code
✓ Test prüft echte Wirkung danach (ai-verify-self.sh Check 12)
? Mechanismus gilt seit Versionen als ok, ändert aber nie etwas
  (Beispiel: Auto-Invalidierung war seit v5 tot, fix 084fcd4)
@ hooks/post-commit, ai-verify-self.sh
```
<!-- /silent_noop_needs_effect_test -->

<!-- #prisma_singleton -->
```
ID: prisma_singleton
P: 2
→ Hot-Reload erzeugt N Prisma-Instanzen → Pool voll
✗ new PrismaClient()
✓ import { prisma } from "@/lib/prisma"
@ alle DB-Zugriffe
```
<!-- /prisma_singleton -->

```
ID: _template
P: 2
seen: [YYYY-MM-DD]
→ [Kurzbeschreibung]
✗ [was falsch ist]
✓ [was richtig ist]
? [Symptom]
@ [betroffene Dateien]
```

## Legende
```
→ Was passiert  ✗ FALSCH  ✓ RICHTIG  ? Symptom  @ Dateien  ⇒ Verweis
P: 1=kritisch | 2=wichtig (default) | 3=nice-to-know
seen: optional — Datum, an dem der Eintrag zuletzt bestätigt wurde.
      Fehlt die Zeile, pflegt ai-context-registry.sh --scan sie in
      registry.yaml (nicht hier in der .md). status in registry.yaml:
      fresh (seen ≥ letzte Code-Änderung der @-Dateien) | check (Code
      neuer als seen — Eintrag ggf. veraltet) | orphan (@-Dateien weg).
```

> REGELN: snake_case ID ≤30 chars. Vor Writeback IDs prüfen (--dedup). Überlauf: P3 → _gotchas_archive.md, P1 niemals löschen.
