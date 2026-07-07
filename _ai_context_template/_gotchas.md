# ⚠️ Gotchas — [PROJECT_NAME]
> **Max 15. Code-Format. Laden bei jedem Coding-Task.**
> Aktualisiert: [DATE]
> P: 1=kritisch (nie löschen) | 2=wichtig (default) | 3=nice-to-know (zuerst archiviert)

## Aktiv

<!-- #auth_version -->
```
ID: auth_version
P: 2
→ NextAuth v5 ≠ v4
✗ getServerSession()          ← v4, veraltet
✓ auth() from "next-auth"     ← v5, korrekt
? session.user undefined → prüfe auth callback signature
@ src/lib/auth.ts, alle API routes
```
<!-- /auth_version -->

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
