#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(here, '..', '..');
const srcDir = path.join(projectRoot, 'docs');
const destDir = path.join(projectRoot, 'site-next', 'src', 'content', 'docs');

const NON_PYTHON_LANGS = ['csharp', 'rust', 'java', 'go', 'cpp', 'typescript'];

// Stale Python marker names → current names
const MARKER_RENAMES = {
  deposit_guard: 'deposit_funds_guard',
  deposit_validate: 'deposit_funds_validate',
  deposit_compute: 'deposit_funds_compute',
};

// Pre-defined span wrappers already added in source
const SPAN_WRAPPERS = {
  'deposit_funds_guard→deposit_funds_compute': 'deposit_funds',
  'deposit_guard→deposit_compute': 'deposit_funds',
};

function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    const st = fs.statSync(full);
    if (st.isDirectory()) walk(full, out);
    else if (name.endsWith('.md') || name.endsWith('.mdx')) out.push(full);
  }
  return out;
}

function transform(src, relPath) {
  let s = src;

  // Drop Docusaurus theme imports
  s = s.replace(/^import\s+Tabs\s+from\s+['"]@theme\/Tabs['"];?\s*\n/m, '');
  s = s.replace(/^import\s+TabItem\s+from\s+['"]@theme\/TabItem['"];?\s*\n/m, '');

  // If MDX has Tabs usage, add Starlight import after frontmatter
  if (/<Tabs[\s>]/.test(s) && !/@astrojs\/starlight\/components/.test(s)) {
    const importLine = "import { Tabs, TabItem } from '@astrojs/starlight/components';\n\n";
    if (s.startsWith('---')) {
      const fmEnd = s.indexOf('\n---', 4) + 4;
      s = s.slice(0, fmEnd) + '\n\n' + importLine + s.slice(fmEnd + 1);
    } else {
      s = importLine + s;
    }
  }

  // Split frontmatter (if any) from body
  let fmBody = '';
  let body = s;
  const fmMatch = s.match(/^---\n([\s\S]*?)\n---\n?/);
  if (fmMatch) {
    fmBody = fmMatch[1];
    body = s.slice(fmMatch[0].length);
  }
  let fmTitle = null;
  let fmDesc = null;
  for (const line of fmBody.split('\n')) {
    const tm = line.match(/^title:\s*(.+)$/);
    const dm = line.match(/^description:\s*(.+)$/);
    if (tm) fmTitle = tm[1].trim();
    else if (dm) fmDesc = dm[1].trim();
  }
  if (!fmTitle) {
    const h1 = body.match(/^#\s+(.+?)\s*$/m);
    if (h1) {
      fmTitle = h1[1].trim();
      body = body.replace(/^#\s+.+?\s*$\n?/m, '');
    }
  }
  // YAML-quote title if it contains special chars
  const quoteIfNeeded = (v) => /[:#'"`&*!|>%@]/.test(v) ? `"${v.replace(/"/g, '\\"')}"` : v;
  const fmLines = [`title: ${quoteIfNeeded(fmTitle ?? 'Untitled')}`];
  if (fmDesc) fmLines.push(`description: ${quoteIfNeeded(fmDesc)}`);
  s = '---\n' + fmLines.join('\n') + '\n---\n' + body.replace(/^\n+/, '');

  // Strip non-Python TabItems whole (Docusaurus value= attr)
  for (const lang of NON_PYTHON_LANGS) {
    const re = new RegExp(
      `<TabItem\\s+value=["']${lang}["'][^>]*>[\\s\\S]*?</TabItem>\\s*`,
      'g'
    );
    s = s.replace(re, '');
  }

  // Also strip non-Python TabItems where attr is label= (no value=)
  for (const lang of ['C#', 'Rust', 'Java', 'Go', 'C\\+\\+', 'TypeScript']) {
    const re = new RegExp(
      `<TabItem\\s+label=["']${lang}["'][^>]*>[\\s\\S]*?</TabItem>\\s*`,
      'g'
    );
    s = s.replace(re, '');
  }

  // Normalize remaining TabItem attrs: remove value= and default; keep label
  s = s.replace(/<TabItem([^>]*)>/g, (m, attrs) => {
    let a = attrs
      .replace(/\s+value=["'][^"']*["']/g, '')
      .replace(/\s+default\b/g, '')
      .replace(/\s+groupId=["'][^"']*["']/g, '');
    return `<TabItem${a}>`;
  });

  // Drop groupId on Tabs
  s = s.replace(/<Tabs([^>]*)>/g, (m, attrs) => {
    const a = attrs.replace(/\s+groupId=["'][^"']*["']/g, '');
    return `<Tabs${a}>`;
  });

  // Rewrite Python code fences: path + start/end → region
  s = s.replace(
    /```python\s+file=examples\/python\/([^\s]+)(?:\s+start=docs:start:(\w+))?(?:\s+end=docs:end:(\w+))?/g,
    (m, filePart, start, end) => {
      const s1 = start ? (MARKER_RENAMES[start] ?? start) : null;
      const e1 = end ? (MARKER_RENAMES[end] ?? end) : null;
      let meta = `file=vendor/examples/python/${filePart}`;
      if (s1 && e1) {
        if (s1 === e1) meta += ` region=${s1}`;
        else {
          const key = `${s1}→${e1}`;
          const wrap = SPAN_WRAPPERS[key];
          if (wrap) meta += ` region=${wrap}`;
          else meta += ` region=${s1} /* TODO: span ${s1}→${e1} needs wrapper in source */`;
        }
      } else if (s1) {
        meta += ` region=${s1}`;
      }
      return '```python ' + meta;
    }
  );

  // Generic fence rewrite: any lang with `file=<path>` + `start=docs:start:X end=docs:end:X`
  // Used for `protobuf file=proto/angzarr/*.proto start=... end=...` and similar.
  // Paths are left unchanged (proto/, etc. resolve via the plugin's rootDir = repoRoot).
  s = s.replace(
    /```([A-Za-z0-9_+#-]+)\s+file=(\S+)\s+start=docs:start:(\w+)\s+end=docs:end:(\w+)/g,
    (m, lang, filePart, start, end) => {
      if (lang === 'python' && filePart.startsWith('examples/python/')) return m; // already handled above
      if (start === end) return '```' + lang + ' file=' + filePart + ' region=' + start;
      return '```' + lang + ' file=' + filePart + ` region=${start} /* TODO: span ${start}→${end} needs wrapper in source */`;
    }
  );

  // Remove non-Python code fences with file= (drop entire fenced block).
  // Use line-anchored match to avoid crossing adjacent empty fences.
  s = s.replace(
    /^```(?:csharp|rust|java|go|cpp|typescript)\s+file=[^\n]*\n(?:.*\n)*?^```\s*\n?/gm,
    ''
  );

  // Convert HTML comments to JSX comments (MDX v3 requirement)
  s = s.replace(/<!--([\s\S]*?)-->/g, '{/* $1 */}');

  // Docusaurus admonition titles → Starlight bracket form
  // `:::note Title` → `:::note[Title]`
  s = s.replace(
    /^:::(note|tip|info|warning|caution|danger)[ \t]+(.+)$/gm,
    ':::$1[$2]'
  );

  // Docusaurus resolves `./subdir/x` as docs-relative; Astro treats it as page-relative.
  // Rewrite to root-relative for docs-root sections.
  s = s.replace(
    /\]\(\.\/(features|components|sdks|tooling|operations|examples|reference|glossary|blog)\//g,
    ']( /$1/'
  ).replace(/\]\( \//g, '](/');

  // Collapse 3+ consecutive blank lines
  s = s.replace(/\n{4,}/g, '\n\n\n');

  return s;
}

function ensureDir(d) { fs.mkdirSync(d, { recursive: true }); }

const files = walk(srcDir);
let ported = 0;
for (const f of files) {
  let rel = path.relative(srcDir, f);
  // Skip Docusaurus-specific generated content we'll handle separately
  if (rel.startsWith('api/rest/')) continue;
  if (rel.startsWith('api/proto/')) continue; // autogenerated, regenerate later
  if (rel === 'glossary.mdx') continue; // terminology plugin artifact

  const src = fs.readFileSync(f, 'utf8');
  // Docusaurus `slug: /` → Starlight root `index.mdx`
  if (/^slug:\s*\/\s*$/m.test(src.match(/^---\n([\s\S]*?)\n---/)?.[1] ?? '')) {
    const ext = path.extname(rel);
    rel = 'index' + ext;
  }
  const out = transform(src, rel);
  const dest = path.join(destDir, rel);
  ensureDir(path.dirname(dest));
  fs.writeFileSync(dest, out);
  ported++;
}
console.log(`Ported ${ported} files to ${path.relative(projectRoot, destDir)}`);
