import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api.dart';
import '../services/voice_recorder.dart';
import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import 'paper.dart';

/// CiCi 手机端输入栏：胶囊输入框 + 图片 + 语音切换。
///
/// 语音模式中间变成「按住 说话」：按住开始识别并在上方浮层实时显示，
/// 松手后弹确认面板，可编辑或直接发送。桌面端不走这个组件。
class CiciComposer extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool sending;
  final bool picking;
  final VoidCallback onSend;
  final Future<void> Function() onPickImage;
  final Future<void> Function(String text) onSubmitVoice;

  const CiciComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onPickImage,
    required this.onSubmitVoice,
    this.hint = '和 CiCi 说一句…',
    this.sending = false,
    this.picking = false,
  });

  @override
  State<CiciComposer> createState() => _CiciComposerState();
}

class _CiciComposerState extends State<CiciComposer> {
bool _voiceMode = false;
  bool _holding = false;
  bool _recognizing = false;
  bool _slideCancel = false;
  String _preview = '';
  double _level = 0;
  DateTime? _holdAt;
  double _downY = 0;
  double _overlayBottom = 82;
  Timer? _capTimer;
  OverlayEntry? _entry;
  final GlobalKey _barKey = GlobalKey();

  static const String _voicePrefKey = 'citro_cici_voice_mode';
  static const double _cancelDistance = 54;
  static const Color _cancelRed = Color(0xFFD4514A);

  @override
  void initState() {
    super.initState();
    unawaited(_restoreMode());
  }

  Future<void> _restoreMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_voicePrefKey);
      if (saved != null && mounted) setState(() => _voiceMode = saved);
    } catch (_) {}
  }

  void _toggleVoice() {
    setState(() => _voiceMode = !_voiceMode);
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_voicePrefKey, _voiceMode);
      } catch (_) {}
    }());
    if (_voiceMode) {
      // 提前把麦克风权限问掉，按住时就不必再等授权弹窗。
      unawaited(VoiceRecorder.hasPermission());
    } else {
      _cancelHold();
    }
  }

  Future<void> _startHold(PointerDownEvent event) async {
    if (_holding || widget.sending) return;
    HapticFeedback.lightImpact();
    _downY = event.position.dy;
    setState(() {
      _holding = true;
      _recognizing = false;
      _slideCancel = false;
      _preview = '';
      _level = 0;
    });
    _holdAt = DateTime.now();
    _showOverlay();
    final started = await VoiceRecorder.start(
      onLevel: (level) {
        if (!mounted) return;
        setState(() => _level = level);
        _entry?.markNeedsBuild();
      },
      onText: (text) {
        if (!mounted) return;
        setState(() => _preview = text);
        _entry?.markNeedsBuild();
      },
    );
    if (!mounted) return;
    if (!started) {
      final message = VoiceRecorder.lastError ?? '麦克风没有启动';
      setState(() => _holding = false);
      _hideOverlay();
      AppToast.show(context, message);
      unawaited(_showVoiceHelp(title: '麦克风没有启动', note: message));
      return;
    }
    // 服务端只接受 30 秒以内的音频，到点自动收尾。
    _capTimer = Timer(VoiceRecorder.maxLength, () {
      if (_holding) _endHold(abort: false);
    });
  }

  void _onHoldMove(PointerMoveEvent event) {
    if (!_holding) return;
    final dy = event.position.dy - _downY;
    final cancel = dy < -_cancelDistance;
    if (cancel != _slideCancel) {
      setState(() => _slideCancel = cancel);
      if (cancel) HapticFeedback.selectionClick();
      _entry?.markNeedsBuild();
    }
  }

  Future<void> _endHold({bool abort = false}) async {
    if (!_holding) return;
    final cancel = abort || _slideCancel;
    HapticFeedback.mediumImpact();
    _capTimer?.cancel();
    _capTimer = null;
    if (cancel) {
      await VoiceRecorder.cancel();
      if (!mounted) return;
      setState(() {
        _holding = false;
        _recognizing = false;
        _slideCancel = false;
        _preview = '';
        _level = 0;
      });
      _hideOverlay();
      AppToast.show(context, '已取消');
      return;
    }
    setState(() => _recognizing = true);
    _entry?.markNeedsBuild();
    String text = '';
    String? error;
    try {
      text = await VoiceRecorder.finish();
    } catch (e) {
      error = e is ApiException ? e.message : '$e';
    }
    final heldAt = _holdAt;
    _holdAt = null;
    if (!mounted) return;
    setState(() {
      _holding = false;
      _recognizing = false;
      _preview = '';
      _level = 0;
    });
    _hideOverlay();
    if (text.isNotEmpty) {
      // 不再二次确认，识别完直接发送。
      setState(() => _preview = '');
      await widget.onSubmitVoice(text.trim());
      return;
    }
    if (error != null) {
      AppToast.show(context, error);
      await _showVoiceHelp(title: '语音转写失败', note: error);
      return;
    }
    final held = heldAt == null
        ? Duration.zero
        : DateTime.now().difference(heldAt);
    AppToast.show(
      context,
      held.inMilliseconds < 600 ? '按住说话，说完再松手' : '没有听清，再说一次试试。',
    );
  }

  void _cancelHold() {
    if (_holding) {
      unawaited(VoiceRecorder.cancel());
      setState(() {
        _holding = false;
        _recognizing = false;
        _slideCancel = false;
        _preview = '';
      });
      _hideOverlay();
    }
  }

/// 录不上或转写失败时给出可复制的诊断信息。
  Future<void> _showVoiceHelp({String? title, String? note}) async {
    final info = VoiceRecorder.diagnoseNow();
    if (!mounted) return;
    await showCitroSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.c;
        return Container(
          padding: EdgeInsets.fromLTRB(
            18,
            14,
            18,
            MediaQuery.paddingOf(ctx).bottom + 16,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: c.line2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title ?? '语音输入不可用',
                style: context.ui(
                  size: CitroType.title,
                  weight: CitroType.strong,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                note ?? '录音或转写没有成功。下面是可以截图反馈的诊断信息。',
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.line),
                ),
                child: Text(
                  info,
                  style: context.ui(
                    size: CitroType.caption,
                    color: c.ink2,
                    height: 1.7,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AccentButton(
                text: '知道了',
                height: 42,
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

void _showOverlay() {
    // 以输入栏实际位置为基准，别用固定偏移：待办页和首页的输入栏高度不同，
    // 写死数值必然有一边挡住输入框。
    _overlayBottom = _measureBarBottom();
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_entry!);
  }

  double _measureBarBottom() {
    final fallback = MediaQuery.paddingOf(context).bottom + 82;
    final box = _barKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return fallback;
    final screen = MediaQuery.sizeOf(context).height;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = screen - top + 8;
    if (bottom.isNaN || bottom <= 0) return fallback;
    return bottom.clamp(0.0, screen * 0.7);
  }

  void _hideOverlay() {
    _entry?.remove();
    _entry = null;
  }

Widget _buildOverlay(BuildContext context) {
    final c = context.c;
    final accent = _slideCancel ? _cancelRed : c.ink;
    return Positioned(
      left: 16,
      right: 16,
      bottom: _overlayBottom,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            decoration: BoxDecoration(
              color: accent.withAlpha(238),
              borderRadius: BorderRadius.circular(16),
              boxShadow: CitroColors.shadows.lg(c),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(
                      strokeSvg(_slideCancel ? AppIcons.close : AppIcons.mic,
                          width: 2),
                      size: 13,
                      color: c.surface,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _slideCancel
                          ? '松开取消'
                          : (_recognizing ? '正在识别…' : '松开发送'),
                      style: context.ui(
                        size: CitroType.caption,
                        weight: CitroType.strong,
                        color: c.surface,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 音量条：一眼看出麦克风到底有没有在采集。
                    for (var i = 0; i < 5; i++)
                      Container(
                        width: 3,
                        height: 6.0 + i * 3,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: c.surface.withAlpha(
                            _level / 2 > i ? 230 : 60,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    const Spacer(),
                    if (!_slideCancel)
                      Text(
                        '上滑取消',
                        style: context.ui(
                          size: 10,
                          color: c.surface.withAlpha(120),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      _preview.isNotEmpty
                          ? _preview
                          : (_recognizing ? '正在转成文字…' : '正在听，说完松手'),
                      style: context.ui(
                        size: CitroType.bodyLg,
                        color: _preview.isNotEmpty
                            ? c.surface
                            : c.surface.withAlpha(150),
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideOverlay();
    VoiceRecorder.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget round(
      String icon, {
      VoidCallback? onTap,
      bool active = false,
      Widget? child,
    }) => Pressable(
      onTap: onTap,
      scale: .92,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? c.accent.withAlpha(40) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Center(
          child:
              child ??
              AppIcon(
                strokeSvg(icon, width: 2),
                size: 19,
                color: active ? c.accentInk : c.ink2,
              ),
        ),
      ),
    );

final input = _voiceMode
        ? Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _startHold,
            onPointerMove: _onHoldMove,
            onPointerUp: (_) => _endHold(),
            onPointerCancel: (_) => _endHold(abort: true),
            child: Container(
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _slideCancel
                    ? _cancelRed.withAlpha(30)
                    : (_holding ? c.accent.withAlpha(36) : Colors.transparent),
                borderRadius: BorderRadius.circular(19),
              ),
              child: Text(
                _slideCancel
                    ? '松开取消'
                    : (_holding ? '松开发送' : '按住 说话'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.ui(
                  size: CitroType.body,
                  weight: CitroType.strong,
                  color: _slideCancel
                      ? _cancelRed
                      : (_holding ? c.accentInk : c.ink2),
                ),
              ),
            ),
          )
        : TextField(
            controller: widget.controller,
            textInputAction: TextInputAction.send,
            style: context.ui(size: CitroType.body),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: widget.hint,
              hintStyle: context.ui(size: CitroType.body, color: c.inkSoft),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
            ),
            onSubmitted: (_) => widget.onSend(),
          );

return Padding(
      key: _barKey,
      padding: EdgeInsets.fromLTRB(
        12,
        6,
        12,
        MediaQuery.paddingOf(context).bottom + 10,
      ),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            round(
              AppIcons.image,
              onTap: widget.picking || widget.sending
                  ? null
                  : widget.onPickImage,
              child: widget.picking
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
            Expanded(child: input),
            round(
              AppIcons.mic,
              active: _voiceMode,
              onTap: widget.sending ? null : _toggleVoice,
            ),
            if (!_voiceMode)
              round(
                AppIcons.send,
                onTap: widget.sending ? null : widget.onSend,
              ),
          ],
        ),
      ),
    );
  }
}
