import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lpinyin/lpinyin.dart';

import '../data/idioms.dart';
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

// 保持既有契约：外部若通过本文件取得 OrdinalGlyph，仍可解析到。
export 'game_word_common.dart' show OrdinalGlyph;

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
  final rnd = GameRandom.create();
  final input = TextEditingController();
  final scroll = ScrollController();
  List<ChainItem> chain = [];
  Set<String> used = {};
  /// 当前需要接的首字**默认读音**。
  ///
  /// 只用于展示与喂给 AI —— 判定同音一律走 [_hitNeed]（按所有读法），
  /// 不要再拿它做相等比较。
  String needPinyin = '';

  /// 当前需要接的那个**字**本身 —— 判定同音要按它的所有读法算，
  /// 多音字只比默认读法会误杀（玩家接「月」接「乐(yuè)」被拒）。
  String needChar = '';

  /// 界面上的「需接」文案：把字和它的全部读法都列出来，
  /// 免得出现「显示需接 chang、实际 zhāng 也放行」的自相矛盾。
  String get _needLabel {
    if (needChar.isEmpty) return '—';
    final rs = _readings(needChar).toList()..sort();
    return rs.length <= 1 ? needChar : '$needChar（${rs.join('/')}）';
  }
  bool running = false;
  bool over = false;
  bool won = false;
  bool aiThinking = false;
  bool validating = false;
  int count = 0;
  int score = 0;
  int best = 0;
  int deadline = 60;
  late final WordToast toast;
  late final WordCountdown countdown;
  String endTitle = '时间到';
  String endSub = '60 秒内没接上，本局结束';
  final _progress = ValueNotifier<String>('');
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    best = AppState.instance.localBest('idiom');
    toast = WordToast(setState: setState, isMounted: () => mounted);
    countdown = WordCountdown(
      total: 60,
      isMounted: () => mounted,
      isRunning: () => running,
      onTick: (left) => setState(() => deadline = left),
      onTimeout: () => _finish(win: false),
    );
    _reset();
    // v1.6.4：键盘抬起时列表要停在最新的词上（用户反馈抬键盘看到的是旧词）。
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

  /// 输入框获得焦点（键盘弹出）时滚到最新一条。
  void _onFocus() {
    if (focus.hasFocus) scrollWordChainLatest(scroll);
  }

  late final KeyboardObserver _kbObserver;

  void _reset() {
    countdown.cancel();
    chain = [];
    used = {};
    needPinyin = '';
    count = 0;
    score = 0;
    running = false;
    over = false;
    won = false;
    aiThinking = false;
    validating = false;
    deadline = 60;
    toast.clear();
    input.clear();
    _progress.value = '';
    if (mounted) setState(() {});
  }

  void _start() {
    _reset();
    final seed = kIdiomSeeds[rnd.nextInt(kIdiomSeeds.length)];
    chain.add(ChainItem(seed, 'seed', '起手'));
    used.add(seed);
    needChar = seed.substring(seed.length - 1);
    needPinyin = _pinyin(needChar);
    running = true;
    countdown.start();
    setState(() {});
    focus.requestFocus();
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

  /// 生僻读法白名单：lpinyin 的字典里混着不少现代汉语基本不用的读法
  /// （乐 lào/yào、落 là/lào、说 shuì/yuè、数 shuò、女 rǔ、地 de…），
  /// 全放进去会出现「亡羊补牢(láo) → 落井下石(luò)」这种碍眼的误放。
  /// 这里只保留成语里真正会用到的读法。
  static const Map<String, Set<String>> _commonReadings = {
    '乐': {'le', 'yue'},
    '说': {'shuo'},
    '数': {'shu'},
    '女': {'nv'},
    '地': {'di'},
    '石': {'shi'},
    '大': {'da'},
    '合': {'he'},
    '种': {'zhong'},
    '车': {'che'},
    '尾': {'wei'},
    '家': {'jia'},
    '趋': {'qu'},
    '丁': {'ding'},
    '宿': {'su'},
    '会': {'hui'},
    '厂': {'chang'},
    '落': {'luo'},
    '着': {'zhuo'},
  };

  /// 一个字的可用读音（不带声调）。多音字会有多个，例如「乐」→ {le, yue}。
  Set<String> _readings(String ch) {
    if (ch.isEmpty) return const {};
    try {
      final all = PinyinHelper.convertToPinyinArray(
        ch.substring(0, 1),
        PinyinFormat.WITHOUT_TONE,
      ).map((e) => e.toLowerCase()).toSet();
      final common = _commonReadings[ch.substring(0, 1)];
      // 白名单只用来**删掉**生僻读法；万一字典给的读音不在白名单里
      // （版本差异），保留字典原样，避免把能接的词误杀。
      if (common != null && all.containsAll(common)) {
        return all.intersection(common);
      }
      return all;
    } catch (_) {
      return {ch.toLowerCase()};
    }
  }

  /// 首字与 needChar 是否同音（任一方任一读法相同即可）。
  bool _hitNeed(String firstChar) {
    final a = _readings(firstChar);
    if (a.isEmpty) return false;
    return a.any(_readings(needChar).contains);
  }

  void _submitFromEnter() {
    if (!wordEnterGuardPasses(input)) {
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
    if (!_hitNeed(raw.substring(0, 1))) {
      _feedback('首字读音要接上「$_needLabel」，再想想');
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
    setState(() => toast.fb = 'AI 判定中…');
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
    final mult = wordMultiplier(count);
    score += 10 * mult;
    input.clear();
    if (aiVerified) _feedback('AI 判定：「$raw」通过 ✓');
    setState(() {
      chain.add(ChainItem(raw, 'you', '接龙 ${mult > 1 ? '×$mult' : ''}'));
      needChar = raw.substring(raw.length - 1);
      needPinyin = _pinyin(needChar);
      aiThinking = true;
      if (!aiVerified) toast.fb = '';
    });
    GameSfx.eat();
    _progress.value = '接龙 $count · 得分 $score';
    scrollWordChainLatest(scroll);
    countdown.cancel();
    Future.delayed(const Duration(milliseconds: 650), _aiTurn);
  }

  Future<void> _aiTurn() async {
    if (!mounted || !running) return;
    final candidates = kIdioms
        .where((e) => !used.contains(e) && _hitNeed(e.characters.first))
        .toList();
    String? pick;
    if (candidates.isEmpty) {
      // 本地词库接不上时才走 AI 兜底（AiService → glm-5.3-flash）。
      setState(() => toast.fb = 'AI 兜底中…');
      pick = await AiService.suggestIdiom(
        last: chain.isEmpty ? '' : chain.last.text,
        char: needChar,
        pinyin: _readings(needChar).join('/'),
        used: used.toList(),
      );
      if (!mounted || !running) return;
      if (pick == null ||
          pick.length != 4 ||
          used.contains(pick) ||
          !_hitNeed(pick.substring(0, 1))) {
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
      needChar = chosen.substring(chosen.length - 1);
      needPinyin = _pinyin(needChar);
      aiThinking = false;
      toast.fb = '';
    });
    countdown.start();
    deadline = countdown.left;
    scrollWordChainLatest(scroll);
    focus.requestFocus();
  }

  void _feedback(String msg) => toast.show(msg);

  void _finish({required bool win}) {
    if (!running) return;
    countdown.cancel();
    if (win) score += 10 * wordMultiplier(count);
    running = false;
    over = true;
    won = win;
    aiThinking = false;
    validating = false;
    toast.clear();
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
      need: _needLabel,
      deadline: deadline,
      aiThinking: aiThinking,
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
      onRank: () => showGameLeaderboard(context, game: 'idiom', title: '成语接龙 · 玩家排行'),
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

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      hideActionsOnKeyboard: true,
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
        WordSeg('你与 AI 轮流接龙，'),
        WordSeg('只要尾字与首字同音', em: true),
        WordSeg('即可，不区分声调'),
      ],
      [
        WordSeg('每回合 '),
        WordSeg('60 秒', em: true),
        WordSeg('，超时即结束本局'),
      ],
      [
        WordSeg('接对一个基础 '),
        WordSeg('+10 分', em: true),
        WordSeg('；答对 '),
        WordSeg('2 个后 ×2', em: true),
        WordSeg('、'),
        WordSeg('4 个后 ×4', em: true),
        WordSeg('，之后每多 2 个倍率再加 2 倍'),
      ],
      [WordSeg('成语需真实存在，由 AI 判定；本局用过的不能重复')],
    ];
    return WordMenuShell(
      title: '成语接龙',
      subtitle: '上一个成语的尾字，就是你要接的读音',
      rules: texts,
      aiLine: 'AI 对战 · GLM-5.3-Flash 实时出题与判定',
    );
  }

  // --- 运行中棋盘 --------------------------------------------------------

  Widget _board(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final frac = (deadline / 60).clamp(0.0, 1.0);
    final warn = deadline <= 10;
    return Column(
      children: [
        WordChainPanel(
          scrollController: scrollController,
          itemCount: chain.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _chainRow(
              context,
              chain[chain.length - 1 - index],
              isLast: index == 0,
            ),
          ),
          fb: fb,
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
              // 多读法全列出来时胶囊会变长（「需接 差（cha/chai/ci）」），
              // 用 Flexible 兜住，窄屏换成两行而不是把整行顶爆。
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: id.soft,
                    borderRadius: BorderRadius.circular(
                      CitroColors.radii.chip,
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(
                      style: context.body(size: CitroType.small, color: c.ink2),
                      children: [
                        const TextSpan(text: '需接 '),
                        TextSpan(
                          text: need,
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
                      text: '×${wordMultiplier(count)}',
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
        WordInputRow(
          controller: input,
          focusNode: focusNode,
          enabled: !aiThinking,
          hintText: '输入成语，选候选词后点发送',
          maxLength: 64,
          onEnter: onEnter,
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
    return WordChainRow(
      bar: bar,
      tagText: tagText,
      meta: item.note,
      showMeta: item.note.isNotEmpty,
      body: TextSpan(
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
    );
  }

  // --- 结算 --------------------------------------------------------------

  Widget _result(BuildContext context) {
    return WordResultPanel(
      endTitle: endTitle,
      endSub: endSub,
      won: won,
      stats: [
        WordStat(label: '本局接龙', value: '$count'),
        WordStat(label: '最长链', value: '${chain.length}'),
        WordStat(label: '本局得分', value: '$score', accent: true),
      ],
      onAgain: onAgain,
    );
  }
}
