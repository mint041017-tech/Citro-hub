import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/ai.dart';
import '../services/media.dart';
import '../services/platform.dart' as platform;
import '../services/speech.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/cici_composer.dart';
import '../widgets/paper.dart';
import 'ledger_ai.dart';
import 'ledger_models.dart';
import 'ledger_store.dart';
import 'ledger_theme.dart';
import 'ledger_widgets.dart';

/// 记账模块里的 cici：看账、给建议、自然语言代记账。
///
/// 和历史对话一致，AI 只输出 ledger 动作块，客户端解析成草稿卡，
/// 用户点「确认入账」之后才真正写入账本。
class LedgerCiciTab extends StatefulWidget {
  final String monthKey;

  const LedgerCiciTab({super.key, required this.monthKey});

  @override
  State<LedgerCiciTab> createState() => _LedgerCiciTabState();
}

class _CiciMsg {
  final bool user;
  String text;
  bool pending;
  final String? image;
  List<LedgerDraft> drafts = const [];
  bool confirmed = false;

  _CiciMsg({
    required this.user,
    this.text = '',
    this.pending = false,
    this.image,
  });
}

/// 会话级历史：切页、返回首页都保留，App 退出后自然清空。
final List<_CiciMsg> _history = [];

class _LedgerCiciTabState extends State<LedgerCiciTab>
    with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;
  String? _error;
  String? _pendingImage;
  bool _picking = false;
  bool _listening = false;
  String _voiceBase = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LedgerStore.instance.ensureInit();
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
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                  itemCount: _history.length,
                  itemBuilder: (context, i) => _bubble(context, _history[i]),
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              _error!,
              style: context.lui(size: CitroType.caption, color: c.stamp),
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
    final store = LedgerStore.instance;
    final summary = store.summaryFor(widget.monthKey);
    final plan = store.planFor(widget.monthKey);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      children: [
        PaperCard(
          tapeColor: c.tape2,
          tapeAngle: 2.2,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                        'cici',
                        style: context.lui(
                          weight: CitroType.strong,
                          size: CitroType.titleLg,
                        ),
                      ),
                      Text(
                        '你的记账搭子',
                        style: context.lui(
                          size: CitroType.meta,
                          color: c.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                summary.entryCount == 0
                    ? '这个月还没有账单。把你花的钱说给我，我来帮你记；也可以发一张支付截图。'
                    : '${LedgerDates.monthLabel(widget.monthKey)}：支出 '
                          '${ledgerMoney(summary.expenseCents)}，收入 '
                          '${ledgerMoney(summary.incomeCents)}。'
                          '${plan.hasBudget ? '预算还剩 ${ledgerMoney(summary.budgetRemainingCents)}。' : '还没有设置预算。'}'
                          '想让我分析哪一块？',
                style: context.lui(
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
          '可以这样问',
          style: context.lui(
            size: CitroType.label,
            weight: CitroType.strong,
            color: c.inkSoft,
          ),
        ),
        const SizedBox(height: 8),
        for (final prompt in _prompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Pressable(
              onTap: () => _send(prompt),
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
                        prompt,
                        style: context.lui(size: CitroType.body, color: c.ink2),
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
    '这个月花超了吗',
    '帮我分析一下餐饮支出',
    '奶茶 18 块，帮我记上',
    '怎么才能再多省下 500',
  ];

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
      ledgerToast(context, '当前设备暂不支持语音输入，可以先打字。');
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
        ledgerToast(context, '没有听清，再说一次试试。');
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
      if (mounted) ledgerToast(context, '图片读取失败，换一张试试');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

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

  Future<void> _send(String raw) async {
    final text = raw.trim();
    final image = _pendingImage;
    if ((text.isEmpty && image == null) || _sending) return;
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
    _toEnd();

    final store = LedgerStore.instance;
    final month = widget.monthKey;
    final contextText = LedgerAi.contextFor(
      monthKey: month,
      summary: store.summaryFor(month),
      plan: store.planFor(month),
      budgets: store.categoryBudgets(month),
      recent: store.recentEntries(limit: 8),
      monthEntries: store.entriesInMonth(month),
      categories: store.categories,
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
        extraSystem: '${LedgerAi.assistantSystem}\n\n【当前账本数据】\n$contextText',
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
      final (clean, drafts) = LedgerAi.parseReply(
        buffer.toString(),
        categories: store.categories,
      );
      if (!mounted) return;
      setState(() {
        assistant.text = clean.isEmpty ? '我没组织好这句话，再说一次？' : clean;
        assistant.pending = false;
        assistant.drafts = drafts;
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

  void _confirmDrafts(_CiciMsg msg) {
    if (msg.confirmed || msg.drafts.isEmpty) return;
    final store = LedgerStore.instance;
    var count = 0;
    for (final draft in msg.drafts) {
      if (draft.amountCents <= 0) continue;
      final category = store.categoryOf(draft.categoryId, kind: draft.kind);
      store.addEntry(
        kind: draft.kind,
        amountCents: draft.amountCents,
        categoryId: category.id,
        note: draft.note,
        occurredAt: draft.occurredAt,
        source: LedgerSource.cici,
      );
      count++;
    }
    setState(() => msg.confirmed = true);
    ledgerToast(context, count == 0 ? '没有可入账的账单' : '已入账 $count 笔');
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: CitroMotion.easeOut,
      );
    });
  }

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
                    style: context.lui(
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
                          '正在翻账本…',
                          style: context.lui(
                            size: CitroType.meta,
                            color: c.inkSoft,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (m.text.isNotEmpty)
                          Text(
                            m.text,
                            style: context.lui(
                              size: CitroType.body,
                              color: c.ink,
                              height: 1.7,
                            ),
                          ),
                        if (m.drafts.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _draftCard(context, m),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _draftCard(BuildContext context, _CiciMsg msg) {
    final c = context.c;
    final store = LedgerStore.instance;
    final total = msg.drafts.fold<int>(
      0,
      (sum, draft) => sum + draft.amountCents,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: c.noteG,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: c.mintLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(
                strokeSvg(AppIcons.wallet, width: 1.9),
                size: 14,
                color: c.mintInk,
              ),
              const SizedBox(width: 5),
              Text(
                '待确认账单',
                style: context.lui(
                  size: CitroType.caption,
                  weight: CitroType.strong,
                  color: c.mintInk,
                ),
              ),
              const Spacer(),
              Text(
                ledgerMoney(total),
                style: context.lui(
                  size: CitroType.caption,
                  weight: CitroType.strong,
                  color: c.mintInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final draft in msg.drafts)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${draft.kind.label} · '
                      '${store.categoryOf(draft.categoryId, kind: draft.kind).name}'
                      '${draft.note.isEmpty ? '' : ' · ${draft.note}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.lui(size: CitroType.small, color: c.ink2),
                    ),
                  ),
                  Text(
                    ledgerMoney(draft.amountCents),
                    style: context.lui(
                      size: CitroType.small,
                      weight: CitroType.strong,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          if (msg.confirmed)
            Row(
              children: [
                AppIcon(
                  strokeSvg(AppIcons.check, width: 2.2),
                  size: 13,
                  color: c.mintInk,
                ),
                const SizedBox(width: 4),
                Text(
                  '已入账',
                  style: context.lui(size: CitroType.caption, color: c.mintInk),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: Pressable(
                onTap: () => _confirmDrafts(msg),
                scale: .96,
                hoverLift: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                  ),
                  child: Text(
                    '确认入账',
                    style: context.lui(
                      size: CitroType.caption,
                      weight: CitroType.strong,
                      color: const Color(0xFF2E2C22),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 快捷动作 + 输入栏
  // -------------------------------------------------------------------------

  Widget _quickActions(BuildContext context) {
    final c = context.c;
    const items = [
      (AppIcons.trendUp, '分析'),
      (AppIcons.flag, '超支'),
      (AppIcons.heart, '省钱'),
      (AppIcons.wallet, '记一笔'),
    ];
    const prompts = [
      '分析一下这个月的收支，给我 3 条建议',
      '这个月哪些分类超预算了',
      '帮我找找可以省下来的钱',
      '奶茶 18 块，帮我记上',
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = items[index];
          return Pressable(
            onTap: () => _send(prompts[index]),
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
                  AppIcon(
                    strokeSvg(item.$1, width: 1.9),
                    size: 14,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.$2,
                    style: context.lui(size: CitroType.caption, color: c.ink2),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final c = context.c;
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
                      '这张图会一起发给 cici',
                      style: context.lui(
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
    return _desktopComposer(context);
  }

  Widget _desktopComposer(BuildContext context) {
    final c = context.c;
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
                color: active ? c.accent2 : c.accentInk,
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
                      '这张图会一起发给 cici',
                      style: context.lui(
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
                    style: context.lui(size: CitroType.body),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '和 cici 说说这个月的账…',
                      hintStyle: context.lui(
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
}
