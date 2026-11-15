import 'package:flutter/foundation.dart';

/// 画质档位：720p / 1080p / 2K × 30 / 60fps。
///
/// ⚠️ 关键事实（来自 flutter_webrtc 1.6.3 的源码核对）：
///   - Android 的 `getDisplayMedia` **完全忽略** constraints：永远是全物理
///     屏幕分辨率、固定 30fps（`GetUserMediaImpl.getDisplayMedia` 只用
///     `Display.getRealSize()` 和常量 `DEFAULT_FPS = 30`）；
///   - 桌面端只解析 `video.deviceId.exact` 和 `video.mandatory.frameRate`，
///     不解析 width / height；
///   - iOS 应用内采集固定半分辨率 + 8fps。
///
/// 所以「720p-2K 可选、30-60fps 可选」只能在**编码侧**实现：
/// 采集后通过 `RTCRtpSender.setParameters` 设 `maxBitrate` / `maxFramerate`
/// / `scaleResolutionDownBy`。这个类同时给出采集约束与编码参数。
@immutable
class ShareQuality {
  const ShareQuality({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.label,
  });

  final int width;
  final int height;
  final int frameRate;
  final String label;

  /// 由低到高排列，UI 直接用这个顺序展示。
  static const List<ShareQuality> presets = <ShareQuality>[
    p720_30,
    p720_60,
    p1080_30,
    p1080_60,
    p2k_30,
    p2k_60,
  ];

  static const ShareQuality p720_30 = ShareQuality(
    width: 1280,
    height: 720,
    frameRate: 30,
    label: '720p · 30fps',
  );
  static const ShareQuality p720_60 = ShareQuality(
    width: 1280,
    height: 720,
    frameRate: 60,
    label: '720p · 60fps',
  );
  static const ShareQuality p1080_30 = ShareQuality(
    width: 1920,
    height: 1080,
    frameRate: 30,
    label: '1080p · 30fps',
  );
  static const ShareQuality p1080_60 = ShareQuality(
    width: 1920,
    height: 1080,
    frameRate: 60,
    label: '1080p · 60fps',
  );
  static const ShareQuality p2k_30 = ShareQuality(
    width: 2560,
    height: 1440,
    frameRate: 30,
    label: '2K · 30fps',
  );
  static const ShareQuality p2k_60 = ShareQuality(
    width: 2560,
    height: 1440,
    frameRate: 60,
    label: '2K · 60fps',
  );

  static const ShareQuality fallback = p720_30;

  /// 目标码率上限（bps）。
  ///
  /// 这是**上限**而不是目标值：WebRTC 的拥塞控制（GCC）会根据网络状况
  /// 自动调低，网络好时编码器可以尽量用。以前设 2.5/4/8 Mbps 是把屏幕
  /// 内容当静态文档估的，实际播放视频/滚动页面时观感差距明显，用户反馈
  /// 「限制了流量」。现在抬到编码器在对应分辨率下真正用得上的量级：
  ///   720p 6 Mbps / 1080p 10 Mbps / 2K 20 Mbps
  /// 60fps 档 = 基准 × 1.6。真正的限制只剩网络本身。
  int get maxBitrate {
    final pixels = width * height;
    final base = pixels <= 1280 * 720
        ? 6000000
        : pixels <= 1920 * 1080
        ? 10000000
        : 20000000;
    return frameRate >= 60 ? (base * 1.6).round() : base;
  }

  /// 采集约束。`deviceId` 不在这里写死 —— 桌面端要枚举源之后再填。
  Map<String, dynamic> captureConstraints({
    String? deviceId,
    bool withSystemAudio = false,
  }) {
    final video = <String, dynamic>{
      'mandatory': <String, dynamic>{'frameRate': frameRate.toDouble()},
    };
    if (deviceId != null && deviceId.isNotEmpty) {
      video['deviceId'] = <String, dynamic>{'exact': deviceId};
    }
    return <String, dynamic>{'video': video, 'audio': withSystemAudio};
  }

  /// 发给 Worker 的画质参数（Worker 只存不校验，真正生效在客户端）。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'width': width,
    'height': height,
    'frameRate': frameRate,
  };

  static ShareQuality fromJson(Map<String, dynamic>? json) {
    if (json == null) return fallback;
    final w = (json['width'] as num?)?.toInt();
    final h = (json['height'] as num?)?.toInt();
    final f = (json['frameRate'] as num?)?.toInt();
    for (final p in presets) {
      if (p.width == w && p.height == h && p.frameRate == f) return p;
    }
    return fallback;
  }

  /// 归一化服务端返回的画质：非法值回落到 720p30，避免客户端崩在奇怪数据上。
  static ShareQuality sanitize(Map<String, dynamic>? json) => fromJson(json);

  @override
  bool operator ==(Object other) =>
      other is ShareQuality &&
      other.width == width &&
      other.height == height &&
      other.frameRate == frameRate;

  @override
  int get hashCode => Object.hash(width, height, frameRate);

  @override
  String toString() => label;
}
