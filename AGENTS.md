<!-- ai-context:managed:start -->
## AI Context Engine — Navigation

Vor Datei-Suche/-Erstellung bei Bug-Beschreibungen, "wo ist X"-Fragen oder
Code-Aufgaben zuerst ausfuehren:

    bash _ai_context/scripts/ai-symptom-router.sh "<beschreibung>"

Routet ueber Interaction Map, Symbol Map, Gotchas/Debug-Patterns (mit
Frische-Status), Invarianten und Impact-Graph zu den wahrscheinlichsten
Dateien — statt die Codebase blind zu durchsuchen. Kein Treffer? Normal
grep/lesen.

Nach Aufgaben-Abschluss neue Erkenntnisse eintragen — welche Datei
zustaendig ist, steht in `_ai_context/knowledge.manifest.yaml` (Format-
Beispiele: `_ai_context/_gotchas.md`).

Unterstuetzt dein Tool MCP (z.B. Cursor)? `.mcp.json` im Projekt-Root
registriert den `ai-context`-Server mit den Werkzeugen `locate`,
`memory_search`, `memory_save`, `session_context`, `capture_from_diff` —
dann direkt diese nutzen statt der Bash-Route.
<!-- ai-context:managed:end -->
