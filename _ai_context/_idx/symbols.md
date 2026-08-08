# Symbol Map — ai-context-engine
> Auto-generiert: 2026-08-08 19:38 | Neu generieren: `bash _ai_context/scripts/ai-symbol-map.sh`
> 12 Dateien · 85 Symbole · Direkt springen: Datei:Zeilennummer

## `context_manager_agent.py`
  ProjectMetadata                     L37    
  ContextManagerConfig                L56    
  ContextManagerAgent                 L68    
  __init__                            L91    
  run                                 L101   
  resync                              L151   
  _create_directory_structure         L201   
  _write_files                        L205     — Write all context files + JSON sidecar for each (v4: machine
  _quality_check                      L232     — Validates generated files aren't too long or placeholder-hea
  _find_stale_files                   L255     — Returns list of (relative_path, marker) for stale files.
  _get_git_hash                       L301     — Gets current git hash from the project directory.
  _sanitize                           L313   
  _sanitize_stack                     L330     — Sanitize all stack values before use in prompts.
  _call_haiku                         L342   
  _resync_file                        L355     — Asks Haiku to update a stale file based on its current conte
  _generate_quick_facts               L382     — _quick_facts.md — direct from metadata, 0 LLM tokens.
  _generate_sprint                    L444     — current_sprint.md — direct from metadata.
  _generate_index                     L506   
  _generate_tldrs                     L639     — Single Haiku call to generate TL;DRs for all context files.
  _generate_architecture              L690   
  _generate_decisions                 L711   
  _generate_components                L727   
  _generate_state                     L750   
  _generate_api                       L772   
  _generate_database                  L796   
  integrate_into_orchestrator         L826   
## `mcp/src/capture-cli.ts`
  main                                L11    
## `mcp/src/lib/locate.ts`
  tokens                              L25    
  raw                                 L26    
  loadSynonyms                        L31      — ------------------------------------------------------------
  expandQueryTokens                   L50    
  parseDrawers                        L69    
  globToRegExp                        L97    
  matchingDrawers                     L117   
  fileInDrawer                        L121   
  parseInteractionMap                 L134   
  scoreMapRow                         L159   
  parseRegistry                       L187   
  chunksFromMarkdownFallback          L246   
  extractChunkBody                    L270   
  escapeRe                            L283   
  symptomLine                         L287   
  extractAtFiles                      L293     — Plausible Dateipfade aus der `@ file1, file2, ...`-Zeile (si
  scoreChunk                          L299   
  freshnessNote                       L307   
  parseSymbols                        L322   
  parseInterfaces                     L358   
  parseInvariants                     L387   
  parseImpactGraph                    L417     — ------------------------------------------------------------
  locateQuery                         L447   
  boost                               L487     — gehört, werden nach oben priorisiert (stabiler Sort, daher R
  addFile                             L611   
## `mcp/src/lib/paths.ts`
  findProjectRoot                     L9     
  localContextDir                     L23      — Pfad zum projektlokalen `_ai_context`-Ordner.
  globalContextDir                    L28      — Globaler AI-Context-Ordner (`~/.ai-context`).
  crossProjectsDir                    L33      — Cross-Projekt-Speicher: `~/.ai-context/projects/<id>/`.
  crossProjectContextDirs             L38      — Liefert alle vorhandenen Cross-Projekt-Kontextordner (außer 
## `mcp/src/lib/projectId.ts`
  getProjectId                        L18    
  readGitOrigin                       L41    
## `mcp/src/lib/save.ts`
  contentHash                         L36    
  saveFact                            L45    
## `mcp/src/lib/search.ts`
  collectMarkdown                     L18      — Sammelt rekursiv alle Markdown-Dateien unterhalb von `dir`.
  splitBlocks                         L37      — Zerlegt Markdown in Blöcke (an Überschriften und Leerzeilen)
  flush                               L42    
  tokenize                            L67    
  scoreBlock                          L75    
  searchContext                       L98    
## `mcp/src/locate-cli.ts`
  main                                L16    
## `mcp/src/server.ts`
  main                                L15    
## `mcp/src/tools/capture_from_diff.ts`
  readDiff                            L63    
  tryGit                              L64    
  analyze                             L85      — Heuristiken über hinzugefügte (`+`) Diff-Zeilen.
  push                                L88    
  extractChangedFiles                 L138   
  loadImpactGraph                     L146   
  detectGaps                          L167     — Vergleicht geänderte Dateien gegen den Impact Graph und meld
  loadInvariants                      L207     — Lädt invariants.yaml aus dem _ai_context-Ordner. Kein Fehler
  flush                               L214   
  checkInvariants                     L247     — Prüft ob geänderte Dateien Invarianten berühren und gibt War
  readCommitIntent                    L279     — Liest den letzten Commit-Titel und speichert ihn als Intent 
  text                                L295   
## `mcp/src/tools/memory_search.ts`
  formatHits                          L48    
## `mcp/src/tools/session_context.ts`
  read                                L42    
  clip                                L51    
  text                                L55    
