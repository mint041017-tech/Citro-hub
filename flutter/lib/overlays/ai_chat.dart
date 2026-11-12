import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai.dart';
import '../services/api.dart';
import '../services/cici_persona.dart';
import '../services/media.dart';
import '../services/platform.dart' as platform;
import '../services/speech.dart';
import '../state/app_state.dart';
import '../services/models.dart';
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

  /// 桌面端麦克风按钮的长按说话：按下超过 0.42s 开始听写，松手停止；
  /// 短按仍然只是开关。
  Timer? _micTimer;
  bool _micLongPressed = false;

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
    _micTimer?.cancel();
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
      // 系统听写的 stop 在某些 ROM 上会一直不回，别让这次点击吊在这里。
      await SpeechInput.stop().timeout(const Duration(seconds: 3), onTimeout: () {});
      return;
    }
    final ready = await SpeechInput.ensureReady().timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
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

  /// 桌面端麦克风机按下：0.42s 后开始听写，松手停止；短按只切换开关。
  void _micDown() {
    if (_sending || _picking) return;
    _micLongPressed = false;
    _micTimer?.cancel();
    _micTimer = Timer(const Duration(milliseconds: 420), () {
      _micLongPressed = true;
      if (!_listening) _toggleVoice();
    });
  }

  void _micUp() {
    _micTimer?.cancel();
    _micTimer = null;
    if (_micLongPressed && _listening) _toggleVoice();
  }

  /// [keepInput] 为 true 时（快捷「建议」）发送预设文案，但保留输入框里
  /// 用户已经打了一半的内容，不清空。
  Future<void> _send([String? preset, bool keepInput = false]) async {
    if (_sending) return;
    final text = (preset ?? _input.text).trim();
    final image = preset == null ? _pendingImage : null;
    if (text.isEmpty && image == null) return;
    if (!keepInput) _input.clear();
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

  /// 顶栏的圆形图标按钮：性格 / 新对话 / 关闭，三枚统一 36。
  Widget _HeaderIcon({
    required String icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final c = context.c;
    return Semantics(
      label: tooltip,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: c.line2),
          ),
          child: Center(
            child: AppIcon(strokeSvg(icon, width: 2), size: 18, color: c.ink2),
          ),
        ),
      ),
    );
  }

  /// 紧凑通知条：图标 + 一行字，比原来的大横幅矮一半。
  Widget _notice(
    BuildContext context, {
    required String icon,
    required Color color,
    required Color background,
    required Color border,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(CitroColors.radii.small),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          AppIcon(strokeSvg(icon, width: 2), size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.body(
                size: CitroType.micro,
                weight: CitroType.medium,
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CitroColors.radii.card),
        ),
        child: ColoredBox(
          // CiCi 页面统一用奶米底（玻璃已取消，实心即可）。
          color: const Color(0xFFF9EDD7),
          child: SizedBox(
            height: height,
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
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
                                style: context.heading(
                                  size: CitroType.titleLg,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.body(
                                  size: CitroType.micro,
                                  color: c.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 三个等大的圆形图标按钮：性格 / 新对话 / 关闭。
                        // 以前是「带字胶囊 + 圆形」混着来，宽度不一、重心乱；
                        // 现在统一 36 圆钮，一行对齐，功能都还在。
                        _HeaderIcon(
                          icon: AppIcons.sparkle,
                          tooltip: '性格',
                          onTap: _editPersona,
                        ),
                        const SizedBox(width: 6),
                        _HeaderIcon(
                          icon: AppIcons.plus,
                          tooltip: '新对话',
                          onTap: _clear,
                        ),
                        const SizedBox(width: 6),
                        _HeaderIcon(
                          icon: AppIcons.close,
                          tooltip: '关闭',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  CitroDivider(color: c.line2.withAlpha(150)),
                  // 奖励 / 转运提示：合并成一块紧凑的通知区，不再上下各挂一条
                  // 大横幅把消息列表挤窄。
                  if (_chatRewarded || (widget.goodDeed && _deedShared))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Column(
                        children: [
                          if (_chatRewarded)
                            _notice(
                              context,
                              icon: AppIcons.sparkle,
                              color: c.accentInk,
                              background: c.accentLt.withAlpha(
                                c.dark ? 70 : 170,
                              ),
                              border: c.accent.withAlpha(80),
                              text: '今日首次找 CiCi · 卡面抽卡机会 +1，去「我的 - 卡面收藏」抽',
                            ),
                          if (widget.goodDeed && _deedShared) ...[
                            if (_chatRewarded) const SizedBox(height: 6),
                            _notice(
                              context,
                              icon: AppIcons.sparkle,
                              color: c.mintInk,
                              background: c.mintSoft,
                              border: c.mintLine,
                              text: '转运机会 +1 · 关掉对话，回签卡点「再抽一签」',
                            ),
                          ],
                        ],
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
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text(
                        _error!,
                        style: context.body(
                          size: CitroType.small,
                          color: c.stamp,
                        ),
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
    final greeting = widget.recipe != null
        ? '关于《${widget.recipe!.name}》，想聊点什么？'
        : widget.goodDeed
        ? '今天抽到下签也别慌。跟我说说你今天做的一件好事，我帮你转运一次。'
        : '今天想聊点什么？';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 居中头像 + 打招呼：以前是 72 大图斜 3° 配右侧气泡，
          // 重心偏左、右侧留白偏大，现在收成一列，视觉重心稳。
          Center(
            child: Container(
              width: 64,
              height: 64,
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
                  cacheWidth: 192,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '你好呀，我是 CiCi',
              style: context.heading(size: CitroType.titleLg, color: c.ink),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              greeting,
              textAlign: TextAlign.center,
              style: context.body(
                size: CitroType.meta,
                color: c.inkSoft,
                height: 1.6,
              ),
            ),
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
                style: context.body(
                  size: CitroType.caption,
                  color: c.mintInk,
                  height: 1.6,
                ),
              ),
            ),
          ],
          if (prompts.isNotEmpty) ...[
            const SizedBox(height: 20),
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
                        borderRadius: BorderRadius.circular(
                          CitroColors.radii.chip,
                        ),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        p,
                        style: context.body(
                          size: CitroType.caption,
                          color: c.ink2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'AI 生成内容仅供参考；文字与图片会发送至第三方 AI 服务处理，请勿发送敏感信息。',
            textAlign: TextAlign.center,
            style: context.body(
              size: CitroType.micro,
              color: c.inkSoft,
              height: 1.5,
            ),
          ),
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
                          style: context.body(
                            size: CitroType.caption,
                            color: c.inkSoft,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      m.text,
                      style: context.body(
                        size: CitroType.meta,
                        color: c.ink,
                        height: 1.7,
                      ),
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
        // 输入栏下方不再垫底色，直接落在页面底上。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingImage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        CitroColors.radii.small,
                      ),
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
      // 输入栏下方不再垫底色，直接落在页面底上。
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          CitroColors.radii.small,
                        ),
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
                      style: context.body(
                        size: CitroType.small,
                        color: c.inkSoft,
                      ),
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
                      style: context.body(
                        size: CitroType.small,
                        color: c.accentInk,
                      ),
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
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.only(right: 8, bottom: 2),
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
              Listener(
                onPointerDown: (_) => _micDown(),
                onPointerUp: (_) => _micUp(),
                onPointerCancel: (_) => _micUp(),
                child: GestureDetector(
                  onTap: () {
                    if (_micLongPressed) {
                      _micLongPressed = false;
                      return;
                    }
                    if (!_sending && !_picking) _toggleVoice();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 8, bottom: 2),
                    decoration: BoxDecoration(
                      color: _listening ? c.accent.withAlpha(36) : c.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _listening ? c.accent : c.line2,
                      ),
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: animation,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
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
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 38,
                    maxHeight: 108,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(
                      CitroColors.radii.inner,
                    ),
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
                      hintStyle: context.body(
                        size: CitroType.meta,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sending ? null : _send,
                child: Container(
                  width: 38,
                  height: 38,
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
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CitroColors.radii.card),
          ),
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
                      style: context.heading(
                        size: CitroType.titleLg,
                        color: c.ink,
                      ),
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
                  style: context.body(
                    size: CitroType.caption,
                    color: c.inkSoft,
                    height: 1.6,
                  ),
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
                  style: context.body(
                    size: CitroType.body,
                    color: c.ink,
                    height: 1.6,
                  ),
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
                    counterStyle: context.body(
                      size: CitroType.small,
                      color: c.inkSoft,
                    ),
                    contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        CitroColors.radii.inner,
                      ),
                      borderSide: BorderSide(color: c.line2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        CitroColors.radii.inner,
                      ),
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
          color: selected
              ? c.accentLt.withAlpha(c.dark ? 70 : 170)
              : c.surface2,
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
