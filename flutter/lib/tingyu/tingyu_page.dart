import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import '../overlays/pomodoro_sheet.dart';
import '../services/chime.dart';
import '../services/haptics.dart';
import '../services/pomodoro.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'tingyu_controller.dart';
import 'tingyu_models.dart';

void _closeTingyu(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
  } else {
    nav.pushReplacementNamed('/home');
  }
}

/// Citro 内的听隅页面：统一顶栏（返回 + 标题 + 时间），内容沿用原听隅布局。
class TingyuPage extends StatefulWidget {
  const TingyuPage({super.key});

  @override
  State<TingyuPage> createState() => _TingyuPageState();
}

class _TingyuPageState extends State<TingyuPage> {
  late final NookController _c = NookController.instance;

  @override
  void initState() {
    super.initState();
    if (!_c.ready) unawaited(_c.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final theme = NookApp(controller: _c).theme(dark);
        final size = MediaQuery.sizeOf(context);
        final portrait = size.height >= size.width;
        final p = Palette(dark);
        return Theme(
          data: theme,
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: !portrait
                ? null
                : AppBar(
                    backgroundColor: theme.scaffoldBackgroundColor,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    shape: Border(
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
                    leading: IconButton(
                      tooltip: '返回',
                      color: theme.colorScheme.onSurface,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                      ),
                      onPressed: () => _closeTingyu(context),
                    ),
                    titleSpacing: 0,
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.spa_outlined,
                            size: 16,
                            color: p.onAccent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '听隅',
                          style: TextStyle(
                            fontFamily: AppFonts.zcool,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      const TingyuPomodoroButton(),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TingyuTopClock(compact: size.width < 380),
                      ),
                    ],
                  ),
            body: MediaQuery.removePadding(
              context: context,
              removeTop: portrait,
              child: NookHome(controller: _c, landscapeHeader: !portrait),
            ),
          ),
        );
      },
    );
  }
}

CitroColors _tingyuPomodoroColors(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = dark ? CitroColors.darkColors : CitroColors.light;
  return base.copyWith(
    accent: dark ? const Color(0xFFAAC4A2) : const Color(0xFF4F6957),
    accent2: dark ? const Color(0xFF8FAF86) : const Color(0xFF3E5747),
    accentInk: dark ? const Color(0xFFC8DCC0) : const Color(0xFF3E5747),
    accentLt: dark ? const Color(0xFFC8DCC0) : const Color(0xFF7C9B79),
    hl: dark ? const Color(0x33AAC4A2) : const Color(0x8FE4EADD),
    hlInk: dark ? const Color(0x57AAC4A2) : const Color(0x9E4F6957),
  );
}

class TingyuPomodoroButton extends StatefulWidget {
  const TingyuPomodoroButton({super.key});

  @override
  State<TingyuPomodoroButton> createState() => _TingyuPomodoroButtonState();
}

class _TingyuPomodoroButtonState extends State<TingyuPomodoroButton> {
  @override
  void initState() {
    super.initState();
    PomodoroState.instance.ensureInit();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: PomodoroState.instance,
      builder: (context, _) {
        final state = PomodoroState.instance;
        final ticking = state.active;
        return Semantics(
          button: true,
          label: ticking ? '番茄钟，还剩 ${state.timeText}' : '番茄钟',
          child: Tooltip(
            message: ticking ? '番茄钟 · 还剩 ${state.timeText}' : '番茄钟',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showPomodoroOverlay(
                  context,
                  colors: _tingyuPomodoroColors(context),
                  nook: true,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ticking ? p.accent : p.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: ticking ? p.accent : p.border),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: ticking
                        ? Padding(
                            key: const ValueKey('pomodoro-count'),
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                state.timeText,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: p.onAccent,
                                ),
                              ),
                            ),
                          )
                        : Icon(
                            Icons.timer_outlined,
                            key: const ValueKey('pomodoro-icon'),
                            size: 18,
                            color: p.text,
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 从首页移过来的时间：日期 + 星期 + 时分秒，随听隅顶栏显示。
class TingyuTopClock extends StatefulWidget {
  const TingyuTopClock({super.key, this.compact = false});

  /// 窄屏只保留时分秒，避免顶栏和倒计时药丸挤在一起。
  final bool compact;

  @override
  State<TingyuTopClock> createState() => _TingyuTopClockState();
}

class _TingyuTopClockState extends State<TingyuTopClock> {
  DateTime _now = DateTime.now();
  Timer? _timer;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now();
    final delay = Duration(milliseconds: 1000 - now.millisecond);
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const week = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    String two(int value) => value.toString().padLeft(2, '0');
    final timeStyle = TextStyle(
      fontFamily: AppFonts.kalam,
      fontSize: widget.compact ? 19 : 21,
      fontWeight: FontWeight.w700,
      height: 1.1,
      color: p.text,
    );
    final dateStyle = TextStyle(fontSize: 11.5, color: p.muted);
    final timeWidth = _measureText(context, timeStyle, '88:88:88');
    final dateWidth =
        _measureText(context, dateStyle, '88.88') +
        5 +
        _measureText(context, dateStyle, '周五');
    final width = widget.compact ? timeWidth : math.max(timeWidth, dateWidth);
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _hover ? p.soft.withValues(alpha: .6) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SizedBox(
          width: width + 2,
          height: 46,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.compact) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${_now.month}.${two(_now.day)}', style: dateStyle),
                      const SizedBox(width: 5),
                      Text(
                        week[_now.weekday % 7],
                        style: dateStyle.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                ],
                Text(
                  '${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}',
                  style: timeStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _measureText(BuildContext context, TextStyle style, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width.ceilToDouble();
  }
}

class Palette {
  final bool dark;
  const Palette(this.dark);
  static Palette of(BuildContext context) =>
      Palette(Theme.of(context).brightness == Brightness.dark);
  Color get bg => dark ? const Color(0xff191f1c) : const Color(0xfff7f4ed);
  Color get surface => dark ? const Color(0xff242d27) : const Color(0xfffffdf8);
  Color get subtle => dark ? const Color(0xff303a32) : const Color(0xffedefe5);
  Color get text => dark ? const Color(0xffe5ebde) : const Color(0xff35433e);
  Color get muted => dark ? const Color(0xffa8b5a6) : const Color(0xff647066);
  Color get accent => dark ? const Color(0xffaac4a2) : const Color(0xff4f6957);
  Color get onAccent =>
      dark ? const Color(0xff1e2b20) : const Color(0xfffffdf8);
  Color get soft => dark ? const Color(0xff354b39) : const Color(0xffe4eadd);
  Color get border => dark ? const Color(0xff465248) : const Color(0xffd7ded2);
  Color get warning => dark ? const Color(0xffd3b77e) : const Color(0xff82602f);
  Color get error => dark ? const Color(0xffe8a49b) : const Color(0xff9a4944);
}

Color categoryColor(String category, bool dark) => switch (category) {
  '雨声' => dark ? const Color(0xff9fb0bd) : const Color(0xff6d8090),
  '森林' => dark ? const Color(0xffa9bf9e) : const Color(0xff70896a),
  '水流' => dark ? const Color(0xffa3c0c3) : const Color(0xff78969a),
  '风铃' => dark ? const Color(0xffd8c58f) : const Color(0xffb39a5d),
  '水下' => dark ? const Color(0xff93a9b8) : const Color(0xff5c7180),
  '城市' => dark ? const Color(0xffc3b8a8) : const Color(0xff8e8579),
  '篝火' => dark ? const Color(0xffd9a582) : const Color(0xffb87a55),
  '噪声' => dark ? const Color(0xffb4bcae) : const Color(0xff7d857a),
  '本地' => dark ? const Color(0xffaac4a2) : const Color(0xff4f6957),
  _ => dark ? const Color(0xffaac4a2) : const Color(0xff4f6957),
};

IconData categoryIcon(String category) => switch (category) {
  '雨声' => Icons.water_drop_outlined,
  '森林' => Icons.forest_outlined,
  '水流' => Icons.waves_outlined,
  '风铃' => Icons.wind_power_outlined,
  '水下' => Icons.bubble_chart_outlined,
  '城市' => Icons.location_city_outlined,
  '篝火' => Icons.local_fire_department_outlined,
  '噪声' => Icons.graphic_eq_outlined,
  '本地' => Icons.audio_file_outlined,
  _ => Icons.graphic_eq_outlined,
};

class NookApp extends StatelessWidget {
  final NookController controller;
  const NookApp({super.key, required this.controller});

  ThemeData theme(bool dark) {
    final p = Palette(dark);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: p.accent,
          onPrimary: p.onAccent,
          surface: p.surface,
          onSurface: p.text,
          outline: p.border,
        );
    return ThemeData(
      useMaterial3: true,
      fontFamily: AppFonts.noto,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: p.text, fontSize: 16, height: 1.5),
        bodySmall: TextStyle(color: p.muted, fontSize: 14, height: 1.5),
      ),
      dividerColor: p.border,
      splashFactory: NoSplash.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: TextStyle(
            fontFamily: AppFonts.noto,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.text,
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: TextStyle(
            fontFamily: AppFonts.noto,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.accent,
          textStyle: TextStyle(
            fontFamily: AppFonts.noto,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.muted,
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: p.accent,
        inactiveTrackColor: p.border,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: .1),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        hintStyle: TextStyle(color: p.muted, fontSize: 15),
        labelStyle: TextStyle(color: p.muted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.text,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          color: p.bg,
          fontFamily: AppFonts.noto,
          fontSize: 12,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border),
        ),
        textStyle: TextStyle(
          color: p.text,
          fontFamily: AppFonts.noto,
          fontSize: 15,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.text,
        contentTextStyle: TextStyle(
          color: p.bg,
          fontFamily: AppFonts.noto,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '听隅 · 给自己，留一小片安静。',
      theme: theme(false),
      darkTheme: theme(true),
      themeMode: switch (controller.theme) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      },
      home: NookHome(controller: controller),
    ),
  );
}

class NookHome extends StatefulWidget {
  final NookController controller;
  final bool landscapeHeader;
  const NookHome({
    super.key,
    required this.controller,
    this.landscapeHeader = false,
  });
  @override
  State<NookHome> createState() => _NookHomeState();
}

class _NookHomeState extends State<NookHome> {
  NookController get c => widget.controller;
  int page = 0;
  String category = '全部';
  String query = '';
  final search = TextEditingController();
  static const nav = ['此刻', '声音', '收藏', '设置'];
  static const navIcons = [
    Icons.grid_view_outlined,
    Icons.graphic_eq_outlined,
    Icons.bookmark_border_rounded,
    Icons.tune_rounded,
  ];

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<bool> act(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    final ok = await c.send(action, data);
    if (!ok) {
      final message = c.error ?? '操作没有完成，请再试一次。';
      if (message.contains('最多同时播放') && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: '调整混音',
              onPressed: () => setState(() => page = 0),
            ),
          ),
        );
      } else {
        toast(message);
      }
    }
    return ok;
  }

  Future<bool> setTrackVolume(String id, int value) async {
    final ok = await act('volume', {'id': id, 'value': value});
    if (ok && c.playing) {
      final silent =
          c.master == 0 ||
          (c.tracks.isNotEmpty &&
              c.tracks.every((t) => ((t['volume'] as num?) ?? 0) <= 0));
      if (silent) {
        await act('pause');
        toast('当前已静音。调高音量后，再点击播放。');
      }
    }
    return ok;
  }

  Future<bool> setMasterVolume(int value) async {
    final ok = await act('master', {'value': value});
    if (ok && value == 0 && c.playing) {
      await act('pause');
      toast('当前已静音。调高音量后，再点击播放。');
    }
    return ok;
  }

  void openLibrary() => setState(() {
    page = 1;
    category = '全部';
  });

  Future<bool> confirm(
    String title,
    String body, {
    String accept = '确认',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 20)),
          content: Text(body, style: const TextStyle(height: 1.7)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(accept),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> guardSwitch() async {
    if (!c.dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存这份声音配方？', style: TextStyle(fontSize: 21)),
        content: const Text('当前混音有未保存的调整。保存后，下次就能直接回来。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('不保存并切换'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存后切换'),
          ),
        ],
      ),
    );
    if (choice == 'save') return await saveMix();
    return choice == 'discard';
  }

  Future<void> loadScene(SceneSpec scene) async {
    if (!await guardSwitch()) return;
    final tracks = scene.tracks.entries
        .where((e) => c.available.contains(e.key))
        .map((e) => {'id': e.key, 'volume': e.value})
        .toList();
    if (tracks.length != scene.tracks.length) {
      toast('这个场景还有声音未就绪，请先试听其他声音。');
      return;
    }
    final keepTimer = c.hasTimer;
    if (await act('load', {
      'tracks': tracks,
      'title': scene.title,
      'autoplay': true,
    })) {
      if (!keepTimer)
        await act('timer', {
          'seconds': scene.minutes * 60,
          'fadeSeconds': scene.fadeSeconds,
        });
      c.markLoaded();
      if (keepTimer) toast('已切换场景，保留当前定时。');
    }
  }

  Future<void> loadFavorite(
    Map<String, dynamic> favorite, {
    bool autoplay = true,
  }) async {
    if (!await guardSwitch()) return;
    final all = validTracks(favorite['tracks']);
    final available = c.library.map((s) => s.id).toSet();
    final tracks = all.where((t) => available.contains(t['id'])).toList();
    if (tracks.isEmpty) {
      toast('组合中的声音已不可用，请先重新导入。');
      return;
    }
    if (tracks.length != all.length &&
        !await confirm(
          '有声音暂时不可用',
          '这份配方有 ${all.length - tracks.length} 个本地声音缺失。仅${autoplay ? '播放' : '载入'}其余可用声音？',
          accept: autoplay ? '播放可用声音' : '载入可用声音',
        ))
      return;
    final keepTimer = c.hasTimer;
    if (await act('load', {
      'tracks': tracks,
      'title': favorite['name'],
      'autoplay': autoplay,
    })) {
      await act('master', {
        'value': (favorite['master'] as num? ?? 70).clamp(0, 100),
      });
      if (!keepTimer && favorite['seconds'] is num)
        await act('timer', {
          'seconds': favorite['seconds'],
          'fadeSeconds': favorite['fade'] ?? 30,
        });
      c.markLoaded(favorite['id'] as String);
      c.touchFavorite(favorite['id'] as String);
      if (!autoplay) {
        toast('已载入“${favorite['name']}”，点击播放开始。');
      }
    }
  }

  Future<bool> saveMix() async {
    unawaited(c.loadFullFont());
    if (c.tracks.isEmpty) {
      toast('先加入至少一种声音，再保存配方。');
      return false;
    }
    final name = TextEditingController(text: c.title);
    var withTimer = false;
    var update = c.favoriteId != null;
    String? validation;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => sheet(ctx, '保存一份安静', [
          Text(
            '把喜欢的声音比例留下来，下次一键播放。',
            style: TextStyle(color: Palette.of(ctx).muted, fontSize: 14),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: name,
            autofocus: true,
            maxLength: 24,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: '混音名称',
              errorText: validation,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: c.tracks
                .map(
                  (t) => smallTag(
                    ctx,
                    '${c.sound(t['id']).name} ${t['volume']}%',
                    icon: c.sound(t['id']).icon,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          if (c.hasTimer)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('保存建议计时', style: TextStyle(fontSize: 16)),
              subtitle: Text(
                '保存时长与淡出，不保存剩余时间',
                style: TextStyle(fontSize: 14, color: Palette.of(ctx).muted),
              ),
              value: withTimer,
              onChanged: (v) => setLocal(() => withTimer = v),
            ),
          if (c.favoriteId != null)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('更新原组合', style: TextStyle(fontSize: 16)),
              subtitle: Text(
                '关闭后另存为新组合',
                style: TextStyle(fontSize: 14, color: Palette.of(ctx).muted),
              ),
              value: update,
              onChanged: (v) => setLocal(() => update = v),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.bookmark_add_outlined, size: 19),
              label: Text(update ? '更新组合' : '保存组合'),
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setLocal(() => validation = '给这份混音起个名字。');
                  return;
                }
                if (c.saveFavorite(
                  name.text,
                  withTimer: withTimer,
                  update: update,
                )) {
                  Navigator.pop(ctx, true);
                } else {
                  setLocal(() => validation = c.error);
                }
              },
            ),
          ),
        ]),
      ),
    );
    if (result == true) toast('已保存到收藏。');
    return result == true;
  }

  Widget sheet(BuildContext ctx, String title, List<Widget> children) {
    final p = Palette.of(ctx);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .92,
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 16, 26, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.border,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭面板',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 21),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> timerSheet() async {
    final savedMinutes = c.hasTimer
        ? (c.remaining / 60).round().clamp(1, 720)
        : 30;
    var hours = savedMinutes ~/ 60;
    var minutes = savedMinutes % 60;
    var fade = c.hasTimer ? c.timerFade : c.defaultFade;
    final hourInput = TextEditingController(text: '$hours');
    final minuteInput = TextEditingController(text: '$minutes');
    String? validation;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final total =
              (int.tryParse(hourInput.text) ?? 0) * 60 +
              (int.tryParse(minuteInput.text) ?? 0);
          final safeFade = total < 1
              ? 0
              : math.min(fade, math.min(total * 30, 120));
          final adjusted = fade > safeFade;
          final end = total >= 1 ? endClockText(total * 60) : null;
          return sheet(ctx, '定时关闭', [
            Text(
              '让声音在合适的时候停下来。渐弱包含在总时长内，暂停后倒计时仍继续。',
              style: TextStyle(
                color: Palette.of(ctx).muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [10, 30, 60]
                  .map(
                    (m) => selectButton(
                      ctx,
                      '$m 分钟',
                      hours * 60 + minutes == m,
                      () => setLocal(() {
                        hours = m ~/ 60;
                        minutes = m % 60;
                        hourInput.text = '$hours';
                        minuteInput.text = '$minutes';
                        validation = null;
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: hourInput,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(labelText: '小时'),
                    onChanged: (v) => setLocal(() {
                      hours = int.tryParse(v) ?? 0;
                      validation = null;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: minuteInput,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(labelText: '分钟'),
                    onChanged: (v) => setLocal(() {
                      minutes = int.tryParse(v) ?? 0;
                      validation = null;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              '结束前渐弱',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [0, 15, 30, 60, 120]
                  .map(
                    (s) => selectButton(
                      ctx,
                      s == 0 ? '关闭' : '$s 秒',
                      fade == s,
                      () => setLocal(() {
                        fade = s;
                        validation = null;
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            Text(
              total < 1
                  ? '请选择 1 到 720 分钟的时长。'
                  : safeFade > 0
                  ? '最后 $safeFade 秒逐渐变轻，$end 结束。'
                  : '到点后直接停止，$end 结束。',
              style: TextStyle(
                fontSize: 14,
                color: validation != null
                    ? Palette.of(ctx).error
                    : Palette.of(ctx).muted,
                height: 1.5,
              ),
            ),
            if (adjusted)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '时长较短，渐弱已调整为 $safeFade 秒。',
                  style: TextStyle(
                    fontSize: 14,
                    color: Palette.of(ctx).warning,
                    height: 1.5,
                  ),
                ),
              ),
            if (validation != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  validation!,
                  style: TextStyle(fontSize: 14, color: Palette.of(ctx).error),
                ),
              ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final h = int.tryParse(hourInput.text) ?? 0;
                  final m = int.tryParse(minuteInput.text) ?? 0;
                  final value = h * 60 + m;
                  if (h < 0 ||
                      h > 12 ||
                      m < 0 ||
                      m > 59 ||
                      value < 1 ||
                      value > 720) {
                    setLocal(
                      () => validation = m > 59
                          ? '分钟请在 0 到 59 之间。'
                          : '请输入 1 到 720 分钟的时长。',
                    );
                    return;
                  }
                  final fadeValue = math.min(fade, math.min(value * 30, 120));
                  Navigator.pop(ctx);
                  if (await act('timer', {
                    'seconds': value * 60,
                    'fadeSeconds': fadeValue,
                  })) {
                    toast(
                      c.playing
                          ? fadeValue > 0
                                ? '计时已开始，最后 $fadeValue 秒渐弱。'
                                : '计时已开始，到点后停止。'
                          : '计时已准备，播放后开始。',
                    );
                  }
                },
                child: Text(
                  c.hasTimer
                      ? '重新计时'
                      : c.playing
                      ? '开始计时'
                      : '播放后开始',
                ),
              ),
            ),
            if (c.hasTimer)
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    act('cancelTimer');
                    toast('已取消定时，声音不受影响。');
                  },
                  child: const Text('取消当前定时'),
                ),
              ),
          ]);
        },
      ),
    );
  }

  Widget selectButton(
    BuildContext ctx,
    String text,
    bool selected,
    VoidCallback onTap,
  ) {
    final p = Palette.of(ctx);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? p.soft : p.surface,
        side: BorderSide(color: selected ? p.accent : p.border),
        foregroundColor: selected ? p.accent : p.text,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      child: Text(text, style: const TextStyle(fontSize: 15)),
    );
  }

  void breathe() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BreathingPage(reducedMotion: c.reducedMotion),
    ),
  );

  Future<void> importAudio() async {
    unawaited(c.loadFullFont());
    final before = c.locals.length;
    final ok = await act('import');
    if (!mounted) return;
    if (ok && c.locals.length > before) {
      setState(() {
        page = 1;
        category = '本地';
      });
      toast(kIsWeb ? '声音已保存在此浏览器，可以加入混音了。' : '声音已保存在此设备，可以加入混音了。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;
        final wide = constraints.maxWidth >= 1200;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop) sidebar(context),
                Expanded(
                  child: Column(
                    children: [
                      if (widget.landscapeHeader)
                        _landscapeHeader(context, desktop),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: c.reducedMotion || CitroMotion.reduced(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 240),
                          switchInCurve: CitroMotion.easeOut,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(0, .025),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: !c.ready
                              ? KeyedSubtree(
                                  key: const ValueKey('nook-loading'),
                                  child: loadingView(context),
                                )
                              : KeyedSubtree(
                                  key: ValueKey('nook-page-$page'),
                                  child: page == 2
                                      ? favoritesTab(context, desktop)
                                      : SingleChildScrollView(
                                          key: PageStorageKey('page-$page'),
                                          padding: EdgeInsets.fromLTRB(
                                            desktop ? 34 : 20,
                                            widget.landscapeHeader
                                                ? (desktop ? 10 : 6)
                                                : (desktop ? 32 : 14),
                                            desktop ? 34 : 20,
                                            34,
                                          ),
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 1050,
                                            ),
                                            child: switch (page) {
                                              1 => libraryPage(context),
                                              3 => settingsPage(context),
                                              _ => homePage(context, wide),
                                            },
                                          ),
                                        ),
                                ),
                        ),
                      ),
                      if (desktop && !wide) miniPlayer(context),
                    ],
                  ),
                ),
                if (wide)
                  Container(
                    width: 300,
                    decoration: BoxDecoration(
                      color: p.surface,
                      border: Border(left: BorderSide(color: p.border)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                      child: mixContents(context),
                    ),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: desktop
              ? null
              : Container(
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border(top: BorderSide(color: p.border)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (page != 0) miniPlayer(context),
                        SizedBox(
                          height: 64,
                          child: Row(
                            children: List.generate(
                              4,
                              (i) => Expanded(
                                child: Semantics(
                                  selected: page == i,
                                  child: InkWell(
                                    onTap: () => setState(() => page = i),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          navIcons[i],
                                          size: 22,
                                          color: page == i ? p.accent : p.muted,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          nav[i],
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: page == i
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: page == i
                                                ? p.accent
                                                : p.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _landscapeHeader(BuildContext context, bool desktop) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(desktop ? 34 : 20, 10, desktop ? 34 : 20, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: () => _closeTingyu(context),
            style: IconButton.styleFrom(
              backgroundColor: p.surface,
              foregroundColor: p.text,
              side: BorderSide(color: p.border),
              minimumSize: const Size(38, 38),
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
            ),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
          ),
          const SizedBox(width: 6),
          if (!desktop) brand(context, compact: true),
          const Spacer(),
          const TingyuPomodoroButton(),
          const TingyuTopClock(),
        ],
      ),
    );
  }

  Widget loadingView(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.spa_outlined, size: 36, color: Palette.of(context).accent),
        const SizedBox(height: 20),
        const Text('正在整理你的声音空间', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 20),
        const SizedBox(
          width: 140,
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ],
    ),
  );

  Widget brand(BuildContext context, {bool compact = false}) {
    final p = Palette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 36 : 40,
          height: compact ? 36 : 40,
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.spa_outlined, color: p.onAccent, size: 25),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '听隅',
              style: TextStyle(
                fontFamily: AppFonts.zcool,
                fontSize: compact ? 22 : 25,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
                color: p.text,
              ),
            ),
            if (!compact)
              Text(
                'QUIET NOOK',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.8,
                  color: p.muted,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget sidebar(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: 194,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 33, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          brand(context),
          const SizedBox(height: 54),
          ...List.generate(
            4,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                selected: page == i,
                child: Material(
                  color: page == i ? p.soft : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: () => setState(() => page = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            navIcons[i],
                            color: page == i ? p.accent : p.muted,
                            size: 21,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            nav[i],
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: page == i
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: page == i ? p.accent : p.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.eco_outlined, color: p.muted, size: 29),
                const SizedBox(height: 12),
                Text(
                  '此刻，不必着急。',
                  style: TextStyle(fontSize: 14, color: p.muted, height: 1.8),
                ),
                const SizedBox(height: 22),
                Text(
                  p.dark ? '夜色正好' : '日光正好',
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget pageHeading(
    BuildContext context,
    String title,
    String subtitle, {
    Widget? trailing,
  }) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppFonts.zcool,
                    fontSize: 26,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(color: p.muted, fontSize: 14, height: 1.45),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  String get homeStatus {
    final parts = <String>['${c.tracks.length} 种声音'];
    final silent =
        c.tracks.isNotEmpty &&
        (c.master == 0 ||
            c.tracks.every((t) => ((t['volume'] as num?) ?? 0) <= 0));
    if (c.timerStatus == 'expired') {
      parts.add('声音已按计划停止');
    } else if (c.timerStatus == 'fading') {
      parts.add('正在渐弱 · ${clockText(c.remaining)}');
    } else if (silent) {
      parts.add('当前已静音');
    } else if (c.hasTimer) {
      parts.add(
        c.timerStatus == 'armed'
            ? '播放后开始计时'
            : c.playing
            ? '正在播放'
            : '计时中',
      );
    } else if (c.playing) {
      parts.add('正在播放');
    } else if (c.tracks.isNotEmpty) {
      parts.add('准备好了，就从这里开始');
    } else {
      parts.add('先选一份安静');
    }
    if (c.dirty) parts.add('有未保存修改');
    return parts.join(' · ');
  }

  String? get timerCaption {
    if (c.timerStatus == 'expired') {
      return '声音已按计划停止；再次播放不会自动重新计时。';
    }
    if (!c.hasTimer) return null;
    final end = endClockText(c.remaining);
    final fade = c.timerFade;
    final fadeText = fade > 0 ? '最后 $fade 秒渐弱' : '到点直接停止';
    if (c.timerStatus == 'armed') {
      return '播放后开始 · ${(c.timerDuration / 60).round()} 分钟 · $fadeText';
    }
    if (c.timerStatus == 'fading') {
      return '正在渐弱 · $end 结束';
    }
    return '剩余 ${clockText(c.remaining)} · $end 结束 · $fadeText';
  }

  Widget homePage(BuildContext context, bool wide) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(context, '为现在，留一点安静。', '给自己，留一小片安静。'),
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(19),
                ),
                child: AspectRatio(
                  aspectRatio: MediaQuery.sizeOf(context).width < 600
                      ? 1.85
                      : 2.55,
                  child: Image.asset(
                    'assets/tingyu/rain-nook.webp',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, .25),
                    color: p.dark ? const Color(0xffc6ccbd) : null,
                    colorBlendMode: p.dark ? BlendMode.modulate : null,
                    semanticLabel: '雨落在窗外，窗边放着书和一杯茶的水彩画',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.title,
                      style: const TextStyle(
                        fontFamily: AppFonts.zcool,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      homeStatus,
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    heroActions(context),
                    if (timerCaption != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 15,
                              color: p.muted,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                timerCaption!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: p.muted,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!wide) ...[
          const SizedBox(height: 30),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '当前声音',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${c.tracks.length} / 6 种',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: mixContents(context, embedded: true),
          ),
        ],
        const SizedBox(height: 31),
        Row(
          children: [
            const Expanded(
              child: Text(
                '为此刻，选一套声音',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: openLibrary,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('全部声音', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 15),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        LayoutBuilder(
          builder: (ctx, box) {
            final scale = MediaQuery.textScalerOf(ctx).scale(16) / 16;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: box.maxWidth >= 590 ? 4 : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 132.0 + math.max(0.0, scale - 1) * 80,
              ),
              itemCount: scenes.length,
              itemBuilder: (ctx, i) => sceneCard(context, scenes[i]),
            );
          },
        ),
        const SizedBox(height: 24),
        Material(
          color: p.soft,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: breathe,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.self_improvement_outlined,
                    size: 32,
                    color: p.accent,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '跟着呼吸一分钟',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '不用做得很好，舒服就好。',
                          style: TextStyle(fontSize: 14, color: p.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, size: 20, color: p.accent),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 15, color: p.muted),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                kIsWeb
                    ? '网页版在锁屏或切换应用后可能暂停声音；请勿将计时用作闹钟。'
                    : '离开此页后声音仍会继续；锁屏与后台表现取决于系统省电策略，请勿将计时用作闹钟。',
                style: TextStyle(fontSize: 12, color: p.muted, height: 1.6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget heroActions(BuildContext context) {
    final timer = timerAction(context);
    final save = OutlinedButton.icon(
      onPressed: saveMix,
      icon: const Icon(Icons.bookmark_border_rounded, size: 19),
      label: const Text('保存'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 15),
      ),
    );
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (scale > 1.2) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: timer),
              ),
              const SizedBox(width: 12),
              playButton(context, size: 58),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: save),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: timer),
        ),
        playButton(context, size: 58),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: save),
        ),
      ],
    );
  }

  Widget timerAction(BuildContext context) {
    final p = Palette.of(context);
    final active = c.hasTimer || c.timerStatus == 'expired';
    return OutlinedButton.icon(
      onPressed: timerSheet,
      icon: const Icon(Icons.timer_outlined, size: 19),
      label: Text(
        c.hasTimer
            ? clockText(c.remaining)
            : c.timerStatus == 'expired'
            ? '已结束'
            : '定时',
        style: TextStyle(
          fontSize: active ? 17 : 15,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: active ? p.soft : p.surface,
        foregroundColor: active ? p.accent : p.text,
        side: BorderSide(color: active ? p.accent : p.border),
      ),
    );
  }

  Widget sceneCard(BuildContext context, SceneSpec scene) {
    final p = Palette.of(context);
    return Material(
      color: p.dark ? p.surface : scene.tint,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => loadScene(scene),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(scene.icon, color: p.accent, size: 25),
                  const Spacer(),
                  Text(
                    '${scene.minutes} 分钟',
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scene.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    scene.subtitle,
                    style: TextStyle(fontSize: 12, color: p.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget smallTag(BuildContext context, String text, {IconData? icon}) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.subtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: p.muted),
            const SizedBox(width: 5),
          ],
          Text(text, style: TextStyle(fontSize: 12, color: p.muted)),
        ],
      ),
    );
  }

  Widget playButton(BuildContext context, {double size = 48}) {
    final p = Palette.of(context);
    final active = c.playing;
    final enabled = c.ready && !(c.busy && !active);
    return Tooltip(
      message: active ? '暂停声音' : '播放声音',
      excludeFromSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
          ),
          onPressed: enabled ? () => act('toggle') : null,
          child: c.busy && !active
              ? Semantics(
                  label: '正在准备播放',
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Semantics(
                  label: active ? '暂停声音' : '播放声音',
                  child: Icon(
                    active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: size * .52,
                  ),
                ),
        ),
      ),
    );
  }

  Widget mixContents(BuildContext context, {bool embedded = false}) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!embedded) ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  '当前混音',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              playButton(context, size: 48),
              const SizedBox(width: 6),
              Icon(Icons.headphones_outlined, size: 22, color: p.muted),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (!embedded) ...[
          Row(
            children: [
              Text(
                '${c.tracks.length} / 6 种声音',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
              const Spacer(),
              if (c.dirty)
                Text(
                  '有未保存修改',
                  style: TextStyle(
                    color: p.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        if (c.tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              '还没有声音。\n选几种，调成自己的环境。',
              style: TextStyle(color: p.muted, fontSize: 14, height: 1.7),
            ),
          ),
        ...c.tracks.map((t) => trackRow(context, t)),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: openLibrary,
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text('添加声音'),
          ),
        ),
        const SizedBox(height: 24),
        Divider(color: p.border),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.volume_down_outlined, size: 21, color: p.muted),
            const SizedBox(width: 9),
            const Text('总音量', style: TextStyle(fontSize: 15)),
            const Spacer(),
            Text(
              '${c.master}%',
              style: TextStyle(
                fontSize: 14,
                color: p.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Semantics(
          label: '总音量',
          child: Slider(
            value: c.master.toDouble(),
            min: 0,
            max: 100,
            label: '${c.master}%',
            onChanged: (v) => setMasterVolume(v.round()),
          ),
        ),
        if (!embedded) ...[
          const SizedBox(height: 15),
          Material(
            color: p.soft,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: timerSheet,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 19, color: p.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.hasTimer ? clockText(c.remaining) : '定时关闭',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: p.accent,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          if (c.hasTimer)
                            Text(
                              '${endClockText(c.remaining)} 结束',
                              style: TextStyle(fontSize: 12, color: p.accent),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: p.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saveMix,
              icon: const Icon(Icons.bookmark_border_rounded, size: 18),
              label: const Text('保存混音'),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              '不必很大声，刚刚好就好。',
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ),
        ],
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              c.error!,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget trackRow(BuildContext context, Map<String, dynamic> track) {
    final p = Palette.of(context);
    final sound = c.sound(track['id']);
    final value = (track['volume'] as num).toDouble();
    final tint = categoryColor(sound.category, p.dark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.subtle,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(sound.icon, size: 21, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  sound.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => trackVolumeSheet(sound, value),
                style: TextButton.styleFrom(
                  minimumSize: const Size(52, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  foregroundColor: p.muted,
                ),
                child: Text(
                  '${value.round()}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                tooltip: '移除${sound.name}',
                onPressed: () => act('remove', {'id': sound.id}),
                icon: const Icon(Icons.close_rounded, size: 17),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: '${sound.name}音量',
                  child: Slider(
                    value: value,
                    min: 0,
                    max: 100,
                    label: '${value.round()}%',
                    onChanged: (v) => setTrackVolume(sound.id, v.round()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> trackVolumeSheet(SoundSpec sound, double initial) async {
    var current = initial.round().clamp(0, 100);
    final input = TextEditingController(text: '$current');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final p = Palette.of(ctx);
          Future<void> apply(int value) async {
            current = value.clamp(0, 100);
            input.text = '$current';
            setLocal(() {});
            await setTrackVolume(sound.id, current);
          }

          return sheet(ctx, sound.name, [
            Text('精确调整这一轨的音量', style: TextStyle(color: p.muted, fontSize: 14)),
            const SizedBox(height: 22),
            Center(
              child: Text(
                '$current%',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                  color: p.accent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Slider(
              value: current.toDouble(),
              min: 0,
              max: 100,
              divisions: 100,
              label: '$current%',
              onChanged: (v) => unawaited(apply(v.round())),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => unawaited(apply(current - 5)),
                  child: const Text('减 5'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: input,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(suffixText: '%'),
                    onSubmitted: (v) =>
                        unawaited(apply(int.tryParse(v) ?? current)),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => unawaited(apply(current + 5)),
                  child: const Text('加 5'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final typed = int.tryParse(input.text);
                  if (typed != null) unawaited(apply(typed));
                  Navigator.pop(ctx);
                },
                child: const Text('完成'),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget miniPlayer(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: p.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => page = 0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.spa_outlined, size: 24, color: p.accent),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${c.tracks.length} 种声音${c.hasTimer
                                      ? c.timerStatus == 'armed'
                                            ? ' · 播放后计时'
                                            : ' · 定时中'
                                      : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (c.hasTimer)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      clockText(c.remaining),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                playButton(context, size: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget libraryPage(BuildContext context) {
    final p = Palette.of(context);
    final barScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final barHeight = 48.0 + math.max(0.0, barScale - 1) * 18;
    final filtered = c.library
        .where(
          (s) =>
              (category == '全部' || s.category == category) &&
              ('${s.name}${s.category}${s.description}'.contains(query)),
        )
        .toList();
    final categories = [
      for (final name in categoryOrder)
        if (name == '全部' ||
            name == '本地' ||
            c.library.any((s) => s.category == name))
          name,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(context, '声音', '选几种声音，调成自己的环境。'),
        TextField(
          controller: search,
          onTap: () => c.loadFullFont(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: '搜索雨声、森林、风铃…',
            labelText: '搜索声音',
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    tooltip: '清除搜索',
                    onPressed: () => setState(() {
                      query = '';
                      search.clear();
                    }),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  )
                : null,
          ),
          onChanged: (v) => setState(() => query = v.trim()),
        ),
        const SizedBox(height: 19),
        SizedBox(
          height: barHeight,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final v in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(v, style: const TextStyle(fontSize: 14)),
                          selected: category == v,
                          showCheckmark: false,
                          selectedColor: p.soft,
                          backgroundColor: p.surface,
                          labelStyle: TextStyle(
                            color: category == v ? p.accent : p.muted,
                            fontWeight: category == v
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          side: BorderSide(
                            color: category == v ? p.accent : p.border,
                          ),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 9,
                          ),
                          onSelected: (_) => setState(() => category = v),
                        ),
                      ),
                    const SizedBox(width: 26),
                  ],
                ),
              ),
              IgnorePointer(
                child: Container(
                  width: 26,
                  height: barHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [p.bg.withValues(alpha: 0), p.bg],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (category == '本地') ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: p.soft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.supportsImport ? '把自己的声音，收进来。' : '内置声音，随时可用。',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  c.supportsImport
                      ? '音频只保存在${kIsWeb ? "此浏览器" : "此设备"}，不会上传。支持常见音频格式，单个文件不超过 50 MB，时长 5 秒到 10 分钟。'
                      : '当前客户端暂未开放本地导入；内置自然录音、合成噪声和场景预设都可以直接使用。',
                  style: TextStyle(fontSize: 14, color: p.muted, height: 1.6),
                ),
                if (c.supportsImport) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: c.busy ? null : importAudio,
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: Text(c.busy ? '正在处理音频' : '导入本地音频'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (filtered.isEmpty) ...[
          emptyState(
            context,
            query.isNotEmpty ? '没有找到这个声音' : '把喜欢的声音，收进这一页',
            query.isNotEmpty ? '试试搜索“雨”或“水流”，或者清除搜索。' : '导入一段喜欢的环境音，与内置声音一起播放。',
            Icons.search_rounded,
          ),
          if (query.isNotEmpty)
            Center(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  query = '';
                  search.clear();
                }),
                child: const Text('清除搜索'),
              ),
            ),
        ],
        LayoutBuilder(
          builder: (ctx, box) {
            final scale = MediaQuery.textScalerOf(ctx).scale(14) / 14;
            final columns = scale > 1.35 && box.maxWidth < 600
                ? 1
                : box.maxWidth >= 850
                ? 4
                : box.maxWidth >= 550
                ? 3
                : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 13,
                mainAxisSpacing: 13,
                mainAxisExtent: 258.0 + math.max(0.0, scale - 1) * 120,
              ),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) => soundCard(ctx, filtered[i]),
            );
          },
        ),
        const SizedBox(height: 22),
        Text(
          '环境录音与合成音色已分别标注。试听会暂时暂停当前混音，8 秒后恢复。',
          style: TextStyle(fontSize: 12, color: p.muted, height: 1.6),
        ),
      ],
    );
  }

  Widget soundCard(BuildContext context, SoundSpec sound) {
    final p = Palette.of(context);
    final selected = c.contains(sound.id);
    final previewing = c.previewId == sound.id;
    final synthetic = sound.synthesized || c.kinds[sound.id] == 'synth';
    final tint = categoryColor(sound.category, p.dark);
    final source = sound.category == '本地'
        ? '本地音频'
        : synthetic
        ? '合成音色'
        : '环境录音';
    return Material(
      color: selected ? p.soft : p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? p.accent.withValues(alpha: .65) : p.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => soundDetailSheet(sound),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: p.subtle,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(sound.icon, size: 26, color: tint),
                  ),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_circle_rounded, size: 19, color: p.accent),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                sound.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                sound.description,
                style: TextStyle(fontSize: 14, color: p.muted, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '$source · ${sound.category}',
                style: TextStyle(fontSize: 12, color: p.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () => act(
                        previewing ? 'stopPreview' : 'preview',
                        {'id': sound.id},
                      ),
                      icon: Icon(
                        previewing
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                      ),
                      label: Text(
                        previewing
                            ? c.previewRemaining > 0
                                  ? '${c.previewRemaining.ceil()}s'
                                  : '停止'
                            : '试听',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    onPressed: () {
                      if (selected) {
                        setState(() => page = 0);
                        return;
                      }
                      act('add', {'id': sound.id, 'volume': 45});
                    },
                    icon: selected
                        ? null
                        : const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      selected ? '已加入' : '加入',
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> soundDetailSheet(SoundSpec sound) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (ctx) => AnimatedBuilder(
      animation: c,
      builder: (ctx, _) {
        final p = Palette.of(ctx);
        final selected = c.contains(sound.id);
        final previewing = c.previewId == sound.id;
        final synthetic = sound.synthesized || c.kinds[sound.id] == 'synth';
        final tint = categoryColor(sound.category, p.dark);
        final source = sound.category == '本地'
            ? '本地音频'
            : synthetic
            ? '合成音色'
            : '环境录音';
        return sheet(ctx, '声音详情', [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: p.subtle,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(sound.icon, size: 38, color: tint),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sound.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${sound.category} · $source',
                      style: TextStyle(fontSize: 14, color: p.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            sound.description,
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
          const SizedBox(height: 10),
          Text(
            '喜欢它，就让它加入当前的混音。',
            style: TextStyle(fontSize: 14, color: p.muted),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => act(previewing ? 'stopPreview' : 'preview', {
                    'id': sound.id,
                  }),
                  icon: Icon(
                    previewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    size: 19,
                  ),
                  label: Text(previewing ? '停止试听' : '单独试听'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    if (selected) {
                      Navigator.pop(ctx);
                      setState(() => page = 0);
                      return;
                    }
                    act('add', {'id': sound.id, 'volume': 45});
                  },
                  icon: Icon(
                    selected ? Icons.check_rounded : Icons.add_rounded,
                    size: 19,
                  ),
                  label: Text(selected ? '已加入' : '加入混音'),
                ),
              ),
            ],
          ),
          if (selected)
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  act('remove', {'id': sound.id});
                },
                child: const Text('从混音中移除'),
              ),
            ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '单独试听 8 秒，不会加入混音。',
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ),
        ]);
      },
    ),
  );

  Widget emptyState(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: p.soft, shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: p.accent),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 14, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget sortButton(BuildContext context) {
    final p = Palette.of(context);
    const labels = {'recent': '最近使用', 'created': '最近创建', 'name': '名称排序'};
    return PopupMenuButton<String>(
      initialValue: c.favoriteSort,
      tooltip: '收藏排序',
      position: PopupMenuPosition.under,
      onSelected: c.setFavoriteSort,
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'recent', child: Text('最近使用')),
        PopupMenuItem(value: 'created', child: Text('最近创建')),
        PopupMenuItem(value: 'name', child: Text('名称排序')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 18, color: p.muted),
            const SizedBox(width: 6),
            Text(
              labels[c.favoriteSort] ?? '最近使用',
              style: TextStyle(fontSize: 14, color: p.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget favoritesHeader(BuildContext context) => pageHeading(
    context,
    '收藏',
    '你的声音配方，都在这里。',
    trailing: sortButton(context),
  );

  /// 收藏页：标题与排序固定在顶部，只有配方列表滚动。
  Widget favoritesTab(BuildContext context, bool desktop) {
    final horizontal = desktop ? 34.0 : 20.0;
    final top = widget.landscapeHeader
        ? (desktop ? 10.0 : 6.0)
        : (desktop ? 32.0 : 14.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: favoritesHeader(context),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const PageStorageKey('page-2'),
            padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 34),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1050),
              child: favoritesPage(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget favoritesPage(BuildContext context) {
    final p = Palette.of(context);
    final favorites = c.sortedFavorites;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (favorites.isEmpty) ...[
          emptyState(
            context,
            '还没有声音配方',
            '调好一份混音，再把它留下来。',
            Icons.bookmark_border_rounded,
          ),
          Center(
            child: FilledButton.icon(
              onPressed: openLibrary,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('去选声音'),
            ),
          ),
        ],
        ...favorites.map((f) {
          final tracks = validTracks(f['tracks']);
          final ids = c.library.map((s) => s.id).toSet();
          final missing = tracks.where((t) => !ids.contains(t['id'])).length;
          final current = c.favoriteId == f['id'];
          final unavailable = tracks.isEmpty;
          final categories = <String>[];
          for (final t in tracks) {
            final name = c.sound(t['id']).category;
            if (!categories.contains(name)) categories.add(name);
            if (categories.length == 3) break;
          }
          final status = missing > 0
              ? '$missing 个声音不可用'
              : current && c.dirty
              ? '有未保存修改'
              : current
              ? c.playing
                    ? '正在播放'
                    : '当前组合'
              : '${tracks.length} 种声音${f['seconds'] is num ? ' · 建议 ${(f['seconds'] as num) ~/ 60} 分钟' : ''}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Material(
              color: p.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: current ? p.accent : p.border,
                  width: current ? 1.4 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: unavailable ? null : () => loadFavorite(f),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: p.subtle,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              tracks.isEmpty
                                  ? Icons.spa_outlined
                                  : c.sound(tracks.first['id']).icon,
                              color: tracks.isEmpty
                                  ? p.accent
                                  : categoryColor(
                                      c.sound(tracks.first['id']).category,
                                      p.dark,
                                    ),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f['name'] as String,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: missing > 0
                                        ? p.warning
                                        : current && c.dirty
                                        ? p.accent
                                        : p.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: '更多操作',
                            position: PopupMenuPosition.under,
                            icon: const Icon(
                              Icons.more_horiz_rounded,
                              size: 22,
                            ),
                            onSelected: (value) async {
                              switch (value) {
                                case 'load':
                                  await loadFavorite(f, autoplay: false);
                                  break;
                                case 'rename':
                                  await renameFavorite(f);
                                  break;
                                case 'delete':
                                  if (await confirm(
                                    '删除这份声音配方？',
                                    '“${f['name']}”会从收藏中移除，声音文件不会被删除。',
                                    accept: '删除收藏',
                                  )) {
                                    if (!c.deleteFavorite(f['id'])) {
                                      toast(c.error!);
                                    }
                                  }
                                  break;
                              }
                            },
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(value: 'load', child: Text('仅载入')),
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('重命名'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('删除收藏'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final category in categories)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: p.subtle,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    categoryIcon(category),
                                    size: 14,
                                    color: categoryColor(category, p.dark),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    category,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: unavailable ? null : () => loadFavorite(f),
                          icon: const Icon(Icons.play_arrow_rounded, size: 19),
                          label: Text(unavailable ? '声音不可用' : '加载并播放'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> renameFavorite(Map<String, dynamic> favorite) async {
    unawaited(c.loadFullFont());
    final input = TextEditingController(text: favorite['name'] as String);
    String? validation;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('重命名', style: TextStyle(fontSize: 21)),
          content: TextField(
            controller: input,
            autofocus: true,
            maxLength: 24,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: '混音名称',
              errorText: validation,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (input.text.trim().isEmpty) {
                  setLocal(() => validation = '给这份混音起个名字。');
                  return;
                }
                Navigator.pop(ctx, input.text.trim());
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (name != null && c.renameFavorite(favorite['id'] as String, name)) {
      toast('已重命名。');
    }
  }

  Widget settingsPage(BuildContext context) {
    final p = Palette.of(context);
    final size = c.locals.fold<num>(
      0,
      (sum, l) => sum + (l['size'] as num? ?? 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(context, '设置', '一些简单的设置，让这里更像你。'),
        settingSection(context, '体验', [
          Text(
            '外观跟随 Citro 的明暗设置。',
            style: TextStyle(fontSize: 14, color: p.muted, height: 1.5),
          ),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('减少动态效果', style: TextStyle(fontSize: 16)),
            subtitle: Text(
              '呼吸引导保留文字提示，减少画面缩放。',
              style: TextStyle(fontSize: 14, color: p.muted),
            ),
            value: c.reducedMotion,
            onChanged: c.setReducedMotion,
          ),
        ]),
        settingSection(context, '播放', [
          const Text(
            '默认渐弱',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '新建计时时默认使用，只影响新计时，不改变正在运行的计时。',
            style: TextStyle(fontSize: 14, color: p.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [0, 15, 30, 60, 120]
                .map(
                  (s) => selectButton(
                    context,
                    s == 0 ? '关闭' : '$s 秒',
                    c.defaultFade == s,
                    () => c.setDefaultFade(s),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          infoRow(
            context,
            Icons.restore_rounded,
            '恢复上次混音',
            '打开时恢复上次的声音与音量，但不会自动发声。',
          ),
          const SizedBox(height: 20),
          infoRow(
            context,
            Icons.headphones_outlined,
            '后台与锁屏',
            kIsWeb
                ? '网页版在锁屏或切换应用后可能暂停声音；系统媒体控件取决于浏览器支持，关闭页面会结束播放。'
                : '原生端离开页面后声音仍会继续；锁屏与后台播放取决于系统策略。',
          ),
        ]),
        settingSection(context, '存储', [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${c.locals.length} 个本地文件，占用 ${sizeText(size)}',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              if (c.supportsImport)
                TextButton.icon(
                  onPressed: c.busy ? null : importAudio,
                  icon: const Icon(Icons.file_upload_outlined, size: 17),
                  label: const Text('导入'),
                ),
            ],
          ),
          if (c.locals.isEmpty)
            Text(
              c.supportsImport
                  ? '还没有导入声音。你可以把自己的环境音收进来。'
                  : '当前客户端使用内置声音；本地导入在 Web 端可用。',
              style: TextStyle(fontSize: 14, color: p.muted, height: 1.6),
            ),
          ...c.locals.map(
            (l) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.audio_file_outlined,
                color: categoryColor('本地', p.dark),
              ),
              title: Text(
                l['name'] as String? ?? '本地声音',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
              subtitle: Text(
                '${clockText(l['duration'] as num? ?? 0)} · ${sizeText(l['size'] as num? ?? 0)}',
                style: const TextStyle(fontSize: 14),
              ),
              trailing: IconButton(
                tooltip: '删除本地声音${l['name']}',
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: () async {
                  if (await confirm(
                    '删除本地声音？',
                    '删除“${l['name']}”的浏览器副本。正在播放的这一轨会被移除，关联收藏会标记缺失；原文件不会被改动。',
                    accept: '删除声音',
                  ))
                    await act('deleteLocal', {'id': l['id']});
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '清除网站数据会删除收藏和导入副本。不同浏览器或不同端口的数据不互通。',
            style: TextStyle(fontSize: 12, color: p.muted, height: 1.6),
          ),
        ]),
        settingSection(context, '关于听隅', [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.spa_outlined, color: p.onAccent, size: 26),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '听隅',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '版本 1.0.0 · Web',
                    style: TextStyle(fontSize: 14, color: p.muted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          infoRow(
            context,
            Icons.offline_bolt_outlined,
            '不需要账号，也没有广告',
            kIsWeb
                ? '内置录音按需加载，需要联网；导入的个人音频只存入此浏览器，不会上传。'
                : '内置录音按需联网加载；当前客户端不写入个人音频文件。',
          ),
          const SizedBox(height: 20),
          infoRow(
            context,
            Icons.water_drop_outlined,
            '录音与合成，分别标明',
            '自然录音做了循环处理；水下静域与三种噪声为合成音色，近水气泡是真实录音。本地导入自动处理接缝，仍建议试听，不保证所有文件都能无感循环。',
          ),
          const SizedBox(height: 20),
          infoRow(
            context,
            Icons.lock_outline_rounded,
            '数据留在这台设备',
            kIsWeb
                ? '收藏和设置都保存在此浏览器。清除网站数据会一并删除，不同浏览器或不同端口的数据不互通。'
                : '收藏和设置保存在本机；清除应用数据会一并删除。',
          ),
        ]),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '听隅   /   给自己，留一小片安静。',
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ),
        ),
      ],
    );
  }

  Widget settingSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    final p = Palette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget infoRow(
    BuildContext context,
    IconData icon,
    String title,
    String content,
  ) {
    final p = Palette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: p.accent),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                content,
                style: TextStyle(fontSize: 14, color: p.muted, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class BreathingPage extends StatefulWidget {
  final bool reducedMotion;
  const BreathingPage({super.key, required this.reducedMotion});
  @override
  State<BreathingPage> createState() => _BreathingPageState();
}

class _BreathingPageState extends State<BreathingPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController animation;
  final stopwatch = Stopwatch();
  Timer? ticker;
  int minutes = 1;
  bool running = true;
  bool done = false;
  int _phase = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    animation.addListener(_onPhaseTick);
    stopwatch.start();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!done && stopwatch.elapsed.inSeconds >= minutes * 60) {
        stopwatch.stop();
        animation.stop();
        running = false;
        done = true;
        unawaited(Chime.done());
        unawaited(Haptics.done());
      }
      setState(() {});
    });
  }

  void _onPhaseTick() {
    final next = animation.value < .4 ? 0 : 1;
    if (next == _phase) return;
    _phase = next;
    if (!running || done) return;
    unawaited(Chime.breath(inhale: next == 0));
    unawaited(Haptics.breath());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && running) toggle();
  }

  void toggle() {
    setState(() {
      if (done) {
        done = false;
        stopwatch.reset();
        animation.value = 0;
      }
      running = !running;
      if (running) {
        _phase = animation.value < .4 ? 0 : 1;
        stopwatch.start();
        animation.repeat();
      } else {
        stopwatch.stop();
        animation.stop();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    stopwatch.stop();
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final reduce =
        widget.reducedMotion || MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        tooltip: '返回',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded, size: 22),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                '呼吸',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '吸气 4 秒，呼气 6 秒。不必屏息。',
                              style: TextStyle(fontSize: 14, color: p.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    height: 250,
                    child: Center(
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (ctx, _) {
                          final value = animation.value;
                          final phase = value < .4
                              ? value / .4
                              : 1 - (value - .4) / .6;
                          return Transform.scale(
                            scale: reduce
                                ? 1
                                : .78 +
                                      Curves.easeInOut.transform(
                                            phase.clamp(0, 1),
                                          ) *
                                          .22,
                            child: Container(
                              width: 220,
                              height: 220,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: p.soft,
                                border: Border.all(
                                  color: p.accent.withValues(alpha: .18),
                                  width: 15,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    done
                                        ? '很好，就这样'
                                        : !running
                                        ? '按自己的节奏'
                                        : value < .4
                                        ? '慢慢吸气'
                                        : '轻轻呼气',
                                    style: TextStyle(
                                      fontSize: 24,
                                      color: p.accent,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    clockText(
                                      math.max(
                                        0,
                                        minutes * 60 -
                                            stopwatch.elapsed.inSeconds,
                                      ),
                                    ),
                                    style: TextStyle(
                                      color: p.muted,
                                      fontSize: 15,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [1, 3, 5]
                        .map(
                          (m) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: ChoiceChip(
                              label: Text('$m 分钟'),
                              selected: minutes == m,
                              showCheckmark: false,
                              selectedColor: p.soft,
                              backgroundColor: p.surface,
                              side: BorderSide(
                                color: minutes == m ? p.accent : p.border,
                              ),
                              shape: const StadiumBorder(),
                              labelStyle: TextStyle(
                                fontSize: 14,
                                color: minutes == m ? p.accent : p.muted,
                              ),
                              onSelected: (_) {
                                setState(() {
                                  minutes = m;
                                  stopwatch.reset();
                                  stopwatch.start();
                                  done = false;
                                  running = true;
                                  _phase = 0;
                                  animation.value = 0;
                                  animation.repeat();
                                });
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: FilledButton.icon(
                      onPressed: toggle,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      icon: Icon(
                        done
                            ? Icons.refresh_rounded
                            : running
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 19,
                      ),
                      label: Text(
                        done
                            ? '再呼吸一会儿'
                            : running
                            ? '暂停引导'
                            : '继续引导',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '引导结束不会关闭混音。感到不适时，请停止。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 12, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
