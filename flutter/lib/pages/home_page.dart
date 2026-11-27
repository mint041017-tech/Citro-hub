import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/quotes.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_page.dart' deferred as calendarPage;
import '../calendar/calendar_store.dart';
import '../services/api.dart';
import '../services/clock.dart';
import '../services/haptics.dart';
import '../overlays/appreciation_sheet.dart';
import '../overlays/card_collection.dart';
import '../overlays/lantern_sheet.dart';
import '../overlays/weather_sheet.dart';
import '../services/lantern_api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/lunar.dart';
import '../widgets/card_flight.dart';
import '../widgets/card_morph.dart';
import '../widgets/desktop_shell.dart';
import '../widgets/shared_element.dart';
import '../widgets/home_background.dart';
import '../widgets/home_bento.dart';
import '../widgets/home_entries.dart';
import '../widgets/home_layout.dart';
import '../mbti/home_card.dart';
import '../widgets/paper.dart';
import '../widgets/todo_home_card.dart';
import '../widgets/mood_home_card.dart';
import '../widgets/ledger_home_card.dart';
import '../widgets/lazy_page.dart';
import '../widgets/tablet_shell.dart';
import 'cook_page.dart' deferred as cookPage;
import 'me_page.dart';
import 'web_home.dart';

String _weekdayLabel(DateTime d) {
  const names = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  return names[d.weekday - 1];
}

class HomePage extends StatefulWidget {
  final ValueChanged<int> onSwitchTab;
  const HomePage({super.key, required this.onSwitchTab});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();

  /// 当前背景露出高度与卡片覆盖比例（驱动背景模糊）。
  ///
  /// 背景图尺寸是异步解码的：图信息晚到时如果让英雄区变矮，整页滚动内容会
  /// 突然缩短，[ScrollView] 会把用户正在拖动的位置钳回顶部（表现为「刚进
  /// 主界面几秒内怎么拖都被拉回原位」）。所以同一尺寸下只允许增高，不允许
  /// 回缩；只有屏幕/窗口尺寸变化时才重新计算。
  double _bgHeight = 0;
  Size? _bgLayoutSize;

  /// 卡片覆盖比例（0..1），驱动背景模糊强度。
  ///
  /// 用 ValueNotifier 而不是 setState 字段：滚动路径上每帧都会更新它，
  /// setState 会把整页（含 HomeBento 卡片栅格）连带重新 build/layout；
  /// ValueNotifier 只通知真正依赖它的背景层那一个 builder。
  final ValueNotifier<double> _bgCover = ValueNotifier<double>(0);

  /// 越界位移（像素）：顶部下拉为正，底部上推为负。
  ///
  /// 回弹由 [BouncingScrollPhysics] 产生；背景图按这个值等比缩放，
  /// 弹回时同步归零。同样只通知背景层，不重建卡片。
  final ValueNotifier<double> _overscroll = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    CitroBlendImage.bottomEdge.addListener(_onBgEdge);
    _scroll.addListener(_onScrollOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showLanternWelcomeIfNeeded(context);
    });
  }

  /// 背景图解码完成后，卡片区起点跟着图的下边缘走。
  void _onBgEdge() {
    if (mounted) setState(() {});
  }

  /// 双击英雄区（背景可见的那一块）切换背景图。
  ///
  /// 手势只挂在这里：卡片、顶栏、横滑切 Tab 都不经过它；单击也不会被吞
  /// （只认双击，单击照常落空）。
  /// 英雄区上一次点击的时间与位置，用来识别双击。
  ///
  /// 用 Listener 的原始指针事件而不是 GestureDetector 的 onDoubleTap：
  /// 手势竞技场里双击识别器会和首页的滚动/回弹抢，导致下拉被拖住。
  DateTime? _lastHeroTapAt;
  Offset? _lastHeroTapPos;

  void _onHeroPointerDown(PointerDownEvent event) {
    final now = DateTime.now();
    final lastAt = _lastHeroTapAt;
    final lastPos = _lastHeroTapPos;
    final isDoubleTap =
        lastAt != null &&
        lastPos != null &&
        now.difference(lastAt) < const Duration(milliseconds: 320) &&
        (event.position - lastPos).distance < 40;
    _lastHeroTapAt = now;
    _lastHeroTapPos = event.position;
    if (isDoubleTap) {
      _lastHeroTapAt = null;
      _lastHeroTapPos = null;
      unawaited(Haptics.breath());
      CitroAmbientBackground.cycle();
    }
  }

  void _onScrollOffset() {
    if (!_scroll.hasClients) return;
    final cover = (_scroll.offset / _bgHeight).clamp(0.0, 1.0);
    // 只在超过 1% 时才写 notifier（避免每像素一帧），但只通知背景层，
    // 不再 setState 整页——卡片栅格在滚动时保持不重建。
    if ((cover - _bgCover.value).abs() > .01) {
      _bgCover.value = cover;
    }
    final position = _scroll.position;
    final over = position.pixels < position.minScrollExtent
        ? position.minScrollExtent - position.pixels
        : position.pixels > position.maxScrollExtent
        ? -(position.pixels - position.maxScrollExtent)
        : 0.0;
    if (over != _overscroll.value) _overscroll.value = over;
  }

  @override
  void dispose() {
    CitroBlendImage.bottomEdge.removeListener(_onBgEdge);
    _scroll.removeListener(_onScrollOffset);
    _overscroll.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = CitroLayoutScope.maybeOf(context);
    // 只有「Web 宽屏但仍走移动壳」（竖屏的宽窗口）才用网页专用首页。
    // 横屏已经进了桌面壳（tabletNav），这里直接落到下面 Windows 同款分栏首页。
    if (kIsWeb &&
        !(layout?.tabletNav ?? false) &&
        MediaQuery.sizeOf(context).width >= 1025) {
      return WebHomePage(onSwitchTab: widget.onSwitchTab);
    }
    final media = MediaQuery.sizeOf(context);
    final width = layout?.contentWidth ?? media.width;
    final duoWide = (layout?.duo ?? false) && media.width > media.height;
    final wide = width >= 780 || (duoWide && width >= 600);
    final maxWidth = wide ? 1120.0 : 760.0;
    final form = wide ? HomeForm.wide : HomeForm.compact;
    final sideNav = layout?.tabletNav ?? false;
    // 卡片区四周同一个留白：左右 = 顶部 = _panelGap（宽屏居中时左右取余量）。
    final side = math.max(_panelGap, (width - maxWidth) / 2);
    // 桌面分栏：首页左栏放卡片背景，右栏放卡片区。
    // Windows 桌面壳与平板横屏（iPad / Android 平板）都走这套，
    // 手机与平板竖屏仍是原来的上下结构。
    final split = (layout?.splitHome ?? false) && wide;

    // 顶栏（账号 + 日期）固定占位，卡片从它下缘开始滚，两者不重叠。
    final topBarReserved = MediaQuery.paddingOf(context).top + 56;
    // 卡片面板的顶边落在屏幕的这个高度上（默认约 2/3）；
    // 英雄区（背景 + 打招呼）= 这段高度减去顶栏。
    final heroBottom = wide
        ? math.min(480.0, media.height * .60)
        : (media.height * .58).clamp(400.0, 560.0);
    // 卡片面板的顶边：优先落在背景图的下边缘；图还没解码出来时按「视口
    // 55%」估算 —— 与 [CitroBlendImage] 对图片显示高度的封顶一致，
    // 图信息晚到后英雄区不会忽然变矮。
    final bgEdge = CitroBlendImage.bottomEdge.value;
    final rawBg = bgEdge > 0
        ? math.max(120.0, bgEdge - topBarReserved)
        : math.max(
            120.0,
            math.min(heroBottom, media.height * 0.55) - topBarReserved,
          );
    final nextBgHeight = math.min(rawBg, media.height * 0.55);
    if (_bgLayoutSize != media) {
      // 首次布局 / 旋转 / 窗口尺寸变化：允许重新定高。
      _bgLayoutSize = media;
      _bgHeight = nextBgHeight;
    } else {
      // 同一尺寸下图片尺寸晚到：只增高不回缩，滚动内容不会突然变短。
      _bgHeight = math.max(_bgHeight, nextBgHeight);
    }
    final bgHeight = _bgHeight;

    return Stack(
      children: [
        // 背景层：铺满全屏，固定不动。清晰度随卡片覆盖下降（卡片上滑盖住
        // 背景时背景变糊）；越界回弹时按同一比例缩放，弹回时同步归位。
        // Windows 左右分栏时背景只属于左栏，不在这里铺。
        // 模糊强度从滚动 notifier 读：滚动时只有这一层重建，
        // 不会把上面的卡片栅格一起拖下水（旧实现每 1% 滚动
        // setState 整页，是滑动掉帧的主因之一）。
        if (!split)
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _bgCover,
                builder: (context, cover, _) => ValueListenableBuilder<double>(
                  valueListenable: _overscroll,
                  builder: (context, over, child) =>
                      _zoomOnOverscroll(over, child!),
                  child: CitroAmbientBackground(
                    blurred: true,
                    blurSigma: cover * 16,
                    darkScrim: true,
                    // 深色主题下把背景图再压暗一点。
                    dim: 0.18,
                  ),
                ),
              ),
            ),
          )
        else
          // 分栏：整窗铺同一张背景（重模糊 + 罩面），左栏再放清晰的原图，
          // 右栏卡片浮在模糊背景上——像 iPad 的小组件页。
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: context.c.bg),
                    CitroAmbientBackground(
                      lowRes: true,
                      blurred: false,
                      scrim: false,
                      cover: true,
                      washMin: context.c.dark ? .64 : .40,
                      washColor: context.c.field(FieldTone.deep).bg,
                    ),
                  ],
                ),
              ),
            ),
          ),
        // 卡片区的磨砂底：同一张背景图的低清放大版（天然重模糊、零滤镜开销），
        // 只露出在卡片面板顶边以下，顶边跟着滚动走——上面是清晰的原图，
        // 卡片像一张磨砂玻璃板压在图上，这就是 iOS 小组件页的观感。
        if (!split)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _scroll,
                builder: (context, child) {
                  final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                  // 顶栏实高 = 安全区 + 8 上边距 + 42 内容。
                  final barH = MediaQuery.paddingOf(context).top + 50;
                  final top = (barH + bgHeight - offset).clamp(
                    0.0,
                    media.height,
                  );
                  return ClipRRect(
                    clipper: _PanelBackdropClipper(
                      top: top,
                      radius: _panelRadius,
                    ),
                    child: child,
                  );
                },
                child: RepaintBoundary(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: context.c.bg),
                      // 色场底：同一张图的柔化版 + 主色家族的罩面（自适应：
                      // 偏暗的图会自动加厚，卡片上的灰字始终读得清）。
                      CitroAmbientBackground(
                        lowRes: true,
                        blurred: false,
                        scrim: false,
                        cover: true,
                        washMin: context.c.dark ? .48 : .24,
                        washColor: context.c.field(FieldTone.deep).bg,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // 顶栏固定 + 下方内容。
        Positioned.fill(
          child: Column(
            children: [
              // Windows 左右分栏时顶栏自带底色，和右栏卡片区连成一体。
              _HomeTopBar(side: side, solid: split, empty: split),
              Expanded(
                child: split
                    ? _splitBody(width: width, side: side, sideNav: sideNav)
                    : SingleChildScrollView(
                        key: const ValueKey('home-scroll'),
                        controller: _scroll,
                        // 顶部 / 底部都保留回弹：越界量驱动背景等比缩放。
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: bgHeight,
                              // 双击这块可见背景换图：命中区就是英雄区
                              // （顶栏以下、卡片以上），不压到卡片点击。
                              // 用 Listener 而不是 GestureDetector：
                              // 后者要进手势竞技场，会把首页的下拉拖拽一起拖住；
                              // Listener 只旁观指针，不参与竞争。
                              child: Listener(
                                behavior: HitTestBehavior.translucent,
                                onPointerDown: _onHeroPointerDown,
                                child: _HomeHeader(side: side),
                              ),
                            ),
                            _cardsPanelWidget(
                              side: side,
                              sideNav: sideNav,
                              form: form,
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 越界位移换算成背景等比缩放：顶部下拉放大，底部上推缩小。
  Widget _zoomOnOverscroll(double over, Widget child) {
    if (over == 0) return child;
    final ratio = (over.abs() / 360).clamp(0.0, 1.0);
    return Transform.scale(
      scale: over > 0 ? 1 + ratio * .12 : 1 - ratio * .06,
      alignment: over > 0 ? Alignment.topCenter : Alignment.bottomCenter,
      child: child,
    );
  }

  /// 卡片面板：上下结构的滚动视图与 Windows 左右分栏的右栏共用。
  Widget _cardsPanelWidget({
    required double side,
    required bool sideNav,
    required HomeForm form,
    double topPad = _panelGap,
  }) => _CardsPanel(
    // 同心圆角：面板圆角 = 卡片圆角 + 留白，外圈和内圈的弧线平行。
    radiusTop: _panelRadius,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(side, topPad, side, sideNav ? 92 : 108),
          child: HomeBento(form: form, builder: _cardFor),
        ),
        const SizedBox(height: 18),
        Center(
          child: Pressable(
            onTap: () => showAppreciationSheet(context),
            child: Text(
              'Citro · 今天也要开心',
              style: context.body(
                size: CitroType.small,
                color: context.c.inkSoft,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    ),
  );

  /// Windows 左右分栏：左栏是「卡片背景」（背景图满高 + 问候语），
  /// 右栏是卡片区（独立滚动）。
  Widget _splitBody({
    required double width,
    required double side,
    required bool sideNav,
  }) {
    // 背景图按 3:4 摆放、四边留一样宽的边距：
    // 面板宽 = 0.75 × (正文高 − 2m) + 2m，图才不会被裁掉。
    const bgInset = 16.0;
    return LayoutBuilder(
      builder: (context, cons) {
        // 原来这里还套了一层 min(width * .5, …)：常见窗口宽度下 0.5 会先夹住，
        // 左栏内框变成 0.72 左右，上下留白比左右大得多 —— 看上去就是「摆放不协调」。
        // 现在只保证右栏卡片区不低于 320，其余全交给 3:4 反推。
        final ideal = 0.75 * (cons.maxHeight - 2 * bgInset) + 2 * bgInset;
        final leftWidth = math.min(
          math.max(240.0, ideal),
          math.max(240.0, width - AppSpacing.x2 - 300.0),
        );
        // 栅格要按右栏的真实宽度选：整页 width 在分栏下有 970+，右栏只剩
        // 450 上下，照整页取 12 栏每格只有 25px，卡片文字必然溢出。
        final colWidth = cons.maxWidth - leftWidth - AppSpacing.x2;
        // 选哪种栅格看「每格宽度」：行高是固定的 50，格子一宽卡片就被拉成
        // 450×174 的扁片（全屏两列时），格子一窄文字又挤爆（100 出头）。
        // 目标是每格 65 上下 —— 两种栅格里挑离它更近的那个。
        const cellTarget = 65.0;
        final compactCell =
            (colWidth - (HomeForm.compact.columns - 1) * HomeForm.compact.gap) /
            HomeForm.compact.columns;
        final wideCell =
            (colWidth - (HomeForm.wide.columns - 1) * HomeForm.wide.gap) /
            HomeForm.wide.columns;
        // 十二列栅格至少要 55 一格：分栏右栏只有 580-750 宽时，
        // 十二列会算出 36-50 一格，三格宽卡片就成了又窄又高的柱子。
        final useWide =
            wideCell >= 55 &&
            (wideCell - cellTarget).abs() < (compactCell - cellTarget).abs();
        final colForm = useWide ? HomeForm.wide : HomeForm.compact;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: leftWidth,
              child: Padding(
                padding: const EdgeInsets.all(bgInset),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      // 图按卡片同款圆角裁，四条边再渐隐进页面底色，
                      // 不要硬边（用户要求「和卡片同款圆角 + 边缘虚化」）。
                      child: _FeatheredEdges(
                        radius: CitroColors.radii.card,
                        sigma: 14,
                        child: ValueListenableBuilder<double>(
                          valueListenable: _overscroll,
                          builder: (context, over, child) =>
                              _zoomOnOverscroll(over, child!),
                          child: CitroAmbientBackground(
                            blurred: false,
                            blurSigma: 0,
                            darkScrim: true,
                            dim: 0.18,
                            ratio3x4: true,
                          ),
                        ),
                      ),
                    ),
                    Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _onHeroPointerDown,
                      // side 是整页的留白（全屏下能到 300），左栏里不能用，
                      // 否则打招呼语被挤成三行。这里最多留一个 bgInset。
                      child: _HomeHeader(side: math.min(side, bgInset)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: ColoredBox(
                // 右栏透明：卡片直接浮在整窗的模糊背景上。
                color: Colors.transparent,
                child: SingleChildScrollView(
                  key: const ValueKey('home-scroll'),
                  controller: _scroll,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  child: _cardsPanelWidget(
                    // side 是整页居中用的留白（全屏 (width-1120)/2 能到 300），
                    // 右栏不能跟着用，否则卡片被挤成 80px 宽、文字全溢出。
                    side: _panelGap,
                    sideNav: sideNav,
                    form: colForm,
                    // 左栏图片从 body 顶 + 16 开始，卡片顶边也要落在同一条线上。
                    topPad: _panelGap,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 首页卡片的内容映射：栅格只负责位置，卡片自身保持原来的交互与动效。
  ///
  /// 色场重设计：每个模块包一层 [CitroFieldScope]，按模块分配色调——
  /// 待办是最饱和的主色块（视觉重心），其余按浅 / 暖 / 深 / 玻璃错开。
  Widget _cardFor(HomeSlot slot) =>
      CitroFieldScope(tone: _toneFor(slot.id), child: _cardBody(slot));

  static FieldTone _toneFor(HomeCardId id) => switch (id) {
    // 主色：每屏最多一两块，最常用的放这里。
    HomeCardId.todo => FieldTone.primary,
    HomeCardId.checkin => FieldTone.primary,
    // 深色：压住画面，和主色形成最大明暗对比。
    HomeCardId.ledger => FieldTone.deep,
    HomeCardId.tingyu => FieldTone.deep,
    HomeCardId.quote => FieldTone.deep,
    // 暖色 / 浅色：中间层。
    HomeCardId.mood => FieldTone.warm,
    HomeCardId.mbti => FieldTone.warm,
    HomeCardId.game => FieldTone.warm,
    HomeCardId.weather => FieldTone.light,
    HomeCardId.calendar => FieldTone.light,
    HomeCardId.cook => FieldTone.glass,
    // 玻璃：信息少的入口。
    HomeCardId.cardCollection => FieldTone.glass,
    HomeCardId.res => FieldTone.light,
  };

  Widget _cardBody(HomeSlot slot) => switch (slot.id) {
    HomeCardId.checkin => const CheckinCard(),
    HomeCardId.todo => const TodoHomeCard(),
    HomeCardId.mood => const MoodHomeCard(),
    HomeCardId.ledger => const LedgerHomeCard(),
    HomeCardId.tingyu => const TingyuCard(),
    HomeCardId.weather => const WeatherCard(),
    HomeCardId.cook => const CookCard(),
    HomeCardId.calendar => const CalendarCard(),
    HomeCardId.quote => const QuoteCard(),
    HomeCardId.cardCollection => const CardCollectionEntry(),
    HomeCardId.mbti => const MbtiHomeCard(),
    HomeCardId.game => HomeGameCard(gameKey: slot.item ?? ''),
    HomeCardId.res => HomeResCard(item: slot.item ?? ''),
  };
}

/// 固定的顶部栏：账号入口 + 日期。
///
/// 上滑时卡片会盖住打招呼，但账号和日期始终留在顶部，不用跟着滚走。
/// 背景由底层的固定背景层统一提供（铺满全屏），这里只画内容。
/// 给首页左栏的背景图套上卡片同款圆角，并把四条边渐隐进页面底色。
///
/// 两层 [ShaderMask]（dstIn）分别羽化上下、左右：dstIn 只取 shader 的 alpha，
/// 「中间白、边缘透明」的渐变就是一张羽化蒙版。没用 [BackdropFilter] ——
/// Windows 上它会整块重绘，这里两个 shader 就够了。
/// 给首页左栏的背景图套上卡片同款圆角，并把四条边做**高斯**虚化。
///
/// 做法是先离线画一张「圆角矩形 + MaskFilter 高斯模糊」的蒙版，
/// 再用 [ShaderMask]（dstIn）拿它的 alpha 去乘图片：框内 alpha=1 保留，
/// 沿圆角轮廓往外按高斯衰减到 0。这样边缘是真模糊，
/// 而且过度的轮廓就是圆角矩形本身，不是矩形渐变那种硬边。
///
/// 没用 [BackdropFilter]：Windows 上它会在滚动 / 弹层动画期间整块重绘，
/// 而这里蒙版只按尺寸生成一次，之后每帧只是一个 shader 采样。
class _FeatheredEdges extends StatefulWidget {
  final Widget child;
  final double radius;

  /// 边缘高斯模糊 sigma（逻辑像素）。
  final double sigma;

  const _FeatheredEdges({
    required this.child,
    required this.radius,
    this.sigma = 12,
  });

  @override
  State<_FeatheredEdges> createState() => _FeatheredEdgesState();
}

class _FeatheredEdgesState extends State<_FeatheredEdges> {
  ui.Image? _mask;
  Size _maskSize = Size.zero;
  double _maskDpr = 1;
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _mask?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, cons) {
        final size = cons.biggest;
        final mask = _mask;
        if (mask == null || _maskSize != size || _maskDpr != dpr) {
          if (!_failed) _regen(size, dpr);
          // 蒙版还没生成好：先只裁圆角，别闪一块直角出来。
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: widget.child,
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (_) => ui.ImageShader(
              mask,
              TileMode.clamp,
              TileMode.clamp,
              // 蒙版按 devicePixelRatio 栅格化，这里再缩回逻辑尺寸。
              Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1).storage,
            ),
            child: widget.child,
          ),
        );
      },
    );
  }

  void _regen(Size size, double dpr) {
    if (_busy || _failed || size.isEmpty || !size.isFinite) return;
    _busy = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _makeMask(size, dpr);
    });
  }

  Future<void> _makeMask(Size size, double dpr) async {
    final image = await _renderMask(size, dpr);
    _busy = false;
    if (!mounted) {
      image?.dispose();
      return;
    }
    if (image == null) {
      // 生成不了（比如测试环境没有栅格器）就只裁圆角，别死循环重试。
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _mask?.dispose();
      _mask = image;
      _maskSize = size;
      _maskDpr = dpr;
    });
  }

  /// 画一张圆角矩形，边缘用 [ui.MaskFilter.blur] 模糊，作为羽化蒙版。
  Future<ui.Image?> _renderMask(Size size, double dpr) async {
    final w = (size.width * dpr).round();
    final h = (size.height * dpr).round();
    if (w <= 0 || h <= 0) return null;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Radius.circular(widget.radius * dpr),
        ),
        Paint()
          ..maskFilter = ui.MaskFilter.blur(
            ui.BlurStyle.normal,
            widget.sigma * dpr,
          ),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      picture.dispose();
      return image;
    } catch (_) {
      return null;
    }
  }
}

class _HomeTopBar extends StatelessWidget {
  final double side;

  /// 是否给顶栏铺一层底色（Windows 左右分栏时需要，见调用处注释）。
  final bool solid;

  /// Windows 左右分栏：账号和日期都不显示，顶栏只留一条背景。
  final bool empty;

  const _HomeTopBar({
    required this.side,
    this.solid = false,
    this.empty = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (empty) {
      // 只保留一条背景：左右分栏时顶栏不再放内容，但必须遮住
      // Stack 最底层的负一屏（透明区域会把它露出来）。
      return SafeArea(
        bottom: false,
        // 整窗已铺模糊背景（不透明），顶栏透明即可盖住负一屏。
        child: const Padding(
          padding: EdgeInsets.only(top: AppSpacing.x1),
          child: SizedBox(height: 42),
        ),
      );
    }
    final app = context.app;
    final now = CitroClock.now();
    final user = app.user;
    // user.av 可能是相对路径，必须过 Api.imageUrl 拼成完整地址，
    // 否则 Image.network 直接失败、errorBuilder 返回空——整个圆就是空白。
    final avatarUrl = Api.imageUrl(user?.av);
    // 顶栏不单独加底色：直接压在全屏背景上，白字靠背景罩面读得清；
    // 卡片从它下缘开始滚，不会叠上来。
    return SafeArea(
      bottom: false,
      child: Container(
        color: null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            side,
            AppSpacing.x1,
            // 右侧避开 Windows 悬浮窗控（其他端 inset 为 0）。
            side + CitroDesktopShell.windowControlsInset,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Pressable(
                  onTap: () => openMePage(context),
                  hoverLift: 0,
                  hoverShadow: false,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CitroHero(
                          tag: CitroHero.tagOf('profile', 'me'),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white54),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: avatarUrl.isEmpty
                                ? Center(
                                    child:
                                        app.loggedIn &&
                                            user != null &&
                                            user.name.isNotEmpty
                                        ? Text(
                                            user.name[0],
                                            style: context.heading(
                                              size: CitroType.label,
                                              color: c.ink,
                                            ),
                                          )
                                        : AppIcon(
                                            strokeSvg(AppIcons.user, width: 2),
                                            size: 16,
                                            color: c.ink2,
                                          ),
                                  )
                                : Image.network(
                                    avatarUrl,
                                    fit: BoxFit.cover,
                                    cacheWidth: 96,
                                    errorBuilder: (_, _, _) => Center(
                                      child: AppIcon(
                                        strokeSvg(AppIcons.user, width: 2),
                                        size: 16,
                                        color: c.ink2,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.x1),
                        Flexible(
                          child: Text(
                            app.loggedIn && user != null && user.name.isNotEmpty
                                ? user.name
                                : '点击进入我的',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.body(
                              size: CitroType.label,
                              weight: CitroType.medium,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        AppIcon(
                          strokeSvg(AppIcons.chevronRight, width: 2),
                          size: 15,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x1),
              if (LanternApi.currentWindow() != null) ...[
                const LanternEntry(),
                const SizedBox(width: AppSpacing.x1),
              ],
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(28),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white24),
                ),
                child: Center(
                  child: Text(
                    '${now.month} 月 ${now.day} 日 · ${_weekdayLabel(now)}',
                    style: context.body(
                      size: CitroType.micro,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 英雄区的打招呼：跟着滚动走，上滑时被卡片盖掉。
class _HomeHeader extends StatelessWidget {
  final double side;

  const _HomeHeader({required this.side});

  static const _heroShadow = [
    Shadow(color: Color(0x59000000), blurRadius: 18, offset: Offset(0, 2)),
    Shadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final now = CitroClock.now();
    final greeting = now.hour < 6
        ? '夜深了'
        : now.hour < 11
        ? '早上好'
        : now.hour < 14
        ? '中午好'
        : now.hour < 18
        ? '下午好'
        : '晚上好';
    // 第二句按「月 + 日」轮换，不会每天都一样。
    const lines = [
      '今天也要开心',
      '慢慢来，比较快',
      '记得好好吃饭',
      '喝杯水，歇一下',
      '你已经很棒了',
      '给自己一点时间',
      '别急，事情会一件件好起来',
      '今天也是适合努力的一天',
      '把今天过好就够了',
      '照顾好自己',
    ];
    final line = lines[(now.month + now.day) % lines.length];
    return Padding(
      padding: EdgeInsets.fromLTRB(side, AppSpacing.x1, side, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          // iOS 锁屏式排版：小一号的问候在上，大号粗体的一句话在下；
          // 白字压一层柔和投影，浅色背景图上也读得清。
          Text(
            greeting,
            textAlign: TextAlign.left,
            style: context
                .heading(
                  size: CitroType.titleLg,
                  color: Colors.white.withValues(alpha: .92),
                  height: 1.2,
                )
                .copyWith(shadows: _heroShadow),
          ),
          const SizedBox(height: 2),
          Text(
            line,
            textAlign: TextAlign.left,
            style: context
                .display(
                  size: CitroType.hero,
                  color: Colors.white,
                  height: 1.12,
                  letterSpacing: -0.8,
                )
                .copyWith(shadows: _heroShadow),
          ),
          const SizedBox(height: AppSpacing.x3),
        ],
      ),
    );
  }
}

/// 下半部分的卡片面板：顶部圆角 + 一条模糊过渡带。
///
/// 过渡带是透明的，[BackdropFilter] 采到的是上半部分的背景图，
/// 于是卡片区像是从背景里「长」出来的，而不是一刀切上去。
class _CardsPanel extends StatelessWidget {
  final Widget child;
  final double radiusTop;

  const _CardsPanel({required this.child, required this.radiusTop});

  @override
  Widget build(BuildContext context) {
    // 沉浸式：卡片区不再是一整块实色底，而是一层由浅到深的罩面，
    // 背景图从卡片之间透出来；卡片本身是磨砂材质。罩面越往下越厚，
    // 长列表滚到底部时文字依然读得清。
    final c = context.c;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radiusTop)),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: c.field(FieldTone.deep).bg.withValues(alpha: .08),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class LanternEntry extends StatelessWidget {
  const LanternEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => showLanternSheet(context),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.sm(c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              strokeSvg(AppIcons.moon, width: 2),
              size: 17,
              color: c.accent,
            ),
            const SizedBox(width: 6),
            Text(
              '灯谜',
              style: context.body(
                size: CitroType.label,
                weight: CitroType.medium,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final c = context.c;
    final w = state.weather;
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      onTap: () => showWeatherDialog(context),
      // 小尺寸 bento 格里整体等比缩小，避免固定内容把卡片撑爆。
      child: LayoutBuilder(
        builder: (context, cons) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: cons.maxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.sun, width: 2),
                      size: 15,
                      color: c.accent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '天气',
                      style: context.body(
                        size: CitroType.meta,
                        weight: CitroType.medium,
                        color: c.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    AppIcon(
                      strokeSvg(AppIcons.location, width: 2),
                      size: 13,
                      color: c.inkSoft,
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        // 窄卡片上按屏宽收紧，避免和左上角标签重叠。
                        maxWidth: math.min(
                          96.0,
                          MediaQuery.sizeOf(context).width * .22,
                        ),
                      ),
                      child: Text(
                        w.city.isEmpty ? '定位中…' : w.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(
                          size: CitroType.meta,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x2),
                // 温度数字在窄格里可能比卡片宽，等比缩小而不是硬撑爆。
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        w.emoji,
                        style: const TextStyle(fontSize: 36, height: 1),
                      ),
                      const SizedBox(width: AppSpacing.x1),
                      Text(
                        '${w.temp.round()}°',
                        style: context.hand(
                          size: 50,
                          weight: CitroType.strong,
                          color: c.ink,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  w.desc,
                  textAlign: TextAlign.center,
                  style: context.heading(
                    size: CitroType.titleLg,
                    color: c.ink2,
                  ),
                ),
                const SizedBox(height: AppSpacing.x2),
                const CitroDivider(),
                const SizedBox(height: AppSpacing.x2),
                Row(
                  children: [
                    Expanded(child: CitroStat('体感', '${w.feels.round()}°')),
                    Container(width: 1, height: 28, color: c.line),
                    Expanded(child: CitroStat('湿度', '${w.humidity}%')),
                  ],
                ),
                const SizedBox(height: AppSpacing.x1),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${w.updated} 更新',
                    style: context.body(
                      size: CitroType.small,
                      color: c.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CookCard extends StatelessWidget {
  const CookCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CitroCard(
      padding: const EdgeInsets.all(16),
      onTap: () {
        final rect = CitroCardFlight.rectOf(context);
        if (rect.isEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              settings: const RouteSettings(name: 'cook'),
              builder: (_) => CitroLazyPage(
                load: () async {
                  await cookPage.loadLibrary();
                  return cookPage.CookPage();
                },
              ),
            ),
          );
          return;
        }
        CitroCardMorph.openCardPage(
          context,
          source: rect,
          settings: const RouteSettings(name: 'cook'),
          builder: (_) => CitroLazyPage(
            load: () async {
              await cookPage.loadLibrary();
              return cookPage.CookPage();
            },
          ),
          snapshot: CitroCardFlight.snapshotOf(context, rect),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 96),
        // 窄格子（小屏手机 / 双栏内屏）里图标 + 箭头会挤爆一行，
        // 这时改成竖排：图标在上，两行文字在下。
        child: LayoutBuilder(
          builder: (context, cons) {
            final icon = Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.tintYellow,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.fork, width: 2),
                  size: 28,
                  color: c.accentInk,
                ),
              ),
            );
            final text = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '食谱日记',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.heading(size: CitroType.titleLg, color: c.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  '记录今天吃了什么',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: CitroType.meta, color: c.inkSoft),
                ),
              ],
            );
            if (cons.maxWidth < 190) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.tintYellow,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.fork, width: 2),
                          size: 20,
                          color: c.accentInk,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  text,
                ],
              );
            }
            return Row(
              children: [
                icon,
                const SizedBox(width: AppSpacing.x2),
                Expanded(child: text),
                const SizedBox(width: AppSpacing.x1),
                AppIcon(
                  strokeSvg(AppIcons.arrowRight, width: 2),
                  size: 18,
                  color: c.inkSoft,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class CalendarCard extends StatefulWidget {
  /// 计划页只需要「今天」：大日期 + 星期 + 农历，不铺整月格子。
  final bool compact;

  const CalendarCard({super.key, this.compact = false});

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  int _monthOffset = 0;

  @override
  void initState() {
    super.initState();
    CalendarStore.instance.ensureInit();
  }

  void _open(BuildContext context) {
    final rect = CitroCardFlight.rectOf(context);
    if (rect.isEmpty) {
      Navigator.of(context).pushNamed('/calendar');
      return;
    }
    CitroCardMorph.openCardPage(
      context,
      source: rect,
      settings: const RouteSettings(name: '/calendar'),
      builder: (_) => CitroLazyPage(
        load: () async {
          await calendarPage.loadLibrary();
          return calendarPage.CalendarPage();
        },
      ),
      snapshot: CitroCardFlight.snapshotOf(context, rect),
    );
  }

  /// 日期上是否有倒数日 / 纪念日，供月历格显示小圆点。
  bool _hasMark(DateTime date) {
    for (final mark in CalendarStore.instance.marks) {
      if (CalendarDates.hits(mark, date)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final current = DateTime.now();
    final now = DateTime(current.year, current.month + _monthOffset, 1);
    final first = DateTime(now.year, now.month, 1);
    final startWd = first.weekday % 7;
    final days = DateTime(now.year, now.month + 1, 0).day;
    final prevDays = DateTime(now.year, now.month, 0).day;
    const wd = ['日', '一', '二', '三', '四', '五', '六'];
    final cells = <_CalCellData>[];
    for (var i = 0; i < 42; i++) {
      int day;
      int cy = now.year, cm = now.month;
      bool dim = false;
      if (i < startWd) {
        day = prevDays - startWd + 1 + i;
        dim = true;
        cm = now.month == 1 ? 12 : now.month - 1;
        if (now.month == 1) cy = now.year - 1;
      } else if (i >= startWd + days) {
        day = i - startWd - days + 1;
        dim = true;
        cm = now.month == 12 ? 1 : now.month + 1;
        if (now.month == 12) cy = now.year + 1;
      } else {
        day = i - startWd + 1;
      }
      final date = DateTime(cy, cm, day);
      final isToday =
          _monthOffset == 0 &&
          !dim &&
          day == current.day &&
          cy == current.year &&
          cm == current.month;
      cells.add(_CalCellData(day, date, dim, isToday));
    }
    return ListenableBuilder(
      listenable: CalendarStore.instance,
      builder: (context, _) => CitroCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        onTap: () => _open(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 3×3 起的小卡片只保留「今天」：大日期 + 星期 + 农历，
            // 不再铺整月日期格，避免小尺寸里 42 个日期挤成一团。
            final mini =
                widget.compact ||
                constraints.maxHeight < 210 ||
                constraints.maxWidth < 210;
            if (mini) return _todayOnly(context, current);
            final fill = constraints.hasBoundedHeight;
            // 迷你尺寸：收紧标题与字号，把空间留给 6 行日期。
            final dense =
                constraints.maxHeight < 260 || constraints.maxWidth < 240;
            Widget row(int r) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < 7; col++) ...[
                  if (col > 0) const SizedBox(width: 2),
                  Expanded(
                    child: _CalCell(
                      day: cells[r * 7 + col].day,
                      date: cells[r * 7 + col].date,
                      dim: cells[r * 7 + col].dim,
                      today: cells[r * 7 + col].today,
                      dot: _hasMark(cells[r * 7 + col].date),
                      fill: fill,
                      dense: dense,
                    ),
                  ),
                ],
              ],
            );
            final gridRows = <Widget>[
              for (var r = 0; r < 6; r++)
                if (fill)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: r == 0 ? 0 : 2),
                      child: row(r),
                    ),
                  )
                else
                  SizedBox(
                    height: 44,
                    child: Padding(
                      padding: EdgeInsets.only(top: r == 0 ? 0 : 2),
                      child: row(r),
                    ),
                  ),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '日历',
                      style: context.body(
                        size: dense ? CitroType.small : CitroType.meta,
                        weight: CitroType.medium,
                        color: c.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    Pressable(
                      onTap: () => setState(() => _monthOffset--),
                      hoverLift: 0,
                      hoverShadow: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.chevron_left_rounded,
                          size: dense ? 18 : 22,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                    Text(
                      dense ? '${now.month}月' : '${now.year}年${now.month}月',
                      style: context.hand(
                        size: dense ? CitroType.label : CitroType.bodyLg,
                        color: c.ink,
                      ),
                    ),
                    Pressable(
                      onTap: () => setState(() => _monthOffset++),
                      hoverLift: 0,
                      hoverShadow: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: dense ? 18 : 22,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x1),
                Row(
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: dense ? 2 : 4),
                          child: Text(
                            wd[i],
                            textAlign: TextAlign.center,
                            style: context.body(
                              size: dense ? CitroType.small : CitroType.label,
                              weight: CitroType.medium,
                              color: (i == 0 || i == 6) ? c.accent : c.inkSoft,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (fill)
                  Expanded(child: Column(children: gridRows))
                else
                  ...gridRows,
              ],
            );
          },
        ),
      ),
    );
  }

  /// 迷你卡片：参照系统日历小组件的排版，只显示今天。
  ///
  /// 顶部年月、左侧超大日期、底部事件卡；事件卡第一行放节日 / 节气 / 今日
  /// 标记，第二行补上公历日期与农历，保证小卡也看得见农历。
  Widget _todayOnly(BuildContext context, DateTime today) {
    final c = context.c;
    final lunar = lunarOf(today);
    final fid = festivalIdOf(today);
    final term = termToday(today);
    final marks = CalendarStore.instance.todayMarks(today);
    final headline = fid != null
        ? festivalName(fid)
        : (term ??
              (marks.isNotEmpty ? marks.first.title : weekdayChinese(today)));
    final lunarDay = lunar != null ? kLunarDayNames[lunar.day - 1] : '';
    String two(int value) => value.toString().padLeft(2, '0');
    final yearMonth =
        '${today.year}/${two(today.month)}'
        '${lunarDay.isEmpty ? '' : ' · $lunarDay'}';
    final dateLine = '${today.month}月${today.day}日';
    final markLabel = marks.isNotEmpty
        ? CalendarDates.labelFor(marks.first, today)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          yearMonth,
          style: context.body(size: CitroType.small, color: c.inkSoft),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${today.day}',
                style: context.hand(
                  size: CitroType.display,
                  weight: CitroType.strong,
                  color: c.ink,
                  height: .95,
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: CitroType.caption,
                        weight: CitroType.medium,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (markLabel != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      markLabel,
                      maxLines: 1,
                      style: context.body(
                        size: CitroType.micro,
                        color: c.stamp,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 1),
              Text(
                dateLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: CitroType.micro, color: c.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CalCellData {
  final int day;
  final DateTime date;
  final bool dim;
  final bool today;
  const _CalCellData(this.day, this.date, this.dim, this.today);
}

class _CalCell extends StatelessWidget {
  final int day;
  final DateTime date;
  final bool dim;
  final bool today;
  final bool fill;

  /// 该日期是否有倒数日 / 纪念日，有则在日期右上角点一颗小圆点。
  final bool dot;

  /// 迷你日历：缩小日期与农历字号，隐藏次要标签。
  final bool dense;
  const _CalCell({
    required this.day,
    required this.date,
    required this.dim,
    required this.today,
    this.dot = false,
    this.fill = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    String? label;
    Color? labelColor;
    if (!dim) {
      final fid = festivalIdOf(date);
      final term = termToday(date);
      if (fid != null) {
        label = festivalName(fid);
        labelColor = c.accent;
      } else if (term != null) {
        label = term;
        labelColor = c.mintInk;
      } else {
        final lu = lunarOf(date);
        if (lu != null) {
          label = lu.day == 1
              ? lu.name
              : lu.name.substring(math.max(0, lu.name.length - 2));
        }
      }
    }
    final dayColor = today
        ? c.onAccent
        : (dim ? c.inkSoft.withAlpha(140) : c.ink);
    final subColor = today
        ? c.onAccent
        : (labelColor ?? c.inkSoft).withAlpha(dim ? 140 : 255);
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      // 日历格高度随卡片尺寸变化，用 scaleDown 兜底，避免字体
      // 行高在不同平台相差半像素时出现 RenderFlex 溢出。
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: context.hand(
                  size: dense
                      ? CitroType.body
                      : (fill ? CitroType.titleLg : CitroType.title),
                  color: dayColor,
                  height: 1.05,
                ),
              ),
              if (dot)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: today
                          ? c.onAccent
                          : (dim ? c.accent.withAlpha(140) : c.accent),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(
                  size: dense ? CitroType.micro : CitroType.small,
                  color: subColor,
                  height: 1.15,
                ),
              ),
            ),
        ],
      ),
    );
    return Container(
      height: fill ? null : 44,
      padding: EdgeInsets.only(top: fill ? 2 : 3, bottom: fill ? 2 : 2),
      decoration: today
          ? BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(fill ? 12 : 10),
            )
          : null,
      // 非本月日期在上面的颜色里已经压暗，不再额外套 Opacity，
      // 避免整个日期格多一层离屏合成。
      child: content,
    );
  }
}

class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = CitroClock.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final q = kQuotes[dayOfYear % kQuotes.length];
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () =>
          copyText('${q.cn} — ${q.en}', context: context, tip: '已复制每日一言'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 112),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 250;
            final body = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.book, width: 2),
                      size: 13,
                      color: c.accent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '每日一言',
                      style: context.body(
                        size: CitroType.micro,
                        weight: CitroType.medium,
                        color: c.inkSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  '「${q.cn}」',
                  textAlign: TextAlign.center,
                  locale: const Locale('zh', 'CN'),
                  style: context.heading(
                    size: narrow ? CitroType.title : CitroType.titleLg,
                    color: c.ink,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  '— ${q.en}',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: CitroType.meta,
                    color: c.inkSoft,
                    height: 1.45,
                  ),
                ),
              ],
            );
            // 引文长短不一，整块等比缩小，宁可字小一点也不撑爆卡片。
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: body,
            );
          },
        ),
      ),
    );
  }
}

/// 卡片面板磨砂底的裁切：从 [top] 往下，顶部两角带卡片同款圆角。
class _PanelBackdropClipper extends CustomClipper<RRect> {
  final double top;
  final double radius;

  const _PanelBackdropClipper({required this.top, required this.radius});

  @override
  RRect getClip(Size size) => RRect.fromRectAndCorners(
    Rect.fromLTRB(0, top, size.width, size.height + radius),
    topLeft: Radius.circular(radius),
    topRight: Radius.circular(radius),
  );

  @override
  bool shouldReclip(_PanelBackdropClipper old) =>
      old.top != top || old.radius != radius;
}

/// 首页卡片区四周的留白（顶部 / 左右相等）。
const double _panelGap = 14;

/// 卡片区面板的顶部圆角：卡片圆角（色场 26）+ 留白，保证同心。
const double _panelRadius = 26 + _panelGap;
