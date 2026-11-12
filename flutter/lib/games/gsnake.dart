import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/game_sfx.dart';
import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'game_common.dart';
import 'game_identity.dart';
import 'game_ui.dart';

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
      above: [
        GameSegTabs<String>(
          items: _diffItems,
          value: diff,
          onChanged: (d) => onDiff?.call(d),
        ),
      ],
      pills: [
        GameScorePill(label: '分数', value: '$score', bump: score > 0),
        GameScorePill(label: '最高分', value: best > 0 ? '$best' : '0'),
      ],
      actions: [
        GameActionButton(
          label: '新游戏',
          icon: GameIcons.reset,
          primary: true,
          onTap: onNewGame,
        ),
        GameActionButton(
          label: '排行榜',
          icon: GameIcons.trophySimple,
          onTap: onRank,
        ),
      ],
      boardGap: 0,
      // 棋盘尺寸只吃内容区约束：竖屏扣除方向盘与键盘提示，横屏 / 平板与
      // 方向盘并排，不再读 MediaQuery（按屏幕宽算在横屏必然裁切）。
      board: LayoutBuilder(builder: (context, cons) {
        final w = cons.maxWidth.isFinite ? cons.maxWidth : 360.0;
        final h = cons.maxHeight.isFinite ? cons.maxHeight : double.infinity;
        final wide = w >= 600;
        final keyboard = keyboardMode && !kIsWeb;
        const dpad = 240.0;
        final hint = (keyboard || kIsWeb) ? 26.0 : 0.0;
        var maxW = w;
        var maxH = h;
        // 竖屏棋盘按内容宽算：方向盘在棋盘下方，整页可滚，不必给它预留高度
        // （棋盘区在 SingleChildScrollView 里，maxHeight 恒为无限，扣了反而把
        // 棋盘压到 148px，比方向盘还小）。横屏 / 平板与方向盘并排时才扣宽度。
        if (keyboard) {
          if (h.isFinite) maxH = h - hint;
        } else if (wide) {
          maxW = w - dpad - 24;
          if (kIsWeb && h.isFinite) maxH = h - hint;
        }
        final boardW = math.max(140.0, math.min(520.0, math.min(maxW, maxH)));
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (keyboard) ...[
              _board(context, boardW),
              const SizedBox(height: 8),
              _hint(context),
            ] else if (wide)
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
              _hint(context),
            ],
          ],
        );
      }),
    );
  }

  /// 键盘提示：保持在棋盘外，用身份色读出。
  Widget _hint(BuildContext context) {
    final identity = GameIdentityScope.of(context);
    return Text(
      'WASD / 方向键控制',
      style: context.body(size: 11, color: identity.primaryInk),
    );
  }

  Widget _board(BuildContext context, double boardW) {
    final identity = GameIdentityScope.of(context);
    return Center(
      child: Container(
        width: boardW,
        height: boardW,
        decoration: BoxDecoration(
          // 底板：主题卡面 + 身份色描边，与 2048 底板同一套。
          color: context.c.surface,
          borderRadius: BorderRadius.circular(CitroColors.radii.card),
          border: Border.all(color: identity.primary.withAlpha(60)),
          boxShadow: CitroColors.shadows.card(context.c),
        ),
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
                    // 极浅静态网格：identity.soft 低透明叠在主题卡面上，
                    // 只交代格子位置，不跟蛇身抢视线。
                    line: identity.soft.withAlpha(context.c.dark ? 46 : 180),
                    // 暗色底板是深面，身份色实底要提亮一档才压得住。
                    body: context.c.dark ? identity.onDark() : identity.primary,
                    deep: identity.deep,
                    foodColor: context.c.dark
                        ? identity.onDark()
                        : (identity.secondary ?? identity.deep),
                    paper: GameIdentity.paper,
                    // (棋盘宽 - 左右边框2 - 上下左右留白12 - 16个1px间隙) / 17
                    // 370 宽时 = 20，与 web 一致；窄屏时等比缩小保证两侧对称
                    // （最小 6：保证 17 格 + 留白仍落在最小棋盘里）
                    cell: math.max(6.0, (boardW - 30) / 17),
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
    final identity = GameIdentityScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.96),
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '游戏结束',
            style: context.heading(size: CitroType.subtitle, color: c.ink),
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
                    style: TextStyle(
                      color: identity.primaryInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' · 蛇长 ${snake.length}'),
                ],
              ),
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: c.ink2),
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
    final identity = GameIdentityScope.of(context);
    const cell = 74.6719;
    const step = cell + 8;
    const size = step * 3 - 8; // 240.0157
    Widget btn(String path, int col, int row, int dx, int dy) {
      return Positioned(
        left: col * step,
        top: row * step,
        width: cell,
        height: cell,
        child: GameHover(
          enabled: onTurn != null,
          scale: 1.04,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTurn == null ? null : () => onTurn!(dx, dy),
            child: Container(
              decoration: BoxDecoration(
                color: identity.soft,
                shape: BoxShape.circle,
                border: Border.all(color: identity.primary.withAlpha(90)),
              ),
              child: Center(
                child: AppIcon(
                  '<svg viewBox="0 0 24 24" fill="#000000">$path</svg>',
                  size: 26,
                  color: identity.primaryInk,
                ),
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

/// .gsnake-board：17×17 网格棋盘。
///
/// v2：底座是带身份色的容器，棋盘里只画极浅静态网格线；蛇身是一条圆角
/// 折线（identity.primary），头部补眼睛 / 舌头（identity.deep），食物用
/// identity.secondary ?? identity.deep。不再用整屏 CustomPaint 方格当底座。
class _SnakeBoardPainter extends CustomPainter {
  _SnakeBoardPainter({
    required this.snake,
    required this.food,
    required this.grid,
    required this.line,
    required this.body,
    required this.deep,
    required this.foodColor,
    required this.paper,
    this.cell = 20,
  });

  final List<Point> snake;
  final Point food;
  final int grid;

  /// 网格线。
  final Color line;

  /// 蛇身（identity.primary）。
  final Color body;

  /// 头部细节（identity.deep）。
  final Color deep;

  /// 食物（identity.secondary ?? identity.deep）。
  final Color foodColor;

  /// 眼睛白（identity.paper）。
  final Color paper;

  /// 格子边长。v1.6.0：随棋盘宽度缩放（旧实现固定 20px，内容区 < 370 的
  /// 机型上棋盘被右侧裁掉一截，看起来没居中）。
  final double cell;

  static const double _pad = 6; // board padding
  static const double _gap = 1;

  @override
  void paint(Canvas canvas, Size size) {
    // 底板圆角由容器画，画布内容（网格 / 蛇）收在同一个圆角里。
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(CitroColors.radii.card),
      ),
    );
    final origin = 1 + _pad;
    final step = cell + _gap;
    double center(int i) => origin + i * step + cell / 2;

    // 静态网格：只画线，不画整屏方格。
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var i = 0; i <= grid; i++) {
      final p = origin + i * step - (i == 0 ? 0 : _gap);
      canvas.drawLine(
        Offset(p, origin),
        Offset(p, size.height - origin),
        linePaint,
      );
      canvas.drawLine(
        Offset(origin, p),
        Offset(size.width - origin, p),
        linePaint,
      );
    }

    if (food.x >= 0 && food.x < grid && food.y >= 0 && food.y < grid) {
      canvas.drawCircle(
        Offset(center(food.x), center(food.y)),
        cell * 0.40,
        Paint()..color = foodColor,
      );
    }

    if (snake.isEmpty) return;

    // 蛇身：圆角折线穿过每个格子中心。
    final path = Path()
      ..moveTo(center(snake.first.x), center(snake.first.y));
    for (var i = 1; i < snake.length; i++) {
      path.lineTo(center(snake[i].x), center(snake[i].y));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = body
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.66
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 头部：朝向第二格的方向。
    final head = snake.first;
    final hx = center(head.x);
    final hy = center(head.y);
    var dx = 1.0, dy = 0.0;
    if (snake.length > 1) {
      dx = (head.x - snake[1].x).toDouble();
      dy = (head.y - snake[1].y).toDouble();
    }
    canvas.drawCircle(Offset(hx, hy), cell * 0.50, Paint()..color = body);

    // 眼睛：纸白底 + 深墨瞳。
    final px = -dy, py = dx;
    for (final s in const [1.0, -1.0]) {
      final ex = hx + px * cell * 0.20 * s + dx * cell * 0.12;
      final ey = hy + py * cell * 0.20 * s + dy * cell * 0.12;
      canvas.drawCircle(Offset(ex, ey), cell * 0.13, Paint()..color = paper);
      canvas.drawCircle(
        Offset(ex + dx * cell * 0.05, ey + dy * cell * 0.05),
        cell * 0.06,
        Paint()..color = deep,
      );
    }

    // 舌头：朝向前方的分叉细线。
    final tongue = Paint()
      ..color = deep
      ..strokeWidth = cell * 0.09
      ..strokeCap = StrokeCap.round;
    final tx0 = hx + dx * cell * 0.44;
    final ty0 = hy + dy * cell * 0.44;
    final tx1 = hx + dx * cell * 0.80;
    final ty1 = hy + dy * cell * 0.80;
    canvas.drawLine(Offset(tx0, ty0), Offset(tx1, ty1), tongue);
    final angle = math.atan2(dy, dx);
    for (final s in const [1.0, -1.0]) {
      final a = angle + s * 0.55;
      canvas.drawLine(
        Offset(tx1, ty1),
        Offset(
          tx1 + math.cos(a) * cell * 0.22,
          ty1 + math.sin(a) * cell * 0.22,
        ),
        tongue,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnakeBoardPainter old) =>
      old.snake != snake ||
      old.food != food ||
      old.grid != grid ||
      old.line != line ||
      old.body != body ||
      old.deep != deep ||
      old.foodColor != foodColor ||
      old.paper != paper ||
      old.cell != cell;
}
