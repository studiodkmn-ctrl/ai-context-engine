import { z } from 'zod';
import { findProjectRoot, localContextDir, crossProjectContextDirs } from '../lib/paths.js';
import { getProjectId } from '../lib/projectId.js';
import { searchContext, SearchHit } from '../lib/search.js';
import * as path from 'node:path';

export const memorySearchTool = {
  name: 'memory_search',
  config: {
    title: 'Gedächtnis durchsuchen',
    description:
      'Findet relevante Schnipsel aus dem AI-Context-Gedächtnis (_ai_context/**) — gezielt, ' +
      'nicht alles. Sucht auch in anderen Projekten (~/.ai-context/projects/*). ' +
      'IMMER zuerst hier fragen, bevor du Dateien liest. Nichts gefunden → normal Dateien lesen.',
    inputSchema: {
      query: z.string().describe('Suchbegriffe, z. B. "typescript parser auth token"'),
      limit: z.number().int().min(1).max(20).optional().describe('Max. Treffer (Default 6)'),
    },
  },
  async handler({ query, limit }: { query: string; limit?: number }) {
    const root = findProjectRoot();
    const id = getProjectId(root);
    const sources = [
      { dir: localContextDir(root), kind: 'local' as const },
      ...crossProjectContextDirs(id).map(dir => ({
        dir,
        kind: 'cross' as const,
        project: path.basename(path.dirname(dir)),
      })),
    ];

    const hits = searchContext(query, sources, limit ?? 6);
    if (hits.length === 0) {
      return {
        content: [
          {
            type: 'text' as const,
            text: `Kein Treffer für "${query}" im Gedächtnis. Lies die Dateien normal.`,
          },
        ],
      };
    }

    return { content: [{ type: 'text' as const, text: formatHits(query, hits) }] };
  },
};

function formatHits(query: string, hits: SearchHit[]): string {
  const lines = [`${hits.length} Treffer für "${query}":\n`];
  for (const h of hits) {
    const where = h.source === 'cross' ? ` [aus Projekt ${h.project}]` : '';
    lines.push(`### ${h.relFile}:${h.line}${where}  (Score ${h.score})`);
    lines.push(h.snippet);
    lines.push('');
  }
  return lines.join('\n');
}
