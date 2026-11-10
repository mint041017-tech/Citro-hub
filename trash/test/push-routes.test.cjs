const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const http = require('node:http');
const { spawn } = require('node:child_process');

async function server(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'citro-push-'));
  for (const name of ['trash.js', 'push-notifications.js', 'apns.js']) {
    fs.copyFileSync(path.join(__dirname, '..', name), path.join(dir, name));
  }
  fs.mkdirSync(path.join(dir, 'data'));
  fs.writeFileSync(path.join(dir, 'data', 'sessions.json'), JSON.stringify({ tokens: {
    abc: { name: 'alice', exp: Date.now() + 60000 },
  } }));
  const listener = net.createServer();
  await new Promise((resolve) => listener.listen(0, '127.0.0.1', resolve));
  const port = listener.address().port;
  await new Promise((resolve) => listener.close(resolve));
  const child = spawn(process.execPath, [path.join(dir, 'trash.js')], {
    env: { PATH: process.env.PATH, PORT: String(port), HOST: '127.0.0.1' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(async () => {
    child.kill();
    await new Promise((resolve) => child.once('exit', resolve));
    fs.rmSync(dir, { recursive: true, force: true });
  });
  await new Promise((resolve, reject) => {
    child.stdout.on('data', (chunk) => { if (chunk.toString().includes('[chimu] on')) resolve(); });
    child.once('exit', () => reject(new Error('server exited before listening')));
    setTimeout(() => reject(new Error('server startup timed out')), 5000).unref();
  });
  return { dir, port };
}

function request(port, method, route, body) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method, path: route,
      headers: { 'x-trash-token': 'abc', 'content-type': 'application/json',
        'content-length': Buffer.byteLength(JSON.stringify(body)) } }, (res) => {
      res.resume(); res.on('end', () => resolve(res.statusCode));
    });
    req.on('error', reject);
    req.end(JSON.stringify(body));
  });
}

test('a bind awaiting its body cannot revive a logged out session', async (t) => {
  const { dir, port } = await server(t);
  const body = JSON.stringify({ token: 'a'.repeat(64), environment: 'production' });
  const result = new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/api/push/devices',
      headers: { 'x-trash-token': 'abc', 'content-length': Buffer.byteLength(body) } }, (res) => {
      res.resume(); res.on('end', () => resolve(res.statusCode));
    });
    req.on('error', reject);
    req.flushHeaders();
    req.on('socket', (socket) => socket.once('connect', async () => {
      try {
        assert.equal(await request(port, 'POST', '/api/auth/logout', {}), 200);
        req.end(body);
      } catch (error) { reject(error); req.destroy(); }
    }));
  });
  assert.equal(await result, 401);
  assert.equal(fs.existsSync(path.join(dir, 'data', 'push-devices.json')), false);
});

test('push persistence failure returns an error and preserves previous file', async (t) => {
  const { dir, port } = await server(t);
  const pushFile = path.join(dir, 'data', 'push-devices.json');
  assert.equal(await request(port, 'POST', '/api/push/devices', { token: 'a'.repeat(64), environment: 'production' }), 200);
  const before = fs.readFileSync(pushFile, 'utf8');
  fs.mkdirSync(pushFile + '.tmp');
  assert.equal(await request(port, 'POST', '/api/push/devices', { token: 'b'.repeat(64), environment: 'production' }), 500);
  assert.equal(fs.readFileSync(pushFile, 'utf8'), before);
  assert.equal(await request(port, 'DELETE', '/api/push/devices', { token: 'a'.repeat(64) }), 500);
  assert.equal(fs.readFileSync(pushFile, 'utf8'), before);
  fs.rmdirSync(pushFile + '.tmp');
  assert.equal(await request(port, 'DELETE', '/api/push/devices', { token: 'a'.repeat(64) }), 200);
  assert.deepEqual(JSON.parse(fs.readFileSync(pushFile, 'utf8')).devices, {});
});
