/**
 * Room Durable Object：一个房间一个实例。
 *
 * 职责：
 *   - 保存房间状态（成员、发布者、画质、聊天历史、过期时间）；
 *   - 处理房间 WebSocket，广播 member / publisher / chat / viewer_count 事件；
 *   - 提供内部 HTTP 接口给 Worker 调用（Worker 负责调 SFU，DO 不碰密钥）。
 *
 * 媒体本身不过这里：视频 / 音频走 Cloudflare Realtime SFU，
 * 这个 DO 只搬几 KB 的信令。
 */

import {
  ApiError,
  ERR,
  type ChatMessage,
  type ClientEvent,
  type CreateRoomRequest,
  type MemberRole,
  type PublicMember,
  type PublicRoom,
  type PublicTrack,
  type Quality,
  type RoomState,
  type ServerEvent,
} from './types';

const PERSIST_KEY = 'room';

interface ConnectionMeta {
  connId: string;
  uid: string;
  role: MemberRole;
  name: string;
  joinedAt: number;
}

const DEFAULT_QUALITY: Quality = { width: 1280, height: 720, frameRate: 30 };

export class Room implements DurableObject {
  private state: RoomState;
  private conns = new Map<string, ConnectionMeta>();
  private chat: ChatMessage[] = [];
  private env: { ROOM_MAX_VIEWERS: string; CHAT_HISTORY_LIMIT: string; HOST_GRACE_MINUTES: string };

  constructor(
    private ctx: DurableObjectState,
    env: unknown,
  ) {
    const e = (env ?? {}) as Record<string, string>;
    this.env = {
      ROOM_MAX_VIEWERS: e.ROOM_MAX_VIEWERS || '50',
      CHAT_HISTORY_LIMIT: e.CHAT_HISTORY_LIMIT || '50',
      HOST_GRACE_MINUTES: e.HOST_GRACE_MINUTES || '5',
    };
    this.state = this.emptyState('');
  }

  // ── 生命周期 ──────────────────────────────────────────────────────────

  private emptyState(roomId: string): RoomState {
    return {
      roomId,
      roomCode: '',
      title: '',
      roomType: 'one_to_many',
      status: 'waiting',
      hostUid: '',
      quality: { ...DEFAULT_QUALITY },
      maxViewers: Number(this.env.ROOM_MAX_VIEWERS) || 50,
      createdAt: Date.now(),
      expiresAt: 0,
      members: {},
      ended: false,
    };
  }

  /** 从 SQLite 读回状态；首次调用时 state 是空壳。 */
  private async load(): Promise<void> {
    const saved = await this.ctx.storage.get<RoomState>(PERSIST_KEY);
    if (saved) {
      this.state = saved;
      // 兼容旧字段
      if (!this.state.members) this.state.members = {};
      if (typeof this.state.ended !== 'boolean') this.state.ended = this.state.status === 'ended';
    }
    const chat = await this.ctx.storage.get<ChatMessage[]>('chat');
    if (chat) this.chat = chat;
  }

  private async persist(): Promise<void> {
    await this.ctx.storage.put(PERSIST_KEY, this.state);
    await this.ctx.storage.put('chat', this.chat);
  }

  async alarm(): Promise<void> {
    await this.load();
    if (this.state.status === 'ended') return;
    // 闹钟有两种来源：到期（expiresAt）和房主离开后的宽限（HOST_GRACE_MINUTES）。
    // 两者都回收房间，只是给观众的提示语不同。
    const host = this.state.members[this.state.hostUid];
    const reason = host && !host.online ? '主持人已断开连接' : '房间已到期';
    this.state.status = 'ended';
    this.state.ended = true;
    await this.persist();
    await this.broadcast({ type: 'room_ended', reason });
    await this.closeAll();
  }

  // ── 入口 ──────────────────────────────────────────────────────────────

  async fetch(request: Request): Promise<Response> {
    await this.load();
    const url = new URL(request.url);
    const path = url.pathname;

    // WebSocket 升级：DO 直接接管房间事件通道。
    if (path.endsWith('/ws') && request.headers.get('Upgrade')?.toLowerCase() === 'websocket') {
      return this.handleWebSocket(request);
    }

    if (request.method !== 'POST' && request.method !== 'GET') {
      return json({ err: 'method not allowed' }, 405);
    }

    try {
      switch (path) {
        // ── Worker → DO 内部接口 ──
        case '/internal/reset':
          return await this.onReset(request);
        case '/internal/member-join':
          return await this.onMemberJoin(request);
        case '/internal/member-leave':
          return await this.onMemberLeave(request);
        case '/internal/publish':
          return await this.onPublish(request);
        case '/internal/session':
          return await this.onSession(request);
        case '/internal/unpublish':
          return await this.onUnpublish(request);
        case '/internal/chat':
          return await this.onChat(request);
        case '/internal/quality':
          return await this.onQuality(request);
        case '/internal/role':
          return await this.onRole(request);
        case '/internal/kick':
          return await this.onKick(request);
        case '/internal/end':
          return await this.onEnd(request);
        case '/internal/state':
          return json({
            room: this.publicRoom(),
            members: this.publicMembers(),
            chatHistory: this.chat,
          });
        case '/internal/push':
          return await this.onPush(request);
        default:
          return json({ err: 'not found' }, 404);
      }
    } catch (e) {
      // ApiError 自带 status / code（满员 409、房间已结束 409、参数错 400…），
      // 必须原样带回去。统一压成 500 会让 Worker 无法把「房间已满」透传给客户端。
      if (e instanceof ApiError) {
        return json({ err: e.message, code: e.code }, e.status);
      }
      const msg = e instanceof Error ? e.message : String(e);
      return json({ err: msg }, 500);
    }
  }

  /** 创建房间（Worker 在 POST /api/rooms 里调用）。 */
  private async onReset(request: Request): Promise<Response> {
    const body = (await request.json()) as CreateRoomRequest & {
      roomId: string;
      roomCode: string;
      hostUid: string;
      hostName: string;
      expiresAt: number;
    };
    const maxViewers = Number(this.env.ROOM_MAX_VIEWERS) || 50;
    this.state = this.emptyState(body.roomId);
    this.state.roomCode = body.roomCode;
    this.state.title = (body.title || '一起看').slice(0, 40);
    this.state.roomType = body.roomType ?? 'one_to_many';
    this.state.hostUid = body.hostUid;
    this.state.quality = { ...DEFAULT_QUALITY, ...(body.quality ?? {}) };
    this.state.maxViewers = maxViewers;
    this.state.createdAt = Date.now();
    this.state.expiresAt = body.expiresAt;
    this.state.members = {
      [body.hostUid]: {
        uid: body.hostUid,
        name: body.hostName,
        role: 'host',
        sfuSessionId: null,
        sfuPublishSessionId: null,
        tracks: [],
        joinedAt: Date.now(),
        // 主持人从创建那一刻起就在房间里；他的 WS 断开时再由
        // onSocketGone 标记离线，这样「观看人数」不会出现 0 人在线的空房。
        online: true,
      },
    };
    this.chat = [];
    await this.persist();
    await this.ctx.storage.setAlarm(body.expiresAt);
    return json({ ok: true, room: this.publicRoom() });
  }

  // ── 成员 ──────────────────────────────────────────────────────────────

  private async onMemberJoin(request: Request): Promise<Response> {
    const body = (await request.json()) as {
      uid: string;
      name: string;
      role: MemberRole;
      connId: string;
    };
    if (this.state.status === 'ended') throw ERR.roomEnded();
    if (!body.uid) throw ERR.badRequest('缺少 uid');

    const existing = this.state.members[body.uid];
    // 房主重连不占新名额；新观众在满员时拒绝。
    // 这里必须用「占名额的人数」而不是 viewerCount()：后者把房主也算进去
    // （为了让「N 人在线」在房主单人时不显示 0），直接拿它当上限会少进一个人。
    if (!existing && body.role !== 'host' && this.occupiedSlots() >= this.state.maxViewers) {
      throw ERR.roomFull();
    }

    this.state.members[body.uid] = {
      uid: body.uid,
      name: body.name || existing?.name || '观众',
      role: existing?.role ?? body.role,
      sfuSessionId: existing?.sfuSessionId ?? null,
      sfuPublishSessionId: existing?.sfuPublishSessionId ?? null,
      tracks: existing?.tracks ?? [],
      joinedAt: existing?.joinedAt ?? Date.now(),
      online: true,
    };
    await this.persist();
    const joined = this.publicMember(body.uid);
    if (joined) await this.broadcast({ type: 'member_joined', member: joined });
    await this.broadcastViewerCount();
    // 房主重新 join（WS 还没连上）也要撤掉宽限闹钟。
    if (body.uid === this.state.hostUid) await this.cancelHostGrace();
    return json({ ok: true, room: this.publicRoom() });
  }

  private async onMemberLeave(request: Request): Promise<Response> {
    const body = (await request.json()) as { uid: string; connId?: string };
    const m = this.state.members[body.uid];
    if (m) {
      m.online = false;
      await this.persist();
      await this.broadcast({ type: 'member_left', uid: body.uid });
      await this.broadcastViewerCount();
    }
    return json({ ok: true });
  }

  // ── 发布 / 订阅状态 ───────────────────────────────────────────────────

  private async onPublish(request: Request): Promise<Response> {
    const body = (await request.json()) as {
      uid: string;
      sessionId: string;
      tracks: PublicTrack[];
    };
    const m = this.state.members[body.uid];
    if (!m) throw ERR.forbidden('成员不存在');
    // 发布 offer 一律写发布 session；订阅 session（sfuSessionId）不碰。
    // 旧实现写 sfuSessionId，观众开麦时 publish offer 直接 renegotiate
    // 订阅链路，把 system 音频的 m-line 谈崩（开麦即丢系统声音的根因）。
    const hadNoSession = !m.sfuPublishSessionId;
    m.sfuPublishSessionId = body.sessionId;
    const known = new Set(m.tracks.map((t) => t.name));
    for (const t of body.tracks ?? []) {
      // mid 要跟着更新：重新发布时 m-line 序号可能和上次不同。
      const existing = m.tracks.find((x) => x.name === t.name);
      if (existing) {
        existing.kind = t.kind;
        existing.mid = t.mid;
      } else if (!known.has(t.name)) {
        m.tracks.push({ name: t.name, kind: t.kind, ...(t.mid ? { mid: t.mid } : {}) });
      }
    }
    // 有多路共享的成员，角色提升为 publisher（主持人保持 host）。
    // 只开麦不算 —— 语音是独立能力，观众开麦后仍然是观众，
    // 否则成员列表会把人标成「共享者」，publisherCount 也会虚高。
    if (this.hasScreen(m.tracks) && m.role === 'viewer') m.role = 'publisher';
    if (!this.hasScreen(m.tracks) && m.role === 'publisher') m.role = 'viewer';
    await this.persist();

    if (hadNoSession && m.tracks.length > 0) {
      await this.broadcast({
        type: 'publisher_joined',
        uid: m.uid,
        name: m.name,
        sessionId: m.sfuPublishSessionId,
        tracks: m.tracks.map((t) => ({ ...t })),
      });
    } else {
      for (const t of body.tracks ?? []) {
        await this.broadcast({
          type: 'track_added',
          uid: m.uid,
          sessionId: m.sfuPublishSessionId!,
          track: { ...t },
        });
      }
    }
    return json({ ok: true, room: this.publicRoom() });
  }

  /**
   * 记录成员的 SFU session。观众为订阅建的 session 也要记下来，
   * 否则「不能订阅自己」和「离开时关 session」都拿不到 sessionId。
   */
  private async onSession(request: Request): Promise<Response> {
    const body = (await request.json()) as { uid: string; sessionId: string };
    const m = this.state.members[body.uid];
    if (!m) throw ERR.forbidden('成员不存在');
    if (!m.sfuSessionId) m.sfuSessionId = body.sessionId;
    await this.persist();
    return json({ ok: true, room: this.publicRoom() });
  }

  private async onUnpublish(request: Request): Promise<Response> {
    const body = (await request.json()) as { uid: string; sessionId?: string; trackNames?: string[] };
    const m = this.state.members[body.uid];
    if (!m) return json({ ok: true });
    const removed = body.trackNames ?? m.tracks.map((t) => t.name);
    m.tracks = m.tracks.filter((t) => !removed.includes(t.name));
    const stillPublishing = m.tracks.length > 0;
    if (!stillPublishing) {
      m.sfuPublishSessionId = null;
      if (m.role === 'publisher') m.role = 'viewer';
    }
    await this.persist();
    await this.broadcast({
      type: 'publisher_left',
      uid: m.uid,
      sessionId: body.sessionId ?? '',
    });
    for (const name of removed) {
      await this.broadcast({ type: 'track_removed', uid: m.uid, sessionId: '', trackName: name });
    }
    return json({ ok: true });
  }

  // ── 聊天 ──────────────────────────────────────────────────────────────

  private async onChat(request: Request): Promise<Response> {
    const body = (await request.json()) as { uid: string; name?: string; text: string };
    const text = String(body.text ?? '').trim().slice(0, 500);
    if (!text) throw ERR.badRequest('消息不能为空');
    const m = this.state.members[body.uid];
    const msg: ChatMessage = {
      id: `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
      uid: body.uid,
      name: body.name ?? m?.name ?? '观众',
      text,
      at: Date.now(),
    };
    const limit = Number(this.env.CHAT_HISTORY_LIMIT) || 50;
    this.chat.push(msg);
    if (this.chat.length > limit) this.chat = this.chat.slice(-limit);
    await this.ctx.storage.put('chat', this.chat);
    await this.broadcast({ type: 'chat', message: msg });
    return json({ ok: true, message: msg });
  }

  // ── 画质 / 角色 / 踢人 / 结束 ─────────────────────────────────────────

  private async onQuality(request: Request): Promise<Response> {
    const body = (await request.json()) as { uid: string; quality: Quality };
    if (body.uid !== this.state.hostUid) throw ERR.forbidden('只有主持人可以调整画质');
    const q = sanitizeQuality(body.quality);
    this.state.quality = q;
    await this.persist();
    await this.broadcast({ type: 'quality_changed', quality: q });
    return json({ ok: true, quality: q });
  }

  private async onRole(request: Request): Promise<Response> {
    const body = (await request.json()) as { actor: string; uid: string; role: MemberRole };
    if (body.actor !== this.state.hostUid) throw ERR.forbidden('只有主持人可以变更角色');
    const m = this.state.members[body.uid];
    if (!m) throw ERR.badRequest('成员不存在');
    m.role = body.role;
    await this.persist();
    const role = this.publicMember(body.uid);
    if (role) await this.broadcast({ type: 'member_joined', member: role });
    return json({ ok: true });
  }

  private async onKick(request: Request): Promise<Response> {
    const body = (await request.json()) as { actor: string; uid: string };
    if (body.actor !== this.state.hostUid) throw ERR.forbidden('只有主持人可以踢人');
    if (body.uid === this.state.hostUid) throw ERR.badRequest('不能踢出主持人');
    await this.broadcast({ type: 'member_left', uid: body.uid });
    this.closeConnectionsFor(body.uid);
    delete this.state.members[body.uid];
    await this.persist();
    await this.broadcastViewerCount();
    return json({ ok: true });
  }

  private async onEnd(request: Request): Promise<Response> {
    const body = (await request.json().catch(() => ({}))) as { actor?: string; reason?: string };
    if (body.actor && body.actor !== this.state.hostUid) throw ERR.forbidden('只有主持人可以结束房间');
    this.state.status = 'ended';
    this.state.ended = true;
    await this.persist();
    await this.broadcast({ type: 'room_ended', reason: body.reason || '主持人已结束一起看' });
    await this.closeAll();
    return json({ ok: true });
  }

  /** Worker 主动向房间推一条事件（例如 SFU 侧通知）。 */
  private async onPush(request: Request): Promise<Response> {
    const event = (await request.json()) as ServerEvent;
    await this.broadcast(event);
    return json({ ok: true });
  }

  // ── WebSocket ─────────────────────────────────────────────────────────

  private async handleWebSocket(request: Request): Promise<Response> {
    const token = new URL(request.url).searchParams.get('token');
    // token 的签名校验在 Worker 侧已完成；DO 只解析出 uid / role。
    const payload = parseUnverifiedToken(token);
    if (!payload) throw ERR.noAuth('房间凭证无效');

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.ctx.acceptWebSocket(server, [`${payload.roomId}`]);

    const meta: ConnectionMeta = {
      connId: `${Math.random().toString(36).slice(2)}-${Date.now().toString(36)}`,
      uid: payload.uid,
      role: payload.role,
      name: payload.name,
      joinedAt: Date.now(),
    };
    server.serializeAttachment(meta as unknown as string);
    this.conns.set(meta.connId, meta);

    // 重连的人要重新标记为在线：断线时标了离线，而 WS 重连不一定伴随重新 join
    // （房主尤其如此 —— 客户端靠 hello 恢复状态就够了）。不补这一笔的话
    // viewerCount 会一直少算，房主的宽限闹钟也会误以为人没回来。
    await this.load();
    const m = this.state.members[meta.uid];
    if (m && !m.online) {
      m.online = true;
      await this.persist();
      const rejoined = this.publicMember(meta.uid);
      if (rejoined) await this.broadcast({ type: 'member_joined', member: rejoined });
      await this.broadcastViewerCount();
    }

    // 房主回来了：撤掉宽限闹钟，恢复成房间的到期时间。
    if (meta.uid === this.state.hostUid) await this.cancelHostGrace();

    // 连接一建立就推一份完整快照。客户端靠 hello 才知道自己连上了
    // （RoomWs 收到 hello 才置 connected，之后才肯发 chat / quality），
    // 断线重连也靠它补齐发布者列表，不用重新 join。
    try {
      server.send(
        JSON.stringify({
          type: 'hello',
          self: this.publicMember(meta.uid, true),
          room: this.publicRoom(),
          members: this.publicMembers(meta.uid),
          chatHistory: this.chat.slice(-(Number(this.env.CHAT_HISTORY_LIMIT) || 50)),
        }),
      );
    } catch {
      /* 连接已断，close 回调会清理 */
    }

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer): Promise<void> {
    const meta = ws.deserializeAttachment() as unknown as ConnectionMeta | null;
    if (!meta) return;
    let event: ClientEvent;
    try {
      event = JSON.parse(typeof raw === 'string' ? raw : new TextDecoder().decode(raw)) as ClientEvent;
    } catch {
      return;
    }
    // P2P 直连已下线（媒体改走 Agora 优先 + Cloudflare 兜底）。事件类型
    // 是网络上来的任意字符串，类型收窄挡不住老客户端仍在发 p2p_*，
    // 这里按运行时前缀回一个明确的错误让它停手。
    if (event.type.startsWith('p2p_')) {
      send(ws, {
        type: 'error',
        code: 'p2p_retired',
        message: 'P2P 直连已下线，媒体走声网/Cloudflare 转发',
      } satisfies ServerEvent);
      return;
    }
    switch (event.type) {
      case 'ping':
        send(ws, { type: 'pong', at: event.at ?? Date.now() } satisfies ServerEvent);
        break;
      case 'chat':
        await this.load();
        await this.onChat(
          new Request('http://do/internal/chat', {
            method: 'POST',
            body: JSON.stringify({ uid: meta.uid, name: meta.name, text: event.text }),
          }),
        );
        break;
      case 'publish_state':
        await this.load();
        await this.onPublishState(meta.uid, event.tracks);
        break;
      case 'quality':
        await this.load();
        await this.onQuality(
          new Request('http://do/internal/quality', {
            method: 'POST',
            body: JSON.stringify({ uid: meta.uid, quality: event.quality }),
          }),
        );
        break;
      case 'request_publish':
      case 'grant_publish':
        // 还没实现，收到就忽略，避免客户端以为已经生效。
        break;
      case 'kick':
      case 'end_room':
        // 这两个动作需要主持人身份，统一走 Worker 的 REST（那里有 token 校验）。
        send(ws, {
          type: 'error',
          code: 'use_rest',
          message: '该操作请走 REST 接口（/kick 或 /end）',
        } satisfies ServerEvent);
        break;
      default:
        break;
    }
  }

  /**
   * P2P 信令转发已随 P2P 直连功能下线（媒体改走 Agora 优先 +
   * Cloudflare 兜底，转发在服务端做没有意义）。`p2p_*` 事件统一在
   * webSocketMessage 里回 p2p_retired 错误，老客户端收到就停手。
   */

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    await this.onSocketGone(ws, code, reason);
  }

  async webSocketError(ws: WebSocket, error: unknown): Promise<void> {
    await this.onSocketGone(ws, 1011, String(error));
  }

  /**
   * 房主重新上线（WS 重连，或重新 `join`）：撤掉「房主离开」的宽限闹钟，
   * 恢复成房间的到期时间。两个入口都要调 —— 漏掉 join 那条的话，
   * 房主只重连了 HTTP 没重连 WS 时，房间照样会被回收。
   */
  private async cancelHostGrace(): Promise<void> {
    if (this.state.status === 'ended') return;
    await this.ctx.storage.setAlarm(this.state.expiresAt);
  }

  private async onSocketGone(ws: WebSocket, _code: number, _reason: string): Promise<void> {
    const meta = ws.deserializeAttachment() as unknown as ConnectionMeta | null;
    if (!meta) return;
    this.conns.delete(meta.connId);
    // 同一个用户可能有多个连接（多端同时在线），只在最后一个断开时标记离线。
    const stillOnline = [...this.conns.values()].some((c) => c.uid === meta.uid);
    if (!stillOnline) {
      await this.load();
      const m = this.state.members[meta.uid];
      if (m?.online) {
        m.online = false;
        await this.persist();
        await this.broadcast({ type: 'member_left', uid: meta.uid });
        await this.broadcastViewerCount();
        // 房主离开：给 TA 一段宽限时间重连（HOST_GRACE_MINUTES），超时就回收，
        // 免得观众对着一个没有主持人的房间一直等。只有还有观众在线才需要宽限，
        // 没人的房间等到期即可。
        // 注意 setAlarm 会覆盖掉原来的到期闹钟；房主重连时再设回来。
        if (
          meta.uid === this.state.hostUid &&
          this.state.status !== 'ended' &&
          this.occupiedSlots() > 0
        ) {
          const graceMs = (Number(this.env.HOST_GRACE_MINUTES) || 5) * 60_000;
          await this.ctx.storage.setAlarm(Date.now() + graceMs);
        }
      }
    }
  }

  private async onPublishState(uid: string, tracks: PublicTrack[]): Promise<void> {
    const m = this.state.members[uid];
    if (!m) return;
    // publish_state 的语义是「这是我当前的完整 track 列表」，所以整体替换；
    // 但要保住 mid —— 它只由客户端上报，冲掉之后订阅方就匹配不上 onTrack。
    const prevMid = new Map(m.tracks.map((t) => [t.name, t.mid]));
    const prevNames = new Set(m.tracks.map((t) => t.name));
    m.tracks = tracks.map((t) => ({
      name: t.name,
      kind: t.kind,
      ...(t.mid ? { mid: t.mid } : prevMid.get(t.name) ? { mid: prevMid.get(t.name) } : {}),
    }));
    if (this.hasScreen(m.tracks) && m.role === 'viewer') m.role = 'publisher';
    if (!this.hasScreen(m.tracks) && m.role === 'publisher') m.role = 'viewer';
    await this.persist();

    // 必须广播 diff：客户端的「停止共享 / 开麦 / 关共享留麦」都只走
    // publish_state，不广播的话其它端不知道画面没了，会一直挂着最后一帧。
    // 事件形状和 onPublish 保持一致，客户端不需要两套解析。
    const nextNames = new Set(m.tracks.map((t) => t.name));
    // 广播里的 sessionId 必须是发布 session：订阅方拿它当订阅目标。
    const pubSession = m.sfuPublishSessionId ?? '';
    if (prevNames.size === 0 && nextNames.size > 0) {
      // 从「没有发布」到「有发布」整条给一次 publisher_joined，和 onPublish
      // 的分支保持一致：订阅方先建好这一路再收 track，不会丢首帧。
      await this.broadcast({
        type: 'publisher_joined',
        uid: m.uid,
        name: m.name,
        sessionId: pubSession,
        tracks: m.tracks.map((t) => ({ ...t })),
      });
    } else if (prevNames.size > 0 && nextNames.size === 0) {
      await this.broadcast({ type: 'publisher_left', uid: m.uid, sessionId: pubSession });
    } else {
      for (const t of m.tracks) {
        if (prevNames.has(t.name)) continue;
        await this.broadcast({
          type: 'track_added',
          uid: m.uid,
          sessionId: pubSession,
          track: { ...t },
        });
      }
      for (const name of prevNames) {
        if (nextNames.has(name)) continue;
        await this.broadcast({ type: 'track_removed', uid: m.uid, sessionId: '', trackName: name });
      }
    }
  }

  // ── 广播 ──────────────────────────────────────────────────────────────

  private async broadcast(event: ServerEvent): Promise<void> {
    const payload = JSON.stringify(event);
    for (const ws of this.ctx.getWebSockets()) {
      const meta = ws.deserializeAttachment() as unknown as ConnectionMeta | null;
      if (!meta) continue;
      // hello 只在建立连接时发，不参与广播。
      try {
        ws.send(payload);
      } catch {
        /* 连接已断，close 回调会清理 */
      }
    }
  }

  private async broadcastViewerCount(): Promise<void> {
    await this.broadcast({ type: 'viewer_count', count: this.viewerCount() });
  }

  private closeConnectionsFor(uid: string): void {
    for (const ws of this.ctx.getWebSockets()) {
      const meta = ws.deserializeAttachment() as unknown as ConnectionMeta | null;
      if (meta?.uid === uid) {
        try {
          ws.close(4000, 'kicked');
        } catch {
          /* ignore */
        }
      }
    }
  }

  private async closeAll(): Promise<void> {
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.close(4001, 'room ended');
      } catch {
        /* ignore */
      }
    }
    await this.ctx.storage.deleteAll();
    // 这里原来还设了一个 60 秒后的 alarm「做最后清理」，但 alarm() 开头
    // 就会因为 status === 'ended' 直接返回 —— 既不会清理，又会把 DO 唤醒
    // 一次（storage 已空，load() 还会重建一个空房间）。所以删掉。
  }

  // ── 视图 ──────────────────────────────────────────────────────────────

  private viewerCount(): number {
    return Object.values(this.state.members).filter((m) => m.online).length;
  }

  /** 真正占用观众名额的人数：房主不占名额。满员判定用这个，不要用 viewerCount()。 */
  private occupiedSlots(): number {
    return Object.values(this.state.members).filter((m) => m.online && m.role !== 'host').length;
  }

  /** 只算正在发画面的成员。只开麦的观众不算「有人在共享」。 */
  private publisherCount(): number {
    return Object.values(this.state.members).filter((m) => this.hasScreen(m.tracks)).length;
  }

  private hasScreen(tracks: PublicTrack[]): boolean {
    return tracks.some((t) => t.name === 'screen');
  }

  private publicMember(uid: string, self = false): PublicMember | null {
    const m = this.state.members[uid];
    if (!m) return null;
    return {
      uid: m.uid,
      name: m.name,
      role: m.role,
      online: m.online,
      tracks: m.tracks.map((t) => ({ ...t })),
      // 订阅方要用「发布 session」找媒体源；这里对外统一暴露发布侧
      // （sfuSessionId 是旧字段名，语义收窄为发布 session + 兜底）。
      // 纯发布 session 走 sfuPublishSessionId，/publish 用它判断复用。
      sfuSessionId: m.sfuPublishSessionId ?? m.sfuSessionId,
      sfuPublishSessionId: m.sfuPublishSessionId,
      self,
    };
  }

  private publicMembers(selfUid?: string): PublicMember[] {
    return Object.keys(this.state.members)
      .map((uid) => this.publicMember(uid, uid === selfUid))
      .filter((m): m is PublicMember => m !== null);
  }

  private publicRoom(): PublicRoom {
    return {
      roomId: this.state.roomId,
      roomCode: this.state.roomCode,
      title: this.state.title,
      roomType: this.state.roomType,
      status: this.state.status,
      hostUid: this.state.hostUid,
      quality: { ...this.state.quality },
      maxViewers: this.state.maxViewers,
      createdAt: this.state.createdAt,
      expiresAt: this.state.expiresAt,
      viewerCount: this.viewerCount(),
      publisherCount: this.publisherCount(),
    };
  }
}

// ── 工具 ────────────────────────────────────────────────────────────────

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}

function send(ws: WebSocket, event: ServerEvent): void {
  try {
    ws.send(JSON.stringify(event));
  } catch {
    /* ignore */
  }
}

/** 解析 JWT 的 payload 但不校验签名 —— DO 只在前置 Worker 校验过后才收到连接。 */
function parseUnverifiedToken(token: string | null): {
  roomId: string;
  uid: string;
  role: MemberRole;
  name: string;
} | null {
  if (!token) return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const pad = parts[1].length % 4 === 0 ? '' : '='.repeat(4 - (parts[1].length % 4));
    const bin = atob(parts[1].replace(/-/g, '+').replace(/_/g, '/') + pad);
    const obj = JSON.parse(new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0))));
    if (!obj.roomId || !obj.uid) return null;
    return {
      roomId: String(obj.roomId),
      uid: String(obj.uid),
      role: (obj.role as MemberRole) || 'viewer',
      name: String(obj.name || '观众'),
    };
  } catch {
    return null;
  }
}

export function sanitizeQuality(q: Partial<Quality> | undefined): Quality {
  const width = clampInt(q?.width, 1280, [1280, 1920, 2560]);
  const height = clampInt(q?.height, 720, [720, 1080, 1440]);
  const frameRate = clampInt(q?.frameRate, 30, [30, 60]);
  return { width, height, frameRate };
}

function clampInt(v: number | undefined, fallback: number, allowed: number[]): number {
  const n = typeof v === 'number' && Number.isFinite(v) ? Math.round(v) : fallback;
  return allowed.includes(n) ? n : fallback;
}

/** 给 Worker 用的类型补充（避免循环 import 的类型断裂）。 */
export type { IceServer, Member, Quality, RoomType } from './types';
