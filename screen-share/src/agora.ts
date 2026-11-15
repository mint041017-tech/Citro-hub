/**
 * Agora RTC Access Token（"007" / AccessToken2）签发 —— 纯 Workers 原生 API。
 *
 * 实现与官方 agora-token (RtcTokenBuilder2.buildTokenWithUid) 逐字节对齐，
 * 已用官方库双向交叉验证（我们签的 token 官方能验，官方签的我们能验）：
 *
 *   content    = u16len(signature) + signature + signingInfo
 *   signingInfo = appId(str) + issueTs(u32) + expire(u32) + salt(u32)
 *               + serviceCount(u16) + 每个 service:
 *                   type(u16) + privilegeCount(u16) + (privilege(u16) + expire(u32))*
 *                   + RTC 专属: channelName(str) + uid(str)
 *   signing    = HMAC(key=u32le(salt),    HMAC(key=u32le(issueTs), cert))   ← cert 是 UTF-8 字符串！
 *   signature  = HMAC(key=signing, signingInfo)
 *   token      = "007" + base64(deflate(content))                          ← zlib 格式压缩
 *
 * 所有整数小端（u16/u32）；字符串 = u16 字节长度前缀 + UTF-8 字节。
 * uid 虽是数字也按十进制字符串打包（官方 ServiceRtc 语义：uid===0 → 空串）。
 * privilege expire 与 token expire 同为「now + ttl」的绝对秒（官方 sample 语义）。
 */

import { ERR } from './types';

const TOKEN_VERSION = '007';
const SERVICE_RTC = 1;
// RTC 特权：join / publish audio / publish video / publish data
const PRIVILEGES = [1, 2, 3, 4] as const;

export interface AgoraEnv {
  AGORA_APP_ID?: string;
  AGORA_APP_CERT?: string;
}

const encoder = new TextEncoder();

/** 小端 u16 长度前缀 + UTF-8 字节（与官方 ByteBuf.putString 一致）。 */
function packString(out: number[], s: string): void {
  const b = encoder.encode(s);
  out.push(b.length & 0xff, (b.length >> 8) & 0xff);
  for (const byte of b) out.push(byte);
}

function packU16(out: number[], v: number): void {
  out.push(v & 0xff, (v >> 8) & 0xff);
}

function packU32(out: number[], v: number): void {
  out.push(v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff);
}

function u32leBytes(v: number): Uint8Array {
  const b = new Uint8Array(4);
  b[0] = v & 0xff;
  b[1] = (v >>> 8) & 0xff;
  b[2] = (v >>> 16) & 0xff;
  b[3] = (v >>> 24) & 0xff;
  return b;
}

async function hmac(key: Uint8Array | string, message: Uint8Array): Promise<Uint8Array> {
  const keyBytes = typeof key === 'string' ? encoder.encode(key) : key;
  const k = await crypto.subtle.importKey(
    'raw',
    keyBytes as BufferSource,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', k, message as BufferSource));
}

/** deflate 压缩为 zlib 格式（0x78 0x9C 头），与官方 zlib.deflateSync 一致。 */
async function deflateZlib(bytes: Uint8Array): Promise<Uint8Array> {
  const cs = new CompressionStream('deflate');
  const writer = cs.writable.getWriter();
  await writer.write(bytes as BufferSource);
  await writer.close();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for await (const chunk of cs.readable) {
    chunks.push(chunk as Uint8Array);
    total += (chunk as Uint8Array).length;
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

function base64(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

/**
 * 签发 RTC AccessToken2（官方 RtcTokenBuilder2.buildTokenWithUid 等价实现）。
 *
 * @param appId     Agora 项目 App ID（32 位 hex）
 * @param cert      Agora 项目主证书（32 位 hex）
 * @param channel   频道名（我们用 roomId）
 * @param uid       数字 uid（按十进制字符串打包；0 会按官方语义打成空串，
 *                  我们的 uidFor 永不为 0，无需特判）
 * @param ttlSeconds token 与四个特权共同的存活秒数
 */
export async function buildRtcToken(
  appId: string,
  cert: string,
  channel: string,
  uid: number,
  ttlSeconds: number,
): Promise<string> {
  if (!appId || !cert) {
    throw ERR.agora('未配置 AGORA_APP_ID / AGORA_APP_CERT');
  }
  if (!/^[0-9a-fA-F]{32}$/.test(cert)) {
    throw ERR.agora('AGORA_APP_CERT 格式不对：应为 32 位十六进制主证书');
  }
  const now = Math.floor(Date.now() / 1000);
  // salt 与官方一致取 (1, 99999999]
  const salt = Math.floor(Math.random() * 99_999_999) + 1;
  // 官方 RtcTokenBuilder2 语义：issueTs 为绝对 unix 秒，token expire 与
  // 特权 expire 都写「存活秒数」（delta），服务端按 issueTs + expire 判过期。
  const expire = ttlSeconds;

  // signingInfo
  const info: number[] = [];
  packString(info, appId);
  packU32(info, now);
  packU32(info, ttlSeconds);
  packU32(info, salt);
  packU16(info, 1); // 一个 service：RTC
  packU16(info, SERVICE_RTC);
  packU16(info, PRIVILEGES.length);
  for (const priv of PRIVILEGES) {
    packU16(info, priv);
    packU32(info, expire);
  }
  packString(info, channel);
  packString(info, uid === 0 ? '' : String(uid));
  const signingInfo = Uint8Array.from(info);

  // signing = HMAC(u32le(salt), HMAC(u32le(issueTs), cert字符串))
  const layer1 = await hmac(u32leBytes(now), encoder.encode(cert));
  const signing = await hmac(u32leBytes(salt), layer1);
  const signature = await hmac(signing, signingInfo);

  // content = u16len(sig) + sig + signingInfo，deflate 后拼 "007" 前缀
  const content: number[] = [];
  packU16(content, signature.length);
  content.push(...signature);
  content.push(...signingInfo);
  const compressed = await deflateZlib(Uint8Array.from(content));
  return TOKEN_VERSION + base64(compressed);
}

/** 判断是否配置了 Agora（没配就静默回 Cloudflare 链路）。 */
export function agoraConfigured(env: AgoraEnv): boolean {
  return Boolean(env.AGORA_APP_ID && env.AGORA_APP_CERT);
}
