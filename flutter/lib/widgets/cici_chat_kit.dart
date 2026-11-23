import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'paper.dart';

// =============================================================================
// CiCi 会话共享套件：消息模型 / 流式状态机 / 列表与输入器基础件。
//
// 本文件不直接依赖 lib/state、lib/services：系统提示词、性格、工具注册与执行、
// 持久化都由调用方组装后注入；这里只承载三处会话（账本 / 待办 / 通用浮层）
// 重复的通用骨架。业务侧差异（提示词、工具回执、气泡皮肤、入口壳）留在调用方。
// =============================================================================

/// 会话消息（单一数据类，三处共用一份定义）。
///
/// [extra] 留给业务侧挂载工具回执（草稿列表、确认状态、已建标题等），
/// kit 不解析、不序列化。当前会话历史只活在内存里，不落盘 JSON，
/// 因此不存在老数据字段兼容问题。
class CiciChatMessage {
  final bool user;
  String text;
  bool pending;
  final String? image;

  /// 业务侧工具回执，类型由调用方约定。
  Object? extra;

  CiciChatMessage({
    required this.user,
    this.text = '',
    this.pending = false,
    this.image,
    this.extra,
  });
}

/// 正文流工厂：调用方在闭包里组装系统提示 / 性格后调用 AI 服务并返回正文流。
typedef CiciChatStreamFactory = Stream<String> Function(
  List<Map<String, dynamic>> messages,
);

/// 异常分类：把底层异常翻译成气泡里的展示文案（AiException 取 message，
/// 其余走通用网络文案）。分类规则由调用方给出，kit 不认识服务层类型。
typedef CiciChatErrorClassifier = String Function(Object error);

/// 会话状态机：持有消息列表与发送中 / 错误 / 选图状态，驱动流式追加。
///
/// UI 刷新（setState）与滚动跟随仍由调用方负责；状态机只改数据，不碰 BuildContext。
class CiciChatSession {
  CiciChatSession({
    List<CiciChatMessage>? messages,
    this.historyLimit = 12,
  }) : messages = messages ?? [];

  /// 当前会话消息列表。浮层场景需要在两套历史之间切换，调用方在使用前重绑。
  List<CiciChatMessage> messages;

  /// 最多带进下一次请求的历史条数。
  final int historyLimit;

  bool sending = false;
  String? error;
  String? pendingImage;
  bool picking = false;

  /// 注入：把历史消息发给模型，返回正文流。
  CiciChatStreamFactory? streamFactory;

  /// 注入：异常 → 气泡展示文案。
  CiciChatErrorClassifier? classifyError;

  CiciChatMessage addUser(String text, String? image) =>
      CiciChatMessage(user: true, text: text, image: image);

  CiciChatMessage addAssistant({String text = '', bool pending = true}) =>
      CiciChatMessage(user: false, text: text, pending: pending);

  /// 多段 content：带图时拼 text + image_url；纯文本直接返回字符串。
  static dynamic contentFor(CiciChatMessage m) {
    if (m.image == null) return m.text;
    return <Map<String, dynamic>>[
      if (m.text.isNotEmpty) {'type': 'text', 'text': m.text},
      {
        'type': 'image_url',
        'image_url': {'url': m.image},
      },
    ];
  }

  /// 过滤占位 / 空内容消息，截断到最近 [historyLimit] 条，发给模型。
  List<Map<String, dynamic>> buildRequestMessages() {
    final source = messages
        .where((m) => !m.pending && (m.text.isNotEmpty || m.image != null))
        .map(
          (m) => <String, dynamic>{
            'role': m.user ? 'user' : 'assistant',
            'content': contentFor(m),
          },
        )
        .toList();
    return source.length > historyLimit
        ? source.sublist(source.length - historyLimit)
        : source;
  }

  /// 流式主循环：逐片追加到 [assistant]；结束后回调 [onReplied] 做业务解析
  /// 与工具落库；异常经 [classifyError] 写回气泡；finally 复位 [sending]。
  ///
  /// [onTick] 每来一片 / 状态变化后触发一次，调用方用来刷新 UI 与滚动跟随。
  Future<void> runAssistantStream(
    CiciChatMessage assistant, {
    required Future<void> Function() onReplied,
    VoidCallback? onTick,
  }) async {
    final source = buildRequestMessages();
    try {
      await for (final chunk in streamFactory!(source)) {
        assistant.text += chunk;
        assistant.pending = false;
        onTick?.call();
      }
      await onReplied();
    } catch (e) {
      assistant.pending = false;
      assistant.text = classifyError?.call(e) ?? e.toString();
      onTick?.call();
    } finally {
      sending = false;
      onTick?.call();
    }
  }
}

// =============================================================================
// 展示基础件
// =============================================================================

/// 本地 data URL 图片：解码失败给占位图标，避免坏图把消息列表顶崩。
class CiciLocalImage extends StatefulWidget {
  const CiciLocalImage({
    super.key,
    required this.dataUrl,
    required this.width,
    required this.height,
  });

  final String dataUrl;
  final double width;
  final double height;

  @override
  State<CiciLocalImage> createState() => _CiciLocalImageState();
}

class _CiciLocalImageState extends State<CiciLocalImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant CiciLocalImage oldWidget) {
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

/// 等待中的助手气泡：转圈 + 一行提示。文案与线宽由调用方传入。
class CiciPendingIndicator extends StatelessWidget {
  const CiciPendingIndicator({
    super.key,
    required this.label,
    this.strokeWidth = 2,
    this.labelStyle,
  });

  final String label;
  final double strokeWidth;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: strokeWidth,
            color: c.accent,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: labelStyle ??
              context.body(size: CitroType.meta, color: c.inkSoft),
        ),
      ],
    );
  }
}

/// 消息列表骨架：气泡外观由调用方用 [bubbleBuilder] 注入，
/// 欢迎页 / 空态也留在调用方。
class CiciMessageListView extends StatelessWidget {
  const CiciMessageListView({
    super.key,
    required this.messages,
    required this.controller,
    required this.padding,
    required this.bubbleBuilder,
  });

  final List<CiciChatMessage> messages;
  final ScrollController controller;
  final EdgeInsets padding;
  final Widget Function(BuildContext, CiciChatMessage) bubbleBuilder;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: messages.length,
      itemBuilder: (context, i) => bubbleBuilder(context, messages[i]),
    );
  }
}

/// 待发图片预览条：缩略图 + 一行说明 + 移除按钮（记账 / 待办同款）。
class CiciImagePreview extends StatelessWidget {
  const CiciImagePreview({
    super.key,
    required this.dataUrl,
    required this.label,
    required this.size,
    required this.onClear,
    this.labelStyle,
    this.radius,
  });

  final String dataUrl;
  final String label;
  final double size;
  final VoidCallback onClear;
  final TextStyle? labelStyle;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(radius ?? CitroColors.radii.small),
          child: CiciLocalImage(
            dataUrl: dataUrl,
            width: size,
            height: size,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: labelStyle ??
                context.body(size: CitroType.caption, color: c.inkSoft),
          ),
        ),
        Pressable(
          onTap: onClear,
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
    );
  }
}

/// 桌面端输入栏（记账 / 待办同款）：图片 + 语音 + 输入框 + 发送。
///
/// 手机端走既有的 `CiciComposer`；本组件只负责桌面行。提示文案、文字样式、
/// 语音与选图行为都由调用方注入。
class CiciDesktopComposer extends StatelessWidget {
  const CiciDesktopComposer({
    super.key,
    required this.controller,
    required this.hint,
    required this.sending,
    required this.picking,
    required this.listening,
    required this.imageLabel,
    required this.pendingImage,
    required this.onSend,
    required this.onPickImage,
    required this.onToggleVoice,
    required this.onClearImage,
    this.textStyle,
    this.hintStyle,
  });

  final TextEditingController controller;
  final String hint;
  final bool sending;
  final bool picking;
  final bool listening;
  final String imageLabel;
  final String? pendingImage;
  final VoidCallback onSend;
  final VoidCallback? onPickImage;
  final VoidCallback onToggleVoice;
  final VoidCallback onClearImage;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    Widget circle(
      String icon, {
      bool active = false,
      VoidCallback? onTap,
      Widget? child,
    }) =>
        Pressable(
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
              child: child ??
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
          if (pendingImage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CiciImagePreview(
                dataUrl: pendingImage!,
                label: imageLabel,
                size: 52,
                onClear: onClearImage,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              circle(
                AppIcons.image,
                onTap: picking || sending ? null : onPickImage,
                child: picking
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
                active: listening,
                onTap: sending || picking ? null : onToggleVoice,
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
                    borderRadius: BorderRadius.circular(CitroColors.radii.small),
                    border: Border.all(color: c.line),
                  ),
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    style: textStyle,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: hint,
                      hintStyle: hintStyle,
                      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Pressable(
                onTap: onSend,
                scale: .94,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: sending ? c.line2 : c.accent,
                    borderRadius: BorderRadius.circular(CitroColors.radii.small),
                  ),
                  child: Center(
                    child: AppIcon(
                      strokeSvg(AppIcons.send, width: 1.8),
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
