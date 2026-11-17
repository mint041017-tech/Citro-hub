import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'room_api.dart';
import 'room_models.dart';
import 'screen_capture.dart';
import 'share_quality.dart';

/// 一路订阅的目标：track 名和它要挂到的 renderer。
class SfuSubscription {
  const SfuSubscription({
    required this.trackName,
    this.videoRenderer,
    this.audioRenderer,
  });

  final String trackName;
  final RTCVideoRenderer? videoRenderer;
  final RTCVideoRenderer? audioRenderer;
}

/// 一路待接入的订阅。
///
/// [mid] 是 Worker 在 `/subscribe` 响应里回传的 m-line 序号。Cloudflare 的
/// `onTrack` 事件本身不带「这是谁」的信息，所以只能靠 mid 把 track 对回
/// 到当初的订阅上；[mid] 为空时回落到 FIFO（同一成员的 SDP 交换是串行的）。
class _PendingSub {
  _PendingSub({
    required this.trackName,
    this.mid,
    this.videoRenderer,
    this.audioRenderer,
  });

  final String trackName;
  String? mid;
  final RTCVideoRenderer? videoRenderer;
  final RTCVideoRenderer? audioRenderer;
}

/// 媒体引擎：一个房间成员一个 [SfuClient]，对应 Worker 侧的一个 SFU session。
///
/// 发布与订阅共用同一个 RTCPeerConnection（Cloudflare 允许一个 session 同时
/// 收发），这样 1 对 1 和「观众也要开麦」不需要第二条链路。
///
/// 两条硬约束来自 SFU 的接口形态，改动前先读：
///   1. **不做 trickle ICE**。客户端必须等 candidate 收齐再发 offer，否则
///      SFU 拿到的 SDP 里没有任何可连地址，会直接失败。
///   2. **mid 必须动态读**。`addTransceiver` 之后 m-line 序号由 SDP 决定，
///      客户端加了第二路（麦克风）以后写死 "0" 会指错，必须从
///      `pc.getTransceivers()` 里读出来上报。
class SfuClient {
  SfuClient({
    required this.roomId,
    required this.roomToken,
    required this.iceServers,
    this.onConnectionStateChanged,
  });

  final String roomId;
  final String roomToken;
  final List<Map<String, dynamic>> iceServers;
  final void Function(bool connected)? onConnectionStateChanged;

  /// 订阅 PC：接收 screen/system/mic 的下行链路。
  ///
  /// 与发布 PC 刻意分离（见 [_publishPc]）：旧实现一条 PC 同时收发，
  /// 观众开麦时 publish offer 被路由进订阅 session，renegotiation 把
  /// system 音频的 m-line 谈崩 ——「开麦即丢系统声音」的根因。
  RTCPeerConnection? _pc;

  /// 订阅 session（Worker /subscribe 建，记在 DO 的 sfuSessionId）。
  String? _sessionId;

  /// 发布 PC：屏幕/系统声音的上行链路，独立 session。
  RTCPeerConnection? _publishPc;

  /// 发布 session（Worker /publish 建，记在 DO 的 sfuPublishSessionId）。
  String? _publishSessionId;

  MediaStream? _localStream;
  bool _publishing = false;
  bool _closed = false;
  final List<_PendingSub> _pending = <_PendingSub>[];

  /// 订阅 PC 的 SDP 交换串行队列。
  ///
  /// 进房后 `joinRoom` 的同步订阅和服务端 hello 触发的同步订阅会几乎
  /// 同时到达；两个 `setRemoteDescription` 并发会让 signalingState
  /// 直接抛错，Cloudflare 对同一个 session 的并发 mutation 也会回 406。
  /// 发布 PC 与订阅 PC 的交换互不相干，各走各的队列。
  Future<void> _exchangeQueue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _exchangeQueue = _exchangeQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// 系统声音是否真的挂在这条链路上了。
  ///
  /// 采集没拿到 loopback、或线上 Worker 还不认 `system` 这个 track 名时
  /// 都会是 false —— 设置里的「系统音量」据此禁用，而不是让用户拖一个
  /// 没有作用的滑杆。
  bool _systemAudioAttached = false;

  // ── 观众侧远端音量 ─────────────────────────────────────────────────────
  //
  // 观众的 renderer 播的是远端轨；音量作用在轨上（Helper.setVolume 同样
  // 适用于远端轨，底层是 Android AudioTrack / iOS volume）。订阅建立后
  // 新到的轨自动套当前值，拖动过的值不用等下一轨重挂。

  /// trackName → 远端音轨（`system` / `mic`）。
  final Map<String, MediaStreamTrack> _remoteAudioTracks = <String, MediaStreamTrack>{};

  /// 观众端远端音量（0–1），作用在所有远端音轨上。
  double _remoteVolume = 1;

  /// 观众端拖动音量（0–1）。立即作用于已挂的远端音轨。
  Future<void> setRemoteVolume(double volume) async {
    _remoteVolume = volume.clamp(0.0, 1.0);
    for (final track in _remoteAudioTracks.values) {
      try {
        await Helper.setVolume(_remoteVolume, track);
      } catch (e) {
        debugPrint('设置远端音量失败：$e');
      }
    }
  }

  /// trackId → `screen` / `mic` / `system`。发布时靠它把 transceiver 翻回 track 名。
  final Map<String, String> _trackNames = <String, String>{};

  /// 是否已经连上 SFU（ICE 完成）。
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  /// 最近一次错误，UI 直接展示。
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  bool get isPublishing => _publishing;
  String? get sessionId => _sessionId;

  /// 共享画面是否带了一路系统声音（视频里的声音，不是麦克风）。
  bool get hasSystemAudio => _systemAudioAttached;

  /// 订阅 PC（接收链路）。[/subscribe] 建 session 后，SFU 的 offer 从
  /// 这里进，onTrack 挂 renderer 也只发生在它上面。
  Future<RTCPeerConnection> _ensurePc() async {
    final existing = _pc;
    if (existing != null) return existing;
    final pc = await createPeerConnection(<String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    pc.onConnectionState = (RTCPeerConnectionState state) {
      final ok =
          state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      connected.value = ok;
      onConnectionStateChanged?.call(ok);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // ICE 失败先尝试重启，而不是直接重建整条链路。
        pc.restartIce().catchError((Object _) {});
      }
    };
    pc.onTrack = _onTrack;
    _pc = pc;
    return pc;
  }

  /// 发布 PC（发送链路）。纯 sendonly：屏幕、系统声音、麦克风都从这里
  /// 出去。与订阅 PC 完全独立 —— 观众开麦时这条链路的 offer 绝不会碰到
  /// 订阅 session 的 m-line。
  Future<RTCPeerConnection> _ensurePublishPc() async {
    final existing = _publishPc;
    if (existing != null) return existing;
    final pc = await createPeerConnection(<String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    pc.onConnectionState = (RTCPeerConnectionState state) {
      // 发布链路的状态单独上报：断开时 connected 不受影响（订阅链路
      // 还在），但 lastError 会让 UI 知道推流出问题了。
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        pc.restartIce().catchError((Object _) {});
      }
    };
    _publishPc = pc;
    return pc;
  }

  /// 等 ICE candidate 收齐。
  ///
  /// 有些平台（尤其 Windows）不保证 `onIceGatheringState` 一定触发，
  /// 所以额外留一个超时兜底：等不到就把当前 SDP 发出去，总比卡死好。
  Future<void> _waitForIceGathering(RTCPeerConnection pc) async {
    RTCIceGatheringState? state;
    try {
      state = await pc.getIceGatheringState();
    } catch (_) {
      return;
    }
    if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) return;

    final done = Completer<void>();
    final previous = pc.onIceGatheringState;
    pc.onIceGatheringState = (RTCIceGatheringState s) {
      previous?.call(s);
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !done.isCompleted) {
        done.complete();
      }
    };
    try {
      await done.future.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      debugPrint('ICE 收集超时，仍按当前 SDP 发布');
    } finally {
      pc.onIceGatheringState = previous;
    }
  }

  void _onTrack(RTCTrackEvent event) {
    final mid = event.transceiver?.mid;

    // 先按 mid 精确匹配；拿不到 mid 才退回订阅顺序。
    _PendingSub? sub;
    if (mid != null && mid.isNotEmpty) {
      final i = _pending.indexWhere((s) => s.mid == mid);
      if (i >= 0) sub = _pending.removeAt(i);
    }
    sub ??= _pending.isNotEmpty ? _pending.removeAt(0) : null;
    if (sub == null) {
      debugPrint('收到远端 track，但没有待处理的订阅：${event.track.kind} mid=$mid');
      return;
    }

    final renderer = event.track.kind == 'audio'
        ? sub.audioRenderer
        : sub.videoRenderer;
    // 远端音轨记账 + 立即套当前音量（拖动可能发生在轨到达之前）。
    if (event.track.kind == 'audio') {
      _remoteAudioTracks[sub.trackName] = event.track;
      unawaited(
        Helper.setVolume(_remoteVolume, event.track).catchError((Object e) {
          debugPrint('远端音轨初始音量设置失败：$e');
        }),
      );
    }
    if (renderer == null) return;

    // 常规情况：SDP 带 msid，事件直接给出远端流。
    if (event.streams.isNotEmpty) {
      _attachRenderer(renderer, event.streams.first);
      return;
    }
    // Cloudflare Realtime SFU 的 answer 不一定带 msid，此时 onTrack 的
    // streams 为空。以前这里直接 return，表现就是「有画面没声音」或
    // 干脆什么都收不到；自己造一条只含该 track 的流交给 renderer。
    unawaited(
      createLocalMediaStream('citro-remote-${event.track.id}')
          .then((stream) {
            stream.addTrack(event.track);
            _attachRenderer(renderer, stream);
          })
          .catchError((Object e) {
            debugPrint('构造远端流失败：$e');
          }),
    );
  }

  /// 把远端流挂到 renderer 上。
  ///
  /// flutter_webrtc 的 `RTCVideoRenderer.srcObject` 在 `initialize()`
  /// 完成前会直接抛异常（"Call initialize before setting the stream"）。
  /// 控制器已经会先等初始化，这里再兜一层：失败不打断 onTrack，
  /// 200ms 后重试一次，避免偶发的初始化竞态把第一帧永久丢掉。
  void _attachRenderer(RTCVideoRenderer renderer, MediaStream stream) {
    try {
      renderer.srcObject = stream;
    } catch (e) {
      debugPrint('挂载远端流失败，稍后重试：$e');
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        try {
          renderer.srcObject = stream;
        } catch (e2) {
          debugPrint('重试挂载远端流失败：$e2');
        }
      });
    }
  }

  // ── 发布 ──────────────────────────────────────────────────────────────

  /// 发布屏幕（画面 + 系统声音；不再发布麦克风）。
  ///
  /// [includeSystemAudio]：是否把采集流里的系统声音轨也发到 SFU。Windows
  /// 上声网已在发布系统声时必须传 false —— WebRTC 的 Windows ADM 会把
  /// 播放流登记成「通信」类别，只要 SFU 链路上有音频发送者，系统就会触发
  /// communications ducking，把其它应用（以及用户自己放的音乐）音量压到
  /// 20%。实测 SFU 带系统声时端点峰值 0.4109 → 0.0517，纯画面则全程
  /// 0.41。声网链路不受影响，观众照样从声网收系统声。
  ///
  /// 返回 SFU 侧的 sessionId，后续停止共享时用来关 session。
  Future<String> publishScreen(
    MediaStream stream,
    ShareQuality quality, {
    bool includeSystemAudio = true,
  }) async {
    // 发布走独立的 PC/session，绝不碰订阅链路。
    final pc = await _ensurePublishPc();
    _localStream = stream;

    final videoTrack = stream.getVideoTracks().isEmpty
        ? null
        : stream.getVideoTracks().first;
    if (videoTrack == null) {
      throw const ShareApiException('没有可用的屏幕画面');
    }
    await _addTrack(pc, videoTrack, 'screen');

    // 系统声音（桌面端 loopback）是独立于麦克风的一路轨。名字必须上报给
    // Worker，订阅端才能把它和 `mic` 分开播；老版本 Worker 只认 screen /
    // mic，所以下面有「摘掉再发一次」的降级。
    final systemTrack = !includeSystemAudio || stream.getAudioTracks().isEmpty
        ? null
        : stream.getAudioTracks().first;
    if (systemTrack != null) {
      await _addTrack(pc, systemTrack, 'system');
      _systemAudioAttached = true;
    }

    try {
      return await _exchangeOffer(pc, quality);
    } on ShareApiException catch (e) {
      if (systemTrack == null || !e.message.contains('不支持的 track')) rethrow;
      // 线上 Worker 还没升级：画面优先，把系统声音摘掉重新协商。
      // 部署新版 Worker 后这里不会再走到，用户下次开始共享就有声音。
      await _detachSystemAudio(pc, stream, systemTrack);
      return _exchangeOffer(pc, quality);
    }
  }

  /// 从 PeerConnection 和采集流里同时摘掉系统声音。
  Future<void> _detachSystemAudio(
    RTCPeerConnection pc,
    MediaStream stream,
    MediaStreamTrack track,
  ) async {
    _systemAudioAttached = false;
    _trackNames.remove(track.id);
    try {
      for (final sender in await pc.getSenders()) {
        if (sender.track?.id == track.id) {
          await pc.removeTrack(sender);
          break;
        }
      }
    } catch (e) {
      debugPrint('摘除系统声音失败：$e');
    }
    try {
      await stream.removeTrack(track);
    } catch (_) {}
    try {
      track.stop();
    } catch (_) {}
  }

  /// 共享内容（系统声音）的音量（0–1）。
  Future<void> setSystemVolume(double volume) async {
    if (!_systemAudioAttached) return;
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    for (final track in tracks) {
      try {
        await Helper.setVolume(volume, track);
      } catch (e) {
        debugPrint('设置系统音量失败：$e');
      }
    }
  }

  /// 画质档位变化时重新下发编码参数。
  ///
  /// 不需要重新采集，也不需要重新 offer —— `setParameters` 直接作用于
  /// 正在发送的 sender，SFU 侧只会看到码率 / 帧率变化。
  Future<void> applyQuality(ShareQuality quality) async {
    final pc = _publishPc;
    if (pc == null) return;
    await _applyVideoEncoding(pc, quality);
  }

  /// 建 offer、等 ICE、把当前所有发送中的 track 报给 SFU、拿回 answer。
  ///
  /// 每次都上报全部发送中的 track（而不是只报新增的那一路）：SFU 侧的
  /// `tracks/new` 是累加语义，重复声明已存在的 track 不会丢路线。
  Future<String> _exchangeOffer(RTCPeerConnection pc, ShareQuality quality) {
    return _serialized(() => _exchangeOfferLocked(pc, quality));
  }

  /// 调用方必须已经在 [_serialized] 队列里（或确认独占 PeerConnection）。
  Future<String> _exchangeOfferLocked(
    RTCPeerConnection pc,
    ShareQuality quality,
  ) async {
    final offer = await pc.createOffer(<String, dynamic>{
      'mandatory': <String, dynamic>{
        'OfferToReceiveAudio': false,
        'OfferToReceiveVideo': false,
      },
      'optional': <Map<String, dynamic>>[],
    });
    // 立体声声明：采集侧已是双声道（cached_out_channels_=2），但 Opus
    // 只有在 SDP 的 fmtp 带 stereo=1 时才按立体声编码，否则发布端会把
    // 两声道下混成单声道——采集改动白做。sprop-stereo=1 告诉接收端
    // 解码输出也是立体声。改写失败不影响流程（回落原始 SDP，音质单声）。
    final sdp = enableStereo(offer.sdp ?? '');
    await pc.setLocalDescription(RTCSessionDescription(sdp, offer.type));
    await _waitForIceGathering(pc);

    final tracks = await _localTracks(pc);
    if (tracks.isEmpty) throw const ShareApiException('没有可发布的画面');

    // 必须用 setLocalDescription 之后的 SDP：createOffer 返回的字符串
    // 是「还没收集 ICE」的版本，等完 gathering 后候选只写进
    // pc.localDescription。发旧 offer 会在对称 NAT / 部分移动网络下
    // 连不上，表现是有 session 但一直没有媒体。
    final local = await pc.getLocalDescription();
    final result = await RoomApi.instance.publish(
      roomId,
      roomToken: roomToken,
      sdp: local?.sdp ?? offer.sdp ?? '',
      tracks: tracks,
    );
    // Worker 对发布重试复用同一 session（member.sfuPublishSessionId），
    // 本地记录保持一致。这是发布 session，与订阅的 _sessionId 无关。
    _publishSessionId ??= result.sessionId;

    await pc.setRemoteDescription(
      RTCSessionDescription(result.sdp, result.type),
    );
    await _applyVideoEncoding(pc, quality);
    await _applyAudioEncoding(pc);
    _publishing = true;
    return result.sessionId;
  }

  /// 把一路 track 挂到 pc 上，并记住它的名字。
  Future<void> _addTrack(
    RTCPeerConnection pc,
    MediaStreamTrack track,
    String name,
  ) async {
    await pc.addTransceiver(
      track: track,
      kind: track.kind == 'audio'
          ? RTCRtpMediaType.RTCRtpMediaTypeAudio
          : RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly),
    );
    final id = track.id;
    if (id != null) _trackNames[id] = name;
  }

  /// 读出当前所有发送中的 track，连同它们的 mid。
  Future<List<RoomTrack>> _localTracks(RTCPeerConnection pc) async {
    final out = <RoomTrack>[];
    try {
      for (final tr in await pc.getTransceivers()) {
        final track = tr.sender.track;
        if (track == null) continue;
        final id = track.id;
        if (id == null) continue;
        final name = _trackNames[id];
        if (name == null) continue;
        out.add(
          RoomTrack(
            name: name,
            kind: track.kind == 'audio' ? 'audio' : 'video',
            mid: tr.mid,
          ),
        );
      }
    } catch (e) {
      debugPrint('读取 transceiver 失败：$e');
    }
    return out;
  }

  /// 编码侧的画质控制。
  ///
  /// 采集分辨率是屏幕原生大小（Android 完全忽略 constraints），
  /// 所以要达到「720p / 2K 可选」必须在这里做：
  ///   - maxBitrate：限制出口码率，直接决定 Cloudflare 的计费流量；
  ///   - maxFramerate：限制帧率；
  ///   - scaleResolutionDownBy：把超采样源缩到目标档位。
  Future<void> _applyVideoEncoding(
    RTCPeerConnection pc,
    ShareQuality quality,
  ) async {
    try {
      for (final sender in await pc.getSenders()) {
        final track = sender.track;
        if (track == null || track.kind != 'video') continue;
        final settings = track.getSettings();
        final srcWidth = (settings['width'] as num?)?.toInt() ?? 0;
        double scale = 1.0;
        if (srcWidth > quality.width) {
          scale = srcWidth / quality.width;
        }
        await sender.setParameters(
          RTCRtpParameters(
            encodings: <RTCRtpEncoding>[
              RTCRtpEncoding(
                maxBitrate: quality.maxBitrate,
                maxFramerate: quality.frameRate,
                scaleResolutionDownBy: scale,
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // 编码参数失败不影响推流，只是画质不受控。
      debugPrint('设置编码参数失败：$e');
    }
  }

  /// 音频编码侧的码率上限。
  ///
  /// flutter_webrtc 不设置时 Opus 会按 SFU 的带宽估计自适应，实际经常停在
  /// 32 kbps 上下，音乐 / 人声都发闷。256 kbps 是 Opus 音乐模式（fullband
  /// 立体声）的实用上限——麦克风人声天然用不到，系统声音（音乐/游戏音效）
  /// 在高码率下高频细节明显更好。不会强行跑满，拥塞时仍会自动降。
  Future<void> _applyAudioEncoding(RTCPeerConnection pc) async {
    try {
      for (final sender in await pc.getSenders()) {
        final track = sender.track;
        if (track == null || track.kind != 'audio') continue;
        await sender.setParameters(
          RTCRtpParameters(
            encodings: <RTCRtpEncoding>[
              RTCRtpEncoding(maxBitrate: 256000),
            ],
          ),
        );
      }
    } catch (e) {
      // 音频参数失败不影响推流，只是码率不受控。
      debugPrint('设置音频编码参数失败：$e');
    }
  }

  /// 把 SDP 里所有 opus 的 fmtp 行追加 `stereo=1;sprop-stereo=1`。
  ///
  /// 已带 stereo=1 的行不重复加；没有 opus fmtp 行（理论不可能，opus
  /// 协商成功必有）时不动 SDP。纯字符串处理，失败回落原 SDP。
  /// 公开静态：P2P 宿主侧 offer 用同一处理（P2pClient 引用）。
  static String enableStereo(String sdp) {
    if (!sdp.contains('opus')) return sdp;
    final lines = sdp.split('\r\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.startsWith('a=fmtp:') || !line.contains('opus')) continue;
      if (line.contains('stereo=1')) continue;
      lines[i] = '$line;stereo=1;sprop-stereo=1';
    }
    return lines.join('\r\n');
  }

  /// 停止发布，但保留接收链路（观众还在看）。
  ///
  /// 发布 PC 整条关闭（它只承载发送），比逐个 removeTrack 干净：
  /// session 留给 Worker 的 /unpublish 关闭，PC 关掉后 30 s 无媒体
  /// SFU 自动回收。下次开共享会新建 PC + session。
  Future<void> unpublish() async {
    _publishing = false;
    try {
      _publishPc?.close();
    } catch (_) {}
    _publishPc = null;
    _publishSessionId = null;
    ScreenCapture.stopStream(_localStream);
    _localStream = null;
    _systemAudioAttached = false;
    _trackNames.clear();
  }

  // ── 订阅 ──────────────────────────────────────────────────────────────

  /// 订阅发布者的多路 track（一次 offer / 一次 renegotiation）。
  ///
  /// 分开订阅时 `system` 音频会叠加在已经稳定的 `screen` m-line 上做
  /// 二次协商，libwebrtc 侧还可能撞 RTP header extension 冲突；批量订阅
  /// 把所有 m-line 放进同一次 exchange。
  Future<void> subscribe(
    String publisherSessionId,
    List<SfuSubscription> subscriptions,
  ) {
    if (subscriptions.isEmpty) return Future<void>.value();
    // 和发布共用一条串行队列：joinRoom 与 WebSocket hello 都会触发
    // 订阅，不能在同一台 PC 上并发 setRemoteDescription。
    return _serialized(() async {
      final pc = await _ensurePc();
      final trackNames = subscriptions.map((s) => s.trackName).toList();

      // 先换 SDP 再登记 pending：mid 只有 Worker 回响应才知道，
      // 而 onTrack 一定在 setRemoteDescription 之后才来。
      final sub = await RoomApi.instance.subscribe(
        roomId,
        roomToken: roomToken,
        publisherSessionId: publisherSessionId,
        trackNames: trackNames,
      );
      _sessionId ??= sub.sessionId;

      for (final item in subscriptions) {
        final mapped = sub.mids[item.trackName];
        final mid = (mapped != null && mapped.isNotEmpty)
            ? mapped
            : (item.trackName == trackNames.first && sub.mid.isNotEmpty
                  ? sub.mid
                  : null);
        _pending.add(
          _PendingSub(
            trackName: item.trackName,
            mid: mid,
            videoRenderer: item.videoRenderer,
            audioRenderer: item.audioRenderer,
          ),
        );
      }

      await pc.setRemoteDescription(RTCSessionDescription(sub.sdp, sub.type));
      // 和网页观看端保持一致：createAnswer 不带 legacy 约束，交给
      // unified-plan 按远端 offer 的 direction 自动生成。
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      // 订阅侧以前漏了这一步：answer 在 ICE 收集完成前就发出去了，
      // SDP 里没有任何本地候选。发布侧一直是等的，接收侧没等，
      // 所以浏览器能看、App 观看端却总是连不上媒体。
      await _waitForIceGathering(pc);
      final local = await pc.getLocalDescription();
      await RoomApi.instance.sendAnswer(
        roomId,
        roomToken: roomToken,
        sessionId: sub.sessionId,
        sdp: local?.sdp ?? answer.sdp ?? '',
      );
    });
  }

  /// 订阅读卡：把某一路订阅对应的 renderer 清掉（发布者下线时 UI 调用）。
  void detach(RTCVideoRenderer renderer) {
    renderer.srcObject = null;
  }

  // ── 收尾 ──────────────────────────────────────────────────────────────

  /// 断开并释放整条媒体链路。
  ///
  /// 本地清理先做、网络通知后发：旧实现先 await leave（HTTP 超时 20 s），
  /// 网络一慢「退出一起看」就卡住不返回，采集和画面也还开着。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _publishing = false;
    final id = roomId;
    final token = roomToken;
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      _publishPc?.close();
    } catch (_) {}
    _publishPc = null;
    _publishSessionId = null;
    _remoteAudioTracks.clear();
    _remoteVolume = 1;
    ScreenCapture.stopStream(_localStream);
    _localStream = null;
    _systemAudioAttached = false;
    _trackNames.clear();
    _pending.clear();
    connected.value = false;
    // 服务端离开通知放后台；收不到也会随 session 超时清理。
    unawaited(
      RoomApi.instance
          .leave(id, roomToken: token)
          .timeout(const Duration(seconds: 5), onTimeout: () {}),
    );
  }

  @override
  String toString() =>
      'SfuClient($roomId, session=$_sessionId, publishing=$_publishing)';
}
