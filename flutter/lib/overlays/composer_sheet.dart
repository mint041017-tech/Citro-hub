import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/media.dart';
import '../services/models.dart';
import '../services/voice.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import '../widgets/voice_bubble.dart';

Future<Post?> showComposerSheet(BuildContext context) async {
  Post? created;
  await showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _Composer(onCreated: (p) => created = p),
  );
  return created;
}

/// 图片字节只解码一次并持有同一个 provider：
/// 逐字输入会频繁 setState，若每次重建都重新 base64Decode 生成新的
/// MemoryImage，缓存键会变化导致反复解码、预览不停闪烁。
class _PendingImage {
  final String data;
  final Uint8List bytes;

  _PendingImage(this.data)
    : bytes = Uint8List.fromList(
        base64Decode(data.substring(data.indexOf(',') + 1)),
      );

  late final provider = ResizeImage(MemoryImage(bytes), width: 246);
}

class _Composer extends StatefulWidget {
  final ValueChanged<Post> onCreated;
  const _Composer({required this.onCreated});
  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final text = TextEditingController();
  final List<_PendingImage> images = [];
  bool loading = false;
  bool recording = false;
  int recordSeconds = 0;
  Timer? recordTimer;
  VoiceResult? voice;
  String? error;

  @override
  void dispose() {
    text.dispose();
    recordTimer?.cancel();
    if (recording) VoiceRecorder.cancel();
    super.dispose();
  }

  Future<void> _pick({bool camera = false}) async {
    if (images.length >= 3) {
      AppToast.show(context, '最多上传 3 张图片');
      return;
    }
    try {
      final data = await MediaService.pickImageData(
        camera: camera,
        maxWidth: 1400,
        quality: 82,
      );
      if (data == null || !mounted) return;
      setState(() => images.add(_PendingImage(data)));
    } catch (e) {
      if (mounted) AppToast.show(context, '选择图片失败');
    }
  }

  Future<void> _toggleRecord() async {
    if (recording) {
      recordTimer?.cancel();
      final r = await VoiceRecorder.stop();
      if (!mounted) return;
      setState(() {
        recording = false;
        voice = r;
      });
      if (r == null) AppToast.show(context, '录音失败，请重试');
      return;
    }
    final ok = await VoiceRecorder.start(onAutoStop: _stopAtLimit);
    if (!mounted) return;
    if (!ok) {
      AppToast.show(context, '无法录音，请检查麦克风权限');
      return;
    }
    setState(() {
      recording = true;
      recordSeconds = 0;
      voice = null;
    });
    recordTimer?.cancel();
    recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => recordSeconds++);
      if (recordSeconds >= 60) _stopAtLimit();
    });
  }

  void _stopAtLimit() {
    if (!recording) return;
    recordTimer?.cancel();
    () async {
      final r = await VoiceRecorder.stop();
      if (!mounted) return;
      setState(() {
        recording = false;
        voice = r;
      });
    }();
  }

  Future<void> _send() async {
    if (loading) return;
    if (recording) {
      AppToast.show(context, '请先结束录音');
      return;
    }
    if (text.text.trim().isEmpty && images.isEmpty && voice == null) {
      setState(() => error = '内容不能为空');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final post = await Api.createPost(
        text: text.text.trim(),
        imgs: [for (final img in images) img.data],
        voice: voice?.dataUrl,
        voiceDur: voice?.seconds ?? 0,
      );
      if (!mounted) return;
      final cardReward = images.isNotEmpty
          ? await context.app.grantPostCardDraw()
          : false;
      if (!mounted) return;
      AppToast.show(context, cardReward ? '发布成功 · 获得一次卡面抽卡机会' : '发布成功');
      widget.onCreated(post);
      Navigator.of(context).pop();
    } on Exception catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final h =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: h * .82,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CitroColors.radii.card),
          ),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.lg(c),
        ),
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
                padding: const EdgeInsets.fromLTRB(18, 8, 10, 4),
                child: Row(
                  children: [
                    Text('发布动态', style: context.heading(size: 20)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AppIcon(
                          strokeSvg(AppIcons.close, width: 2.2),
                          size: 18,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(
                            CitroColors.radii.small,
                          ),
                          border: Border.all(color: c.line),
                        ),
                        child: TextField(
                          controller: text,
                          autofocus: true,
                          maxLines: 6,
                          onChanged: (_) => setState(() {}),
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                          style: context.body(
                            size: CitroType.body,
                            height: 1.7,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                            counterStyle: context.body(
                              size: CitroType.micro,
                              color: c.inkSoft,
                            ),
                            hintText: '说点什么，和队友们聊聊…',
                            hintStyle: context.body(
                              size: CitroType.body,
                              color: c.inkSoft,
                            ),
                          ),
                        ),
                      ),
                      if (images.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 82,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: images.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      CitroColors.radii.small,
                                    ),
                                    child: Image(
                                      image: images[i].provider,
                                      width: 82,
                                      height: 82,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() => images.removeAt(i)),
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: c.ink.withAlpha(180),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.close,
                                          size: 12,
                                          color: c.bg,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                      if (recording) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: c.dangerSoft,
                            borderRadius: BorderRadius.circular(
                              CitroColors.radii.small,
                            ),
                            border: Border.all(color: c.stamp.withAlpha(80)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: c.stamp,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '录音中 ${recordSeconds}s / 60s',
                                style: context.body(
                                  size: CitroType.caption,
                                  color: c.stamp,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _toggleRecord,
                                child: Container(
                                  height: 30,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: c.surface2,
                                    borderRadius: BorderRadius.circular(
                                      CitroColors.radii.chip,
                                    ),
                                    border: Border.all(
                                      color: c.stamp.withAlpha(90),
                                    ),
                                  ),
                                  child: Text(
                                    '结束',
                                    style: context.body(
                                      size: CitroType.caption,
                                      weight: CitroType.medium,
                                      color: c.stamp,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (voice != null && !recording) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            VoiceBubble(
                              url: voice!.dataUrl,
                              seconds: voice!.seconds,
                              local: true,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '点击试听',
                              style: context.body(
                                size: CitroType.small,
                                color: c.inkSoft,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => setState(() => voice = null),
                              child: Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.surface2,
                                  borderRadius: BorderRadius.circular(
                                    CitroColors.radii.chip,
                                  ),
                                  border: Border.all(
                                    color: c.stamp.withAlpha(90),
                                  ),
                                ),
                                child: Text(
                                  '删除',
                                  style: context.body(
                                    size: CitroType.caption,
                                    weight: CitroType.medium,
                                    color: c.stamp,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${text.text.length} 字',
                          style: context.body(
                            size: CitroType.micro,
                            color: c.inkSoft,
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: context.body(
                            size: CitroType.caption,
                            color: c.stamp,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    _iconBtn(c, AppIcons.image, () => _pick()),
                    const SizedBox(width: 4),
                    _iconBtn(c, AppIcons.camera, () => _pick(camera: true)),
                    const SizedBox(width: 4),
                    _iconBtn(c, AppIcons.mic, _toggleRecord, active: recording),
                    const Spacer(),
                    Pressable(
                      onTap: _send,
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(
                            CitroColors.radii.chip,
                          ),
                          boxShadow: CitroColors.shadows.sm(c),
                        ),
                        child: Center(
                          child: loading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: c.ink,
                                  ),
                                )
                              : Text(
                                  '发布',
                                  style: context.body(
                                    size: CitroType.body,
                                    weight: CitroType.medium,
                                    color: c.onAccent,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(
    CitroColors c,
    String icon,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? c.dangerSoft : c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.small),
          border: Border.all(color: active ? c.accent : c.line),
        ),
        child: Center(
          child: AppIcon(
            strokeSvg(icon, width: 2),
            size: 18,
            color: active ? c.stamp : c.accentInk,
          ),
        ),
      ),
    );
  }
}
