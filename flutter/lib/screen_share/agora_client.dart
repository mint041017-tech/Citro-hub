import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

import '../services/platform.dart' as platform;
import 'room_api.dart';

/// 媒体主链路：声网 Agora SD-RTN（国内直连，延迟低）。
///
/// 角色：
///   主持人 = joinChannel(broadcaster)，共享开始后用**声网原生采集**发
///            屏幕画面 + 系统声（Android/iOS `startScreenCapture`，
///            Windows `startScreenCaptureByDisplayId`）。麦克风 join 时
///            关死，主持人点「开麦」经 [setMicPublished] 打开发布链；
///            观众端没有开麦入口，说话仍走文字聊天。
///   观众   = joinChannel(audience)，SDK 按 autoSubscribe 自动收远端音视频
///            （含主持人的麦），外放意图经 [setSpeakerphone] 表达。
///
/// 为什么用声网原生采集而不是把 flutter_webrtc 的帧喂进自定义 track：
///   1. v3.0.0 的自定义 track 方案是半成品——视频从未 push 过帧（观众
///      黑屏），音频的 PCM 桥（ScreenCaptureBridge）只有 sink 没有源
///      （全员哑巴）。libwebrtc 的 track 拿不出原始帧是死结。
///   2. 声网原生采集自带系统声（Android 内部播放 / Windows WASAPI
///      loopback），与我们补丁修的 WASAPI 行为一致，且编码/弱网全托管。
///
/// 与 Cloudflare 链路并行的规则：主持人的 screen/system 在两条链路上
/// 都发（老客户端只能收 CF）；观众端谁连上了声网就跳过 SFU 的这两路。
///
/// token 从 Worker `/api/agora/token` 换（24h 有效，join 前取一次即可）。
/// Worker 未配证书时 `enabled=false`，控制器自动走 Cloudflare 链路。
class AgoraClient {
  AgoraClient({required this.roomId, required this.roomToken});

  final String roomId;
  final String roomToken;

  RtcEngine? _engine;
  bool _initialized = false;

  /// 观众端的外放意图：true = 进房就想外放。join 后设置一次失败 /
  /// 连接回调时按这个字段补打（见 [onConnectionStateChanged]）。
  bool _speakerphoneWanted = false;

  /// 观众是否手动关过外放。关过之后连接重连不再强制打开。
  bool _speakerphoneUserOff = false;

  /// 当前是否已成功连上声网。false 时控制器回退 Cloudflare。
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  /// 远端画面挂载回调：uid（声网数字 uid）→ 需要渲染。
  /// UI 拿 uid 建 AgoraVideoView（remote），不走 RTCVideoRenderer。
  void Function(int uid, bool videoAvailable)? onRemoteVideo;
  void Function(int uid, bool audioAvailable)? onRemoteAudio;
  void Function(bool connected)? onConnectionStateChanged;

  /// 声网权限错误（Android 屏幕采集授权被拒 / 系统声采集失败）。
  /// 主持人侧用它把「声网没发出去」反馈给用户，房间不中断（还有 CF 链路）。
  void Function(PermissionType permissionType)? onPermissionError;

  /// 发布者（主持人）的声网 uid —— 观众据此认出哪一路是屏幕画面。
  int? hostUid;

  /// 字符串 uid → 声网数字 uid 的映射。Worker 侧（JS）用 FNV-1a：
  /// `h ^= c; h = Math.imul(h, 0x01000193)`，最后 `h >>> 0` 转 32 位
  /// 无符号。Dart 必须逐位对齐 JS 的有符号 32 位运算，两端哈希才一致。
  static int uidFor(String uid) {
    var h = 0x811c9dc5.toSigned(32);
    for (var i = 0; i < uid.length; i++) {
      h = (h ^ uid.codeUnitAt(i)).toSigned(32);
      h = _imul(h, 0x01000193);
    }
    final unsigned = h & 0xFFFFFFFF;
    // 与 Worker 一致：避开 0（Agora 把 0 当「SDK 分配」），取正 31 位。
    final v = unsigned % 0x7fffffff;
    return v == 0 ? 1 : v;
  }

  /// JS Math.imul 的 Dart 等价：有符号 32 位乘法，只保留低 32 位。
  static int _imul(int a, int b) {
    final ah = (a >>> 16) & 0xFFFF;
    final al = a & 0xFFFF;
    final bh = (b >>> 16) & 0xFFFF;
    final bl = b & 0xFFFF;
    var high = ((ah * bl + al * bh) & 0xFFFFFFFF) >>> 0;
    final low = ((al * bl) & 0xFFFFFFFF) >>> 0;
    final combined = (((high << 16) >>> 0) + low) >>> 0;
    return combined.toSigned(32);
  }

  /// 成员字符串 uid 对应的声网数字 uid（观众侧查询远端画面用）。
  int? remoteUidFor(String memberUid) => uidFor(memberUid);

  // ── 初始化 ─────────────────────────────────────────────────────────────

  /// 初始化引擎并用房间 token 换声网 token，成功后加入频道。
  /// 任何一步失败都返回 false（调用方回退 Cloudflare），绝不抛出。
  Future<bool> join({
    required bool asHost,
    required int numericUid,
    required String appId,
  }) async {
    try {
      final engine = createAgoraRtcEngine();
      await engine.initialize(
        RtcEngineContext(
          appId: appId,
          // 直播场景：主持人 / 观众两种角色，比 communication 更省下行。
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          // GameStreaming 场景：一起看的核心是「听视频里的声音」。上一轮
          // 为回声改回 Default 后手机端**采不到系统声**（声网文档对小米
          // 等机型的明确提示：Default 走通讯音量模式，屏幕采集的内部播
          // 放回采在该模式下被系统限制），这是实测回归——系统声可靠性
          // 优先级最高，保持 GameStreaming。
          audioScenario: AudioScenarioType.audioScenarioGameStreaming,
          // areaCode 是 int 位掩码；GLOB = 0xFFFFFFF 覆盖全球节点，
          // 声网按就近接入自动选国内节点。
          areaCode: 0xFFFFFFF,
        ),
      );
      _engine = engine;

      final tokenResult = await RoomApi.instance.fetchAgoraToken(
        roomToken: roomToken,
        channel: roomId,
      );
      if (tokenResult == null) {
        await _releaseEngine();
        return false;
      }

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onConnectionStateChanged: (connection, state, reason) {
            final ok = state == ConnectionStateType.connectionStateConnected;
            connected.value = ok;
            // 观众的外放兜底：join 时 engine 可能还没准备好（返回码
            // 非 0 / 音频会话未建立），连接真正建立后按意图补一次。
            // 手动关过外放的不动（尊重用户选择）。
            if (ok && _speakerphoneWanted && !_speakerphoneUserOff) {
              unawaited(_setSpeakerphoneInternal(true));
            }
            onConnectionStateChanged?.call(ok);
          },
          onRemoteVideoStateChanged:
              (connection, remoteUid, state, reason, elapsed) {
                final started =
                    state == RemoteVideoState.remoteVideoStateDecoding ||
                    state == RemoteVideoState.remoteVideoStateStarting;
                if (started ||
                    state == RemoteVideoState.remoteVideoStateStopped) {
                  if (started && !_knownRemoteUids.contains(remoteUid)) {
                    _knownRemoteUids.add(remoteUid);
                    // 新远端进来补一次音量设置（Agora 按用户调音量）。
                    unawaited(_applyRemoteVolume(remoteUid));
                  }
                  onRemoteVideo?.call(remoteUid, started);
                }
              },
          onRemoteAudioStateChanged:
              (connection, remoteUid, state, reason, elapsed) {
                onRemoteAudio?.call(
                  remoteUid,
                  state == RemoteAudioState.remoteAudioStateDecoding ||
                      state == RemoteAudioState.remoteAudioStateStarting,
                );
              },
          onUserOffline: (connection, remoteUid, reason) {
            onRemoteVideo?.call(remoteUid, false);
            onRemoteAudio?.call(remoteUid, false);
          },
          onPermissionError: (permissionType) {
            debugPrint('Agora 权限错误：$permissionType');
            onPermissionError?.call(permissionType);
          },
        ),
      );

      await engine.setClientRole(
        role: asHost
            ? ClientRoleType.clientRoleBroadcaster
            : ClientRoleType.clientRoleAudience,
      );

      // 音乐级编码（48kHz 立体声），必须在 join 之前调；失败不拦 join
      //（有兜底音质也比没画面强）。手机端 StandardStereo：HighQualityStereo
      // 在中低端机编码器算力超载（实测系统声断续）；桌面端保留高保真档。
      try {
        await engine.setAudioProfile(
          profile: platform.isDesktop
              ? AudioProfileType.audioProfileMusicHighQualityStereo
              : AudioProfileType.audioProfileMusicStandardStereo,
          scenario: AudioScenarioType.audioScenarioGameStreaming,
        );
      } catch (e) {
        debugPrint('Agora 音质档设置失败（继续）：$e');
      }

      // 麦克风轨 join 时保持关死（发布链在主持人点「开麦」时经
      // setMicPublished 打开）；AI 回消 / AI 降噪扩展也随开麦动作一起
      // 启用（它们的处理对象只有麦克风采集信号，关麦时启用无意义）。
      await engine.joinChannel(
        token: tokenResult.token,
        channelId: tokenResult.channel,
        uid: tokenResult.uid,
        options: ChannelMediaOptions(
          // 主持人：屏幕（含系统声）在共享启动时逐项打开；麦克风由
          // [setMicPublished] 按开关控制。观众只收不发（autoSubscribe
          // 收主持人的屏幕音 + 麦）。
          publishScreenTrack: false,
          publishCameraTrack: false,
          publishMicrophoneTrack: false,
          publishCustomAudioTrack: false,
          publishCustomVideoTrack: false,
          autoSubscribeAudio: !asHost,
          autoSubscribeVideo: !asHost,
          clientRoleType: asHost
              ? ClientRoleType.clientRoleBroadcaster
              : ClientRoleType.clientRoleAudience,
        ),
      );
      hostUid = asHost ? tokenResult.uid : null;
      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('Agora join 失败，回退 Cloudflare：$e');
      await _releaseEngine();
      return false;
    }
  }

  Future<void> _releaseEngine() async {
    final engine = _engine;
    _engine = null;
    _initialized = false;
    connected.value = false;
    if (engine != null) {
      try {
        await engine.leaveChannel();
      } catch (_) {}
      try {
        await engine.release();
      } catch (_) {}
    }
  }

  // ── 发布（主持人）：声网原生采集 ───────────────────────────────────────

  /// 开始屏幕共享发布：画面 + 系统声都走声网原生采集。
  ///
  /// [displayId] / [windowId]：Windows 端选中的共享源（display 或窗口），
  /// null 表示整屏（Android/iOS 只有整屏概念）。分辨率 / 帧率从画质档来。
  ///
  /// Android 的屏幕授权弹窗由 SDK 内部触发（onPermissionError(2) 表示
  /// 被拒）；iOS 走 ReplayKit 广播扩展。Windows 直接按 id 采。
  /// 失败返回 false —— 调用方让画面继续走 CF 链路，房间不中断。
  Future<bool> startScreenShare({
    required int width,
    required int frameRate,
    String? displayId,
    String? windowId,
    bool withAudio = true,
  }) async {
    final engine = _engine;
    if (engine == null || !_initialized) return false;
    try {
      if (platform.isWindows) {
        // Windows：displayId / windowId 都是字符串 id（我们自己的枚举），
        // Agora 的 display id 是整数；窗口走 windowId。转不出来就整屏。
        final params = ScreenCaptureParameters(
          dimensions: VideoDimensions(width: width, height: width * 9 ~/ 16),
          frameRate: frameRate,
          captureAudio: withAudio,
        );
        // regionRect 传全空 = 不裁剪，采整屏 / 整窗。
        const fullRegion = Rectangle();
        final wid = windowId != null ? int.tryParse(windowId) : null;
        final did = wid == null ? int.tryParse(displayId ?? '') : null;
        if (wid != null) {
          await engine.startScreenCaptureByWindowId(
            windowId: wid,
            regionRect: fullRegion,
            captureParams: params,
          );
        } else if (did != null) {
          await engine.startScreenCaptureByDisplayId(
            displayId: did,
            regionRect: fullRegion,
            captureParams: params,
          );
        } else {
          await engine.startScreenCaptureByDisplayId(
            displayId: 0, // 主显示器
            regionRect: fullRegion,
            captureParams: params,
          );
        }
      } else {
        // Android / iOS：SDK 自己弹授权。系统声 captureAudio 一并打开
        //（部分小米机型采不到系统声，onPermissionError 之外无明确信号，
        // 我们不因音频失败中断共享）。
        await engine.startScreenCapture(
          ScreenCaptureParameters2(
            captureAudio: true,
            captureVideo: true,
            videoParams: ScreenVideoParameters(
              dimensions: VideoDimensions(
                width: width,
                height: width * 9 ~/ 16,
              ),
              frameRate: frameRate,
            ),
          ),
        );
      }
      // 打开屏幕轨发布。Android/iOS 的 mediaProjection 流要用
      // publishScreenCaptureVideo + publishScreenCaptureAudio 一对开关
      // 显式打开（publishScreenTrack 在移动端只代表「主屏幕轨」语义，
      // 少了 CaptureVideo 这个开关画面发布不出去——上一版观众「听得到
      // 麦听不到画面声」就是因为画面轨没真正发出去，系统声也跟着
      // 屏幕轨一起哑了）；Windows 用 publishScreenTrack 就够。
      if (platform.isWindows) {
        await engine.updateChannelMediaOptions(
          ChannelMediaOptions(
            publishScreenTrack: true,
            publishScreenCaptureAudio: withAudio,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
          ),
        );
      } else {
        await engine.updateChannelMediaOptions(
          ChannelMediaOptions(
            publishScreenCaptureVideo: true,
            publishScreenCaptureAudio: withAudio,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
          ),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Agora 屏幕共享启动失败（回 CF 链路）：$e');
      return false;
    }
  }

  /// 停止屏幕共享发布（画面 + 系统声一起停）。
  Future<void> stopScreenShare() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.stopScreenCapture();
      await engine.updateChannelMediaOptions(
        ChannelMediaOptions(
          publishScreenTrack: false,
          publishScreenCaptureVideo: false,
          publishScreenCaptureAudio: false,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
    } catch (_) {}
  }

  /// 系统声（loopback 采集）音量（0–1），与 SFU 的 setSystemVolume 对齐。
  /// adjustLoopbackSignalVolume 范围 0–100（100=原声）。
  Future<void> setSystemVolume(double volume) async {
    final engine = _engine;
    if (engine == null) return;
    try {
      final v = (volume.clamp(0.0, 1.0) * 100).round();
      await engine.adjustLoopbackSignalVolume(v);
    } catch (e) {
      debugPrint('Agora 系统声音量设置失败：$e');
    }
  }

  // ── 外放 / 麦克风开关 ──────────────────────────────────────────────────

  /// 观众端强制外放（扬声器出声）。声网的音频路由归声网引擎管——
  /// flutter_webrtc 的 Helper.setSpeakerphoneOn 对它完全无效，还会抢
  /// Android AudioManager 的 audio focus 把 GameStreaming 场景的回采
  /// 打得断断续续，所以这里必须用声网自己的 setEnableSpeakerphone。
  ///
  /// join 后立即调用可能撞上引擎尚未就绪的窗口，失败不打紧：
  /// onConnectionStateChanged 变 connected 时会按 [_speakerphoneWanted]
  /// 再补一次。主持人跟随物理路由（耳机进耳机），不该调这个。
  Future<void> setSpeakerphone(bool on) async {
    _speakerphoneWanted = on;
    if (!on) _speakerphoneUserOff = true;
    await _setSpeakerphoneInternal(on);
  }

  Future<void> _setSpeakerphoneInternal(bool on) async {
    final engine = _engine;
    if (engine == null || !_initialized) return;
    try {
      await engine.setEnableSpeakerphone(on);
    } catch (e) {
      // 静默：路由由连接回调兜底重试，观众听不到声音的场景另有排查路径。
      debugPrint('Agora setEnableSpeakerphone($on) 失败：$e');
    }
  }

  /// 主持人开关麦克风发布。true = 开麦（同时启用 AI 回消 / AI 降噪），
  /// false = 闭麦。失败返回 false，调用方提示用户；绝不抛出。
  ///
  /// 开麦前请求过 RECORD_AUDIO 运行时权限是调用方（控制器）的事：
  /// 声网 SDK 原生层不弹权限框，manifest 声明不够。
  Future<bool> setMicPublished(bool on) async {
    final engine = _engine;
    if (engine == null || !_initialized) return false;
    try {
      if (on) {
        // AI 回消 / AI 降噪：处理对象是麦克风采集信号，开麦前启用一次
        // 即可（重复调无害）。provider 与 extension 是两个不同字段：
        // provider 是插件包名（agora_custom_aiaec /
        // agora_ai_noise_suppression_extension，SDK .so 里可 strings 到），
        // extension 是能力名（ai_noise_suppression 等）。名字不对 SDK 会
        // 报 not found —— 吞掉不拦开麦，最坏是没有回消降噪，不至于哑。
        const extPairs = <(String, String)>[
          ('agora_custom_aiaec', 'agora_custom_aiaec'),
          ('agora_ai_noise_suppression_extension', 'ai_noise_suppression'),
        ];
        for (final (provider, extension) in extPairs) {
          try {
            await engine.enableExtension(provider: provider, extension: extension);
          } catch (_) {
            // 名字不匹配该 SDK 版本时跳过；全失败也不拦开麦。
          }
        }
        try {
          await engine.enableAudio();
        } catch (_) {}
        try {
          await engine.setAINSMode(
            enabled: true,
            mode: AudioAinsMode.ainsModeBalanced,
          );
        } catch (_) {}
      }
      await engine.updateChannelMediaOptions(
        ChannelMediaOptions(
          publishMicrophoneTrack: on,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Agora ${on ? '开麦' : '闭麦'}失败：$e');
      return false;
    }
  }

  // ── 观众音量 ───────────────────────────────────────────────────────────

  double _remoteVolume = 1;

  /// 调远端音量（所有远端 uid 一起调，跟 SfuClient.setRemoteVolume 对齐）。
  Future<void> setRemoteVolume(double volume) async {
    final engine = _engine;
    _remoteVolume = volume.clamp(0.0, 1.0);
    if (engine == null) return;
    try {
      // Agora 的音量是 0~200（100 = 原声）。0 时静音。
      final v = (_remoteVolume * 100).round();
      // adjustUserPlaybackSignalVolume 需要指定 uid；这里对已知远端逐个调，
      // 新 uid 进来时 applyRemoteVolume 会补。
      for (final uid in _knownRemoteUids) {
        await engine.adjustUserPlaybackSignalVolume(uid: uid, volume: v);
      }
    } catch (_) {}
  }

  final Set<int> _knownRemoteUids = <int>{};

  Future<void> _applyRemoteVolume(int uid) async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.adjustUserPlaybackSignalVolume(
        uid: uid,
        volume: (_remoteVolume * 100).round(),
      );
    } catch (_) {}
  }

  // ── 收尾 ───────────────────────────────────────────────────────────────

  /// 断开并释放。
  Future<void> close() async {
    await _releaseEngine();
    _knownRemoteUids.clear();
    _speakerphoneWanted = false;
    _speakerphoneUserOff = false;
    connected.value = false;
  }
}

/// 兼容保留：旧引用已全部移除，占位避免外部 import 报错。
/// （flutter_webrtc 的 MediaStream 类型还在控制器签名里出现。）
