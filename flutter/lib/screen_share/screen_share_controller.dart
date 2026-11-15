import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/orientation.dart';
import '../services/platform.dart' as platform;
import '../services/prefs.dart';
import '../theme/breakpoints.dart';
import 'agora_client.dart';
import 'danmaku_bridge.dart';
import 'room_api.dart';
import 'room_models.dart';
import 'room_ws.dart';
import 'screen_capture.dart';
import 'share_quality.dart';
import 'sfu_client.dart';

/// 房间控制器：把 REST（进房 / SDP 交换）、WebSocket（房间事件）和
/// SFU（媒体收发）三条链路收成一个可监听的状态机。
///
///  UI 只读状态、只调方法，不直接碰 [RoomApi] / [RoomWs] / [SfuClient]。
class ScreenShareController extends ChangeNotifier {
  ScreenShareController();

  // ── 可观察状态 ────────────────────────────────────────────────────────

  RoomInfo? _room;
  List<RoomMember> _members = <RoomMember>[];
  List<ChatMessage> _chat = <ChatMessage>[];
  bool _busy = false;
  String? _error;
  bool _publishing = false;
  bool _wsConnected = false;
  bool _ended = false;
  String? _endReason;
  bool _miniWindow = false;
  ShareQuality _quality = ShareQuality.fallback;
  double _systemVolume = 1;
  double _viewerVolume = 1;
  bool _fullscreen = false;
  String? _selfUid;
  String? _roomId;
  String? _roomToken;
  List<Map<String, dynamic>> _iceServers = <Map<String, dynamic>>[];

  RoomInfo? get room => _room;
  List<RoomMember> get members => List<RoomMember>.unmodifiable(_members);
  List<ChatMessage> get chat => List<ChatMessage>.unmodifiable(_chat);
  bool get busy => _busy;
  String? get error => _error;
  bool get publishing => _publishing;
  bool get wsConnected => _wsConnected;
  bool get ended => _ended;
  String? get endReason => _endReason;

  /// 小窗开关。放在控制器里而不是页面里，这样跳页 / 返回时不丢状态。
  bool get miniWindow => _miniWindow;

  ShareQuality get quality => _quality;

  /// 共享画面里系统声音的音量（0–1）。
  double get systemVolume => _systemVolume;

  /// 观众端：远端音量（0–1）。作用于远端的 `system` 轨（和网页观看端
  /// 的单一音量语义一致）。发布者自己的系统声音量见 [systemVolume]。
  double get viewerVolume => _viewerVolume;

  /// 观众端是否处于全屏放映。
  bool get fullscreen => _fullscreen;

  /// 当前这条共享是否真的带系统声音。没在共享、采集没拿到 loopback、
  /// 或旧版 Worker 不认 `system` 轨时都是 false，设置里的滑杆会禁用。
  bool get hasSystemAudio => _publishing && (_sfu?.hasSystemAudio ?? false);

  String? get selfUid => _selfUid;
  String? get roomId => _roomId;
  bool get inRoom => _room != null;
  bool get isHost => _room?.hostUid != null && _room?.hostUid == _selfUid;

  /// 主持人当前是否已开麦（声网发布链已含麦克风）。观众恒为 false，
  /// 也没有开麦入口——只有主持端有麦，观众说话走文字聊天。
  bool get micOn => _micOn;

  /// 开/闭麦请求进行中（防连点）。
  bool get micBusy => _micBusy;

  /// 正在共享**画面**的其他成员（不含自己）。
  ///
  /// 「主画面」和发布者切换条只该列出有 screen 轨的人；老版本客户端
  /// 还会发 mic 轨，那些成员不会出现在这里。
  List<RoomMember> get remotePublishers => _members
      .where((m) => m.hasScreen && m.uid != _selfUid)
      .toList(growable: false);

  /// 主画面该显示谁：优先有 screen 的发布者。
  RoomMember? get mainPublisher {
    final list = remotePublishers;
    if (list.isEmpty) return null;
    for (final m in list) {
      if (m.hasScreen) return m;
    }
    return list.first;
  }

  /// 本地预览的 renderer（主持人正在共享时才有）。
  RTCVideoRenderer? get localRenderer => _localRenderer;

  /// 主画面的 renderer：远端优先；没有远端时退回本地预览。
  RTCVideoRenderer? get mainRenderer {
    final publisher = mainPublisher;
    if (publisher != null && publisher.hasScreen) {
      return rendererFor(publisher.uid, 'screen');
    }
    return _localRenderer;
  }

  /// 当前能不能发起共享。Flutter Web 不在内：flutter_webrtc 1.6.3
  /// 的 pubspec 没有声明 web 平台。
  ///
  /// 静态的：只取决于平台，不取决于房间状态，入口页也要用。
  static bool get canPublish => ScreenCapture.canPublish;

  /// 发起共享前会不会弹「整屏 / 单个窗口」选择器。
  bool get canPickSource => ScreenCapture.canPickSource;

  // ── 内部 ──────────────────────────────────────────────────────────────

  RoomWs? _ws;
  SfuClient? _sfu;
  AgoraClient? _agora;

  /// 主持人是否已把画面发到声网（声网原生采集成功启动）。
  /// 与 [_publishing]（CF 链路状态）独立：声网失败时画面只走 CF。
  bool _agoraSharing = false;
  MediaStream? _previewStream;
  RTCVideoRenderer? _localRenderer;
  final Map<String, RTCVideoRenderer> _renderers = <String, RTCVideoRenderer>{};

  /// 每路 renderer 的初始化 Future。
  ///
  /// `RTCVideoRenderer.srcObject` 在 initialize 完成前会抛异常；订阅必须
  /// 等它完成再发出，否则 onTrack 到达时挂载会静默失败，画面永远黑着。
  final Map<String, Future<void>> _rendererInit = <String, Future<void>>{};
  final Set<String> _subscribed = <String>{};
  bool _disposed = false;

  /// 媒体是否正在走声网。false = Cloudflare（未配证书 / Agora join 失败）。
  bool _viaAgora = false;

  /// 主持人麦克风开关状态（观众恒为 false）。
  bool _micOn = false;

  /// 开/闭麦请求进行中。
  bool _micBusy = false;

  /// Android 运行时麦克风权限的申请通道（原生 MainActivity 注册）。
  /// 声网 SDK 不自己弹权限框，RECORD_AUDIO 没请求过就是 denied ——
  /// 表现就是「开麦没声」，所以开麦前必须在这里把权限弹掉。
  static const MethodChannel _micPermissionChannel = MethodChannel(
    'com.chimu.crew/mic_permission',
  );

  /// 声网 30 秒等待窗的定时器：到点还没连上就通知一次 UI（链路徽标
  /// 从「声网」翻回「Cloudflare」）。连接成功即作废。
  Timer? _agoraWaitTimer;

  /// 观众端视角：当前媒体链路（用于 UI 角标）。
  bool get viaAgora => _viaAgora;

  /// 订阅同步的单飞锁 + 重跑标记。
  ///
  /// 进房、WebSocket hello、房间刷新都会各触发一次同步；并发跑会在
  /// 同一台 PC 上同时对同一个发布者发起两次订阅。第二次如果发生在第一次
  /// 完成后，正常的新增成员仍要处理，所以不是简单丢掉，而是排队重跑。
  Future<void>? _syncRunning;
  bool _syncQueued = false;

  static const String _recentKey = 'citro_share_recent_rooms';

  /// 最近 3 个房间，格式 `房间码:roomId`。
  List<String> get recentRooms => Prefs.getStringList(_recentKey);

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  // ── 进房 ──────────────────────────────────────────────────────────────

  /// 创建房间（主持人）。创建成功后**不会**自动共享，由用户点「开始共享」。
  Future<void> createRoom({
    required String title,
    String roomType = 'one_to_many',
    ShareQuality quality = ShareQuality.fallback,
  }) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      final res = await RoomApi.instance.createRoom(
        title: title,
        roomType: roomType,
        quality: quality,
      );
      _adoptJoin(
        res.roomToken,
        res.iceServers,
        res.room,
        res.members,
        res.chatHistory,
        agoraEnabled: res.agoraEnabled,
      );
      _quality = res.room.quality;
      _rememberRoom(res.room.roomCode);
      await _connectWs();
    } on ShareApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '创建房间失败：$e';
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 用房间号 / 房间码加入（观众）。
  ///
  /// [name] 只是显示名；信令侧始终用游客身份加入，避免同账号多设备
  /// 共用同一个 uid（见 [RoomApi.joinRoom]）。
  Future<void> joinRoom({
    required String roomId,
    String? code,
    String? name,
  }) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      final res = await RoomApi.instance.joinRoom(
        roomId,
        code: code,
        name: name,
      );
      _adoptJoin(
        res.roomToken,
        res.iceServers,
        res.room,
        res.members,
        res.chatHistory,
        agoraEnabled: res.agoraEnabled,
      );
      _quality = res.room.quality;
      _rememberRoom(res.room.roomCode);
      await _connectWs();
      // 房间里可能已经有人在共享，进来就要订阅。
      await _syncSubscriptions();
    } on ShareApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '加入房间失败：$e';
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _adoptJoin(
    String roomToken,
    List<Map<String, dynamic>> iceServers,
    RoomInfo room,
    List<RoomMember> members,
    List<ChatMessage> chatHistory, {
    bool agoraEnabled = false,
  }) {
    _roomToken = roomToken;
    _iceServers = iceServers;
    _room = room;
    _roomId = room.roomId;
    _members = members;
    _chat = chatHistory;
    _selfUid = members
        .firstWhere((m) => m.self, orElse: () => members.first)
        .uid;
    _ended = false;
    _endReason = null;
    _viaAgora = false;
    _micOn = false;
    // 观众的外放在声网 join 成功后经声网自己的 API 设置（见 _joinAgora）。
    // 不再用 flutter_webrtc 的 Helper.setSpeakerphoneOn：对声网引擎无效，
    // 还会抢 Android AudioManager 的 audio focus，把 GameStreaming 场景的
    // 系统声回采打得断断续续。
    if (agoraEnabled) {
      // 声网链路后台尝试：join 成功把 _viaAgora 置 true 并触发一次订阅
      // 同步（观众认 hostUid 的画面），失败就留在 Cloudflare 链路上，
      // 房间信令不受影响。
      unawaited(_joinAgora());
    }
  }

  /// 声网链路的接入。成功 → _viaAgora=true；失败 → 保持 CF 链路。
  Future<void> _joinAgora() async {
    final roomId = _roomId;
    final token = _roomToken;
    final selfUid = _selfUid;
    if (roomId == null || token == null || selfUid == null) return;
    final creds = await RoomApi.instance.fetchAgoraToken(
      roomToken: token,
      channel: roomId,
    );
    if (creds == null) return;
    final client = AgoraClient(roomId: roomId, roomToken: token);
    final isHost = _room?.hostUid == selfUid;
    final ok = await client.join(
      asHost: isHost,
      numericUid: creds.uid,
      appId: creds.appId,
    );
    if (!ok || _disposed) {
      // join 失败不立即放弃：起 30s 等待窗后整体重试一次（弱网下首次
      // 建连失败很常见）。仍失败才彻底留在 CF 链路。
      if (_disposed) {
        await client.close();
        return;
      }
      debugPrint('Agora join 失败，30s 后重试一次');
      _agoraWaitTimer?.cancel();
      _agoraWaitTimer = Timer(const Duration(seconds: 30), () {
        if (_disposed || _viaAgora) return;
        unawaited(_joinAgora());
      });
      await client.close();
      return;
    }
    client.onConnectionStateChanged = (c) {
      // 连接 / 断线都要刷 UI（链路徽标跟着翻）。
      _notify();
    };
    client.onRemoteVideo = (uid, available) {
      if (available) _notify();
    };
    _agora = client;
    _viaAgora = true;
    // 一起看是扬声器场景：观众默认外放（他们要听视频声），join 已完成，
    // setEnableSpeakerphone 此刻可以立即生效；连接回调里还有 connected
    // 分支兜底（引擎未就绪时重试）。主持人跟随物理路由，不设。
    if (!isHost) {
      unawaited(client.setSpeakerphone(true));
    }
    debugPrint('Agora 链路已接入（host=$isHost uid=${creds.uid}）');
    // 30 秒等待窗：声网握手慢（弱网 / 首次建连）不等于失败——窗口内
    // 徽标先显示「声网」；到点还没连上就刷一次 UI，让徽标翻回
    // Cloudflare（共享选路本就按 _viaAgora / connected 判定）。
    _agoraWaitTimer?.cancel();
    _agoraWaitTimer = Timer(const Duration(seconds: 30), () {
      if (_disposed || !_viaAgora) return;
      if (!client.connected.value) {
        debugPrint('声网 30s 未连上，降级 Cloudflare 主链路');
        _notify();
      }
    });
    _notify();
  }

  /// 记住房间码（不是 roomId）—— 加入时只用房间码就够了。
  void _rememberRoom(String code) {
    final list = <String>[...Prefs.getStringList(_recentKey)];
    list.insert(0, '$code:$roomId');
    // 去重后最多留 3 个。
    final seen = <String>{};
    final deduped = <String>[];
    for (final item in list) {
      if (seen.add(item)) deduped.add(item);
    }
    Prefs.setStringList(_recentKey, deduped.take(3).toList());
  }

  Future<void> _connectWs() async {
    final roomId = _roomId;
    final token = _roomToken;
    if (roomId == null || token == null) return;
    _ws?.close();
    _ws = RoomWs.start(
      roomId: roomId,
      token: token,
      onEvent: _onWsEvent,
      onStateChanged: (ok) {
        _wsConnected = ok;
        _notify();
      },
    );
  }

  // ── 事件 ──────────────────────────────────────────────────────────────

  Future<void> _onWsEvent(WsEvent e) async {
    switch (e.type) {
      case 'hello':
        // 重连后服务端会重推完整快照，按快照补齐发布者。
        final room = e.room;
        if (room != null) _room = room;
        _members = e.members;
        _chat = e.chatHistory;
        await _syncSubscriptions();
        break;

      case 'member_joined':
        final m = e.member;
        if (m != null && !_members.any((x) => x.uid == m.uid)) {
          _members = <RoomMember>[..._members, m];
        }
        break;

      case 'member_left':
        _members = _members.where((m) => m.uid != e.uid).toList();
        _releaseRenderersFor(e.uid ?? '');
        break;

      case 'publisher_joined':
      case 'track_added':
      case 'track_removed':
      case 'publisher_left':
        // 这几个事件只带 uid / sessionId，拿不到完整 track 列表，
        // 直接回源一次最可靠。
        await _refreshRoom();
        break;

      case 'viewer_count':
        _room = _room?.copyWithLive(
          viewerCount: e.count ?? 0,
          publisherCount: _room?.publisherCount,
        );
        break;

      case 'chat':
        final msg = e.chat;
        if (msg != null && !_chat.any((m) => m.id == msg.id)) {
          _chat = <ChatMessage>[..._chat, msg];
          // 主持人端把新聊天转发给弹幕悬浮窗（观众端不需要）。
          if (isHost && DanmakuBridge.enabled) {
            unawaited(DanmakuBridge.push(msg.name, msg.text));
          }
        }
        break;

      case 'quality_changed':
        _quality = e.quality;
        break;

      case 'room_ended':
        _ended = true;
        _endReason = e.reason ?? '主持人已结束一起看';
        break;

      case 'error':
        _error = e.message ?? '出错了';
        break;

      case 'pong':
        break;
    }
    _notify();
  }

  /// 回源拉一次房间状态，并同步订阅 / renderer。
  Future<void> _refreshRoom() async {
    final roomId = _roomId;
    final token = _roomToken;
    if (roomId == null || token == null) return;
    try {
      final res = await RoomApi.instance.getRoom(roomId, roomToken: token);
      _room = res.room;
      _members = res.members;
      await _syncSubscriptions();
      _syncRenderers();
    } catch (_) {
      // 拉取失败不影响已经在跑的媒体。
    }
    _notify();
  }

  Future<void> _syncSubscriptions() {
    final running = _syncRunning;
    if (running != null) {
      _syncQueued = true;
      return running;
    }
    final future = _runSyncLoop();
    _syncRunning = future;
    return future;
  }

  Future<void> _runSyncLoop() async {
    try {
      do {
        _syncQueued = false;
        await _syncOnce();
      } while (_syncQueued && !_disposed);
    } finally {
      _syncRunning = null;
    }
  }

  Future<void> _syncOnce() async {
    for (final m in _members) {
      if (m.uid == _selfUid) continue;
      final session = m.sfuSessionId;
      if (session == null || session.isEmpty) continue;

      // 走声网时主持人的媒体轨（screen/system）由 Agora autoSubscribe
      // 自动收——SFU 一路都不订：订了也是双收。判定用
      // useAgoraRemoteRender（与画面渲染一致），声网 30s 等待窗内 /
      // 掉线时自动回落 SFU 全量。老版本主持人的 mic 轨也照订不误。
      final skipAgora = useAgoraRemoteRender && m.uid == _room?.hostUid;
      final todo = <RoomTrack>[];
      for (final t in m.tracks) {
        if (skipAgora) continue;
        final key = _key(m.uid, t.name);
        if (_subscribed.contains(key)) continue;
        _subscribed.add(key);
        todo.add(t);
      }
      if (todo.isEmpty) continue;

      // 先等 renderer 初始化完成，再发起订阅：onTrack 会在
      // setRemoteDescription 里同步触发，没初始化好的 renderer 挂 srcObject
      // 会直接抛异常。一次只等一次订阅 —— 同一发布者的画面和系统声音
      // 必须放进同一个 offer，避免二次协商把音频 m-line 弄丢。
      for (final t in todo) {
        await _waitRenderer(_key(m.uid, t.name));
      }
      if (_disposed) return;
      try {
        await _ensureSfu().subscribe(session, [
          for (final t in todo)
            SfuSubscription(
              trackName: t.name,
              videoRenderer: t.isAudio ? null : rendererFor(m.uid, t.name),
              audioRenderer: t.isAudio ? rendererFor(m.uid, t.name) : null,
            ),
        ]);
        // 不在这里动扬声器路由：媒体主链路走声网时外放由
        // AgoraClient.setSpeakerphone 负责（连接回调兜底），这条 SFU
        // 订阅路径只服务 CF 兜底链路。flutter_webrtc 的
        // Helper.setSpeakerphoneOn 与声网引擎抢 audio focus 是系统声
        // 断续的头号嫌疑，已整体摘除。
      } catch (e) {
        for (final t in todo) {
          _subscribed.remove(_key(m.uid, t.name));
        }
        debugPrint('订阅 ${m.name} 的 ${todo.map((t) => t.name).join('+')} 失败：$e');
      }
    }
    _syncRenderers();
  }

  /// 等某一路 renderer 初始化完成（失败也继续，挂载侧还会兜底重试）。
  Future<void> _waitRenderer(String key) async {
    final ready = _rendererInit[key];
    if (ready == null) return;
    try {
      await ready;
    } catch (_) {}
  }

  /// 清掉已经不存在的 track 的 renderer，避免泄漏纹理。
  void _syncRenderers() {
    final alive = <String>{};
    for (final m in _members) {
      if (m.uid == _selfUid) continue;
      for (final t in m.tracks) {
        alive.add(_key(m.uid, t.name));
      }
    }
    for (final key in _renderers.keys.toList()) {
      if (alive.contains(key)) continue;
      final r = _renderers.remove(key);
      _rendererInit.remove(key);
      _safeDispose(r);
    }
    _subscribed.removeWhere((k) => !alive.contains(k));
  }

  void _releaseRenderersFor(String uid) {
    final prefix = '$uid:';
    for (final key in _renderers.keys.toList()) {
      if (!key.startsWith(prefix)) continue;
      final r = _renderers.remove(key);
      _rendererInit.remove(key);
      _safeDispose(r);
      _subscribed.remove(key);
    }
  }

  String _key(String uid, String trackName) => '$uid:$trackName';

  void _safeDispose(RTCVideoRenderer? r) {
    if (r == null) return;
    try {
      r.dispose().catchError((Object _) {});
    } catch (_) {}
  }

  /// 懒创建一路 renderer。
  ///
  /// 返回时 [RTCVideoRenderer.initialize] 可能还没完成，但 `RTCVideoView`
  /// 内部用 `ValueListenableBuilder` 监听 renderer，初始化完成后会自己重建，
  /// 所以这里只要保证 widget 侧拿到的是同一个对象即可。
  RTCVideoRenderer rendererFor(String uid, String trackName) {
    final key = _key(uid, trackName);
    final existing = _renderers[key];
    if (existing != null) return existing;
    final r = RTCVideoRenderer();
    _renderers[key] = r;
    _rendererInit[key] = r
        .initialize()
        .then<void>((_) {
          if (_disposed) {
            r.dispose().catchError((Object _) {});
            return;
          }
          _notify();
        })
        .catchError((Object e) {
          debugPrint('renderer 初始化失败（$key）：$e');
        });
    return r;
  }

  SfuClient _ensureSfu() {
    final existing = _sfu;
    if (existing != null) return existing;
    final sfu = SfuClient(
      roomId: _roomId ?? '',
      roomToken: _roomToken ?? '',
      iceServers: _iceServers,
    );
    _sfu = sfu;
    return sfu;
  }

  /// 声网链路的远端画面 uid（主持人发布者的数字 uid），null 表示不可用。
  ///
  /// Agora 的画面用 [AgoraVideoView]（原生渲染）而不是 RTCVideoRenderer，
  /// UI 拿这个 uid 建 remote controller。
  int? get agoraRemoteUid {
    if (!_viaAgora) return null;
    final host = _room?.hostUid;
    if (host == null || host == _selfUid) return null;
    return _agora?.remoteUidFor(host);
  }

  /// 房主在声网里的数字 uid（主持人自己预览用）。
  int? get agoraSelfUid => _viaAgora ? _agora?.hostUid : null;

  /// 当前声网链路是否真的连上了。
  bool get agoraConnected => _viaAgora && (_agora?.connected.value ?? false);

  /// 「此刻该用声网原生渲染远端画面吗」——房间页舞台和全屏页共用。
  ///
  /// 两个页面必须**同帧同判定**：全屏 ↔ 房间切换时若一处走 Agora 渲染、
  /// 另一处走 SFU renderer，画面会在切换瞬间黑一下或挂不上（SFU 的
  /// screen 轨在声网模式下从未订阅，renderer 里没有流）。uid 已就绪
  /// 且链路连接中才用 Agora 渲染；其余一律走 SFU renderer（CF 兜底）。
  bool get useAgoraRemoteRender {
    final uid = agoraRemoteUid;
    return uid != null && agoraConnected;
  }

  // ── 共享 ──────────────────────────────────────────────────────────────

  /// 开始共享屏幕（画面 + 可选系统声）。桌面选源弹窗的「开启内容声音」
  /// 开关经 [withAudio] 传进来；Android/iOS 恒采系统声（loopback 可用性
  /// 由采集层静默降级）。
  Future<void> startSharing({String? sourceId, bool withAudio = true}) async {
    if (_publishing || busy) return;
    if (!canPublish) {
      _error = '当前平台不支持发起一起看，只能观看';
      _notify();
      return;
    }
    _busy = true;
    _error = null;
    _notify();
    try {
      final stream = await ScreenCapture.captureScreen(
        quality: _quality,
        sourceId: sourceId,
        withSystemAudio: withAudio,
      );
      _previewStream = stream;

      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;
      _localRenderer = renderer;

      // 声网链路：改用声网原生采集发布画面+系统声（flutter_webrtc 的
      // track 拿不出原始帧，自定义 track 方案发不出任何东西）。失败或
      // 未连上时静默留在 CF 链路 —— 两条链路并存，观众端任取一条。
      final agora = _viaAgora ? _agora : null;
      if (agora != null) {
        final ok = await agora.startScreenShare(
          width: _quality.width,
          frameRate: _quality.frameRate,
          displayId: sourceId,
          withAudio: withAudio,
        );
        if (!ok) {
          debugPrint('Agora 屏幕发布失败，画面仅走 CF 链路');
        } else {
          _agoraSharing = true;
        }
      }

      final sfu = _ensureSfu();
      try {
        await sfu.publishScreen(stream, _quality);
        // 把用户之前拖好的音量补到新音轨上（默认都是 1.0）。
        await sfu.setSystemVolume(_systemVolume);
      } catch (e) {
        if (_agoraSharing) {
          // 声网已把画面（含系统声）发出去，观众端看得到；CF 链路失败只记
          // 日志，不报错、不清预览 —— 否则声网采集独立于这条流还在发，
          // 观众有画面而主持人却看到「开始共享失败」。
          debugPrint('CF 链路发布失败（声网已在发，忽略）：$e');
        } else {
          rethrow;
        }
      }
      _publishing = true;

      // 主动上报一次，让 WS 广播出去（REST publish 已经写过 DO，
      // 但 WS 事件才是让其他端立刻订阅的那一下）。
      _ws?.sendPublishState(<RoomTrack>[
        const RoomTrack(name: 'screen', kind: 'video'),
        if (sfu.hasSystemAudio) const RoomTrack(name: 'system', kind: 'audio'),
      ]);
    } on ShareApiException catch (e) {
      _error = e.message;
      _cleanupPreview();
    } catch (e) {
      _error = '开始共享失败：$e';
      _cleanupPreview();
    } finally {
      _busy = false;
      _notify();
    }
  }

  // ── 主持人麦克风 ──────────────────────────────────────────────────────

  /// 主持人开/闭麦。观众没有开麦入口（UI 由 isHost 门禁，这里也挡一层）。
  ///
  /// Android 先弹 RECORD_AUDIO 运行时权限（声网 SDK 原生层不弹框），
  /// 权限到手才动声网发布链；失败置 [_error] 并复位 busy，不抛出。
  Future<void> toggleMic() async {
    if (_micBusy || !agoraConnected) return;
    if (!isHost) return;
    _micBusy = true;
    _notify();
    try {
      final turningOn = !_micOn;
      if (turningOn && platform.isAndroid) {
        final granted = await _ensureMicPermission();
        if (!granted) {
          _error = '需要麦克风权限才能说话';
          return;
        }
      }
      final ok = await _agora?.setMicPublished(turningOn) ?? false;
      if (ok) {
        _micOn = turningOn;
      } else {
        _error = turningOn ? '开麦失败，请再试一次' : '闭麦失败，请再试一次';
      }
    } catch (e) {
      debugPrint('toggleMic 异常：$e');
      _error = '麦克风操作失败';
    } finally {
      _micBusy = false;
      _notify();
    }
  }

  /// 请求 Android 麦克风权限。通道不在（老 APK / 非 Android）或系统拒绝
  /// 都返回 false，绝不抛出。
  Future<bool> _ensureMicPermission() async {
    try {
      final granted = await _micPermissionChannel.invokeMethod<bool>('request');
      return granted ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (e) {
      debugPrint('麦克风权限请求失败：$e');
      return false;
    }
  }

  /// 停止共享，但留在房间里（观众还在看别人 / 还能聊天）。
  Future<void> stopSharing() async {
    if (!_publishing) return;
    try {
      await _sfu?.unpublish();
    } catch (_) {}
    if (_agoraSharing) {
      unawaited(_agora?.stopScreenShare());
      _agoraSharing = false;
    }
    // 共享停了麦也一起收（开麦状态不跨共享保留）。
    if (_micOn) {
      unawaited(
        _agora
            ?.setMicPublished(false)
            .then((ok) {
              if (ok) {
                _micOn = false;
                _notify();
              }
            })
            .catchError((Object _) {}),
      );
    }
    _cleanupPreview();
    _publishing = false;
    // 明确上报「已无发布轨」，覆盖掉之前 screen/system 的发布状态。
    _ws?.sendPublishState(const <RoomTrack>[]);
    _notify();
  }

  void _cleanupPreview() {
    ScreenCapture.stopStream(_previewStream);
    _previewStream = null;
    final r = _localRenderer;
    _localRenderer = null;
    _safeDispose(r);
  }

  void setSystemVolume(double value) {
    final next = value.clamp(0.0, 1.0);
    if (next == _systemVolume) return;
    _systemVolume = next;
    _notify();
  }

  Future<void> commitSystemVolume() async {
    final sfu = _sfu;
    // 系统声在两条链路各有一份（SFU loopback / 声网屏幕轨），一起调。
    if (_sfu?.hasSystemAudio ?? false) {
      await sfu?.setSystemVolume(_systemVolume);
    }
    if (agoraConnected && isHost) {
      await _agora?.setSystemVolume(_systemVolume);
    }
  }

  // ── 观众端：远端音量 / 全屏 ──────────────────────────────────────────

  /// 观众拖动远端音量。拖动中只改本地状态，松手 commit。
  void setViewerVolume(double value) {
    final next = value.clamp(0.0, 1.0);
    if (next == _viewerVolume) return;
    _viewerVolume = next;
    _notify();
  }

  /// 松手后把音量真正作用到远端音轨（system）。
  Future<void> commitViewerVolume() async {
    final sfu = _sfu;
    if (sfu != null) await sfu.setRemoteVolume(_viewerVolume);
    // 声网侧的 system/screen 走 Agora 音量。
    await _agora?.setRemoteVolume(_viewerVolume);
  }

  /// 进入全屏放映：沉浸式 + Android 锁横屏 + 置 [fullscreen] 标记。
  ///
  /// 系统栏 / 方向在这里处理；整页路由由房间页负责（页面持有
  /// Navigator，控制器不碰导航）。房间页监听 [fullscreen] 压 /
  /// 弹 [FullscreenStageRoute]，之前只藏系统栏不压页面，用户看到的
  /// 还是顶栏 + Dock + SafeArea，反馈「不是完全全屏」。
  ///
  /// iPad 刻意不锁方向（Info.plist 是全方向策略，运行时改会冲突），
  /// 只藏系统栏。iOS 的方向重锁由 [CitroOrientation.fullscreen] guard
  /// 挡住（否则 root_shell 一帧后就把方向改回去）。
  Future<void> enterFullscreen() async {
    if (_fullscreen) return;
    _fullscreen = true;
    _notify();
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    final isPad = _isPadDevice();
    if (!isPad) {
      try {
        await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } catch (_) {}
    }
    CitroOrientation.fullscreen = true;
  }

  /// 退出全屏：清标记（路由由房间页弹）、恢复系统栏与方向。
  Future<void> exitFullscreen() async {
    if (!_fullscreen) return;
    _fullscreen = false;
    _notify();
    CitroOrientation.fullscreen = false;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    // iPad 不锁方向，退出时也不用恢复。
    if (!_isPadDevice()) {
      final portrait = const <DeviceOrientation>[DeviceOrientation.portraitUp];
      try {
        await SystemChrome.setPreferredOrientations(portrait);
      } catch (_) {}
    }
  }

  /// 切换全屏。
  Future<void> toggleFullscreen() =>
      _fullscreen ? exitFullscreen() : enterFullscreen();

  /// 粗判 iPad：短边 ≥600 且不是 Duo 内屏。方向锁只在 iPhone/Duo 外屏收紧。
  bool _isPadDevice() {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    final size = view?.physicalSize;
    if (size == null) return false;
    final dpr = view?.devicePixelRatio ?? 1;
    final shortest = size.shortestSide / dpr;
    return shortest >= 600 &&
        !CitroForm.duoInner(Size(size.width / dpr, size.height / dpr));
  }

  /// 换画质。正在共享时立刻下发新的编码参数，不用中断推流。
  Future<void> setQuality(ShareQuality q) async {
    if (_quality == q) return;
    _quality = q;
    _room = _room?.copyWithLive(quality: q);
    _notify();
    _ws?.sendQuality(q);
    if (_publishing) {
      try {
        await _sfu?.applyQuality(q);
      } catch (e) {
        debugPrint('切换画质失败：$e');
      }
    }
  }

  // ── 聊天 / 小窗 / 退出 ────────────────────────────────────────────────

  void sendChat(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    if (!_wsConnected) {
      _error = '连接已断开，消息发不出去';
      _notify();
      return;
    }
    _ws?.sendChat(t);
  }

  void toggleMiniWindow() {
    _miniWindow = !_miniWindow;
    _notify();
  }

  void closeMiniWindow() {
    if (!_miniWindow) return;
    _miniWindow = false;
    _notify();
  }

  /// 主持人结束整个房间。
  ///
  /// 先清本地状态、立刻放行界面；结束房间的请求在后台发（旧实现先
  /// await 一个 20 s 超时的 HTTP，退出按钮会长时间无响应）。
  Future<void> endRoom() async {
    final roomId = _roomId;
    final token = _roomToken;
    unawaited(_teardown());
    if (roomId != null && token != null) {
      unawaited(RoomApi.instance.endRoom(roomId, roomToken: token));
    }
  }

  /// 主持人踢人。
  Future<void> kickMember(String uid) async {
    final roomId = _roomId;
    final token = _roomToken;
    if (roomId == null || token == null) return;
    try {
      await RoomApi.instance.kick(roomId, roomToken: token, uid: uid);
    } on ShareApiException catch (e) {
      _error = e.message;
      _notify();
    }
  }

  /// 离开房间（观众或主持人不结束房间时）。
  Future<void> leave() => _teardown();

  Future<void> _teardown() async {
    _ws?.close();
    _ws = null;
    _agoraWaitTimer?.cancel();
    _agoraWaitTimer = null;
    // 麦克风发布链随引擎一起释放；显式关一次是防御（重进房间时状态干净）。
    if (_micOn) {
      unawaited(_agora?.setMicPublished(false).catchError((Object _) => false));
    }
    _micOn = false;
    _micBusy = false;
    try {
      await _agora?.close();
    } catch (_) {}
    _agora = null;
    _viaAgora = false;
    _agoraSharing = false;
    try {
      await _sfu?.close();
    } catch (_) {}
    _sfu = null;
    for (final r in _renderers.values) {
      _safeDispose(r);
    }
    _renderers.clear();
    _rendererInit.clear();
    _subscribed.clear();
    _cleanupPreview();
    _room = null;
    _members = <RoomMember>[];
    _chat = <ChatMessage>[];
    _selfUid = null;
    _roomId = null;
    _roomToken = null;
    _iceServers = <Map<String, dynamic>>[];
    _publishing = false;
    _wsConnected = false;
    _ended = false;
    _endReason = null;
    _miniWindow = false;
    _viewerVolume = 1;
    _fullscreen = false;
    CitroOrientation.fullscreen = false;
    // 音频路由归声网引擎管，引擎已随 close() 释放，App 其他声音的
    // 路由不受影响；这里不再碰 flutter_webrtc 的 Helper（会抢
    // audio focus）。
    _notify();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _agoraWaitTimer?.cancel();
    _ws?.close();
    _agora?.close();
    _sfu?.close();
    for (final r in _renderers.values) {
      _safeDispose(r);
    }
    _renderers.clear();
    _rendererInit.clear();
    ScreenCapture.stopStream(_previewStream);
    _previewStream = null;
    _safeDispose(_localRenderer);
    _micOn = false;
    _micBusy = false;
    super.dispose();
  }
}
