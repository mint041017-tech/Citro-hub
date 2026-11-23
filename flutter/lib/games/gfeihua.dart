import 'dart:async';

import 'package:flutter/material.dart';

import '../data/poems.dart';
import '../services/ai.dart';
import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'game_ui.dart';
import 'game_common.dart' show showGameLeaderboard;
import 'game_random.dart';
import 'game_word_common.dart';

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
  final rnd = GameRandom.create();
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
  late final WordToast toast;
  late final WordCountdown countdown;
  String endTitle = '时间到';
  String endSub = '120 秒内没接上，本局结束';
  final _progress = ValueNotifier<String>('');
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    best = AppState.instance.localBest('feihua');
    toast = WordToast(setState: setState, isMounted: () => mounted);
    countdown = WordCountdown(
      total: 120,
      isMounted: () => mounted,
      isRunning: () => running,
      onTick: (left) => setState(() => seconds = left),
      onTimeout: () => _end(false),
    );
    // v1.6.4：键盘抬起时列表停在最新一句上
    _kbObserver = KeyboardObserver(() => scrollWordChainLatest(scroll));
    WidgetsBinding.instance.addObserver(_kbObserver);
    focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_kbObserver);
    focus.removeListener(_onFocus);
    countdown.dispose();
    toast.dispose();
    input.dispose();
    scroll.dispose();
    focus.dispose();
    _progress.dispose();
    super.dispose();
  }

  late final KeyboardObserver _kbObserver;

  void _onFocus() {
    if (focus.hasFocus) scrollWordChainLatest(scroll);
  }

  void _start() {
    countdown.cancel();
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
    toast.clear();
    ch = kFeihuaChars[rnd.nextInt(kFeihuaChars.length)];
    input.clear();
    setState(() {});
    countdown.start();
    focus.requestFocus();
    _progress.value = '令字 $ch';
  }

  void _submitFromEnter() {
    if (!wordEnterGuardPasses(input)) {
      _feedback('请先选好中文候选词，再回车提交');
      return;
    }
    _submit();
  }

  /// 这句（或它的半句/整句）是不是已经说过。
  ///
  /// [used] 里存的是归一化键（见 [poemKey]），所以同一句诗的
  /// 不同标点写法、以及玩家打的半句，都算同一条。
  bool _isUsed(String line) {
    final key = poemKey(canonicalPoemLine(line));
    if (used.contains(key)) return true;
    // 词库外的句子（AI 判定收下的）没有归一化键，退回原文互含判断。
    for (final u in used) {
      if (u.length < 5) continue;
      if (line.contains(u) || u.contains(line)) return true;
    }
    return false;
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
    if (_isUsed(raw)) {
      _feedback('这句已经说过了');
      return;
    }
    // 半句命中词库整句时直接收下，不必再等 AI 判定。
    final canon = canonicalPoemLine(raw);
    if (canon == raw && !kPoemLines.any((p) => p.line == raw)) {
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
    setState(() => toast.fb = 'AI 判定中…');
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
    used.add(poemKey(canonicalPoemLine(raw)));
    count++;
    final mult = wordMultiplier(count);
    score += 10 * mult;
    input.clear();
    if (aiVerified) _feedback('AI 判定：「$raw」通过 ✓');
    setState(() {
      chain.add(FhItem(raw, '你', 'you'));
      thinking = true;
      if (!aiVerified) toast.fb = '';
    });
    GameSfx.eat();
    _progress.value = '对句 $count · 得分 $score';
    scrollWordChainLatest(scroll);
    countdown.cancel();
    Future.delayed(const Duration(milliseconds: 650), _aiTurn);
  }

  Future<void> _aiTurn() async {
    if (!mounted || !running) return;
    final pool = kPoemLines
        .where((p) => p.line.contains(ch) && !used.contains(poemKey(p.line)))
        .toList();
    String? line;
    String? meta;
    if (pool.isEmpty) {
      // 本地诗句库对不上时才走 AI 兜底（AiService → glm-5.3-flash）。
      setState(() => toast.fb = 'AI 兜底中…');
      final suggestion = await AiService.suggestPoem(
        char: ch,
        used: used.map(canonicalPoemLine).toList(),
      );
      if (!mounted || !running) return;
      if (suggestion == null ||
          _isUsed(suggestion.line) ||
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
    used.add(poemKey(canonicalPoemLine(line)));
    GameSfx.flip();
    setState(() {
      chain.add(FhItem(line!, meta!, 'ai'));
      thinking = false;
      toast.fb = '';
    });
    countdown.start();
    seconds = countdown.left;
    scrollWordChainLatest(scroll);
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
    countdown.start();
    seconds = countdown.left;
    _progress.value = '令字 $ch';
    AppToast.show(context, '换令字：$ch');
  }

  void _feedback(String msg) => toast.show(msg);

  void _end(bool playerWon) {
    if (!running) return;
    countdown.cancel();
    running = false;
    over = true;
    won = playerWon;
    thinking = false;
    validating = false;
    if (playerWon) {
      final mult = wordMultiplier(count);
      score += 10 * mult;
    }
    toast.clear();
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
      fb: toast.fb,
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
      onRank: () => showGameLeaderboard(context, game: 'feihua', title: '飞花令 · 玩家排行'),
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
      board: WordBoardShell(
        colors: c,
        phaseIndex: phase.index,
        menu: _menu(context),
        playing: _board(context),
        result: _result(context),
      ),
    );
  }

  // --- 菜单 --------------------------------------------------------------

  Widget _menu(BuildContext context) {
    const texts = <List<WordSeg>>[
      [
        WordSeg('系统随机抽一个'),
        WordSeg('令字', em: true),
        WordSeg('，你与 AI 轮流说出含这个字的诗句'),
      ],
      [
        WordSeg('每回合 '),
        WordSeg('120 秒', em: true),
        WordSeg('，超时即结束本局'),
      ],
      [
        WordSeg('每句基础 '),
        WordSeg('+10 分', em: true),
        WordSeg('；答对 '),
        WordSeg('2 句后 ×2', em: true),
        WordSeg('、'),
        WordSeg('4 句后 ×4', em: true),
        WordSeg('，之后每多 2 句倍率再加 2 倍'),
      ],
      [
        WordSeg('答满 2 句后即可'),
        WordSeg('随时换个令字', em: true),
        WordSeg('，换字不影响已累计的倍数'),
      ],
    ];
    return WordMenuShell(
      title: '飞花令',
      subtitle: '说出含有令字的诗句',
      rules: texts,
      aiLine: 'AI 对战 · GLM-5.3-Flash 实时抽字与对诗',
    );
  }

  // --- 运行中棋盘 --------------------------------------------------------

  Widget _board(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final frac = (seconds / 120).clamp(0.0, 1.0);
    final warn = seconds <= 10;
    return Column(
      children: [
        WordChainPanel(
          scrollController: scrollController,
          itemCount: chain.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _chainRow(context, chain[chain.length - 1 - index]),
          ),
          fb: fb,
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
        WordInputRow(
          controller: input,
          focusNode: focusNode,
          enabled: !thinking,
          hintText: '输入一句诗，选候选词后点发送',
          maxLength: 128,
          onEnter: onEnter,
        ),
      ],
    );
  }

  Widget _chainRow(BuildContext context, FhItem item) {
    final id = GameIdentityScope.of(context);
    // 诗卡统一身份色：soft 底 + deep 描边 + ink 字；左对齐，出处右对齐。
    final bar = item.role == 'ai' ? id.deep : id.primary;
    final tagText = item.role == 'ai' ? 'AI' : '你';
    return WordChainRow(
      bar: bar,
      tagText: tagText,
      meta: item.meta,
      body: _markedLine(context, item.line),
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
    return WordResultPanel(
      endTitle: endTitle,
      endSub: endSub,
      won: won,
      stats: [
        WordStat(label: '本局对句', value: '$count'),
        WordStat(label: '最长链', value: '${chain.length}'),
        WordStat(label: '本局得分', value: '$score', accent: true),
      ],
      onAgain: onAgain,
    );
  }
}
