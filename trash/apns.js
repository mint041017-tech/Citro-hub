const crypto = require('crypto');
const fs = require('fs');
const http2 = require('http2');

function privateKey(config) {
  try {
    if (config.file) return fs.readFileSync(config.file, 'utf8');
    if (config.keyB64) return Buffer.from(config.keyB64, 'base64').toString('utf8');
    if (config.key) return config.key;
    return '';
  } catch (e) {
    return '';
  }
}

let cachedJwt;
let cachedJwtAt;

function providerToken(config) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && cachedJwtAt && now - cachedJwtAt < 1800) return cachedJwt;
  const key = privateKey(config);
  if (!key || !config.teamId || !config.keyId) throw new Error('APNs is not configured');
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: config.keyId })).toString('base64url');
  const claims = Buffer.from(JSON.stringify({ iss: config.teamId, iat: now })).toString('base64url');
  const input = header + '.' + claims;
  const signature = crypto.sign('SHA256', Buffer.from(input), {
    key: key,
    dsaEncoding: 'ieee-p1363',
  });
  cachedJwt = input + '.' + Buffer.from(signature).toString('base64url');
  cachedJwtAt = now;
  return cachedJwt;
}

function sendApns(config, token, environment, payload) {
  if (!config.teamId || !config.keyId || !config.bundleId || !privateKey(config)) {
    return Promise.resolve({ skipped: true, reason: 'APNs is not configured' });
  }
  const host = environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  return new Promise((resolve) => {
    let settled = false;
    const client = http2.connect('https://' + host);
    let timeout;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      client.close();
      resolve(value);
    };
    timeout = setTimeout(() => finish({ error: 'APNs request timed out' }), 5000);
    client.on('error', (error) => finish({ error: error.message }));
    let bearer;
    try {
      bearer = providerToken(config);
    } catch (error) {
      finish({ skipped: true, reason: error.message });
      return;
    }
    const request = client.request({
      ':method': 'POST',
      ':path': '/3/device/' + token,
      authorization: 'bearer ' + bearer,
      'apns-topic': config.bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    });
    request.write(JSON.stringify(payload), 'utf8');
    request.end();
    request.on('response', (headers) => finish({ status: headers[':status'] }));
    request.on('error', (error) => finish({ error: error.message }));
  });
}

module.exports = { sendApns };
