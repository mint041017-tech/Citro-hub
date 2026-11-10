const assert = require('node:assert/strict');
const test = require('node:test');

const {
  applyApnsStatus,
  bindPushDevice,
  devicesForUser,
  interactionPayload,
  normalizePushState,
  notificationTargets,
  removePushDevicesForUser,
} = require('../push-notifications');

test('a device token is bound to only its latest account', () => {
  const token = 'a'.repeat(64);
  let state = { devices: {} };

  state = bindPushDevice(state, 'alice', token, 'production');
  assert.deepEqual(devicesForUser(state, 'alice'), [
    { token, uid: 'alice', environment: 'production' },
  ]);

  state = bindPushDevice(state, 'bob', token, 'production');
  assert.deepEqual(devicesForUser(state, 'alice'), []);
  assert.deepEqual(devicesForUser(state, 'bob'), [
    { token, uid: 'bob', environment: 'production' },
  ]);
});

test('invalid tokens are rejected without changing state', () => {
  const state = { devices: {} };
  assert.throws(
    () => bindPushDevice(state, 'alice', 'not-hex', 'production'),
    /invalid APNs token/
  );
  assert.throws(
    () => bindPushDevice(state, 'alice', 'a'.repeat(64), 'development'),
    /invalid APNs environment/
  );
  assert.deepEqual(state, { devices: {} });
});

test('device tokens are normalized to lowercase and duplicates merge', () => {
  const upper = 'A'.repeat(64);
  const lower = upper.toLowerCase();
  let state = bindPushDevice({ devices: {} }, 'alice', upper, 'production');
  assert.deepEqual(devicesForUser(state, 'alice'), [
    { token: lower, uid: 'alice', environment: 'production' },
  ]);

  const normalized = normalizePushState({
    devices: {
      [upper]: { token: upper, uid: 'alice', environment: 'production', updated: 2 },
      [lower]: { token: lower, uid: 'bob', environment: 'production', updated: 1 },
    },
  });
  assert.deepEqual(devicesForUser(normalized, 'alice'), [
    { token: lower, uid: 'alice', environment: 'production' },
  ]);
  assert.deepEqual(devicesForUser(normalized, 'bob'), []);
});

test('community interactions build bounded alert payloads', () => {
  const text = 'x'.repeat(120);
  assert.deepEqual(interactionPayload('comment', '小明', text), {
    aps: {
      alert: { title: '小明 评论了你的动态', body: 'x'.repeat(60) + '…' },
      sound: 'default',
      threadId: 'citro-community',
    },
  });
  assert.deepEqual(interactionPayload('reply', '阿珍', '你好'), {
    aps: {
      alert: { title: '阿珍 回复了你', body: '你好' },
      sound: 'default',
      threadId: 'citro-community',
    },
  });
  assert.deepEqual(interactionPayload('like', '阿强', ''), {
    aps: {
      alert: { title: '阿强 赞了你的动态', body: '有人给你送了一个赞' },
      sound: 'default',
      threadId: 'citro-community',
    },
  });
});

test('notification targets exclude the actor and duplicates', () => {
  assert.deepEqual(
    notificationTargets({ actor: 'alice', owner: 'alice', replyTo: 'bob' }),
    ['bob'],
  );
  assert.deepEqual(
    notificationTargets({ actor: 'alice', owner: 'bob', replyTo: 'bob' }),
    ['bob'],
  );
});

test('APNs invalid-token responses remove only that device', () => {
  const first = 'a'.repeat(64);
  const second = 'b'.repeat(64);
  let state = { devices: {} };
  state = bindPushDevice(state, 'alice', first, 'production');
  state = bindPushDevice(state, 'alice', second, 'production');

  state = applyApnsStatus(state, first, 410);
  assert.deepEqual(devicesForUser(state, 'alice'), [
    { token: second, uid: 'alice', environment: 'production' },
  ]);
});

test('a stale invalid-token response cannot remove a rebound device', () => {
  const token = 'd'.repeat(64);
  let state = { devices: {} };
  state = bindPushDevice(state, 'alice', token, 'production');
  state.devices[token].updated = 1;
  const sent = { ...state.devices[token] };
  state = bindPushDevice(state, 'bob', token, 'sandbox');

  state = applyApnsStatus(
    state,
    token,
    410,
    sent.uid,
    sent.environment,
    sent.updated,
  );

  assert.deepEqual(devicesForUser(state, 'bob'), [
    { token, uid: 'bob', environment: 'sandbox' },
  ]);

  const stale = { ...state.devices[token] };
  state.devices[token].updated = 2;
  state = applyApnsStatus(
    state,
    token,
    410,
    sent.uid,
    sent.environment,
    stale.updated,
  );
  assert.equal(state.devices[token].updated, 2);
});

test('account cleanup removes every bound device', () => {
  let state = { devices: {} };
  state = bindPushDevice(state, 'alice', 'a'.repeat(64), 'production');
  state = bindPushDevice(state, 'alice', 'b'.repeat(64), 'production');
  state = bindPushDevice(state, 'bob', 'c'.repeat(64), 'production');

  state = removePushDevicesForUser(state, 'alice');
  assert.deepEqual(devicesForUser(state, 'alice'), []);
  assert.equal(devicesForUser(state, 'bob').length, 1);
});
