// Run: node --test tools/level-designer/
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const S = require('./server.js');
const L = require('./level.js');

const LEVEL = {
  name: 'One', length: 8, repeat: true,
  events: [{ time: 1, type: 'diver', lane: 1, count: 3, dir: -1 }, { time: 0, type: 'weaver', lane: 4, count: 3, dir: 1 }],
};

const PIECES = {
  version: 1, scroll_speed: 60,
  pieces: [
    { id: 'rock', name: 'Rock', description: 'A rock.', size: [40, 40], shape: 'circle', hp: 3, outline: [[0, -20], [20, 0], [0, 20], [-20, 0]] },
    { id: 'bar', name: 'Bar', size: [64, 18], shape: 'rect', hp: 0, tile: true, caps: ['bar_l', 'bar_l'], outline: [[-32, -9], [32, -9], [32, 9], [-32, 9]] },
    { id: 'bar_l', name: 'Bar end', size: [24, 18], shape: 'rect', hp: 0, cap: true, outline: [[-12, -9], [12, -9], [12, 9], [-12, 9]] },
  ],
};
const OB = { time: 2, type: 'obstacle', piece: 'bar', lane: 3, count: 4, dir: -1 };

function makeRepo({ levels = true, pieces = PIECES } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'leveldes-'));
  if (pieces !== null) {
    fs.mkdirSync(path.join(root, 'assets/obstacles'), { recursive: true });
    fs.writeFileSync(path.join(root, 'assets/obstacles/pieces.json'), typeof pieces === 'string' ? pieces : JSON.stringify(pieces));
  }
  if (levels) {
    fs.mkdirSync(path.join(root, 'levels'));
    fs.writeFileSync(path.join(root, 'levels/one.json'), L.serialize(LEVEL));
    fs.writeFileSync(path.join(root, 'levels/broken.json'), '{nope');
    fs.writeFileSync(path.join(root, 'levels/old.json'), JSON.stringify({ name: 'Old', bpm: 120, beats_per_bar: 4, bars: 4, repeat: true, events: [] }));
    fs.writeFileSync(path.join(root, 'levels/notes.txt'), 'x');
    fs.writeFileSync(path.join(root, 'levels/.hidden.json'), L.serialize(LEVEL));
  }
  fs.writeFileSync(path.join(root, 'secret.json'), '{"secret":true}');
  return root;
}

async function withServer(fn, repoOpts) {
  const root = makeRepo(repoOpts);
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
  const q = (slug) => '/api/level?slug=' + encodeURIComponent(slug);
  const put = (slug, data, headers) => request('PUT', q(slug), {
    body: typeof data === 'string' ? data : JSON.stringify(data),
    headers: { 'Content-Type': 'application/json', Origin: origin, ...headers },
  });
  const del = (slug, headers) => request('DELETE', q(slug), { headers: { Origin: origin, ...headers } });
  const get = (slug) => request('GET', q(slug));
  try {
    await fn({ root, port, request, put, del, get });
  } finally {
    await new Promise((r) => server.close(r));
    fs.rmSync(root, { recursive: true, force: true });
  }
}

test('GET /api/levels lists valid slugs with names, flags broken files, skips others', () => withServer(async ({ request }) => {
  const res = await request('GET', '/api/levels');
  assert.equal(res.status, 200);
  assert.deepEqual(res.json.levels.map((l) => l.slug), ['broken', 'old', 'one']);
  assert.equal(res.json.levels[2].name, 'One');
  assert.ok(res.json.levels[0].error);
  assert.match(res.json.levels[1].error, /old score format/);
}));

test('GET /api/levels is empty when levels/ is missing', () => withServer(async ({ request }) => {
  const res = await request('GET', '/api/levels');
  assert.equal(res.status, 200);
  assert.deepEqual(res.json.levels, []);
}, { levels: false }));

test('GET /api/level returns the normalised level; 404 / 422 otherwise', () => withServer(async ({ get }) => {
  const res = await get('one');
  assert.equal(res.status, 200);
  assert.deepEqual(res.json, L.validate(LEVEL));
  assert.equal((await get('missing')).status, 404);
  assert.equal((await get('broken')).status, 422);
  const old = await get('old');
  assert.equal(old.status, 422);
  assert.match(old.json.error, /old score format/);
}));

test('PUT creates levels/ and the file, sorted and pretty, with no temp files left', () => withServer(async ({ root, put, get }) => {
  const res = await put('new_level-2', LEVEL);
  assert.equal(res.status, 200, res.text);
  const file = path.join(root, 'levels/new_level-2.json');
  const text = fs.readFileSync(file, 'utf8');
  assert.equal(text, L.serialize(LEVEL));
  assert.deepEqual(JSON.parse(text).events.map((e) => e.time), [0, 1]);
  assert.deepEqual(fs.readdirSync(path.join(root, 'levels')).filter((f) => f.includes('.tmp-')), []);
  assert.equal((await get('new_level-2')).status, 200);
}, { levels: false }));

test('PUT overwrites an existing level', () => withServer(async ({ root, put }) => {
  const res = await put('one', { ...LEVEL, name: 'Renamed', length: 140 });
  assert.equal(res.status, 200, res.text);
  assert.equal(res.json.level.name, 'Renamed');
  assert.equal(JSON.parse(fs.readFileSync(path.join(root, 'levels/one.json'), 'utf8')).length, 140);
}));

test('concurrent PUTs all land', () => withServer(async ({ root, put }) => {
  await Promise.all(['a', 'b', 'c', 'one'].map((s) => put(s, { ...LEVEL, name: s })));
  for (const s of ['a', 'b', 'c', 'one']) assert.equal(JSON.parse(fs.readFileSync(path.join(root, 'levels', s + '.json'), 'utf8')).name, s);
}));

test('PUT/GET/DELETE reject bad slugs and traversal', () => withServer(async ({ root, put, get, del, request }) => {
  for (const s of ['', '../secret', '..', 'a/b', 'A', '_x', '.hidden', 'one.json', 'x'.repeat(41), '%2e%2e', 'one\0']) {
    assert.equal((await put(s, LEVEL)).status, 400, 'put ' + s);
    assert.equal((await get(s)).status, 400, 'get ' + s);
    assert.equal((await del(s)).status, 400, 'del ' + s);
  }
  assert.equal((await request('GET', '/api/level')).status, 400);
  assert.equal((await request('GET', '/api/level?slug=..%2Fsecret')).status, 400);
  assert.equal(fs.readFileSync(path.join(root, 'secret.json'), 'utf8'), '{"secret":true}');
  assert.ok(!fs.existsSync(path.join(root, 'levels/..json')));
}));

test('symlinks out of levels/ are refused', () => withServer(async ({ root, put, get, del }) => {
  fs.symlinkSync(path.join(root, 'secret.json'), path.join(root, 'levels/link.json'));
  assert.equal((await put('link', LEVEL)).status, 400);
  assert.equal((await get('link')).status, 400);
  assert.equal((await del('link')).status, 400);
  assert.equal(fs.readFileSync(path.join(root, 'secret.json'), 'utf8'), '{"secret":true}');
}));

test('a levels/ dir that is a symlink is refused', () => withServer(async ({ root, put }) => {
  const elsewhere = fs.mkdtempSync(path.join(os.tmpdir(), 'leveldes-out-'));
  try {
    fs.symlinkSync(elsewhere, path.join(root, 'levels'));
    assert.equal((await put('x', LEVEL)).status, 400);
    assert.deepEqual(fs.readdirSync(elsewhere), []);
  } finally { fs.rmSync(elsewhere, { recursive: true, force: true }); }
}, { levels: false }));

test('PUT rejects invalid levels and bad bodies, leaving the file untouched', () => withServer(async ({ root, put }) => {
  const before = fs.readFileSync(path.join(root, 'levels/one.json'), 'utf8');
  const bad = [
    '{nope', '[]', 'null', '42',
    { ...LEVEL, length: 5000 }, { ...LEVEL, name: '' }, { ...LEVEL, length: 0 }, { ...LEVEL, bpm: 120 },
    { ...LEVEL, events: [{ time: 8, type: 'weaver', lane: 0, count: 1, dir: 1 }] },
    { ...LEVEL, events: [{ beat: 0, type: 'weaver', lane: 0, count: 1, dir: 1 }] },
    { ...LEVEL, events: [{ time: 0, type: 'boss', lane: 0, count: 1, dir: 1 }] },
  ];
  for (const b of bad) {
    const res = await put('one', b);
    assert.equal(res.status, 400, JSON.stringify(b) + ' → ' + res.text);
    assert.ok(res.json.error);
  }
  const msg = await put('one', { ...LEVEL, length: 5000 });
  assert.match(msg.json.error, /length/);
  const big = await put('one', '{"name":"' + 'x'.repeat(2 * 1024 * 1024) + '"}');
  assert.equal(big.status, 413);
  assert.equal(fs.readFileSync(path.join(root, 'levels/one.json'), 'utf8'), before);
}));

test('DELETE removes a level; 404 when missing', () => withServer(async ({ root, del, request }) => {
  const res = await del('one');
  assert.equal(res.status, 200, res.text);
  assert.ok(!fs.existsSync(path.join(root, 'levels/one.json')));
  assert.equal((await del('one')).status, 404);
  assert.deepEqual((await request('GET', '/api/levels')).json.levels.map((l) => l.slug), ['broken', 'old']);
}));

test('cross-site and DNS-rebinding requests are refused', () => withServer(async ({ root, port, put, del, request }) => {
  assert.equal((await put('one', LEVEL, { Origin: 'http://evil.example' })).status, 403);
  assert.equal((await put('one', LEVEL, { Origin: 'http://127.0.0.1:' + port + '.evil.example' })).status, 403);
  assert.equal((await put('one', LEVEL, { Origin: 'https://127.0.0.1:' + port })).status, 403);
  assert.equal((await put('one', LEVEL, { Origin: '' })).status, 403);
  assert.equal((await put('one', LEVEL, { 'Content-Type': 'text/plain' })).status, 415);
  assert.equal((await del('one', { Origin: 'http://evil.example' })).status, 403);
  assert.equal((await request('DELETE', '/api/level?slug=one')).status, 403, 'no origin');
  assert.ok(fs.existsSync(path.join(root, 'levels/one.json')));
  assert.equal((await request('GET', '/api/levels', { headers: { Host: 'evil.example:' + port } })).status, 403);
  assert.equal((await request('GET', '/api/levels', { headers: { Host: '127.0.0.1' } })).status, 403);
  assert.equal((await request('GET', '/api/levels', { headers: { Host: 'localhost:' + port } })).status, 200);
  assert.equal((await put('one', LEVEL, { Origin: 'http://localhost:' + port })).status, 200);
}));

test('static files: only the tool files are served; unknown routes 404', () => withServer(async ({ request }) => {
  const index = await request('GET', '/');
  assert.equal(index.status, 200);
  assert.match(index.headers['content-type'], /text\/html/);
  assert.match(index.text, /Level Designer/);
  assert.equal((await request('GET', '/level.js')).status, 200);
  assert.equal((await request('GET', '/server.js')).status, 404);
  assert.equal((await request('GET', '/../../levels/one.json')).status, 404);
  assert.equal((await request('POST', '/api/level?slug=one')).status, 404);
  assert.equal((await request('POST', '/api/levels')).status, 404);
}));

test('parseArgs: defaults, options, errors', () => {
  const d = S.parseArgs([]);
  assert.equal(d.port, 5175);
  assert.ok(fs.existsSync(path.join(d.root, 'tools/level-designer/server.js')));
  assert.equal(S.parseArgs(['--port=0']).port, 0);
  assert.equal(S.parseArgs(['--root=' + os.tmpdir()]).root, path.resolve(os.tmpdir()));
  assert.throws(() => S.parseArgs(['--bogus']), /unknown/);
  assert.throws(() => S.parseArgs(['--port=99999']), /port/);
  assert.throws(() => S.parseArgs(['--port=abc']), /port/);
  assert.throws(() => S.parseArgs(['--root=/nonexistent-dir']), /no such/);
});

test('GET /api/pieces serves the catalog; 404 without one, 422 when malformed', async () => {
  await withServer(async ({ request }) => {
    const res = await request('GET', '/api/pieces');
    assert.equal(res.status, 200);
    assert.deepEqual(res.json, PIECES);
    assert.equal((await request('POST', '/api/pieces')).status, 404);
  });
  await withServer(async ({ request }) => {
    const res = await request('GET', '/api/pieces');
    assert.equal(res.status, 404);
    assert.match(res.json.error, /piece catalog/);
  }, { pieces: null });
  await withServer(async ({ request, put }) => {
    const res = await request('GET', '/api/pieces');
    assert.equal(res.status, 422);
    assert.match(res.json.error, /pieces\.json: not valid JSON/);
    assert.equal((await put('one', LEVEL)).status, 422);
  }, { pieces: '{nope' });
  await withServer(async ({ request }) => {
    assert.match((await request('GET', '/api/pieces')).json.error, /duplicate/);
  }, { pieces: { pieces: [{ id: 'a', size: [1, 1] }, { id: 'a', size: [1, 1] }] } });
});

test('the real repo catalog loads', async () => {
  const p = await S.loadPieces(path.resolve(__dirname, '../..'));
  assert.ok(p && p.cat.placeable.length > 0);
});

test('PUT validates obstacles against the catalog and saves them in key order', () => withServer(async ({ root, put, get }) => {
  const good = { ...LEVEL, events: [...LEVEL.events, OB, { ...OB, piece: 'rock', time: 3, count: 1, dir: 1 }] };
  const res = await put('obs', good);
  assert.equal(res.status, 200, res.text);
  const text = fs.readFileSync(path.join(root, 'levels/obs.json'), 'utf8');
  assert.equal(text, L.serialize(good, PIECES));
  const saved = JSON.parse(text).events.find((e) => e.type === 'obstacle');
  assert.deepEqual(Object.keys(saved), ['time', 'type', 'piece', 'lane', 'count', 'dir']);
  assert.deepEqual((await get('obs')).json.events.filter((e) => e.type === 'obstacle').length, 2);
  const before = text;
  const bad = [
    [{ ...OB, piece: 'nope' }, /not in the piece catalog/],
    [{ ...OB, piece: 'bar_l' }, /end cap/],
    [{ ...OB, piece: 'Bad-Id' }, /piece/],
    [{ time: 0, type: 'weaver', piece: 'rock', lane: 0, count: 1, dir: 1 }, /only allowed on obstacle/],
    [{ time: 0, type: 'obstacle', lane: 0, count: 1, dir: 1 }, /missing field "piece"/],
  ];
  for (const [e, re] of bad) {
    const r = await put('obs', { ...LEVEL, events: [e] });
    assert.equal(r.status, 400, JSON.stringify(e));
    assert.match(r.json.error, re);
  }
  assert.equal(fs.readFileSync(path.join(root, 'levels/obs.json'), 'utf8'), before);
}));

test('levels using unknown pieces are flagged on list/get', () => withServer(async ({ root, request, get }) => {
  fs.writeFileSync(path.join(root, 'levels/gone.json'), L.serialize({ ...LEVEL, events: [{ ...OB, piece: 'removed' }] }, null));
  const list = (await request('GET', '/api/levels')).json.levels;
  assert.match(list.find((l) => l.slug === 'gone').error, /not in the piece catalog/);
  assert.equal((await get('gone')).status, 422);
}));

test('without a catalog any well-formed piece id is accepted', () => withServer(async ({ put }) => {
  assert.equal((await put('obs', { ...LEVEL, events: [{ ...OB, piece: 'whatever_1' }] })).status, 200);
  assert.equal((await put('obs', { ...LEVEL, events: [{ ...OB, piece: 'Bad!' }] })).status, 400);
}, { pieces: null }));
