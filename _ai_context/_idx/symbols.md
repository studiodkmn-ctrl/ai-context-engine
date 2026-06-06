# Symbol Map — ai-context-v6.5
> Auto-generiert: 2026-06-06 05:34 | Neu generieren: `bash _ai_context/scripts/ai-symbol-map.sh`
> 10 Dateien · 59 Symbole · Direkt springen: Datei:Zeilennummer

## `context_manager_agent.py`
  ProjectMetadata                     L37    
  ContextManagerConfig                L56    
  ContextManagerAgent                 L68    
  __init__                            L91      (self, project_output_dir: str, config: Optional[ContextManagerConfig]
  run                                 L101     (self, project_metadata: ProjectMetadata)
  resync                              L151     (self, project_output_dir: Optional[str] = None)
  _create_directory_structure         L201     (self)
  _write_files                        L205     (self, results: dict)  — Write all context files + JSON sidecar for each (v4: machine
  _quality_check                      L232     (self)  — Validates generated files aren't too long or placeholder-hea
  _find_stale_files                   L255     (self)  — Returns list of (relative_path, marker) for stale files.
  _get_git_hash                       L301     (self)  — Gets current git hash from the project directory.
  _sanitize                           L313     (self, text: str, max_len: int = 500)
  _sanitize_stack                     L330     (self, stack: dict)  — Sanitize all stack values before use in prompts.
  _call_haiku                         L342     (self, system_prompt: str, user_prompt: str)
  _resync_file                        L355     (self, relative_path: str, existing_content: str)  — Asks Haiku to update a stale file based on its current conte
  _generate_quick_facts               L382     (self, meta: ProjectMetadata)  — _quick_facts.md — direct from metadata, 0 LLM tokens.
  _generate_sprint                    L444     (self, meta: ProjectMetadata)  — current_sprint.md — direct from metadata.
  _generate_index                     L506     (self, meta: ProjectMetadata, generated_contents: dict)
  _generate_tldrs                     L639     (self, file_summaries: dict)  — Single Haiku call to generate TL;DRs for all context files.
  _generate_architecture              L690     (self, meta: ProjectMetadata)
  _generate_decisions                 L711     (self, meta: ProjectMetadata)
  _generate_components                L727     (self, meta: ProjectMetadata)
  _generate_state                     L750     (self, meta: ProjectMetadata)
  _generate_api                       L772     (self, meta: ProjectMetadata)
  _generate_database                  L796     (self, meta: ProjectMetadata)
  integrate_into_orchestrator         L826     (project_output_dir: str, orchestrator_result: dict)
## `mcp/src/capture-cli.ts`
  main                                L11      (): Promise<void>
    → used in: mcp/src/capture-cli.ts
## `mcp/src/lib/paths.ts`
  findProjectRoot                     L9       (start?: string): string
    → used in: mcp/src/tools/capture_from_diff.ts · mcp/src/tools/memory_save.ts · mcp/src/tools/memory_search.ts · mcp/src/tools/session_context.ts
  localContextDir                     L23      (root = findProjectRoot()  — Pfad zum projektlokalen `_ai_context`-Ordner.
    → used in: mcp/src/lib/projectId.ts · mcp/src/lib/save.ts · mcp/src/tools/capture_from_diff.ts · mcp/src/tools/memory_search.ts · mcp/src/tools/session_context.ts
  globalContextDir                    L28      (): string  — Globaler AI-Context-Ordner (`~/.ai-context`).
  crossProjectsDir                    L33      (): string  — Cross-Projekt-Speicher: `~/.ai-context/projects/<id>/`.
  crossProjectContextDirs             L38      (excludeId?: string): string[]  — Liefert alle vorhandenen Cross-Projekt-Kontextordner (außer 
    → used in: mcp/src/tools/memory_search.ts
## `mcp/src/lib/projectId.ts`
  getProjectId                        L18      (root: string): string
    → used in: mcp/src/tools/memory_search.ts
  readGitOrigin                       L41      (root: string): string | null
## `mcp/src/lib/save.ts`
  contentHash                         L34      (s: string): string
  saveFact                            L43    
    → used in: mcp/src/tools/capture_from_diff.ts · mcp/src/tools/memory_save.ts
## `mcp/src/lib/search.ts`
  collectMarkdown                     L18      (dir: string, acc: string[] = []): string[]  — Sammelt rekursiv alle Markdown-Dateien unterhalb von `dir`.
  splitBlocks                         L37      (content: string):   — Zerlegt Markdown in Blöcke (an Überschriften und Leerzeilen)
  flush                               L42      ()
    → used in: mcp/src/lib/search.ts
  tokenize                            L67      (q: string): string[]
  scoreBlock                          L75      (textLower: string, terms: string[]): number
  searchContext                       L98      (query: string, sources: Source[], limit = 6): SearchHit[]
    → used in: mcp/src/tools/memory_search.ts
## `mcp/src/server.ts`
  main                                L14      (): Promise<void>
    → used in: mcp/src/capture-cli.ts
## `mcp/src/tools/capture_from_diff.ts`
  readDiff                            L63      (root: string, range?: string): string | null
  tryGit                              L64      (args: string[]): string | null =>
  analyze                             L85      (diff: string): Suggestion[]  — Heuristiken über hinzugefügte (`+`) Diff-Zeilen.
  push                                L88      (type: FactType, content: string)
    → used in: mcp/src/lib/paths.ts · mcp/src/lib/search.ts · mcp/src/tools/memory_search.ts · mcp/src/tools/session_context.ts
  extractChangedFiles                 L135     (diff: string): Set<string>
  loadImpactGraph                     L143     (root: string): Map<string, string[]>
  detectGaps                          L164     (diff: string, root: string): Suggestion[]  — Vergleicht geänderte Dateien gegen den Impact Graph und meld
  loadInvariants                      L204     (root: string): Invariant[]  — Lädt invariants.yaml aus dem _ai_context-Ordner. Kein Fehler
  flush                               L211     ()
    → used in: mcp/src/lib/search.ts
  checkInvariants                     L244     (diff: string, root: string): Suggestion[]  — Prüft ob geänderte Dateien Invarianten berühren und gibt War
  readCommitIntent                    L276     (root: string): Suggestion | null  — Liest den letzten Commit-Titel und speichert ihn als Intent 
  text                                L292     (t: string)
    → used in: context_manager_agent.py · mcp/src/lib/search.ts · mcp/src/tools/capture_from_diff.ts
## `mcp/src/tools/memory_search.ts`
  formatHits                          L48      (query: string, hits: SearchHit[]): string
## `mcp/src/tools/session_context.ts`
  read                                L42      (file: string): string | null
  clip                                L51      (s: string): string
  text                                L55      (t: string)
    → used in: context_manager_agent.py · mcp/src/lib/search.ts · mcp/src/tools/capture_from_diff.ts
