// Level Designer server: serves the timeline editor UI and reads/saves levels/<slug>.json in the repo.
// Node built-ins only. Listens on 127.0.0.1 so nothing outside this machine can reach it.
//
//   node tools/level-designer/server.js          then open http://127.0.0.1:5175
//   options: --port=N  --root=/path/to/repo
//
// API (slug matches ^[a-z0-9][a-z0-9_-]{0,39}$):
//   GET    /api/levels           { levels: [{ slug, name }] }
//   GET    /api/level?slug=…     the level JSON
//   PUT    /api/level?slug=…     body: level JSON; validated, then written atomically (creates or overwrites)
//   DELETE /api/level?slug=…     removes the file
//   GET    /api/pieces           the obstacle piece catalog (assets/obstacles/pieces.json); 404 if missing
// Levels are validated against the piece catalog when it exists (re-read on every request).
'use strict';

const http = require('node:http');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const Level = require('./level.js');

const DEFAULT_PORT = 5175;
const LEVELS_DIR = 'levels';
const PIECES_FILE = path.join('assets', 'obstacles', 'pieces.json');
const MAX_BODY = 1024 * 1024;
const STATIC = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/index.html': ['index.html', 'text/html; charset=utf-8'],
  '/level.js': ['level.js', 'text/javascript; charset=utf-8'],
};

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

// Resolves a client-supplied slug to levels/<slug>.json. The slug regex rules out traversal; the
// realpath check refuses a levels/ dir or file that is a symlink pointing elsewhere.
async function resolveLevel(root, slug, { mustExist }) {
  if (!Level.isSlug(slug)) throw new HttpError(400, 'bad slug');
  const dir = path.join(root, LEVELS_DIR);
  let dirReal;
  try { dirReal = await fsp.realpath(dir); } catch {
    if (mustExist) throw new HttpError(404, 'not found');
    await fsp.mkdir(dir, { recursive: true });
    dirReal = await fsp.realpath(dir);
  }
  const rootReal = await fsp.realpath(root);
  if (dirReal !== path.join(rootReal, LEVELS_DIR)) throw new HttpError(400, 'bad levels dir');
  const abs = path.join(dirReal, slug + '.json');
  let st = null;
  try { st = await fsp.lstat(abs); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  if (st && !st.isFile()) throw new HttpError(400, 'bad path');
  if (!st && mustExist) throw new HttpError(404, 'not found');
  return abs;
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

// Reads the piece catalog. Returns { raw, cat } or null when the file does not exist.
async function loadPieces(root) {
  let text;
  try { text = await fsp.readFile(path.join(root, PIECES_FILE), 'utf8'); } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw e;
  }
  try {
    const raw = JSON.parse(text);
    return { raw, cat: Level.indexCatalog(raw) };
  } catch (e) {
    throw new HttpError(422, 'assets/obstacles/pieces.json: ' + (e instanceof SyntaxError ? 'not valid JSON' : e.message));
  }
}

async function listLevels(root, cat) {
  if (cat === undefined) { const p = await loadPieces(root); cat = p ? p.cat : null; }
  let entries;
  try { entries = await fsp.readdir(path.join(root, LEVELS_DIR), { withFileTypes: true }); } catch { return []; }
  const out = [];
  for (const e of entries) {
    if (!e.isFile() || !e.name.endsWith('.json')) continue;
    const slug = e.name.slice(0, -5);
    if (!Level.isSlug(slug)) continue;
    let name = slug;
    let error;
    try {
      name = Level.parse(await fsp.readFile(path.join(root, LEVELS_DIR, e.name), 'utf8'), cat).name;
    } catch (err) { error = err.message; }
    out.push(error ? { slug, name, error } : { slug, name });
  }
  return out.sort((a, b) => (a.slug < b.slug ? -1 : a.slug > b.slug ? 1 : 0));
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
  let writes = Promise.resolve(); // serialize writes so saves and deletes never interleave

  function allowedHost(h, port) {
    return h === '127.0.0.1:' + port || h === 'localhost:' + port;
  }

  function queue(fn) {
    const job = writes.then(fn);
    writes = job.catch(() => {});
    return job;
  }

  async function catalog() {
    const p = await loadPieces(root);
    return p ? p.cat : null;
  }

  async function saveLevel(slug, body) {
    if (!Level.isSlug(slug)) throw new HttpError(400, 'bad slug');
    const cat = await catalog();
    let text;
    try { text = Level.serialize(JSON.parse(body), cat); } catch (e) {
      throw new HttpError(400, e instanceof SyntaxError ? 'body must be JSON' : e.message);
    }
    return queue(async () => {
      const abs = await resolveLevel(root, slug, { mustExist: false });
      await writeAtomic(abs, text);
      return { slug, level: JSON.parse(text) };
    });
  }

  function checkWrite(req, port) {
    const origin = req.headers.origin;
    if (!origin || !origin.startsWith('http://') || !allowedHost(origin.slice(7), port)) throw new HttpError(403, 'bad origin');
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
    if (req.method === 'GET' && url.pathname === '/api/levels') return sendJson(res, 200, { levels: await listLevels(root, await catalog()) });
    if (req.method === 'GET' && url.pathname === '/api/pieces') {
      const p = await loadPieces(root);
      if (!p) throw new HttpError(404, 'no piece catalog (assets/obstacles/pieces.json)');
      return sendJson(res, 200, p.raw);
    }
    if (url.pathname === '/api/level') {
      const slug = url.searchParams.get('slug');
      if (req.method === 'GET') {
        const abs = await resolveLevel(root, slug, { mustExist: true });
        let level;
        const cat = await catalog();
        try { level = Level.parse(await fsp.readFile(abs, 'utf8'), cat); } catch (e) { throw new HttpError(422, slug + '.json: ' + e.message); }
        return sendJson(res, 200, level);
      }
      if (req.method === 'PUT') {
        checkWrite(req, port);
        if (!/^application\/json\b/.test(req.headers['content-type'] || '')) throw new HttpError(415, 'content-type must be application/json');
        return sendJson(res, 200, await saveLevel(slug, await readBody(req)));
      }
      if (req.method === 'DELETE') {
        checkWrite(req, port);
        await queue(async () => fsp.rm(await resolveLevel(root, slug, { mustExist: true })));
        return sendJson(res, 200, { slug, deleted: true });
      }
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
  const out = { port: DEFAULT_PORT, root: path.resolve(__dirname, '../..') };
  for (const a of argv) {
    if (a.startsWith('--port=')) out.port = /^\d+$/.test(a.slice(7)) ? parseInt(a.slice(7), 10) : NaN;
    else if (a.startsWith('--root=')) out.root = path.resolve(a.slice(7));
    else throw new Error('unknown option ' + a);
  }
  if (!(out.port >= 0 && out.port < 65536)) throw new Error('bad --port');
  if (!fs.existsSync(out.root) || !fs.statSync(out.root).isDirectory()) throw new Error('no such directory ' + out.root);
  return out;
}

if (require.main === module) {
  let opts;
  try { opts = parseArgs(process.argv.slice(2)); } catch (e) { console.error(e.message); process.exit(1); }
  const server = createServer(opts);
  server.listen(opts.port, '127.0.0.1', () => console.log('Level Designer: http://127.0.0.1:' + server.address().port));
}

module.exports = { createServer, resolveLevel, listLevels, loadPieces, parseArgs, HttpError, LEVELS_DIR, PIECES_FILE };
