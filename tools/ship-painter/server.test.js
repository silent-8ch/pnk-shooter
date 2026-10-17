// Run: node --test tools/ship-painter/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const S = require('./server.js');

const PAINTED = '<svg data-slots="1" data-slot-names="Hull"><path data-slot="1" fill="#ff0000"/></svg>';
const WHITE = '<svg><path fill="#ffffff"/></svg>';
const COLORED = '<svg><path fill="#8075ff"/></svg>';

function makeRepo() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'painter-'));
  fs.mkdirSync(path.join(root, 'assets/filler/fx'), { recursive: true });
  fs.writeFileSync(path.join(root, 'assets/ship01.svg'), PAINTED);
  fs.writeFileSync(path.join(root, 'assets/ship01_normal.png'), 'png');
  fs.writeFileSync(path.join(root, 'assets/filler/scout.svg'), COLORED);
  fs.writeFileSync(path.join(root, 'assets/filler/fx/spark.svg'), WHITE);
  fs.writeFileSync(path.join(root, 'assets/filler/fx/spark.svg.import'), 'x');
  fs.mkdirSync(path.join(root, 'assets/.hidden'));
  fs.writeFileSync(path.join(root, 'assets/.hidden/x.svg'), WHITE);
  fs.writeFileSync(path.join(root, 'secret.svg'), WHITE);
  // Make the normal map newer than its SVG.
  const old = new Date(Date.now() - 60000);
  fs.utimesSync(path.join(root, 'assets/ship01.svg'), old, old);
  return root;
}

async function withServer(fn) {
  const root = makeRepo();
  const server = S.createServer({ root });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  const origin = 'http://127.0.0.1:' + port;
  function request(method, url, { body, headers } = {}) {
    return new Promise((resolve, reject) => {
      const req = http.request({ host: '127.0.0.1', port, method, path: url, headers: { Host: '127.0.0.1:' + port, ...headers } }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let json = null;
          try { json = JSON.parse(text); } catch {}
          resolve({ status: res.statusCode, headers: res.headers, text, json });
        });
      });
      req.on('error', reject);
      if (body !== undefined) req.write(body);
      req.end();
    });
  }
  const put = (p, data, headers) => request('PUT', '/api/asset?path=' + encodeURIComponent(p), {
    body: typeof data === 'string' ? data : JSON.stringify(data),
    headers: { 'Content-Type': 'application/json', Origin: origin, ...headers },
  });
  try {
    await fn({ root, port, request, put });
  } finally {
    await new Promise((r) => server.close(r));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

test('GET /api/assets lists SVGs with status and derived PNGs, skipping dot dirs and non-assets', () => withServer(async ({ request }) => {
  const res = await request('GET', '/api/assets');
  assert.equal(res.status, 200);
  const rows = res.json.assets;
  assert.deepEqual(rows.map((r) => r.path), [
    'assets/filler/fx/spark.svg', 'assets/filler/scout.svg', 'assets/ship01.svg', 'assets/ship01_normal.png',
  ]);
  const by = Object.fromEntries(rows.map((r) => [r.path, r]));
  assert.equal(by['assets/filler/scout.svg'].status, 'needs-strategy');
  assert.equal(by['assets/filler/fx/spark.svg'].suggested, 'tint');
  assert.equal(by['assets/ship01_normal.png'].status, 'derived');
}));

test('seed writes a registry; list then reflects it, including normal map state', () => withServer(async ({ root, request }) => {
  const added = await S.seed(root);
  assert.equal(added.length, 3);
  const db = JSON.parse(fs.readFileSync(path.join(root, S.REGISTRY_PATH), 'utf8'));
  assert.equal(db.assets['assets/ship01.svg'].strategy, 'palette');
  assert.deepEqual(db.assets['assets/ship01.svg'].slots, ['Hull']);
  const rows = (await request('GET', '/api/assets')).json.assets;
  const ship = rows.find((r) => r.path === 'assets/ship01.svg');
  assert.equal(ship.status, 'ok');
  assert.equal(ship.normalMap, 'ok');
  assert.deepEqual(await S.seed(root), [], 'seeding twice adds nothing');
}));

test('GET /api/asset returns SVG text; /api/raw is sandboxed', () => withServer(async ({ request }) => {
  const res = await request('GET', '/api/asset?path=assets/filler/scout.svg');
  assert.equal(res.status, 200);
  assert.equal(res.text, COLORED);
  const raw = await request('GET', '/api/raw?path=assets/ship01_normal.png');
  assert.equal(raw.status, 200);
  assert.equal(raw.headers['content-type'], 'image/png');
  assert.match(raw.headers['content-security-policy'], /sandbox/);
  assert.equal((await request('GET', '/api/asset?path=assets/ship01_normal.png')).status, 400, 'asset text is SVG only');
}));

test('PUT saves the SVG and the entry; status and normal map update', () => withServer(async ({ root, put, request }) => {
  const svg = '<svg data-slots="1" data-slot-names="Body"><path data-slot="1" fill="#8075ff"/></svg>';
  const res = await put('assets/filler/scout.svg', { entry: { strategy: 'palette', role: 'enemy', notes: 'n' }, svg });
  assert.equal(res.status, 200, res.text);
  assert.equal(res.json.status, 'ok');
  assert.equal(fs.readFileSync(path.join(root, 'assets/filler/scout.svg'), 'utf8'), svg);
  const db = JSON.parse(fs.readFileSync(path.join(root, S.REGISTRY_PATH), 'utf8'));
  assert.deepEqual(db.assets['assets/filler/scout.svg'], { strategy: 'palette', role: 'enemy', slots: ['Body'], notes: 'n' });
  assert.deepEqual(fs.readdirSync(path.join(root, 'assets/filler')).filter((f) => f.includes('.tmp-')), [], 'no temp files left');

  await put('assets/ship01.svg', { entry: { strategy: 'palette' }, svg: PAINTED.replace('ff0000', '00ff00') });
  const ship = (await request('GET', '/api/assets')).json.assets.find((r) => r.path === 'assets/ship01.svg');
  assert.equal(ship.normalMap, 'stale');
}));

test('PUT without svg only updates the entry', () => withServer(async ({ root, put }) => {
  const res = await put('assets/filler/fx/spark.svg', { entry: { strategy: 'tint' } });
  assert.equal(res.status, 200, res.text);
  assert.equal(fs.readFileSync(path.join(root, 'assets/filler/fx/spark.svg'), 'utf8'), WHITE);
  assert.equal(res.json.status, 'ok');
}));

test('concurrent PUTs all land in the registry', () => withServer(async ({ root, put }) => {
  await Promise.all([
    put('assets/filler/fx/spark.svg', { entry: { strategy: 'tint' } }),
    put('assets/filler/scout.svg', { entry: { strategy: 'fixed' } }),
    put('assets/ship01.svg', { entry: { strategy: 'palette' } }),
  ]);
  const db = JSON.parse(fs.readFileSync(path.join(root, S.REGISTRY_PATH), 'utf8'));
  assert.equal(Object.keys(db.assets).length, 3);
}));

test('PUT rejects paths outside assets/, traversal, new files and other types', () => withServer(async ({ put }) => {
  const entry = { entry: { strategy: 'tint' } };
  for (const p of ['../secret.svg', 'secret.svg', '/etc/passwd', 'assets/../secret.svg', 'assets/./ship01.svg',
    'assets\\ship01.svg', 'assets/.hidden/x.svg', 'assets/ship01_normal.png', 'assets/assets.json', '']) {
    const res = await put(p, entry);
    assert.equal(res.status, 400, p + ' → ' + res.text);
  }
  assert.equal((await put('assets/new.svg', entry)).status, 404, 'saves never create files');
}));

test('PUT rejects symlinks that escape assets/', () => withServer(async ({ root, put }) => {
  fs.symlinkSync(path.join(root, 'secret.svg'), path.join(root, 'assets/link.svg'));
  const res = await put('assets/link.svg', { entry: { strategy: 'tint' }, svg: '<svg/>' });
  assert.equal(res.status, 400);
  assert.equal(fs.readFileSync(path.join(root, 'secret.svg'), 'utf8'), WHITE);
}));

test('PUT rejects bad bodies', () => withServer(async ({ root, put }) => {
  const p = 'assets/filler/scout.svg';
  assert.equal((await put(p, '{nope')).status, 400);
  assert.equal((await put(p, { entry: { strategy: 'bogus' } })).status, 400);
  assert.equal((await put(p, { entry: { strategy: 'tint' }, svg: 'not svg' })).status, 400);
  assert.equal((await put(p, { entry: { strategy: 'tint' }, svg: 42 })).status, 400);
  const big = await put(p, { entry: { strategy: 'tint' }, svg: '<svg>' + 'x'.repeat(3 * 1024 * 1024) + '</svg>' });
  assert.equal(big.status, 413);
  assert.equal(fs.readFileSync(path.join(root, p), 'utf8'), COLORED, 'file untouched');
}));

test('cross-site and DNS-rebinding requests are refused', () => withServer(async ({ port, put, request }) => {
  const p = 'assets/filler/scout.svg';
  const entry = { entry: { strategy: 'tint' } };
  assert.equal((await put(p, entry, { Origin: 'http://evil.example' })).status, 403);
  assert.equal((await put(p, entry, { Origin: 'http://127.0.0.1:' + port + '.evil.example' })).status, 403);
  assert.equal((await put(p, entry, { Origin: '' })).status, 403);
  assert.equal((await put(p, entry, { 'Content-Type': 'text/plain' })).status, 415);
  assert.equal((await request('GET', '/api/assets', { headers: { Host: 'evil.example:' + port } })).status, 403);
  assert.equal((await request('GET', '/api/assets', { headers: { Host: 'localhost:' + port } })).status, 200);
}));

test('static files: only the tool files are served', () => withServer(async ({ request }) => {
  const index = await request('GET', '/');
  assert.equal(index.status, 200);
  assert.match(index.text, /Ship Painter/);
  assert.equal((await request('GET', '/registry.js')).status, 200);
  assert.equal((await request('GET', '/server.js')).status, 404);
  assert.equal((await request('GET', '/../../assets/ship01.svg')).status, 404);
}));

test('parseArgs: defaults, options, errors', () => {
  const d = S.parseArgs([]);
  assert.equal(d.port, 5174);
  assert.ok(fs.existsSync(path.join(d.root, 'assets')));
  assert.equal(S.parseArgs(['--port=0', '--seed']).seed, true);
  assert.throws(() => S.parseArgs(['--bogus']), /unknown/);
  assert.throws(() => S.parseArgs(['--port=99999']), /port/);
  assert.throws(() => S.parseArgs(['--root=/nonexistent-dir']), /no assets/);
});
