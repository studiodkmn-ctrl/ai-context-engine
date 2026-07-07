import { z } from 'zod';
import { findProjectRoot } from '../lib/paths.js';
import { locateQuery } from '../lib/locate.js';

export const locateTool = {
  name: 'locate',
  config: {
    title: 'Code-Stelle finden',
    description:
      'Findet Code-Stelle/Ursache für eine Frage oder Bug-Beschreibung in 1 Lookup — ' +
      'fächert über Interaction Map, Symbol Map, Interfaces, Gotchas/Debug-Patterns ' +
      '(mit Frische-Status), Invarianten und Impact-Graph. IMMER zuerst aufrufen, ' +
      'bevor Dateien gelesen oder gegrept werden. Kein Treffer → normal grep/Read.',
    inputSchema: {
      query: z.string().describe('Bug-Beschreibung oder Suchbegriffe, z. B. "login button reagiert nicht"'),
    },
  },
  async handler({ query }: { query: string }) {
    const root = findProjectRoot();
    const result = await locateQuery(query, root);
    return { content: [{ type: 'text' as const, text: result.markdown }] };
  },
};
