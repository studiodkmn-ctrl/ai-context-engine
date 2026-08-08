# 📦 gotchas Archiv — automatisch archivierte Einträge
> Orphan-Einträge (Code-Datei existiert nicht mehr, seen älter als 30 Tage).
> Verschoben von ai-context-doctor.sh — Inhalt unverändert, nichts gelöscht.

## Archiviert

<!-- archiviert 2026-08-06: orphan seit >=30d -->
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
