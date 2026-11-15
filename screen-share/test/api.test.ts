/**
 * 端到端信令流程测试：真实跑 Worker + Durable Object，只把 SFU 的 outbound
 * fetch 换成 mock。这样能在没有 Cloudflare 凭据的情况下验证整条链路。
 */
import { beforeEach, describe, expect, it } from 'vitest';
import { SELF, env, fetchMock, runDurableObjectAlarm, runInDurableObject } from 'cloudflare:test';

const ORIGIN = 'https://share.mint1017.cn';
const SFU = 'https://rtc.live.cloudflare.com';
const APP = '/v1/apps/test-app-id';

/**
 * SFU 的 TURN 凭证接口。
 *
 * 必须 `.persist()`：fetchMock 的 interceptor 默认是「一次性」的， reply 完一次
 * 就被消费掉，而 create / join / /api/ice 每次都会调 generateIceServers()。
 * 不 persist 的话，第一个请求（create）就把拦截器用光，后面每个 join 都会
 * 撞上 `net.connect disabled` 直接 500 —— 而靠「拦截器在测试之间泄漏」
 * 捡回来的余量会让结果随测试执行顺序变化，表现为偶发失败。
 */
function mockTurn() {
  fetchMock
    .get(SFU)
    .intercept({
      path: '/v1/turn/keys/test-turn-id/credentials/generate-ice-servers',
      method: 'POST',
    })
    .reply(200, {
      iceServers: [
        { urls: ['turn:turn.cloudflare.com:3478'], username: 'turn-user', credential: 'turn-pass' },
      ],
    })
    .persist();
}

/** 建 SFU session。 */
function mockCreateSession(sessionId: string) {
  fetchMock
    .get(SFU)
    .intercept({ path: `${APP}/sessions/new`, method: 'POST' })
    .reply(200, { sessionId });
}

/** 发布：往 session 里加 local track，SFU 回 answer。 */
function mockPublish(sessionId: string, answerSdp = 'v=0\r\nfake-answer') {
  fetchMock
    .get(SFU)
    .intercept({ path: `${APP}/sessions/${sessionId}/tracks/new`, method: 'POST' })
    .reply(200, {
      sessionId,
      sessionDescription: { type: 'answer', sdp: answerSdp },
      tracks: [{ trackName: 'screen', status: 'active' }],
    });
}

/** 订阅：往 session 里加 remote track，SFU 回 offer。 */
function mockSubscribe(sessionId: string, offerSdp = 'v=0\r\nfake-offer', mid = '5') {
  fetchMock
    .get(SFU)
    .intercept({ path: `${APP}/sessions/${sessionId}/tracks/new`, method: 'POST' })
    .reply(200, {
      sessionId,
      sessionDescription: { type: 'offer', sdp: offerSdp },
      tracks: [{ location: 'remote', trackName: 'screen', mid, status: 'active' }],
    });
}

/** renegotiate：提交 answer。 */
function mockRenegotiate(sessionId: string) {
  fetchMock
    .get(SFU)
    .intercept({ path: `${APP}/sessions/${sessionId}/renegotiate`, method: 'PUT' })
    .reply(200, { sessionId });
}

/**
 * 拆 session。Cloudflare 没有 DELETE session 接口：先查 track 列表，
 * 再用 `tracks/close {force:true}` 全部关掉。
 */
function mockCloseSession(sessionId: string) {
  fetchMock
    .get(SFU)
    .intercept({ path: `${APP}/sessions/${sessionId}`, method: 'GET' })
    .reply(200, {
      tracks: [
        { location: 'local', mid: '0', trackName: 'screen', status: 'active' },
        { location: 'local', mid: '1', trackName: 'mic', status: 'active' },
      ],
    });
  fetchMock
    .get(SFU)
    .intercept({ path: `${APP}/sessions/${sessionId}/tracks/close`, method: 'PUT' })
    .reply(200, { requiresImmediateRenegotiation: false, tracks: [{ mid: '0' }] });
}

async function post(path: string, body?: unknown, headers: Record<string, string> = {}) {
  return SELF.fetch(`${ORIGIN}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

async function get(path: string, headers: Record<string, string> = {}) {
  return SELF.fetch(`${ORIGIN}${path}`, { headers });
}

beforeEach(() => {
  mockTurn();
});

describe('健康检查与静态资源', () => {
  it('/api/health 返回 200', async () => {
    const res = await get('/api/health');
    expect(res.status).toBe(200);
    const data = (await res.json()) as { ok: boolean; service: string };
    expect(data.ok).toBe(true);
    expect(data.service).toBe('citro-screen-share');
  });

  it('未配置的静态路径不抛错', async () => {
    const res = await get('/some-page');
    expect(res.status).toBe(404);
  });
});

describe('创建 → 加入 → 发布 → 订阅 → 结束', () => {
  it('走通完整链路', async () => {
    // 1. 创建房间（本地 POC 模式下 TRASH_API_BASE 为空，走访客放行）
    const createRes = await post(
      '/api/rooms',
      { title: '验收测试', roomType: 'one_to_many', quality: { width: 1920, height: 1080, frameRate: 60 } },
      { 'X-Trash-Token': 'a'.repeat(32) },
    );
    expect(createRes.status).toBe(200);
    const created = (await createRes.json()) as {
      roomId: string;
      roomCode: string;
      roomToken: string;
      iceServers: unknown[];
      room: { quality: { width: number; height: number; frameRate: number } };
    };
    expect(created.roomId).toBeTruthy();
    expect(created.roomCode).toHaveLength(6);
    expect(created.room.quality).toEqual({ width: 1920, height: 1080, frameRate: 60 });
    expect(created.iceServers.length).toBeGreaterThan(0);

    const hostAuth = { Authorization: `Bearer ${created.roomToken}` };

    // 2. 观众用房间码加入。
    //    路径里只给 6 位码（真实用户的输入），验证 DO 用房间码做 key，
    //    不会因此新建一个空房间。
    const joinRes = await post(`/api/rooms/${created.roomCode}/join?code=${created.roomCode}`, {});
    expect(joinRes.status).toBe(200);
    const joined = (await joinRes.json()) as {
      roomToken: string;
      room: { viewerCount: number };
      members: Array<{ uid: string; role: string }>;
    };
    expect(joined.room.viewerCount).toBe(2);
    expect(joined.members).toHaveLength(2);
    const viewerAuth = { Authorization: `Bearer ${joined.roomToken}` };

    // 3. 主持人发布屏幕
    mockCreateSession('sess-host');
    mockPublish('sess-host');
    // mid 必须原样透传到 SFU，客户端加了麦克风以后索引会错位。
    const publishRes = await post(
      `/api/rooms/${created.roomId}/publish`,
      {
        sdp: 'v=0\r\nfake-offer',
        type: 'offer',
        tracks: [
          { name: 'screen', kind: 'video', mid: '2' },
          { name: 'system', kind: 'audio', mid: '4' },
          { name: 'mic', kind: 'audio', mid: '3' },
        ],
      },
      hostAuth,
    );
    expect(publishRes.status).toBe(200);
    const published = (await publishRes.json()) as {
      sessionId: string;
      sessionDescription: { sdp: string; type: string };
    };
    expect(published.sessionId).toBe('sess-host');
    expect(published.sessionDescription.type).toBe('answer');

    // 4. 房间状态里能看到发布者的 sessionId 和 mid
    const stateRes = await get(`/api/rooms/${created.roomId}`, hostAuth);
    const state = (await stateRes.json()) as {
      members: Array<{
        uid: string;
        role: string;
        tracks: Array<{ name: string; mid?: string }>;
        sfuSessionId: string | null;
      }>;
    };
    const hostMember = state.members.find((m) => m.role === 'host');
    expect(hostMember?.sfuSessionId).toBe('sess-host');
    expect(hostMember?.tracks).toHaveLength(3);
    expect(hostMember?.tracks.find((t) => t.name === 'screen')?.mid).toBe('2');
    expect(hostMember?.tracks.find((t) => t.name === 'system')?.mid).toBe('4');
    expect(hostMember?.tracks.find((t) => t.name === 'mic')?.mid).toBe('3');

    // 5. 观众订阅主持人的屏幕
    mockCreateSession('sess-viewer');
    mockSubscribe('sess-viewer');
    const subRes = await post(
      `/api/rooms/${created.roomId}/subscribe`,
      { publisherSessionId: 'sess-host', trackName: 'screen' },
      viewerAuth,
    );
    expect(subRes.status).toBe(200);
    const sub = (await subRes.json()) as {
      sessionId: string;
      sessionDescription: { sdp: string; type: string };
      mid: string;
    };
    expect(sub.sessionId).toBe('sess-viewer');
    expect(sub.sessionDescription.type).toBe('offer');
    // 客户端要用这个 mid 匹配 onTrack，必须由 SFU 回传而不是猜。
    expect(sub.mid).toBe('5');

    // 6. 观众提交 answer
    mockRenegotiate('sess-viewer');
    const answerRes = await post(
      `/api/rooms/${created.roomId}/answer`,
      { sessionId: 'sess-viewer', sdp: 'v=0\r\nfake-answer', type: 'answer' },
      viewerAuth,
    );
    expect(answerRes.status).toBe(200);

    // 7. 观众不能订阅自己
    const selfSub = await post(
      `/api/rooms/${created.roomId}/subscribe`,
      { publisherSessionId: 'sess-viewer', trackName: 'screen' },
      viewerAuth,
    );
    expect(selfSub.status).toBe(400);

    // 8. 观众不能结束房间
    const badEnd = await post(`/api/rooms/${created.roomId}/end`, {}, viewerAuth);
    expect(badEnd.status).toBe(403);

    // 9. 主持人结束房间：会顺手关掉所有 SFU session
    mockCloseSession('sess-host');
    mockCloseSession('sess-viewer');
    const endRes = await post(`/api/rooms/${created.roomId}/end`, {}, hostAuth);
    expect(endRes.status).toBe(200);

    // 10. 结束后旧 token 不能再加入
    const rejoin = await post(`/api/rooms/${created.roomId}/join?code=${created.roomCode}`, {});
    expect(rejoin.status).toBe(409);
  });

  it('只用 6 位房间码也能找到同一个房间', async () => {
    const createRes = await post('/api/rooms', {}, { 'X-Trash-Token': 'a'.repeat(32) });
    const created = (await createRes.json()) as { roomId: string; roomCode: string };
    const res = await post(`/api/rooms/${created.roomCode}/join?code=${created.roomCode}`, {});
    expect(res.status).toBe(200);
    const data = (await res.json()) as { room: { roomId: string; viewerCount: number } };
    // 必须落回创建时的那个房间，而不是新建一个。
    expect(data.room.roomId).toBe(created.roomId);
    expect(data.room.viewerCount).toBe(2);
  });

  it('错误的房间码会被拒', async () => {
    const createRes = await post('/api/rooms', {}, { 'X-Trash-Token': 'b'.repeat(32) });
    const created = (await createRes.json()) as { roomId: string };
    const res = await post(`/api/rooms/${created.roomId}/join?code=000000`, {});
    expect(res.status).toBe(401);
  });

  it('未登录且没有房间码不能创建房间之外的受保护接口', async () => {
    const res = await get('/api/rooms/999999-zz');
    expect(res.status).toBe(401);
  });

  it('签名段无法解码的 room token 返回 400 而不是 500', async () => {
    // 回归：fromBase64url 用的是 atob，非法字符会抛 DOMException。
    // 之前它没被 try 包住，被 index.ts 的兜底 catch 压成 500，
    // 还把 atob 的原始错误文本原样返回给客户端。
    for (const token of ['a.b.!!!', 'a.b.c', 'a.b.%BAD%']) {
      const res = await get(`/api/rooms/999999-zz?token=${encodeURIComponent(token)}`);
      expect(res.status, `token=${token}`).toBe(400);
      const data = (await res.json()) as { code?: string; err?: string };
      expect(data.code).toBe('bad_request');
      expect(data.err).not.toContain('atob');
    }
  });

  it('订阅不存在的发布者返回 404', async () => {
    const createRes = await post('/api/rooms', {}, { 'X-Trash-Token': 'c'.repeat(32) });
    const created = (await createRes.json()) as { roomId: string; roomToken: string };
    const res = await post(
      `/api/rooms/${created.roomId}/subscribe`,
      { publisherSessionId: 'nope', trackName: 'screen' },
      { Authorization: `Bearer ${created.roomToken}` },
    );
    expect(res.status).toBe(404);
  });
});

describe('WebSocket 事件通道', () => {
  it('连接后立刻收到 hello 快照（含自己、成员、聊天记录）', async () => {
    const createRes = await post('/api/rooms', {}, { 'X-Trash-Token': 'f'.repeat(32) });
    const created = (await createRes.json()) as { roomId: string; roomToken: string };

    // DO 靠 Upgrade 头判断这是不是 WS 升级；SELF.fetch 默认不带。
    const res = await SELF.fetch(
      `${ORIGIN}/api/rooms/${created.roomId}/ws?token=${encodeURIComponent(created.roomToken)}`,
      { headers: { Upgrade: 'websocket' } },
    );
    expect(res.status).toBe(101);
    const ws = res.webSocket;
    expect(ws).not.toBeNull();
    ws!.accept();

    const hello = await new Promise<Record<string, unknown>>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('hello 超时')), 8000);
      ws!.addEventListener('message', (e) => {
        const data = JSON.parse(String(e.data)) as Record<string, unknown>;
        if (data['type'] === 'hello') {
          clearTimeout(timer);
          resolve(data);
        }
      });
      ws!.addEventListener('error', () => {
        clearTimeout(timer);
        reject(new Error('ws error'));
      });
    });

    expect(hello['self']).toBeTruthy();
    expect(hello['room']).toBeTruthy();
    expect(hello['members']).toHaveLength(1);
    expect(Array.isArray(hello['chatHistory'])).toBe(true);
    ws!.close();
  });

  it('缺少房间凭证时不能建连', async () => {
    const createRes = await post('/api/rooms', {}, { 'X-Trash-Token': 'a'.repeat(32) });
    const created = (await createRes.json()) as { roomId: string };
    const res = await SELF.fetch(`${ORIGIN}/api/rooms/${created.roomId}/ws`);
    expect(res.status).toBe(401);
  });
});

describe('房主断线宽限', () => {
  // F-09：主持人断线后 5 分钟内可重连，房间不被回收。
  // 做法：房主最后一个连接断开时把 DO 闹钟改成 now + HOST_GRACE_MINUTES；
  // 房主重连时设回 expiresAt。闹钟响时房主仍离线 → 回收房间。
  const openWs = async (roomId: string, token: string) => {
    const res = await SELF.fetch(
      `${ORIGIN}/api/rooms/${roomId}/ws?token=${encodeURIComponent(token)}`,
      { headers: { Upgrade: 'websocket' } },
    );
    expect(res.status).toBe(101);
    const ws = res.webSocket!;
    ws.accept();
    return ws;
  };

  /** roomCode 就是 DO 的 name：genRoomId = `${code}-${suffix}`，doKey 取 '-' 之前。 */
  const stubFor = (roomCode: string) => env.ROOMS.get(env.ROOMS.idFromName(roomCode));

  const readAlarm = (stub: ReturnType<typeof stubFor>) =>
    runInDurableObject(stub, async (_instance, state) => state.storage.getAlarm());

  const readStatus = (stub: ReturnType<typeof stubFor>) =>
    runInDurableObject(stub, async (instance) =>
      (instance as unknown as { state: { status: string } }).state.status,
    );

  /** 等 DO 处理完异步回调（Miniflare 上 WS close 不是同步的）。 */
  const waitFor = async (fn: () => Promise<boolean>, what: string) => {
    for (let i = 0; i < 50; i++) {
      if (await fn()) return;
      await new Promise((r) => setTimeout(r, 20));
    }
    throw new Error(`等待超时：${what}`);
  };

  it('房主断线后启动宽限闹钟，到点回收房间', async () => {
    const createRes = await post('/api/rooms', {}, { 'X-Trash-Token': 'g'.repeat(32) });
    const created = (await createRes.json()) as {
      roomId: string;
      roomCode: string;
      roomToken: string;
      expiresAt: number;
    };
    // 先加一个观众：只有还有观众在线时才需要宽限。
    const joinRes = await post(
      `/api/rooms/${created.roomCode}/join?code=${created.roomCode}`,
      { name: '观众' },
      { 'cf-connecting-ip': '198.51.100.2' },
    );
    expect(joinRes.status).toBe(200);

    const stub = stubFor(created.roomCode);
    expect(await readAlarm(stub)).toBe(created.expiresAt);

    const hostWs = await openWs(created.roomId, created.roomToken);
    hostWs.close();
    await waitFor(async () => (await readAlarm(stub)) !== created.expiresAt, '宽限闹钟');

    const grace = (await readAlarm(stub)) as number;
    // 宽限是「现在 + 5 分钟」附近，而不是原来的 12 小时后。
    const nowSec = Date.now() / 1000;
    expect(grace / 1000).toBeGreaterThan(nowSec + 4 * 60);
    expect(grace / 1000).toBeLessThan(nowSec + 6 * 60);

    expect(await runDurableObjectAlarm(stub)).toBe(true);
    expect(await readStatus(stub)).toBe('ended');
  });

  it('房主在宽限内重连，闹钟恢复成到期时间', async () => {
    const createRes = await post('/api/rooms', {}, { 'X-Trash-Token': 'h'.repeat(32) });
    const created = (await createRes.json()) as {
      roomId: string;
      roomCode: string;
      roomToken: string;
      expiresAt: number;
    };
    const joinRes = await post(
      `/api/rooms/${created.roomCode}/join?code=${created.roomCode}`,
      { name: '观众' },
      { 'cf-connecting-ip': '198.51.100.3' },
    );
    expect(joinRes.status).toBe(200);

    const stub = stubFor(created.roomCode);
    const first = await openWs(created.roomId, created.roomToken);
    first.close();
    await waitFor(async () => (await readAlarm(stub)) !== created.expiresAt, '宽限闹钟');

    // 房主重连：闹钟应该被设回到期时间，房间继续活着。
    const second = await openWs(created.roomId, created.roomToken);
    await waitFor(async () => (await readAlarm(stub)) === created.expiresAt, '恢复到期闹钟');
    expect(await readStatus(stub)).not.toBe('ended');
    second.close();
  });

  it('房主只重新 join（不重连 WS）也能撤掉宽限闹钟', async () => {
    const createRes = await post('/api/rooms', {}, { 'X-Trash-Token': 'k'.repeat(32) });
    const created = (await createRes.json()) as {
      roomId: string;
      roomCode: string;
      roomToken: string;
      expiresAt: number;
    };
    const joinRes = await post(
      `/api/rooms/${created.roomCode}/join?code=${created.roomCode}`,
      { name: '观众' },
      { 'cf-connecting-ip': '198.51.100.4' },
    );
    expect(joinRes.status).toBe(200);

    const stub = stubFor(created.roomCode);
    const hostWs = await openWs(created.roomId, created.roomToken);
    hostWs.close();
    await waitFor(async () => (await readAlarm(stub)) !== created.expiresAt, '宽限闹钟');

    // 房主带着自己的 trash token 重新 join，但不开 WS。
    // POC 模式下 uid = guest_<token 前 6 位>，和创建时一致。
    const rejoin = await post(
      `/api/rooms/${created.roomCode}/join?code=${created.roomCode}`,
      { name: '房主' },
      { 'X-Trash-Token': 'k'.repeat(32), 'cf-connecting-ip': '198.51.100.5' },
    );
    expect(rejoin.status).toBe(200);
    await waitFor(async () => (await readAlarm(stub)) === created.expiresAt, '恢复到期闹钟');
  });
});

describe('画质参数', () => {
  it('非法画质回落到 720p30', async () => {
    const res = await post(
      '/api/rooms',
      { quality: { width: 9999, height: 10, frameRate: 7 } },
      { 'X-Trash-Token': 'd'.repeat(32) },
    );
    const data = (await res.json()) as { room: { quality: { width: number; frameRate: number } } };
    expect(data.room.quality.width).toBe(1280);
    expect(data.room.quality.frameRate).toBe(30);
  });

  it('2K / 60fps 被接受', async () => {
    const res = await post(
      '/api/rooms',
      { quality: { width: 2560, height: 1440, frameRate: 60 } },
      { 'X-Trash-Token': 'e'.repeat(32) },
    );
    const data = (await res.json()) as { room: { quality: { width: number; height: number } } };
    expect(data.room.quality.width).toBe(2560);
    expect(data.room.quality.height).toBe(1440);
  });
});

describe('观众满员', () => {
  // 回归：满员判定原来用 viewerCount()，它把房主也算成一个人，
  // 结果房间实际只能进 49 个观众，和方案里「1 个共享端 + 50 个观众端」对不上。
  // 房主不占名额，50 个观众要都能进，第 51 个才被拒。
  it('房主不占名额：50 个观众都能进，第 51 个被拒', async () => {
    const createRes = await post('/api/rooms', { title: '满员测试' }, { 'X-Trash-Token': 'a'.repeat(32) });
    const created = (await createRes.json()) as { roomCode: string };
    const code = created.roomCode;

    let lastViewerCount = 0;
    for (let i = 0; i < 50; i++) {
      // 每个观众用不同 IP：join 有「每 IP 每 60 秒 20 次」的限流，
      // 50 次 join 若都算同一个 IP，第 21 次会被 429 —— 那是限流在起作用，
      // 不是满员逻辑。真实场景里 50 个观众本来也来自不同 IP。
      const r = await post(`/api/rooms/${code}/join?code=${code}`, { name: '观众' + i }, {
        'cf-connecting-ip': `203.0.113.${i + 1}`,
      });
      expect(r.status, `第 ${i + 1} 个观众应能加入`).toBe(200);
      const rb = (await r.json()) as { room?: { viewerCount?: number } };
      lastViewerCount = rb.room?.viewerCount ?? 0;
    }
    // viewerCount 把房主也算进去，所以 50 个观众时是 51 —— 这正是满员判定
    // 不能用它的原因。
    expect(lastViewerCount).toBe(51);

    const over = await post(
      `/api/rooms/${code}/join?code=${code}`,
      { name: '超额观众' },
      { 'cf-connecting-ip': '203.0.113.250' },
    );
    expect(over.status).toBe(409);
    const body = (await over.json()) as { code: string };
    expect(body.code).toBe('room_full');
  });
});

describe('多人语音：麦克风与画面权限分开', () => {
  it('观众可以只发布麦克风；已有麦克风也不能补发画面', async () => {
    const createRes = await post(
      '/api/rooms',
      { title: '语音权限', roomType: 'one_to_many' },
      { 'X-Trash-Token': '9'.repeat(32) },
    );
    const created = (await createRes.json()) as { roomId: string; roomCode: string };
    const joinRes = await post(`/api/rooms/${created.roomCode}/join?code=${created.roomCode}`, {
      name: '听众甲',
    });
    const joined = (await joinRes.json()) as {
      roomToken: string;
      members: Array<{ name: string; self?: boolean }>;
    };
    // 加入响应必须自带 self 标记：客户端靠它区分「我」是主持人还是观众。
    expect(joined.members.find((m) => m.self)?.name).toBe('听众甲');
    const viewerAuth = { Authorization: `Bearer ${joined.roomToken}` };

    // 只发 mic：允许。旧实现的 `canPublish` 在 1 对多模式下会把这里拦成 403。
    mockCreateSession('sess-voice');
    mockPublish('sess-voice');
    const micRes = await post(
      `/api/rooms/${created.roomId}/publish`,
      {
        sdp: 'v=0\r\nfake-offer',
        type: 'offer',
        tracks: [{ name: 'mic', kind: 'audio', mid: '0' }],
      },
      viewerAuth,
    );
    expect(micRes.status).toBe(200);

    // 状态里角色仍是 viewer：只开麦不算「共享者」，publisherCount 也不该涨。
    const stateRes = await get(`/api/rooms/${created.roomId}`, viewerAuth);
    const state = (await stateRes.json()) as {
      room: { publisherCount: number };
      members: Array<{ name: string; role: string; tracks: Array<{ name: string }> }>;
    };
    const voice = state.members.find((m) => m.name === '听众甲');
    expect(voice?.role).toBe('viewer');
    expect(voice?.tracks.map((t) => t.name)).toEqual(['mic']);
    expect(state.room.publisherCount).toBe(0);

    // 同一个 session 里补发 screen：仍然 403。
    // 旧判定用的是 `tracks.length > 0`，观众先开麦就能把画面权限一起放出去。
    const screenRes = await post(
      `/api/rooms/${created.roomId}/publish`,
      {
        sdp: 'v=0\r\nfake-offer',
        type: 'offer',
        tracks: [
          { name: 'screen', kind: 'video', mid: '0' },
          { name: 'mic', kind: 'audio', mid: '1' },
        ],
      },
      viewerAuth,
    );
    expect(screenRes.status).toBe(403);
  });
});
