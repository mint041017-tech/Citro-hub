import 'package:flutter/material.dart';

import 'dart:convert';

import '../services/ai.dart';
import '../services/media.dart';
import '../services/platform.dart' as platform;
import '../services/pomodoro.dart';
import '../services/speech.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/cici_composer.dart';
import '../widgets/paper.dart';
import 'todo_ai.dart';
import 'todo_models.dart';
import 'todo_store.dart';

/// 小c助手：带待办上下文的 CiCi。可以创建任务、拆解、总结、查询、给建议。
class TodoCici extends StatefulWidget {
  const TodoCici({super.key});

  @override
  State<TodoCici> createState() => _TodoCiciState();
}

class _CiciMsg {
  final bool user;
  String text;
  bool pending;
  List<TodoDraft> created;

  /// 用户上传的图片（data URL），随消息一起发给 CiCi。
  final String? image;

  _CiciMsg({
    required this.user,
    this.text = '',
    this.pending = false,
    this.created = const [],
    this.image,
  });
}

/// 会话级历史：切页面、关面板都保留，App 退出后自然清空。
final List<_CiciMsg> _history = [];

class _TodoCiciState extends State<TodoCici> with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;
  String? _error;

  /// 图片与语音：和首页 CiCi 一样，可以说完就发、或者带一张图问。
  String? _pendingImage;
  bool _picking = false;
  bool _listening = false;
  String _voiceBase = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TodoStore.instance.ensureInit();
    PomodoroState.instance.ensureInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SpeechInput.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 键盘弹起/收起会改变视口高度，等布局完成再贴底；稍后再补一次，
    // 因为部分系统键盘的最终高度会晚一帧才稳定。
    _jumpEnd();
    Future<void>.delayed(const Duration(milliseconds: 260), _jumpEnd);
  }

  void _jumpEnd() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Expanded(
          child: _history.isEmpty
              ? _welcome(context)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  itemCount: _history.length,
                  itemBuilder: (context, i) => _bubble(context, _history[i]),
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              _error!,
              style: context.ui(size: CitroType.caption, color: c.stamp),
            ),
          ),
        _quickActions(context),
        _composer(context),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 欢迎页
  // -------------------------------------------------------------------------

  Widget _welcome(BuildContext context) {
    final c = context.c;
    final store = TodoStore.instance;
    final open = store.todayTasks.where((t) => !t.done).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
            boxShadow: CitroColors.shadows.paper(c),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c.accent.withAlpha(45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(AppIcons.sparkle, width: 2),
                        size: 18,
                        color: c.accentInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CiCi',
                        style: context.ui(
                          weight: CitroType.strong,
                          size: CitroType.titleLg,
                        ),
                      ),
                      Text(
                        '待办助手',
                        style: context.ui(
                          size: CitroType.meta,
                          color: c.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                open == 0
                    ? '今天的事项都处理完了，或者还没有任务。你可以让我帮你拆解一件正在拖的事。'
                    : '今天还有 $open 条没完成。可以直接告诉我「明天下午三点提醒我交周报」，我会创建任务。',
                style: context.ui(
                  size: CitroType.body,
                  color: c.ink2,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '可以这样用',
          style: context.ui(
            size: CitroType.label,
            weight: CitroType.strong,
            color: c.inkSoft,
          ),
        ),
        const SizedBox(height: 8),
        for (final p in _prompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Pressable(
              onTap: () => _send(p),
              scale: .995,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: c.bg2.withAlpha(c.dark ? 120 : 80),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p,
                        style: context.ui(size: CitroType.body, color: c.ink2),
                      ),
                    ),
                    AppIcon(
                      strokeSvg(AppIcons.arrowRight, width: 1.8),
                      size: 16,
                      color: c.inkSoft,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  static const _prompts = [
    '帮我看看今天还有什么没做',
    '明天下午三点提醒我交周报',
    '把「准备周会」拆成几个小步骤',
    '客观总结一下我今天的状态',
  ];

  // -------------------------------------------------------------------------
  // 气泡
  // -------------------------------------------------------------------------

  Widget _bubble(BuildContext context, _CiciMsg m) {
    final c = context.c;
    if (m.user) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2, left: 42),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              color: c.accent.withAlpha(c.dark ? 60 : 46),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(color: c.accent.withAlpha(90)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.image != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.memory(
                      base64Decode(m.image!.split(',').last),
                      width: 150,
                      height: 110,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (m.text.isNotEmpty) const SizedBox(height: 6),
                ],
                if (m.text.isNotEmpty)
                  Text(
                    m.text,
                    style: context.ui(
                      size: CitroType.body,
                      color: c.ink,
                      height: 1.6,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2, right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: c.accent.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: AppIcon(
                strokeSvg(AppIcons.sparkle, width: 2),
                size: 14,
                color: c.accentInk,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
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
                            strokeWidth: 2,
                            color: c.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '正在想想…',
                          style: context.ui(
                            size: CitroType.meta,
                            color: c.inkSoft,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.text,
                          style: context.ui(
                            size: CitroType.body,
                            color: c.ink,
                            height: 1.7,
                          ),
                        ),
                        if (m.created.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final d in m.created)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                children: [
                                  AppIcon(
                                    strokeSvg(AppIcons.check, width: 2),
                                    size: 13,
                                    color: c.mintInk,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      d.update
                                          ? '已更新：${d.title}'
                                          : '已创建：${d.title}',
                                      style: context.ui(
                                        size: CitroType.caption,
                                        color: c.inkSoft,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 快捷动作
  // -------------------------------------------------------------------------

  Widget _quickActions(BuildContext context) {
    final c = context.c;
    const items = [
      (AppIcons.sparkle, '拆解'),
      (AppIcons.note, '总结'),
      (AppIcons.list, '查询'),
      (AppIcons.flag, '建议'),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final item = items[i];
          return Pressable(
            scale: .95,
            onTap: () => _action(context, i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    strokeSvg(item.$1, width: 1.8),
                    size: 15,
                    color: c.inkSoft,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    item.$2,
                    style: context.ui(size: CitroType.label, color: c.ink2),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _action(BuildContext context, int index) async {
    switch (index) {
      case 0:
        await _pickBreakdown(context);
      case 1:
        await _summarize(context);
      case 2:
        _query();
      case 3:
        await _suggest(context);
    }
  }

  Future<void> _pickBreakdown(BuildContext context) async {
    final open = TodoStore.instance.tasks.where((t) => !t.done).toList();
    if (open.isEmpty) {
      AppToast.show(context, '没有可以拆解的任务');
      return;
    }
    final picked = await showModalBottomSheet<TodoTask>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final c = ctx.c;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * .6,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: c.line),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '拆解哪一条',
                style: ctx.ui(
                  weight: CitroType.strong,
                  size: CitroType.titleLg,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in open.take(30))
                      Pressable(
                        onTap: () => Navigator.of(ctx).pop(t),
                        scale: .995,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: c.line),
                          ),
                          child: Text(
                            t.title,
                            style: ctx.ui(size: CitroType.body, color: c.ink),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !context.mounted) return;
    final subs = await _run(context, () => TodoAi.breakdown(picked), '正在拆解…');
    if (subs == null || subs.isEmpty || !context.mounted) return;
    TodoStore.instance.addSubtasks(picked, subs);
    _appendAssistant(
      '已把「${picked.title}」拆成 ${subs.length} 步：\n${subs.map((e) => '· $e').join('\n')}',
    );
  }

  Future<void> _summarize(BuildContext context) async {
    final store = TodoStore.instance;
    final now = DateTime.now();
    final text = await _run(
      context,
      () => TodoAi.summary(
        day: now,
        tasks: store.tasksOn(now),
        moods: store.moodsOn(now),
        focusMinutes: _focusMinutes(now),
        streak: store.streak,
      ),
      '正在总结…',
    );
    if (text == null || !mounted) return;
    await store.saveReview(now, text, ai: true);
    _appendAssistant(text);
    if (mounted) AppToast.show(context, '总结已写入今日复盘');
  }

  Future<void> _suggest(BuildContext context) async {
    final store = TodoStore.instance;
    final week = store.weekDone;
    final text = await _run(
      context,
      () => TodoAi.suggest(
        recent: store.tasks,
        doneByDay: {for (final e in week) e.$1: e.$2},
        focusMinutes: PomodoroState.instance.weekMinutes.fold<int>(
          0,
          (a, b) => a + b,
        ),
      ),
      '正在看数据…',
    );
    if (text != null) _appendAssistant(text);
  }

  void _query() {
    final store = TodoStore.instance;
    final tasks = store.todayTasks;
    if (tasks.isEmpty) {
      _appendAssistant('今天没有任务。');
      return;
    }
    final done = tasks.where((t) => t.done).length;
    final open = tasks.where((t) => !t.done).toList();
    final buffer = StringBuffer('今天共 ${tasks.length} 条，已完成 $done 条。');
    if (open.isNotEmpty) {
      buffer.write('\n未完成：');
      for (final t in open) {
        final time = taskTimeText(t);
        buffer.write('\n· ${t.title}${time.isEmpty ? '' : '（$time）'}');
      }
    }
    _appendAssistant(buffer.toString());
  }

  int _focusMinutes(DateTime day) {
    var total = 0;
    for (final s in PomodoroState.instance.sessions) {
      if (dayOf(s.at) == dayOf(day)) total += s.minutes;
    }
    return total;
  }

  // -------------------------------------------------------------------------
  // 对话
  // -------------------------------------------------------------------------

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

  /// 带图消息按多段 content 发给模型，和首页 CiCi 一致。
  dynamic _contentFor(_CiciMsg m) {
    if (m.image == null) return m.text;
    return <Map<String, dynamic>>[
      if (m.text.isNotEmpty) {'type': 'text', 'text': m.text},
      {
        'type': 'image_url',
        'image_url': {'url': m.image},
      },
    ];
  }

  Widget _composer(BuildContext context) {
    final c = context.c;
    // 手机端换成胶囊输入栏：图片 + 输入/按住说话 + 语音切换 + 发送。
    if (platform.isAndroid || platform.isIOS) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      base64Decode(_pendingImage!.split(',').last),
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '这张图会一起发给 CiCi',
                      style: context.ui(
                        size: CitroType.caption,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                  Pressable(
                    onTap: () => setState(() => _pendingImage = null),
                    scale: .9,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: AppIcon(
                        strokeSvg(AppIcons.close, width: 2),
                        size: 14,
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
            onSend: () => _send(_input.text),
            onPickImage: _pickImage,
            onSubmitVoice: (text) async {
              _input.text = text;
              await _send(text);
            },
          ),
        ],
      );
    }
    Widget circle(
      String icon, {
      bool active = false,
      VoidCallback? onTap,
      Widget? child,
    }) => Pressable(
      onTap: onTap,
      scale: .94,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? c.accent.withAlpha(36) : c.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: active ? c.accent : c.line2),
        ),
        child: Center(
          child:
              child ??
              AppIcon(
                strokeSvg(icon, width: 2),
                size: 18,
                color: active ? c.accent : c.accentInk,
              ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        6,
        16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      base64Decode(_pendingImage!.split(',').last),
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '这张图会一起发给 CiCi',
                      style: context.ui(
                        size: CitroType.caption,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                  Pressable(
                    onTap: () => setState(() => _pendingImage = null),
                    scale: .9,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: AppIcon(
                        strokeSvg(AppIcons.close, width: 2),
                        size: 14,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              circle(
                AppIcons.image,
                onTap: _picking || _sending ? null : _pickImage,
                child: _picking
                    ? SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: c.accent,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              circle(
                AppIcons.mic,
                active: _listening,
                onTap: _sending || _picking ? null : _toggleVoice,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 44,
                    maxHeight: 120,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.line),
                  ),
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    style: context.ui(size: CitroType.body),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '和 CiCi 说一句，回车发送…',
                      hintStyle: context.ui(
                        size: CitroType.body,
                        color: c.inkSoft,
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    ),
                    onSubmitted: (_) => _send(_input.text),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Pressable(
                onTap: () => _send(_input.text),
                scale: .94,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _sending ? c.line2 : c.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: AppIcon(
                      strokeSvg(AppIcons.send, width: 1.8, color: '#2E2C22'),
                      size: 18,
                      color: const Color(0xFF2E2C22),
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

  void _appendAssistant(String text, {List<TodoDraft> created = const []}) {
    setState(() {
      _history.add(_CiciMsg(user: false, text: text, created: created));
      _error = null;
    });
    _toEnd();
  }

  Future<T?> _run<T>(
    BuildContext context,
    Future<T> Function() task,
    String label,
  ) async {
    final msg = _CiciMsg(user: false, pending: true);
    setState(() => _history.add(msg));
    _toEnd();
    try {
      return await task();
    } catch (e) {
      setState(() {
        msg.pending = false;
        msg.text = e.toString().replaceFirst('AiException: ', '');
      });
      return null;
    } finally {
      setState(() => msg.pending = false);
    }
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    final image = _pendingImage;
    if ((text.isEmpty && image == null) || _sending) return;
    if (text.endsWith('：') || text.endsWith(':')) {
      final extra = _input.text.trim();
      if (extra.isEmpty) {
        _input.text = text;
        return;
      }
    }
    _input.clear();
    setState(() {
      _pendingImage = null;
      _history.add(_CiciMsg(user: true, text: text, image: image));
      _sending = true;
      _error = null;
    });
    _toEnd();

    final assistant = _CiciMsg(user: false, pending: true);
    setState(() => _history.add(assistant));

    final store = TodoStore.instance;
    final now = DateTime.now();
    final contextText = TodoAi.contextFor(
      tasks: store.tasks,
      moods: store.moods,
      focusMinutes: _focusMinutes(now),
      streak: store.streak,
      now: now,
    );

    final source = _history
        .where((m) => !m.pending && (m.text.isNotEmpty || m.image != null))
        .map(
          (m) => <String, dynamic>{
            'role': m.user ? 'user' : 'assistant',
            'content': _contentFor(m),
          },
        )
        .toList();
    final messages = source.length > 12
        ? source.sublist(source.length - 12)
        : source;

    try {
      final buffer = StringBuffer();
      await for (final chunk in AiService.streamChat(
        messages,
        extraSystem: '${TodoAi.assistantSystem}\n\n【当前待办数据】\n$contextText',
        persona: AppState.instance.ciciPersona,
      )) {
        if (!mounted) return;
        buffer.write(chunk);
        setState(() {
          assistant.text += chunk;
          assistant.pending = false;
        });
        _toEnd();
      }
      final (clean, drafts) = TodoAi.parseReply(buffer.toString());
      final created = _createDrafts(drafts);
      if (!mounted) return;
      setState(() {
        assistant.text = clean.isEmpty ? '我没有组织好这句话，再说一次？' : clean;
        assistant.pending = false;
        assistant.created = created;
      });
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
      _toEnd();
    }
  }

  List<TodoDraft> _createDrafts(List<TodoDraft> drafts) {
    if (drafts.isEmpty) return const [];
    final store = TodoStore.instance;
    final done = <TodoDraft>[];
    for (final d in drafts) {
      // 更新指令：按标题找到已有任务，补备注或改时间，不新建。
      if (d.update) {
        TodoTask? target;
        for (final t in store.tasks) {
          if (t.title.trim() == d.title.trim()) {
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
        done.add(d);
        continue;
      }
      final cat = store.categories.firstWhere(
        (c) => c.name == d.categoryName,
        orElse: () => store.categories.first,
      );
      store.createTask(
        title: d.title,
        note: d.note,
        kind: d.kind,
        categoryId: cat.id,
        listId: store.lists.first.id,
        remindAt: d.kind == TodoKind.reminder
            ? (d.at ?? DateTime.now().add(const Duration(hours: 1)))
            : null,
        dueAt: d.kind == TodoKind.task
            ? (d.at ?? DateTime.now().add(const Duration(days: 1)))
            : null,
        habitDays: d.kind == TodoKind.habit
            ? (d.days.isEmpty ? {1, 2, 3, 4, 5} : d.days)
            : null,
        habitTime: d.time,
        subtasks: d.subtasks,
        source: 'cici',
      );
      done.add(d);
    }
    return done;
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: CitroMotion.hover,
        curve: CitroMotion.easeOut,
      );
    });
  }
}
