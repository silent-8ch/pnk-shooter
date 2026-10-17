// Ship Painter server: serves the painter UI and lets it read and save assets in the repo.
// Node built-ins only. Listens on 127.0.0.1 so nothing outside this machine can reach it.
//
//   node tools/ship-painter/server.js            then open http://127.0.0.1:5174
//   node tools/ship-painter/server.js --seed     add registry entries for unclassified SVGs, then exit
//   options: --port=N  --root=/path/to/repo
//
// API (paths are repo-relative and must be inside assets/):
//   GET /api/assets                 every SVG (+ derived PNGs) with strategy and status
//   GET /api/asset?path=…           SVG text
//   GET /api/raw?path=…             SVG or PNG bytes, for thumbnails (sandboxed)
//   PUT /api/asset?path=…           { entry: {strategy, role, notes}, svg?: string } saves entry (+ SVG)
'use strict';

const http = require('node:http');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const Registry = require('./registry.js');

const DEFAULT_PORT = 5174;
const ASSETS_DIR = 'assets';
const REGISTRY_PATH = 'assets/assets.json';
const MAX_BODY = 2 * 1024 * 1024;
const STATIC = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/index.html': ['index.html', 'text/html; charset=utf-8'],
  '/painter.js': ['painter.js', 'text/javascript; charset=utf-8'],
  '/regions.js': ['regions.js', 'text/javascript; charset=utf-8'],
  '/registry.js': ['registry.js', 'text/javascript; charset=utf-8'],
};
const RAW_TYPES = { '.svg': 'image/svg+xml', '.png': 'image/png' };

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

// Resolves a client-supplied repo-relative path to an absolute file inside assets/.
// Rejects absolute paths, traversal, other extensions, and symlinks that escape assets/.
async function resolveAsset(root, rel, exts) {
  if (typeof rel !== 'string' || rel === '' || rel.length > 512) throw new HttpError(400, 'path required');
  if (rel.includes('\\') || rel.includes('\0') || path.posix.isAbsolute(rel)) throw new HttpError(400, 'bad path');
  const norm = path.posix.normalize(rel);
  if (norm !== rel || norm.split('/').some((s) => s === '..' || s === '.' || s.startsWith('.'))) throw new HttpError(400, 'bad path');
  if (!norm.startsWith(ASSETS_DIR + '/')) throw new HttpError(400, 'path must be inside assets/');
  if (!exts.includes(path.posix.extname(norm).toLowerCase())) throw new HttpError(400, 'unsupported file type');
  const abs = path.join(root, ...norm.split('/'));
  let real;
  try { real = await fsp.realpath(abs); } catch { throw new HttpError(404, 'not found'); }
  const assetsReal = await fsp.realpath(path.join(root, ASSETS_DIR));
  if (!real.startsWith(assetsReal + path.sep)) throw new HttpError(400, 'bad path');
  return { rel: norm, abs: real };
}

// Every file under assets/ with one of exts, as repo-relative posix paths. Skips dot entries.
async function walk(root, exts) {
  const out = [];
  async function visit(dir, rel) {
    let entries;
    try { entries = await fsp.readdir(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (e.name.startsWith('.')) continue;
      const childRel = rel + '/' + e.name;
      if (e.isDirectory()) await visit(path.join(dir, e.name), childRel);
      else if (e.isFile() && exts.includes(path.extname(e.name).toLowerCase())) out.push(childRel);
    }
  }
  await visit(path.join(root, ASSETS_DIR), ASSETS_DIR);
  return out.sort();
}

async function readSvgs(root) {
  const files = {};
  for (const rel of await walk(root, ['.svg'])) files[rel] = await fsp.readFile(path.join(root, rel), 'utf8');
  return files;
}

async function loadRegistry(root) {
  let text = null;
  try { text = await fsp.readFile(path.join(root, REGISTRY_PATH), 'utf8'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  return Registry.parse(text);
}

// Write to a temp file in the same directory, then rename over the target.
async function writeAtomic(abs, text) {
  const tmp = abs + '.tmp-' + process.pid + '-' + crypto.randomBytes(4).toString('hex');
  try {
    await fsp.writeFile(tmp, text, 'utf8');
    await fsp.rename(tmp, abs);
  } catch (e) {
    await fsp.rm(tmp, { force: true });
    throw e;
  }
}

async function mtime(abs) {
  try { return (await fsp.stat(abs)).mtimeMs; } catch { return null; }
}

// For palette art: 'none' (no <name>_normal.png), 'stale' (SVG newer than it), or 'ok'.
async function normalMapState(root, rel) {
  const png = rel.replace(/\.svg$/i, '_normal.png');
  const pngTime = await mtime(path.join(root, png));
  if (pngTime === null) return 'none';
  return (await mtime(path.join(root, rel))) > pngTime ? 'stale' : 'ok';
}

async function listAssets(root) {
  const files = await readSvgs(root);
  const db = await loadRegistry(root);
  const rows = Registry.list(db, files);
  for (const r of rows) {
    r.kind = 'svg';
    if (r.strategy === 'palette' && r.status !== 'missing-file') r.normalMap = await normalMapState(root, r.path);
  }
  for (const p of await walk(root, ['.png'])) rows.push({ path: p, kind: 'png', status: 'derived' });
  return rows.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}

async function seed(root) {
  const db = await loadRegistry(root);
  const added = Registry.seed(db, await readSvgs(root));
  await writeAtomic(path.join(root, REGISTRY_PATH), Registry.serialize(db));
  return added;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size <= MAX_BODY) chunks.push(c); // past the limit, keep draining so the client sees the 413
    });
    req.on('end', () => {
      if (size > MAX_BODY) reject(new HttpError(413, 'body too large'));
      else resolve(Buffer.concat(chunks).toString('utf8'));
    });
    req.on('error', reject);
  });
}

function createServer(opts) {
  const root = path.resolve(opts.root);
  let writes = Promise.resolve(); // serialize saves so registry updates never interleave

  function allowedHost(h, port) {
    return h === '127.0.0.1:' + port || h === 'localhost:' + port;
  }

  async function saveAsset(rel, body) {
    let data;
    try { data = JSON.parse(body); } catch { throw new HttpError(400, 'body must be JSON'); }
    if (!data || typeof data !== 'object') throw new HttpError(400, 'body must be an object');
    let entry;
    try { entry = Registry.validateEntry(data.entry); } catch (e) { throw new HttpError(400, e.message); }
    if (data.svg !== undefined && (typeof data.svg !== 'string' || !/<svg\b/.test(data.svg))) throw new HttpError(400, 'svg must be SVG text');
    const target = await resolveAsset(root, rel, ['.svg']); // must already exist: saves never create files
    const job = writes.then(async () => {
      if (data.svg !== undefined) await writeAtomic(target.abs, data.svg);
      const svg = await fsp.readFile(target.abs, 'utf8');
      const db = await loadRegistry(root);
      const saved = Registry.setEntry(db, target.rel, entry, svg);
      await writeAtomic(path.join(root, REGISTRY_PATH), Registry.serialize(db));
      return { path: target.rel, entry: saved, status: Registry.statusOf(saved, svg) };
    });
    writes = job.catch(() => {});
    return job;
  }

  async function handle(req, res, port) {
    if (!allowedHost(req.headers.host, port)) throw new HttpError(403, 'bad host');
    const url = new URL(req.url, 'http://localhost');
    if (req.method === 'GET' && STATIC[url.pathname]) {
      const [file, type] = STATIC[url.pathname];
      const text = await fsp.readFile(path.join(__dirname, file));
      res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
      res.end(text);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/assets') return sendJson(res, 200, { assets: await listAssets(root) });
    if (req.method === 'GET' && url.pathname === '/api/asset') {
      const t = await resolveAsset(root, url.searchParams.get('path'), ['.svg']);
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(await fsp.readFile(t.abs));
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/raw') {
      const t = await resolveAsset(root, url.searchParams.get('path'), Object.keys(RAW_TYPES));
      res.writeHead(200, {
        'Content-Type': RAW_TYPES[path.extname(t.abs).toLowerCase()],
        'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; sandbox",
        'X-Content-Type-Options': 'nosniff',
        'Cache-Control': 'no-store',
      });
      res.end(await fsp.readFile(t.abs));
      return;
    }
    if (req.method === 'PUT' && url.pathname === '/api/asset') {
      const origin = req.headers.origin;
      if (!origin || !allowedHost(origin.replace(/^http:\/\//, ''), port) || !origin.startsWith('http://')) throw new HttpError(403, 'bad origin');
      if (!/^application\/json\b/.test(req.headers['content-type'] || '')) throw new HttpError(415, 'content-type must be application/json');
      return sendJson(res, 200, await saveAsset(url.searchParams.get('path'), await readBody(req)));
    }
    throw new HttpError(404, 'not found');
  }

  const server = http.createServer((req, res) => {
    const port = server.address().port;
    handle(req, res, port).catch((e) => {
      const status = e instanceof HttpError ? e.status : 500;
      if (status === 500) console.error(e);
      if (!res.headersSent) sendJson(res, status, { error: status === 500 ? 'internal error' : e.message });
      else res.end();
    });
  });
  return server;
}

function sendJson(res, status, obj) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(obj));
}

function parseArgs(argv) {
  const out = { port: DEFAULT_PORT, root: path.resolve(__dirname, '../..'), seed: false };
  for (const a of argv) {
    if (a === '--seed') out.seed = true;
    else if (a.startsWith('--port=')) out.port = parseInt(a.slice(7), 10);
    else if (a.startsWith('--root=')) out.root = path.resolve(a.slice(7));
    else throw new Error('unknown option ' + a);
  }
  if (!(out.port >= 0 && out.port < 65536)) throw new Error('bad --port');
  if (!fs.existsSync(path.join(out.root, ASSETS_DIR))) throw new Error('no assets/ under ' + out.root);
  return out;
}

if (require.main === module) {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.seed) {
    seed(opts.root).then((added) => {
      console.log('Added ' + added.length + ' entr' + (added.length === 1 ? 'y' : 'ies') + ' to ' + REGISTRY_PATH);
      added.forEach((p) => console.log('  ' + p));
    }, (e) => { console.error(e.message); process.exit(1); });
  } else {
    const server = createServer(opts);
    server.listen(opts.port, '127.0.0.1', () => console.log('Ship Painter: http://127.0.0.1:' + server.address().port));
  }
}

module.exports = { createServer, resolveAsset, listAssets, seed, parseArgs, HttpError, REGISTRY_PATH };
