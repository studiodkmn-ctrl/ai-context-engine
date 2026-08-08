# Interface Snapshot — ai-context-engine
> Auto-generiert: 2026-08-08 22:28 | Neu generieren: `bash _ai_context/scripts/ai-interface-snapshot.sh`
> 17 Interfaces/Types — Format: `Name  Datei:Zeile  Felder`

ProjectMetadata                 context_manager_agent.py:37          project_name, project_description, stack, folder_structure, generated_files, architecture_decisions, api_routes, db_models
ContextManagerConfig            context_manager_agent.py:56          model, max_tokens, context_dir_name, today, max_file_lines
Drawer                          mcp/src/lib/locate.ts:63             id, index, globs, keywords
MapRow                          mcp/src/lib/locate.ts:127            elem, loc, handler, store, endpoint, elem, loc, handler
RegistryChunk                   mcp/src/lib/locate.ts:177            id, type, priority, file, tags, seen, code_touched, status
ManifestEntry                   mcp/src/lib/locate.ts:254            path, type
SymbolHit                       mcp/src/lib/locate.ts:359            name, file, line, args, score, name, file, line
InterfaceHit                    mcp/src/lib/locate.ts:395            name, file, line, fields, score, id, level, rule
Invariant                       mcp/src/lib/locate.ts:425            id, level, rule, scope
LocateResult                    mcp/src/lib/locate.ts:485            markdown, hitCount, filesToRead
Meta                            mcp/src/lib/projectId.ts:7           projectId, origin, createdAt, cwd, encoding, timeout
SaveResult                      mcp/src/lib/save.ts:17               saved, file, reason?, gotcha, debug, security, decision, endpoint
SearchHit                       mcp/src/lib/search.ts:4              file, relFile, line, snippet, score, source, project?
Source                          mcp/src/lib/search.ts:87             dir, kind, project?, relFile, line, snippet, source, project
Suggestion                      mcp/src/tools/capture_from_diff.ts:9  type, content, name, config, title, description, inputSchema, apply
InvariantDep                    mcp/src/tools/capture_from_diff.ts:193  type, ref, id, level, rule, scope, depends
Invariant                       mcp/src/tools/capture_from_diff.ts:198  id, level, rule, scope, depends
