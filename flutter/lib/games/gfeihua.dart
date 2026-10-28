import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/poems.dart';
import '../services/ai.dart';
import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'game_ui.dart';
// 序数印章字「壹贰叁肆」在内置子集字体里缺字，统一复用成语接龙页里的
// OrdinalGlyph（内嵌 ZCOOL KuaiLe 字形轮廓），两页保持同一套渲染。
import 'gidiom.dart' show OrdinalGlyph;

// ---------------------------------------------------------------------------
// 纸笺色板（取自 web 计算样式树 _tmp/ref/spec/gfeihua.txt，390x844 light）
// ---------------------------------------------------------------------------
const Color _ink = Color(0xFF23211C);
const Color _ink2 = Color(0xFF4E4A40);
const Color _inkSoft = Color(0xFF6E6858);
const Color _stamp = Color(0xFFB3402A);
const Color _accent = Color(0xFFF2A43C);
const Color _accent2 = Color(0xFFDE8A1F);
const Color _accentInk = Color(0xFF8F4E05);
const Color _surface2 = Color(0xFFFFFDF8);
const Color _line = Color(0xFFE4DCC9);
const Color _line2 = Color(0xFFD2C8B0);
const Color _paperGrid = Color(0x1660523A);
const Color _mintInk = Color(0xFF2C6B50);
const Color _fail = Color(0xFFC4482F);
const Color _onAccent = Color(0xFF2E2C22);
const Color _hintText = Color(0xFFB6AF9F);

const TextStyle _emStyle = TextStyle(
  color: _accentInk,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
);

const double _stageH = 506.39;
const double _innerW = 360;

/// 飞花令链上的一句（you 玩家 / ai 电脑）。
class FhItem {
  final String line;
  final String meta;
  final String role;
  const FhItem(this.line, this.meta, this.role);
}

/// 页面阶段（golden 用 menu 态，与 web 截图一致）。
enum FeihuaPhase { menu, playing, result }

class GameFeihuaPage extends StatefulWidget {
  const GameFeihuaPage({super.key});
  @override
  State<GameFeihuaPage> createState() => _GameFeihuaPageState();
}

class _GameFeihuaPageState extends State<GameFeihuaPage> {
  final rnd = math.Random();
  final input = TextEditingController();
  final scroll = ScrollController();
  List<FhItem> chain = [];
  Set<String> used = {};
  String ch = '花';
  int count = 0;
  int score = 0;
  int best = 0;
  int seconds = 120;
  bool running = false;
  bool over = false;
  bool won = false;
  bool thinking = false;
  bool validating = false;
  String fb = '';
  String endTitle = '时间到';
  String endSub = '120 秒内没接上，本局结束';
  Timer? timer;
  final _progress = ValueNotifier<String>('');
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    best = AppState.instance.localBest('feihua');
    // v1.6.4：键盘抬起时列表停在最新一句上
    _kbObserver = KeyboardObserver(_scrollBottom);
    WidgetsBinding.instance.addObserver(_kbObserver);
    focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_kbObserver);
    focus.removeListener(_onFocus);
    timer?.cancel();
    _fbTimer?.cancel();
    input.dispose();
    scroll.dispose();
    focus.dispose();
    _progress.dispose();
    super.dispose();
  }

  late final KeyboardObserver _kbObserver;

  void _onFocus() {
    if (focus.hasFocus) _scrollBottom();
  }

  void _start() {
    timer?.cancel();
    chain = [];
    used = {};
    count = 0;
    score = 0;
    seconds = 120;
    running = true;
    over = false;
    won = false;
    thinking = false;
    validating = false;
    fb = '';
    ch = kFeihuaChars[rnd.nextInt(kFeihuaChars.length)];
    input.clear();
    setState(() {});
    _timer();
    focus.requestFocus();
    _progress.value = '令字 $ch';
  }

  void _timer() {
    timer?.cancel();
    seconds = 120;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !running) return;
      setState(() => seconds--);
      if (seconds <= 0) _end(false);
    });
  }

  void _submitFromEnter() {
    if (input.value.composing.isValid) return;
    if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(input.text)) {
      _feedback('请先选好中文候选词，再回车提交');
      return;
    }
    _submit();
  }

  void _submit() {
    if (!running || thinking || validating) return;
    final raw = input.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (raw.isEmpty) {
      _feedback('先想一句诗吧');
      return;
    }
    if (raw.length < 5) {
      _feedback('请至少写一句五个字的诗');
      return;
    }
    if (!raw.contains(ch)) {
      _feedback('诗句里要有令字「$ch」');
      return;
    }
    if (!RegExp(r'^[\u4e00-\u9fa5，。！？、；：,.!?;:]{5,30}$').hasMatch(raw)) {
      _feedback('请只输入中文诗句');
      return;
    }
    if (used.contains(raw)) {
      _feedback('这句已经说过了');
      return;
    }
    if (!kPoemLines.any((p) => p.line == raw)) {
      // 本地诗句库没有 → AI 判定兜底（web 端由服务端查词库后才问 AI）。
      _verifyAndAccept(raw);
      return;
    }
    _accept(raw);
  }

  /// AI 兜底：判定玩家提交的词库外诗句是否真实存在且含令字。
  Future<void> _verifyAndAccept(String raw) async {
    if (validating) return;
    validating = true;
    setState(() => fb = 'AI 判定中…');
    final verdict = await AiService.verifyPoem(raw, ch);
    if (!mounted) return;
    validating = false;
    if (verdict != true) {
      // v1.6.3：原来紧跟的 setState(fb='') 会把提示抹掉，改为自动消失的 toast
      _feedback(verdict == false ? 'AI 判定：这不是含「$ch」的真实诗句' : 'AI 暂时判定不了，换一句试试');
      return;
    }
    _accept(raw, aiVerified: true);
  }

  void _accept(String raw, {bool aiVerified = false}) {
    used.add(raw);
    count++;
    final mult = math.max(1, (count ~/ 2) * 2);
    score += 10 * mult;
    input.clear();
    if (aiVerified) _feedback('AI 判定：「$raw」通过 ✓');
    setState(() {
      chain.add(FhItem(raw, '你', 'you'));
      thinking = true;
      if (!aiVerified) fb = '';
    });
    GameSfx.eat();
    _progress.value = '对句 $count · 得分 $score';
    _scrollBottom();
    timer?.cancel();
    Future.delayed(const Duration(milliseconds: 650), _aiTurn);
  }

  Future<void> _aiTurn() async {
    if (!mounted || !running) return;
    final pool = kPoemLines
        .where((p) => p.line.contains(ch) && !used.contains(p.line))
        .toList();
    String? line;
    String? meta;
    if (pool.isEmpty) {
      // 本地诗句库对不上时才走 AI 兜底（AiService → glm-5.3-flash）。
      setState(() => fb = 'AI 兜底中…');
      final suggestion = await AiService.suggestPoem(
        char: ch,
        used: used.toList(),
      );
      if (!mounted || !running) return;
      if (suggestion == null ||
          used.contains(suggestion.line) ||
          !suggestion.line.contains(ch)) {
        _end(true);
        return;
      }
      line = suggestion.line;
      final frag = [
        if (suggestion.author.isNotEmpty) suggestion.author,
        if (suggestion.title.isNotEmpty) '《${suggestion.title}》',
      ].join();
      meta = frag.isEmpty ? 'AI 对诗' : frag;
    } else {
      final p = pool[rnd.nextInt(pool.length)];
      line = p.line;
      meta = '${p.author}《${p.title}》';
    }
    used.add(line);
    GameSfx.flip();
    setState(() {
      chain.add(FhItem(line!, meta!, 'ai'));
      thinking = false;
      fb = '';
    });
    _timer();
    _scrollBottom();
    focus.requestFocus();
  }

  void _changeChar() {
    if (!running || count < 2) return;
    var next = kFeihuaChars[rnd.nextInt(kFeihuaChars.length)];
    if (next == ch) {
      next =
          kFeihuaChars[(kFeihuaChars.indexOf(next) + 1) % kFeihuaChars.length];
    }
    setState(() => ch = next);
    _timer();
    _progress.value = '令字 $ch';
    AppToast.show(context, '换令字：$ch');
  }

  Timer? _fbTimer;

  void _feedback(String msg) {
    // v1.6.2：只保留顶部 fb 浮层；v1.6.3：2.2s 自动消失的 toast 行为。
    _fbTimer?.cancel();
    if (!mounted) return;
    setState(() => fb = msg);
    _fbTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => fb = '');
    });
  }

  void _end(bool playerWon) {
    if (!running) return;
    timer?.cancel();
    running = false;
    over = true;
    won = playerWon;
    thinking = false;
    validating = false;
    if (playerWon) {
      final mult = math.max(1, (count ~/ 2) * 2);
      score += 10 * mult;
    }
    fb = '';
    if (playerWon) {
      GameSfx.win();
    } else {
      GameSfx.lose();
    }
    endTitle = playerWon ? 'AI 对不出了！' : '时间到';
    endSub = playerWon ? 'AI 没能对出含「$ch」的诗句，本局你赢啦' : '120 秒内没接上，本局结束';
    _progress.value = '';
    AppState.instance.saveLocalBest('feihua', score);
    AppState.instance.submitScore('feihua', score);
    setState(() {});
  }

  void _scrollBottom() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameFeihuaView(
      phase: running
          ? FeihuaPhase.playing
          : (over ? FeihuaPhase.result : FeihuaPhase.menu),
      count: count,
      score: score,
      best: best,
      chain: chain,
      ch: ch,
      seconds: seconds,
      thinking: thinking,
      fb: fb,
      endTitle: endTitle,
      endSub: endSub,
      won: won,
      input: input,
      focusNode: focus,
      scrollController: scroll,
      liveProgress: _progress,
      onStart: _start,
      onAgain: _start,
      onSubmit: _submit,
      onEnter: _submitFromEnter,
      onSwap: _changeChar,
      onRank: () => showGameRank(context, game: 'feihua', title: '飞花令 · 玩家排行'),
    );
  }
}

// ---------------------------------------------------------------------------
// 纯视觉层：web #gfeihuaPage 的 390x844 版式
// ---------------------------------------------------------------------------

/// 飞花令视图（纯视觉；golden 用默认 menu 态渲染）。
class GameFeihuaView extends StatelessWidget {
  const GameFeihuaView({
    super.key,
    this.phase = FeihuaPhase.menu,
    this.count = 0,
    this.score = 0,
    this.best = 0,
    this.chain = const <FhItem>[],
    this.ch = '花',
    this.seconds = 120,
    this.thinking = false,
    this.fb = '',
    this.endTitle = '时间到',
    this.endSub = '120 秒内没接上，本局结束',
    this.won = false,
    this.input,
    this.focusNode,
    this.scrollController,
    this.liveProgress,
    this.onStart,
    this.onAgain,
    this.onSubmit,
    this.onEnter,
    this.onSwap,
    this.onRank,
  });

  final FeihuaPhase phase;
  final int count;
  final int score;
  final int best;
  final List<FhItem> chain;
  final String ch;
  final int seconds;
  final bool thinking;
  final String fb;
  final String endTitle;
  final String endSub;
  final bool won;
  final TextEditingController? input;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final ValueNotifier<String>? liveProgress;
  final VoidCallback? onStart;
  final VoidCallback? onAgain;
  final VoidCallback? onSubmit;
  final VoidCallback? onEnter;
  final VoidCallback? onSwap;
  final VoidCallback? onRank;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final w = media.width;
    final tablet = w >= 900;
    final stageH = tablet
        ? math.min(640.0, math.max(520.0, media.height - 340))
        : _stageH;
    return GameScaffold(
      gameKey: 'gfeihua',
      title: '飞花令',
      boardGap: 12,
      liveProgress: liveProgress,
      pills: [
        GameScorePill(label: '本局对句', value: '$count'),
        GameScorePill(label: '本局得分', value: '$score'),
        GameScorePill(label: '最长记录', value: '$best'),
      ],
      actions: [
        GameActionButton(
          label: '开始飞花令',
          icon: GameIcons.reset,
          primary: true,
          onTap: onStart,
        ),
        GameActionButton(label: '排行榜', icon: GameIcons.trophy, onTap: onRank),
      ],
      board: SizedBox(
        width: math.max(0.0, w - GameMetrics.sidePad * 2),
        // v1.6.2：键盘弹出时按剩余可视高度收短舞台。
        height: phase == FeihuaPhase.playing
            ? math.min(
                stageH,
                math.max(
                  280.0,
                  media.height - MediaQuery.viewInsetsOf(context).bottom - 240,
                ),
              )
            : stageH,
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
          child: SizedBox.expand(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                // 纸笺色板固定为浅色，舞台也保持浅色纸面，
                // 否则深色主题下深色文字会压在深色底上。
                color: CitroColors.light.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CitroColors.light.line),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _PaperLinesPainter(_paperGrid)),
                  ),
                  if (phase == FeihuaPhase.menu)
                    Center(
                      child: tablet
                          ? SizedBox.expand(
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: _innerW,
                                  height: _stageH,
                                  child: _menu(),
                                ),
                              ),
                            )
                          : SizedBox(
                              width: _innerW,
                              height: _stageH,
                              child: _menu(),
                            ),
                    )
                  else if (phase == FeihuaPhase.playing)
                    _board()
                  else
                    _result(),
                  // web .gi-stage::after 的「诗」水印；菜单面板不透明会盖住它。
                  if (phase != FeihuaPhase.menu) _watermark(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- 菜单（web #gfeihuaMenu.gi-panel.on） -------------------------------
  Widget _menu() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 52.891,
          left: (_innerW - 52) / 2,
          width: 52,
          height: 52,
          child: _sealMark(),
        ),
        Positioned(
          top: 112.891,
          left: -1,
          right: 1,
          height: 26.4,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 2.64),
              child: Text(
                '飞花令',
                style: const TextStyle(
                  fontFamily: AppFonts.zcool,
                  fontFamilyFallback: AppFonts.fallback,
                  fontSize: 22,
                  height: 1.2,
                  letterSpacing: 2.64,
                  color: _ink,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 148.281,
          left: 18,
          width: 324,
          height: 20.625,
          child: _tagRow('说出含有令字的诗句'),
        ),
        Positioned(top: 182.905, left: 18, width: 324, child: _rules()),
        Positioned(
          top: 375.531,
          left: (_innerW - 140) / 2,
          width: 140,
          height: 48,
          child: _bigButton('开始飞花令', onStart),
        ),
        Positioned(
          top: 431.531,
          left: -1,
          right: 1,
          height: 18.969,
          child: Center(
            child: Text(
              'AI 对战 · GLM-5.3-Flash 实时抽字与对诗',
              style: const TextStyle(
                fontFamily: AppFonts.noto,
                fontFamilyFallback: AppFonts.bodyFallback,
                fontSize: 11.5,
                height: 1.65,
                letterSpacing: 0.575,
                color: _inkSoft,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sealMark() {
    return Transform.rotate(
      angle: -4 * math.pi / 180,
      child: Opacity(
        opacity: 0.92,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _stamp, width: 2),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.center,
          child: const Text(
            '飞花\n令',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.zcool,
              fontFamilyFallback: AppFonts.fallback,
              fontSize: 13,
              height: 1.12,
              letterSpacing: 0,
              color: _stamp,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tagRow(String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _tagRule(reverse: true),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 12.5,
              height: 1.65,
              letterSpacing: 0.75,
              color: _ink2,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _tagRule(),
      ],
    );
  }

  Widget _tagRule({bool reverse = false}) {
    return Container(
      width: 40,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: reverse
              ? const [Color(0x00D2C8B0), _line2]
              : const [_line2, Color(0x00D2C8B0)],
        ),
      ),
    );
  }

  Widget _rules() {
    final base = TextStyle(
      fontFamily: AppFonts.noto,
      fontFamilyFallback: AppFonts.bodyFallback,
      fontSize: 13.5,
      height: 22.95 / 13.5,
      letterSpacing: 0,
      color: _ink2,
    );
    const ord = ['壹', '贰', '叁', '肆'];
    final texts = <List<InlineSpan>>[
      [
        const TextSpan(text: '系统随机抽一个'),
        const TextSpan(text: '令字', style: _emStyle),
        const TextSpan(text: '，你与 AI 轮流说出含这个字\n的诗句'),
      ],
      [
        const TextSpan(text: '每回合 '),
        const TextSpan(text: '120 秒', style: _emStyle),
        const TextSpan(text: '，超时即结束本局'),
      ],
      [
        const TextSpan(text: '每句基础 '),
        const TextSpan(text: '+10 分', style: _emStyle),
        const TextSpan(text: '；本局答对 '),
        const TextSpan(text: '2 句后 ×2', style: _emStyle),
        const TextSpan(text: '、'),
        const TextSpan(text: '4 句后', style: _emStyle),
        const TextSpan(text: '\n'),
        const TextSpan(text: '×4', style: _emStyle),
        const TextSpan(text: '，之后每多 2 句倍率再加 2 倍'),
      ],
      [
        const TextSpan(text: '答满 2 句后即可'),
        const TextSpan(text: '随时换个令字', style: _emStyle),
        const TextSpan(text: '，换字不影响已累计的倍数'),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < texts.length; i++) ...[
          if (i > 0) const SizedBox(height: 7),
          _ruleRow(ord[i], TextSpan(style: base, children: texts[i])),
        ],
      ],
    );
  }

  Widget _ruleRow(String ord, TextSpan span) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            border: Border.all(color: _stamp, width: 1),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.center,
          child: OrdinalGlyph(ord),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text.rich(span)),
      ],
    );
  }

  // --- 运行中棋盘（web #gfeihuaBoard） -----------------------------------
  Widget _board() {
    final frac = (seconds / 120).clamp(0.0, 1.0);
    final mult = math.max(1, (count ~/ 2) * 2);
    return Column(
      children: [
        SizedBox(
          height: 66.297,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '令字',
                        style: TextStyle(
                          fontFamily: AppFonts.noto,
                          fontFamilyFallback: AppFonts.bodyFallback,
                          fontSize: 11.5,
                          height: 1.65,
                          letterSpacing: 0.92,
                          color: _inkSoft,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 3),
                        decoration: BoxDecoration(
                          border: Border.all(color: _stamp, width: 2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          ch.isEmpty ? '—' : ch,
                          style: const TextStyle(
                            fontFamily: AppFonts.zcool,
                            fontFamilyFallback: AppFonts.fallback,
                            fontSize: 22,
                            height: 36.3 / 22,
                            letterSpacing: 1.32,
                            color: _stamp,
                          ),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '$seconds',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: AppFonts.noto,
                            fontFamilyFallback: AppFonts.bodyFallback,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.65,
                            letterSpacing: 0,
                            color: seconds <= 10 ? _stamp : _ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Container(
                        width: 58,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _line,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: _line2, width: 1),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 56 * frac,
                          height: 5,
                          decoration: BoxDecoration(
                            color: seconds <= 10 ? _stamp : _accent,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _dashedLine(_line2),
            ],
          ),
        ),
        Expanded(
          // v1.6.1：错误 / AI 判定提示改为浮层挂在链表区顶部（用户反馈：
          // 提示要显示在屏幕上方；此前放在底部，弹键盘后被遮）。
          child: Stack(
            children: [
              Positioned.fill(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  children: [
                    for (final item in chain) ...[
                      _chainRow(item),
                      const SizedBox(height: 9),
                    ],
                  ],
                ),
              ),
              if (fb.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 6,
                  child: Center(child: _fbChip(fb)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 65,
          child: Column(
            children: [
              _dashedLine(_line2),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: SizedBox(
                  height: 46,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: input,
                          focusNode: focusNode,
                          enabled: !thinking,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => onEnter?.call(),
                          maxLength: 128,
                          style: const TextStyle(
                            fontFamily: AppFonts.noto,
                            fontFamilyFallback: AppFonts.bodyFallback,
                            fontSize: 16,
                            height: 1.65,
                            letterSpacing: 0.96,
                            color: _ink,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            counterText: '',
                            hintText: '输入一句诗，选候选词后回车或点「对」',
                            hintStyle: const TextStyle(
                              fontFamily: AppFonts.noto,
                              fontFamilyFallback: AppFonts.bodyFallback,
                              fontSize: 16,
                              color: _hintText,
                            ),
                            filled: true,
                            fillColor: _surface2,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _line2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _line2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _accent),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _line2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      _pillButton(
                        label: '对',
                        width: 66,
                        height: 46,
                        fontSize: 17,
                        letterSpacing: 1.02,
                        onTap: thinking ? null : onSubmit,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 28.266,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 6),
            child: Row(
              children: [
                // v1.6.1：令字常驻输入行上方（用户反馈：键盘抬起会遮住顶部
                // 的令字，把它复制到键盘上方永远可见的位置）。
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _stamp),
                  ),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontFamily: AppFonts.noto,
                        fontFamilyFallback: AppFonts.bodyFallback,
                        fontSize: 11.5,
                        height: 1.65,
                        letterSpacing: 0.23,
                        color: _ink2,
                      ),
                      children: [
                        const TextSpan(text: '令字 '),
                        TextSpan(
                          text: ch.isEmpty ? '—' : ch,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _stamp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Opacity(
                  opacity: count >= 2 ? 1 : 0.3,
                  child: GestureDetector(
                    onTap: onSwap,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _line2),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '换个令字',
                        style: TextStyle(
                          fontFamily: AppFonts.noto,
                          fontFamilyFallback: AppFonts.bodyFallback,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.65,
                          letterSpacing: 0.5,
                          color: _accentInk,
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontFamily: AppFonts.noto,
                      fontFamilyFallback: AppFonts.bodyFallback,
                      fontSize: 11.5,
                      height: 1.65,
                      letterSpacing: 0.23,
                      color: _inkSoft,
                    ),
                    children: [
                      const TextSpan(text: '当前 '),
                      TextSpan(
                        text: '×$mult',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _mintInk,
                        ),
                      ),
                      TextSpan(text: ' · 本局已答 $count 句'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chainRow(FhItem item) {
    final bar = item.role == 'ai' ? _mintInk : _accent;
    final tagText = item.role == 'ai' ? 'AI' : '你';
    return Container(
      decoration: BoxDecoration(
        color: item.role == 'ai'
            ? _surface2
            : Color.alphaBlend(_accent.withAlpha(20), _surface2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.role == 'ai' ? _line : _accent),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: bar),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: bar,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            tagText,
                            style: TextStyle(
                              fontFamily: AppFonts.zcool,
                              fontFamilyFallback: AppFonts.fallback,
                              fontSize: 11,
                              height: 1.4,
                              letterSpacing: 0,
                              color: item.role == 'ai'
                                  ? const Color(0xFFF5F1E3)
                                  : _onAccent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.meta,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFonts.noto,
                              fontFamilyFallback: AppFonts.bodyFallback,
                              fontSize: 11,
                              letterSpacing: 0,
                              color: _inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text.rich(_markedLine(item.line)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 诗句里的令字用朱砂高亮（web gfeihuaMark：split(ch).join(<em>ch</em>)）。
  TextSpan _markedLine(String line) {
    const base = TextStyle(
      fontFamily: AppFonts.zcool,
      fontFamilyFallback: AppFonts.fallback,
      fontSize: 17,
      height: 1.5,
      letterSpacing: 1.2,
      color: _ink,
    );
    if (ch.isEmpty || !line.contains(ch)) {
      return const TextSpan(style: base, text: '');
    }
    final parts = line.split(ch);
    return TextSpan(
      style: base,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          TextSpan(text: parts[i]),
          if (i < parts.length - 1)
            TextSpan(
              text: ch,
              style: const TextStyle(
                color: _accentInk,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ],
    );
  }

  // --- 结算（web #gfeihuaResult.gi-panel） ------------------------------
  Widget _result() {
    final titleColor = won ? _mintInk : _fail;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 36.3,
            child: Center(
              child: Text(
                endTitle,
                style: TextStyle(
                  fontFamily: AppFonts.zcool,
                  fontFamilyFallback: AppFonts.fallback,
                  fontSize: 22,
                  height: 36.3 / 22,
                  letterSpacing: 2.64,
                  color: titleColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _tagRule(reverse: true),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  endSub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppFonts.noto,
                    fontFamilyFallback: AppFonts.bodyFallback,
                    fontSize: 12.5,
                    height: 1.65,
                    letterSpacing: 0.75,
                    color: _ink2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _tagRule(),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stat('本局对句', '$count'),
              const SizedBox(width: 20),
              _stat('最长链', '${chain.length}'),
              const SizedBox(width: 20),
              _stat('本局得分', '$score', accent: true),
            ],
          ),
          const SizedBox(height: 17),
          SizedBox(width: 140, height: 48, child: _bigButton('再来一局', onAgain)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {bool accent = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppFonts.noto,
            fontFamilyFallback: AppFonts.bodyFallback,
            fontSize: 11.5,
            height: 1.65,
            letterSpacing: 0.46,
            color: _inkSoft,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppFonts.kalam,
            fontFamilyFallback: AppFonts.fallback,
            fontSize: 23,
            fontWeight: FontWeight.w700,
            height: 1.65,
            letterSpacing: 0,
            color: accent ? _accentInk : _ink,
          ),
        ),
      ],
    );
  }

  // --- 共用小件 ----------------------------------------------------------
  Widget _watermark() {
    return Positioned(
      right: 13,
      bottom: 11,
      width: 25,
      height: 25,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.5,
          child: Transform.rotate(
            angle: -7 * math.pi / 180,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: _stamp, width: 1),
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child: const Text(
                '诗',
                style: TextStyle(
                  fontFamily: AppFonts.zcool,
                  fontFamilyFallback: AppFonts.fallback,
                  fontSize: 14,
                  height: 1.65,
                  letterSpacing: 0,
                  color: _stamp,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashedLine(Color color) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashedLinePainter(color)),
    );
  }

  Widget _bigButton(String label, VoidCallback? onTap) {
    return GameHover(
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 2,
              height: 48,
              child: Container(
                decoration: BoxDecoration(
                  color: _accent2,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.transparent),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: AppFonts.noto,
                    fontFamilyFallback: AppFonts.bodyFallback,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.28,
                    color: _onAccent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 链表区顶部的错误 / AI 判定提示胶囊（不占布局，浮在列表上方）。
  Widget _fbChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A3C301A),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: const TextStyle(
          fontFamily: AppFonts.noto,
          fontFamilyFallback: AppFonts.bodyFallback,
          fontSize: 12.5,
          height: 1.5,
          letterSpacing: 0,
          fontWeight: FontWeight.w600,
          color: _ink2,
        ),
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required double width,
    required double height,
    required double fontSize,
    required double letterSpacing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 2,
              height: height,
              child: Container(
                decoration: BoxDecoration(
                  color: _accent2,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppFonts.noto,
                    fontFamilyFallback: AppFonts.bodyFallback,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: letterSpacing,
                    color: _onAccent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 背景竖线 / 虚线
// ---------------------------------------------------------------------------

class _PaperLinesPainter extends CustomPainter {
  _PaperLinesPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var x = 28.0; x < size.width; x += 28) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperLinesPainter old) => old.color != color;
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset(math.min(x + 3, size.width), 0.5),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
