#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(here, '..', '..');
const srcDir = path.join(projectRoot, 'blog');
const destDir = path.join(projectRoot, 'site-next', 'src', 'content', 'docs', 'blog');

const AUTHORS = {
  angzarr: { name: 'Ben Abbitt', link: 'https://github.com/benjaminabbitt', picture: 'https://github.com/benjaminabbitt.png' },
};

fs.mkdirSync(destDir, { recursive: true });

const files = fs.readdirSync(srcDir).filter((f) => f.endsWith('.md') || f.endsWith('.mdx'));
let ported = 0;
for (const f of files) {
  // Filename: YYYY-MM-DD-slug.md
  const m = f.match(/^(\d{4}-\d{2}-\d{2})-(.+?)\.mdx?$/);
  if (!m) continue;
  const date = m[1];
  const defaultSlug = m[2];

  const raw = fs.readFileSync(path.join(srcDir, f), 'utf8');
  const fmMatch = raw.match(/^---\n([\s\S]*?)\n---\n?/);
  const fmBody = fmMatch ? fmMatch[1] : '';
  let body = fmMatch ? raw.slice(fmMatch[0].length) : raw;

  let title = null, description = null, slug = defaultSlug;
  const authors = [];
  const tags = [];
  for (const line of fmBody.split('\n')) {
    const tm = line.match(/^title:\s*(.+)$/);
    const sm = line.match(/^slug:\s*(.+)$/);
    const dm = line.match(/^description:\s*(.+)$/);
    const am = line.match(/^authors:\s*\[(.+)\]/);
    const tgm = line.match(/^tags:\s*\[(.+)\]/);
    if (tm) title = tm[1].replace(/^["']|["']$/g, '');
    else if (sm) slug = sm[1].trim();
    else if (dm) description = dm[1].replace(/^["']|["']$/g, '');
    else if (am) am[1].split(',').forEach((a) => authors.push(a.trim()));
    else if (tgm) tgm[1].split(',').forEach((t) => tags.push(t.trim()));
  }

  // Drop Docusaurus @site import and replace with Astro component import if used
  body = body.replace(/^import\s+BlogHeader\s+from\s+['"]@site\/src\/components\/BlogHeader['"];?\s*\n/m, '');
  // Strip Docusaurus truncate marker (MDX v3 rejects raw HTML comments)
  body = body.replace(/<!--\s*truncate\s*-->/g, '');
  // Convert any remaining HTML comments to JSX comments
  body = body.replace(/<!--([\s\S]*?)-->/g, '{/* $1 */}');
  // Docusaurus admonition titles → Starlight bracket form
  body = body.replace(
    /^:::(note|tip|info|warning|caution|danger)[ \t]+(.+)$/gm,
    ':::$1[$2]'
  );
  const needsBlogHeader = /<BlogHeader\s*\/?>/.test(body);
  const importLine = needsBlogHeader
    ? "import BlogHeader from '../../../components/BlogHeader.astro';\n\n"
    : '';

  const fmOut = ['---', `title: ${JSON.stringify(title ?? defaultSlug)}`];
  if (description) fmOut.push(`description: ${JSON.stringify(description)}`);
  // Pin exact Docusaurus URL via explicit slug override
  fmOut.push(`slug: ${JSON.stringify(`blog/${slug}`)}`);
  fmOut.push(`date: ${date}`);
  if (authors.length) {
    fmOut.push('authors:');
    for (const a of authors) fmOut.push(`  - ${JSON.stringify(a)}`);
  }
  if (tags.length) {
    fmOut.push('tags:');
    for (const t of tags) fmOut.push(`  - ${JSON.stringify(t)}`);
  }
  fmOut.push('---');
  const out = fmOut.join('\n') + '\n\n' + importLine + body.replace(/^\n+/, '');

  fs.writeFileSync(path.join(destDir, `${slug}.mdx`), out);
  ported++;
}
console.log(`Ported ${ported} blog posts to ${path.relative(projectRoot, destDir)}`);
