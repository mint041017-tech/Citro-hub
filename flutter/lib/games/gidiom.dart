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
import '../widgets/paper.dart';

import 'game_identity.dart';
import 'game_ui.dart';

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
    _kbObserver = KeyboardObserver(_scrollToLatest);
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
    if (focus.hasFocus) _scrollToLatest();
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

  void _submitFromEnter() {
    if (input.value.composing.isValid) return;
    if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(input.text)) {
      _feedback('请先选好中文候选词，再回车提交');
      return;
    }
    _submit();
  }

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
    _scrollToLatest();
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
    _scrollToLatest();
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

  /// 链表是 reverse 的：最新一条固定在偏移 0（视觉底部），所以「滚到最新」
  /// 就是回到 0。列表短于视口时 maxScrollExtent 为 0，offset 天然停在 0。
  void _scrollToLatest() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!scroll.hasClients) return;
      if (scroll.position.pixels <= 0) return;
      scroll.animateTo(
        0,
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
      c: context.c,
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
      onEnter: _submitFromEnter,
      onRank: () => showGameRank(context, game: 'idiom', title: '成语接龙 · 玩家排行'),
    );
  }
}

// ---------------------------------------------------------------------------
// 纯视觉层：nosh 卡片流
// ---------------------------------------------------------------------------

/// 成语接龙视图（纯视觉；golden 用默认 menu 态渲染）。
class GameIdiomView extends StatelessWidget {
  const GameIdiomView({
    super.key,
    this.c = CitroColors.light,
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
    this.onEnter,
    this.onRank,
  });

  final CitroColors c;
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
  final VoidCallback? onEnter;
  final VoidCallback? onRank;

  TextStyle _emStyle(GameIdentity id) => TextStyle(
    color: id.primaryInk,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  @override
  Widget build(BuildContext context) {
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
      // 舞台只吃内容区约束：竖屏扣除 HUD / 操作行 / 正在玩，横屏扣除左右侧栏，
      // 不再读 MediaQuery（按整屏宽算在横屏必然裁切）。
      // 但棋盘区在 SingleChildScrollView 里，高度无界：maxHeight 不可用时退回
      // 按宽度估算（w * 1.5）。横屏 / 键盘弹出时若真实高度不足，底部输入行会
      // 落到首屏外，靠整页滚动兜底——注释如实说明，尚未做到自适应。
      board: LayoutBuilder(
        builder: (context, constraints) {
          final w =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : math.min(600.0, math.max(420.0, w * 1.5));
          final id = GameIdentityScope.of(context);
          return SizedBox(
            width: w,
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(CitroColors.radii.card),
                border: Border.all(color: id.primary.withAlpha(46)),
                boxShadow: CitroColors.shadows.card(c),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CitroColors.radii.card),
                child: phase == IdiomPhase.menu
                    ? _menu(context)
                    : (phase == IdiomPhase.playing
                          ? _board(context)
                          : _result(context)),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- 菜单 --------------------------------------------------------------

  Widget _menu(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '成语接龙',
              textAlign: TextAlign.center,
              style: context.heading(size: CitroType.heading, color: c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              '上一个成语的尾字，就是你要接的读音',
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: c.ink2),
            ),
            const SizedBox(height: 18),
            _rules(context),
            const SizedBox(height: 16),
            Text(
              'AI 对战 · GLM-5.3-Flash 实时出题与判定',
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.small, color: c.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rules(BuildContext context) {
    final id = GameIdentityScope.of(context);
    const ord = ['壹', '贰', '叁', '肆'];
    final texts = <List<InlineSpan>>[
      [
        const TextSpan(text: '你与 AI 轮流接龙，'),
        TextSpan(text: '只要尾字与首字同音', style: _emStyle(id)),
        const TextSpan(text: '即可，不区分声调'),
      ],
      [
        const TextSpan(text: '每回合 '),
        TextSpan(text: '60 秒', style: _emStyle(id)),
        const TextSpan(text: '，超时即结束本局'),
      ],
      [
        const TextSpan(text: '接对一个基础 '),
        TextSpan(text: '+10 分', style: _emStyle(id)),
        const TextSpan(text: '；答对 '),
        TextSpan(text: '2 个后 ×2', style: _emStyle(id)),
        const TextSpan(text: '、'),
        TextSpan(text: '4 个后 ×4', style: _emStyle(id)),
        const TextSpan(text: '，之后每多 2 个倍率再加 2 倍'),
      ],
      [const TextSpan(text: '成语需真实存在，由 AI 判定；本局用过的不能重复')],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < texts.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _ruleRow(
            id,
            ord[i],
            TextSpan(
              style: context.body(size: CitroType.body, color: c.ink2),
              children: texts[i],
            ),
          ),
        ],
      ],
    );
  }

  Widget _ruleRow(GameIdentity id, String ord, TextSpan span) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: id.soft,
            borderRadius: BorderRadius.circular(CitroColors.radii.xs),
          ),
          alignment: Alignment.center,
          child: OrdinalGlyph(ord, color: id.primaryInk),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text.rich(span)),
      ],
    );
  }

  // --- 运行中棋盘 --------------------------------------------------------

  Widget _board(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final frac = (deadline / 60).clamp(0.0, 1.0);
    final warn = deadline <= 10;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: ListView.builder(
                  controller: scrollController,
                  // 反向列表：最新一条从底部「长」出来，短链时条目贴在输入区上方，
                  // 键盘弹出被顶掉的只是上面的旧词，最新词始终可见。
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: chain.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _chainRow(
                      context,
                      chain[chain.length - 1 - index],
                      isLast: index == 0,
                    ),
                  ),
                ),
              ),
              if (fb.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 6,
                  child: Center(child: _fbChip(context, fb)),
                ),
            ],
          ),
        ),
        CitroDivider(color: c.line),
        // 关键信息跟着输入区走：键盘抬起时上半屏被顶掉，令音 / 倒计时 /
        // 倍数集中放在输入区上方，抬起键盘也还在视线里。
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Row(
            children: [
              if (aiThinking) ...[
                Text(
                  'AI 兜底中…',
                  style: context.body(size: CitroType.small, color: c.inkSoft),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: id.soft,
                  borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                ),
                child: Text.rich(
                  TextSpan(
                    style: context.body(size: CitroType.small, color: c.ink2),
                    children: [
                      const TextSpan(text: '需接 '),
                      TextSpan(
                        text: need.isEmpty ? '—' : need,
                        style: context.body(
                          size: CitroType.body,
                          weight: CitroType.strong,
                          color: id.primaryInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 34,
                child: Text(
                  '$deadline',
                  textAlign: TextAlign.right,
                  style: context.hand(
                    size: CitroType.titleLg,
                    weight: CitroType.strong,
                    color: warn ? id.deep : c.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 58,
                child: CitroProgressBar(
                  value: frac,
                  height: 6,
                  color: warn ? id.deep : id.primary,
                  track: id.deep.withAlpha(40),
                ),
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  style: context.body(size: CitroType.small, color: c.inkSoft),
                  children: [
                    const TextSpan(text: '当前 '),
                    TextSpan(
                      text: '×${math.max(1, (count ~/ 2) * 2)}',
                      style: context.body(
                        size: CitroType.body,
                        weight: CitroType.strong,
                        color: id.primaryInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: TextField(
              controller: input,
              focusNode: focusNode,
              enabled: !aiThinking,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onEnter?.call(),
              maxLength: 64,
              style: context.body(size: CitroType.bodyLg, color: c.ink),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText: '输入成语，选候选词后回车提交',
                hintStyle: context.body(size: CitroType.body, color: c.inkSoft),
                filled: true,
                fillColor: id.soft.withAlpha(90),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                // 去掉身份红描边：输入区只用中性描边，聚焦时换主题青瓷。
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CitroColors.radii.field),
                  borderSide: BorderSide(color: c.line2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CitroColors.radii.field),
                  borderSide: BorderSide(color: c.line2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CitroColors.radii.field),
                  borderSide: BorderSide(color: c.accent, width: 1.5),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(CitroColors.radii.field),
                  borderSide: BorderSide(color: c.line2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chainRow(
    BuildContext context,
    ChainItem item, {
    bool isLast = false,
  }) {
    final id = GameIdentityScope.of(context);
    // 成语块统一身份色：soft 底 + deep 描边 + ink 字；角色只靠小标签区分。
    final bar = item.role == 'ai'
        ? id.deep
        : (item.role == 'you' ? id.primary : id.ink);
    final tagText = item.role == 'ai' ? 'AI' : (item.role == 'you' ? '你' : '起手');
    final text = item.text;
    return Container(
      decoration: BoxDecoration(
        color: id.soft,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: id.deep.withAlpha(70)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: bar),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: bar,
                            borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                          ),
                          child: Text(
                            tagText,
                            style: context.body(
                              size: CitroType.micro,
                              weight: CitroType.strong,
                              color: id.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (item.note.isNotEmpty)
                          Expanded(
                            child: Text(
                              item.note,
                              textAlign: TextAlign.right,
                              style: context.body(size: CitroType.small, color: c.inkSoft),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        style: context.heading(size: CitroType.title, color: id.ink),
                        children: [
                          if (isLast && text.isNotEmpty) ...[
                            TextSpan(text: text.substring(0, text.length - 1)),
                            TextSpan(
                              text: text.substring(text.length - 1),
                              style: TextStyle(
                                // 画在 id.soft 上：主色 3.98:1 不达 AA，
                                // 换 primaryInk（6.3:1）与其他强调文字一致。
                                color: id.primaryInk,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ] else
                            TextSpan(text: text),
                        ],
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

  // --- 结算 --------------------------------------------------------------

  Widget _result(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final titleColor = won ? id.primaryInk : id.deep;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              endTitle,
              textAlign: TextAlign.center,
              style: context.heading(size: CitroType.heading, color: titleColor),
            ),
            const SizedBox(height: 8),
            Text(
              endSub,
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: c.ink2),
            ),
            const SizedBox(height: 18),
            // 窄屏（横屏 / 小窗）改成 Wrap，三个统计块自动换行不挤爆。
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 20,
              runSpacing: 12,
              children: [
                _stat(context, '本局接龙', '$count'),
                _stat(context, '最长链', '${chain.length}'),
                _stat(context, '本局得分', '$score', accent: true),
              ],
            ),
            const SizedBox(height: 20),
            GameActionButton(
              label: '再来一局',
              primary: true,
              expand: true,
              onTap: onAgain,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value, {bool accent = false}) {
    final id = GameIdentityScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: context.body(size: CitroType.small, color: c.inkSoft)),
        const SizedBox(height: 3),
        Text(
          value,
          style: context.hand(
            size: CitroType.heading,
            weight: CitroType.strong,
            color: accent ? id.primaryInk : id.ink,
          ),
        ),
      ],
    );
  }

  // --- 共用小件 ----------------------------------------------------------

  /// 链表区顶部的错误 / AI 判定提示胶囊。
  Widget _fbChip(BuildContext context, String text) {
    final id = GameIdentityScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(color: id.primary.withAlpha(90)),
        boxShadow: CitroColors.shadows.card(c),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: context.body(
          size: CitroType.meta,
          weight: CitroType.strong,
          color: id.ink,
        ),
      ),
    );
  }
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
  const OrdinalGlyph(this.ord, {super.key, this.fontSize = 12, this.color});

  final String ord;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? context.c.ink;
    return SizedBox(
      width: fontSize * 0.92,
      height: fontSize,
      child: CustomPaint(
        painter: _OrdinalGlyphPainter(ord, fontSize, resolved),
      ),
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
