import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import '../../widgets/modal.dart';
import '../../widgets/paper.dart';
import '../screen_capture.dart';
import '../screen_share_theme.dart';
import '../share_quality.dart';

/// 用户选好的共享内容 + 画质 + 是否带内容声音。
///
/// 画质在这里选而不是回房间再改：KOOK 的共享设置也是「选内容 + 分辨率 /
/// 帧率」一步完成，少一次来回。
class ShareSourcePick {
  const ShareSourcePick({
    required this.source,
    required this.quality,
    this.withAudio = true,
  });

  final ScreenSource source;
  final ShareQuality quality;

  /// 「开启内容声音」勾选框的结果（参考稿新增）。默认 true：旧调用方
  /// 不传这个字段也能编译，行为同以前（尽量带上系统声）。
  ///
  /// 弹窗只负责收集；要不要接进采集链路（传给
  /// `ScreenShareController.startSharing(withAudio: ...)` →
  /// `captureConstraints(withSystemAudio: ...)`）由调用方决定，本文件
  /// 不改 controller / screen_capture 的任何逻辑。
  final bool withAudio;
}

/// 桌面端共享源选择器：整块屏幕，或某一个应用窗口。
///
/// 为什么必须在采集**之前**选：`desktopCapturer.getSources()` 枚举时
/// 会把源塞进 flutter_webrtc 原生侧的缓存，`getDisplayMedia` 只认缓存里
/// 的 id；不选 / 传空会回落到 "0"，Windows 上直接 `source not found!`。
///
/// 枚举时让系统一并生成 320×180 的缩略图，选择器里直接展示画面预览。
/// 版式按参考稿定稿（深色直播工具风，强调色走 App 主题橙）：
///   - 标题「选择直播内容」+ 右上角白色 × + 合规副标题；
///   - 「选择应用窗口 / 选择电脑全屏」短下划线 tab（非胶囊非填充）；
///   - 固定三列 16:9 缩略图网格，纵向滚动，选中项主题橙描边 + 微光晕；
///   - 底部两行：画质 / 帧率深色胶囊下拉 + 「开启内容声音」勾选框；
///   - 最底部全宽「开始直播」，未选源置灰。
///
/// 返回 null 表示用户取消。
Future<ShareSourcePick?> showShareSourcePicker(
  BuildContext context,
  List<ScreenSource> sources, {
  ShareQuality quality = ShareQuality.fallback,
}) {
  return showCitroDialog<ShareSourcePick>(
    context,
    builder: (_) => ShareTheme(
      child: _SourcePicker(sources: sources, quality: quality),
    ),
  );
}

class _SourcePicker extends StatefulWidget {
  const _SourcePicker({required this.sources, required this.quality});

  final List<ScreenSource> sources;
  final ShareQuality quality;

  @override
  State<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<_SourcePicker> {
  late ShareQuality _quality = widget.quality;

  /// 默认停在「选择应用窗口」tab；只有屏幕可共享的机器才落到「电脑全屏」。
  late bool _screensOnly = !widget.sources.any((s) => !s.isScreen);

  /// 初始选中跟着默认 tab 走：源列表里屏幕排在窗口前面时，若直接取
  /// `sources.first` 会出现「选中项在另一个 tab 里」的错位（网格看似
  /// 没选中、按钮却能点）。
  late ScreenSource? _selected = widget.sources
      .cast<ScreenSource?>()
      .firstWhere((s) => s!.isScreen == _screensOnly, orElse: () => null);

  /// 「开启内容声音」默认勾上：与旧行为一致（尽量采系统声）。
  bool _withAudio = true;

  final GlobalKey _cardKey = GlobalKey();
  Offset? _downAt;

  /// id → 预览 JPEG。macOS 枚举时就有；Windows 是进弹窗后逐项补的。
  final Map<String, Uint8List> _previews = <String, Uint8List>{};

  /// 还在取的 id。取失败时从集合里移除，落到「暂无预览」，失败不重试。
  final Set<String> _pending = <String>{};

  @override
  void initState() {
    super.initState();
    for (final s in widget.sources) {
      final thumb = s.thumbnail;
      if (thumb != null && thumb.isNotEmpty) {
        _previews[s.id] = thumb;
      } else {
        _pending.add(s.id);
      }
    }
    if (_pending.isNotEmpty) unawaited(_loadPreviews());
  }

  /// 逐项取预览，每取到一张就刷一次 —— 窗口多的机器上，等全部取完
  /// 再显示会让弹窗白等好几秒。并发发起，原生侧会自己串行处理。
  Future<void> _loadPreviews() async {
    Future<void> loadOne(ScreenSource source) async {
      final bytes = await ScreenCapture.thumbnailFor(source.id);
      if (!mounted) return;
      setState(() {
        _pending.remove(source.id);
        if (bytes != null) _previews[source.id] = bytes;
      });
    }

    await Future.wait(<Future<void>>[
      for (final source in widget.sources)
        if (_pending.contains(source.id)) loadOne(source),
    ]);
  }

  void _pickQuality({int? width, int? frameRate}) {
    final w = width ?? _quality.width;
    final f = frameRate ?? _quality.frameRate;
    for (final p in ShareQuality.presets) {
      if (p.width == w && p.frameRate == f) {
        setState(() => _quality = p);
        return;
      }
    }
  }

  void _switchTab(bool screens) {
    if (_screensOnly == screens) return;
    setState(() {
      _screensOnly = screens;
      final group = widget.sources.where((s) => s.isScreen == screens);
      if (_selected == null || _selected!.isScreen != screens) {
        _selected = group.isEmpty ? null : group.first;
      }
    });
  }

  /// 点在卡片外 → 关闭。PaperDialog 同款命中判定：按住拖出不算，
  /// 落点在卡片矩形内不算。
  void _onPointerUp(PointerUpEvent event) {
    final down = _downAt;
    _downAt = null;
    if (down == null) return;
    if ((event.position - down).distance > 14) return;
    final box = _cardKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.contains(event.position)) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    final screens = widget.sources
        .where((s) => s.isScreen)
        .toList(growable: false);
    final windows = widget.sources
        .where((s) => !s.isScreen)
        .toList(growable: false);
    final visible = _screensOnly ? screens : windows;
    final selected = _selected;
    return Material(
      type: MaterialType.transparency,
      // 整屏 Listener + 命中判定：点卡片外关闭。路由 barrier 本身可点关
      // （showCitroDialog 的 dismissible），这里补齐卡片周边透明区域。
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _downAt = e.position,
        onPointerUp: _onPointerUp,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 参考稿：弹窗宽 min(720, 可用宽 - 32)。
              final width = math.min(720.0, constraints.maxWidth - 32);
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: SizedBox(
                    width: width,
                    child: KeyedSubtree(
                      key: _cardKey,
                      // 入场：卡片 0.96→1 缩放 + 淡入（180ms easeOutCubic），
                      // 叠在路由自带的整卡转场上，形成「卡片先到、内容再
                      // 落定」的两段节奏。
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: reduce
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => Opacity(
                          opacity: t,
                          child: Transform.scale(
                            scale: .96 + .04 * t,
                            alignment: Alignment.center,
                            child: child,
                          ),
                        ),
                        child: _buildCard(
                          context,
                          c,
                          screens: screens,
                          windows: windows,
                          visible: visible,
                          selected: selected,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    CitroColors c, {
    required List<ScreenSource> screens,
    required List<ScreenSource> windows,
    required List<ScreenSource> visible,
    required ScreenSource? selected,
  }) {
    return Container(
      // 参考稿：深色 surface 底、圆角 16、内边距 20。
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.lg(c),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '选择直播内容',
                  style: context.heading(size: CitroType.titleLg, color: c.ink),
                ),
              ),
              // 右上角白色 ×，命中区补到 44pt。
              Pressable(
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: AppSpacing.touch,
                  height: AppSpacing.touch,
                  child: Center(
                    child: AppIcon(
                      strokeSvg(AppIcons.close, width: 2),
                      size: 20,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '选择直播内容，让观众更聚焦，内容须严格遵守平台规则，'
            '严禁传播任何违法违规或不良信息',
            style: context.body(
              size: CitroType.caption,
              color: c.inkSoft,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          if (screens.isNotEmpty && windows.isNotEmpty) ...[
            _SourceTabs(screensOnly: _screensOnly, onChanged: _switchTab),
            const SizedBox(height: AppSpacing.x2),
          ],
          _buildGrid(context, c, visible),
          const SizedBox(height: AppSpacing.x2),
          // 控制行：左画质、右帧率，Spacer 拉开，各占约 45%。
          Row(
            children: [
              Expanded(
                flex: 45,
                child: _PickerDropdown(
                  label: const <int, String>{
                    1280: '720p',
                    1920: '1080p',
                    2560: '2K',
                  }[_quality.width],
                  value: _quality.width,
                  options: const <int, String>{
                    1280: '标清 720p',
                    1920: '高清 1080p',
                    2560: '2K',
                  },
                  onSelect: (w) => _pickQuality(width: w),
                ),
              ),
              const Spacer(flex: 10),
              Expanded(
                flex: 45,
                child: _PickerDropdown(
                  label: const <int, String>{
                    30: '30帧',
                    60: '60帧',
                  }[_quality.frameRate],
                  value: _quality.frameRate,
                  options: const <int, String>{30: '30帧', 60: '60帧'},
                  onSelect: (f) => _pickQuality(frameRate: f),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildAudioRow(context, c),
          const SizedBox(height: AppSpacing.x2),
          _buildStartButton(context, selected),
        ],
      ),
    );
  }

  /// 固定三列缩略图网格，纵向滚动。高度只按现有行数给：不足一屏就
  /// 收紧不留白，超过两行半封顶，网格开始滚。
  Widget _buildGrid(
    BuildContext context,
    CitroColors c,
    List<ScreenSource> visible,
  ) {
    if (visible.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            '没有可共享的内容',
            style: context.body(size: CitroType.meta, color: c.inkSoft),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final cellWidth = (constraints.maxWidth - 2 * spacing) / 3;
        // 16:9 预览 + 图下 13px 窗口名一行的总高。
        final extent = cellWidth * 9 / 16 + 26;
        final rows = (visible.length / 3).ceil();
        final height = math.min(340.0, rows * extent + (rows - 1) * spacing);
        return SizedBox(
          height: height,
          child: GridView.builder(
            padding: EdgeInsets.zero,
            itemCount: visible.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              // 参考稿：固定 3 列，不随宽度变。
              crossAxisCount: 3,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              mainAxisExtent: extent,
            ),
            itemBuilder: (context, i) {
              final source = visible[i];
              return _SourceTile(
                source: source,
                preview: _previews[source.id],
                loading: _pending.contains(source.id),
                selected: identical(source, _selected),
                onTap: () => setState(() => _selected = source),
              );
            },
          ),
        );
      },
    );
  }

  /// 「开启内容声音」勾选框 + 右侧说明。勾选切换是瞬时变色，不加动画
  /// （动效清单里只有入场 / 描边 / 下划线 / 按压四项）。
  Widget _buildAudioRow(BuildContext context, CitroColors c) {
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _withAudio = !_withAudio),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 方形圆角 4、16px；勾选态主题橙实底白勾，未勾是发丝空框。
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _withAudio
                        ? c.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _withAudio ? c.accent : c.line2,
                      width: 1.5,
                    ),
                  ),
                  child: _withAudio
                      ? Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.check, width: 3),
                            size: 10,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: AppSpacing.x1),
                Text(
                  '开启内容声音',
                  style: context.body(
                    size: CitroType.meta,
                    weight: CitroType.medium,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Text(
          '共享内容自带的音频',
          style: context.body(size: CitroType.caption, color: c.inkSoft),
        ),
      ],
    );
  }

  /// 全宽「开始直播」：主题橙实底、白字 16px、圆角 12（不再是全站胶囊）。
  /// 未选源透明度 0.4 + 吞掉点击。
  Widget _buildStartButton(BuildContext context, ScreenSource? selected) {
    final enabled = selected != null;
    final c = context.c;
    Widget button() => Material(
      color: c.accent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled
            ? () => Navigator.of(context).pop(
                ShareSourcePick(
                  source: selected,
                  quality: _quality,
                  withAudio: _withAudio,
                ),
              )
            : null,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              '开始直播',
              style: context.body(
                size: CitroType.bodyLg,
                weight: CitroType.medium,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
    if (!enabled) {
      return Opacity(opacity: .4, child: IgnorePointer(child: button()));
    }
    return button();
  }
}

/// 深色圆角胶囊下拉：胶囊里是当前值 + 下箭头，点开是深色圆角菜单。
///
/// 菜单项在选中值前画一颗主题橙对勾，比纯高亮更容易确认当前档位。
class _PickerDropdown extends StatelessWidget {
  const _PickerDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelect,
  });

  final String? label;
  final int value;
  final Map<int, String> options;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PopupMenuButton<int>(
      initialValue: value,
      color: c.surface2,
      surfaceTintColor: Colors.transparent,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 150),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.line),
      ),
      onSelected: onSelect,
      itemBuilder: (_) => [
        for (final entry in options.entries)
          PopupMenuItem(
            value: entry.key,
            height: 42,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: entry.key == value
                      ? AppIcon(
                          AppIcons.check,
                          size: 14,
                          color: c.accent,
                        )
                      : null,
                ),
                Text(
                  entry.value,
                  style: context.body(
                    size: CitroType.meta,
                    weight: entry.key == value
                        ? CitroType.medium
                        : CitroType.regular,
                    color: entry.key == value ? c.ink : c.inkSoft,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(
                  size: CitroType.meta,
                  weight: CitroType.medium,
                  color: c.ink,
                ),
              ),
            ),
            const SizedBox(width: 6),
            AppIcon(AppIcons.chevronDown, size: 14, color: c.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// 「选择应用窗口 / 选择电脑全屏」tab：选中白字 + 底部主题橙短下划线，
/// 切换时下划线平移过去（200ms），无背景无胶囊。
class _SourceTabs extends StatelessWidget {
  const _SourceTabs({required this.screensOnly, required this.onChanged});

  final bool screensOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    Widget tab(String label, bool active, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: reduce ? Duration.zero : CitroMotion.hover,
                curve: CitroMotion.easeColor,
                style: context.body(
                  size: CitroType.label,
                  weight: active ? CitroType.medium : CitroType.regular,
                  color: active ? c.ink : c.inkSoft,
                ),
                child: Text(label),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final half = constraints.maxWidth / 2;
        return SizedBox(
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  tab('选择应用窗口', !screensOnly, () => onChanged(false)),
                  tab('选择电脑全屏', screensOnly, () => onChanged(true)),
                ],
              ),
              // 短下划线指示器：随选中 tab 平移，高亮色与缩略图选中描边同源。
              AnimatedPositioned(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: CitroMotion.easeOut,
                left: screensOnly ? half : 0,
                width: half,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 28,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SourceTile extends StatefulWidget {
  const _SourceTile({
    required this.source,
    required this.preview,
    required this.loading,
    required this.selected,
    required this.onTap,
  });

  final ScreenSource source;
  final Uint8List? preview;
  final bool loading;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SourceTile> createState() => _SourceTileState();
}

class _SourceTileState extends State<_SourceTile> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!_hover) setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) {
          if (!_down) setState(() => _down = true);
        },
        onTapUp: (_) {
          if (_down) setState(() => _down = false);
        },
        onTapCancel: () {
          if (_down) setState(() => _down = false);
        },
        // 按下收到 0.98；悬停不加缩放，只把发丝边提亮预告可点。
        child: AnimatedScale(
          scale: reduce ? 1 : (_down ? .98 : 1),
          duration: reduce ? Duration.zero : CitroMotion.press,
          curve: CitroMotion.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // 选中：主题橙 2px 描边 + 25% 橙晕（blur 12），180ms 过渡。
                child: AnimatedContainer(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: CitroMotion.easeColor,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? c.accent
                          : (_hover ? c.line2 : c.line),
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: c.accent.withAlpha(64),
                              blurRadius: 12,
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                  child: _Thumbnail(
                    bytes: widget.preview,
                    loading: widget.loading,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.source.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: CitroType.meta, color: c.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.bytes, required this.loading});

  final Uint8List? bytes;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final thumb = bytes;
    if (thumb == null || thumb.isEmpty) {
      return Container(
        color: c.bg2,
        alignment: Alignment.center,
        child: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.accent,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(AppIcons.monitor, size: 22, color: c.inkSoft),
                  const SizedBox(height: 4),
                  Text(
                    '暂无预览',
                    style: context.body(
                      size: CitroType.micro,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
      );
    }
    // cacheWidth 只限制解码尺寸：窗口多的机器上，一张 4K 屏的 JPEG
    // 全尺寸解码会占几十 MB，预览格只有几百 px，没必要。
    return Image.memory(
      thumb,
      fit: BoxFit.cover,
      cacheWidth: 640,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        color: c.bg2,
        alignment: Alignment.center,
        child: AppIcon(AppIcons.monitor, size: 22, color: c.inkSoft),
      ),
    );
  }
}
