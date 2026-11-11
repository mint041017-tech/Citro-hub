import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/cards.dart';
import '../state/app_state.dart';

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
    return ColoredBox(
      color: CitroTimeBackground.baseColor(),
      child: Image.asset(
        CitroTimeBackground.assetFor(DateTime.now()),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 512,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
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

  const CitroAmbientBackground({
    super.key,
    this.blurred = false,
    this.blurSigma = 18,
    this.scrim = true,
    this.darkScrim = false,
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
    Widget image = (_ready && _face != null)
        ? Image.network(
            _face!.url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 512,
            errorBuilder: (_, _, _) => const CitroTimeBackground(),
          )
        : const CitroTimeBackground();
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
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        useDark
            ? CitroAmbientBackground.scrimDark
            : CitroAmbientBackground.scrimLight,
      ],
    );
  }
}
