import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/browser_effects.dart';
import 'game_identity.dart';
import 'game_ui.dart';

/// 记忆卡牌（web `#gmemPage`：index.html:8109-8143 + gmem JS 18096-18239）。
///
/// 视觉基准 `_tmp/ref/games/gmem-m-l.png`（390×844 light）实测 px：
/// 难度条 274.672×41（padding 4 / gap 2 / 按钮 86.89×31）
/// → 棋盘 wrap 360.797×486.375（border 1，board margin-top 16）
/// → board 358.797×468.375（4 列 82.19 / 4 行 109.59，gap 10，卡面 3:4）。
/// 版式 v2：难度条在棋盘上方，步数/用时/最佳进顶栏数据看板，重开/排行榜在棋盘下方。
class GameMemoryPage extends StatefulWidget {
  const GameMemoryPage({super.key});

  @override
  State<GameMemoryPage> createState() => _GameMemoryPageState();
}

/// 卡牌视觉数据（View 只读，不含可变状态）。
typedef MemoryCardData = ({int pair, String char, bool open, bool matched});

class _MemoryCard {
  final int pair;
  final String char;
  bool open = false;
  bool matched = false;
  _MemoryCard(this.pair, this.char);
}

class _DiffSpec {
  const _DiffSpec(this.label, this.cols, this.rows, this.pairs);
  final String label;
  final int cols;
  final int rows;
  final int pairs;
}

const _diffSpecs = <String, _DiffSpec>{
  'easy': _DiffSpec('简单 4×3', 4, 3, 6),
  'std': _DiffSpec('标准 4×4', 4, 4, 8),
  'hard': _DiffSpec('困难 5×4', 5, 4, 10),
};
const _chars = '福禄寿喜梅兰竹菊松鹤龙凤';

class _GameMemoryPageState extends State<GameMemoryPage> {
  String diff = 'std';
  List<_MemoryCard> deck = [];
  List<int> open = [];
  int matched = 0;
  int moves = 0;
  int seconds = 0;
  bool lock = false;
  bool over = false;
  bool submitted = false;
  Timer? timer;
  Timer? closeTimer;
  bool started = false;
  final _progress = ValueNotifier<String>('步数 0');

  _DiffSpec get _meta => _diffSpecs[diff]!;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  @override
  void dispose() {
    timer?.cancel();
    closeTimer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _newGame() {
    timer?.cancel();
    closeTimer?.cancel();
    final meta = _meta;
    final cards = <_MemoryCard>[];
    for (var i = 0; i < meta.pairs; i++) {
      cards.add(_MemoryCard(i, _chars[i]));
      cards.add(_MemoryCard(i, _chars[i]));
    }
    cards.shuffle(math.Random());
    setState(() {
      deck = cards;
      open = [];
      matched = 0;
      moves = 0;
      seconds = 0;
      lock = false;
      over = false;
      submitted = false;
      started = false;
    });
    _progress.value = '步数 0';
  }

  void _start() {
    if (started) return;
    started = true;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || over) return;
      setState(() => seconds++);
    });
  }

  void _flip(int i) {
    if (lock || over) return;
    final card = deck[i];
    if (card.open || card.matched) return;
    _start();
    GameSfx.flip();
    setState(() {
      card.open = true;
      open.add(i);
    });
    if (open.length < 2) return;
    moves++;
    _progress.value = '步数 $moves';
    final a = deck[open[0]], b = deck[open[1]];
    if (a.pair == b.pair) {
      GameSfx.match();
      setState(() {
        a.matched = true;
        b.matched = true;
        matched++;
        open.clear();
      });
      if (matched == _meta.pairs) _win();
    } else {
      GameSfx.miss();
      lock = true;
      closeTimer = Timer(const Duration(milliseconds: 760), () {
        if (!mounted) return;
        setState(() {
          a.open = false;
          b.open = false;
          open.clear();
          lock = false;
        });
      });
    }
  }

  int get _score {
    final pairs = _meta.pairs;
    final eff = pairs * 2 / math.max(moves, pairs);
    return math.max(0, (eff * 10000).round() - seconds * 6);
  }

  Future<void> _win() async {
    over = true;
    timer?.cancel();
    GameSfx.win();
    final score = _score;
    final app = context.app;
    await app.saveLocalBest('memory:$diff', score);
    if (!submitted) {
      submitted = true;
      await app.submitScore('memory:$diff', score);
    }
    if (mounted) setState(() {});
  }

  void _setDiff(String d) {
    if (d == diff) return;
    setState(() => diff = d);
    _newGame();
  }

  void _openRank() {
    showGameRank(
      context,
      game: 'memory',
      title: '记忆卡牌',
      difficulties: const [('easy', '简单'), ('std', '标准'), ('hard', '困难')],
      initial: diff,
    );
  }

  @override
  Widget build(BuildContext context) {
    final best = context.app.localBest('memory:$diff');
    return GameMemoryView(
      diff: diff,
      cards: [
        for (final c in deck)
          (pair: c.pair, char: c.char, open: c.open, matched: c.matched),
      ],
      moves: moves,
      seconds: seconds,
      best: best,
      over: over,
      score: over ? _score : 0,
      liveProgress: _progress,
      onDiff: _setDiff,
      onFlip: _flip,
      onNew: _newGame,
      onRank: _openRank,
    );
  }
}

/// 纯视觉层（golden 测试用固定数据渲染，不触发任何玩法副作用）。
class GameMemoryView extends StatelessWidget {
  const GameMemoryView({
    super.key,
    this.diff = 'std',
    this.cards = const <MemoryCardData>[],
    this.moves = 0,
    this.seconds = 0,
    this.best = 0,
    this.over = false,
    this.score = 0,
    this.liveProgress,
    this.onDiff,
    this.onFlip,
    this.onNew,
    this.onRank,
  });

  final String diff;
  final List<MemoryCardData> cards;
  final int moves;
  final int seconds;
  final int best;
  final bool over;
  final int score;
  final ValueNotifier<String>? liveProgress;
  final ValueChanged<String>? onDiff;
  final ValueChanged<int>? onFlip;
  final VoidCallback? onNew;
  final VoidCallback? onRank;

  @override
  Widget build(BuildContext context) {
    final meta = _diffSpecs[diff] ?? _diffSpecs['std']!;
    return GameScaffold(
      gameKey: 'gmem',
      title: '记忆卡牌',
      liveProgress: liveProgress,
      liveInScroll: true,
      rankDifficulties: const [('easy', '简单'), ('std', '标准'), ('hard', '困难')],
      rankInitial: diff,
      above: [
        GameSegTabs<String>(
          items: const [
            ('easy', '简单 4×3'),
            ('std', '标准 4×4'),
            ('hard', '困难 5×4'),
          ],
          value: diff,
          onChanged: (d) => onDiff?.call(d),
        ),
      ],
      pills: [
        GameScorePill(label: '步数', value: '$moves'),
        GameScorePill(label: '用时', value: '${seconds}s'),
        GameScorePill(label: '最佳', value: best > 0 ? '$best' : '--'),
      ],
      actions: [
        GameActionButton(
          label: '重新开始',
          icon: GameIcons.refresh,
          primary: true,
          onTap: onNew,
        ),
        GameActionButton(label: '排行榜', icon: GameIcons.trophy, onTap: onRank),
      ],
      // 棋盘尺寸只吃内容区约束：竖屏约 0.92 内容宽，横屏用侧栏剩余宽度，
      // 高度再按舞台剩余收一档，保证任何比例下整块棋盘可见（不裁切）。
      board: LayoutBuilder(
        builder: (context, cons) {
          final w = cons.maxWidth.isFinite ? cons.maxWidth : 358.0;
          final h = cons.maxHeight.isFinite ? cons.maxHeight : 480.0;
          final portrait = h >= w;
          final maxW = portrait ? math.min(w * 0.92, 480.0) : math.min(w, 480.0);
          return _MemoryBoard(
            cards: cards,
            cols: meta.cols,
            rows: meta.rows,
            maxWidth: maxW,
            maxHeight: math.max(120.0, h),
            over: over,
            score: score,
            moves: moves,
            seconds: seconds,
            onFlip: onFlip,
            onNew: onNew,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 棋盘：纸卡 wrap（含胶带）+ 3:4 卡面网格
// ---------------------------------------------------------------------------

class _MemoryBoard extends StatelessWidget {
  const _MemoryBoard({
    required this.cards,
    required this.cols,
    required this.rows,
    required this.maxWidth,
    required this.maxHeight,
    required this.over,
    required this.score,
    required this.moves,
    required this.seconds,
    this.onFlip,
    this.onNew,
  });

  final List<MemoryCardData> cards;
  final int cols;
  final int rows;

  /// 内容区给棋盘的最大宽 / 高（来自 LayoutBuilder，不读 MediaQuery）。
  final double maxWidth;
  final double maxHeight;
  final bool over;
  final int score;
  final int moves;
  final int seconds;
  final ValueChanged<int>? onFlip;
  final VoidCallback? onNew;

  static const _gap = 10.0;

  /// 纸板内边距：卡牌左右各收 9px（手机两侧贴边的用户反馈），上下各 17px。
  static const _sideInset = 9.0;
  static const _boardSide = 17.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    // 卡面保持 3:4；宽度优先吃满内容区，高度不够时（横屏 / 矮屏）按高度
    // 反推卡宽，整块棋盘始终完整落在舞台里。
    final maxCardW = (maxWidth - _sideInset * 2 - _gap * (cols - 1)) / cols;
    final maxCardH = (maxHeight - _boardSide * 2 - _gap * (rows - 1)) / rows;
    var cardW = maxCardW;
    var cardH = cardW * 4 / 3 - 0.01;
    if (cardH > maxCardH) {
      cardH = math.max(24.0, maxCardH);
      cardW = cardH * 3 / 4;
    }
    final pitchX = cardW + _gap;
    final pitchY = cardH + _gap;
    final boardW = cardW * cols + _gap * (cols - 1) + _sideInset * 2;
    final boardH = cardH * rows + _gap * (rows - 1);
    final wrapW = boardW + 2;
    // v1.6.0：底排卡牌距纸卡下缘只有 1px（wrapH = boardH + 18，而顶部留
    // 17px），用户反馈下部太贴边。改为与顶部对称的 17px。
    final wrapH = boardH + _boardSide * 2;

    final tiles = <Widget>[];
    for (var r = 0; r < rows; r++) {
      for (var col = 0; col < cols; col++) {
        final i = r * cols + col;
        final x = _sideInset + col * pitchX;
        final y = _boardSide + r * pitchY;
        tiles.add(
          Positioned(
            left: x,
            top: y,
            width: cardW,
            height: cardH,
            child: i < cards.length
                ? _MemoryTile(
                    key: ValueKey<String>('card-$i'),
                    data: cards[i],
                    onTap: onFlip == null ? null : () => onFlip!(i),
                  )
                : const SizedBox.shrink(),
          ),
        );
      }
    }

    return SizedBox(
      width: wrapW,
      height: wrapH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // 纸板底：主题面上叠一层极低透明的主色，不铺死色。
                color: Color.lerp(c.surface, identity.primary, 0.12),
                borderRadius: BorderRadius.circular(CitroColors.radii.card),
                border: Border.all(color: identity.primary.withAlpha(60)),
                boxShadow: CitroColors.shadows.card(c),
              ),
              child: SizedBox(width: wrapW, height: wrapH),
            ),
          ),
          ...tiles,
          if (over)
            Positioned(
              left: 1,
              top: 1,
              right: 1,
              bottom: 1,
              child: _MemoryOverlay(
                score: score,
                moves: moves,
                seconds: seconds,
                onRetry: onNew,
              ),
            ),
        ],
      ),
    );
  }
}

class _MemoryOverlay extends StatelessWidget {
  const _MemoryOverlay({
    required this.score,
    required this.moves,
    required this.seconds,
    this.onRetry,
  });

  final int score;
  final int moves;
  final int seconds;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(CitroColors.radii.card),
      child: CitroBackdropBlur(
        sigma: 6,
        child: Container(
          color: c.surface.withValues(alpha: 0.94),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '配对完成！',
                style: context.heading(
                  size: CitroType.heading,
                  color: identity.primaryInk,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '用时 $seconds 秒 · 步数 $moves · 得分 $score',
                style: context.body(size: CitroType.meta, color: c.ink2),
              ),
              const SizedBox(height: 10),
              GameActionButton(label: '再来一局', primary: true, onTap: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单张卡牌：320ms 绕 Y 翻转（web 原版 500ms，节奏统一到 CitroMotion）。
class _MemoryTile extends StatefulWidget {
  const _MemoryTile({super.key, required this.data, this.onTap});

  final MemoryCardData data;
  final VoidCallback? onTap;

  @override
  State<_MemoryTile> createState() => _MemoryTileState();
}

class _MemoryTileState extends State<_MemoryTile>
    with SingleTickerProviderStateMixin {
  static const _flip = Duration(milliseconds: 320);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _flip,
    value: widget.data.open || widget.data.matched ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _MemoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = (widget.data.open || widget.data.matched) ? 1.0 : 0.0;
    if ((_ctrl.value - target).abs() > 0.0001) {
      _ctrl.animateTo(
        target,
        duration: CitroMotion.guard(context, _flip),
        curve: CitroMotion.curveFor(context, CitroMotion.easeOut),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameHover(
      enabled: widget.onTap != null,
      lift: 2,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final angle = _ctrl.value * math.pi;
            final front = angle > math.pi / 2;
            final m = Matrix4.identity()..setEntry(3, 2, 1 / 700);
            m.rotateY(angle + (front ? math.pi : 0));
            return Transform(
              alignment: Alignment.center,
              transform: m,
              child: front
                  ? _CardFront(
                      char: widget.data.char,
                      matched: widget.data.matched,
                    )
                  : const _CardBack(),
            );
          },
        ),
      ),
    );
  }
}

/// 卡背：身份浅色端（identity.soft）+ 主色斜纹，文字用深色端。
class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    final radius = BorderRadius.circular(CitroColors.radii.small);
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: identity.soft,
          borderRadius: radius,
          boxShadow: CitroColors.shadows.sm(c),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: CustomPaint(
            painter: _CardStripePainter(color: identity.primary.withAlpha(72)),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'CITRO',
                    style: context.hand(
                      size: CitroType.micro,
                      weight: CitroType.strong,
                      color: identity.deep,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '橘',
                    style: context.heading(
                      size: CitroType.titleLg,
                      color: identity.deep,
                    ),
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

/// 45° 斜纹：卡背主色条纹，极低透明叠在 identity.soft 上。
class _CardStripePainter extends CustomPainter {
  const _CardStripePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(CitroColors.radii.small),
      ),
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const gap = 9.0;
    for (var d = -size.height; d < size.width + size.height; d += gap) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CardStripePainter old) => old.color != color;
}

/// 卡正面：纸白卡（identity.paper）+ 主色可读深墨汉字；
/// 配成后主色描边 + 轻放大。
class _CardFront extends StatelessWidget {
  const _CardFront({required this.char, required this.matched});

  final String char;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final identity = GameIdentityScope.of(context);
    return SizedBox.expand(
      child: AnimatedScale(
        scale: matched ? 1.05 : 1,
        duration: CitroMotion.size,
        curve: CitroMotion.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: GameIdentity.paper,
            borderRadius: BorderRadius.circular(CitroColors.radii.small),
            border: Border.all(
              color: matched ? identity.primary : identity.deep.withAlpha(70),
              width: matched ? 1.8 : 1,
            ),
            boxShadow: CitroColors.shadows.sm(c),
          ),
          alignment: Alignment.center,
          child: Text(
            char,
            style: context.heading(
              size: CitroType.display,
              color: matched ? identity.primary : identity.primaryInk,
            ),
          ),
        ),
      ),
    );
  }
}
