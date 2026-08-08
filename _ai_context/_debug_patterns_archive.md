# 📦 debug_patterns Archiv — automatisch archivierte Einträge
> Orphan-Einträge (Code-Datei existiert nicht mehr, seen älter als 30 Tage).
> Verschoben von ai-context-doctor.sh — Inhalt unverändert, nichts gelöscht.

## Archiviert

<!-- archiviert 2026-08-06: orphan seit >=30d -->
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
