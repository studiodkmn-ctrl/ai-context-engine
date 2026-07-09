# Interface Snapshot — ai-context-v6.5
> Auto-generiert: 2026-07-09 22:04 | Neu generieren: `bash _ai_context/scripts/ai-interface-snapshot.sh`
> 16 Interfaces/Types — Format: `Name  Datei:Zeile  Felder`

ProjectMetadata                 context_manager_agent.py:37          project_name, project_description, stack, folder_structure, generated_files, architecture_decisions, api_routes, db_models
ContextManagerConfig            context_manager_agent.py:56          model, max_tokens, context_dir_name, today, max_file_lines
Drawer                          mcp/src/lib/locate.ts:62             id, index, globs, keywords
MapRow                          mcp/src/lib/locate.ts:126            elem, loc, handler, store, endpoint, elem, loc, handler
RegistryChunk                   mcp/src/lib/locate.ts:176            id, type, priority, file, tags, seen, code_touched, status
SymbolHit                       mcp/src/lib/locate.ts:268            name, file, line, args, score, name, file, line
InterfaceHit                    mcp/src/lib/locate.ts:304            name, file, line, fields, score, id, level, rule
Invariant                       mcp/src/lib/locate.ts:334            id, level, rule, scope
LocateResult                    mcp/src/lib/locate.ts:394            markdown, hitCount, filesToRead
Meta                            mcp/src/lib/projectId.ts:7           projectId, origin, createdAt, cwd, encoding, timeout
SaveResult                      mcp/src/lib/save.ts:16               saved, file, reason?, gotcha, debug, security, decision, endpoint
SearchHit                       mcp/src/lib/search.ts:4              file, relFile, line, snippet, score, source, project?
Source                          mcp/src/lib/search.ts:87             dir, kind, project?, relFile, line, snippet, source, project
Suggestion                      mcp/src/tools/capture_from_diff.ts:9  type, content, name, config, title, description, inputSchema, apply
InvariantDep                    mcp/src/tools/capture_from_diff.ts:193  type, ref, id, level, rule, scope, depends
Invariant                       mcp/src/tools/capture_from_diff.ts:198  id, level, rule, scope, depends
