# ⚡ Quick Facts — ai-context-engine

## Identity
```
Project:  ai-context-engine
Stack:    Bash + Python 3 + TypeScript (MCP-Server, Node)
```

## 📍 Key File Paths + Impact-Radius

| Code-Datei | Zweck | Genutzt von (Kontext-Dateien) |
|---|---|---|
| `mcp/src/lib/locate.ts` | locate() — Routing über alle Indizes | architecture.md, decisions.md |
| `_ai_context/scripts/lib/ctx.py` | Geteilte Helfer (Tokens, Chunks, Manifest, Frische) | architecture.md |
| `_ai_context/knowledge.manifest.yaml` | Einzige Quelle: welche Datei ist Wissensdatei | decisions.md (ADR-006) |
| `hooks/post-commit` | Auto-Invalidierung, Trim, Auto-Capture | decisions.md, testing.md |
| `_ai_context/scripts/ai-context-doctor.sh` | Health-Checks des Kontextsystems | testing.md |
| `migrate.sh` / `setup_ai_context.sh` | Verteilung in Projekte | decisions.md |
