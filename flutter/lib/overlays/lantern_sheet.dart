import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/lantern_api.dart';
import '../services/prefs.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'auth_modal.dart';

const _lanternHelloPrefix = 'chimu_lantern_popup_';

Future<void> showLanternSheet(BuildContext context) async {
  final window = LanternApi.currentWindow();
  if (window != null && !_helloSeenToday()) {
    final enter = await showCitroDialog<bool>(
      context,
      builder: (_) => _LanternWelcome(window: window),
    );
    await _markHelloSeenToday();
    if (enter != true || !context.mounted) return;
  }
  if (!context.mounted) return;
  await showCitroDialog(context, builder: (_) => const _LanternDialog());
}

Future<void> showLanternWelcomeIfNeeded(BuildContext context) async {
  final window = LanternApi.currentWindow();
  if (window == null || _helloSeenToday() || !context.mounted) return;
  final enter = await showCitroDialog<bool>(
    context,
    builder: (_) => _LanternWelcome(window: window),
  );
  await _markHelloSeenToday();
  if (enter != true || !context.mounted) return;
  await showCitroDialog(context, builder: (_) => const _LanternDialog());
}

bool _helloSeenToday() {
  try {
    return Prefs.getString('$_lanternHelloPrefix${LanternApi.dayKey()}') == '1';
  } catch (_) {
    return true;
  }
}

Future<void> _markHelloSeenToday() async {
  try {
    await Prefs.setString('$_lanternHelloPrefix${LanternApi.dayKey()}', '1');
  } catch (_) {
    // 本地存储不可用时仍可进入活动。
  }
}

class _LanternWelcome extends StatelessWidget {
  final LanternWindow window;

  const _LanternWelcome({required this.window});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      maxWidth: 390,
      showClose: false,
      tapeColor: c.tape3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '🌕',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 54),
          ),
          const SizedBox(height: 8),
          Text(
            '中秋猜灯谜',
            textAlign: TextAlign.center,
            style: context.heading(size: 27),
          ),
          const SizedBox(height: 12),
          Text(
            '月圆人圆，灯谜开猜。\n三十道灯谜，答对一题记一分。\n请登录后作答，${window.welcomeDeadline} 收卷。',
            textAlign: TextAlign.center,
            style: context.body(size: 13.5, color: c.ink2, height: 1.75),
          ),
          const SizedBox(height: 12),
          Text(
            '请豆姐帮忙的罚一个月饼！！！',
            textAlign: TextAlign.center,
            style: context.body(
              size: 13,
              weight: FontWeight.w700,
              color: const Color(0xFF7A2D12),
            ),
          ),
          const SizedBox(height: 22),
          AccentButton(
            text: '进灯谜摊',
            onTap: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 10),
          AccentButton(
            text: '稍后再来',
            outlined: true,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

class _LanternDialog extends StatefulWidget {
  const _LanternDialog();

  @override
  State<_LanternDialog> createState() => _LanternDialogState();
}

class _LanternDialogState extends State<_LanternDialog> {
  final _controllers = <int, TextEditingController>{
    for (final riddle in LanternApi.fallbackRiddles)
      riddle.id: TextEditingController(),
  };
  final _focusNodes = <int, FocusNode>{
    for (final riddle in LanternApi.fallbackRiddles) riddle.id: FocusNode(),
  };
  final _emojiController = TextEditingController();
  final _emojiFocus = FocusNode();
  final _messages = <int, String>{};
  final _submitting = <int>{};

  Timer? _pollTimer;
  LanternSnapshot? _state;
  String? _error;
  String? _emojiMessage;
  bool _loading = true;
  bool _requestBusy = false;
  bool _emojiBusy = false;
  bool _boardTab = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_load(quiet: true)),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _emojiController.dispose();
    _emojiFocus.dispose();
    super.dispose();
  }

  bool get _typing =>
      _emojiFocus.hasFocus || _focusNodes.values.any((node) => node.hasFocus);

  bool get _open => _state?.open == true && LanternApi.currentWindow() != null;

  Future<void> _load({bool quiet = false, bool force = false}) async {
    if (_requestBusy && quiet) return;
    _requestBusy = true;
    if (!quiet && mounted) {
      setState(() {
        _loading = _state == null;
        _error = null;
      });
    }
    try {
      final fresh = await LanternApi.state();
      if (!mounted) return;
      _state = fresh;
      // 轮询期间保留正在输入的表单与焦点，提交后强制刷新。
      if (!quiet || force || !_typing) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (!mounted || quiet) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    } finally {
      _requestBusy = false;
    }
  }

  Future<void> _login() async {
    await showAuthModal(context);
    if (mounted) await _load(force: true);
  }

  Future<void> _answer(LanternRiddle riddle) async {
    if (!AppState.instance.loggedIn) {
      setState(() => _messages[riddle.id] = '先登录再猜');
      await _login();
      return;
    }
    final answer = _controllers[riddle.id]!.text.trim();
    if (answer.isEmpty) {
      setState(() => _messages[riddle.id] = '写个答案呀');
      return;
    }
    if (_submitting.contains(riddle.id)) return;
    setState(() {
      _submitting.add(riddle.id);
      _messages.remove(riddle.id);
    });
    try {
      final result = await LanternApi.answer(riddle.id, answer);
      if (!mounted) return;
      if (result['ok'] == true) {
        _controllers[riddle.id]!.clear();
        _messages[riddle.id] = '猜中啦！';
      } else if (result['err'] != null) {
        _messages[riddle.id] = '${result['err']}';
      } else {
        _messages[riddle.id] = '菜！';
        AppToast.show(context, '菜！', duration: const Duration(seconds: 1));
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      _messages[riddle.id] = error.code == 401 ? '先登录再猜' : error.message;
      if (error.code == 401) await _login();
    } catch (_) {
      if (mounted) _messages[riddle.id] = '网络开小差';
    } finally {
      if (mounted) setState(() => _submitting.remove(riddle.id));
    }
    if (mounted) await _load(quiet: true, force: true);
  }

  Future<void> _drawEmoji() async {
    if (_emojiBusy || !_open) return;
    setState(() {
      _emojiBusy = true;
      _emojiMessage = null;
    });
    try {
      await LanternApi.drawEmoji();
      if (mounted) await _load(quiet: true, force: true);
    } catch (error) {
      if (mounted) setState(() => _emojiMessage = '$error');
    } finally {
      if (mounted) setState(() => _emojiBusy = false);
    }
  }

  Future<void> _answerEmoji() async {
    if (_emojiBusy || !_open) return;
    final answer = _emojiController.text.trim();
    if (answer.isEmpty) {
      setState(() => _emojiMessage = '写个答案呀');
      return;
    }
    setState(() {
      _emojiBusy = true;
      _emojiMessage = null;
    });
    try {
      final result = await LanternApi.answerEmoji(answer);
      if (!mounted) return;
      if (result['ok'] == true) {
        _emojiController.clear();
        _emojiMessage = '猜中 +0.5！';
        // 原版规则：答对后自动抽取下一题。
        await LanternApi.drawEmoji();
      } else if (result['err'] != null) {
        _emojiMessage = '${result['err']}';
      } else {
        _emojiMessage = '菜！';
        AppToast.show(context, '菜！', duration: const Duration(seconds: 1));
      }
      if (mounted) await _load(quiet: true, force: true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _emojiMessage = error.message);
      if (error.code == 401) await _login();
    } catch (_) {
      if (mounted) setState(() => _emojiMessage = '网络开小差');
    } finally {
      if (mounted) setState(() => _emojiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final content = compact
        ? (_boardTab ? _buildBoard(c) : _buildGuess(c))
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 205, child: _buildBoard(c)),
              const SizedBox(width: 18),
              Expanded(child: _buildGuess(c)),
            ],
          );
    return PaperDialog(
      maxWidth: compact ? 460 : 1000,
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 22,
        40,
        compact ? 16 : 22,
        compact ? 18 : 22,
      ),
      tapeColor: c.tape3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(c, compact),
          const SizedBox(height: 12),
          _buildStatus(c),
          if (compact) ...[const SizedBox(height: 12), _buildMobileTabs(c)],
          if (_loading && _state == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_error != null) _buildError(c),
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }

  Widget _buildHeader(CitroColors c, bool compact) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('🌕', style: TextStyle(fontSize: compact ? 30 : 36)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('猜灯谜', style: context.heading(size: 24)),
              Text(
                'Mid-Autumn · Lantern Riddles',
                style: context.display(size: 12, color: c.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(width: 34),
      ],
    );
  }

  Widget _buildStatus(CitroColors c) {
    final state = _state;
    final window = LanternApi.currentWindow();
    final closedAfter = state?.closedAfter.isNotEmpty == true
        ? state!.closedAfter
        : (window?.closedAfter ?? '次日 03:00');
    final text = _open
        ? '灯谜日 ${state?.date ?? window?.date ?? ''} · 可作答 · $closedAfter 收卷'
        : '已收卷 · $closedAfter 截止';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _open ? c.mintSoft : c.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _open ? c.mintLine : c.line),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: context.body(
          size: 12,
          weight: FontWeight.w600,
          color: _open ? c.mintInk : c.inkSoft,
        ),
      ),
    );
  }

  Widget _buildError(CitroColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '灯谜服务开小差了… $_error',
              style: context.body(size: 11.5, color: c.stamp),
            ),
          ),
          TextButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildMobileTabs(CitroColors c) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabButton('猜谜', !_boardTab, () {
              setState(() => _boardTab = false);
            }),
          ),
          Expanded(
            child: _tabButton('排行榜', _boardTab, () {
              setState(() => _boardTab = true);
            }),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String text, bool selected, VoidCallback onTap) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        decoration: BoxDecoration(
          color: selected ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: context.body(
            size: 13,
            weight: FontWeight.w700,
            color: selected ? const Color(0xFF2E2C22) : c.inkSoft,
          ),
        ),
      ),
    );
  }

  Widget _buildBoard(CitroColors c) {
    final board = _state?.board ?? const <LanternBoardEntry>[];
    final me = _state?.meName;
    return PaperCard(
      padding: const EdgeInsets.all(14),
      color: c.dark ? c.surface2 : c.noteY,
      shadow: PaperShadow.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, size: 20, color: c.accentInk),
              const SizedBox(width: 7),
              Text('灯谜榜', style: context.heading(size: 18)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '答对一题记 1 分\n同分比谁先解出',
            style: context.body(size: 11, color: c.inkSoft, height: 1.55),
          ),
          const SizedBox(height: 12),
          if (board.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Text(
                '暂无上榜，来当第一人',
                textAlign: TextAlign.center,
                style: context.body(size: 12, color: c.inkSoft),
              ),
            )
          else
            for (var i = 0; i < board.length; i++) ...[
              _rankItem(board[i], i, me),
              if (i != board.length - 1) const SizedBox(height: 7),
            ],
        ],
      ),
    );
  }

  Widget _rankItem(LanternBoardEntry entry, int index, String? me) {
    final c = context.c;
    final mine = entry.name == me;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? c.hl : c.surface.withAlpha(c.dark ? 60 : 170),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: mine ? c.accentLt : c.line),
      ),
      child: Row(
        children: [
          Container(
            width: 23,
            height: 23,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == 0 ? c.accent : c.line2,
            ),
            child: Text(
              '${index + 1}',
              style: context.display(
                size: 12,
                weight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(
                size: 12,
                weight: mine ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            '${_score(entry.score)} 分',
            style: context.body(
              size: 11.5,
              weight: FontWeight.w700,
              color: c.accentInk,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuess(CitroColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilters(c),
        const SizedBox(height: 12),
        _buildRiddleGrid(c),
        const SizedBox(height: 18),
        _buildEmoji(c),
      ],
    );
  }

  Widget _buildFilters(CitroColors c) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '三十道灯谜',
            style: context.body(
              size: 12,
              weight: FontWeight.w700,
              color: c.inkSoft,
            ),
          ),
        ),
        _filterButton('全部', 'all'),
        const SizedBox(width: 5),
        _filterButton('未中', 'open'),
        const SizedBox(width: 5),
        _filterButton('已中', 'solved'),
      ],
    );
  }

  Widget _filterButton(String label, String value) {
    final c = context.c;
    final selected = _filter == value;
    return Pressable(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.accent2 : c.line2),
        ),
        child: Text(
          label,
          style: context.body(
            size: 11,
            weight: FontWeight.w600,
            color: selected ? const Color(0xFF2E2C22) : c.inkSoft,
          ),
        ),
      ),
    );
  }

  bool _solvedByMe(LanternRiddle riddle) {
    final state = _state;
    if (state == null) return false;
    return state.meSolved.contains(riddle.id) ||
        riddle.solvers.any((solver) => solver.name == state.meName);
  }

  List<LanternRiddle> get _visibleRiddles {
    final source = _state?.riddles.isNotEmpty == true
        ? _state!.riddles
        : LanternApi.fallbackRiddles;
    return source
        .where((riddle) {
          final solved = _solvedByMe(riddle);
          return switch (_filter) {
            'open' => !solved,
            'solved' => solved,
            _ => true,
          };
        })
        .toList(growable: false);
  }

  Widget _buildRiddleGrid(CitroColors c) {
    final riddles = _visibleRiddles;
    if (riddles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Text(
          '这个筛选下没有灯谜',
          textAlign: TextAlign.center,
          style: context.body(size: 12, color: c.inkSoft),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final riddle in riddles)
              SizedBox(width: width, child: _riddleCard(riddle)),
          ],
        );
      },
    );
  }

  Widget _riddleCard(LanternRiddle riddle) {
    final c = context.c;
    final solved = _solvedByMe(riddle);
    final me = _state?.meName;
    final solvers = riddle.solvers;
    final solverText = solvers.isEmpty
        ? '尚无人猜中'
        : '${solvers.map((solver) => solver.name == me ? '我' : solver.name).join(' · ')} 猜中';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: solved ? c.mintSoft : c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: solved ? c.mintLine : c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                riddle.id.toString().padLeft(2, '0'),
                style: context.display(
                  size: 21,
                  weight: FontWeight.w700,
                  color: solved ? c.mintInk : c.accentInk,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    riddle.question,
                    style: context.body(
                      size: 13,
                      weight: FontWeight.w600,
                      color: c.ink,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            solverText,
            style: context.body(
              size: 10.5,
              color: solved ? c.mintInk : c.inkSoft,
            ),
          ),
          const SizedBox(height: 9),
          if (_open)
            Row(
              children: [
                Expanded(child: _answerInput(riddle)),
                const SizedBox(width: 7),
                AccentButton(
                  text: '揭榜',
                  width: 64,
                  height: 40,
                  loading: _submitting.contains(riddle.id),
                  onTap: _submitting.contains(riddle.id)
                      ? null
                      : () => _answer(riddle),
                ),
              ],
            )
          else
            Text('已收卷', style: context.body(size: 11.5, color: c.stamp)),
          SizedBox(
            height: 20,
            child: _messages[riddle.id] == null
                ? null
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _messages[riddle.id]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: 10.5,
                        color: _messages[riddle.id] == '猜中啦！'
                            ? c.mintInk
                            : c.stamp,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _answerInput(LanternRiddle riddle) {
    final c = context.c;
    return TextField(
      controller: _controllers[riddle.id],
      focusNode: _focusNodes[riddle.id],
      maxLength: 40,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _answer(riddle),
      style: context.body(size: 13),
      cursorColor: c.accent,
      decoration: InputDecoration(
        hintText: '写谜底…',
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: c.line2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: c.line2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: c.accent),
        ),
      ),
    );
  }

  Widget _buildEmoji(CitroColors c) {
    final emoji = _state?.emoji;
    final solved = emoji?.solved.length ?? 0;
    final total = emoji?.total ?? 30;
    return PaperCard(
      padding: const EdgeInsets.all(15),
      color: c.dark ? c.surface2 : c.noteB,
      shadow: PaperShadow.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('附加题 · emoji 猜成语', style: context.heading(size: 17)),
                  const SizedBox(height: 3),
                  Text(
                    '抽取制 · 答对自动下一题 · 每题 0.5 分 · 共 30 题',
                    style: context.body(size: 10.5, color: c.inkSoft),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HandChip('已解 $solved/$total', size: 10.5),
                  const SizedBox(width: 5),
                  HandChip(
                    '附加分 ${_score(emoji?.score ?? 0)}',
                    size: 10.5,
                    bg: c.hl,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : (solved / total).clamp(0, 1),
              minHeight: 5,
              color: c.accent,
              backgroundColor: c.line,
            ),
          ),
          const SizedBox(height: 14),
          _emojiBody(c, emoji),
        ],
      ),
    );
  }

  Widget _emojiBody(CitroColors c, LanternEmojiState? emoji) {
    if (!AppState.instance.loggedIn) {
      return Column(
        children: [
          Text('登录后参与附加题', style: context.body(size: 12, color: c.inkSoft)),
          const SizedBox(height: 10),
          AccentButton(text: '去登录', outlined: true, height: 38, onTap: _login),
        ],
      );
    }
    if (emoji == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '附加题加载中…',
          textAlign: TextAlign.center,
          style: context.body(size: 12, color: c.inkSoft),
        ),
      );
    }
    final current = emoji.current;
    if (current != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface.withAlpha(c.dark ? 70 : 170),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
            ),
            child: Text(
              current.emoji,
              style: const TextStyle(fontSize: 38, height: 1.35),
            ),
          ),
          const SizedBox(height: 12),
          if (_open)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emojiController,
                    focusNode: _emojiFocus,
                    maxLength: 12,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _answerEmoji(),
                    style: context.body(size: 14),
                    decoration: InputDecoration(
                      hintText: '猜成语…',
                      counterText: '',
                      isDense: true,
                      filled: true,
                      fillColor: c.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide(color: c.accent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AccentButton(
                  text: '交卷',
                  width: 72,
                  height: 42,
                  loading: _emojiBusy,
                  onTap: _emojiBusy ? null : _answerEmoji,
                ),
              ],
            )
          else
            Text(
              '已收卷',
              textAlign: TextAlign.center,
              style: context.body(size: 12, color: c.stamp),
            ),
          if (_emojiMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _emojiMessage!,
                style: context.body(
                  size: 11,
                  color: _emojiMessage == '猜中 +0.5！' ? c.mintInk : c.stamp,
                ),
              ),
            ),
          const SizedBox(height: 7),
          Text(
            '答对自动抽取下一题 · 停在本题直到答对',
            textAlign: TextAlign.center,
            style: context.body(size: 10.5, color: c.inkSoft),
          ),
        ],
      );
    }
    final done = emoji.solved.length >= emoji.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          done ? '附加题已全部解完' : (_open ? '点击下方抽取一题' : '已收卷'),
          textAlign: TextAlign.center,
          style: context.body(size: 12.5, color: c.inkSoft),
        ),
        if (!done && _open) ...[
          const SizedBox(height: 12),
          AccentButton(
            text: '抽一题',
            loading: _emojiBusy,
            onTap: _emojiBusy ? null : _drawEmoji,
          ),
        ],
        if (_emojiMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _emojiMessage!,
              textAlign: TextAlign.center,
              style: context.body(size: 11, color: c.stamp),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          '答对自动抽取下一题 · 每题 0.5 分',
          textAlign: TextAlign.center,
          style: context.body(size: 10.5, color: c.inkSoft),
        ),
      ],
    );
  }

  String _score(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
