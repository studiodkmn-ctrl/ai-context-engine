import { z } from 'zod';
import { findProjectRoot } from '../lib/paths.js';
import { saveFact, FactType } from '../lib/save.js';
import * as path from 'node:path';

const TYPES: [FactType, ...FactType[]] = [
  'gotcha',
  'debug',
  'security',
  'decision',
  'endpoint',
  'auth',
  'component',
  'note',
];

export const memorySaveTool = {
  name: 'memory_save',
  config: {
    title: 'Erkenntnis ins Gedächtnis schreiben',
    description:
      'Hält einen Fakt / Gotcha / eine Entscheidung in der richtigen Markdown-Datei fest. ' +
      'Identischer Inhalt wird nie doppelt gespeichert (Dedup über Content-Hash). ' +
      'Nutze das für neue Erkenntnisse, die der nächste Agent kennen sollte.',
    inputSchema: {
      content: z.string().min(3).describe('Der Fakt — kurz, eine Aussage.'),
      type: z
        .enum(TYPES)
        .describe(
          'gotcha | debug | security | decision | endpoint | auth | component | note',
        ),
      priority: z
        .union([z.literal(1), z.literal(2), z.literal(3)])
        .optional()
        .describe('Nur für gotcha/debug/security: 1=kritisch, 2=wichtig (Default), 3=nice'),
    },
  },
  async handler({
    content,
    type,
    priority,
  }: {
    content: string;
    type: FactType;
    priority?: 1 | 2 | 3;
  }) {
    const root = findProjectRoot();
    const res = saveFact(root, type, content, priority ?? 2);
    const rel = path.relative(root, res.file);
    const msg = res.saved
      ? `Gespeichert in ${rel}.`
      : res.reason === 'duplicate'
        ? `Schon vorhanden in ${rel} — nichts doppelt geschrieben.`
        : `Nicht gespeichert (${res.reason}).`;
    return { content: [{ type: 'text' as const, text: msg }] };
  },
};
