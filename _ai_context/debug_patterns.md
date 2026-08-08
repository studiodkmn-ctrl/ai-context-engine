# 🔍 Debug Patterns — ai-context-engine
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

```
ID: _template
P: 2
seen: [YYYY-MM-DD]
→ [Kurzbeschreibung]
? [Fehlermeldung / Symptom]
fix: [Lösung als Code]
@ [Dateien]
⇒ [Verweis auf verwandte Gotcha/Rule]
```

> REGELN: Vor Writeback IDs prüfen (--dedup). Überlauf: P3 → Archiv, P1 niemals löschen. Verweis (⇒) statt Inhalt kopieren.
> seen: optional, siehe _gotchas.md#legende — Frische-Status landet in registry.yaml.
