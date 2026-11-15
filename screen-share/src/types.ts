/**
 * Citro 屏幕共享：Worker ↔ Flutter ↔ Durable Object 的共享契约。
 *
 * 这个文件是「单一事实来源」：Flutter 侧的 room_api.dart 必须与这里的
 * 请求 / 响应结构逐字段对齐。改动字段时两边一起改。
 */

// ── 房间 ────────────────────────────────────────────────────────────────

export type RoomType = 'one_to_many' | 'one_to_one' | 'multi_party';
export type RoomStatus = 'waiting' | 'live' | 'ended';
export type MemberRole = 'host' | 'publisher' | 'viewer';

/** 画质档：用户可在 720p / 1080p / 2K 之间选，帧率 30 或 60。 */
export interface Quality {
  width: number;
  height: number;
  frameRate: number;
}

/**
 * 一路已发布的 track。name 是 SFU 里的 trackName，kind 用于 UI 与订阅过滤。
 *
 * `screen` 画面、`mic` 麦克风、`system` 共享内容自带的系统声音（桌面端
 * loopback）。三者可以同时存在，订阅端按 name 区分播放。
 */
export interface TrackInfo {
  name: string;
  kind: 'video' | 'audio';
  /**
   * 客户端 PeerConnection 里这个 track 的 m-line 序号。
   * 必须由客户端从 `pc.getTransceivers()` 读出来传过来 —— 硬编码 "0"
   * 在加了第二路 track（麦克风）后会指错。
   */
  mid?: string;
}

export interface Member {
  uid: string;
  name: string;
  role: MemberRole;
  /**
   * 接收侧 session（订阅时建立）。
   * 旧版本同时拿它当发布 session；分离后语义收窄为「我订阅用的
   * session」，观众开麦的发布 offer 走 [sfuPublishSessionId]，不再
   * renegotiate 订阅链路（那会把 system 音频的 m-line 谈崩）。
   */
  sfuSessionId: string | null;
  /**
   * 发布侧 session（/publish 时建立）。发布者的画面/声音从这里发出，
   * 其它成员订阅时以它为目标。null = 当前没有发布任何媒体。
   */
  sfuPublishSessionId: string | null;
  /** 该成员正在发布的 track 列表。 */
  tracks: TrackInfo[];
  joinedAt: number;
  /** 是否在线（WebSocket 是否连着）。 */
  online: boolean;
}

/** ICE server 结构（workers-types 不带 RTCIceServer，这里自己定义）。 */
export interface IceServer {
  urls: string | string[];
  username?: string;
  credential?: string;
}

export interface RoomState {
  roomId: string;
  /** 6 位数字房间码，用于邀请。 */
  roomCode: string;
  title: string;
  roomType: RoomType;
  status: RoomStatus;
  hostUid: string;
  quality: Quality;
  maxViewers: number;
  createdAt: number;
  expiresAt: number;
  /** 主持人选中的画质，新加入的共享者默认沿用。 */
  members: Record<string, Member>;
  /** 已结束的房间集合（roomId），用于吊销未过期的旧 token。 */
  ended: boolean;
}

// ── REST 请求 / 响应 ────────────────────────────────────────────────────

export interface CreateRoomRequest {
  title?: string;
  roomType?: RoomType;
  quality?: Partial<Quality>;
}

/** 媒体链路配置：Agora 可用时客户端优先走声网，否则用 Cloudflare。 */
export interface MediaConfig {
  agora: { enabled: boolean };
}

export interface CreateRoomResponse {
  roomId: string;
  roomCode: string;
  roomToken: string;
  iceServers: IceServer[];
  expiresAt: number;
  room: PublicRoom;
  agora: MediaConfig['agora'];
  /** 创建者此时是房间里唯一的成员（host），客户端直接拿来渲染成员列表。 */
  members: PublicMember[];
}

export interface JoinRoomRequest {
  name?: string;
}

export interface JoinRoomResponse {
  roomToken: string;
  iceServers: IceServer[];
  room: PublicRoom;
  agora: MediaConfig['agora'];
  members: PublicMember[];
  chatHistory: ChatMessage[];
}

export interface PublishRequest {
  sdp: string;
  type: string;
  tracks: TrackInfo[];
}

export interface PublishResponse {
  sessionId: string;
  sessionDescription: SessionDescriptionPayload;
}

export interface SubscribeRequest {
  publisherSessionId: string;
  /** 单路订阅（旧客户端）。 */
  trackName?: string;
  /** 批量订阅：一次 tracks/new 把所有路都加上，只回一个 offer。 */
  trackNames?: string[];
}

export interface SubscribeResponse {
  sessionId: string;
  sessionDescription: SessionDescriptionPayload;
  /** 第一路的 mid，兼容旧客户端。 */
  mid: string;
  /** 批量订阅时每一路在订阅侧 session 里的 mid。 */
  tracks?: Array<{ trackName: string; mid: string }>;
}

export interface AnswerRequest {
  sessionId: string;
  sdp: string;
  type: string;
}

export interface SessionDescriptionPayload {
  sdp: string;
  type: string;
}

export interface IceResponse {
  iceServers: IceServer[];
}

export interface PublicTrack {
  name: string;
  kind: 'video' | 'audio';
  /** 发布时客户端报告的 m-line 序号。 */
  mid?: string;
}

export interface PublicMember {
  uid: string;
  name: string;
  role: MemberRole;
  online: boolean;
  tracks: PublicTrack[];
  /**
   * 媒体源（发布）session；订阅时用它定位发布者。没有发布时为 null，
   * 但兜底回落到内部接收 session（旧格式兼容，见 Room.publicMember）。
   */
  sfuSessionId: string | null;
  /**
   * 纯发布 session（不含兜底）。Worker /publish 用它做「重试复用」
   * 判断；观众开麦的 publish offer 走这条 session，不再 renegotiate
   * 订阅链路。
   */
  sfuPublishSessionId?: string | null;
  self?: boolean;
}

export interface PublicRoom {
  roomId: string;
  roomCode: string;
  title: string;
  roomType: RoomType;
  status: RoomStatus;
  hostUid: string;
  quality: Quality;
  maxViewers: number;
  createdAt: number;
  expiresAt: number;
  viewerCount: number;
  publisherCount: number;
}

export interface ChatMessage {
  id: string;
  uid: string;
  name: string;
  text: string;
  at: number;
  /** true 表示这是本地刚发出的消息，用于乐观渲染去重。 */
  local?: boolean;
}

// ── WebSocket 事件 ──────────────────────────────────────────────────────

/** Server → Client */
export type ServerEvent =
  | { type: 'hello'; self: PublicMember; room: PublicRoom; members: PublicMember[]; chatHistory: ChatMessage[] }
  | { type: 'member_joined'; member: PublicMember }
  | { type: 'member_left'; uid: string }
  | { type: 'publisher_joined'; uid: string; name: string; sessionId: string; tracks: PublicTrack[] }
  | { type: 'publisher_left'; uid: string; sessionId: string }
  | { type: 'track_added'; uid: string; sessionId: string; track: PublicTrack }
  | { type: 'track_removed'; uid: string; sessionId: string; trackName: string }
  | { type: 'viewer_count'; count: number }
  | { type: 'room_ended'; reason?: string }
  | { type: 'chat'; message: ChatMessage }
  | { type: 'quality_changed'; quality: Quality }
  | { type: 'error'; code: string; message: string }
  | { type: 'pong'; at: number };

/** Client → Server（p2p_* 已随 P2P 直连下线删除；DO 收到会回 p2p_retired） */
export type ClientEvent =
  | { type: 'ping'; at: number }
  | { type: 'chat'; text: string }
  | { type: 'publish_state'; tracks: PublicTrack[] }
  | { type: 'quality'; quality: Quality }
  | { type: 'request_publish' }
  | { type: 'grant_publish'; uid: string }
  | { type: 'kick'; uid: string }
  | { type: 'end_room' };

// ── 内部错误 ────────────────────────────────────────────────────────────

export class ApiError extends Error {
  code: string;
  status: number;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export const ERR = {
  noAuth: (msg = '未登录') => new ApiError(401, 'unauthorized', msg),
  badRequest: (msg = '请求参数有误') => new ApiError(400, 'bad_request', msg),
  notFound: (msg = '房间不存在') => new ApiError(404, 'not_found', msg),
  roomEnded: (msg = '房间已结束') => new ApiError(409, 'room_ended', msg),
  roomFull: (msg = '房间已满') => new ApiError(409, 'room_full', msg),
  forbidden: (msg = '没有权限') => new ApiError(403, 'forbidden', msg),
  sfu: (msg = '媒体服务异常') => new ApiError(502, 'sfu_error', msg),
  agora: (msg = '声网服务异常') => new ApiError(502, 'agora_error', msg),
  rateLimit: (msg = '操作太频繁') => new ApiError(429, 'rate_limited', msg),
};

// ── 环境绑定 ────────────────────────────────────────────────────────────

export interface Env {
  ROOMS: DurableObjectNamespace;
  ASSETS: Fetcher;

  CF_REALTIME_APP_ID: string;
  CF_REALTIME_APP_SECRET: string;
  CF_TURN_KEY_ID: string;
  CF_TURN_KEY_SECRET: string;
  ROOM_TOKEN_SECRET: string;

  /** 声网 Agora：未配置时媒体走 Cloudflare 链路（可后续 secret put 即启用）。 */
  AGORA_APP_ID?: string;
  AGORA_APP_CERT?: string;

  /** trash.js 的地址，用于校验 X-Trash-Token；不配置时放行（仅用于本地 POC）。 */
  TRASH_API_BASE?: string;
  /** 调用 trash.js 时携带的共享密钥，避免被他人冒用。 */
  TRASH_API_SECRET?: string;

  ROOM_MAX_VIEWERS: string;
  ROOM_TTL_HOURS: string;
  ROOM_TOKEN_TTL_HOURS: string;
  HOST_GRACE_MINUTES: string;
  CHAT_HISTORY_LIMIT: string;
}

/** Durable Object 的构造参数（wrangler 注入）。 */
export interface RoomDurableObjectState {
  storage: DurableObjectStorage;
}
