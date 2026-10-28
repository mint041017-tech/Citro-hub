import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/browser_effects.dart';
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
    final boardW = math.min(MediaQuery.sizeOf(context).width * 0.92, 480.0);
    return GameScaffold(
      gameKey: 'gmem',
      title: '记忆卡牌',
      liveProgress: liveProgress,
      liveInScroll: true,
      rankDifficulties: const [('easy', '简单'), ('std', '标准'), ('hard', '困难')],
      rankInitial: diff,
      above: [_DiffTabs(value: diff, onChanged: onDiff)],
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
      board: _MemoryBoard(
        cards: cards,
        cols: meta.cols,
        rows: meta.rows,
        boardW: boardW,
        over: over,
        score: score,
        moves: moves,
        seconds: seconds,
        onFlip: onFlip,
        onNew: onNew,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 难度分段器：棋盘上方
// ---------------------------------------------------------------------------

/// 难度分段器（web .gmem-diff：274.672×41 / padding 4 / gap 2 / 按钮 86.89×31）。
class _DiffTabs extends StatelessWidget {
  const _DiffTabs({required this.value, this.onChanged});

  final String value;
  final ValueChanged<String>? onChanged;

  static const _tabW = 86.8906;
  static const _tabH = 31.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final entries = _diffSpecs.entries.toList();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            _tab(entries[i].key, entries[i].value.label),
          ],
        ],
      ),
    );
  }

  Widget _tab(String key, String label) {
    final on = key == value;
    return GameHover(
      enabled: onChanged != null,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(key),
        child: Container(
          width: _tabW,
          height: _tabH,
          alignment: Alignment.center,
          decoration: on
              ? const BoxDecoration(
                  color: Color(0xFFF2A43C),
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x66FE923B),
                      offset: Offset(0, 4),
                      blurRadius: 14,
                    ),
                  ],
                )
              : null,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 19 / 12,
              letterSpacing: 0.2,
              color: on ? const Color(0xFF2E2C22) : const Color(0xFF4E4A40),
            ),
          ),
        ),
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
    required this.boardW,
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
  final double boardW;
  final bool over;
  final int score;
  final int moves;
  final int seconds;
  final ValueChanged<int>? onFlip;
  final VoidCallback? onNew;

  static const _gap = 10.0;

  // 版面绝对坐标（390 宽、844 高的 web 页面实测值）。
  // Chrome 会把布局里的圆角矩形边框四舍五入到整数设备像素（pixel snapping），
  // 所以这里按绝对坐标 snap 后再放每个卡位，边框/内环才不会出现 1px 灰边。
  static const _wrapAbsLeft = 14.6;
  static const _wrapAbsTop = 318.303;
  static const _boardAbsLeft = 15.6;
  static const _boardAbsTop = 335.303;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // 2026-10-23：web 原版卡牌左右直接顶到纸卡内缘（0 内边距），手机上两侧
    // 卡面与游戏区边界贴得过近（用户反馈）。这里给左右各收进 9px，
    // 卡片整体按剩余宽度重排，上下边距保持原样。
    const sideInset = 9.0;
    final cardW = (boardW - sideInset * 2 - _gap * (cols - 1)) / cols;
    // web 上卡片行高来自 grid 的 3:4 轨道（109.594），这里留 0.01 余量避免
    // 第 3 行 574.5 被 round 到 575（Chrome 是 574）。
    final cardH = cardW * 4 / 3 - 0.01;
    final pitchX = cardW + _gap;
    final pitchY = cardH + _gap;
    final boardH = cardH * rows + _gap * (rows - 1);
    final wrapW = boardW + 2;
    // v1.6.0：底排卡牌距纸卡下缘只有 1px（wrapH = boardH + 18，而顶部留
    // 17px），用户反馈下部太贴边。改为与顶部对称的 17px。
    final wrapH = boardH + 34;

    final tiles = <Widget>[];
    for (var r = 0; r < rows; r++) {
      for (var col = 0; col < cols; col++) {
        final i = r * cols + col;
        final x0 = (_boardAbsLeft + sideInset + col * pitchX).roundToDouble();
        final x1 = (_boardAbsLeft + sideInset + col * pitchX + cardW)
            .roundToDouble();
        final y0 = (_boardAbsTop + r * pitchY).roundToDouble();
        final y1 = (_boardAbsTop + r * pitchY + cardH).roundToDouble();
        tiles.add(
          Positioned(
            left: x0 - _wrapAbsLeft,
            top: y0 - _wrapAbsTop,
            width: x1 - x0,
            height: y1 - y0,
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
            child: CssShadowLayer(
              radius: 14,
              shadows: const [
                CssShadowSpec(
                  color: Color(0x0E5A4A2C),
                  offset: Offset(0, 1),
                  blur: 2,
                ),
                CssShadowSpec(
                  color: Color(0x4D5A4A2C),
                  offset: Offset(0, 8),
                  blur: 20,
                  spread: -12,
                ),
              ],
              child: SizedBox(
                width: wrapW,
                height: wrapH,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line),
                  ),
                ),
              ),
            ),
          ),
          // 胶带：web ::before top -11、left 50% + translateX(-50%)，z-index 7 盖在纸卡上
          Positioned(
            top: -11,
            left: (wrapW - 82) / 2,
            child: const IgnorePointer(child: GameTape()),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: CitroBackdropBlur(
        sigma: 6,
        child: Container(
          color: c.dark ? c.surface.withAlpha(0xE8) : const Color(0xE0FCF8F0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '配对完成！',
                style: TextStyle(
                  fontFamily: AppFonts.zcool,
                  fontFamilyFallback: AppFonts.fallback,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.68,
                  color: c.mintInk,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '用时 $seconds 秒 · 步数 $moves · 得分 $score',
                style: TextStyle(
                  fontFamily: AppFonts.noto,
                  fontFamilyFallback: AppFonts.bodyFallback,
                  fontSize: 13,
                  color: c.ink2,
                ),
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

/// 单张卡牌：500ms cubic-bezier(.22,1,.36,1) 绕 Y 翻转（web .gmem-inner）。
class _MemoryTile extends StatefulWidget {
  const _MemoryTile({super.key, required this.data, this.onTap});

  final MemoryCardData data;
  final VoidCallback? onTap;

  @override
  State<_MemoryTile> createState() => _MemoryTileState();
}

class _MemoryTileState extends State<_MemoryTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    value: widget.data.open || widget.data.matched ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _MemoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = (widget.data.open || widget.data.matched) ? 1.0 : 0.0;
    if ((_ctrl.value - target).abs() > 0.0001) {
      _ctrl.animateTo(
        target,
        duration: const Duration(milliseconds: 500),
        curve: const Cubic(0.22, 1, 0.36, 1),
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

List<CssShadowSpec> _cardShadows() => const [
  CssShadowSpec(color: Color(0x0E5A4A2C), offset: Offset(0, 1), blur: 2),
  CssShadowSpec(
    color: Color(0x4D5A4A2C),
    offset: Offset(0, 8),
    blur: 20,
    spread: -12,
  ),
];

/// 卡背：橙色 + 3px 奶油内环 + 「CITRO」/「橘」（web .gmem-back）。
class _CardBack extends StatelessWidget {
  const _CardBack();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CssShadowLayer(
      radius: 10,
      shadows: _cardShadows(),
      child: SizedBox.expand(
        child: Container(
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.accent2),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0x4DFFFDF8), width: 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'CITRO',
                  style: TextStyle(
                    fontFamily: AppFonts.kalam,
                    fontFamilyFallback: AppFonts.fallback,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    letterSpacing: 1.98,
                    color: c.ink.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '橘',
                  style: TextStyle(
                    fontFamily: AppFonts.zcool,
                    fontFamilyFallback: AppFonts.fallback,
                    fontSize: 21.06,
                    fontWeight: FontWeight.w400,
                    height: 1,
                    color: c.ink,
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

/// 卡正面：纸色 + Kalam 汉字（配成后薄荷绿，web `.matched .gmem-front`）。
class _CardFront extends StatelessWidget {
  const _CardFront({required this.char, required this.matched});

  final String char;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CssShadowLayer(
      radius: 10,
      shadows: _cardShadows(),
      child: SizedBox.expand(
        child: Container(
          decoration: BoxDecoration(
            color: matched ? c.mintSoft : c.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: matched ? c.mintLine : c.line),
          ),
          child: Center(
            child: Text(
              char,
              style: TextStyle(
                fontFamily: AppFonts.kalam,
                fontFamilyFallback: AppFonts.fallback,
                fontSize: 23.4,
                fontWeight: FontWeight.w400,
                height: 38.61 / 23.4,
                color: matched ? c.mintInk : c.accentInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
