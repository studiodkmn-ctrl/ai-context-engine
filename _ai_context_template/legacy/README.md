# legacy/

Erledigte Einmal-Werkzeuge. Bleiben erhalten (nicht gelöscht), werden aber
**nicht** mehr in neue Projekte kopiert (`setup_ai_context.sh` kopiert nur
`scripts/*.sh`).

| Datei | Warum hier |
|---|---|
| `ai-context-migrate-priorities.sh` | Einmalige Migration zu v5.2-Prioritäten — abgeschlossen. Kein aktiver Aufrufer. |

> `ai-context-drawer.sh` ist **nicht** hier: es ist Teil der laufenden
> Overflow-Automatik (post-commit-Hook + manuell) und bleibt in `scripts/`.

Bei Bedarf wiederherstellen:
`git mv _ai_context_template/legacy/<datei> _ai_context_template/scripts/`
