# 🔍 Debug Patterns — /Users/adnandikmen/Desktop/test-kontext
> **Max 15. Laden nur bei Debugging. Code-Format.**
> Aktualisiert: 2026-04-14

## Aktiv

<!-- #hydration_mismatch -->
```
ID: hydration_mismatch
P: 2
→ Server/Client HTML unterschiedlich
? "Hydration failed" / "Text content mismatch"
fix: 'use client' Direktive + useEffect für browser-only Code
  ✗ {typeof window !== 'undefined' && <Component />}
  ✓ const [mounted, setMounted] = useState(false)
    useEffect(() => setMounted(true), [])
    if (!mounted) return null
@ alle Client-Components mit Browser-APIs
```
<!-- /hydration_mismatch -->

<!-- #prisma_connection -->
```
ID: prisma_connection
P: 2
→ DB-Verbindung schlägt fehl
? "Can't reach database" / P1001 Error
fix:
  1. DATABASE_URL in .env prüfen
  2. npx prisma generate
  3. npx prisma db push
@ prisma/schema.prisma, .env
⇒ _gotchas.md#prisma_singleton
```
<!-- /prisma_connection -->

```
ID: _template
P: 2
→ [Kurzbeschreibung]
? [Fehlermeldung / Symptom]
fix: [Lösung als Code]
@ [Dateien]
⇒ [Verweis auf verwandte Gotcha/Rule]
```

> REGELN: Vor Writeback IDs prüfen (--dedup). Überlauf: P3 → Archiv, P1 niemals löschen. Verweis (⇒) statt Inhalt kopieren.
