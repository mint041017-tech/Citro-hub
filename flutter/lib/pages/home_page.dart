import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/quotes.dart';
import '../services/fish.dart';
import '../overlays/ai_chat.dart';
import '../overlays/appreciation_sheet.dart';
import '../overlays/extra_sheets.dart';
import '../overlays/lantern_sheet.dart';
import '../overlays/zodiac_modal.dart';
import '../services/lantern_api.dart';
import '../services/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../tingyu/tingyu_controller.dart';
import '../utils/lunar.dart';
import '../widgets/card_flight.dart';
import '../widgets/card_morph.dart';
import '../widgets/home_bento.dart';
import '../widgets/home_entries.dart';
import '../widgets/home_layout.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/paper.dart';
import '../widgets/weather_widgets.dart';
import '../widgets/tablet_shell.dart';
import 'cook_page.dart';
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

class _HomePageState extends State<HomePage> {
  final ScrollController _scroll = ScrollController();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showLanternWelcomeIfNeeded(context);
      HomeLayoutStore.instance.syncFromAccount();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setEditing(bool value) {
    if (!mounted || _editing == value) return;
    setState(() => _editing = value);
    if (value) {
      HomeLayoutStore.instance.syncFromAccount(force: true);
    }
    if (value && _scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: CitroMotion.pageTouch,
        curve: CitroMotion.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1025) {
      return WebHomePage(onSwitchTab: widget.onSwitchTab);
    }
    final c = context.c;
    final layout = CitroLayoutScope.maybeOf(context);
    final media = MediaQuery.sizeOf(context);
    final width = layout?.contentWidth ?? media.width;
    final duoWide = (layout?.duo ?? false) && media.width > media.height;
    final wide = width >= 780 || (duoWide && width >= 600);
    final maxWidth = wide ? 1120.0 : 760.0;
    final layoutKey = homeLayoutKeyFor(
      wide ? HomeForm.wide : HomeForm.compact,
      media.width > media.height,
    );
    final sideNav = layout?.tabletNav ?? false;
    final side = math.max(8.0, (width - maxWidth) / 2);
    return Stack(
      children: [
        Positioned.fill(
          child: PaperBackground(
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                controller: _scroll,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  side,
                  AppSpacing.pageTop(width),
                  side,
                  sideNav ? 32 : 100,
                ),
                child: CitroStagger(
                  step: const Duration(milliseconds: 32),
                  children: [
                    ListenableBuilder(
                      listenable: NookController.instance,
                      builder: (context, _) {
                        final now = DateTime.now();
                        final lantern = LanternApi.currentWindow() != null;
                        // 页眉只承载日期与当前状态，不再放账号胶囊：
                        // 手机与 Web 窄屏在底部「我的」Tab，Windows / iPad 在侧栏头像。
                        // 播放控件已移进「听隅」卡片，页眉不再重复显示。
                        return SizedBox(
                          height: 48,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 460;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${now.month} 月 ${now.day} 日',
                                          style: context.heading(
                                            size: 19,
                                            color: c.ink,
                                            height: 1.1,
                                            letterSpacing: .4,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _weekdayLabel(now),
                                          style: context.body(
                                            size: 10.5,
                                            color: c.inkSoft,
                                            letterSpacing: .3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (lantern && !compact) ...[
                                    const LanternEntry(),
                                    const SizedBox(width: 8),
                                  ],
                                  _LayoutEditButton(
                                    editing: _editing,
                                    compact: compact,
                                    onPressed: () => _setEditing(!_editing),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    AnimatedSize(
                      duration: CitroMotion.reduced(context)
                          ? Duration.zero
                          : CitroMotion.size,
                      curve: CitroMotion.easeOut,
                      alignment: Alignment.topCenter,
                      child: _editing
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _EditHintBar(
                                onContent: () => showAddCardSheet(
                                  context: context,
                                  layoutKey: layoutKey,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    HomeBento(
                      layoutKey: layoutKey,
                      editing: _editing,
                      scrollController: _scroll,
                      builder: _cardFor,
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Pressable(
                        onTap: () => showAppreciationSheet(context),
                        child: Text(
                          'Citro · 今天也要开心',
                          style: context.body(
                            size: 10.5,
                            color: c.inkSoft.withAlpha(150),
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!sideNav)
          Positioned(
            right: math.max(18.0, (width - maxWidth) / 2 + 18),
            bottom: MediaQuery.paddingOf(context).bottom + 92,
            child: const AiHomeButton(),
          ),
      ],
    );
  }

  /// 首页卡片的内容映射：栅格只负责位置，卡片自身保持原来的交互与动效。
  Widget _cardFor(HomeSlot slot) => switch (slot.id) {
    HomeCardId.checkin => const CheckinCard(),
    HomeCardId.tingyu => const TingyuCard(),
    HomeCardId.fish => const FishCard(),
    HomeCardId.weather => const WeatherCard(),
    HomeCardId.cook => const CookCard(),
    HomeCardId.calendar => const CalendarCard(),
    HomeCardId.zodiac => const ZodiacCard(),
    HomeCardId.quote => const QuoteCard(),
    HomeCardId.game => HomeGameCard(gameKey: slot.item ?? ''),
    HomeCardId.res => HomeResCard(item: slot.item ?? ''),
  };
}

class _LayoutEditButton extends StatelessWidget {
  final bool editing;
  final bool compact;
  final VoidCallback onPressed;

  const _LayoutEditButton({
    required this.editing,
    required this.compact,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = editing ? '完成' : '调整布局';
    return Semantics(
      key: const ValueKey('home-layout-edit'),
      button: true,
      label: label,
      child: Pressable(
        onTap: onPressed,
        hoverLift: 0,
        hoverShadow: false,
        hoverColor: c.hl.withAlpha(c.dark ? 24 : 60),
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: CitroMotion.hover,
          curve: CitroMotion.easeOut,
          height: 40,
          padding: EdgeInsets.symmetric(
            horizontal: editing && !compact ? 14 : 10,
          ),
          decoration: BoxDecoration(
            color: editing ? c.accent : c.surface2.withAlpha(220),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: editing ? c.accentInk.withAlpha(50) : c.line,
            ),
            boxShadow: CitroColors.shadows.paper(c),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                strokeSvg(editing ? AppIcons.calendar : _slidersIcon, width: 2),
                size: 17,
                color: editing ? const Color(0xFF2E2C34) : c.ink2,
              ),
              if (editing && !compact) ...[
                const SizedBox(width: 5),
                Text(
                  '完成',
                  style: context.body(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: const Color(0xFF2E2C34),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static const _slidersIcon =
      '<path d="M4 7h8M16 7h4M4 17h3M11 17h9"/><circle cx="14" cy="7" r="2.2"/><circle cx="7" cy="17" r="2.2"/>';
}

class _EditHintBar extends StatelessWidget {
  final VoidCallback onContent;

  const _EditHintBar({required this.onContent});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: c.hl.withAlpha(c.dark ? 30 : 90),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              AppIcon(
                strokeSvg(_slidersIcon, width: 2),
                size: 16,
                color: c.accentInk,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  compact ? '拖圆柄换位 · 右上角删除' : '拖顶部圆柄换位 · 右上角垃圾桶删除 · 右下角调大小',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: 11.5, color: c.accentInk),
                ),
              ),
              const SizedBox(width: 8),
              Pressable(
                key: const ValueKey('home-content-open'),
                onTap: onContent,
                hoverLift: 0,
                hoverShadow: false,
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: c.line),
                  ),
                  child: Center(
                    child: Text(
                      '添加卡片',
                      style: context.body(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: c.accentInk,
                      ),
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

  static const _slidersIcon =
      '<path d="M4 7h8M16 7h4M4 17h3M11 17h9"/><circle cx="14" cy="7" r="2.2"/><circle cx="7" cy="17" r="2.2"/>';
}

class LanternEntry extends StatelessWidget {
  const LanternEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => showLanternSheet(context),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌕', style: TextStyle(fontSize: 17)),
            const SizedBox(width: 5),
            Text('灯谜', style: context.heading(size: 14, color: c.ink)),
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
    return PaperCard(
      tapeColor: c.tape,
      tapeAngle: -3,
      color: c.surface2,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      onTap: () => showWeatherSheet(context),
      child: Stack(
        children: [
          // 地名独立钉在卡片右上角：不再和「天气」标题挤在同一条基线上，
          // 字号放大后也有稳定的阅读位置。
          Positioned(
            top: -2,
            right: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  strokeSvg(AppIcons.location, width: 2),
                  size: 13,
                  color: c.inkSoft,
                ),
                const SizedBox(width: 3),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    // 窄卡片上按屏宽收紧，避免和左上角的「天气」标签重叠。
                    maxWidth: math.min(
                      96.0,
                      MediaQuery.sizeOf(context).width * .22,
                    ),
                  ),
                  child: Text(
                    w.city.isEmpty ? '定位中…' : w.city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: context
                        .heading(
                          size: 16.5,
                          color: c.ink,
                          height: 1.1,
                          letterSpacing: .2,
                        )
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '天气',
                    style: context.heading(
                      size: 12.5,
                      color: c.accentInk,
                      letterSpacing: .25,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            w.emoji,
                            style: const TextStyle(fontSize: 42, height: 1),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${w.temp.round()}°',
                            style: context.display(
                              size: 52,
                              weight: FontWeight.w700,
                              color: c.ink,
                              height: .95,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              'C',
                              style: context.body(
                                size: 14,
                                weight: FontWeight.w600,
                                color: c.ink2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      w.desc,
                      style: context.heading(
                        size: 16.5,
                        color: c.accentInk,
                        letterSpacing: .8,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: DashedLine(color: c.line.withAlpha(120)),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _WeatherMetric(
                            label: '体感',
                            value: '${w.feels.round()}°',
                            color: c,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: c.line.withAlpha(140),
                        ),
                        Expanded(
                          child: _WeatherMetric(
                            label: '湿度',
                            value: '${w.humidity}%',
                            color: c,
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${w.updated} 更新',
                        style: context.hand(size: 11, color: c.inkSoft),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeatherMetric extends StatelessWidget {
  final String label;
  final String value;
  final CitroColors color;

  const _WeatherMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Column(
      children: [
        Text(
          label,
          style: context.body(
            size: 11.5,
            weight: FontWeight.w600,
            color: c.inkSoft,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: context.display(
            size: 17,
            weight: FontWeight.w700,
            color: c.ink,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class CookCard extends StatelessWidget {
  const CookCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperCard(
      tapeColor: c.tape3,
      tapeAngle: -2.5,
      color: c.noteY,
      shadow: PaperShadow.paper,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      onTap: () {
        final rect = CitroCardFlight.rectOf(context);
        if (rect.isEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              settings: const RouteSettings(name: 'cook'),
              builder: (_) => const CookPage(),
            ),
          );
          return;
        }
        CitroCardMorph.pushPageSoft(
          context,
          source: rect,
          settings: const RouteSettings(name: 'cook'),
          builder: (_) => const CookPage(),
          snapshot: CitroCardFlight.snapshotOf(context, rect),
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: 2,
            top: 0,
            child: Transform.rotate(
              angle: 10 * math.pi / 180,
              child: const Text(
                '🍳',
                style: TextStyle(fontSize: 26, height: 1),
              ),
            ),
          ),
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.rotate(
                    angle: 0,
                    child: Column(
                      children: [
                        Text(
                          '食谱',
                          style: context.heading(
                            size: 32,
                            color: c.ink,
                            height: 1.1,
                            letterSpacing: 2,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            '日记',
                            style: context.heading(
                              size: 32,
                              color: c.accentInk,
                              height: 1.1,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.line2, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          strokeSvg(AppIcons.arrowRight, width: 2.2),
                          size: 14,
                          color: c.accentInk,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '进日记',
                          style: context.body(
                            size: 11.5,
                            weight: FontWeight.w700,
                            color: c.accentInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FishCard extends StatelessWidget {
  const FishCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final infoText = FishStateView.chipText;
    // 把「距休息日 N 天」里的数字单独放大，避免小卡片缩放后数字看不清。
    final match = RegExp(r'^(.*?)(\d+)(\s*天.*)$').firstMatch(infoText);
    final lead = (match?.group(1) ?? infoText).trimRight();
    final days = match?.group(2);
    final tail = (match?.group(3) ?? '').trimLeft();
    return PaperCard(
      tapeColor: c.tape,
      tapeAngle: 2.5,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      onTap: () => showFishSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '摸鱼日历',
            style: context.heading(
              size: 12.5,
              color: c.accentInk,
              letterSpacing: .3,
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '🐟',
                          style: TextStyle(fontSize: 26, height: 1),
                        ),
                        const SizedBox(width: 6),
                        if (days == null)
                          Text(
                            infoText,
                            style: context.display(
                              size: 18,
                              color: c.ink,
                              height: 1.3,
                            ),
                          )
                        else ...[
                          Text(
                            lead,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.body(
                              size: 13,
                              weight: FontWeight.w600,
                              color: c.ink,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            days,
                            style: context.display(
                              size: 28,
                              weight: FontWeight.w800,
                              color: c.ink,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            tail,
                            maxLines: 1,
                            style: context.body(
                              size: 13,
                              weight: FontWeight.w600,
                              color: c.ink,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '点击查看摸鱼详情',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(size: 10.5, color: c.inkSoft),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CalendarCard extends StatefulWidget {
  const CalendarCard({super.key});

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  int _monthOffset = 0;

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
    return PaperCard(
      tapeColor: c.tape2,
      tapeAngle: 2.5,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
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
                    style: context.heading(
                      size: dense ? 11 : 12.5,
                      color: c.accentInk,
                    ),
                  ),
                  const Spacer(),
                  Pressable(
                    onTap: () => setState(() => _monthOffset--),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: dense ? 16 : 20,
                        color: const Color(0x8F8F4E05),
                      ),
                    ),
                  ),
                  Text(
                    dense ? '${now.month}月' : '${now.year}年${now.month}月',
                    style: context.display(
                      size: dense ? 13 : 16,
                      color: c.accentInk,
                    ),
                  ),
                  Pressable(
                    onTap: () => setState(() => _monthOffset++),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: dense ? 16 : 20,
                        color: const Color(0x8F8F4E05),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: dense ? 2 : 3),
                        child: Text(
                          wd[i],
                          textAlign: TextAlign.center,
                          style: context.body(
                            size: dense ? 10 : 13,
                            weight: FontWeight.w700,
                            color: (i == 0 || i == 6) ? c.accentInk : c.inkSoft,
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

  /// 迷你日历：缩小日期与农历字号，隐藏次要标签。
  final bool dense;
  const _CalCell({
    required this.day,
    required this.date,
    required this.dim,
    required this.today,
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
        labelColor = c.accentInk;
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
    return Container(
      height: fill ? null : 44,
      padding: EdgeInsets.only(top: fill ? 2 : 3, bottom: fill ? 2 : 2),
      decoration: today
          ? BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(fill ? 10 : 8),
            )
          : null,
      child: Opacity(
        opacity: dim ? .55 : 1,
        // 日历格高度随卡片尺寸变化，用 scaleDown 兜底，避免字体
        // 行高在不同平台相差半像素时出现 RenderFlex 溢出。
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: context.display(
                  size: dense ? 15 : (fill ? 20 : 19),
                  color: today ? const Color(0xFF2E2C34) : c.ink,
                  height: 1.05,
                ),
              ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: dense ? 7.5 : (fill ? 9.5 : 10),
                      color: today
                          ? const Color(0xFF2E2C34)
                          : (labelColor ?? c.inkSoft),
                      height: 1.15,
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

class ZodiacCard extends StatelessWidget {
  const ZodiacCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final c = context.c;
    final sign = zodiacById(state.zodiacSign);
    final f = state.zodiacFortune;
    final now = DateTime.now();
    final dateText =
        '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} ${weekdayChinese(now)}';
    return PaperCard(
      tapeColor: c.tape2,
      tapeAngle: 2.5,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      onTap: () => showZodiacModal(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 首页把星象卡放在滚动容器里，高度是无界的；此时给卡片一个固定高度，
          // 否则 Column 里的 Expanded 无法布局，整页会空白。
          final cardHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : 260.0;
          final compact = cardHeight < 320;
          final horizontal = constraints.maxWidth >= 280;
          // 迷你尺寸：只保留分数、星座与星语标签，避免 1x1 卡片溢出。
          final micro = constraints.maxWidth < 210 || cardHeight < 210;
          final microBody = micro && f != null && sign != null
              ? _zodiacMicro(context, sign, f)
              : null;
          final leftWidth = (constraints.maxWidth * .38).clamp(112.0, 152.0);
          return SizedBox(
            height: constraints.hasBoundedHeight ? null : cardHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '今日星象',
                      style: context.heading(
                        size: 12.5,
                        color: c.accentInk,
                        letterSpacing: .3,
                      ),
                    ),
                    const Spacer(),
                    if (!micro)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c.dark
                              ? const Color(0x0AFFFFFF)
                              : const Color(0x33F7BC78),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: c.dark ? c.line : const Color(0x1A94530A),
                          ),
                        ),
                        child: Text(
                          dateText,
                          style: context.body(
                            size: 10,
                            color: c.inkSoft,
                            letterSpacing: .2,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                if (microBody != null)
                  Expanded(child: microBody)
                else if (sign == null)
                  Expanded(child: Center(child: _zodiacPick(context)))
                else ...[
                  if (!horizontal)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (f != null)
                          ZodiacRing(score: f.score)
                        else
                          SizedBox(
                            width: 66,
                            height: 66,
                            child: Center(
                              child: state.zodiacLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      '✦',
                                      style: context.display(
                                        size: 22,
                                        color: c.inkSoft.withAlpha(120),
                                      ),
                                    ),
                            ),
                          ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${sign.symbol} ${sign.name}',
                                style: context.heading(
                                  size: 23,
                                  color: c.ink,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${sign.range} · ${sign.element}',
                                style: context.body(
                                  size: 10.5,
                                  color: c.inkSoft,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: c.dark
                                      ? c.hl
                                      : const Color(0x3DF7BC78),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: c.dark
                                        ? c.line
                                        : const Color(0x2914530A),
                                  ),
                                ),
                                child: Text(
                                  '✦ ${f?.tag ?? '星语生成中'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.body(
                                    size: 11,
                                    color: c.dark
                                        ? c.accentInk
                                        : const Color(0xFF8A4B08),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (f == null) ...[
                    const SizedBox(height: 10),
                    Text(
                      state.zodiacError ??
                          (state.zodiacLoading ? '星语生成中…' : '点开卡片生成今日星语'),
                      style: context.body(
                        size: 12.5,
                        color: state.zodiacError != null ? c.stamp : c.inkSoft,
                        height: 1.5,
                      ),
                    ),
                  ] else if (horizontal) ...[
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: leftWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ZodiacRing(score: f.score),
                                const SizedBox(height: 8),
                                Text(
                                  '${sign.symbol} ${sign.name}',
                                  style: context.heading(
                                    size: 21,
                                    color: c.ink,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${sign.range} · ${sign.element}',
                                  style: context.body(
                                    size: 10.5,
                                    color: c.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.dark
                                          ? c.hl
                                          : const Color(0x3DF7BC78),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: c.dark
                                            ? c.line
                                            : const Color(0x2914530A),
                                      ),
                                    ),
                                    child: Text(
                                      '✦ ${f.tag}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.body(
                                        size: 11,
                                        color: c.dark
                                            ? c.accentInk
                                            : const Color(0xFF8A4B08),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: ClipRect(
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: Text(
                                        f.text,
                                        maxLines: compact ? 3 : 5,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.body(
                                          size: 13,
                                          color: c.ink2,
                                          height: 1.6,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (!compact) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    '幸运色 ${f.color}  ·  数字 ${f.number}  ·  幸运物 ${f.item}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.body(
                                      size: 10,
                                      color: c.inkSoft,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _ZStat(value: f.love, label: '爱情'),
                        _ZStat(value: f.work, label: '事业'),
                        _ZStat(value: f.wealth, label: '财运'),
                        _ZStat(value: f.health, label: '健康'),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 9),
                    DashedLine(
                      color: c.dark ? c.line : const Color(0x294A3A22),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            f.text,
                            maxLines: compact ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.body(
                              size: 13.5,
                              color: c.ink2,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _ZStat(value: f.love, label: '爱情'),
                        _ZStat(value: f.work, label: '事业'),
                        _ZStat(value: f.wealth, label: '财运'),
                        _ZStat(value: f.health, label: '健康'),
                      ],
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 7),
                      Text(
                        '幸运色 ${f.color}  ·  数字 ${f.number}  ·  幸运物 ${f.item}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(size: 10, color: c.inkSoft),
                      ),
                    ],
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// 迷你星象卡：只保留分数环、星座与星语标签。
  Widget _zodiacMicro(BuildContext context, ZodiacSign sign, ZodiacFortune f) {
    final c = context.c;
    return Row(
      children: [
        ZodiacRing(score: f.score, size: 56),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${sign.symbol} ${sign.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.heading(size: 17, color: c.ink, height: 1.1),
              ),
              const SizedBox(height: 2),
              Text(
                '✦ ${f.tag}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: 10.5, color: c.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _zodiacPick(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 300;
        return Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 4 : 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '选一个本命星座，解锁今日星象',
                style: context.body(
                  size: compact ? 11.5 : 13,
                  color: c.inkSoft,
                ),
              ),
              SizedBox(height: compact ? 6 : 10),
              Wrap(
                spacing: compact ? 4 : 8,
                runSpacing: compact ? 4 : 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final z in kZodiacSigns)
                    Pressable(
                      onTap: () => showZodiacModal(context),
                      child: Container(
                        padding: compact
                            ? const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              )
                            : const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                        decoration: BoxDecoration(
                          color: c.hl,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.line),
                        ),
                        child: Text(
                          '${z.symbol} ${z.name}',
                          style: context.body(
                            size: compact ? 10.5 : 12,
                            color: c.accentInk,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: compact ? 6 : 10),
              Text(
                '点击选择 →',
                style: context.display(
                  size: compact ? 11.5 : 13,
                  color: c.accentInk,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ZStat extends StatelessWidget {
  final int value;
  final String label;
  const _ZStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: context.display(size: 17, color: c.accentInk, height: 1.1),
          ),
          const SizedBox(height: 1),
          Text(label, style: context.body(size: 9.5, color: c.inkSoft)),
        ],
      ),
    );
  }
}

class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final q = kQuotes[dayOfYear % kQuotes.length];
    return PaperCard(
      tapeColor: c.tape3,
      tapeAngle: -2.5,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      onTap: () =>
          copyText('${q.cn} — ${q.en}', context: context, tip: '已复制每日一言'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 112),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final quoteBody = SizedBox(
              width: constraints.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '每日一言',
                    textAlign: TextAlign.center,
                    style: context.heading(size: 12.5, color: c.accentInk),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      '「${q.cn}」',
                      textAlign: TextAlign.center,
                      locale: const Locale('zh', 'CN'),
                      style: context.heading(
                        size: 19.5,
                        color: c.ink,
                        height: 1.7,
                        letterSpacing: .3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      '— ${q.en}',
                      textAlign: TextAlign.center,
                      style: context.hand(
                        size: 14.5,
                        color: c.inkSoft,
                        height: 1.45,
                        style: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            );
            return Stack(
              children: [
                Positioned(
                  right: 0,
                  top: -8,
                  child: Text(
                    '“',
                    style: context.display(
                      size: 27,
                      color: const Color(0x38B8924A),
                      height: 1,
                    ),
                  ),
                ),
                // 卡片被编辑成较矮的尺寸时整体等比缩小，避免文字硬溢出。
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: quoteBody,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
