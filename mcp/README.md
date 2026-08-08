# ai-context-mcp

Schlanke MCP-Schicht über dem `_ai_context`-System. Legt sich **über** das
bestehende System — ersetzt nichts. Prinzip: *erst Gedächtnis fragen, Dateien
nur lesen wenn nichts gefunden.*

## Die 4 Werkzeuge

| Werkzeug | Was es tut |
|---|---|
| `memory_search(query, limit?)` | Keyword-Suche über `_ai_context/**` — lokal **und** cross-projekt (`~/.ai-context/projects/*`). Nichts gefunden → leer, Agent liest normal. |
| `memory_save(content, type, priority?)` | Schreibt Fakt/Gotcha/Entscheidung in die typgerechte Markdown-Datei. Dedup über Content-Hash. |
| `session_context()` | Kompakter Projektkontext (`_SESSION.md`, Fallback: Index + Quick-Facts). |
| `capture_from_diff(apply?, range?)` | Liest git-diff, schlägt Erkenntnisse vor. `apply=true` schreibt sie (Dedup). |

`type` ∈ `gotcha · debug · security · decision · endpoint · auth · component · playbook · note`

## Bauen & Testen

```bash
npm install
npm run build
node test/smoke.mjs /pfad/zum/projekt   # End-to-end-Smoke-Test
```

## Anbindung an Claude Code

`.mcp.json` im Projekt (Template: `_ai_context_template/.mcp.json`):

```json
{ "mcpServers": { "ai-context": {
    "command": "node",
    "args": ["${HOME}/.ai-context/mcp/dist/server.js"] } } }
```

Der Server findet die Projektwurzel über `AI_CONTEXT_ROOT` oder durch
Aufwärtssuche nach `_ai_context`/`.git` ab dem cwd.

## Auto-Capture

Der `post-commit`-Hook ruft `dist/capture-cli.js --apply HEAD~1..HEAD` auf —
neue Endpoints, TODOs und Env-Vars landen automatisch im Gedächtnis. Bricht den
Commit nie ab.

## Projekt-Identität (W2)

Stabile ID aus git-Remote-`origin` (Fallback: absoluter Pfad), gecacht in
`_ai_context/.meta.json`. MCP-Server und Shell-Scripts teilen dieselbe ID.
