const TOKEN_RE = /^[a-f0-9]{64}$/i;
const ENVIRONMENTS = new Set(['production', 'sandbox']);

function normalizePushState(state) {
  const next = { devices: {} };
  const source = state && state.devices ? state.devices : {};
  for (const raw of Object.values(source)) {
    if (!raw || typeof raw !== 'object') continue;
    const token = String(raw.token || '').trim().toLowerCase();
    if (!TOKEN_RE.test(token) || !raw.uid) continue;
    const updated = Number(raw.updated || 0);
    if (next.devices[token] && Number(next.devices[token].updated || 0) >= updated) continue;
    next.devices[token] = {
      token,
      uid: String(raw.uid),
      environment: ENVIRONMENTS.has(raw.environment) ? raw.environment : 'production',
      updated,
    };
  }
  return next;
}

function bindPushDevice(state, uid, token, environment) {
  const value = String(token || '').trim().toLowerCase();
  if (!TOKEN_RE.test(value)) throw new Error('invalid APNs token');
  if (!ENVIRONMENTS.has(environment)) throw new Error('invalid APNs environment');
  const owner = String(uid || '').trim();
  if (!owner) throw new Error('invalid push account');

  const next = normalizePushState(state);
  next.devices[value] = {
    token: value,
    uid: owner,
    environment,
    updated: Date.now(),
  };
  return next;
}

function devicesForUser(state, uid) {
  const owner = String(uid || '');
  return Object.values(state && state.devices ? state.devices : {})
    .filter((device) => device && device.uid === owner && TOKEN_RE.test(device.token))
    .map(({ token, uid, environment }) => ({ token, uid, environment }))
    .sort((a, b) => a.token.localeCompare(b.token));
}

function removePushDevicesForUser(state, uid) {
  const owner = String(uid || '');
  const next = normalizePushState(state);
  for (const token of Object.keys(next.devices)) {
    if (next.devices[token] && next.devices[token].uid === owner) delete next.devices[token];
  }
  return next;
}

function applyApnsStatus(
  state,
  token,
  status,
  expectedUid,
  expectedEnvironment,
  expectedUpdated,
) {
  if (status !== 410) return state;
  const value = String(token || '').trim().toLowerCase();
  const next = normalizePushState(state);
  const current = next.devices[value];
  if (!current) return state;
  if (
    expectedUid &&
    (current.uid !== expectedUid ||
      current.environment !== expectedEnvironment ||
      Number(current.updated || 0) !== Number(expectedUpdated || 0))
  ) {
    return state;
  }
  delete next.devices[value];
  return next;
}

function truncate(text, max) {
  const value = String(text || '').split(' ').filter(Boolean).join(' ').trim();
  return value.length > max ? value.slice(0, max) + '…' : value;
}

function interactionPayload(type, nick, text) {
  const bodyText = text == null ? '' : text;
  const name = truncate(nick, 24) || '有人';
  let title;
  let body;
  if (type === 'reply') {
    title = name + ' 回复了你';
    body = truncate(bodyText, 60) || '给你发来了回复';
  } else if (type === 'comment') {
    title = name + ' 评论了你的动态';
    body = truncate(bodyText, 60) || '给你写了评论';
  } else if (type === 'like') {
    title = name + ' 赞了你的动态';
    body = '有人给你送了一个赞';
  } else {
    throw new Error('unsupported notification type');
  }
  return {
    aps: {
      alert: { title: title, body: body },
      sound: 'default',
      threadId: 'citro-community',
    },
  };
}

function notificationTargets(options) {
  const actor = String((options && options.actor) || '').trim();
  return [...new Set([(options && options.owner) || '', (options && options.replyTo) || ''])]
    .map((value) => String(value || '').trim())
    .filter((value) => value && value !== actor);
}

module.exports = {
  applyApnsStatus: applyApnsStatus,
  bindPushDevice: bindPushDevice,
  devicesForUser: devicesForUser,
  interactionPayload: interactionPayload,
  normalizePushState: normalizePushState,
  notificationTargets: notificationTargets,
  removePushDevicesForUser: removePushDevicesForUser,
};
