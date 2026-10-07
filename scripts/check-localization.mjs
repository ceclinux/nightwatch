#!/usr/bin/env node
// No dependencies: run with `node scripts/check-localization.mjs` before changing translations.
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const file = path.join(root, 'Sources/SkyCore/Resources/Localization/zh-Hans.json');
const source = fs.readFileSync(file, 'utf8');
const translations = JSON.parse(source);
const errors = [];
const seen = new Set();
for (const match of source.matchAll(/^\s*("(?:[^"\\]|\\.)*")\s*:/gm)) {
  const key = JSON.parse(match[1]);
  if (seen.has(key)) errors.push(`Duplicate translation: ${key}`);
  seen.add(key);
}
const numbered = /\{\d+\}/g;
const printf = /%(?:\d+\$)?[-+0 #]*(?:\d+)?(?:\.\d+)?(?:ll|l)?[@dfgsu]/g;
const tokens = (s, re) => JSON.stringify((s.match(re) ?? []).sort());
for (const [key, value] of Object.entries(translations)) {
  if (typeof value !== 'string' || !value.trim()) { errors.push(`Empty translation: ${key}`); continue; }
  if (tokens(key, numbered) !== tokens(value, numbered)) errors.push(`Numbered placeholders differ: ${key}`);
  if (!/\{\d+\}/.test(key) && tokens(key, printf) !== tokens(value, printf)) errors.push(`Printf arguments differ: ${key}`);
}

// Read Swift literals, including nested strings/parentheses inside interpolations. Unlike a regex over source,
// this also sees nested messages and skips comments and multiline strings. Bare resource names/paths are not keys.
function literal(s, start) {
  let i = start + 1, key = '', count = 0;
  while (i < s.length) {
    if (s[i] === '"') return {end: i + 1, key};
    if (s[i] === '\\' && s[i + 1] === '(') {
      let depth = 1;
      i += 2;
      while (depth && i < s.length) {
        if (s[i] === '"') i = literal(s, i).end;
        else { if (s[i] === '(') depth++; if (s[i] === ')') depth--; i++; }
      }
      key += `{${count++}}`;
    } else if (s[i] === '\\') { key += ({n: '\n', t: '\t', r: '\r'}[s[i + 1]] ?? s[i + 1]); i += 2; }
    else key += s[i++];
  }
  throw new Error('Unclosed Swift string');
}
function checkSwift(file) {
  const s = fs.readFileSync(file, 'utf8');
  for (let i = 0; i < s.length;) {
    if (s.startsWith('//', i)) { const end = s.indexOf('\n', i); i = end < 0 ? s.length : end; }
    else if (s.startsWith('/*', i)) { const end = s.indexOf('*/', i + 2); i = end < 0 ? s.length : end + 2; }
    else if (s.startsWith('"""', i)) { const end = s.indexOf('"""', i + 3); i = end < 0 ? s.length : end + 3; }
    else if (s[i] === '"') {
      const t = literal(s, i);
      if (/L10n\.(?:text|format)\(\s*$/.test(s.slice(Math.max(0, i - 40), i)) && !Object.hasOwn(translations, t.key)) {
        errors.push(`Missing translation in ${path.relative(root, file)}: ${t.key}`);
      }
      // Scan nested interpolation expressions too, without requiring bare literals to be localized.
      const contents = s.slice(i + 1, t.end - 1);
      for (const m of contents.matchAll(/L10n\.(?:text|format)\(\s*(?=")/g)) {
        const nested = literal(contents, m.index + m[0].length);
        if (!Object.hasOwn(translations, nested.key)) errors.push(`Missing nested translation: ${nested.key}`);
      }
      i = t.end;
    } else i++;
  }
}
function walk(dir) {
  for (const item of fs.readdirSync(dir, {withFileTypes: true})) {
    const file = path.join(dir, item.name);
    if (item.isDirectory()) walk(file);
    else if (file.endsWith('.swift')) checkSwift(file);
  }
}
for (const dir of ['Sources/Nightwatch', 'Sources/NightwatchUI', 'Sources/SkyCore', 'Widget/Sources']) walk(path.join(root, dir));
if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
else console.log(`Localization OK: ${Object.keys(translations).length} translations; placeholders and literal references checked.`);
