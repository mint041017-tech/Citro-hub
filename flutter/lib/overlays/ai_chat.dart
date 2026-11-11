import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../games/game_registry.dart';
import '../ledger/ledger_models.dart';
import '../ledger/ledger_store.dart';
import '../services/ai.dart';
import '../services/api.dart';
import '../services/cici_persona.dart';
import '../services/media.dart';
import '../services/platform.dart' as platform;
import '../services/speech.dart';
import '../state/app_state.dart';
import '../services/models.dart';
import '../tingyu/tingyu_controller.dart';
import '../todo/todo_ai.dart';
import '../todo/todo_models.dart';
import '../todo/todo_store.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/cici_composer.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

class _ChatMessage {
  final bool user;
  String text;
  bool pending;
  final String? image;
  _ChatMessage({
    required this.user,
    required this.text,
    this.pending = false,
    this.image,
  });
}

final List<_ChatMessage> _history = [];

/// 转运对话同样跟着一次 App 会话走，关掉面板不会丢，退出 App 才清空。
final List<_ChatMessage> _deedHistory = [];

Future<void> showAiChat(
  BuildContext context, {
  Recipe? recipe,
  bool goodDeed = false,
  VoidCallback? onGoodDeed,
}) async {
  await showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.c.scrim,
    builder: (_) => _AiChatSheet(
      recipe: recipe,
      goodDeed: goodDeed,
      onGoodDeed: onGoodDeed,
    ),
  );
}

class _AiChatSheet extends StatefulWidget {
  final Recipe? recipe;
  final bool goodDeed;
  final VoidCallback? onGoodDeed;
  const _AiChatSheet({this.recipe, this.goodDeed = false, this.onGoodDeed});
  @override
  State<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<_AiChatSheet>
    with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  bool _deedShared = false;
  String? _pendingImage;
  bool _picking = false;
  bool _chatRewarded = false;
  bool _listening = false;
  String _voiceBase = '';

  // 转运对话单独一份记录，不把「好事」混进日常 CiCi 历史。
  List<_ChatMessage> get _messages => widget.goodDeed ? _deedHistory : _history;
  String? _error;

  /// 快捷能力执行期间挡住重复点击，避免连按叠出两个弹层。
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final got = await AppState.instance.grantChatCardDraw();
      if (!mounted || !got) return;
      setState(() => _chatRewarded = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SpeechInput.cancel();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 键盘弹起会缩短列表视口，必须重新贴到底部才能看到最新消息。
    _jumpToEnd();
    Future<void>.delayed(const Duration(milliseconds: 260), _jumpToEnd);
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  static const _deedDoneText = '好事收到，转运机会已经到账\n回到签卡，点「再抽一签」看看新运气。';

  Future<void> _toggleVoice() async {
    if (_sending || _picking) return;
    if (_listening) {
      setState(() => _listening = false);
      await SpeechInput.stop();
      return;
    }
    final ready = await SpeechInput.ensureReady();
    if (!mounted) return;
    if (!ready) {
      AppToast.show(context, '当前设备暂不支持语音输入，可以先打字。');
      return;
    }
    _voiceBase = _input.text;
    setState(() => _listening = true);
    final started = await SpeechInput.start(
      onResult: (text, isFinal) {
        if (!mounted) return;
        final heard = text.trim();
        setState(() {
          _input.text = heard.isEmpty ? _voiceBase : '$_voiceBase$heard';
          _input.selection = TextSelection.collapsed(
            offset: _input.text.length,
          );
          if (isFinal) _listening = false;
        });
        _jumpToEnd();
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _listening = false);
        AppToast.show(context, '没有听清，再说一次试试。');
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _listening = false);
      },
    );
    if (!started && mounted) setState(() => _listening = false);
  }

  Future<void> _send([String? preset]) async {
    if (_sending) return;
    final text = (preset ?? _input.text).trim();
    final image = preset == null ? _pendingImage : null;
    if (text.isEmpty && image == null) return;
    _input.clear();
    _error = null;
    final user = _ChatMessage(user: true, text: text, image: image);
    setState(() {
      _pendingImage = null;
      _messages.add(user);
      _sending = true;
    });
    _scrollToEnd();

    if (widget.goodDeed && !_deedShared) {
      await _reviewDeed(user);
      return;
    }
    final assistant = _ChatMessage(user: false, text: '', pending: true);
    setState(() => _messages.add(assistant));
    _scrollToEnd();
    await _streamReply(assistant);
  }

  Future<void> _reviewDeed(_ChatMessage user) async {
    final assistant = _ChatMessage(user: false, text: '', pending: true);
    setState(() => _messages.add(assistant));
    _scrollToEnd();
    try {
      final result = await AiService.reviewGoodDeed(
        text: user.text,
        image: user.image,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() {
          assistant.pending = false;
          assistant.text = '审核暂时没连上，等会儿再把这件事发我一次吧。';
        });
        return;
      }
      if (!result.pass) {
        setState(() {
          assistant.pending = false;
          assistant.text = result.reply;
        });
        return;
      }
      _deedShared = true;
      widget.onGoodDeed?.call();
      final done = _ChatMessage(
        user: false,
        text: '${result.reply}\n\n$_deedDoneText',
      );
      setState(() {
        assistant.pending = false;
        assistant.text = result.reply;
        _messages.add(done);
      });
      unawaited(_recordDeed(user.text, done, image: user.image));
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        assistant.pending = false;
        assistant.text = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        assistant.pending = false;
        assistant.text = '网络有点不稳，稍后再试。';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  Future<void> _streamReply(_ChatMessage assistant) async {
    final source = _messages
        .where((m) => !m.pending && (m.text.isNotEmpty || m.image != null))
        .map(
          (m) => <String, dynamic>{
            'role': m.user ? 'user' : 'assistant',
            'content': _contentFor(m),
          },
        )
        .toList();
    final messages = source.length > 14
        ? source.sublist(source.length - 14)
        : source;
    try {
      await for (final chunk in AiService.streamChat(
        messages,
        extraSystem: _systemContext(),
        persona: AppState.instance.ciciPersona,
      )) {
        if (!mounted) return;
        setState(() {
          assistant.text += chunk;
          assistant.pending = false;
        });
        _scrollToEnd();
      }
      if (!mounted) return;
      if (assistant.text.isEmpty) {
        setState(() {
          assistant.pending = false;
          assistant.text = '我刚刚走神了，再问我一次吧。';
        });
      } else {
        // CiCi 可以在回复里带上待办草稿，这里落库并补一句确认。
        final (clean, drafts) = TodoAi.parseReply(assistant.text);
        final created = drafts.isEmpty
            ? const <String>[]
            : _createTodos(drafts);
        if (created.isNotEmpty) {
          setState(() {
            assistant.pending = false;
            assistant.text =
                '${clean.trim().isEmpty ? '已经帮你记下了。' : clean.trim()}\n\n'
                '已加入待办：${created.join('、')}';
          });
        } else if (clean.trim().isNotEmpty && clean != assistant.text) {
          setState(() => assistant.text = clean.trim());
        }
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        assistant.pending = false;
        assistant.text = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        assistant.pending = false;
        assistant.text = '网络有点不稳，稍后再试。';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  dynamic _contentFor(_ChatMessage message) {
    if (message.image == null) return message.text;
    return <Map<String, dynamic>>[
      if (message.text.isNotEmpty) {'type': 'text', 'text': message.text},
      {
        'type': 'image_url',
        'image_url': {'url': message.image},
      },
    ];
  }

  Future<void> _pickImage() async {
    if (_picking || _sending) return;
    setState(() => _picking = true);
    try {
      final raw = await MediaService.pickImageBytes(
        maxWidth: 1600,
        quality: 90,
      );
      if (raw == null) return;
      final compressed = await MediaService.compressCookImage(
        raw,
        maxDim: 1280,
        quality: 84,
        limit: 300 * 1024,
      );
      if (!mounted) return;
      setState(() => _pendingImage = MediaService.dataUrl(compressed));
    } catch (_) {
      if (mounted) AppToast.show(context, '图片读取失败，换一张试试');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _clear() {
    if (_sending) return;
    setState(() {
      _messages.clear();
      _error = null;
      _deedShared = false;
      _pendingImage = null;
    });
  }

  // -------------------------------------------------------------------------
  // 快捷能力
  // -------------------------------------------------------------------------

  Future<void> _runCapability(Future<void> Function() action) async {
    if (_acting) return;
    _acting = true;
    try {
      await action();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  /// 把能力执行结果以 CiCi 的口吻写进对话流。
  void _ciciSay(String text) {
    setState(() => _messages.add(_ChatMessage(user: false, text: text)));
    _scrollToEnd();
  }

  Widget _quickActions(BuildContext context) {
    // 食谱助手与转运是专用流程，不混入通用能力入口。
    if (widget.goodDeed || widget.recipe != null) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    final items = <(String, Widget, void Function())>[
      (
        '记一笔',
        _capIcon(AppIcons.wallet, c),
        () => _runCapability(_addLedgerEntry),
      ),
      (
        '删记账',
        _capIcon(AppIcons.trash, c),
        () => _runCapability(_removeLedgerEntry),
      ),
      (
        '记待办',
        _capIcon(AppIcons.note, c),
        () => _runCapability(_addTodo),
      ),
      (
        '删待办',
        _capIcon(AppIcons.minus, c),
        () => _runCapability(_removeTodo),
      ),
      (
        '播放白噪音',
        _capIcon(AppIcons.play, c),
        () => _runCapability(_playNook),
      ),
      (
        '暂停白噪音',
        Icon(Icons.pause_rounded, size: 14, color: c.accentInk),
        () => _runCapability(_pauseNook),
      ),
      ('天气', _capIcon(AppIcons.sun, c), _showWeather),
      ('游戏', _capIcon(AppIcons.games, c), _showGame),
      ('星象', _capIcon(AppIcons.star, c), _showZodiac),
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final (label, icon, onTap) = items[index];
          return _capChip(context, label, icon, onTap);
        },
      ),
    );
  }

  Widget _capIcon(String svg, CitroColors c) =>
      AppIcon(strokeSvg(svg, width: 1.9), size: 14, color: c.accentInk);

  Widget _capChip(
    BuildContext context,
    String label,
    Widget icon,
    void Function() onTap,
  ) {
    final c = context.c;
    return Pressable(
      onTap: () {
        if (_acting) return;
        onTap();
      },
      scale: .94,
      hoverLift: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 4),
            Text(
              label,
              style: context.body(size: CitroType.caption, color: c.ink2),
            ),
          ],
        ),
      ),
    );
  }

  /// 记一笔账：直接在弹层里录入并写入 [LedgerStore]。
  Future<void> _addLedgerEntry() async {
    await LedgerStore.instance.ensureInit();
    if (!mounted) return;
    final result = await showCitroDialog<
        ({LedgerKind kind, int cents, String category, String note})>(
      context,
      builder: (_) => const PaperDialog(
        maxWidth: 360,
        child: _LedgerQuickAddDialog(),
      ),
    );
    if (result == null || !mounted) return;
    final note = result.note.isEmpty ? '' : ' · ${result.note}';
    _ciciSay(
      '已记下${result.kind.label} ${ledgerMoney(result.cents)}'
      ' · ${result.category}$note',
    );
  }

  /// 删除最近一条账单（按发生时间倒序取第一条）。
  Future<void> _removeLedgerEntry() async {
    final store = LedgerStore.instance;
    await store.ensureInit();
    if (!mounted) return;
    final recent = store.recentEntries(limit: 1);
    if (recent.isEmpty) {
      _ciciSay('账本还是空的，没有可删除的账单。');
      return;
    }
    final entry = recent.first;
    final detail = '${entry.kind.label} ${ledgerMoney(entry.amountCents)}'
        '${entry.note.isEmpty ? '' : ' · ${entry.note}'}';
    final ok = await showCitroDialog<bool>(
      context,
      builder: (_) => PaperDialog(
        maxWidth: 340,
        child: _ConfirmDialog(
          title: '删除最近一笔账单？',
          body: '$detail，删除后本月统计会立即变化。',
          confirmText: '删除',
        ),
      ),
    );
    if (ok != true || !mounted) return;
    store.removeEntry(entry.id);
    _ciciSay('已删除最近一笔账单：$detail');
  }

  /// 记一条今日待办：写入 [TodoStore]，当天 23:59 截止。
  Future<void> _addTodo() async {
    await TodoStore.instance.ensureInit();
    if (!mounted) return;
    final title = await showCitroDialog<String>(
      context,
      builder: (_) => const PaperDialog(
        maxWidth: 360,
        child: _TodoQuickAddDialog(),
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;
    _ciciSay('已加入今日待办：$title');
  }

  /// 删除最近一条未完成的待办；没有未完成的就直说。
  Future<void> _removeTodo() async {
    final store = TodoStore.instance;
    await store.ensureInit();
    if (!mounted) return;
    final open = store.tasks.where((t) => !t.done).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (open.isEmpty) {
      _ciciSay('没有未完成的待办可以删除。');
      return;
    }
    final target = open.first;
    final ok = await showCitroDialog<bool>(
      context,
      builder: (_) => PaperDialog(
        maxWidth: 340,
        child: _ConfirmDialog(
          title: '删除这条待办？',
          body: '「${target.title}」删除后不能恢复。',
          confirmText: '删除',
        ),
      ),
    );
    if (ok != true || !mounted) return;
    store.deleteTask(target.id);
    _ciciSay('已删除待办：${target.title}');
  }

  Future<void> _playNook() async {
    final ok = await NookController.instance.send('play');
    if (!mounted) return;
    if (ok) {
      final title = NookController.instance.title;
      _ciciSay('白噪音已播放${title.isEmpty ? '' : ' · 《$title》'}');
    } else {
      _ciciSay(
        '白噪音没能播放：${NookController.instance.error ?? '请稍后再试'}',
      );
    }
  }

  Future<void> _pauseNook() async {
    await NookController.instance.send('pause');
    if (!mounted) return;
    _ciciSay('白噪音已暂停');
  }

  void _showWeather() {
    final w = AppState.instance.weather;
    _ciciSay(
      '${w.city} · ${w.desc} ${w.emoji}\n'
      '${w.temp.round()}°C（体感 ${w.feels.round()}°C）',
    );
  }

  void _showGame() {
    final cards = kGameCards;
    if (cards.isEmpty) {
      _ciciSay('游戏中心还没准备好，稍后再来看看。');
      return;
    }
    final pick = cards[math.Random().nextInt(cards.length)];
    _ciciSay(
      '今天可以玩：${pick.title}\n'
      '分类：${_gameCategoryOf[pick.key] ?? '休闲'} · 想换一个就再点我一次',
    );
  }

  void _showZodiac() {
    final state = AppState.instance;
    final sign = zodiacById(state.zodiacSign);
    if (sign == null) {
      _ciciSay('还没设置星座，去「我的」填生日后我就能报每日运势啦。');
      return;
    }
    final f = state.zodiacFortune;
    if (f == null) {
      _ciciSay(
        '${sign.name} ${sign.symbol} · ${sign.range}\n'
        '今日运势还在生成中，稍后再来问问。',
      );
      return;
    }
    _ciciSay(
      '${sign.name} ${sign.symbol} · ${sign.range}\n'
      '综合运势 ${f.score} · ${f.tag}\n'
      '${f.text}\n'
      '幸运色 ${f.color} · 幸运数字 ${f.number} · 幸运物 ${f.item}\n'
      '爱情 ${f.love} · 事业 ${f.work} · 财富 ${f.wealth} · 健康 ${f.health}',
    );
  }

  /// 游戏中心只有名称，没有分类字段，这里按游戏性质给个本地映射。
  static const _gameCategoryOf = <String, String>{
    'g2048': '益智数字',
    'gmem': '记忆益智',
    'gsudoku': '益智数字',
    'gnono': '逻辑益智',
    'gslide': '益智数字',
    'gsnake': '休闲反应',
    'gsheep': '休闲消除',
    'gjump': '休闲反应',
    'gpeng': '休闲物理解谜',
    'gbrake': '休闲反应',
    'gidiom': '文字',
    'gfeihua': '文字',
    'gliquid': '休闲物理解谜',
    'gknockwater': '沉浸式',
  };


  /// 转运分享的好事同步成一条社区动态（图片一并带上），不再写进笔记。
  Future<void> _recordDeed(
    String text,
    _ChatMessage message, {
    String? image,
  }) async {
    final state = AppState.instance;
    if (!state.loggedIn) {
      if (!mounted) return;
      setState(() {
        message.text = '${message.text}\n登录后才能把这条好事同步到社区。';
      });
      return;
    }
    final content = text.trim().isEmpty ? '分享了公益捐赠截图' : text.trim();
    try {
      await Api.createPost(
        text: '今日好事：$content',
        imgs: [if (image != null && image.isNotEmpty) image],
      );
      if (!mounted) return;
      setState(() {
        message.text = '${message.text}\n已同步到社区动态';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        message.text = '${message.text}\n同步社区失败：${e.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        message.text = '${message.text}\n社区暂时没同步成功，稍后可以再试。';
      });
    }
  }

  String? _systemContext() {
    final parts = <String>[];
    if (widget.recipe != null) parts.add(_recipeContext(widget.recipe!));
    if (widget.goodDeed) {
      parts.add(
        '用户今天抽到了下签或下下签，正通过分享一件今天做过的好事来转运。'
        '请温柔地接住这件事、肯定对方，不要说教、不要追问隐私；2~4 句，口语化。',
      );
    } else {
      // 首页的 CiCi 也能顺手把待办建出来，和待办页用同一套约定。
      final store = TodoStore.instance;
      store.ensureInit();
      parts.add(TodoAi.assistantSystem);
      parts.add(
        '【当前待办数据】\n${TodoAi.contextFor(tasks: store.tasks, moods: store.moods, focusMinutes: 0, streak: store.streak, now: DateTime.now())}',
      );
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  /// 把 CiCi 返回的任务草稿落成真正的待办，返回已建好的标题。
  List<String> _createTodos(List<TodoDraft> drafts) {
    final store = TodoStore.instance;
    final out = <String>[];
    for (final d in drafts) {
      final title = d.title.trim();
      if (title.isEmpty) continue;
      // 更新指令：给已有任务补备注/改时间。
      if (d.update) {
        TodoTask? target;
        for (final t in store.tasks) {
          if (t.title.trim() == title) {
            target = t;
            break;
          }
        }
        if (target == null) continue;
        final note = d.note.trim();
        if (note.isNotEmpty) {
          target.note = target.note.trim().isEmpty
              ? note
              : '${target.note.trim()}；$note';
        }
        if (d.at != null) {
          if (target.kind == TodoKind.task) target.dueAt = d.at;
          if (target.kind == TodoKind.reminder) target.remindAt = d.at;
        }
        store.updateTask(target);
        out.add(title);
        continue;
      }
      final cat = store.categories.firstWhere(
        (c) => c.name == d.categoryName,
        orElse: () => store.categories.first,
      );
      store.createTask(
        title: title,
        note: d.note,
        kind: d.kind,
        categoryId: cat.id,
        listId: store.lists.first.id,
        remindAt: d.at,
        dueAt: d.kind == TodoKind.task
            ? (d.at ?? DateTime.now().add(const Duration(days: 1)))
            : null,
        subtasks: d.subtasks,
        priority: d.priority,
        source: 'cici',
      );
      out.add(title);
    }
    return out;
  }

  String _recipeContext(Recipe r) {
    final ingredients = r.ingredients
        .take(30)
        .map((e) => e.amount.isEmpty ? e.name : '${e.name} ${e.amount}')
        .join('、');
    final steps = r.steps
        .take(12)
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final buffer = StringBuffer()
      ..write('当前用户正在食谱日记查看《${r.name}》。')
      ..write(r.cuisine.isEmpty ? '' : '菜系：${r.cuisine}；')
      ..write(r.dishType.isEmpty ? '' : '类型：${r.dishType}；')
      ..write(r.servings > 0 ? '分量：${r.servings} 人；' : '')
      ..write(
        r.prepMin + r.cookMin > 0 ? '用时：${r.prepMin + r.cookMin} 分钟；' : '',
      )
      ..write(ingredients.isEmpty ? '' : '食材：$ingredients；');
    if (steps.isNotEmpty) {
      buffer.write('步骤：');
      for (var i = 0; i < steps.length; i++) {
        final text = steps[i].length > 90
            ? '${steps[i].substring(0, 90)}…'
            : steps[i];
        buffer.write('${i + 1}. $text；');
      }
    }
    if (r.note.isNotEmpty) buffer.write('小记：${r.note}；');
    buffer.write('请围绕这道菜回答，给具体可操作的建议；不确定就直说，不要编造。');
    return buffer.toString();
  }

  /// 标题下的副标题：场景优先，没有场景时显示当前性格。
  String get _subtitle {
    final recipe = widget.recipe;
    if (recipe != null) return '食谱助手 · ${recipe.name}';
    if (widget.goodDeed) return '分享好事 · 转运一次';
    final persona = AppState.instance.ciciPersona;
    return persona.isEmpty
        ? '嘴硬心软 · 极速回答'
        : '性格 · ${CiciPersona.labelFor(persona)}';
  }

  Future<void> _editPersona() async {
    await showCiciPersonaSheet(context);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = MediaQuery.sizeOf(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final available = size.height - inset;
    final height = math.min(available, math.max(360.0, available * .9));
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CitroColors.radii.card)),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: CitroBackground(
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: c.line2,
                      borderRadius: BorderRadius.circular(CitroColors.radii.xs),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: c.accent.withAlpha(70),
                            shape: BoxShape.circle,
                            border: Border.all(color: c.line2),
                            boxShadow: CitroColors.shadows.sm(c),
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/cici_avatar.webp',
                              fit: BoxFit.cover,
                              cacheWidth: 152,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CiCi',
                                style: context.heading(size: CitroType.titleLg, color: c.ink),
                              ),
                              Text(
                                _subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.body(size: CitroType.micro, color: c.inkSoft),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _editPersona,
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                              border: Border.all(color: c.line2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIcon(
                                  strokeSvg(AppIcons.sparkle, width: 2),
                                  size: 13,
                                  color: c.accentInk,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '性格',
                                  style: context.body(
                                    size: CitroType.meta,
                                    weight: CitroType.medium,
                                    color: c.ink2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _clear,
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                              border: Border.all(color: c.line2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIcon(
                                  strokeSvg(AppIcons.plus, width: 2),
                                  size: 13,
                                  color: _sending
                                      ? c.inkSoft.withAlpha(100)
                                      : c.accentInk,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '新对话',
                                  style: context.body(
                                    size: CitroType.meta,
                                    weight: CitroType.medium,
                                    color: _sending
                                        ? c.inkSoft.withAlpha(100)
                                        : c.ink2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: c.surface2,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.line2),
                            ),
                            child: Center(
                              child: AppIcon(
                                strokeSvg(AppIcons.close, width: 2.2),
                                size: 22,
                                color: c.inkSoft,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  CitroDivider(color: c.line2.withAlpha(150)),
                  if (_chatRewarded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: c.accentLt.withAlpha(c.dark ? 70 : 170),
                          borderRadius: BorderRadius.circular(CitroColors.radii.small),
                          border: Border.all(color: c.accent.withAlpha(80)),
                        ),
                        child: Row(
                          children: [
                            AppIcon(
                              strokeSvg(AppIcons.sparkle, width: 2),
                              size: 13,
                              color: c.accentInk,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '今日首次找 CiCi · 卡面抽卡机会 +1，去「我的 - 卡面收藏」抽',
                                style: context.body(
                                  size: CitroType.small,
                                  weight: CitroType.medium,
                                  color: c.accentInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: _messages.isEmpty
                        ? _welcome(context)
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) =>
                                _bubble(context, _messages[i]),
                          ),
                  ),
                  if (widget.goodDeed && _deedShared)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: c.mintSoft,
                          borderRadius: BorderRadius.circular(CitroColors.radii.small),
                          border: Border.all(color: c.mintLine),
                        ),
                        child: Row(
                          children: [
                            AppIcon(
                              strokeSvg(AppIcons.sparkle, width: 2),
                              size: 14,
                              color: c.mintInk,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '转运机会 +1 · 关掉对话，回签卡点「再抽一签」',
                                style: context.body(
                                  size: CitroType.small,
                                  weight: CitroType.medium,
                                  color: c.mintInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text(
                        _error!,
                        style: context.body(size: CitroType.small, color: c.stamp),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 2),
                    child: Text(
                      'AI 生成内容仅供参考；文字与图片会发送至第三方 AI 服务处理，请勿发送敏感信息。',
                      textAlign: TextAlign.center,
                      style: context.body(size: CitroType.micro, color: c.inkSoft),
                    ),
                  ),
                  _inputBar(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final c = context.c;
    final prompts = widget.recipe != null
        ? ['这道菜怎么补救？', '换成家常做法', '帮我看下火候', '列个采购清单']
        : widget.goodDeed
        ? const <String>[]
        : ['帮我写一句手账文案', '今天吃什么？', '社区怎么玩？', '安慰一下我'];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Transform.rotate(
                angle: -3 * math.pi / 180,
                child: Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: c.accent.withAlpha(70),
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line),
                    boxShadow: CitroColors.shadows.sm(c),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/cici_avatar.webp',
                      fit: BoxFit.cover,
                      cacheWidth: 216,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: c.tintYellow.withAlpha(170),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(CitroColors.radii.xs),
                      topRight: Radius.circular(CitroColors.radii.inner),
                      bottomLeft: Radius.circular(CitroColors.radii.inner),
                      bottomRight: Radius.circular(CitroColors.radii.inner),
                    ),
                    border: Border.all(color: c.line),
                  ),
                  child: Text(
                    widget.recipe != null
                        ? '你好呀，我是 CiCi。\n关于《${widget.recipe!.name}》，想聊点什么？'
                        : widget.goodDeed
                        ? '今天抽到下签也别慌。\n跟我说说你今天做的一件好事，我帮你转运一次。'
                        : '你好呀，我是 CiCi。\n今天想聊点什么？',
                    style: context.body(size: CitroType.meta, color: c.ink2, height: 1.7),
                  ),
                ),
              ),
            ],
          ),
          if (widget.goodDeed) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.mintSoft,
                borderRadius: BorderRadius.circular(CitroColors.radii.small),
                border: Border.all(color: c.mintLine),
              ),
              child: Text(
                context.app.loggedIn
                    ? '要真实帮到别人才算数：帮同学带饭、照顾家人、做志愿服务……也可以发公益捐赠截图（金额不限）。通过后会以「今日好事：…」同步到社区动态（含图片，公开可见）。'
                    : '要真实帮到别人才算数：帮同学带饭、照顾家人、做志愿服务……也可以发公益捐赠截图（金额不限）。通过后才能获得转运机会。',
                style: context.body(size: CitroType.caption, color: c.mintInk, height: 1.6),
              ),
            ),
          ],
          const SizedBox(height: 22),
          if (prompts.isNotEmpty) ...[
            Text(
              '可以试试',
              style: context.body(
                size: CitroType.small,
                weight: CitroType.medium,
                color: c.inkSoft,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in prompts)
                  GestureDetector(
                    onTap: () => _send(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        p,
                        style: context.body(size: CitroType.caption, color: c.ink2),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, _ChatMessage m) {
    final c = context.c;
    if (m.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .76,
          ),
          margin: const EdgeInsets.only(bottom: 12, left: 40),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(CitroColors.radii.inner),
              topRight: Radius.circular(CitroColors.radii.xs),
              bottomLeft: Radius.circular(CitroColors.radii.inner),
              bottomRight: Radius.circular(CitroColors.radii.inner),
            ),
            boxShadow: CitroColors.shadows.sm(c),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (m.image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(CitroColors.radii.small),
                  child: _LocalImage(
                    dataUrl: m.image!,
                    width: 178,
                    height: 132,
                  ),
                ),
                if (m.text.isNotEmpty) const SizedBox(height: 6),
              ],
              if (m.text.isNotEmpty)
                Text(
                  m.text,
                  style: context.body(
                    size: CitroType.meta,
                    color: c.onAccent,
                    height: 1.65,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: c.accentLt.withAlpha(c.dark ? 70 : 170),
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/cici_avatar.webp',
                fit: BoxFit.cover,
                cacheWidth: 112,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .76,
              ),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(CitroColors.radii.xs),
                  topRight: Radius.circular(CitroColors.radii.inner),
                  bottomLeft: Radius.circular(CitroColors.radii.inner),
                  bottomRight: Radius.circular(CitroColors.radii.inner),
                ),
                border: Border.all(color: c.line),
              ),
              child: m.pending && m.text.isEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.7,
                            color: c.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '正在想想…',
                          style: context.body(size: CitroType.caption, color: c.inkSoft),
                        ),
                      ],
                    )
                  : Text(
                      m.text,
                      style: context.body(size: CitroType.meta, color: c.ink, height: 1.7),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar(BuildContext context) {
    final c = context.c;
    // 手机端统一用胶囊输入栏：按住说话、松开发送。
    if (platform.isAndroid || platform.isIOS) {
      return Container(
        decoration: BoxDecoration(
          color: c.surface.withAlpha(235),
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _quickActions(context),
            if (_pendingImage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(CitroColors.radii.small),
                      child: Image.memory(
                        base64Decode(_pendingImage!.split(',').last),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '这张图会一起发给 CiCi',
                        style: context.body(
                          size: CitroType.caption,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _pendingImage = null),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: AppIcon(
                          strokeSvg(AppIcons.close, width: 2),
                          size: 15,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            CiciComposer(
              controller: _input,
              sending: _sending,
              picking: _picking,
              hint: '和 CiCi 说一句…',
              onSend: () => _send(),
              onPickImage: _pickImage,
              onSubmitVoice: (text) async {
                await _send(text);
              },
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: c.surface.withAlpha(235),
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _quickActions(context),
          if (_pendingImage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(CitroColors.radii.small),
                        child: _LocalImage(
                          dataUrl: _pendingImage!,
                          width: 58,
                          height: 58,
                        ),
                      ),
                      Positioned(
                        right: -6,
                        top: -6,
                        child: GestureDetector(
                          onTap: () => setState(() => _pendingImage = null),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: c.ink,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.surface, width: 1.4),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 12,
                              color: c.bg,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '图片会和文字一起发给 CiCi',
                      style: context.body(size: CitroType.small, color: c.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
          if (_listening)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '正在聆听…说完点一下麦克风停止',
                      style: context.body(size: CitroType.small, color: c.accentInk),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _picking || _sending ? null : _pickImage,
                child: Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(right: 8, bottom: 1),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line2),
                  ),
                  child: Center(
                    child: _picking
                        ? SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: c.accent,
                            ),
                          )
                        : AppIcon(
                            strokeSvg(AppIcons.image, width: 2),
                            size: 18,
                            color: c.accentInk,
                          ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _sending || _picking ? null : _toggleVoice,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(right: 8, bottom: 1),
                  decoration: BoxDecoration(
                    color: _listening ? c.accent.withAlpha(36) : c.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: _listening ? c.accent : c.line2),
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Icon(
                        _listening
                            ? Icons.stop_rounded
                            : Icons.mic_none_rounded,
                        key: ValueKey(_listening),
                        size: 20,
                        color: _listening ? c.accent : c.accentInk,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 40,
                    maxHeight: 108,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                    border: Border.all(color: c.line2),
                  ),
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 4,
                    textAlignVertical: TextAlignVertical.center,
                    textInputAction: TextInputAction.send,
                    onTap: () {
                      _focus.requestFocus();
                      SystemChannels.textInput.invokeMethod<void>(
                        'TextInput.show',
                      );
                      _jumpToEnd();
                      Future<void>.delayed(
                        const Duration(milliseconds: 260),
                        _jumpToEnd,
                      );
                    },
                    onSubmitted: (_) => _send(),
                    onTapOutside: (_) => _focus.unfocus(),
                    style: context.body(size: CitroType.meta, height: 1.5),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      hintText: '和 CiCi 聊聊…',
                      hintStyle: context.body(size: CitroType.meta, color: c.inkSoft),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sending ? null : _send,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _sending ? c.accent.withAlpha(100) : c.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line2),
                    boxShadow: _sending ? null : CitroColors.shadows.sm(c),
                  ),
                  child: Center(
                    child: _sending
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.ink,
                            ),
                          )
                        : AppIcon(
                            strokeSvg(AppIcons.send, width: 2),
                            size: 18,
                            color: c.onAccent,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// CiCi 的性格设置弹层，保存后从下一次回复开始生效。
Future<void> showCiciPersonaSheet(BuildContext context) async {
  await showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.c.scrim,
    builder: (_) => const _PersonaSheet(),
  );
}

class _PersonaSheet extends StatefulWidget {
  const _PersonaSheet();

  @override
  State<_PersonaSheet> createState() => _PersonaSheetState();
}

class _PersonaSheetState extends State<_PersonaSheet> {
  final TextEditingController _text = TextEditingController(
    text: AppState.instance.ciciPersona,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pick(String text) {
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {});
  }

  Future<void> _save() async {
    await AppState.instance.setCiciPersona(_text.text);
    if (!mounted) return;
    AppToast.show(context, 'CiCi 的性格已更新');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final current = _text.text.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(CitroColors.radii.card)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.line2,
                      borderRadius: BorderRadius.circular(CitroColors.radii.xs),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'CiCi 的性格',
                      style: context.heading(size: CitroType.titleLg, color: c.ink),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c.surface2,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.line2),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.close, width: 2.2),
                            size: 18,
                            color: c.inkSoft,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '选一个喜欢的说话方式，或者在下面写你想要的性格。保存后从下一句话开始生效，留空就是默认的嘴硬心软。',
                  style: context.body(size: CitroType.caption, color: c.inkSoft, height: 1.6),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in CiciPersona.presets)
                      _presetChip(context, preset, current),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _text,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: CiciPersona.maxLength,
                  onChanged: (_) => setState(() {}),
                  style: context.body(size: CitroType.body, color: c.ink, height: 1.6),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    hintText: '例如：说话像邻居姐姐，爱用「呀」「啦」结尾，会主动关心我今天吃了什么。',
                    hintStyle: context.body(
                      size: CitroType.meta,
                      color: c.inkSoft,
                      height: 1.6,
                    ),
                    filled: true,
                    fillColor: c.surface2,
                    counterStyle: context.body(size: CitroType.small, color: c.inkSoft),
                    contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                      borderSide: BorderSide(color: c.line2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                      borderSide: BorderSide(color: c.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AccentButton(
                        text: '恢复默认',
                        outlined: true,
                        onTap: current.isEmpty ? null : () => _pick(''),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: AccentButton(text: '保存', onTap: _save),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _presetChip(
    BuildContext context,
    ({String label, String text}) preset,
    String current,
  ) {
    final c = context.c;
    final selected = preset.text == current;
    return GestureDetector(
      onTap: () => _pick(preset.text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.accentLt.withAlpha(c.dark ? 70 : 170) : c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Text(
          preset.label,
          style: context.body(
            size: CitroType.meta,
            weight: selected ? CitroType.medium : CitroType.regular,
            color: selected ? c.accentInk : c.ink2,
          ),
        ),
      ),
    );
  }
}

/// 记一笔账的轻量弹层：金额 + 收支 + 分类 + 备注，确认后直接写入账本。
class _LedgerQuickAddDialog extends StatefulWidget {
  const _LedgerQuickAddDialog();

  @override
  State<_LedgerQuickAddDialog> createState() => _LedgerQuickAddDialogState();
}

class _LedgerQuickAddDialogState extends State<_LedgerQuickAddDialog> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  LedgerKind _kind = LedgerKind.expense;
  late String _categoryId;
  String? _error;

  @override
  void initState() {
    super.initState();
    LedgerStore.instance.ensureInit();
    final cats = LedgerStore.instance.categoriesFor(LedgerKind.expense);
    _categoryId = cats.isNotEmpty ? cats.first.id : 'food';
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _switchKind(LedgerKind kind) {
    final cats = LedgerStore.instance.categoriesFor(kind);
    setState(() {
      _kind = kind;
      if (cats.isNotEmpty) _categoryId = cats.first.id;
    });
  }

  void _save() {
    final cents = ledgerParseAmount(_amount.text) ?? 0;
    if (cents <= 0) {
      setState(() => _error = '金额需要大于 0');
      return;
    }
    final store = LedgerStore.instance;
    final category = store.categoryOf(_categoryId, kind: _kind);
    final note = _note.text.trim();
    store.addEntry(
      kind: _kind,
      amountCents: cents,
      categoryId: category.id,
      note: note,
      source: LedgerSource.cici,
    );
    Navigator.of(context).pop(
      (kind: _kind, cents: cents, category: category.name, note: note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final categories = LedgerStore.instance.categoriesFor(_kind);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '记一笔',
          style: context.heading(size: CitroType.subtitle, color: c.ink),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final kind in LedgerKind.values)
              Padding(
                padding: EdgeInsets.only(
                  right: kind == LedgerKind.expense ? 8 : 0,
                ),
                child: _kindChip(context, kind),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
            border: Border.all(color: c.line2),
          ),
          child: Row(
            children: [
              Text(
                '¥',
                style: context.heading(size: CitroType.titleLg, color: c.inkSoft),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: context.heading(size: CitroType.titleLg, color: c.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '0.00',
                    hintStyle: context.heading(
                      size: CitroType.titleLg,
                      color: c.inkSoft.withAlpha(90),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final cat in categories) _categoryChip(context, cat),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          style: context.body(size: CitroType.meta, color: c.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: c.surface2,
            hintText: '备注（可选）',
            hintStyle: context.body(size: CitroType.meta, color: c.inkSoft),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CitroColors.radii.inner),
              borderSide: BorderSide(color: c.line2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CitroColors.radii.inner),
              borderSide: BorderSide(color: c.accent),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: context.body(size: CitroType.caption, color: c.stamp),
          ),
        ],
        const SizedBox(height: 14),
        AccentButton(text: '记下来', onTap: _save),
      ],
    );
  }

  Widget _kindChip(BuildContext context, LedgerKind kind) {
    final c = context.c;
    final selected = kind == _kind;
    return Pressable(
      onTap: () => _switchKind(kind),
      scale: .96,
      hoverLift: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? c.accentLt.withAlpha(c.dark ? 70 : 170)
              : c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Text(
          kind.label,
          style: context.body(
            size: CitroType.meta,
            weight: selected ? CitroType.medium : CitroType.regular,
            color: selected ? c.accentInk : c.ink2,
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(BuildContext context, LedgerCategory cat) {
    final c = context.c;
    final selected = cat.id == _categoryId;
    return Pressable(
      onTap: () => setState(() {
        _categoryId = cat.id;
        _error = null;
      }),
      scale: .96,
      hoverLift: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? c.accentLt.withAlpha(c.dark ? 70 : 170)
              : c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: selected ? c.accent : c.line2),
        ),
        child: Text(
          cat.name,
          style: context.body(
            size: CitroType.caption,
            weight: selected ? CitroType.medium : CitroType.regular,
            color: selected ? c.accentInk : c.ink2,
          ),
        ),
      ),
    );
  }
}

/// 记一条今日待办的轻量弹层。
class _TodoQuickAddDialog extends StatefulWidget {
  const _TodoQuickAddDialog();

  @override
  State<_TodoQuickAddDialog> createState() => _TodoQuickAddDialogState();
}

class _TodoQuickAddDialogState extends State<_TodoQuickAddDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '写个标题吧');
      return;
    }
    final store = TodoStore.instance;
    final now = DateTime.now();
    store.createTask(
      title: title,
      note: _note.text.trim(),
      kind: TodoKind.task,
      categoryId: store.categories.isEmpty ? 'study' : store.categories.first.id,
      listId: store.lists.isEmpty ? 'default' : store.lists.first.id,
      dueAt: DateTime(now.year, now.month, now.day, 23, 59),
      source: 'cici',
    );
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '记一条今日待办',
          style: context.heading(size: CitroType.subtitle, color: c.ink),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          autofocus: true,
          style: context.body(size: CitroType.meta, color: c.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: c.surface2,
            hintText: '例如：给妈妈打个电话',
            hintStyle: context.body(size: CitroType.meta, color: c.inkSoft),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CitroColors.radii.inner),
              borderSide: BorderSide(color: c.line2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CitroColors.radii.inner),
              borderSide: BorderSide(color: c.accent),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          style: context.body(size: CitroType.meta, color: c.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: c.surface2,
            hintText: '备注（可选）',
            hintStyle: context.body(size: CitroType.meta, color: c.inkSoft),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CitroColors.radii.inner),
              borderSide: BorderSide(color: c.line2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CitroColors.radii.inner),
              borderSide: BorderSide(color: c.accent),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: context.body(size: CitroType.caption, color: c.stamp),
          ),
        ],
        const SizedBox(height: 14),
        AccentButton(text: '加入待办', onTap: _save),
      ],
    );
  }
}

/// 删除类能力的二次确认。
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmText,
  });

  final String title;
  final String body;
  final String confirmText;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.heading(size: CitroType.subtitle, color: c.ink),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: context.body(size: CitroType.meta, color: c.inkSoft, height: 1.5),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AccentButton(
                text: '取消',
                outlined: true,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AccentButton(
                text: confirmText,
                danger: true,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LocalImage extends StatefulWidget {
  const _LocalImage({
    required this.dataUrl,
    required this.width,
    required this.height,
  });

  final String dataUrl;
  final double width;
  final double height;

  @override
  State<_LocalImage> createState() => _LocalImageState();
}

class _LocalImageState extends State<_LocalImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant _LocalImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataUrl != widget.dataUrl) _decode();
  }

  void _decode() {
    try {
      final comma = widget.dataUrl.indexOf(',');
      _bytes = comma < 0
          ? null
          : base64Decode(widget.dataUrl.substring(comma + 1));
    } catch (_) {
      _bytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_bytes == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: c.surface2,
        child: Icon(Icons.broken_image_outlined, size: 18, color: c.inkSoft),
      );
    }
    return Image.memory(
      _bytes!,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      cacheWidth: (widget.width * 2.2).round(),
    );
  }
}
