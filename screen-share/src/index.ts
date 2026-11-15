/**
 * Citro 屏幕共享 Worker。
 *
 * 只做三件事：
 *   1. 登录态校验（拿 X-Trash-Token 找 trash.js 换 uid）；
 *   2. 房间 REST API（创建 / 加入 / 发布 / 订阅 / 结束…）；
 *   3. 把房间状态和 WebSocket 交给 Durable Object。
 *
 * 媒体不在这个 Worker 里：视频 / 音频走 Cloudflare Realtime SFU，
 * 见 src/sfu.ts。
 */

import { agoraConfigured, buildRtcToken } from './agora';
import { Room, sanitizeQuality } from './room';
import {
  createSession,
  closeSession,
  generateIceServers,
  publishTracks,
  renegotiate,
  subscribeTracks,
} from './sfu';
import { verifyTrashToken } from './trash';
import { extractBearer, signRoomToken, verifyRoomToken } from './token';
import {
  ApiError,
  ERR,
  type AnswerRequest,
  type ChatMessage,
  type CreateRoomRequest,
  type CreateRoomResponse,
  type Env,
  type JoinRoomRequest,
  type JoinRoomResponse,
  type PublicMember,
  type PublicTrack,
  type PublishRequest,
  type PublishResponse,
  type PublicRoom,
  type RoomType,
  type SessionDescriptionPayload,
  type SubscribeRequest,
  type SubscribeResponse,
} from './types';

export { Room };

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-Trash-Token',
  'Access-Control-Max-Age': '86400',
  'Cache-Control': 'no-store',
  Vary: 'Origin',
};

/** 每个 IP 每分钟最多 20 次加入尝试（防刷房号）。 */
const joinAttempts = new Map<string, { count: number; reset: number }>();

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }

    // 静态资源：非 /api 一律交给 ASSETS（分享首页 / 降级页）。
    // 测试环境可能没有 ASSETS 绑定，此时回落到一行提示而不是抛错。
    if (!url.pathname.startsWith('/api/')) {
      if (!env.ASSETS) {
        return json({ err: '静态资源未配置', path: url.pathname }, 404, CORS);
      }
      const asset = await env.ASSETS.fetch(request);
      const headers = new Headers(asset.headers);
      for (const [k, v] of Object.entries(CORS)) headers.set(k, v);
      return new Response(asset.body, { status: asset.status, headers });
    }

    try {
      const route = routeFor(url.pathname, request.method);
      if (!route) return json({ err: '接口不存在' }, 404, CORS);

      const result = await route(request, env, ctx, url);
      const headers = new Headers(CORS);
      headers.set('Content-Type', 'application/json; charset=utf-8');
      if (result instanceof Response) {
        // WebSocket 握手必须原样返回。一旦重建 Response（哪怕只加 CORS 头），
        // webSocket 属性就丢了，workerd 会直接抛
        // 「Responses may only be constructed with status codes in the range
        // 200 to 599」—— 101 不在允许区间里，且 101 响应本身也不需要 CORS。
        if (result.status === 101 || result.webSocket) return result;
        const out = new Headers(result.headers);
        for (const [k, v] of Object.entries(CORS)) out.set(k, v);
        return new Response(result.body, { status: result.status, headers: out });
      }
      return json(result, 200, CORS);
    } catch (e) {
      if (e instanceof Error && 'status' in e) {
        const err = e as Error & { status: number; code?: string };
        return json({ err: err.message, code: err.code }, err.status, CORS);
      }
      const msg = e instanceof Error ? e.message : String(e);
      return json({ err: msg }, 500, CORS);
    }
  },
} satisfies ExportedHandler<Env>;

// ── 路由 ────────────────────────────────────────────────────────────────

type RouteHandler = (
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  url: URL,
) => Promise<unknown | Response>;

function routeFor(path: string, method: string): RouteHandler | null {
  if (path === '/api/health' && method === 'GET') return health;
  if (path === '/api/ice' && method === 'GET') return ice;
  if (path === '/api/rooms' && method === 'POST') return createRoom;
  if (path === '/api/agora/token' && method === 'POST') return agoraToken;

  const m = /^\/api\/rooms\/([^/]+)(?:\/(.+))?$/.exec(path);
  if (m) {
    const sub = m[2];
    const key = `${method} ${sub ?? ''}`;
    switch (key) {
      case 'GET ':
        return getRoom;
      case 'POST join':
        return joinRoom;
      case 'POST publish':
        return publish;
      case 'POST subscribe':
        return subscribe;
      case 'POST answer':
        return answer;
      case 'POST leave':
        return leave;
      case 'POST kick':
        return kick;
      case 'POST end':
        return endRoom;
      case 'GET ws':
      case 'POST ws':
        return ws;
      default:
        return null;
    }
  }
  return null;
}

// ── 辅助 ────────────────────────────────────────────────────────────────

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...extra },
  });
}

function roomIdFrom(url: URL): string {
  const m = /^\/api\/rooms\/([^/]+)/.exec(url.pathname);
  return m ? decodeURIComponent(m[1]) : '';
}

/**
 * DO 的命名空间 key。
 *
 * roomId 形如 `123456-a1b2c3`（房间码 + 随机后缀），但用户手上只有 6 位
 * 房间码。用房间码当 DO key，`123456` 和 `123456-a1b2c3` 才能落到同一个
 * DO 上 —— 否则「输入房间号加入」会凭空新建一个空房间。
 */
/**
 * 调 DO 的内部接口，并把 DO 的错误原样抛回给调用方。
 *
 * 不检查状态码的话，DO 侧的失败会被吞掉：满员（409）时客户端照样拿到
 * 200 和一张其实进不去的 roomToken，界面会显示「已加入」但收不到任何事件。
 * 这类错误必须透传，见 src/room.ts 的 catch —— 它保留了 ApiError 的 status/code。
 */
async function doCall(env: Env, roomId: string, path: string, init?: RequestInit): Promise<Response> {
  const id = env.ROOMS.idFromName(doKey(roomId));
  const res = await env.ROOMS.get(id).fetch(`https://do${path}`, init);
  if (!res.ok) {
    const body = (await res.json().catch(() => null)) as { err?: string; code?: string } | null;
    throw new ApiError(res.status, body?.code ?? 'do_error', body?.err ?? '房间操作失败');
  }
  return res;
}

function doKey(roomIdOrCode: string): string {
  const i = roomIdOrCode.indexOf('-');
  return i > 0 ? roomIdOrCode.slice(0, i) : roomIdOrCode;
}

/** 取房间状态（带 DO 反查）。 */
async function loadRoom(env: Env, roomId: string): Promise<{ room: PublicRoom; members: PublicMember[] }> {
  const res = await doCall(env, roomId, '/internal/state');
  const data = (await res.json().catch(() => null)) as
    | { room?: PublicRoom; members?: PublicMember[]; err?: string }
    | null;
  if (!data?.room) throw ERR.notFound();
  return { room: data.room, members: data.members ?? [] };
}

function requireToken(env: Env, request: Request, url: URL): Promise<
  Awaited<ReturnType<typeof verifyRoomToken>>
> {
  const fromQuery = url.searchParams.get('token');
  const token = extractBearer(request) ?? fromQuery;
  if (!token) throw ERR.noAuth('缺少房间凭证');
  return verifyRoomToken(token, env.ROOM_TOKEN_SECRET);
}

function clientIp(request: Request): string {
  return (
    request.headers.get('cf-connecting-ip') ??
    request.headers.get('x-real-ip') ??
    'unknown'
  );
}

function rateLimitJoin(ip: string): void {
  const now = Date.now();
  const win = joinAttempts.get(ip);
  if (!win || win.reset < now) {
    joinAttempts.set(ip, { count: 1, reset: now + 60_000 });
    return;
  }
  win.count += 1;
  if (win.count > 20) throw ERR.rateLimit();
}

function genRoomCode(): string {
  const buf = new Uint8Array(3);
  crypto.getRandomValues(buf);
  // 6 位数字，避开 0 开头导致的识别问题。
  const n = 100000 + ((buf[0] << 16 | buf[1] << 8 | buf[2]) % 900000);
  return String(n);
}

function genRoomId(code: string): string {
  const buf = new Uint8Array(3);
  crypto.getRandomValues(buf);
  const suffix = Array.from(buf)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return `${code}-${suffix}`;
}

// ── 接口实现 ────────────────────────────────────────────────────────────

async function health(): Promise<unknown> {
  return { ok: true, ts: Date.now(), service: 'citro-screen-share' };
}

async function ice(request: Request, env: Env, _ctx: ExecutionContext, url: URL): Promise<unknown> {
  await requireToken(env, request, url);
  const iceServers = await generateIceServers(env);
  return { iceServers };
}

/**
 * 字符串 uid → 稳定 uint32（FNV-1a）。Agora 的数字 uid 需要收发两端
 * 一致，我们用房间 uid（字符串）哈希出同一个数，双方各自算即可，
 * 不需要额外的映射接口。
 */
function numericUid(uid: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < uid.length; i++) {
    h ^= uid.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  // Agora uid 0 表示「由 SDK 分配」，避开；取正数 31 位。
  return (h >>> 0) % 0x7fffffff || 1;
}

/**
 * 声网 RTC token。客户端加入房间后调用，拿 { appId, channel, uid, token }。
 * 未配置 AGORA_APP_CERT 时返回 { enabled: false }，客户端回 Cloudflare 链路。
 */
async function agoraToken(
  request: Request,
  env: Env,
  _ctx: ExecutionContext,
  url: URL,
): Promise<unknown> {
  const payload = await requireToken(env, request, url);
  if (!agoraConfigured(env)) {
    return { enabled: false as const };
  }
  const body = (await request.json().catch(() => ({}))) as { channel?: string };
  const channel = (body.channel || payload.roomId).slice(0, 64);
  const uid = numericUid(payload.uid);
  const ttl = 24 * 3600;
  const token = await buildRtcToken(
    env.AGORA_APP_ID!,
    env.AGORA_APP_CERT!,
    channel,
    uid,
    ttl,
  );
  return {
    enabled: true as const,
    appId: env.AGORA_APP_ID,
    channel,
    uid,
    token,
    // join 时留下自己的字符串 uid 和数字 uid 的对应关系，方便排查。
    uidStr: payload.uid,
    expiresAt: (Math.floor(Date.now() / 1000) + ttl) * 1000,
  };
}

async function createRoom(
  request: Request,
  env: Env,
  _ctx: ExecutionContext,
  _url: URL,
): Promise<CreateRoomResponse> {
  const trashToken = request.headers.get('X-Trash-Token');
  const user = await verifyTrashToken(env, trashToken);
  const body = (await request.json().catch(() => ({}))) as CreateRoomRequest;
  const roomType: RoomType = body.roomType ?? 'one_to_many';
  if (!['one_to_many', 'one_to_one', 'multi_party'].includes(roomType)) {
    throw ERR.badRequest('房间模式不正确');
  }
  const quality = sanitizeQuality(body.quality);

  const code = genRoomCode();
  const roomId = genRoomId(code);
  const ttlHours = Number(env.ROOM_TTL_HOURS) || 12;
  const expiresAt = Date.now() + ttlHours * 3600_000;

  await doCall(env, roomId, '/internal/reset', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      roomId,
      roomCode: code,
      title: body.title,
      roomType,
      quality,
      hostUid: user.name,
      hostName: user.name,
      expiresAt,
    }),
  });

  const tokenTtl = (Number(env.ROOM_TOKEN_TTL_HOURS) || 2) * 3600;
  const roomToken = await signRoomToken(
    {
      v: 1,
      roomId,
      roomCode: code,
      uid: user.name,
      name: user.name,
      role: 'host',
    },
    env.ROOM_TOKEN_SECRET,
    tokenTtl,
  );

      const iceServers = await generateIceServers(env);
  const { room, members } = await loadRoom(env, roomId);

  return {
    roomId,
    roomCode: code,
    roomToken,
    iceServers,
    expiresAt,
    room,
    agora: { enabled: agoraConfigured(env) },
    // 和 getRoom 保持一致：把创建者自己标出来，客户端不用猜 uid。
    members: members.map((m) => ({ ...m, self: m.uid === user.name })),
  };
}

async function getRoom(
  request: Request,
  env: Env,
  _ctx: ExecutionContext,
  url: URL,
): Promise<unknown> {
  const payload = await requireToken(env, request, url);
  const { room, members } = await loadRoom(env, payload.roomId);
  return {
    room,
    members: members.map((m) => ({ ...m, self: m.uid === payload.uid })),
  };
}

async function joinRoom(
  request: Request,
  env: Env,
  _ctx: ExecutionContext,
  url: URL,
): Promise<JoinRoomResponse> {
  const roomId = roomIdFrom(url);
  if (!roomId) throw ERR.badRequest('房间号不正确');
  rateLimitJoin(clientIp(request));

  const { room } = await loadRoom(env, roomId);
  if (room.status === 'ended') throw ERR.roomEnded();

  // 两种加入方式：登录 token，或房间码（邀请码）。
  const trashToken = request.headers.get('X-Trash-Token');
  const code = url.searchParams.get('code') ?? request.headers.get('X-Room-Code');
  let user = trashToken ? await verifyTrashToken(env, trashToken) : null;
  if (!user) {
    if (!code || code !== room.roomCode) throw ERR.noAuth('请输入正确的房间码');
    user = { name: `guest_${genRoomCode()}` , token: ''};
  }

  const body = (await request.json().catch(() => ({}))) as JoinRoomRequest;
  const name = (body.name || user.name || '观众').slice(0, 24);

  await doCall(env, roomId, '/internal/member-join', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ uid: user.name, name, role: 'viewer', connId: '' }),
  });

  const tokenTtl = (Number(env.ROOM_TOKEN_TTL_HOURS) || 2) * 3600;
  const roomToken = await signRoomToken(
    {
      v: 1,
      // 用完整 roomId（code-suffix 形态）签名，不用 URL 路径段：Agora
      // token 接口在客户端没传 channel 时回退 payload.roomId，6 位码会让
      // 观众进错频道（App 端主持人发流用的是完整 roomId）。
      roomId: room.roomId,
      roomCode: room.roomCode,
      uid: user.name,
      name,
      role: 'viewer',
    },
    env.ROOM_TOKEN_SECRET,
    tokenTtl,
  );

  const iceServers = await generateIceServers(env);
  const state = await loadRoom(env, roomId);
  const chatHistory = (await getChatHistory(env, roomId)).slice(-50);

  return {
    roomToken,
    iceServers,
    room: state.room,
    agora: { enabled: agoraConfigured(env) },
    // 必须标 self：客户端拿 members 里的 self 认自己，缺了会退化成
    // members.first（房主），观众会被误判成主持人。
    members: state.members.map((m) => ({ ...m, self: m.uid === user!.name })),
    chatHistory,
  };
}

async function getChatHistory(env: Env, roomId: string): Promise<ChatMessage[]> {
  const res = await doCall(env, roomId, '/internal/state');
  const data = (await res.json().catch(() => null)) as { chatHistory?: ChatMessage[] } | null;
  return data?.chatHistory ?? [];
}

async function publish(
  request: Request,
  env: Env,
  _ctx: ExecutionContext,
  url: URL,
): Promise<PublishResponse> {
  const payload = await requireToken(env, request, url);
  const roomId = payload.roomId;
  const { room, members } = await loadRoom(env, roomId);
  if (room.status === 'ended') throw ERR.roomEnded();

  const body = (await request.json()) as PublishRequest;
  if (!body.sdp) throw ERR.badRequest('缺少 SDP');
  // mid 必须原样带过去：SFU 用它把 local track 对到客户端 SDP 的 m-line 上，
  // 客户端加了第二路（麦克风）以后索引会错位。
  const tracks: PublicTrack[] = Array.isArray(body.tracks)
    ? body.tracks.map((t) => ({
        name: t.name,
        kind: t.kind === 'audio' ? 'audio' : 'video',
        ...(t.mid ? { mid: t.mid } : {}),
      }))
    : [{ name: 'screen', kind: 'video' }];
  for (const t of tracks) {
    if (!['screen', 'mic', 'system'].includes(t.name)) throw ERR.badRequest('不支持的 track');
    if (!['video', 'audio'].includes(t.kind)) throw ERR.badRequest('track 类型不正确');
  }

  // 1 对多：**画面**只有主持人或被授权的成员能发。
  // 麦克风不受模式限制 —— 多人实时语音是房间的通用能力，观众开麦
  // 不该被绑在「有人正在共享画面」上。
  const member = members.find((m) => m.uid === payload.uid);
  const publishesScreen = tracks.some((t) => t.name === 'screen');
  // 注意这里判的是「手上已经有一条 screen 轨」，而不是「有任意 track」：
  // 观众先开麦时 member.tracks 里已经有 mic，拿 length > 0 当门槛
  // 会把这个观众的画面权限一并放出去（旧实现的提权口子）。
  const canPublishScreen =
    payload.role === 'host' ||
    payload.role === 'publisher' ||
    room.roomType !== 'one_to_many' ||
    (member?.tracks.some((t) => t.name === 'screen') ?? false);
  if (publishesScreen && !canPublishScreen) {
    throw ERR.forbidden('当前只有主持人可以开始一起看');
  }

  // 串行约束：同一个成员的发布 session 只能有一个进行中的 SDP 交换。
  // 客户端重试时复用同一个发布 session，避免留下孤儿 session。
  // 关键：**绝不**回落到 member.sfuSessionId（那是订阅 session）——
  // 旧实现直接复用它，观众开麦的 publish offer 会 renegotiate 订阅链路，
  // 把 system 音频的 m-line 谈崩（开麦即丢系统声音的根因）。
  let sessionId = member?.sfuPublishSessionId ?? null;

  if (!sessionId) {
    const session = await createSession(env);
    sessionId = session.sessionId;
  }

  // 幽灵 session 兜底：主持人上次共享异常退出（崩溃/杀进程）时
  // unpublish 走不到，DO 里残留旧 session id；SFU 侧 session 30 秒
  // 无媒体即回收，拿死 session 调 publishTracks 会吃 410/404 ——
  // 客户端 CF 链路报「开始共享失败」，而声网链路正常，观众照样有画面。
  // 所以 4xx 一律视为死 session：新建后用**同一个 offer** 重试一次
  // （offer 是对旧 session 的 transceiver 布局做的，新 session 直接吃
  // 同一 offer 没问题），仍失败才放行报错。
  let answer: SessionDescriptionPayload;
  try {
    answer = await publishTracks(env, sessionId, body.sdp, tracks);
  } catch (err) {
    // sfu.ts 抛的 ERR.sfu 带「SFU 410/425...」前缀；网络错误等其他
    // 失败不带状态码，原样抛出，不在这里重试。
    const msg = err instanceof Error ? err.message : String(err);
    if (!/SFU (4\d\d)/.test(msg)) throw err;
    const session = await createSession(env);
    sessionId = session.sessionId;
    answer = await publishTracks(env, sessionId, body.sdp, tracks);
  }

  await doCall(env, roomId, '/internal/publish', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ uid: payload.uid, sessionId, tracks }),
  });

  return { sessionId, sessionDescription: answer };
}

async function subscribe(
  request: Request,
  env: Env,
  _ctx: ExecutionContext,
  url: URL,
): Promise<SubscribeResponse> {
  const payload = await requireToken(env, request, url);
  const roomId = payload.roomId;
  const { room, members } = await loadRoom(env, roomId);
  if (room.status === 'ended') throw ERR.roomEnded();

  const body = (await request.json()) as SubscribeRequest;
  const requested = Array.isArray(body.trackNames) && body.trackNames.length > 0
    ? body.trackNames.filter((n) => typeof n === 'string' && n.length > 0)
    : body.trackName
      ? [body.trackName]
      : [];
  // 同一路重复传没有意义，SFU 会分配重复的远端 track。
  const trackNames = Array.from(new Set(requested));
  if (!body.publisherSessionId || trackNames.length === 0) {
    throw ERR.badRequest('缺少订阅目标');
  }
  if (trackNames.length > 8) throw ERR.badRequest('一次订阅的路数过多');
  for (const name of trackNames) {
    if (!['screen', 'mic', 'system'].includes(name)) throw ERR.badRequest('不支持的 track');
  }
  const publisher = members.find((m) => m.sfuSessionId === body.publisherSessionId);
  if (!publisher) throw ERR.notFound('该路共享已结束');
  if (publisher.uid === payload.uid) throw ERR.badRequest('不能订阅自己的画面');

  // 观众可能已经为别的路建过 session，复用同一个。
  const viewer = members.find((m) => m.uid === payload.uid);
  let sessionId = viewer?.sfuSessionId ?? null;
  if (!sessionId) {
    const session = await createSession(env);
    sessionId = session.sessionId;
  }

  // 一次 tracks/new 批量加多路 remote：SFU 只回一个 offer，
  // 客户端也只做一次 renegotiation。旧客户端仍然可以传单路 trackName。
  // 幽灵轨容错（tolerateErrors）：发布端可能声明了某路（publish_state
  // 只是声明）但 SFU 上没有真实流（例如主持人麦克风归声网、SFU 从未
  // 挂 mic）——SFU 对不存在的轨返回逐轨 errorCode，旧实现整批抛错把
  // screen 一起拖死（Web 观众全黑的根因）。容错模式下失败轨被剔除、
  // 其余照订；全军覆没才抛错。
  const batch = await subscribeTracks(env, sessionId, body.publisherSessionId, trackNames, {
    tolerateErrors: true,
  });
  if (batch.tracks.length < trackNames.length) {
    const got = new Set(batch.tracks.map((t) => t.trackName));
    console.info(
      '订阅剔除失败轨:',
      trackNames.filter((n) => !got.has(n)).join(','),
    );
  }

  // 把观众这一侧的 session 也记进房间，供「不能订阅自己」与离开时清理使用。
  await doCall(env, roomId, '/internal/session', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ uid: payload.uid, sessionId }),
  });

  return {
    sessionId,
    sessionDescription: batch.sessionDescription,
    mid: batch.tracks[0]?.mid ?? '',
    tracks: batch.tracks,
  };
}

async function answer(
  request: Request,
  env: Env,
  _ctx: ExecutionContext,
  url: URL,
): Promise<unknown> {
  await requireToken(env, request, url);
  const body = (await request.json()) as AnswerRequest;
  if (!body.sessionId || !body.sdp) throw ERR.badRequest('缺少 answer SDP');
  await renegotiate(env, body.sessionId, body.sdp);
  return { ok: true };
}

async function leave(request: Request, env: Env, _ctx: ExecutionContext, url: URL): Promise<unknown> {
  const payload = await requireToken(env, request, url);
  const { room, members } = await loadRoom(env, payload.roomId);
  const me = members.find((m) => m.uid === payload.uid);
  // publicMember 暴露的 sfuSessionId = 发布 session（若有）。关掉它；
  // 接收侧 session 不在这里关——DO 只记了接收 session 的占位，SFU 的
  // session 在 30 秒无媒体后自动回收，强行追踪收益不抵复杂度。
  if (room.status !== 'ended') {
    const sid = me?.sfuSessionId;
    if (sid) {
      await closeSession(env, sid).catch(() => null);
    }
  }
  await doCall(env, payload.roomId, '/internal/member-leave', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ uid: payload.uid }),
  });
  return { ok: true };
}

/** 主持人踢人。被踢的人 WS 会被 DO 直接关掉。 */
async function kick(request: Request, env: Env, _ctx: ExecutionContext, url: URL): Promise<unknown> {
  const payload = await requireToken(env, request, url);
  if (payload.role !== 'host') throw ERR.forbidden('只有主持人可以踢人');
  const body = (await request.json().catch(() => ({}))) as { uid?: string };
  if (!body.uid) throw ERR.badRequest('缺少被踢者');
  if (body.uid === payload.uid) throw ERR.badRequest('不能踢出自己');
  await doCall(env, payload.roomId, '/internal/kick', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ actor: payload.uid, uid: body.uid }),
  });
  return { ok: true };
}

async function endRoom(request: Request, env: Env, _ctx: ExecutionContext, url: URL): Promise<unknown> {
  const payload = await requireToken(env, request, url);
  if (payload.role !== 'host') throw ERR.forbidden('只有主持人可以结束房间');
  const { members } = await loadRoom(env, payload.roomId);
  for (const m of members) {
    const sid = m.sfuSessionId;
    if (sid) await closeSession(env, sid).catch(() => null);
  }
  await doCall(env, payload.roomId, '/internal/end', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ actor: payload.uid, reason: '主持人已结束一起看' }),
  });
  return { ok: true };
}

/** WebSocket 直连 DO，房间事件通道。 */
async function ws(
  request: Request,
  env: Env,
  _ctx: ExecutionContext,
  url: URL,
): Promise<Response> {
  const roomId = roomIdFrom(url);
  if (!roomId) throw ERR.badRequest('房间号不正确');
  const token = url.searchParams.get('token');
  if (!token) throw ERR.noAuth('缺少房间凭证');
  // 在这里校验签名，DO 只负责搬运。
  await verifyRoomToken(token, env.ROOM_TOKEN_SECRET);

  const id = env.ROOMS.idFromName(doKey(roomId));
  const target = new URL(`https://do/api/rooms/${encodeURIComponent(roomId)}/ws`);
  target.searchParams.set('token', token);
  return env.ROOMS.get(id).fetch(target.toString(), request);
}
