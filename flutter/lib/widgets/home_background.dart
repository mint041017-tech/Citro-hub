import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show NetworkAssetBundle, rootBundle;
import 'package:image/image.dart' as img;

import '../data/cards.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 背景图的信息：资源、原始尺寸、底部提取色。
class _BgInfo {
  final String asset;
  final Size size;
  final Color bottom;

  const _BgInfo(this.asset, this.size, this.bottom);
}

/// 把背景图按「不放大、不裁切」的方式铺在顶部，下方用提取色混色过渡。
///
/// 图只占上半部（按原始比例缩到屏宽，绝不放大），
/// 未覆盖的下方区域从图底颜色渐变到主题底，避免直接一刀切。
class CitroBlendImage extends StatefulWidget {
  const CitroBlendImage({super.key, this.networkUrl, this.asset});

  /// 背景图下边缘相对屏幕顶部的距离（像素）。
  ///
  /// 首页用它决定卡片区的起始高度：卡片区正好从图的下边缘开始。
  static final ValueNotifier<double> bottomEdge = ValueNotifier(0);

  /// 网络图地址；为空时用 [asset] 或时段背景图。
  final String? networkUrl;

  /// 包内资源路径（assets/card/...）；优先于 [networkUrl]。
  final String? asset;

  @override
  State<CitroBlendImage> createState() => _CitroBlendImageState();
}

class _CitroBlendImageState extends State<CitroBlendImage> {
  /// 解码结果按资源地址缓存：计划 / 游戏 / 社区共用同一张背景，
  /// 不能每进一页就重解码一次。
  static final Map<String, _BgInfo> _cache = {};

  Future<_BgInfo>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(CitroBlendImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.networkUrl != widget.networkUrl ||
        oldWidget.asset != widget.asset) {
      _future = _load();
    }
  }

  Future<_BgInfo> _load() async {
    final key = widget.asset ??
        widget.networkUrl ??
        CitroTimeBackground.assetFor(DateTime.now());
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    final info = await _decode(key);
    _cache[key] = info;
    return info;
  }

  static Future<_BgInfo> _decode(String key) async {
    if (key.startsWith('http')) {
      try {
        final bytes = await _loadNetwork(key);
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          return _BgInfo(
            key,
            Size(decoded.width.toDouble(), decoded.height.toDouble()),
            _sampleBottom(decoded),
          );
        }
      } catch (_) {}
      return _BgInfo(key, Size.zero, CitroTimeBackground.baseColor());
    }
    try {
      final data = await rootBundle.load(key);
      final decoded = img.decodeImage(data.buffer.asUint8List());
      if (decoded != null) {
        return _BgInfo(
          key,
          Size(decoded.width.toDouble(), decoded.height.toDouble()),
          _sampleBottom(decoded),
        );
      }
    } catch (_) {}
    return _BgInfo(key, Size.zero, CitroTimeBackground.baseColor());
  }

  static Future<Uint8List> _loadNetwork(String url) async {
    final bundle = NetworkAssetBundle(Uri.parse(url));
    final data = await bundle.load(url);
    return data.buffer.asUint8List();
  }

  /// 取底部 15% 的平均色，作为下方混色的起点。
  static Color _sampleBottom(img.Image decoded) {
    final w = decoded.width;
    final h = decoded.height;
    if (w == 0 || h == 0) return CitroTimeBackground.baseColor();
    var r = 0, g = 0, b = 0, n = 0;
    final y0 = (h * 0.85).floor();
    for (var y = y0; y < h; y++) {
      for (var x = 0; x < w; x += 3) {
        final p = decoded.getPixel(x, y);
        r += p.r.toInt();
        g += p.g.toInt();
        n++;
        b += p.b.toInt();
      }
    }
    if (n == 0) return CitroTimeBackground.baseColor();
    return Color.fromRGBO(r ~/ n, g ~/ n, b ~/ n, 1);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BgInfo>(
      future: _future,
      builder: (context, snap) {
        final info = snap.data;
        final size = info?.size ?? Size.zero;
        final url = widget.networkUrl;
        final asset = widget.asset;
        // 图按原始比例缩到屏宽（不放大），下边缘就是卡片区的起点。
        if (size != Size.zero) {
          final screenW = MediaQuery.sizeOf(context).width;
          final screenH = MediaQuery.sizeOf(context).height;
          final displayW = math.min(size.width, screenW);
          // 图再高也不超过视口的 65%，给卡片区留位置（超出的部分自然被裁掉）。
          final displayH = math.min(
            size.height * (displayW / size.width),
            screenH * 0.55,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (CitroBlendImage.bottomEdge.value != displayH) {
              CitroBlendImage.bottomEdge.value = displayH;
            }
          });
        }
        // 图没盖到的下方区域用奶米 #F9EDD7，和卡片区连成一整块。
        return ColoredBox(
          color: context.c.bg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (asset != null)
                Image.asset(
                  asset,
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  cacheWidth: 512,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              else if (url != null)
                Image.network(
                  url,
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  cacheWidth: 512,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              else
                Image.asset(
                  info?.asset ?? CitroTimeBackground.assetFor(DateTime.now()),
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  cacheWidth: 512,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 随时段变化的柔光背景图（清晨 / 白天 / 傍晚 / 夜晚）。
///
/// 首页、计划、游戏、社区共用这一套：图很柔，只负责给页面一点情绪，
/// 跨小时自动换。没有别的效果（模糊由外层 [CitroAmbientBackground] 加）。
class CitroTimeBackground extends StatefulWidget {
  const CitroTimeBackground({super.key});

  static String assetFor(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 8) return 'assets/images/backgrounds/dawn.webp';
    if (h >= 8 && h < 17) return 'assets/images/backgrounds/day.webp';
    if (h >= 17 && h < 20) return 'assets/images/backgrounds/dusk.webp';
    return 'assets/images/backgrounds/night.webp';
  }

  /// 背景图还没解码出来时的底色，顺便保证任何主题下都不会闪黑。
  static Color baseColor() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 8) return const Color(0xFFFDE3C8);
    if (h >= 8 && h < 17) return const Color(0xFFFAEEDC);
    if (h >= 17 && h < 20) return const Color(0xFFF8C4A8);
    return const Color(0xFF2A2E40);
  }

  @override
  State<CitroTimeBackground> createState() => _CitroTimeBackgroundState();
}

class _CitroTimeBackgroundState extends State<CitroTimeBackground> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 每分钟看一眼，跨小时就换图。
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const CitroBlendImage();
  }
}

/// 环境背景：优先随机一张「已收藏」的卡面，没有就退回时段背景图。
///
/// 首页用它做整屏背景（随滚动加模糊），计划 / 游戏 / 社区也用它，
/// 固定高斯模糊后垫在内容底下。选中的卡面在多个页面间共享，
/// 免得每个 tab 各自随机出不同的卡。
class CitroAmbientBackground extends StatefulWidget {
  /// 是否对背景图做高斯模糊。
  final bool blurred;

  /// 模糊强度（sigma）。计划 / 游戏 / 社区建议 16–20。
  final double blurSigma;

  /// 是否铺一层主题自适应的罩面，保证直接压在背景上的文字可读。
  final bool scrim;

  /// 强制使用深色罩面（白字场景，比如首页英雄区）。
  final bool darkScrim;

  /// 深色模式下再压暗一档（0..1），让深色主题的背景图更沉稳。
  final double dim;

  const CitroAmbientBackground({
    super.key,
    this.blurred = false,
    this.blurSigma = 18,
    this.scrim = true,
    this.darkScrim = false,
    this.dim = 0,
  });

  /// 浅色主题罩面：压白，深色文字读得清。
  static const Widget scrimLight = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x66FFFFFF), Color(0x1AFFFFFF), Color(0x4DFFFFFF)],
        stops: [0, .5, 1],
      ),
    ),
  );

  /// 深色主题罩面：压黑，浅色文字读得清。
  static const Widget scrimDark = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x80000000), Color(0x1A000000), Color(0x59000000)],
        stops: [0, .5, 1],
      ),
    ),
  );

  @override
  State<CitroAmbientBackground> createState() => _CitroAmbientBackgroundState();
}

class _CitroAmbientBackgroundState extends State<CitroAmbientBackground> {
  /// 多个页面共享同一张卡面：首页先选，其余 tab 直接复用。
  static CardFace? _cachedFace;

  CardFace? _face;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_pick());
  }

  Future<void> _pick() async {
    final cached = _cachedFace;
    if (cached != null) {
      if (mounted)
        setState(() {
          _face = cached;
          _ready = true;
        });
      return;
    }
    await CardCatalog.ensureLoaded();
    if (!mounted) return;
    final owned = context.app.ownedCards
        .map((id) => CardCatalog.byId(id))
        .whereType<CardFace>()
        .toList();
    final face = owned.isEmpty
        ? null
        : owned[math.Random().nextInt(owned.length)];
    _cachedFace = face;
    if (mounted) {
      setState(() {
        _face = face;
        _ready = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 卡面原图已打包进包内，优先用本地资源；否则退回网络图 / 时段背景。
    final face = _ready ? _face : null;
    Widget image = CitroBlendImage(
      asset: face?.isAsset == true ? face!.asset : null,
      networkUrl: face?.isAsset == true ? null : face?.url,
    );
    if (widget.blurred) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: widget.blurSigma,
          sigmaY: widget.blurSigma,
        ),
        child: image,
      );
    }
    if (!widget.scrim) return image;
    final useDark =
        widget.darkScrim || Theme.maybeBrightnessOf(context) == Brightness.dark;
    // 「压暗」只看真实主题：只有深色模式才加，浅色模式背景图保持原样。
    final isDark = Theme.maybeBrightnessOf(context) == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        useDark
            ? CitroAmbientBackground.scrimDark
            : CitroAmbientBackground.scrimLight,
        if (widget.dim > 0 && isDark)
          ColoredBox(
            color: Colors.black.withAlpha((widget.dim * 255).round()),
          ),
    ],
    );
  }
}
