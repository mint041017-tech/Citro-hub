import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai.dart';
import '../services/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';

class _ChatMessage {
  final bool user;
  String text;
  bool pending;
  _ChatMessage({required this.user, required this.text, this.pending = false});
}

final List<_ChatMessage> _history = [];

Future<void> showAiChat(BuildContext context, {Recipe? recipe}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8A23211C),
    builder: (_) => _AiChatSheet(recipe: recipe),
  );
}

class _AiChatSheet extends StatefulWidget {
  final Recipe? recipe;
  const _AiChatSheet({this.recipe});
  @override
  State<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<_AiChatSheet> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
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

  Future<void> _send([String? preset]) async {
    if (_sending) return;
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty) return;
    if (!AiService.available) {
      setState(() => _error = 'AI 暂未配置');
      return;
    }
    _input.clear();
    _error = null;
    final assistant = _ChatMessage(user: false, text: '', pending: true);
    setState(() {
      _history.add(_ChatMessage(user: true, text: text));
      _history.add(assistant);
      _sending = true;
    });
    _scrollToEnd();

    final source = _history
        .where((m) => !m.pending && m.text.isNotEmpty)
        .map((m) => {'role': m.user ? 'user' : 'assistant', 'content': m.text})
        .toList();
    final messages = source.length > 14
        ? source.sublist(source.length - 14)
        : source;

    try {
      await for (final chunk in AiService.streamChat(
        messages,
        extraSystem: widget.recipe == null
            ? null
            : _recipeContext(widget.recipe!),
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

  void _clear() {
    if (_sending) return;
    setState(() {
      _history.clear();
      _error = null;
    });
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: PaperBackground(
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
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.line2),
                            boxShadow: CitroColors.shadows.note(c),
                          ),
                          child: Center(
                            child: AppIcon(
                              strokeSvg(AppIcons.sparkle, width: 2),
                              size: 19,
                              color: const Color(0xFF2E2C22),
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
                                style: context.heading(size: 20, color: c.ink),
                              ),
                              Text(
                                widget.recipe == null
                                    ? '嘴硬心软 · 极速回答'
                                    : '食谱助手 · ${widget.recipe!.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.body(
                                  size: 9.5,
                                  color: c.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _clear,
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(999),
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
                                    size: 12.5,
                                    weight: FontWeight.w600,
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
                  DashedLine(color: c.line2.withAlpha(150)),
                  Expanded(
                    child: _history.isEmpty
                        ? _welcome(context)
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                            itemCount: _history.length,
                            itemBuilder: (_, i) =>
                                _bubble(context, _history[i]),
                          ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text(
                        _error!,
                        style: context.body(size: 10.5, color: c.stamp),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 2),
                    child: Text(
                      'AI 生成内容仅供参考；对话会发送至第三方 AI 服务处理，请勿发送敏感信息。',
                      textAlign: TextAlign.center,
                      style: context.body(size: 9.5, color: c.inkSoft),
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
    final prompts = widget.recipe == null
        ? ['帮我写一句手账文案', '今天吃什么？', '社区怎么玩？', '安慰一下我']
        : ['这道菜怎么补救？', '换成家常做法', '帮我看下火候', '列个采购清单'];
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
                child: Image.asset(
                  'assets/images/cats/23757.webp',
                  width: 82,
                  height: 82,
                  fit: BoxFit.contain,
                  cacheWidth: 250,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: c.noteY.withAlpha(170),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(3),
                      topRight: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    border: Border.all(color: c.line),
                  ),
                  child: Text(
                    widget.recipe == null
                        ? '你好呀，我是 CiCi。\n今天想聊点什么？'
                        : '你好呀，我是 CiCi。\n关于《${widget.recipe!.name}》，想聊点什么？',
                    style: context.body(size: 13, color: c.ink2, height: 1.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '可以试试',
            style: context.body(
              size: 10.5,
              weight: FontWeight.w700,
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
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.line),
                    ),
                    child: Text(
                      p,
                      style: context.body(size: 11.5, color: c.ink2),
                    ),
                  ),
                ),
            ],
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
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(15),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(15),
              bottomRight: Radius.circular(15),
            ),
            boxShadow: CitroColors.shadows.note(c),
          ),
          child: Text(
            m.text,
            style: context.body(
              size: 13,
              color: const Color(0xFF2E2C22),
              height: 1.65,
            ),
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
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: c.hl,
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
            child: Center(
              child: AppIcon(
                strokeSvg(AppIcons.sparkle, width: 2),
                size: 13,
                color: c.accentInk,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .76,
              ),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(15),
                  bottomLeft: Radius.circular(15),
                  bottomRight: Radius.circular(15),
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
                        const SizedBox(width: 7),
                        Text(
                          '正在想想…',
                          style: context.body(size: 11.5, color: c.inkSoft),
                        ),
                      ],
                    )
                  : Text(
                      m.text,
                      style: context.body(size: 13, color: c.ink, height: 1.7),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: c.surface.withAlpha(235),
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 40, maxHeight: 108),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.line2),
              ),
              child: TextField(
                controller: _input,
                focusNode: _focus,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onTap: () {
                  _focus.requestFocus();
                  SystemChannels.textInput.invokeMethod<void>('TextInput.show');
                },
                onSubmitted: (_) => _send(),
                onTapOutside: (_) => _focus.unfocus(),
                style: context.body(size: 13, height: 1.5),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: '和 CiCi 聊聊…',
                  hintStyle: context.body(size: 12.5, color: c.inkSoft),
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
                boxShadow: _sending ? null : CitroColors.shadows.note(c),
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
                        color: const Color(0xFF2E2C22),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AiHomeButton extends StatelessWidget {
  const AiHomeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: () => showAiChat(context),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: c.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: c.accent, width: 1.4),
          boxShadow: CitroColors.shadows.lg(c),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              strokeSvg(AppIcons.sparkle, width: 2),
              size: 18,
              color: c.accentInk,
            ),
            const SizedBox(height: 1),
            Text(
              'CiCi',
              style: context.display(
                size: 8.5,
                weight: FontWeight.w700,
                color: c.accentInk,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
