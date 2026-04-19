import fs from 'node:fs';
import path from 'node:path';
import { visit } from 'unist-util-visit';

const FILE_RE = /(?:^|\s)file=(?:"([^"]+)"|'([^']+)'|(\S+))/;
const REGION_RE = /(?:^|\s)region=(?:"([^"]+)"|'([^']+)'|(\S+))/;
const LINES_RE = /#L(\d+)(?:-L?(\d+))?$/;

export default function remarkCodeRegion(options = {}) {
  const { rootDir = process.cwd(), lenient = false } = options;
  return (tree, vfile) => {
    visit(tree, 'code', (node) => {
      if (!node.meta) return;
      const fileMatch = node.meta.match(FILE_RE);
      if (!fileMatch) return;

      let filePath = fileMatch[1] ?? fileMatch[2] ?? fileMatch[3];
      const linesMatch = filePath.match(LINES_RE);
      let lineStart, lineEnd;
      if (linesMatch) {
        filePath = filePath.replace(LINES_RE, '');
        lineStart = parseInt(linesMatch[1], 10);
        lineEnd = linesMatch[2] ? parseInt(linesMatch[2], 10) : undefined;
      }

      const regionMatch = node.meta.match(REGION_RE);
      const region = regionMatch
        ? (regionMatch[1] ?? regionMatch[2] ?? regionMatch[3])
        : null;

      const abs = path.isAbsolute(filePath)
        ? filePath
        : path.resolve(rootDir, filePath);

      const fail = (msg) => {
        if (lenient) {
          node.value = `# TODO migration: ${msg}`;
          return true;
        }
        throw new Error(`remark-code-region: ${msg}\n  referenced from ${vfile.path ?? '?'}`);
      };

      if (!fs.existsSync(abs)) {
        if (fail(`file not found: ${abs}`)) return;
      }

      const lines = fs.readFileSync(abs, 'utf8').split('\n');
      let slice;
      try {
        if (region) {
          slice = extractRegion(lines, region, abs);
        } else if (lineStart !== undefined) {
          slice = lines.slice(lineStart - 1, lineEnd ?? lines.length);
        } else {
          slice = lines;
        }
      } catch (err) {
        if (fail(err.message)) return;
        throw err;
      }
      slice = stripRegionMarkers(slice);
      node.value = dedent(stripTrailingEmpty(slice));
    });
  };
}

function extractRegion(lines, region, file) {
  const start = new RegExp(`#\\s*region\\s+${escapeRegex(region)}\\b`);
  const end = /#\s*endregion\b/;
  let startIdx = -1;
  let depth = 0;
  for (let i = 0; i < lines.length; i++) {
    if (start.test(lines[i])) {
      if (startIdx === -1) startIdx = i;
      continue;
    }
  }
  if (startIdx === -1) {
    throw new Error(`remark-code-region: region "${region}" not found in ${file}`);
  }
  let endIdx = -1;
  for (let i = startIdx + 1; i < lines.length; i++) {
    if (/#\s*region\b/.test(lines[i])) depth++;
    else if (end.test(lines[i])) {
      if (depth === 0) { endIdx = i; break; }
      depth--;
    }
  }
  if (endIdx === -1) {
    throw new Error(`remark-code-region: unterminated region "${region}" in ${file}`);
  }
  return lines.slice(startIdx + 1, endIdx);
}

function stripRegionMarkers(lines) {
  return lines.filter((l) => !/^\s*(?:\/\/|#)\s*(?:#\s*)?(?:region\b|endregion\b)/.test(l));
}

function stripTrailingEmpty(lines) {
  let end = lines.length;
  while (end > 0 && lines[end - 1].trim() === '') end--;
  return lines.slice(0, end);
}

function dedent(lines) {
  const min = lines.reduce((m, l) => {
    if (!l.trim()) return m;
    const match = l.match(/^(\s*)/);
    return Math.min(m, match[1].length);
  }, Infinity);
  const n = Number.isFinite(min) ? min : 0;
  return lines.map((l) => l.slice(n)).join('\n');
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
