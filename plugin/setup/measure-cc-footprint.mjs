#!/usr/bin/env node
// Measure the Claude Code config context footprint for this repo.
// Reports bytes + token estimate (chars/3.7 heuristic) per always-on or
// on-demand config surface, with HTML comments excluded (they are stripped
// from markdown before reaching the model in some surfaces — reported both ways).
// Usage: node .claude/setup/measure-cc-footprint.mjs [--json <outfile>]
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const root = process.cwd();
const CHARS_PER_TOKEN = 3.7;

function measure(file) {
  try {
    const raw = fs.readFileSync(file, 'utf8');
    const noHtmlComments = raw.replace(/<!--[\s\S]*?-->/g, '');
    return {
      file: path.relative(root, file) || file,
      bytes: Buffer.byteLength(raw),
      tokensEst: Math.round(raw.length / CHARS_PER_TOKEN),
      tokensEstNoComments: Math.round(noHtmlComments.length / CHARS_PER_TOKEN),
    };
  } catch {
    return null;
  }
}

function glob(dir, suffix) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) return glob(p, suffix);
      return e.name.endsWith(suffix) ? [p] : [];
    });
  } catch {
    return [];
  }
}

const surfaces = {
  'always-on (CLAUDE.md + learning rule + memory index)': [
    path.join(root, 'CLAUDE.md'),
    path.join(root, '..', 'CLAUDE.md'),
    path.join(root, '.claude', 'rules', 'learning.md'),
  ].filter(fs.existsSync),
  'path-scoped rules (load on file match)': glob(path.join(root, '.claude', 'rules'), '.md')
    .filter((f) => !f.endsWith('learning.md')),
  'skills (description always; body on invoke)': glob(path.join(root, '.claude', 'skills'), 'SKILL.md'),
  'agents (description always; body on spawn)': glob(path.join(root, '.claude', 'agents'), '.md'),
  'commands (body on invoke)': glob(path.join(root, '.claude', 'commands'), '.md'),
  'docs (load on demand)': glob(path.join(root, '.claude', 'docs'), '.md'),
  'global user agents (~/.claude/agents; body on spawn)': glob(path.join(os.homedir(), '.claude', 'agents'), '.md'),
};

const report = {};
let grand = 0;
for (const [name, files] of Object.entries(surfaces)) {
  const rows = files.map(measure).filter(Boolean).sort((a, b) => b.tokensEst - a.tokensEst);
  const total = rows.reduce((s, r) => s + r.tokensEst, 0);
  report[name] = { totalTokensEst: total, files: rows };
  grand += total;
  console.log(`\n== ${name} — ~${total} tokens (${rows.length} files) ==`);
  for (const r of rows.slice(0, 15)) {
    console.log(`  ${String(r.tokensEst).padStart(6)} tok  ${String(r.bytes).padStart(7)} B  ${r.file}`);
  }
  if (rows.length > 15) console.log(`  … ${rows.length - 15} more`);
}
console.log(`\nGRAND TOTAL (all surfaces, est): ~${grand} tokens`);
console.log('Note: only the always-on surface + descriptions hit every prompt; the rest is on-demand.');

const jsonIdx = process.argv.indexOf('--json');
if (jsonIdx !== -1 && process.argv[jsonIdx + 1]) {
  fs.writeFileSync(process.argv[jsonIdx + 1], JSON.stringify({ generatedAt: new Date().toISOString(), grandTotalTokensEst: grand, surfaces: report }, null, 2));
  console.log(`JSON written to ${process.argv[jsonIdx + 1]}`);
}
