#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { memorySearchTool } from './tools/memory_search.js';
import { memorySaveTool } from './tools/memory_save.js';
import { sessionContextTool } from './tools/session_context.js';
import { captureFromDiffTool } from './tools/capture_from_diff.js';

/**
 * AI Context MCP — schlanke Schicht über dem bestehenden _ai_context-System.
 * Genau 4 Werkzeuge, stdio. Ersetzt nichts, ergänzt nur:
 * erst Gedächtnis fragen, Dateien nur lesen wenn nichts gefunden.
 */
async function main(): Promise<void> {
  const server = new McpServer({
    name: 'ai-context',
    version: '0.1.0',
  });

  for (const t of [memorySearchTool, memorySaveTool, sessionContextTool, captureFromDiffTool]) {
    // Cast nötig, weil die Tools je eigene Zod-Shapes haben.
    server.registerTool(t.name, t.config as any, t.handler as any);
  }

  const transport = new StdioServerTransport();
  await server.connect(transport);
  // stderr ist erlaubt (stdout ist dem Protokoll vorbehalten)
  process.stderr.write('ai-context MCP läuft (stdio)\n');
}

main().catch(err => {
  process.stderr.write(`ai-context MCP Fehler: ${err?.stack || err}\n`);
  process.exit(1);
});
