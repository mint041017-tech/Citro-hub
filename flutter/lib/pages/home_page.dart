import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/quotes.dart';
import '../services/fish.dart';
import '../services/api.dart';
import '../overlays/ai_chat.dart';
import '../overlays/appreciation_sheet.dart';
import '../overlays/extra_sheets.dart';
import '../overlays/lantern_sheet.dart';
import '../overlays/pomodoro_sheet.dart';
import '../overlays/zodiac_modal.dart';
import '../services/lantern_api.dart';
import '../services/models.dart';
import '../services/pomodoro.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/lunar.dart';
import '../widgets/paper.dart';
import '../widgets/tablet_shell.dart';
import '../widgets/weather_widgets.dart';
import 'cook_page.dart';
import 'web_home.dart';

class HomePage extends StatefulWidget {
  final ValueChanged<int> onSwitchTab;
  const HomePage({super.key, required this.onSwitchTab});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showLanternWelcomeIfNeeded(context);
    });
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
    final wide = width >= 820 || (duoWide && width >= 600);
    final maxWidth = wide ? 1120.0 : 760.0;
    final sideNav = layout?.tabletNav ?? false;
    final side = math.max(8.0, (width - maxWidth) / 2);
    return Stack(
      children: [
        PaperBackground(
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(side, 8, side, sideNav ? 32 : 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 64,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const AccountCap(),
                        const Spacer(),
                        if (LanternApi.currentWindow() != null) ...[
                          const LanternEntry(),
                          const SizedBox(width: 8),
                        ],
                        const Clock(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (wide) _wideDashboard() else _phoneDashboard(),
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
        if (!sideNav)
          Positioned(
            right: math.max(18.0, (width - maxWidth) / 2 + 18),
            bottom: MediaQuery.paddingOf(context).bottom + 92,
            child: const AiHomeButton(),
          ),
      ],
    );
  }

  Widget _phoneDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          child: SizedBox(
            height: 248,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(child: WeatherCard()),
                const SizedBox(width: 10),
                const Expanded(child: CookCard()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const RepaintBoundary(child: FishCard()),
        const SizedBox(height: 12),
        const RepaintBoundary(child: CalendarCard()),
        const SizedBox(height: 12),
        const RepaintBoundary(child: ZodiacCard()),
        const SizedBox(height: 12),
        const RepaintBoundary(child: QuoteCard()),
      ],
    );
  }

  Widget _wideDashboard() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RepaintBoundary(
                child: SizedBox(height: 248, child: WeatherCard()),
              ),
              SizedBox(height: 16),
              RepaintBoundary(child: FishCard()),
              SizedBox(height: 16),
              RepaintBoundary(child: CalendarCard()),
            ],
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RepaintBoundary(child: SizedBox(height: 248, child: CookCard())),
              SizedBox(height: 16),
              RepaintBoundary(child: ZodiacCard()),
              SizedBox(height: 16),
              RepaintBoundary(child: QuoteCard()),
            ],
          ),
        ),
      ],
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

class AccountCap extends StatelessWidget {
  const AccountCap({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final c = context.c;
    final user = state.user;
    final streak = state.checkinStreak;
    return Pressable(
      onTap: () => Navigator.of(context).pushNamed('/me'),
      child: Container(
        height: 56,
        padding: const EdgeInsets.fromLTRB(7, 5, 16, 5),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: user != null ? c.accent : c.surface,
                border: Border.all(color: c.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: user?.av != null
                  ? Image.network(
                      Api.imageUrl(user!.av),
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          user.name.isEmpty ? '友' : user.name[0],
                          style: context.display(
                            size: 20,
                            weight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: user == null
                          ? AppIcon(
                              strokeSvg(AppIcons.user, width: 2),
                              size: 21,
                              color: c.ink2,
                            )
                          : Text(
                              user.name.isEmpty ? '友' : user.name[0],
                              style: context.display(
                                size: 20,
                                weight: FontWeight.w700,
                                color: const Color(0xFF2E2C22),
                              ),
                            ),
                    ),
            ),
            const SizedBox(width: 9),
            Pressable(
              onTap: () => showCheckinOverlay(context),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: c.hl,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.calendar, width: 1.9),
                      size: 19,
                      color: c.accentInk,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '打卡',
                      style: context.display(
                        size: 18,
                        weight: FontWeight.w700,
                        color: c.accentInk,
                        letterSpacing: .3,
                      ),
                    ),
                    if (streak > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: c.mint,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '$streak',
                          style: context.body(
                            size: 11,
                            weight: FontWeight.w800,
                            color: const Color(0xFF111113),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Clock extends StatefulWidget {
  const Clock({super.key});

  @override
  State<Clock> createState() => _ClockState();
}

class _ClockState extends State<Clock> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  /// 时钟只显示到分钟：对齐到整分钟刷新，避免整个首页每秒重建。
  void _scheduleTick() {
    _timer?.cancel();
    final now = DateTime.now();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    _timer = Timer(next.difference(now) + const Duration(milliseconds: 30), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = _now;
    const week = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    final date = '${now.month}.${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Pressable(
      onTap: () => showPomodoroOverlay(context),
      child: SizedBox(
        width: 100,
        height: 64,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: AnimatedBuilder(
            animation: PomodoroState.instance,
            builder: (context, child) => Stack(
              clipBehavior: Clip.none,
              children: [
                child!,
                if (PomodoroState.instance.active)
                  const Positioned(
                    top: -3,
                    right: 0,
                    child: Text(
                      '🍅',
                      style: TextStyle(fontSize: 12, height: 1),
                    ),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      date,
                      style: context.body(
                        size: 13,
                        weight: FontWeight.w700,
                        color: c.inkSoft,
                        letterSpacing: .2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      week[now.weekday % 7],
                      style: context.body(
                        size: 13,
                        weight: FontWeight.w800,
                        color: c.inkSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  time,
                  style: context.display(
                    size: 27,
                    weight: FontWeight.w700,
                    color: c.ink,
                    height: 1.25,
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

class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final c = context.c;
    final w = state.weather;
    return PaperCard(
      rotate: -1.8,
      tapeColor: c.tape,
      tapeAngle: -3,
      color: c.surface2,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      onTap: () => showWeatherSheet(context),
      child: Stack(
        children: [
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
                  Flexible(
                    child: Text(
                      w.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: context
                          .heading(size: 12.5, color: c.ink)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
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
                              size: 56,
                              weight: FontWeight.w700,
                              color: c.ink,
                              height: .95,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              'C',
                              style: context.body(
                                size: 17,
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
                        size: 20,
                        color: c.accentInk,
                        letterSpacing: 1.2,
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
            size: 20,
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
      rotate: 1.8,
      tapeColor: c.tape3,
      tapeAngle: -2.5,
      color: c.noteY,
      shadow: PaperShadow.note,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(2),
        topRight: Radius.circular(2),
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'cook'),
          builder: (_) => const CookPage(),
        ),
      ),
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
                style: TextStyle(fontSize: 30, height: 1),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.rotate(
                angle: -1.5 * math.pi / 180,
                child: Column(
                  children: [
                    Text(
                      '食谱',
                      style: context.heading(
                        size: 48,
                        color: c.ink,
                        height: 1.14,
                        letterSpacing: 2.2,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        '日记',
                        style: context.heading(
                          size: 48,
                          color: c.accentInk,
                          height: 1.14,
                          letterSpacing: 2.2,
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
                        size: 12,
                        weight: FontWeight.w700,
                        color: c.accentInk,
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

class FishCard extends StatelessWidget {
  const FishCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final infoText = FishStateView.chipText;
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      onTap: () => showFishSheet(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: -10,
            child: Text(
              '摸鱼日历',
              style: context.heading(
                size: 12,
                color: c.accentInk,
                letterSpacing: .3,
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🐟', style: TextStyle(fontSize: 26, height: 1)),
                    const SizedBox(width: 6),
                    Text(
                      infoText,
                      style: context.display(
                        size: 20,
                        color: c.ink,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '点击查看摸鱼详情',
                  style: context.heading(size: 10, color: c.inkSoft),
                ),
              ],
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
      rotate: 1.2,
      tapeColor: c.tape2,
      tapeAngle: 2.5,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fill = constraints.hasBoundedHeight;
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
                    style: context.heading(size: 15.5, color: c.accentInk),
                  ),
                  const Spacer(),
                  Pressable(
                    onTap: () => setState(() => _monthOffset--),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: 20,
                        color: Color(0x8F8F4E05),
                      ),
                    ),
                  ),
                  Text(
                    '${now.year}年${now.month}月',
                    style: context.display(size: 16, color: c.accentInk),
                  ),
                  Pressable(
                    onTap: () => setState(() => _monthOffset++),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: Color(0x8F8F4E05),
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
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          wd[i],
                          textAlign: TextAlign.center,
                          style: context.body(
                            size: 13,
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
  const _CalCell({
    required this.day,
    required this.date,
    required this.dim,
    required this.today,
    this.fill = false,
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
      padding: EdgeInsets.only(top: fill ? 6 : 3, bottom: fill ? 5 : 2),
      decoration: today
          ? BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(fill ? 10 : 8),
            )
          : null,
      child: Opacity(
        opacity: dim ? .55 : 1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: context.display(
                size: fill ? 23 : 19,
                color: today ? const Color(0xFF2E2C34) : c.ink,
                height: 1.05,
              ),
            ),
            if (label != null)
              Padding(
                padding: EdgeInsets.only(top: fill ? 2 : 1),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: fill ? 12 : 10,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '今日星象',
                style: context.display(
                  size: 11,
                  color: c.inkSoft,
                  letterSpacing: .7,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
          if (sign == null)
            _zodiacPick(context)
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (f != null)
                  ZodiacRing(score: f.score)
                else
                  SizedBox(
                    width: 70,
                    height: 70,
                    child: Center(
                      child: state.zodiacLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${sign.symbol} ${sign.name}',
                        style: context.heading(
                          size: 24,
                          color: c.ink,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${sign.range} · ${sign.element}',
                        style: context.body(size: 10.5, color: c.inkSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (f == null) ...[
              const SizedBox(height: 8),
              Text(
                state.zodiacError ??
                    (state.zodiacLoading ? '星语生成中…' : '点开卡片生成今日星语'),
                style: context.body(
                  size: 12.5,
                  color: state.zodiacError != null ? c.stamp : c.inkSoft,
                  height: 1.5,
                ),
              ),
            ] else ...[
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: Transform.rotate(
                  angle: -1 * math.pi / 180,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.dark ? c.hl : const Color(0x3DF7BC78),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: c.dark ? c.line : const Color(0x2914530A),
                      ),
                    ),
                    child: Text(
                      '✦ ${f.tag}',
                      style: context.body(
                        size: 11.5,
                        color: c.dark ? c.accentInk : const Color(0xFF8A4B08),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                f.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: 13.5, color: c.ink2, height: 1.55),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ZStat(
                    value: f.love,
                    label: '爱情',
                    color: c.dark
                        ? const Color(0x0DFFFFFF)
                        : const Color(0x21F7BC78),
                  ),
                  const SizedBox(width: 5),
                  _ZStat(
                    value: f.work,
                    label: '事业',
                    color: c.dark
                        ? const Color(0x0DFFFFFF)
                        : const Color(0x248CC896),
                  ),
                  const SizedBox(width: 5),
                  _ZStat(
                    value: f.wealth,
                    label: '财运',
                    color: c.dark
                        ? const Color(0x0DFFFFFF)
                        : const Color(0x29F0C878),
                  ),
                  const SizedBox(width: 5),
                  _ZStat(
                    value: f.health,
                    label: '健康',
                    color: c.dark
                        ? const Color(0x0DFFFFFF)
                        : const Color(0x248CBEDC),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DashedLine(color: c.dark ? c.line : const Color(0x294A3A22)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    flex: 12,
                    child: _Lucky(label: '幸运色', value: f.color),
                  ),
                  Expanded(
                    flex: 8,
                    child: _Lucky(label: '数字', value: f.number),
                  ),
                  Expanded(
                    flex: 12,
                    child: _Lucky(label: '幸运物', value: f.item),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _zodiacPick(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Text(
            '选一个本命星座，解锁今日星象',
            style: context.body(size: 13, color: c.inkSoft),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final z in kZodiacSigns)
                Pressable(
                  onTap: () => showZodiacModal(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
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
                      style: context.body(size: 12, color: c.accentInk),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('点击选择 →', style: context.display(size: 13, color: c.accentInk)),
        ],
      ),
    );
  }
}

class _ZStat extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const _ZStat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: context.display(size: 18, color: c.accentInk, height: 1.1),
            ),
            const SizedBox(height: 1),
            Text(label, style: context.body(size: 10, color: c.inkSoft)),
          ],
        ),
      ),
    );
  }
}

class _Lucky extends StatelessWidget {
  final String label;
  final String value;
  const _Lucky({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.body(size: 9, color: c.inkSoft)),
        const SizedBox(height: 1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.body(
            size: 11.5,
            weight: FontWeight.w600,
            color: c.ink2,
          ),
        ),
      ],
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
      rotate: -2,
      tapeColor: c.tape3,
      tapeAngle: -2.5,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      onTap: () =>
          copyText('${q.cn} — ${q.en}', context: context, tip: '已复制每日一言'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 92),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: -6,
              child: Text(
                '“',
                style: context.display(
                  size: 34,
                  color: const Color(0x38B8924A),
                  height: 1,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每日一言',
                  style: context.heading(size: 11.5, color: c.accentInk),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    '「${q.cn}」',
                    textAlign: TextAlign.center,
                    locale: const Locale('zh', 'CN'),
                    style: context.heading(
                      size: 15.5,
                      color: c.ink,
                      height: 1.7,
                      letterSpacing: .3,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '— ${q.en}',
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.hand(
                    size: 13.5,
                    color: c.inkSoft,
                    height: 1.45,
                    style: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
