import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/game_sfx.dart';
import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'game_common.dart';
import 'game_ui.dart';

/// 结算卡数字高亮色（与淘气小球 _floatInk 同款金棕）。
const Color _snakeFloatInk = Color(0xFF8A5A12);

class GameSnakePage extends StatefulWidget {
  const GameSnakePage({super.key});
  @override
  State<GameSnakePage> createState() => _GameSnakePageState();
}

class _GameSnakePageState extends State<GameSnakePage> {
  static const _diffs = {
    'easy': ('简单', 160),
    'std': ('标准', 110),
    'hard': ('困难', 70),
  };
  static const gridSize = 17;

  String diff = 'std';
  List<Point> snake = [];
  Point food = const Point(0, 0);
  int dirX = 1, dirY = 0;
  int nextX = 1, nextY = 0;
  int score = 0;
  bool started = false;
  bool over = false;
  bool submitted = false;
  Timer? timer;
  final FocusNode _keyFocus = FocusNode(debugLabel: 'snake-keyboard');

  bool get _keyboardEnabled => platform.isWindows || kIsWeb;

  /// 「正在玩」进度（web gamesLiveHeartbeat('gsnake', '得分 N · 长度 M')）。
  final ValueNotifier<String> _progress = ValueNotifier<String>('得分 0');

  @override
  void initState() {
    super.initState();
    _newGame();
    if (_keyboardEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keyFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    _progress.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  void _syncLive() {
    _progress.value = over
        ? '得分 $score · 已结束'
        : '得分 $score · 长度 ${snake.length}';
  }

  void _newGame() {
    timer?.cancel();
    snake = [const Point(9, 8), const Point(8, 8), const Point(7, 8)];
    dirX = 1;
    dirY = 0;
    nextX = 1;
    nextY = 0;
    score = 0;
    started = false;
    over = false;
    submitted = false;
    _spawnFood();
    _syncLive();
    setState(() {});
  }

  void _spawnFood() {
    final rnd = math.Random();
    do {
      food = Point(rnd.nextInt(gridSize), rnd.nextInt(gridSize));
    } while (snake.contains(food));
  }

  void _start() {
    if (started || over) return;
    started = true;
    _runTimer();
    setState(() {});
  }

  void _runTimer() {
    timer?.cancel();
    timer = Timer.periodic(
      Duration(milliseconds: _diffs[diff]!.$2),
      (_) => _tick(),
    );
  }

  void _turn(int x, int y) {
    if (over) return;
    if (!started) _start();
    if (x == -dirX && y == -dirY) return;
    nextX = x;
    nextY = y;
  }

  (int, int)? _directionFor(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      return (0, -1);
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      return (0, 1);
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      return (-1, 0);
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      return (1, 0);
    }
    return null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_keyboardEnabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final direction = _directionFor(event.logicalKey);
    if (direction == null) return KeyEventResult.ignored;
    _turn(direction.$1, direction.$2);
    return KeyEventResult.handled;
  }

  void _tick() {
    if (over) return;
    dirX = nextX;
    dirY = nextY;
    final head = snake.first;
    final nxt = Point(head.x + dirX, head.y + dirY);
    if (nxt.x < 0 || nxt.x >= gridSize || nxt.y < 0 || nxt.y >= gridSize) {
      _end();
      return;
    }
    if (snake.contains(nxt) && !(nxt == snake.last)) {
      _end();
      return;
    }
    setState(() {
      snake.insert(0, nxt);
      if (nxt == food) {
        score += 10;
        _spawnFood();
        GameSfx.eat();
      } else {
        snake.removeLast();
      }
    });
    _syncLive();
  }

  void _end() {
    over = true;
    started = false;
    timer?.cancel();
    GameSfx.lose();
    context.app.saveLocalBest('snake:$diff', score);
    if (!submitted) {
      submitted = true;
      context.app.submitScore('snake:$diff', score);
    }
    _syncLive();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final best = context.app.localBest('snake:$diff');
    final view = GameSnakeView(
      diff: diff,
      snake: snake,
      food: food,
      score: score,
      best: best,
      over: over,
      liveProgress: _progress,
      onDiff: (d) {
        setState(() => diff = d);
        _newGame();
      },
      onNewGame: _newGame,
      onTurn: _turn,
      onRetry: _newGame,
      onRank: () => showGameLeaderboard(
        context,
        game: 'snake',
        title: '贪吃蛇',
        difficulties: const [('easy', '简单'), ('std', '标准'), ('hard', '困难')],
        initial: diff,
      ),
      keyboardMode: _keyboardEnabled,
    );
    return Focus(
      focusNode: _keyFocus,
      autofocus: _keyboardEnabled,
      onKeyEvent: _onKey,
      child: view,
    );
  }
}

/// 贪吃蛇页面视觉层（golden 用固定数据渲染）
class GameSnakeView extends StatelessWidget {
  const GameSnakeView({
    super.key,
    required this.snake,
    required this.food,
    this.score = 0,
    this.best = 0,
    this.diff = 'std',
    this.over = false,
    this.liveProgress,
    this.onDiff,
    this.onNewGame,
    this.onTurn,
    this.onRetry,
    this.onRank,
    this.keyboardMode = false,
  });

  final List<Point> snake;
  final Point food;
  final int score;
  final int best;
  final String diff;
  final bool over;
  final ValueNotifier<String>? liveProgress;
  final ValueChanged<String>? onDiff;
  final VoidCallback? onNewGame;
  final void Function(int x, int y)? onTurn;
  final VoidCallback? onRetry;
  final VoidCallback? onRank;
  final bool keyboardMode;

  static const _diffItems = <(String, String)>[
    ('easy', '简单'),
    ('std', '标准'),
    ('hard', '困难'),
  ];

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameKey: 'gsnake',
      title: '贪吃蛇',
      // v1.6.2：恢复「正在玩」组件（此前误关，web 端 #gsnakePage 有该条）。
      showLive: true,
      liveProgress: liveProgress,
      rankDifficulties: const [('easy', '简单'), ('std', '标准'), ('hard', '困难')],
      rankInitial: diff,
      boardGap: 0,
      board: LayoutBuilder(
        builder: (context, cons) {
          final media = MediaQuery.sizeOf(context);
          final duoShort =
              CitroForm.duoInner(media) && media.width > media.height;
          final duoPortrait =
              CitroForm.duoInner(media) && media.height >= media.width;
          final landscapeTablet =
              (media.width >= 900 &&
                  media.shortestSide >= 600 &&
                  media.width > media.height) ||
              duoShort;
          final available = cons.maxWidth.isFinite ? cons.maxWidth : 760.0;
          final heightCap = duoShort
              ? math.max(260.0, media.height - 300)
              : duoPortrait
              ? math.max(320.0, media.height - 550)
              : 520.0;
          final keyboard = keyboardMode && !kIsWeb;
          final boardW = keyboard
              ? math.min(available, math.min(520.0, heightCap))
              : landscapeTablet
              ? math.min(
                  520.0,
                  math.max(320.0, math.min(available - 266, heightCap)),
                )
              : math.min(available, math.min(520.0, heightCap));
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _diffTabs(context),
              const SizedBox(height: 12),
              _hud(context),
              const SizedBox(height: 14),
              if (keyboard) ...[
                _board(context, boardW),
                const SizedBox(height: 8),
                Text(
                  'WASD / 方向键控制',
                  style: context.body(size: 11, color: context.c.inkSoft),
                ),
              ] else if (landscapeTablet)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _board(context, boardW),
                    const SizedBox(width: 24),
                    _dpad(context),
                  ],
                )
              else ...[
                _board(context, boardW),
                const SizedBox(height: 6),
                _dpad(context),
              ],
              if (kIsWeb) ...[
                const SizedBox(height: 8),
                Text(
                  'WASD / 方向键控制',
                  style: context.body(size: 11, color: context.c.inkSoft),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// .gsnake-diff：176x33，3 个 54x31 的按钮
  Widget _diffTabs(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: 176,
      height: 33,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.bg2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _diffItems.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  right: i == _diffItems.length - 1 ? 0 : 6,
                ),
                child: _diffTab(context, _diffItems[i]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _diffTab(BuildContext context, (String, String) item) {
    final c = context.c;
    final on = diff == item.$1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDiff == null ? null : () => onDiff!(item.$1),
      child: Container(
        width: 54,
        height: 31,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.transparent),
        ),
        child: Text(
          item.$2,
          style: TextStyle(
            fontFamily: AppFonts.noto,
            fontFamilyFallback: AppFonts.bodyFallback,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.4,
            color: on ? const Color(0xFF2E2C22) : c.ink2,
          ),
        ),
      ),
    );
  }

  /// .g-hud：pills + actions 一行放不下时自动换行（web .g-hud flex-wrap），
  /// 窄屏机型不会再把按钮挤出屏幕造成「不居中」的观感。
  Widget _hud(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 9,
      runSpacing: 8,
      children: [
        GameScorePill(label: '分数', value: '$score', bump: score > 0),
        GameScorePill(label: '最高分', value: best > 0 ? '$best' : '0'),
        GameActionButton(
          label: '新游戏',
          icon: GameIcons.reset,
          primary: true,
          height: 56.64,
          onTap: onNewGame,
        ),
        GameActionButton(
          label: '排行榜',
          icon: GameIcons.trophySimple,
          height: 56.64,
          onTap: onRank,
        ),
      ],
    );
  }

  Widget _board(BuildContext context, double boardW) {
    return Center(
      child: SizedBox(
        width: boardW,
        height: boardW,
        child: GestureDetector(
          onPanEnd: (d) {
            if (onTurn == null) return;
            final v = d.velocity.pixelsPerSecond;
            if (v.dx.abs() > v.dy.abs()) {
              onTurn!(v.dx > 0 ? 1 : -1, 0);
            } else {
              onTurn!(0, v.dy > 0 ? 1 : -1);
            }
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SnakeBoardPainter(
                    snake: snake,
                    food: food,
                    grid: 17,
                    cellBg: context.c.surface2,
                    boardBg: context.c.line2,
                    bodyColor: context.c.mint,
                    headColor: context.c.mintInk,
                    foodColor: context.c.accent,
                    // (棋盘宽 - 左右边框2 - 上下左右留白12 - 16个1px间隙) / 17
                    // 370 宽时 = 20，与 web 一致；窄屏时等比缩小保证两侧对称
                    cell: math.max(10.0, (boardW - 30) / 17),
                  ),
                ),
              ),
              if (over) Positioned.fill(child: _overlay(context, boardW)),
            ],
          ),
        ),
      ),
    );
  }

  /// 结算浮层 —— v1.6.1 起与淘气小球结算卡同一套样式
  /// （半透明纸面 / 圆角 22 / Kalam 标题 / 灰描述金棕数字 / 主按钮垂直居中）。
  Widget _overlay(BuildContext context, double size) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF0FCF8F0),
        border: Border.all(color: const Color(0x292E2C22)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '游戏结束',
            style: TextStyle(
              fontFamily: AppFonts.kalam,
              fontSize: 22,
              height: 36.3 / 22,
              letterSpacing: 1.32,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '得分 '),
                  TextSpan(
                    text: '$score',
                    style: const TextStyle(
                      color: _snakeFloatInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' · 蛇长 ${snake.length}'),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontFamilyFallback: AppFonts.bodyFallback,
                fontSize: 13,
                height: 22.1 / 13,
                color: c.ink2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          GameActionButton(label: '再来一局', primary: true, onTap: onRetry),
        ],
      ),
    );
  }

  /// .gsnake-dpad：240x240 grid 3x3，gap 8，四个 74.67 圆钮
  Widget _dpad(BuildContext context) {
    final c = context.c;
    const cell = 74.6719;
    const step = cell + 8;
    const size = step * 3 - 8; // 240.0157
    Widget btn(String path, int col, int row, int dx, int dy) {
      return Positioned(
        left: col * step,
        top: row * step,
        width: cell,
        height: cell,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTurn == null ? null : () => onTurn!(dx, dy),
          child: Container(
            decoration: BoxDecoration(
              color: c.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: c.line2),
            ),
            child: Center(
              child: AppIcon(
                '<svg viewBox="0 0 24 24" fill="#000000">$path</svg>',
                size: 26,
                color: c.accentInk,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          btn(GameIcons.arrowUp, 1, 0, 0, -1),
          btn(GameIcons.arrowLeftSolid, 0, 1, -1, 0),
          btn(GameIcons.arrowRightSolid, 2, 1, 1, 0),
          btn(GameIcons.arrowDown, 1, 2, 0, 1),
        ],
      ),
    );
  }
}

class Point {
  final int x, y;
  const Point(this.x, this.y);
  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
}

/// .gsnake-board：370x370 的 17x17 网格（cell 20，gap 1，padding 6）
class _SnakeBoardPainter extends CustomPainter {
  _SnakeBoardPainter({
    required this.snake,
    required this.food,
    required this.grid,
    required this.cellBg,
    required this.boardBg,
    required this.bodyColor,
    required this.headColor,
    required this.foodColor,
    this.cell = 20,
  });

  final List<Point> snake;
  final Point food;
  final int grid;
  final Color cellBg;
  final Color boardBg;
  final Color bodyColor;
  final Color headColor;
  final Color foodColor;

  /// 格子边长。v1.6.0：随棋盘宽度缩放（旧实现固定 20px，内容区 < 370 的
  /// 机型上棋盘被右侧裁掉一截，看起来没居中）。
  final double cell;

  static const double _radius = 14;
  static const double _pad = 6; // board padding
  static const double _gap = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(_radius));
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(rect, Paint()..color = boardBg);

    // inset 0 2px 6px rgba(90,74,44,.09)
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = const Color(0x175A4A2C));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(const Offset(0, 2)),
        const Radius.circular(_radius),
      ),
      Paint()
        ..blendMode = BlendMode.dstOut
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();

    final origin = 1 + _pad;
    final step = cell + _gap;
    final body = Paint()..color = bodyColor;
    final head = Paint()..color = headColor;
    final bg = Paint()..color = cellBg;
    final headPt = snake.isNotEmpty ? snake.first : null;
    for (var row = 0; row < grid; row++) {
      for (var col = 0; col < grid; col++) {
        final cellRect = Rect.fromLTWH(
          origin + col * step,
          origin + row * step,
          cell,
          cell,
        );
        final p = Point(col, row);
        final isHead = headPt != null && headPt == p;
        if (isHead) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(cellRect, const Radius.circular(5)),
            head,
          );
          continue;
        }
        if (snake.length > 1 && snake.contains(p)) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(cellRect, const Radius.circular(4)),
            body,
          );
          continue;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(cellRect, const Radius.circular(2)),
          bg,
        );
      }
    }
    if (food.x >= 0 && food.x < grid && food.y >= 0 && food.y < grid) {
      final fr = Rect.fromLTWH(
        origin + food.x * step,
        origin + food.y * step,
        cell,
        cell,
      );
      canvas.drawOval(fr, Paint()..color = foodColor);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SnakeBoardPainter old) =>
      old.snake != snake ||
      old.food != food ||
      old.grid != grid ||
      old.cellBg != cellBg ||
      old.boardBg != boardBg ||
      old.bodyColor != bodyColor ||
      old.headColor != headColor ||
      old.foodColor != foodColor;
}
