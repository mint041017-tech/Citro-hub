/**
 * Cloudflare Realtime SFU REST 客户端。
 *
 * 媒体路径：
 *   发布 = 建一个 session，往里加 local track，把客户端 offer 交给 SFU，拿回 answer；
 *   订阅 = 建一个 session，往里加 remote track（指向发布者的 session + trackName），
 *           SFU 返回 offer，客户端 answer 后走 renegotiate 提交。
 *
 * ⚠️ 与方案文档（v1.0）不同的几处，均来自 Cloudflare 官方 OpenAPI 核对：
 *   1. **没有 DELETE session 接口**。OpenAPI 一共 12 条路径，全在
 *      `/apps/{appId}` 下。拆 session 要靠 `PUT tracks/close`（force:true）
 *      再断开 PeerConnection。所以本文件用 [closeSession] 取代 deleteSession。
 *   2. `mid` 必须动态读取（`transceiver.mid`），不能硬编码 "0"。
 *   3. `tracks/new` 的批量必须全 local 或全 remote，单批最多 64 条。
 *   4. HTTP 200 不代表成功：批量响应里每条 track 可能带 errorCode。
 *   5. 同一个 session 的 mutation 必须串行，否则会吃到 HTTP 406。
 *
 * 密钥只在这个文件里出现，绝不返回给客户端。
 */

import { ERR, type IceServer, type PublicTrack, type SessionDescriptionPayload } from './types';

const SFU_HOST = 'https://rtc.live.cloudflare.com';

export interface SfuSession {
  sessionId: string;
}

export interface SubscribeResult {
  sessionDescription: SessionDescriptionPayload;
  /** SFU 在我们 session 里分配的 mid，客户端用它匹配 onTrack。 */
  mid: string;
  trackName: string;
}

export interface SubscribeTracksResult {
  sessionDescription: SessionDescriptionPayload;
  /** 每一路在订阅侧 session 里的 mid，客户端按 trackName 匹配 onTrack。 */
  tracks: Array<{ trackName: string; mid: string }>;
}

interface SfuTrack {
  trackId?: string;
  trackName?: string;
  mid?: string;
  kind?: string;
  status?: string;
  sessionId?: string;
  errorCode?: string;
  errorDescription?: string;
  [k: string]: unknown;
}

interface SfuResponse {
  sessionId?: string;
  sessionDescription?: { sdp?: string; type?: string };
  tracks?: SfuTrack[];
  [k: string]: unknown;
}

export interface SfuEnv {
  CF_REALTIME_APP_ID: string;
  CF_REALTIME_APP_SECRET: string;
}

async function sfuFetch(env: SfuEnv, path: string, init: RequestInit = {}): Promise<SfuResponse> {
  if (!env.CF_REALTIME_APP_ID || !env.CF_REALTIME_APP_SECRET) {
    throw ERR.sfu('未配置 CF_REALTIME_APP_ID / CF_REALTIME_APP_SECRET');
  }
  const url = `${SFU_HOST}/v1/apps/${env.CF_REALTIME_APP_ID}${path}`;
  let res: Response;
  try {
    res = await fetch(url, {
      ...init,
      headers: {
        Authorization: `Bearer ${env.CF_REALTIME_APP_SECRET}`,
        'Content-Type': 'application/json',
        ...(init.headers ?? {}),
      },
    });
  } catch (e) {
    throw ERR.sfu(`SFU 网络错误：${e instanceof Error ? e.message : String(e)}`);
  }
  const text = await res.text();
  if (!res.ok) {
    // 410 = session 已失效，客户端应新建；425 = 连接还没建立好。
    const hint =
      res.status === 410
        ? '（session 已失效，请重建）'
        : res.status === 425
          ? '（连接尚未建立，请稍后重试）'
          : '';
    throw ERR.sfu(`SFU ${res.status}${hint}: ${text.slice(0, 200)}`);
  }
  if (!text) return {};
  try {
    return JSON.parse(text) as SfuResponse;
  } catch {
    throw ERR.sfu('SFU 返回了无法解析的内容');
  }
}

function toSessionDescription(raw: SfuResponse | undefined): SessionDescriptionPayload {
  const sdp = raw?.sessionDescription?.sdp;
  const type = raw?.sessionDescription?.type ?? 'answer';
  if (!sdp) throw ERR.sfu('SFU 未返回 sessionDescription');
  return { sdp, type };
}

/** HTTP 200 也可能有个别 track 失败，逐条检查。 */
function assertTracksOk(tracks: SfuTrack[] | undefined, label: string): void {
  for (const t of tracks ?? []) {
    if (t.errorCode) {
      throw ERR.sfu(
        `${label} ${t.trackName ?? t.mid ?? ''} 失败：${t.errorDescription ?? t.errorCode}`,
      );
    }
  }
}

/** 建一个空 session。注意：这不建立 WebRTC 连接，只是拿 sessionId。 */
export async function createSession(env: SfuEnv): Promise<SfuSession> {
  const res = await sfuFetch(env, '/sessions/new', { method: 'POST' });
  if (!res.sessionId) throw ERR.sfu('SFU 未返回 sessionId');
  return { sessionId: res.sessionId };
}

/**
 * 发布：把客户端的 offer 交给 SFU，声明要发送哪些 local track。
 *
 * [tracks] 里的 mid 必须和客户端 SDP 里的 m-line 序号一致 —— 由客户端
 * 从 `pc.getTransceivers()` 读出来传过来，不能在这里猜。
 */
export async function publishTracks(
  env: SfuEnv,
  sessionId: string,
  offerSdp: string,
  tracks: PublicTrack[],
): Promise<SessionDescriptionPayload> {
  const res = await sfuFetch(env, `/sessions/${sessionId}/tracks/new`, {
    method: 'POST',
    body: JSON.stringify({
      sessionDescription: { type: 'offer', sdp: offerSdp },
      tracks: tracks.map((t, i) => ({
        location: 'local',
        mid: t.mid ?? String(i),
        trackName: t.name,
        kind: t.kind === 'audio' ? 'audio' : 'video',
      })),
    }),
  });
  assertTracksOk(res.tracks, '发布');
  return toSessionDescription(res);
}

/**
 * 订阅：让 SFU 把发布者的某一路 track 推到我们的 session 上。
 * SFU 返回 offer，同时告诉我们它分配的 mid —— 客户端据此匹配 onTrack。
 */
export async function subscribeTrack(
  env: SfuEnv,
  sessionId: string,
  publisherSessionId: string,
  trackName: string,
): Promise<SubscribeResult> {
  const res = await sfuFetch(env, `/sessions/${sessionId}/tracks/new`, {
    method: 'POST',
    body: JSON.stringify({
      tracks: [{ location: 'remote', sessionId: publisherSessionId, trackName }],
    }),
  });
  assertTracksOk(res.tracks, '订阅');
  const assigned = res.tracks?.find((t) => t.trackName === trackName);
  return {
    sessionDescription: toSessionDescription(res),
    mid: assigned?.mid ?? '',
    trackName,
  };
}

/**
 * 批量订阅：一次 `tracks/new` 带上同一个发布者的多路 remote track。
 *
 * Cloudflare 明确支持一个请求里放多条 remote 条目，并只返回一个含全部
 * 新 m-line 的 offer。这样 `system` 音频不再是对已跑起来的 `screen`
 * 做二次 renegotiation —— 那一步失败时正是「画面正常、声音断续」的来源。
 */
export async function subscribeTracks(
  env: SfuEnv,
  sessionId: string,
  publisherSessionId: string,
  trackNames: string[],
  opts?: { tolerateErrors?: boolean },
): Promise<SubscribeTracksResult> {
  const res = await sfuFetch(env, `/sessions/${sessionId}/tracks/new`, {
    method: 'POST',
    body: JSON.stringify({
      tracks: trackNames.map((trackName) => ({
        location: 'remote',
        sessionId: publisherSessionId,
        trackName,
      })),
    }),
  });
  if (opts?.tolerateErrors) {
    // 容错模式：SFU 对不存在的轨在对应条目里给 errorCode（幽灵轨，
    // 例如发布端声明了 mic 但 SFU 上从未挂流）。剔掉失败轨，其余照订；
    // 全军覆没才抛错。正常情况逐条无错，行为与严格模式一致。
    const ok = (res.tracks ?? []).filter((t) => !t.errorCode && t.mid);
    if (ok.length === 0) assertTracksOk(res.tracks, '订阅');
    return {
      sessionDescription: toSessionDescription(res),
      tracks: ok.map((t) => ({ trackName: t.trackName ?? '', mid: t.mid ?? '' })),
    };
  }
  assertTracksOk(res.tracks, '订阅');
  const tracks = trackNames.map((trackName) => {
    const assigned = res.tracks?.find((t) => t.trackName === trackName);
    return { trackName, mid: assigned?.mid ?? '' };
  });
  return { sessionDescription: toSessionDescription(res), tracks };
}

/** 提交订阅侧的 answer，完成 renegotiation。 */
export async function renegotiate(
  env: SfuEnv,
  sessionId: string,
  answerSdp: string,
): Promise<void> {
  await sfuFetch(env, `/sessions/${sessionId}/renegotiate`, {
    method: 'PUT',
    body: JSON.stringify({
      sessionDescription: { type: 'answer', sdp: answerSdp },
    }),
  });
}

/** 关闭一路 track。`force: true` 表示不需要再走一次 offer/answer。 */
export async function closeTrack(
  env: SfuEnv,
  sessionId: string,
  mid: string,
  force = true,
): Promise<void> {
  await sfuFetch(env, `/sessions/${sessionId}/tracks/close`, {
    method: 'PUT',
    body: JSON.stringify({ tracks: [{ mid }], force }),
  });
}

/** 查询 session 状态（排查用，也用来拿 mid 列表以便拆 session）。 */
export async function getSession(env: SfuEnv, sessionId: string): Promise<SfuResponse> {
  return sfuFetch(env, `/sessions/${sessionId}`, { method: 'GET' });
}

/**
 * 拆掉一个 session。
 *
 * Cloudflare 没有 DELETE session 接口：先把所有 track 用 force 关掉，
 * 客户端那边再关掉 PeerConnection，session 自身会因 30 秒无媒体而被回收。
 */
export async function closeSession(env: SfuEnv, sessionId: string): Promise<void> {
  try {
    const info = await getSession(env, sessionId);
    const tracks = info.tracks ?? [];
    if (tracks.length > 0) {
      await sfuFetch(env, `/sessions/${sessionId}/tracks/close`, {
        method: 'PUT',
        body: JSON.stringify({
          tracks: tracks
            .filter((t) => !!t.mid)
            .map((t) => ({ mid: t.mid as string })),
          force: true,
        }),
      });
    }
  } catch (e) {
    // session 可能已经因为断线被回收了，这时候「关掉」的目标已经达成。
    console.info(`关闭 SFU session ${sessionId} 时忽略错误：`, e);
  }
}

/**
 * 生成短期 TURN 凭证。
 *
 * Cloudflare 的 TURN Key Secret 只在服务端用；客户端拿到的是 24 小时有效的
 * username / credential（官方 TTL 上限 48 小时）。响应里第一条是 STUN，
 * 第二条是 TURN，可以直接交给 RTCPeerConnection。
 */
export async function generateIceServers(env: {
  CF_TURN_KEY_ID: string;
  CF_TURN_KEY_SECRET: string;
}): Promise<IceServer[]> {
  if (!env.CF_TURN_KEY_ID || !env.CF_TURN_KEY_SECRET) {
    // 没有 TURN 也能跑通大部分网络（STUN + host / srflx），
    // 但对称 NAT 下会失败，所以这里只降级不报错。
    return <IceServer[]>[{ urls: 'stun:stun.cloudflare.com:3478' }];
  }
  const res = await fetch(
    `${SFU_HOST}/v1/turn/keys/${env.CF_TURN_KEY_ID}/credentials/generate-ice-servers`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.CF_TURN_KEY_SECRET}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ ttl: 24 * 3600 }),
    },
  );
  if (!res.ok) {
    return <IceServer[]>[{ urls: 'stun:stun.cloudflare.com:3478' }];
  }
  const data = (await res.json().catch(() => null)) as
    | { iceServers?: Array<{ urls?: string | string[]; username?: string; credential?: string }> }
    | null;
  const list = data?.iceServers;
  if (!Array.isArray(list) || list.length === 0) {
    return <IceServer[]>[{ urls: 'stun:stun.cloudflare.com:3478' }];
  }

  const out: IceServer[] = [];
  const seen = new Set<string>();
  const push = (s: IceServer) => {
    const key = `${s.urls}|${s.username ?? ''}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push(s);
  };
  for (const s of list) {
    if (!s?.urls) continue;
    push({
      urls: s.urls,
      ...(s.username ? { username: s.username } : {}),
      ...(s.credential ? { credential: s.credential } : {}),
    });
  }
  // 保证至少有一条 STUN 兜底。
  if (!out.length) push({ urls: 'stun:stun.cloudflare.com:3478' });
  return out;
}
