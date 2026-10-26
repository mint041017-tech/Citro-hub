import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import 'game_ui.dart';

/// 2048 —— 1:1 复刻原版 Web：index.html 1745 行区 + styles/citro-games.css 第 7 节
/// 移动端实测（390×844）：棋盘 335.39×335.39、cell 74.09、gap 7、pad 8、tile 圆角 10。
class Game2048Page extends StatefulWidget {
  const Game2048Page({super.key});
  @override
  State<Game2048Page> createState() => _Game2048PageState();
}

class _Tile {
  _Tile(this.id, this.value, this.index);
  final int id;
  int value;
  int index;
  bool pop = false;
  bool spawn = false;
}

class _Game2048PageState extends State<Game2048Page> {
  final math.Random _rnd = math.Random();
  final List<_Tile> _tiles = [];
  int _nextId = 1;
  List<_Tile>? _undoTiles;
  int? _undoScore;
  int _score = 0;
  int _best = 0;
  bool _over = false;
  bool _won = false;
  bool _submitted = false;
  final _progress = ValueNotifier<String>('分数 0');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _best = AppState.instance.localBest('2048');
    _newGame();
  }

  @override
  void dispose() {
    _progress.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 16 格 → 数值（预览/撤销用）
  List<int> get _grid {
    final g = List<int>.filled(16, 0);
    for (final t in _tiles) {
      if (t.index >= 0) g[t.index] = t.value;
    }
    return g;
  }

  void _newGame() {
    _tiles
      ..clear()
      ..addAll(_tilesFromGrid(List.filled(16, 0), animate: false));
    _score = 0;
    _over = false;
    _won = false;
    _submitted = false;
    _undoTiles = null;
    _undoScore = null;
    _spawn();
    _spawn();
    _progress.value = '分数 $_score';
    setState(() {});
    _focus.requestFocus();
  }

  List<_Tile> _tilesFromGrid(List<int> g, {bool animate = true}) {
    final out = <_Tile>[];
    for (var i = 0; i < 16; i++) {
      if (g[i] != 0) out.add(_Tile(_nextId++, g[i], i));
    }
    return out;
  }

  void _spawn() {
    final empty = <int>[];
    final used = {for (final t in _tiles) t.index};
    for (var i = 0; i < 16; i++) {
      if (!used.contains(i)) empty.add(i);
    }
    if (empty.isEmpty) return;
    final i = empty[_rnd.nextInt(empty.length)];
    final t = _Tile(_nextId++, _rnd.nextInt(10) == 0 ? 4 : 2, i)..spawn = true;
    _tiles.add(t);
  }

  bool _move(int dx, int dy) {
    if (_over) return false;
    final beforeTiles = [for (final t in _tiles) _Tile(t.id, t.value, t.index)];
    final beforeScore = _score;
    var moved = false;
    var mergedAny = false;
    final result = List<_Tile?>.filled(16, null);
    final removed = <_Tile>[];
    for (var line = 0; line < 4; line++) {
      final lineTiles = <_Tile>[];
      for (var k = 0; k < 4; k++) {
        final x = dx != 0 ? (dx > 0 ? 3 - k : k) : line;
        final y = dy != 0 ? (dy > 0 ? 3 - k : k) : line;
        for (final t in _tiles) {
          if (t.index == y * 4 + x) lineTiles.add(t);
        }
      }
      final merged = <_Tile>[];
      for (var i = 0; i < lineTiles.length; i++) {
        final cur = lineTiles[i];
        if (i + 1 < lineTiles.length && lineTiles[i + 1].value == cur.value) {
          final next = lineTiles[i + 1];
          cur.value *= 2;
          cur.pop = true;
          _score += cur.value;
          if (cur.value == 2048) _won = true;
          removed.add(next);
          merged.add(cur);
          // 关键修复：贴墙原位合并（如 [2,2] 向左）时 index 没变，
          // 旧实现 moved 仍为 false → 被合并的那块没被移除、棋盘出现
          // 幽灵方块并持续翻倍（用户反馈的「卡死/数据错乱」来源）。
          // 合并本身就改变了棋盘，必须计为有效移动。
          mergedAny = true;
          i++;
        } else {
          merged.add(cur);
        }
      }
      for (var k = 0; k < 4; k++) {
        final x = dx != 0 ? (dx > 0 ? 3 - k : k) : line;
        final y = dy != 0 ? (dy > 0 ? 3 - k : k) : line;
        final idx = y * 4 + x;
        if (k < merged.length) {
          final t = merged[k];
          if (t.index != idx) moved = true;
          t.index = idx;
          result[idx] = t;
        } else {
          result[idx] = null;
        }
      }
    }
    moved = moved || mergedAny;
    if (!moved) return false;
    _tiles.removeWhere(removed.contains);
    _undoTiles = beforeTiles;
    _undoScore = beforeScore;
    // 清掉上一轮的动画标记
    for (final t in _tiles) {
      t.spawn = false;
      t.pop = false;
    }
    _spawn();
    _progress.value = '分数 $_score';
    if (!_canMove()) _over = true;
    if (_score > _best) {
      _best = _score;
      AppState.instance.saveLocalBest('2048', _best);
    }
    if (mergedAny) {
      GameSfx.merge();
    } else {
      GameSfx.move();
    }
    if (_over) {
      GameSfx.lose();
      _submit();
    } else if (_won) {
      GameSfx.win();
      _submit();
    }
    setState(() {});
    return true;
  }

  bool _canMove() {
    final g = _grid;
    for (var i = 0; i < 16; i++) {
      if (g[i] == 0) return true;
      final x = i % 4, y = i ~/ 4;
      if (x < 3 && g[i] == g[i + 1]) return true;
      if (y < 3 && g[i] == g[i + 4]) return true;
    }
    return false;
  }

  void _undo() {
    if (_undoTiles == null) return;
    GameSfx.tap();
    setState(() {
      _tiles
        ..clear()
        ..addAll([for (final t in _undoTiles!) _Tile(t.id, t.value, t.index)]);
      _score = _undoScore ?? _score;
      _undoTiles = null;
      _undoScore = null;
      _over = false;
      _progress.value = '分数 $_score';
    });
  }

  Future<void> _submit() async {
    if (_submitted) return;
    _submitted = true;
    await AppState.instance.submitScore('2048', _score);
  }

  void _key(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft) _move(-1, 0);
    if (key == LogicalKeyboardKey.arrowRight) _move(1, 0);
    if (key == LogicalKeyboardKey.arrowUp) _move(0, -1);
    if (key == LogicalKeyboardKey.arrowDown) _move(0, 1);
    if (key == LogicalKeyboardKey.keyA) _move(-1, 0);
    if (key == LogicalKeyboardKey.keyD) _move(1, 0);
    if (key == LogicalKeyboardKey.keyW) _move(0, -1);
    if (key == LogicalKeyboardKey.keyS) _move(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final dots = <int, ({int value, int index, bool pop, bool spawn})>{};
    for (final t in _tiles) {
      dots[t.id] = (value: t.value, index: t.index, pop: t.pop, spawn: t.spawn);
    }
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is KeyDownEvent) _key(e.logicalKey);
      },
      child: Game2048View(
        score: _score,
        best: _best,
        tiles: dots,
        canUndo: _undoTiles != null,
        overlayTitle: _over ? '游戏结束' : (_won ? '2048！' : null),
        overlayDesc: _over || _won ? '本局得分 $_score' : null,
        onSwipe: (dx, dy) => _move(dx, dy),
        onUndo: _undo,
        onNew: _newGame,
        onRank: () =>
            showGameRank(context, game: '2048', title: '2048', aiSplit: true),
      ),
    );
  }
}

/* ============================================================
   纯视觉层（可在 golden 测试里用固定数据渲染）
   ============================================================ */
class Game2048View extends StatelessWidget {
  const Game2048View({
    super.key,
    required this.score,
    required this.best,
    this.grid = const <int>[],
    this.tiles,
    this.canUndo = false,
    this.overlayTitle,
    this.overlayDesc,
    this.onSwipe,
    this.onUndo,
    this.onNew,
    this.onRank,
  });

  final int score;
  final int best;

  /// 预览用：16 格数值（与 [tiles] 二选一）。
  final List<int> grid;

  /// 运行时：带 id 的方块（支持滑动动画）。
  final Map<int, ({int value, int index, bool pop, bool spawn})>? tiles;

  final bool canUndo;
  final String? overlayTitle;
  final String? overlayDesc;
  final void Function(int dx, int dy)? onSwipe;
  final VoidCallback? onUndo;
  final VoidCallback? onNew;
  final VoidCallback? onRank;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final screenW = media.width;
    final shortDuo = CitroForm.duoInner(media) && media.width > media.height;
    final bs = math.min(
      screenW * 0.86,
      shortDuo ? math.max(260.0, media.height - 326) : 500.0,
    );
    final board = _Board24(
      width: bs,
      grid: grid,
      tiles: tiles,
      overlayTitle: overlayTitle,
      overlayDesc: overlayDesc,
      onRetry: onNew,
    );
    return GameScaffold(
      gameKey: 'g2048',
      title: '2048',
      rankAiSplit: true,
      pills: [
        GameScorePill(label: '分数', value: '$score', bump: score > 0),
        GameScorePill(label: '最高分', value: '$best'),
      ],
      actions: [
        GameActionButton(
          label: '撤销',
          icon: GameIcons.undo,
          enabled: canUndo,
          onTap: onUndo,
        ),
        GameActionButton(
          label: '新游戏',
          primary: true,
          icon: GameIcons.refresh,
          onTap: onNew,
        ),
        GameActionButton(label: '排行榜', icon: GameIcons.trophy, onTap: onRank),
      ],
      board: GestureDetector(
        onPanEnd: onSwipe == null
            ? null
            : (d) {
                final v = d.velocity.pixelsPerSecond;
                if (v.dx.abs() > v.dy.abs()) {
                  onSwipe!(v.dx > 0 ? 1 : -1, 0);
                } else {
                  onSwipe!(0, v.dy > 0 ? 1 : -1);
                }
              },
        child: board,
      ),
    );
  }
}

class _Board24 extends StatelessWidget {
  const _Board24({
    required this.width,
    required this.grid,
    required this.tiles,
    required this.overlayTitle,
    required this.overlayDesc,
    required this.onRetry,
  });

  final double width;
  final List<int> grid;
  final Map<int, ({int value, int index, bool pop, bool spawn})>? tiles;
  final String? overlayTitle;
  final String? overlayDesc;
  final VoidCallback? onRetry;

  static const double pad = 8;
  static const double gap = 7;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cell = (width - 2 - pad * 2 - gap * 3) / 4;
    final children = <Widget>[];
    // 16 个空格子
    for (var i = 0; i < 16; i++) {
      final col = i % 4, row = i ~/ 4;
      children.add(
        Positioned(
          left: 1 + pad + col * (cell + gap),
          top: 1 + pad + row * (cell + gap),
          width: cell,
          height: cell,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.line, width: 1),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x092E2C22),
                  blurRadius: 2,
                  spreadRadius: -1,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // 数字块
    if (tiles != null) {
      for (final e in tiles!.entries) {
        final t = e.value;
        final col = t.index % 4, row = t.index ~/ 4;
        children.add(
          AnimatedPositioned(
            key: ValueKey(e.key),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            left: 1 + pad + col * (cell + gap),
            top: 1 + pad + row * (cell + gap),
            width: cell,
            height: cell,
            child: _Tile24(
              value: t.value,
              cell: cell,
              pop: t.pop,
              spawn: t.spawn,
            ),
          ),
        );
      }
    } else {
      for (var i = 0; i < 16; i++) {
        if (i >= grid.length || grid[i] == 0) continue;
        final col = i % 4, row = i ~/ 4;
        children.add(
          Positioned(
            left: 1 + pad + col * (cell + gap),
            top: 1 + pad + row * (cell + gap),
            width: cell,
            height: cell,
            child: _Tile24(value: grid[i], cell: cell),
          ),
        );
      }
    }
    // 结算浮层
    children.add(
      Positioned.fill(
        child: IgnorePointer(
          ignoring: overlayTitle == null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 260),
            opacity: overlayTitle == null ? 0 : 1,
            child: Container(
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.94),
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    overlayTitle ?? '',
                    style: context.heading(
                      size: 30,
                      color: (overlayTitle ?? '').contains('2048')
                          ? c.accentInk
                          : c.mintInk,
                      height: 1.65,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    overlayDesc ?? '',
                    style: context.body(size: 13, color: c.ink2),
                  ),
                  const SizedBox(height: 10),
                  GameActionButton(
                    label: '再来一局',
                    primary: true,
                    onTap: onRetry,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      width: width,
      height: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 底板
          Positioned(
            left: 0,
            top: 0,
            width: width,
            height: width,
            child: CssShadowLayer(
              radius: 14,
              shadows: const [
                CssShadowSpec(
                  color: Color(0x8C5A4A2C),
                  offset: Offset(0, 16),
                  blur: 38,
                  spread: -22,
                ),
                CssShadowSpec(
                  color: Color(0x0F5A4A2C),
                  offset: Offset(0, 2),
                  blur: 6,
                ),
              ],
              child: SizedBox(
                width: width,
                height: width,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: c.dark
                          ? [c.surface, c.surface]
                          : const [Color(0xFFFFFDF8), Color(0xFFFFFDF8)],
                    ),
                    border: Border.all(
                      color: c.dark ? c.line2 : const Color(0xE6FFF8EA),
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
          // 纸胶带（web .g2048-board::before：中心对齐、上移 11px）
          Positioned(left: width / 2 - 41, top: -11, child: const GameTape()),
          ...children,
        ],
      ),
    );
  }
}

class _Tile24 extends StatelessWidget {
  const _Tile24({
    required this.value,
    required this.cell,
    this.pop = false,
    this.spawn = false,
  });

  final int value;
  final double cell;
  final bool pop;
  final bool spawn;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final style = _tileStyle(context, value);
    final fs = switch (value) {
      >= 1024 => cell * 0.27,
      >= 512 => cell * 0.32,
      >= 128 => cell * 0.34,
      _ => cell * 0.42,
    };
    Widget tile = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.$1,
        gradient: style.$3,
        borderRadius: BorderRadius.circular(10),
        // 深色下给同色阶相邻方块留一圈浅描边，边界更清楚。
        border: c.dark
            ? Border.all(color: const Color(0x1AFFFFFF))
            : (style.$4 ? null : Border.all(color: const Color(0x0D2E2C22))),
        boxShadow: style.$5
            ? const [
                BoxShadow(
                  color: Color(0x1A58502A),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Text(
        '$value',
        style: TextStyle(
          fontFamily: AppFonts.kalam,
          fontFamilyFallback: AppFonts.fallback,
          fontSize: fs,
          fontWeight: FontWeight.w400,
          height: 1.65,
          color: style.$2,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
    );
    if (spawn) {
      // web .g-tile.new：appear 200ms（scale 0.4→1 + 淡入）
      tile = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        builder: (ctx, s, child) => Opacity(
          opacity: (0.4 + 0.6 * s).clamp(0, 1),
          child: Transform.scale(scale: 0.4 + 0.6 * s, child: child),
        ),
        child: tile,
      );
    } else if (pop) {
      // web .g-tile.merged：pop 220ms（scale 1→1.18→1 的脉冲）。
      // 旧实现是 Tween(1.0→1.0) 的占位，等于没有动画（用户反馈）。
      tile = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.linear,
        builder: (ctx, s, child) => Transform.scale(
          scale: 1 + 0.18 * math.sin(math.pi * s.clamp(0.0, 1.0)),
          child: child,
        ),
        child: tile,
      );
    }
    return tile;
  }

  (Color, Color, Gradient?, bool, bool) _tileStyle(
    BuildContext context,
    int v,
  ) {
    final c = context.c;
    // 亮色：色阶派生自 --accent（#F2A43C）与 --surface（#FBF7EC）。
    // 2026-10-23：2 / 4 原来都贴着纸底色、肉眼难分（用户反馈）。整条低段
    // 色阶顺次微调：2 压深成暖灰、4 提成明显金调、8/16 顺次加深一档，
    // 保证 2 < 4 < 8 < 16 层次依然单调递增。
    if (!c.dark) {
      return switch (v) {
        2 => (
          const Color(0xFFEFE7D8),
          const Color(0xFF6B5F4C),
          null,
          true,
          true,
        ),
        4 => (
          const Color(0xFFF6DCA6),
          const Color(0xFF8F5A10),
          null,
          true,
          true,
        ),
        8 => (
          const Color(0xFFF3C98C),
          const Color(0xFF5C3A1E),
          null,
          true,
          true,
        ),
        16 => (
          const Color(0xFFF0B877),
          const Color(0xFF4A2A10),
          null,
          true,
          true,
        ),
        32 => (
          const Color(0xFFF2A85F),
          const Color(0xFF101012),
          null,
          true,
          true,
        ),
        64 => (c.accent, const Color(0xFF2E2C22), null, true, false),
        128 => (c.accent2, const Color(0xFFFFF8E8), null, true, true),
        256 => (
          const Color(0xFFBB7720),
          const Color(0xFFFFF8E8),
          null,
          true,
          false,
        ),
        512 => (
          const Color(0xFF9B6620),
          const Color(0xFFF2EBDA),
          null,
          true,
          false,
        ),
        1024 => (
          const Color(0xFF8FC7A0),
          const Color(0xFFFBFFF8),
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8FC7A0), Color(0xFF9DB37A), Color(0xFF2C6B50)],
            stops: [0.0, 0.55, 1.0],
          ),
          true,
          false,
        ),
        2048 => (
          const Color(0xFF9DB37A),
          const Color(0xFFEAF7EF),
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9DB37A), Color(0xFF2C6B50), Color(0xFF4A5533)],
            stops: [0.0, 0.58, 1.0],
          ),
          true,
          false,
        ),
        _ => (
          const Color(0xFF2E2C22),
          const Color(0xFFC9D3B2),
          const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2E2C22), Color(0xFF101012)],
          ),
          true,
          false,
        ),
      };
    }
    // 深色：低段用冷暖交替的色相拉开层次，高段走金→薄荷；128/256 不再同色。
    return switch (v) {
      2 => (
        const Color(0xFF2F2F38),
        const Color(0xFFD8D2C4),
        null,
        false,
        false,
      ),
      4 => (
        const Color(0xFF3F4350),
        const Color(0xFFE6E9F2),
        null,
        false,
        false,
      ),
      8 => (
        const Color(0xFF4A4430),
        const Color(0xFFEFE2CC),
        null,
        false,
        false,
      ),
      16 => (
        const Color(0xFF5A3E2C),
        const Color(0xFFF5E9D2),
        null,
        false,
        false,
      ),
      32 => (
        const Color(0xFF7A4A1F),
        const Color(0xFFFFE9CC),
        null,
        false,
        false,
      ),
      64 => (
        const Color(0xFF9C5A12),
        const Color(0xFFFFF4E4),
        null,
        false,
        false,
      ),
      128 => (c.accent2, const Color(0xFF101012), null, false, false),
      256 => (c.accent, const Color(0xFF101012), null, false, false),
      512 => (c.accentLt, const Color(0xFF101012), null, false, false),
      1024 => (
        const Color(0xFF8FC7A0),
        const Color(0xFF101012),
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC9D3B2), Color(0xFF9DB37A), Color(0xFF7F9459)],
        ),
        true,
        false,
      ),
      2048 => (
        const Color(0xFF9DB37A),
        const Color(0xFFEAF7EF),
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9DB37A), Color(0xFF7F9459), Color(0xFF4A5533)],
        ),
        true,
        false,
      ),
      _ => (
        const Color(0xFF2A2A32),
        c.mint,
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A32), Color(0xFF1A1A20)],
        ),
        true,
        false,
      ),
    };
  }
}
