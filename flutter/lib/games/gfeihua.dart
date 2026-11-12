import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/poems.dart';
import '../services/ai.dart';
import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'game_identity.dart';
import 'game_ui.dart';
// 序数印章字「壹贰叁肆」在内置子集字体里缺字，统一复用成语接龙页里的
// OrdinalGlyph（内嵌 ZCOOL KuaiLe 字形轮廓），两页保持同一套渲染。
import 'gidiom.dart' show OrdinalGlyph;

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

  late final KeyboardObserver _kbObserver;

  void _onFocus() {
    if (focus.hasFocus) _scrollToLatest();
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
    _scrollToLatest();
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
    _scrollToLatest();
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

  /// 链表是 reverse 的：最新一句固定在偏移 0（视觉底部），所以「滚到最新」
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

  @override
  Widget build(BuildContext context) {
    return GameFeihuaView(
      c: context.c,
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
// 纯视觉层：nosh 卡片流
// ---------------------------------------------------------------------------

/// 飞花令视图（纯视觉；golden 用默认 menu 态渲染）。
class GameFeihuaView extends StatelessWidget {
  const GameFeihuaView({
    super.key,
    this.c = CitroColors.light,
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

  final CitroColors c;
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

  TextStyle _emStyle(GameIdentity id) => TextStyle(
    color: id.primaryInk,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      hideActionsOnKeyboard: true,
      gameKey: 'gfeihua',
      title: '飞花令',
      boardGap: 12,
      liveProgress: liveProgress,
      // 顶栏只留两粒：得分 / 最佳（对句数在底部条外不再重复占位）。
      pills: [
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
      // 舞台只吃内容区约束：竖屏扣除 HUD / 操作行 / 正在玩，横屏扣除左右侧栏，
      // 不再读 MediaQuery（按整屏宽算在横屏必然裁切）。
      // 但棋盘区在 SingleChildScrollView 里，高度无界：maxHeight 不可用时退回
      // 按宽度估算（w * 1.5）。横屏 / 键盘弹出时若真实高度不足，底部输入行会
      // 落到首屏外，靠整页滚动兜底——注释如实说明，尚未做到自适应。
      board: LayoutBuilder(
        builder: (context, constraints) {
          final w =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
          // 键盘弹出时压缩棋盘：棋盘是固定高（滚动区无界），不压的话
          // 输入行和下面的「开始飞花令」会被顶到首屏之外。
          final kb = MediaQuery.viewInsetsOf(context).bottom;
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : math.max(
                  220.0,
                  math.min(600.0, math.max(420.0, w * 1.5)) - kb,
                );
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
                child: phase == FeihuaPhase.menu
                    ? _menu(context)
                    : (phase == FeihuaPhase.playing
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
              '飞花令',
              textAlign: TextAlign.center,
              style: context.heading(size: CitroType.heading, color: c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              '说出含有令字的诗句',
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: c.ink2),
            ),
            const SizedBox(height: 18),
            _rules(context),
            const SizedBox(height: 16),
            Text(
              'AI 对战 · GLM-5.3-Flash 实时抽字与对诗',
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
        const TextSpan(text: '系统随机抽一个'),
        TextSpan(text: '令字', style: _emStyle(id)),
        const TextSpan(text: '，你与 AI 轮流说出含这个字的诗句'),
      ],
      [
        const TextSpan(text: '每回合 '),
        TextSpan(text: '120 秒', style: _emStyle(id)),
        const TextSpan(text: '，超时即结束本局'),
      ],
      [
        const TextSpan(text: '每句基础 '),
        TextSpan(text: '+10 分', style: _emStyle(id)),
        const TextSpan(text: '；答对 '),
        TextSpan(text: '2 句后 ×2', style: _emStyle(id)),
        const TextSpan(text: '、'),
        TextSpan(text: '4 句后 ×4', style: _emStyle(id)),
        const TextSpan(text: '，之后每多 2 句倍率再加 2 倍'),
      ],
      [
        const TextSpan(text: '答满 2 句后即可'),
        TextSpan(text: '随时换个令字', style: _emStyle(id)),
        const TextSpan(text: '，换字不影响已累计的倍数'),
      ],
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
    final frac = (seconds / 120).clamp(0.0, 1.0);
    final warn = seconds <= 10;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: ListView.builder(
                  controller: scrollController,
                  // 反向列表：最新一句从底部「长」出来，短链时条目贴在输入区上方，
                  // 键盘弹出被顶掉的只是上面的旧句，最新句始终可见。
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: chain.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _chainRow(context, chain[chain.length - 1 - index]),
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
        // 关键信息跟着输入区走：键盘抬起时上半屏被顶掉，令字 / 倒计时集中
        // 放在输入区上方；换字入口留在同一行右侧。
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Row(
            children: [
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
                      const TextSpan(text: '令字 '),
                      TextSpan(
                        text: ch.isEmpty ? '—' : ch,
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
                  '$seconds',
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
              // 换字按钮 + 解锁提示：对句数从棋盘移除后，count < 2 的解锁条件
              // 在画面上没有数字依据，补一句最小提示说明还差几句。
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: count >= 2 ? 1 : 0.4,
                    child: GestureDetector(
                      onTap: onSwap,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            CitroColors.radii.chip,
                          ),
                          border: Border.all(color: id.primary.withAlpha(80)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '换个令字',
                          style: context.body(
                            size: CitroType.meta,
                            weight: CitroType.strong,
                            color: id.primaryInk,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (count < 2) ...[
                    const SizedBox(height: 4),
                    // 浅底用 primaryInk：深底主题下深色墨迹会糊，这里垫一层
                    // id.soft 浅端，暗色主题也保持可读。
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: id.soft,
                        borderRadius: BorderRadius.circular(
                          CitroColors.radii.chip,
                        ),
                      ),
                      child: Text(
                        '再对 ${2 - count} 句解锁',
                        style: context.body(
                          size: CitroType.small,
                          color: id.primaryInk,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: input,
                    focusNode: focusNode,
                    enabled: !thinking,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onEnter?.call(),
                    maxLength: 128,
                    style: context.body(size: CitroType.bodyLg, color: c.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: '输入一句诗，选候选词后点发送',
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
              const SizedBox(width: 8),
              // 发送按钮：键盘弹出时也能直接点，不必依赖键盘右下角的回车。
              _FhSendButton(
                enabled: !thinking,
                onTap: () => onEnter?.call(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chainRow(BuildContext context, FhItem item) {
    final id = GameIdentityScope.of(context);
    // 诗卡统一身份色：soft 底 + deep 描边 + ink 字；左对齐，出处右对齐。
    final bar = item.role == 'ai' ? id.deep : id.primary;
    final tagText = item.role == 'ai' ? 'AI' : '你';
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
                        Expanded(
                          child: Text(
                            item.meta,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.body(size: CitroType.small, color: c.inkSoft),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text.rich(_markedLine(context, item.line)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 诗句里的令字用身份主色高亮。
  TextSpan _markedLine(BuildContext context, String line) {
    final id = GameIdentityScope.of(context);
    final base = context.heading(size: CitroType.title, color: id.ink);
    if (ch.isEmpty || !line.contains(ch)) {
      return TextSpan(style: base, text: line);
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
              // 画在 id.soft 上：主色 3.88:1 不达 AA，换 primaryInk（6.4:1）。
              style: TextStyle(
                color: id.primaryInk,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ],
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
                _stat(context, '本局对句', '$count'),
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

/// 输入区右侧的发送按钮（48 高，和输入框同高）。
class _FhSendButton extends StatelessWidget {
  const _FhSendButton({required this.onTap, this.enabled = true});

  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final id = GameIdentityScope.of(context);
    return Pressable(
      onTap: enabled ? onTap : null,
      hoverLift: 0,
      hoverShadow: false,
      borderRadius: BorderRadius.circular(CitroColors.radii.button),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? id.primary : id.soft,
          borderRadius: BorderRadius.circular(CitroColors.radii.button),
        ),
        child: AppIcon(
          strokeSvg(AppIcons.arrowRight, width: 2.2),
          size: 18,
          color: enabled ? id.onPrimary : c.inkSoft,
        ),
      ),
    );
  }
}
