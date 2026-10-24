import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lpinyin/lpinyin.dart';

import '../data/idioms.dart';
import '../services/ai.dart';
import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

import 'game_ui.dart';

// ---------------------------------------------------------------------------
// 纸笺色板（取自 web 计算样式树 _tmp/ref/spec/gidiom.txt，390x844 light）
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

/// 接龙链上的一条（seed 系统起手 / you 玩家 / ai 电脑）。
class ChainItem {
  final String text;
  final String role;
  final String note;
  const ChainItem(this.text, this.role, this.note);
}

/// 页面阶段（golden 用 menu 态，与 web 截图一致）。
enum IdiomPhase { menu, playing, result }

class GameIdiomPage extends StatefulWidget {
  const GameIdiomPage({super.key});
  @override
  State<GameIdiomPage> createState() => _GameIdiomPageState();
}

class _GameIdiomPageState extends State<GameIdiomPage> {
  final rnd = math.Random();
  final input = TextEditingController();
  final scroll = ScrollController();
  List<ChainItem> chain = [];
  Set<String> used = {};
  String need = '';
  bool running = false;
  bool over = false;
  bool won = false;
  bool aiThinking = false;
  bool validating = false;
  int count = 0;
  int score = 0;
  int best = 0;
  int deadline = 60;
  String fb = '';
  String endTitle = '时间到';
  String endSub = '60 秒内没接上，本局结束';
  Timer? timer;
  final _progress = ValueNotifier<String>('');
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    best = AppState.instance.localBest('idiom');
    _reset();
    // v1.6.4：键盘抬起时列表要停在最新的词上（用户反馈抬键盘看到的是旧词）。
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

  /// 输入框获得焦点（键盘弹出）时滚到最新一条。
  void _onFocus() {
    if (focus.hasFocus) _scrollBottom();
  }

  late final KeyboardObserver _kbObserver;

  void _reset() {
    timer?.cancel();
    chain = [];
    used = {};
    need = '';
    count = 0;
    score = 0;
    running = false;
    over = false;
    won = false;
    aiThinking = false;
    validating = false;
    deadline = 60;
    fb = '';
    input.clear();
    _progress.value = '';
    if (mounted) setState(() {});
  }

  void _start() {
    _reset();
    final seed = kIdiomSeeds[rnd.nextInt(kIdiomSeeds.length)];
    chain.add(ChainItem(seed, 'seed', '起手'));
    used.add(seed);
    need = _pinyin(seed.substring(seed.length - 1));
    running = true;
    _startTimer();
    setState(() {});
    focus.requestFocus();
  }

  void _startTimer() {
    timer?.cancel();
    deadline = 60;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !running) return;
      setState(() => deadline--);
      if (deadline <= 0) _finish(win: false);
    });
  }

  String _pinyin(String s) {
    try {
      return PinyinHelper.getPinyinE(
        s,
        separator: '',
        format: PinyinFormat.WITHOUT_TONE,
      ).toLowerCase();
    } catch (_) {
      return s;
    }
  }

  int _mult() => math.max(1, (count ~/ 2) * 2);

  void _submit() {
    if (!running || aiThinking || validating) return;
    final raw = input.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (raw.isEmpty) {
      _feedback('先输入一个成语吧');
      return;
    }
    if (!RegExp(r'^[\u4e00-\u9fa5]{2,8}$').hasMatch(raw)) {
      _feedback('请输入 2~8 个汉字的成语');
      return;
    }
    if (used.contains(raw)) {
      _feedback('本局用过的成语不能重复');
      return;
    }
    if (_pinyin(raw.substring(0, 1)) != need) {
      _feedback('首字读音要接上「$need」，再想想');
      return;
    }
    if (!kIdioms.contains(raw)) {
      // 本地词库没有 → AI 判定兜底（web 端由服务端查词库后才问 AI，
      // v1.5.8 直接拒收，词库外的成语全被误杀，用户以为没接 AI）。
      _verifyAndAccept(raw);
      return;
    }
    _accept(raw);
  }

  /// AI 兜底：判定玩家提交的词库外成语是否真实存在。
  Future<void> _verifyAndAccept(String raw) async {
    if (validating) return;
    validating = true;
    setState(() => fb = 'AI 判定中…');
    final verdict = await AiService.verifyIdiom(raw);
    if (!mounted) return;
    validating = false;
    if (verdict != true) {
      // v1.6.3：原来这里 setState(() => fb='') 立刻把提示抹掉了（用户反馈
      // 「AI 判定结果没有 toast」），改为带自动消失的顶部提示。
      _feedback(verdict == false ? 'AI 判定：「$raw」不是成语' : 'AI 暂时判定不了，换一个试试');
      return;
    }
    _accept(raw, aiVerified: true);
  }

  void _accept(String raw, {bool aiVerified = false}) {
    used.add(raw);
    count++;
    final mult = _mult();
    score += 10 * mult;
    input.clear();
    if (aiVerified) _feedback('AI 判定：「$raw」通过 ✓');
    setState(() {
      chain.add(ChainItem(raw, 'you', '接龙 ${mult > 1 ? '×$mult' : ''}'));
      need = _pinyin(raw.substring(raw.length - 1));
      aiThinking = true;
      if (!aiVerified) fb = '';
    });
    GameSfx.eat();
    _progress.value = '接龙 $count · 得分 $score';
    _scrollBottom();
    timer?.cancel();
    Future.delayed(const Duration(milliseconds: 650), _aiTurn);
  }

  Future<void> _aiTurn() async {
    if (!mounted || !running) return;
    final candidates = kIdioms
        .where((e) => !used.contains(e) && _pinyin(e.characters.first) == need)
        .toList();
    String? pick;
    if (candidates.isEmpty) {
      // 本地词库接不上时才走 AI 兜底（AiService → glm-5.3-flash）。
      setState(() => fb = 'AI 兜底中…');
      pick = await AiService.suggestIdiom(
        last: chain.isEmpty ? '' : chain.last.text,
        pinyin: need,
        used: used.toList(),
      );
      if (!mounted || !running) return;
      if (pick == null ||
          pick.length != 4 ||
          used.contains(pick) ||
          _pinyin(pick.substring(0, 1)) != need) {
        _finish(win: true);
        return;
      }
    } else {
      pick = candidates[rnd.nextInt(candidates.length)];
    }
    final chosen = pick;
    used.add(chosen);
    GameSfx.flip();
    setState(() {
      chain.add(ChainItem(chosen, 'ai', 'AI 接龙'));
      need = _pinyin(chosen.substring(chosen.length - 1));
      aiThinking = false;
      fb = '';
    });
    _startTimer();
    _scrollBottom();
    focus.requestFocus();
  }

  Timer? _fbTimer;

  void _feedback(String msg) {
    // v1.6.2：只保留顶部 fb 浮层；v1.6.3：改为 2.2s 自动消失的 toast 行为。
    _fbTimer?.cancel();
    if (!mounted) return;
    setState(() => fb = msg);
    _fbTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => fb = '');
    });
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

  void _finish({required bool win}) {
    if (!running) return;
    timer?.cancel();
    if (win) score += 10 * _mult();
    running = false;
    over = true;
    won = win;
    aiThinking = false;
    validating = false;
    fb = '';
    if (win) {
      GameSfx.win();
    } else {
      GameSfx.lose();
    }
    endTitle = win ? 'AI 接不上了！' : '时间到';
    endSub = win ? 'AI 没能接上，本局你赢啦' : '60 秒内没接上，本局结束';
    _progress.value = '';
    AppState.instance.saveLocalBest('idiom', score);
    AppState.instance.submitScore('idiom', score);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GameIdiomView(
      phase: running
          ? IdiomPhase.playing
          : (over ? IdiomPhase.result : IdiomPhase.menu),
      count: count,
      score: score,
      best: best,
      chain: chain,
      need: need,
      deadline: deadline,
      aiThinking: aiThinking,
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
      onRank: () => showGameRank(context, game: 'idiom', title: '成语接龙 · 玩家排行'),
    );
  }
}

// ---------------------------------------------------------------------------
// 纯视觉层：web #gidiomPage 的 390x844 版式
// ---------------------------------------------------------------------------

/// 成语接龙视图（纯视觉；golden 用默认 menu 态渲染）。
class GameIdiomView extends StatelessWidget {
  const GameIdiomView({
    super.key,
    this.phase = IdiomPhase.menu,
    this.count = 0,
    this.score = 0,
    this.best = 0,
    this.chain = const <ChainItem>[],
    this.need = '',
    this.deadline = 60,
    this.aiThinking = false,
    this.fb = '',
    this.endTitle = '时间到',
    this.endSub = '60 秒内没接上，本局结束',
    this.won = false,
    this.input,
    this.focusNode,
    this.scrollController,
    this.liveProgress,
    this.onStart,
    this.onAgain,
    this.onSubmit,
    this.onRank,
  });

  final IdiomPhase phase;
  final int count;
  final int score;
  final int best;
  final List<ChainItem> chain;
  final String need;
  final int deadline;
  final bool aiThinking;
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
  final VoidCallback? onRank;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final media = MediaQuery.sizeOf(context);
    final w = media.width;
    final tablet = w >= 900;
    final stageH = tablet
        ? math.min(640.0, math.max(520.0, media.height - 340))
        : _stageH;
    return GameScaffold(
      gameKey: 'gidiom',
      title: '成语接龙',
      boardGap: 12,
      liveProgress: liveProgress,
      pills: [
        GameScorePill(label: '本局接龙', value: '$count'),
        GameScorePill(label: '最长记录', value: '$best'),
      ],
      actions: [
        GameActionButton(
          label: '开始接龙',
          icon: GameIcons.reset,
          primary: true,
          onTap: onStart,
        ),
        GameActionButton(label: '排行榜', icon: GameIcons.trophy, onTap: onRank),
      ],
      board: SizedBox(
        width: math.max(0.0, w - GameMetrics.sidePad * 2),
        // v1.6.2：键盘弹出时按剩余可视高度收短舞台。
        height: phase == IdiomPhase.playing
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
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.line),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _PaperLinesPainter(_paperGrid)),
                  ),
                  if (phase == IdiomPhase.menu)
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
                  else if (phase == IdiomPhase.playing)
                    _board()
                  else
                    _result(),
                  // web .gi-stage::after 的「橘」水印；菜单面板不透明会盖住它。
                  if (phase != IdiomPhase.menu) _watermark(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- 菜单（web #gidiomMenu.gi-panel.on） --------------------------------
  Widget _menu() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 42.578,
          left: (_innerW - 52) / 2,
          width: 52,
          height: 52,
          child: _sealMark(),
        ),
        Positioned(
          top: 102.578,
          left: -1,
          right: 1,
          height: 26.4,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 2.64),
              child: Text(
                '成语接龙',
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
          top: 137.968,
          left: 18,
          width: 324,
          height: 41.25,
          child: _tagRow('上一个成语的尾字，就是你要接的读\n音'),
        ),
        Positioned(top: 193.218, left: 18, width: 324, child: _rules()),
        // 2026-10-23：规则四条在 Skia 字形度量下比 web 高约 12px，
        // 固定 top 385.843 的开始按钮会压住第四条（用户反馈「按钮和规则
        // 重叠」）；整体下移 18px 给足间距。
        Positioned(
          top: 403.843,
          left: (_innerW - 140) / 2,
          width: 140,
          height: 48,
          child: _bigButton('开始接龙', onStart),
        ),
        Positioned(
          top: 459.843,
          left: -1,
          right: 1,
          height: 18.969,
          child: Center(
            child: Text(
              'AI 对战 · GLM-5.3-Flash 实时出题与判定',
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
            '同音\n接龙',
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
        const TextSpan(text: '你与 AI 轮流接龙，'),
        const TextSpan(text: '只要尾字与首字同音', style: _emStyle),
        const TextSpan(text: '即可，不\n区分声调'),
      ],
      [
        const TextSpan(text: '每回合 '),
        const TextSpan(text: '60 秒', style: _emStyle),
        const TextSpan(text: '，超时即结束本局'),
      ],
      [
        const TextSpan(text: '接对一个基础 '),
        const TextSpan(text: '+10 分', style: _emStyle),
        const TextSpan(text: '；本局答对 '),
        const TextSpan(text: '2 个后 ×2', style: _emStyle),
        const TextSpan(text: '、'),
        const TextSpan(text: '4 ', style: _emStyle),
        const TextSpan(text: '\n'),
        const TextSpan(text: '个后 ×4', style: _emStyle),
        const TextSpan(text: '，之后每多 2 个倍率再加 2 倍'),
      ],
      [const TextSpan(text: '成语需真实存在，由 AI 判定；本局用过的不能重\n复')],
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

  // --- 运行中棋盘（web #gidiomBoard） ------------------------------------
  Widget _board() {
    final frac = (deadline / 60).clamp(0.0, 1.0);
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
                        '请接这个音',
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
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 3),
                        decoration: BoxDecoration(
                          border: Border.all(color: _stamp, width: 2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          need.isEmpty ? '—' : need,
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
                          '$deadline',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: AppFonts.noto,
                            fontFamilyFallback: AppFonts.bodyFallback,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.65,
                            letterSpacing: 0,
                            color: deadline <= 10 ? _stamp : _ink,
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
                            color: deadline <= 10 ? _stamp : _accent,
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
                          enabled: !aiThinking,
                          // v1.6.1：提交后立即重新聚焦，键盘不收起（用户反馈：
                          // 不要每次提交之后就关闭输入法）。
                          onSubmitted: (_) {
                            onSubmit?.call();
                            focusNode?.requestFocus();
                          },
                          maxLength: 12,
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
                            hintText: '输入成语，回车提交',
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
                        label: '接',
                        width: 66,
                        height: 46,
                        fontSize: 17,
                        letterSpacing: 1.02,
                        onTap: aiThinking ? null : onSubmit,
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
                if (aiThinking)
                  const Text(
                    'AI 兜底中…',
                    style: TextStyle(
                      fontFamily: AppFonts.noto,
                      fontFamilyFallback: AppFonts.bodyFallback,
                      fontSize: 11.5,
                      height: 1.65,
                      letterSpacing: 0,
                      color: _inkSoft,
                    ),
                  ),
                // v1.6.1：需接拼音常驻输入行上方（用户反馈：键盘抬起会遮住
                // 顶部的拼音提示，把它复制到键盘上方永远可见的位置）。
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
                        const TextSpan(text: '需接 '),
                        TextSpan(
                          text: need.isEmpty ? '—' : need,
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
                        text: '×${math.max(1, (count ~/ 2) * 2)}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _accentInk,
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
    );
  }

  Widget _chainRow(ChainItem item) {
    final bar = item.role == 'ai'
        ? _mintInk
        : (item.role == 'you' ? _accent : _stamp);
    final tagText = item.role == 'ai'
        ? 'AI'
        : (item.role == 'you' ? '你' : '起手');
    return Container(
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
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
                        if (item.note.isNotEmpty)
                          Expanded(
                            child: Text(
                              item.note,
                              textAlign: TextAlign.right,
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
                    Text(
                      item.text,
                      style: const TextStyle(
                        fontFamily: AppFonts.zcool,
                        fontFamilyFallback: AppFonts.fallback,
                        fontSize: 18,
                        height: 1.5,
                        letterSpacing: 1.5,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 结算（web #gidiomResult.gi-panel） -------------------------------
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
              _stat('本局接龙', '$count'),
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
                '橘',
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
    return GestureDetector(
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

// ---------------------------------------------------------------------------
// 壹 / 贰 / 叁 / 肆 序数印章字
//
// App 内置的 zcool-app.ttf 是子集字体，没有这四个字（web 端用的是全量
// ZCOOL KuaiLe，页面靠它渲染）。这里把 devtools/fonts-src/ZCOOLKuaiLe.ttf
// 里四个字的字形轮廓（纯直线轮廓）内嵌成路径，按 web 的字号与基线绘制：
// ZCOOL KuaiLe upm=1000 / hhea ascent=880 / descent=-120 / advance=920。
// 这样不新增字体资源也能与参考图逐像素一致。
// ---------------------------------------------------------------------------

class OrdinalGlyph extends StatelessWidget {
  const OrdinalGlyph(
    this.ord, {
    super.key,
    this.fontSize = 12,
    this.color = _stamp,
  });

  final String ord;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fontSize * 0.92,
      height: fontSize,
      child: CustomPaint(painter: _OrdinalGlyphPainter(ord, fontSize, color)),
    );
  }
}

class _OrdinalGlyphPainter extends CustomPainter {
  _OrdinalGlyphPainter(this.ord, this.fontSize, this.color);

  final String ord;
  final double fontSize;
  final Color color;

  static const Map<String, String> _glyphs = {
    '壹': 'M468,648L468,630L701,636L703,541L197,530L194,623L374,627L374,649L71,655L72,748L374,743L374,778L468,778L468,742L806,737L804,642ZM714,316L751,422L156,420L159,317L66,313L61,465L107,513L817,517L862,455L803,286ZM213,407L686,411L687,317L213,313ZM203,121L189,250L237,301L663,301L711,248L696,138L652,98L633,97L620,56L822,65L826,-30L62,-60L58,33L273,42L260,80L253,80ZM293,176L608,190L609,207L289,207ZM370,46L520,52L533,93L357,85Z',
    '贰': 'M829,-69L674,85L660,108L568,602L25,610L26,705L550,697L534,783L626,801L645,696L729,695L690,760L771,808L841,693L875,693L874,598L663,601L750,141L895,-3ZM468,466L69,480L73,573L471,560ZM495,348L81,350L81,445L495,443ZM514,90L423,112L449,226L381,227L309,119L530,31L495,-57L255,39L169,-90L90,-38L268,230L156,233L165,106L70,100L59,280L108,330L510,318L555,260Z',
    '叁': 'M744,393L857,249L783,190L687,313L685,234L282,254L284,287L131,126L62,191L267,407L95,412L98,506L354,498L405,552L235,537L195,615L322,771L396,711L338,641L649,667L627,724L715,759L795,554L707,519L684,576L476,558L511,526L481,495L857,484L855,390ZM338,344L675,329L623,397L394,403ZM272,191L653,200L656,106L273,97ZM201,42L817,90L825,-4L207,-51Z',
    '肆': 'M826,469L826,389L781,341L675,336L674,286L820,291L824,196L670,191L669,145L876,155L880,60L665,50L662,-53L567,-51L570,45L449,40L445,135L574,141L575,188L485,185L482,280L579,283L580,331L465,325L460,420L584,425L586,484L422,494L427,587L589,577L591,630L456,640L464,734L594,724L596,776L691,772L689,717L781,711L825,664L825,564L880,561L875,466ZM41,260L94,266L61,680L107,730L364,734L365,639L159,637L164,573L355,587L362,494L171,478L176,417L399,446L411,352L184,322L188,276L420,302L430,209L223,185L170,57L311,78L290,135L379,167L450,-24L362,-56L345,-11L102,-49L51,16L115,173L51,166ZM686,623L684,572L731,569L731,620ZM732,475L680,478L679,429L732,432Z',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final data = _glyphs[ord];
    if (data == null) return;
    final scale = fontSize / 1000;
    canvas.save();
    canvas.translate(0, fontSize * 0.88);
    canvas.scale(scale, -scale);
    canvas.drawPath(
      _parse(data),
      Paint()
        ..color = color
        ..isAntiAlias = true
        ..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  static Path _parse(String data) {
    final path = Path();
    var cmd = 'M';
    var i = 0;
    while (i < data.length) {
      final ch = data[i];
      final code = data.codeUnitAt(i);
      if (ch == 'Z') {
        path.close();
        i++;
        continue;
      }
      if (code >= 65 && code <= 90) {
        cmd = ch;
        i++;
        continue;
      }
      final xEnd = _numEnd(data, i);
      final x = double.parse(data.substring(i, xEnd));
      i = xEnd;
      if (i < data.length && data[i] == ',') i++;
      final yEnd = _numEnd(data, i);
      final y = double.parse(data.substring(i, yEnd));
      i = yEnd;
      if (cmd == 'M') {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  static int _numEnd(String data, int start) {
    var i = start;
    while (i < data.length) {
      final c = data.codeUnitAt(i);
      final isDigit = c >= 48 && c <= 57;
      if (!isDigit && data[i] != '-' && data[i] != '.') break;
      i++;
    }
    return i;
  }

  @override
  bool shouldRepaint(covariant _OrdinalGlyphPainter old) =>
      old.ord != ord || old.fontSize != fontSize || old.color != color;
}
