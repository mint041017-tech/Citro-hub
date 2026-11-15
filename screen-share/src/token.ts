/**
 * 房间 Token：Worker 自己签发的短期凭证（HS256 JWT）。
 *
 * 为什么不直接把 X-Trash-Token 给客户端长期持有：
 *   1. trash.js 的会话 token 是 30 天有效，泄露即等于账号失守；
 *   2. 房间 token 只需 2 小时，且只携带 roomId / uid / role 三个字段，
 *      泄露后影响范围被限制在这一个房间。
 *
 * 用 WebCrypto 而不是 jsonwebtoken：Worker 里没有 npm 依赖，
 * 且 HS256 的 sign/verify 只需要 crypto.subtle。
 */

import { ERR, type MemberRole } from './types';

export interface RoomTokenPayload {
  v: 1;
  roomId: string;
  roomCode: string;
  uid: string;
  name: string;
  role: MemberRole;
  exp: number;
  iat: number;
}

const encoder = new TextEncoder();

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let bin = '';
  for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromBase64url(s: string): Uint8Array {
  const pad = s.length % 4 === 0 ? '' : '='.repeat(4 - (s.length % 4));
  const bin = atob(s.replace(/-/g, '+').replace(/_/g, '/') + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  if (!secret) {
    // 空密钥会让 importKey 抛出一句看不懂的「Imported HMAC key length (0)…」，
    // 部署时漏配 ROOM_TOKEN_SECRET 就长这样，所以这里先拦一道给出人话。
    throw ERR.sfu('未配置 ROOM_TOKEN_SECRET：请用 `wrangler secret put ROOM_TOKEN_SECRET` 设置');
  }
  return crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
}

export async function signRoomToken(
  payload: Omit<RoomTokenPayload, 'iat' | 'exp'>,
  secret: string,
  ttlSeconds: number,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'HS256', typ: 'JWT' };
  const body: RoomTokenPayload = {
    ...payload,
    iat: now,
    exp: now + ttlSeconds,
  };
  const h = base64url(encoder.encode(JSON.stringify(header)));
  const p = base64url(encoder.encode(JSON.stringify(body)));
  const key = await hmacKey(secret);
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(`${h}.${p}`));
  return `${h}.${p}.${base64url(sig)}`;
}

export async function verifyRoomToken(
  token: string,
  secret: string,
): Promise<RoomTokenPayload> {
  const parts = token.split('.');
  if (parts.length !== 3) throw ERR.badRequest('房间凭证格式不正确');
  const [h, p, s] = parts;
  const key = await hmacKey(secret);
  // 签名段由客户端可控，必须先解码再验签。fromBase64url 用的是 atob，
  // 遇到 base64url 字母表之外的字符（或长度 %4==1）会抛 DOMException；
  // 不包住的话会被 index.ts 的兜底 catch 当成 500 原样返回错误文本，
  // 而设计上这是「凭证格式不对」，应当是 400。
  let sigBytes: Uint8Array;
  try {
    sigBytes = fromBase64url(s);
  } catch {
    throw ERR.badRequest('房间凭证签名无法解析');
  }
  const ok = await crypto.subtle.verify(
    'HMAC',
    key,
    sigBytes as BufferSource,
    encoder.encode(`${h}.${p}`),
  );
  if (!ok) throw ERR.badRequest('房间凭证签名无效');
  let payload: RoomTokenPayload;
  try {
    payload = JSON.parse(new TextDecoder().decode(fromBase64url(p)));
  } catch {
    throw ERR.badRequest('房间凭证无法解析');
  }
  if (payload.v !== 1) throw ERR.badRequest('房间凭证版本不支持');
  if (!payload.roomId || !payload.uid) throw ERR.badRequest('房间凭证缺少必要字段');
  if (payload.exp * 1000 < Date.now()) throw ERR.noAuth('房间凭证已过期');
  return payload;
}

/** 从 Authorization: Bearer xxx 或 ?token=xxx 中取出房间 token。 */
export function extractBearer(req: Request): string | null {
  const h = req.headers.get('authorization');
  if (h) {
    const m = /^Bearer\s+(.+)$/i.exec(h.trim());
    if (m) return m[1].trim();
  }
  return null;
}
