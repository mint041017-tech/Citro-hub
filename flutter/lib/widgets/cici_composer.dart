import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api.dart';
import '../services/voice_recorder.dart';
import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import '../theme/motion.dart';
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

class _CiciComposerState extends State<CiciComposer>
    with SingleTickerProviderStateMixin {
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
  AnimationController? _entryAnim;
  final GlobalKey _barKey = GlobalKey();
  // 录音启动中的 Future：松手时先等它落地，避免 finish() 在 _startedAt 为 null 时空转。
  Future<bool>? _starting;

  /// 麦克风按钮的「长按直接说话」：按下超过 0.42s 就开始录音，
  /// 松手发送； quick tap 仍然只切换语音模式。
  Timer? _micTimer;
  bool _micLongPressed = false;

  static const String _voicePrefKey = 'citro_cici_voice_mode';
  static const double _cancelDistance = 54;

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

  /// 麦克风机按下：先起一个 0.42s 的计时器，超时才算长按说话；
  /// 短按在松手时取消计时器，只切换语音模式。
  void _micDown() {
    if (widget.sending) return;
    _micLongPressed = false;
    _micTimer?.cancel();
    _micTimer = Timer(const Duration(milliseconds: 420), () {
      _micLongPressed = true;
      unawaited(_startHold());
    });
  }

  void _micUp() {
    _micTimer?.cancel();
    _micTimer = null;
    if (_micLongPressed) {
      unawaited(_endHold());
    }
  }

  Future<void> _startHold([double downY = 0]) async {
    if (_holding || widget.sending) return;
    HapticFeedback.lightImpact();
    _downY = downY;
    setState(() {
      _holding = true;
      _recognizing = false;
      _slideCancel = false;
      _preview = '';
      _level = 0;
    });
    _holdAt = DateTime.now();
    _showOverlay();
    final starting = VoiceRecorder.start(
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
    _starting = starting;
    final started = await starting;
    _starting = null;
    if (!mounted) return;
    if (!started) {
      final message = VoiceRecorder.lastError ?? '麦克风没有启动';
      setState(() => _holding = false);
      _hideOverlay();
      AppToast.show(context, message);
      unawaited(_showVoiceHelp(title: '麦克风没有启动', note: message));
      return;
    }
    // 录音上限是 VoiceRecorder.maxLength（25 秒），到点自动收尾。
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
    // 松手可能早于录音启动完成：先等启动落地，再决定取消还是收尾，
    // 否则 finish() 会在 _startedAt == null 时直接返回，麦克风继续采集。
    final starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {}
      _starting = null;
    }
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
      final starting = _starting;
      if (starting != null) {
        // 启动还没完成：等它落地后再取消，确保麦克风一定停住。
        () async {
          try {
            await starting;
          } catch (_) {}
          _starting = null;
          await VoiceRecorder.cancel();
        }();
      } else {
        unawaited(VoiceRecorder.cancel());
      }
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
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(CitroColors.radii.modal),
            ),
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
                  borderRadius: BorderRadius.circular(CitroColors.radii.inner),
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
    final anim = AnimationController(
      vsync: this,
      duration: CitroMotion.panel,
      reverseDuration: CitroMotion.panelReverse,
    )..forward();
    _entryAnim = anim;
    _entry = OverlayEntry(
      builder: (context) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: CitroMotion.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, .05), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: anim, curve: CitroMotion.easeOut),
              ),
          child: _buildOverlay(context),
        ),
      ),
    );
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
    final entry = _entry;
    final anim = _entryAnim;
    _entry = null;
    _entryAnim = null;
    if (entry == null) return;
    if (anim == null || !anim.isAnimating && anim.value == 0) {
      entry.remove();
      return;
    }
    anim.reverse().whenComplete(() {
      if (entry.mounted) entry.remove();
    });
  }

  Widget _buildOverlay(BuildContext context) {
    final c = context.c;
    final accent = _slideCancel ? c.danger : c.ink;
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
              borderRadius: BorderRadius.circular(CitroColors.radii.inner),
              boxShadow: CitroColors.shadows.lg(c),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(
                      strokeSvg(
                        _slideCancel ? AppIcons.close : AppIcons.mic,
                        width: 2,
                      ),
                      size: 13,
                      color: c.bg,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _slideCancel ? '松开取消' : (_recognizing ? '正在识别…' : '松开发送'),
                      style: context.ui(
                        size: CitroType.caption,
                        weight: CitroType.strong,
                        color: c.bg,
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
                          color: c.bg.withAlpha(_level / 2 > i ? 230 : 60),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    const Spacer(),
                    if (!_slideCancel)
                      Text(
                        '上滑取消',
                        style: context.ui(
                          size: CitroType.micro,
                          color: c.bg.withAlpha(120),
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
                        color: _preview.isNotEmpty ? c.bg : c.bg.withAlpha(150),
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
    _micTimer?.cancel();
    // 同 global_search：卸载不播退场动画，直接摘掉浮层再放走控制器。
    final entry = _entry;
    _entry = null;
    _entryAnim?.dispose();
    _entryAnim = null;
    entry?.remove();
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
      borderRadius: BorderRadius.circular(CitroColors.radii.avatar),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? c.ink : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Center(
          child:
              child ??
              AppIcon(
                strokeSvg(icon, width: 2),
                size: 17,
                color: active ? c.bg : c.ink2,
              ),
        ),
      ),
    );

    final input = _voiceMode
        ? Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _startHold(e.position.dy),
            onPointerMove: _onHoldMove,
            onPointerUp: (_) => _endHold(),
            onPointerCancel: (_) => _endHold(abort: true),
            child: Container(
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _slideCancel
                    ? c.dangerSoft
                    : (_holding ? c.surface : Colors.transparent),
                borderRadius: BorderRadius.circular(CitroColors.radii.avatar),
              ),
              child: Text(
                _slideCancel ? '松开取消' : (_holding ? '松开发送' : '按住 说话'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.ui(
                  size: CitroType.body,
                  weight: CitroType.strong,
                  color: _slideCancel ? c.danger : (_holding ? c.ink : c.ink2),
                ),
              ),
            ),
          )
        : TextField(
            controller: widget.controller,
            textInputAction: TextInputAction.send,
            style: context.ui(size: CitroType.bodyLg),
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
        10,
        5,
        10,
        MediaQuery.paddingOf(context).bottom + 8,
      ),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          // 输入框用主题米白（c.surface），和四色底拉开层次。
          color: c.surface,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
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
            // 麦克风：短按切换「按住说话」模式，长按直接开始录音。
            Listener(
              onPointerDown: (_) => _micDown(),
              onPointerUp: (_) => _micUp(),
              onPointerCancel: (_) => _micUp(),
              child: Semantics(
                label: '点按切换语音，长按说话',
                button: true,
                child: round(
                  AppIcons.mic,
                  active: _voiceMode,
                  onTap: () {
                    if (_micLongPressed) {
                      _micLongPressed = false;
                      return;
                    }
                    if (!widget.sending) _toggleVoice();
                  },
                ),
              ),
            ),
            // 只留麦克风：发送交给键盘的回车，语音/文字切换也靠它。
          ],
        ),
      ),
    );
  }
}
