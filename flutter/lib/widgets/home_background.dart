import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show NetworkAssetBundle, rootBundle;
import 'package:image/image.dart' as img;

import '../data/cards.dart';
import '../services/background_cache.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// 背景图的信息：资源、原始尺寸、底部提取色。
///
/// 只放小的元数据：网络图的原始字节另存在 [_CitroBlendImageState._bytesCache]
/// 里（有总量上限），避免缓存地图无限增长。
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
  const CitroBlendImage({
    super.key,
    this.networkUrl,
    this.asset,
    this.cover = false,
    this.ratio3x4 = false,
  });

  /// 背景图下边缘相对屏幕顶部的距离（像素）。
  ///
  /// 首页用它决定卡片区的起始高度：卡片区正好从图的下边缘开始。
  static final ValueNotifier<double> bottomEdge = ValueNotifier(0);

  /// 网络图地址；为空时用 [asset] 或时段背景图。
  final String? networkUrl;

  /// 包内资源路径（assets/card/...）；优先于 [networkUrl]。
  final String? asset;

  /// 铺满整个容器（cover）而不是按屏宽缩到顶部（scaleDown）。
  ///
  /// 首页左右分栏时左栏是个窄高的面板，scaleDown 会只占上半截、
  /// 下半截露底色；cover 才能铺满整个「卡片背景」面板。
  final bool cover;

  /// 图片按 3:4 居中摆放：完整可见、不裁切，多余区域露底色。
  final bool ratio3x4;

  /// 系统内存紧张时由 App 主动清空内存缓存；磁盘缓存不受影响。
  static void clearMemory() => _CitroBlendImageState.clearMemory();

  @override
  State<CitroBlendImage> createState() => _CitroBlendImageState();
}

class _CitroBlendImageState extends State<CitroBlendImage> {
  /// 解码结果按资源地址缓存：计划 / 游戏 / 社区共用同一张背景，
  /// 不能每进一页就重解码一次。
  static final Map<String, _BgInfo> _cache = {};

  /// 网络图的原始字节缓存：磁盘命中后在这里再放一份，
  /// 上屏直接用 [Image.memory]，不再走网络。
  static final Map<String, Uint8List> _bytesCache = {};
  static int _bytesCacheTotal = 0;
  static const int _bytesCacheMaxEntries = 12;
  static const int _bytesCacheMaxBytes = 32 << 20;

  /// 同一张网络图可能被预取和下载同时请求，合并成一次。
  static final Map<String, Future<Uint8List>> _networkInFlight = {};

  static Uint8List? peekBytes(String key) => _bytesCache[key];

  static void _putBytes(String key, Uint8List bytes) {
    final old = _bytesCache.remove(key);
    if (old != null) _bytesCacheTotal -= old.lengthInBytes;
    _bytesCache[key] = bytes;
    _bytesCacheTotal += bytes.lengthInBytes;
    while ((_bytesCache.length > _bytesCacheMaxEntries ||
            _bytesCacheTotal > _bytesCacheMaxBytes) &&
        _bytesCache.isNotEmpty) {
      final first = _bytesCache.keys.first;
      final removed = _bytesCache.remove(first);
      if (removed != null) _bytesCacheTotal -= removed.lengthInBytes;
    }
  }

  /// 提前解码一张背景图（供首页双击切换前预取）。
  ///
  /// 只写缓存、不碰界面：[_load] 随后会直接命中，切换时卡片区起点
  /// 不用等新图解码完才跟着动。
  static void prefetchDecoded(String key) {
    if (_cache.containsKey(key)) return;
    unawaited(ensureReady(key));
  }

  /// 同一张背景可能被当前页和预取同时请求，合并成一次解码。
  static final Map<String, Future<_BgInfo>> _inFlight = {};

  /// 等待一张背景图解码完成并落盘缓存；登录页进入主界面用它来挡一帧。
  static Future<_BgInfo> ensureReady(String key) {
    final hit = _cache[key];
    if (hit != null) return Future<_BgInfo>.value(hit);
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = _decode(key);
    _inFlight[key] = future;
    unawaited(future.then((info) => _cache[key] = info, onError: (_) {}));
    unawaited(
      future.then(
        (_) => _inFlight.remove(key),
        onError: (_) => _inFlight.remove(key),
      ),
    );
    return future;
  }

  /// 只清内存：磁盘上的字节和元数据保留，下次启动仍然命中。
  static void clearMemory() {
    _cache.clear();
    _bytesCache.clear();
    _bytesCacheTotal = 0;
    _networkInFlight.clear();
    _inFlight.clear();
  }

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

  Future<_BgInfo> _load() {
    final key =
        widget.asset ??
        widget.networkUrl ??
        CitroTimeBackground.assetFor(DateTime.now());
    return ensureReady(key);
  }

  static Future<_BgInfo> _decode(String key) async {
    // 磁盘缓存先命中：宽高和底部色已知，不用再解码一次。
    final meta = await BackgroundCache.readMeta(key);
    if (meta != null) {
      unawaited(BackgroundCache.touch(key));
      if (key.startsWith('http')) {
        Uint8List? bytes;
        try {
          bytes = await BackgroundCache.readBytes(key);
          // 元数据在、字节不在（清理删过 / 上次没下完）：补一次下载。
          bytes ??= await _loadNetworkBytes(key);
        } catch (_) {}
        if (bytes != null) _putBytes(key, bytes);
      }
      return _BgInfo(
        key,
        Size(meta.w.toDouble(), meta.h.toDouble()),
        Color.fromRGBO(meta.r, meta.g, meta.b, 1),
      );
    }
    try {
      if (key.startsWith('http')) {
        final bytes = await _loadNetworkBytes(key);
        _putBytes(key, bytes);
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final bottom = _sampleBottom(decoded);
          unawaited(
            BackgroundCache.writeMeta(
              key,
              decoded.width,
              decoded.height,
              bottom.r.toInt(),
              bottom.g.toInt(),
              bottom.b.toInt(),
            ),
          );
          return _BgInfo(
            key,
            Size(decoded.width.toDouble(), decoded.height.toDouble()),
            bottom,
          );
        }
        // 解码失败但字节已经拿到：字节进内存缓存，让 Flutter 自己再解一次。
        return _BgInfo(key, Size.zero, CitroTimeBackground.baseColor());
      } else {
        final data = await rootBundle.load(key);
        final decoded = img.decodeImage(data.buffer.asUint8List());
        if (decoded != null) {
          final bottom = _sampleBottom(decoded);
          unawaited(
            BackgroundCache.writeMeta(
              key,
              decoded.width,
              decoded.height,
              bottom.r.toInt(),
              bottom.g.toInt(),
              bottom.b.toInt(),
            ),
          );
          return _BgInfo(
            key,
            Size(decoded.width.toDouble(), decoded.height.toDouble()),
            bottom,
          );
        }
      }
    } catch (_) {}
    return _BgInfo(key, Size.zero, CitroTimeBackground.baseColor());
  }

  /// 网络图字节：先读磁盘缓存，没有再下载并写回。
  static Future<Uint8List> _loadNetworkBytes(String url) async {
    final cached = await BackgroundCache.readBytes(url);
    if (cached != null && cached.isNotEmpty) {
      unawaited(BackgroundCache.touch(url));
      return cached;
    }
    final existing = _networkInFlight[url];
    if (existing != null) return existing;
    final future = _fetchNetworkBytes(url);
    _networkInFlight[url] = future;
    unawaited(
      future.then(
        (_) => _networkInFlight.remove(url),
        onError: (_) => _networkInFlight.remove(url),
      ),
    );
    return future;
  }

  static Future<Uint8List> _fetchNetworkBytes(String url) async {
    final bundle = NetworkAssetBundle(Uri.parse(url));
    final data = await bundle.load(url).timeout(const Duration(seconds: 12));
    final bytes = data.buffer.asUint8List();
    if (bytes.isEmpty) throw Exception('background image is empty');
    unawaited(BackgroundCache.writeBytes(url, bytes));
    return bytes;
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
        // 网络图优先用缓存字节上屏（MemoryImage），避免二次下载。
        final bytes = url != null ? _bytesCache[url] : null;
        // ratio3x4：图片完整可见（contain）并居中，其余区域露底色。
        final fit = widget.cover
            ? BoxFit.cover
            : (widget.ratio3x4 ? BoxFit.contain : BoxFit.scaleDown);
        final alignment = widget.cover || widget.ratio3x4
            ? Alignment.center
            : Alignment.topCenter;
        // 图没盖到的下方区域用奶米 #F9EDD7，和卡片区连成一整块。
        // 网络图优先用缓存字节上屏（MemoryImage），避免二次下载。
        Widget? placed;
        if (asset != null) {
          placed = Image.asset(
            asset,
            fit: fit,
            alignment: alignment,
            cacheWidth: 512,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        } else if (url != null && bytes != null) {
          placed = Image.memory(
            bytes,
            fit: fit,
            alignment: alignment,
            cacheWidth: 512,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        } else if (url != null && info != null) {
          placed = Image.network(
            url,
            fit: fit,
            alignment: alignment,
            cacheWidth: 512,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        } else if (url != null) {
          // 还在解码 / 下载：先露底色，避免 Image.network 重复下一次。
          placed = const SizedBox.shrink();
        } else {
          placed = Image.asset(
            info?.asset ?? CitroTimeBackground.assetFor(DateTime.now()),
            fit: fit,
            alignment: alignment,
            cacheWidth: 512,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        }
        if (widget.ratio3x4) {
          placed = Center(
            child: AspectRatio(aspectRatio: 3 / 4, child: placed),
          );
        }
        return ColoredBox(
          color: context.c.bg,
          child: Stack(
            fit: StackFit.expand,
            children: [placed],
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

  /// 四个时段的背景图资源；首页双击切换没有卡面时用这一组兜底。
  static const List<String> assets = [
    'assets/images/backgrounds/dawn.webp',
    'assets/images/backgrounds/day.webp',
    'assets/images/backgrounds/dusk.webp',
    'assets/images/backgrounds/night.webp',
  ];

  static String assetFor(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h < 8) return assets[0];
    if (h >= 8 && h < 17) return assets[1];
    if (h >= 17 && h < 20) return assets[2];
    return assets[3];
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
///
/// 首页双击可见的背景区域时调 `cycle()` 在背景图列表里循环换图，
/// 换图走交叉淡化（500ms，减少动态时直接跳过）。
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

  /// 背景图铺满容器（cover）而不是按屏宽缩到顶部。
  /// 首页左右分栏的左栏（窄高面板）需要它才不会下半截露底色。
  final bool cover;

  /// 背景图按 3:4 居中摆放（完整可见，不裁切）。
  final bool ratio3x4;

  const CitroAmbientBackground({
    super.key,
    this.blurred = false,
    this.blurSigma = 18,
    this.scrim = true,
    this.darkScrim = false,
    this.dim = 0,
    this.cover = false,
    this.ratio3x4 = false,
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

  /// 进入主界面前把背景准备好（登录页等待用）。
  /// 真正的实现在 [_CitroAmbientBackgroundState]，这里只做转发。
  static Future<void> prepare({BuildContext? context}) =>
      _CitroAmbientBackgroundState.prepare(context: context);

  /// 把当前选中的背景预载进内存/磁盘缓存。
  static void precache(BuildContext context) =>
      _CitroAmbientBackgroundState.precache(context);

  /// 双击首页背景：在背景图列表里循环切换。
  ///
  /// 真正的状态在 [_CitroAmbientBackgroundState]（多个页面共享同一张背景），
  /// 这里只做转发，供首页等外部调用。
  static void cycle() => _CitroAmbientBackgroundState.cycle();

  @override
  State<CitroAmbientBackground> createState() => _CitroAmbientBackgroundState();
}

class _CitroAmbientBackgroundState extends State<CitroAmbientBackground> {
  /// 多个页面共享同一张卡面：首页先选，其余 tab 直接复用。
  static CardFace? _cachedFace;

  /// 可切换的背景列表：已收藏的卡面。一张都没有时退回时段背景图。
  static List<CardFace> _faces = const [];

  /// 当前背景在列表里的下标；-1 表示还没选过。
  static int _index = -1;

  /// 没有卡面时双击强制的时段图；null 表示跟随时间自动选。
  static String? _timeAsset;

  /// 列表是否已就绪：没就绪时双击不响应，避免切到半加载的列表。
  static bool _listReady = false;

  /// 背景切换版本号：自增一次，所有 [CitroAmbientBackground] 一起换图。
  static final ValueNotifier<int> _revision = ValueNotifier(0);

  /// 背景交叉淡化时长：整屏大面积过渡，比 UI 动效慢一档（500ms），
  /// 太短会闪、太长会拖。减少动态时由 [CitroMotion.guard] 归零。
  static const Duration _bgFade = Duration(milliseconds: 500);

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _revision.addListener(_onRevision);
    unawaited(_pick());
  }

  @override
  void dispose() {
    _revision.removeListener(_onRevision);
    super.dispose();
  }

  /// 双击首页背景：在背景图列表里循环切换。
  ///
  /// 列表是已收藏的卡面；一张都没有时退回时段背景图（清晨 / 白天 /
  /// 傍晚 / 夜晚）。切换的交叉淡化由 build 里的 [AnimatedSwitcher] 做。
  static void cycle() {
    if (!_listReady) return;
    if (_faces.isEmpty) {
      _timeAsset = _nextTimeAsset();
      _cachedFace = null;
    } else {
      _index = (_index + 1) % _faces.length;
      _cachedFace = _faces[_index];
      _timeAsset = null;
    }
    _revision.value++;
  }

  /// 下一张时段背景图（在 [CitroTimeBackground.assets] 里循环）。
  static String _nextTimeAsset() {
    final assets = CitroTimeBackground.assets;
    final current = _timeAsset;
    if (current == null) return assets.first;
    return assets[(assets.indexOf(current) + 1) % assets.length];
  }

  /// 当前背景的资源：本地资源优先，其次网络图。
  static (String?, String?) get _source {
    final face = _cachedFace;
    return (
      _timeAsset ?? (face != null && face.isAsset ? face.asset : null),
      face != null && !face.isAsset ? face.url : null,
    );
  }

  /// 下一张背景的资源，用于提前预取。
  static (String?, String?) get _nextSource {
    if (_faces.isEmpty) return (_nextTimeAsset(), null);
    final face = _faces[(_index + 1) % _faces.length];
    return (face.isAsset ? face.asset : null, face.isAsset ? null : face.url);
  }

  /// 与 [CitroBlendImage] 的 `cacheWidth: 512` 完全一致的 provider：
  /// 预取要写进同一个 [ImageCache] key 才算数。
  /// 网络图有缓存字节时用 [MemoryImage]，避免预取再走一次网络。
  static ImageProvider _providerFor(String? asset, String? url) {
    if (asset != null) return ResizeImage(AssetImage(asset), width: 512);
    if (url != null) {
      final bytes = _CitroBlendImageState.peekBytes(url);
      if (bytes != null) return ResizeImage(MemoryImage(bytes), width: 512);
      return ResizeImage(NetworkImage(url), width: 512);
    }
    return ResizeImage(
      AssetImage(CitroTimeBackground.assetFor(DateTime.now())),
      width: 512,
    );
  }

  /// 已收藏卡面列表就绪流程：只在没就绪时跑一次，之后由 cycle() 换图。
  static Future<void> _ensureList() async {
    if (_listReady) return;
    await CardCatalog.ensureLoaded();
    _applyOwned();
  }

  static void _applyOwned() {
    final owned = AppState.instance.ownedCards
        .map((id) => CardCatalog.byId(id))
        .whereType<CardFace>()
        .toList();
    _faces = owned;
    _listReady = true;
    // 只在没选过时随机一次；之后换图由 cycle() 驱动。
    if (_cachedFace == null) {
      final i = owned.isEmpty ? -1 : math.Random().nextInt(owned.length);
      _index = i;
      _cachedFace = i < 0 ? null : owned[i];
    }
    if (owned.isEmpty) {
      // 没有卡面时显示时段背景图；固定下来，预载和首帧才是同一张。
      _cachedFace = null;
      _index = -1;
      _timeAsset ??= CitroTimeBackground.assetFor(DateTime.now());
    } else {
      _timeAsset = null;
    }
  }

  static Future<void>? _prepareFuture;

  /// 登录页进入主界面前调用：选定背景并确保它已下载 / 解码、写入磁盘缓存。
  ///
  /// 返回同一个 future，可重复 await；失败不抛——背景加载失败
  /// 不该把人挡在主界面之外。
  static Future<void> prepare({BuildContext? context}) {
    final existing = _prepareFuture;
    if (existing != null) {
      if (context != null) unawaited(existing.then((_) => precache(context)));
      return existing;
    }
    final future = _prepare();
    _prepareFuture = future;
    if (context != null) return future.then((_) => precache(context));
    return future;
  }

  static Future<void> _prepare() async {
    try {
      await _ensureList();
      final source = _source;
      // _applyOwned 在没有卡面时会固定一张时段背景图；这里的兜底
      // 再防一次「列表还没就绪」的极端情况。
      final key =
          source.$1 ??
          source.$2 ??
          CitroTimeBackground.assetFor(DateTime.now());
      await _CitroBlendImageState.ensureReady(key);
      _prefetchNextStatic();
    } catch (_) {
      // 背景准备失败不阻塞进入主界面。
    }
  }

  /// 把当前背景提前塞进 Flutter 的 [ImageCache]，首帧不再现场解码。
  static void precache(BuildContext context) {
    if (!context.mounted) return;
    final source = _source;
    unawaited(
      precacheImage(
        _providerFor(source.$1, source.$2),
        context,
        onError: (_, _) {},
      ),
    );
  }

  static void _prefetchNextStatic() {
    final source = _nextSource;
    final key = source.$1 ?? source.$2;
    if (key == null) return;
    _CitroBlendImageState.prefetchDecoded(key);
  }

  Future<void> _pick() async {
    await CardCatalog.ensureLoaded();
    if (!mounted) return;
    _applyOwned();
    if (mounted) {
      setState(() => _ready = true);
    }
    unawaited(_prefetchNext());
  }

  void _onRevision() {
    if (!mounted) return;
    // 只是让 build 重跑一次去读新的 [_source]；此刻 _ready 已经是 true。
    setState(() {});
    unawaited(_prefetchNext());
  }

  /// 预取下一张背景：图片进 [ImageCache]、尺寸进解码缓存，
  /// 切换时才不闪白、卡片区起点也不用等新图解码。
  Future<void> _prefetchNext() async {
    final source = _nextSource;
    final asset = source.$1;
    final url = source.$2;
    if (asset == null && url == null) return;
    await _CitroBlendImageState.ensureReady(asset ?? url!);
    if (!mounted) return;
    unawaited(
      precacheImage(
        _providerFor(asset, url),
        context,
        // 预取失败不算错误：真切到这张时 [CitroBlendImage] 的 errorBuilder
        // 会兜底，这里也不必把异常抛给全局错误上报。
        onError: (_, _) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 卡面原图已打包进包内，优先用本地资源；否则退回网络图 / 时段背景。
    final source = _source;
    final blend = CitroBlendImage(
      key: ValueKey('${source.$1 ?? ''}|${source.$2 ?? ''}'),
      asset: source.$1,
      networkUrl: source.$2,
      cover: widget.cover,
      ratio3x4: widget.ratio3x4,
    );
    // 首帧不包 AnimatedSwitcher：从时段背景硬切到选中的卡面是原本的行为，
    // 不让它多一段淡入；就绪之后的每次换图才交叉淡化。
    Widget image = blend;
    if (_ready) {
      image = AnimatedSwitcher(
        duration: CitroMotion.guard(context, _bgFade),
        switchInCurve: CitroMotion.curveFor(context, CitroMotion.easeInOut),
        switchOutCurve: CitroMotion.curveFor(context, CitroMotion.easeInOut),
        child: blend,
      );
    }
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
          ColoredBox(color: Colors.black.withAlpha((widget.dim * 255).round())),
      ],
    );
  }
}
