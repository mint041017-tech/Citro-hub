import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/platform.dart' as platform;
import '../services/screen_foreground.dart';
import 'share_quality.dart';

/// 一个可选项的采集源（屏幕或窗口）。
///
/// 只有桌面端能枚举；Android 只能整屏，iOS 走系统广播。
class ScreenSource {
  const ScreenSource({
    required this.id,
    required this.name,
    required this.isScreen,
    this.thumbnail,
  });

  final String id;
  final String name;
  final bool isScreen;
  final Uint8List? thumbnail;

  /// 没有名字时给个可读的标题，UI 直接用。
  String get displayLabel =>
      name.trim().isEmpty ? (isScreen ? '整个屏幕' : '窗口') : name;
}

/// 平台相关的采集封装。
///
/// 调用顺序有硬性要求（Android 14+ 尤其严格）：
///   Android：先 `requestCapturePermission()` → 再 `getDisplayMedia()`
///   iOS：先配好 Broadcast Upload Extension → 再 `getDisplayMedia({'video': {'deviceId': 'broadcast'}})`
///   桌面：`getSources()` 选源 → `getDisplayMedia()`
class ScreenCapture {
  const ScreenCapture._();

  /// 当前平台能不能发起共享。
  ///
  /// Flutter Web 不在其中：flutter_webrtc 1.6.3 的 pubspec 没有声明 web
  /// 平台，Web 观众走浏览器打开 `share.mint1017.cn` 的纯网页实现。
  static bool get canPublish =>
      !kIsWeb &&
      (platform.isWindows ||
          platform.isMacOS ||
          platform.isAndroid ||
          platform.isIOS);

  /// 发起共享前是否有「整屏 / 某个窗口」可选。
  ///
  /// 只有桌面端有枚举能力；Android 是系统弹窗授权整屏，iOS 走广播扩展。
  static bool get canPickSource =>
      !kIsWeb && (platform.isWindows || platform.isMacOS);

  /// 桌面端枚举屏幕 / 窗口。其他平台返回空列表（它们没有选择器）。
  ///
  /// `thumbnailSize` 只对 macOS 有意义：Windows 的插件实现
  /// （common/cpp `GetDesktopSources`）会把每项的 `thumbnail` 整个省掉，
  /// 只返回 id / name / type。想拿预览得逐项调用 [thumbnailFor]。
  static Future<List<ScreenSource>> listSources() async {
    if (kIsWeb || !(platform.isWindows || platform.isMacOS))
      return const <ScreenSource>[];
    try {
      final sources = await desktopCapturer.getSources(
        types: const <SourceType>[SourceType.Screen, SourceType.Window],
        thumbnailSize: ThumbnailSize(320, 180),
      );
      return sources
          .map(
            (s) => ScreenSource(
              id: s.id,
              name: s.name,
              isScreen: s.type == SourceType.Screen,
              thumbnail: s.thumbnail,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('枚举采集源失败：$e');
      return const <ScreenSource>[];
    }
  }

  /// 按 id 取一张源的预览图（JPEG 字节）。
  ///
  /// Windows 枚举时不带缩略图，但原生侧仍保留着 `MediaSource`，可以调
  /// `getDesktopSourceThumbnail` 让插件现拍一张。这个调用会同步走一遍
  /// 窗口截取，慢的窗口要几百毫秒，所以选择器是逐项加载、加载完一项就
  /// 刷新一项，而不是等全部取完再开弹窗。
  ///
  /// macOS 枚举时已经带了预览（[ScreenSource.thumbnail] 非空），调用方
  /// 不需要再走这里；测试环境没有插件，直接返回 null。
  static Future<Uint8List?> thumbnailFor(String sourceId) async {
    if (kIsWeb ||
        platform.isTest ||
        !(platform.isWindows || platform.isMacOS)) {
      return null;
    }
    try {
      final bytes = await WebRTC.invokeMethod<Uint8List, dynamic>(
        'getDesktopSourceThumbnail',
        <String, dynamic>{
          'sourceId': sourceId,
          'thumbnailSize': <String, int>{'width': 320, 'height': 180},
        },
      ).timeout(const Duration(seconds: 2));
      if (bytes == null || bytes.isEmpty) return null;
      return bytes;
    } catch (e) {
      debugPrint('取预览图失败（$sourceId）：$e');
      return null;
    }
  }

  /// 采集屏幕。
  ///
  /// [sourceId] 只在桌面端有效；Android 忽略 constraints 且只采整屏，
  /// iOS 用 `broadcast` 走系统广播扩展。
  static Future<MediaStream> captureScreen({
    required ShareQuality quality,
    String? sourceId,
    bool withSystemAudio = true,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Flutter Web 不支持原生屏幕采集，请用浏览器打开分享页');
    }

    if (platform.isAndroid) {
      // Android 14+：必须先拿 MediaProjection 授权，再开始采集，
      // 否则 createVirtualDisplay 会抛 SecurityException。
      await Helper.requestCapturePermission();
      // 授权拿到之后、开始采集之前，起前台服务占住 mediaProjection 类型。
      await startScreenForeground();
      try {
        return await navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
          'video': true,
          'audio': false,
        });
      } catch (e) {
        await stopScreenForeground();
        rethrow;
      }
    }

    if (platform.isIOS) {
      // iOS 只能走 ReplayKit 广播扩展；没配好的话这里会拿不到画面。
      return navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
        'video': <String, dynamic>{'deviceId': 'broadcast'},
        'audio': false,
      });
    }

    // Windows / macOS：可以选源，但「不选」不代表能省掉枚举。
    // 原生 getDisplayMedia（flutter_screen_capture.cc）只认「已枚举进缓存」
    // 的源：不带 deviceId 时 native 侧按 source_id="0" 找，而没有任何源
    // 的 id 是 "0"，且缓存填充只有 getSources() 这一条路。Linux 分支有
    // 「空 id 取第一块屏」的兜底，但那段在 #ifdef __linux__ 里，
    // Windows / macOS 没有 —— 缓存不填就报 "source not found!"。
    // 所以：先 getSources() 填缓存，再把真实源 id 塞进 deviceId.exact。
    var effectiveSourceId = sourceId;
    if (effectiveSourceId == null || effectiveSourceId.isEmpty) {
      final sources = await listSources();
      final screens = sources.where((s) => s.isScreen).toList();
      final picked = screens.isNotEmpty
          ? screens.first
          : (sources.isNotEmpty ? sources.first : null);
      if (picked == null) {
        throw StateError('没有可共享的屏幕或窗口');
      }
      effectiveSourceId = picked.id;
    }
    // 桌面端的 `audio: true` 走的是 WASAPI loopback（整屏）或应用级
    // loopback（单个窗口），也就是「共享内容自己的声音」。它和麦克风是
    // 两路独立音轨：一起看时朋友既能听到视频里的声音，也能听到你说话。
    //
    // 某些机器 / 精简版 Windows 上 loopback 初始化会失败，插件在 C++ 里
    // 会静默降级（audioTracks 为空）；如果整条 getDisplayMedia 抛错，
    // 再退回纯画面，不能让一次音频失败把共享整个拦住。
    try {
      final stream = await navigator.mediaDevices.getDisplayMedia(
        quality.captureConstraints(
          deviceId: effectiveSourceId,
          withSystemAudio: withSystemAudio,
        ),
      );
      // 插件在 loopback 初始化失败时会静默返回零音轨（不抛错），
      // 这里留一条诊断：设置里的系统音量滑杆就是靠它判断禁用。
      if (stream.getAudioTracks().isEmpty) {
        debugPrint('系统声音采集未返回音轨：loopback 不可用，或共享源是单个窗口');
      }
      return stream;
    } catch (e) {
      if (!withSystemAudio) rethrow;
      debugPrint('带系统声音采集失败，退回仅画面：$e');
      return navigator.mediaDevices.getDisplayMedia(
        quality.captureConstraints(deviceId: effectiveSourceId),
      );
    }
  }

  /// 停掉并释放一个流里的所有 track。
  ///
  /// 画面流（带 video track）释放时同时收掉前台服务 —— 只停麦克风不该
  /// 把「正在共享」的通知撤掉。
  static void stopStream(MediaStream? stream) {
    if (stream == null) return;
    final hasVideo = stream.getVideoTracks().isNotEmpty;
    for (final track in stream.getTracks()) {
      try {
        track.stop();
      } catch (_) {}
    }
    try {
      stream.dispose();
    } catch (_) {}
    if (hasVideo) stopScreenForeground();
  }
}
