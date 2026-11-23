import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../data/cards.dart';
import '../overlays/card_draw.dart';
import '../services/clipboard_image.dart';
import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'checkin_models.dart';

/// 打开纪念图预览。点击后才构建图片，不在长卷页上实时渲染。
Future<void> showCheckinPoster(
  BuildContext context, {
  required CheckinVolume volume,
}) {
  return showCitroSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.c.scrim,
    builder: (_) => _PosterSheet(volume: volume),
  );
}

class _PosterSheet extends StatefulWidget {
  final CheckinVolume volume;

  const _PosterSheet({required this.volume});

  @override
  State<_PosterSheet> createState() => _PosterSheetState();
}

class _PosterSheetState extends State<_PosterSheet> {
  final GlobalKey _boundary = GlobalKey();
  bool _withExcerpt = false;
  bool _busy = false;
  bool _imagesReady = false;

  CheckinVolume get volume => widget.volume;

  String get _excerpt {
    for (final entry in volume.entries.reversed) {
      if (!entry.hasText) continue;
      final text = entry.reflectionText.replaceAll('\n', ' ').trim();
      if (text.length <= 34) return text;
      return '${text.substring(0, 34)}…';
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _precache());
  }

  Future<void> _precache() async {
    if (!mounted) return;
    final futures = <Future<void>>[];
    for (final entry in volume.entries) {
      final card = CardCatalog.byId(entry.cardId);
      if (card == null) continue;
      final ImageProvider provider = card.isAsset
          ? AssetImage(card.asset)
          : NetworkImage(card.url);
      futures.add(
        precacheImage(provider, context).catchError((_) {}),
      );
    }
    try {
      await Future.wait(futures).timeout(const Duration(seconds: 4));
    } catch (_) {}
    if (mounted) setState(() => _imagesReady = true);
  }

  Future<Uint8List?> _capture() async {
    final boundary =
        _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes?.buffer.asUint8List();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bytes = await _capture();
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _busy = false);
      AppToast.show(context, '纪念图保存失败，可以稍后再试');
      return;
    }
    try {
      if (kIsWeb) {
        final copied = await copyImageToClipboard(bytes);
        if (mounted) {
          AppToast.show(
            context,
            copied ? '已复制到剪贴板，可以粘贴到聊天里' : '纪念图已生成，请用分享保存',
          );
        }
      } else if (platform.isWindows || platform.isMacOS || platform.isLinux) {
        final name = 'Citro-${volume.title}-${volume.startDate ?? ''}.png';
        final path = await FilePicker.saveFile(
          fileName: name,
          type: FileType.custom,
          allowedExtensions: const ['png'],
          bytes: bytes,
        );
        if (mounted && path != null) {
          AppToast.show(context, '已保存到 $path');
        }
      } else {
        await Share.shareXFiles(
          [
            XFile.fromData(
              bytes,
              mimeType: 'image/png',
              name: 'Citro-${volume.title}.png',
            ),
          ],
          text: '${volume.title} · 七天里收进的 ${volume.filled} 天',
        );
      }
    } catch (_) {
      if (mounted) AppToast.show(context, '保存没有成功，可以再试一次');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bytes = await _capture();
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _busy = false);
      AppToast.show(context, '纪念图生成失败，可以稍后再试');
      return;
    }
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'image/png',
            name: 'Citro-${volume.title}.png',
          ),
        ],
        text: '${volume.title} · 七天里收进的 ${volume.filled} 天',
      );
    } catch (_) {
      final copied = await copyImageToClipboard(bytes);
      if (mounted) {
        AppToast.show(
          context,
          copied ? '当前设备不支持直接分享，已复制到剪贴板' : '分享没有成功，可以改用保存图片',
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final media = MediaQuery.of(context);
    final maxW = media.size.width >= 520 ? 360.0 : media.size.width - 64;
    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CitroColors.radii.modal),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${volume.title} · 纪念图',
                          style: context.heading(size: CitroType.titleLg),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '七天的签、行动与回签，收在一张 1080 × 1440 的图里。',
                          style: context.body(
                            size: CitroType.caption,
                            color: c.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: SizedBox(
                      width: AppSpacing.touch,
                      height: AppSpacing.touch,
                      child: Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.close, width: 2),
                          size: 20,
                          color: c.ink2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: CitroColors.shadows.lg(c),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: RepaintBoundary(
                            key: _boundary,
                            child: SizedBox(
                              width: 360,
                              height: 480,
                              child: CheckinPoster(
                                volume: volume,
                                showExcerpt: _withExcerpt,
                                excerpt: _excerpt,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!_imagesReady)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '卡面还在加载，生成时会用纸质占位卡补上。',
                    textAlign: TextAlign.center,
                    style: context.body(
                      size: CitroType.small,
                      color: c.inkSoft,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              if (_excerpt.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '带一句回签',
                        style: context.body(
                          size: CitroType.caption,
                          color: c.ink2,
                        ),
                      ),
                    ),
                    Switch(
                      value: _withExcerpt,
                      activeThumbColor: c.accent,
                      onChanged: (v) => setState(() => _withExcerpt = v),
                    ),
                  ],
                )
              else
                Text(
                  '回签里还没有留下文字，纪念图只收签与行动。',
                  style: context.body(
                    size: CitroType.small,
                    color: c.inkSoft,
                  ),
                ),
              const SizedBox(height: 12),
              CitroButton(
                label: '保存纪念图',
                expanded: true,
                height: 50,
                busy: _busy,
                onPressed: _busy ? null : _save,
              ),
              const SizedBox(height: 8),
              CitroButton(
                label: '分享',
                style: CitroButtonStyle.outline,
                expanded: true,
                height: 48,
                onPressed: _busy ? null : _share,
              ),
              const SizedBox(height: 8),
              Text(
                '默认只放签、日期与行动状态，不放昵称、账目、任务标题与位置；'
                '只有打开「带一句回签」才会加入一条摘录。',
                textAlign: TextAlign.center,
                style: context.body(
                  size: CitroType.small,
                  color: c.inkSoft,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1080×1440 的纪念图（逻辑 360×480，导出 pixelRatio 3）。
class CheckinPoster extends StatelessWidget {
  final CheckinVolume volume;
  final bool showExcerpt;
  final String excerpt;

  const CheckinPoster({
    super.key,
    required this.volume,
    this.showExcerpt = false,
    this.excerpt = '',
  });

  static const _paper = Color(0xFFFFF8EC);
  static const _ink = Color(0xFF5E4A42);
  static const _ink2 = Color(0xFF8C786C);
  static const _line = Color(0xFFE3D3BB);
  static const _accent = Color(0xFFB6553B);
  static const _mint = Color(0xFF3E7C6B);

  TextStyle _text(
    double size, {
    Color color = _ink,
    FontWeight weight = FontWeight.w500,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: AppFonts.rounded,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  TextStyle _num(double size, {Color color = _ink2}) => TextStyle(
    fontFamily: AppFonts.mono,
    fontFamilyFallback: AppFonts.bodyFallback,
    fontSize: size,
    fontWeight: FontWeight.w500,
    color: color,
    letterSpacing: .4,
  );

  Widget _entryRow(CheckinDayEntry entry) {
    final card = CardCatalog.byId(entry.cardId);
    final date = checkinParseDate(entry.date);
    final dateText = date == null
        ? entry.date
        : '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
    return Row(
      children: [
        Container(
          width: 30,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFFF0E2CC),
          ),
          clipBehavior: Clip.antiAlias,
          child: card == null
              ? Center(
                  child: Text(
                    '空',
                    style: _text(8, color: const Color(0xFFA99586)),
                  ),
                )
              : CardFaceImage(
                  card: card,
                  cacheWidth: 90,
                  borderRadius: BorderRadius.circular(4),
                ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$dateText · ${entry.kindLabel}',
                style: _num(7.5, color: const Color(0xFFA99586)),
              ),
              const SizedBox(height: 1),
              Text(
                entry.signTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _text(10.5, weight: FontWeight.w700, height: 1.2),
              ),
            ],
          ),
        ),
        if (entry.hasReflection)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x99B6553B)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '已回签',
              style: _text(7.5, color: _accent, weight: FontWeight.w700),
            ),
          )
        else if (entry.actionDone)
          Text(
            '已做到',
            style: _text(8, color: _mint, weight: FontWeight.w700),
          )
        else
          Text(
            '来过了',
            style: _text(8, color: const Color(0xFFA99586)),
          ),
      ],
    );
  }

  Widget _emptyRow(int index) {
    return CustomPaint(
      painter: _DashRowPainter(_line),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Text(
              '第 ${index + 1} 格',
              style: _text(
                8,
                color: const Color(0xFFB7A595),
                letterSpacing: .5,
              ),
            ),
            const Spacer(),
            Text(
              '还空着',
              style: _text(8, color: const Color(0xFFB7A595)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots = volume.slots;
    return Container(
      color: _paper,
      child: Stack(
        children: [
          Positioned(
            right: -58,
            top: -70,
            child: Container(
              width: 180,
              height: 180,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x22B6553B), Color(0x00B6553B)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x55B6553B)),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: const BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Citro',
                      style: _text(
                        13,
                        color: _accent,
                        weight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      volume.title,
                      style: _text(12, color: _ink2, letterSpacing: .8),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '七天里，收进了 ${volume.filled} 天',
                  style: _text(19, weight: FontWeight.w700, height: 1.2),
                ),
                const SizedBox(height: 3),
                Text(
                  volume.rangeLabel,
                  style: _num(10),
                ),
                const SizedBox(height: 9),
                Container(height: 1, color: _line),
                const SizedBox(height: 7),
                Expanded(
                  child: Column(
                    children: List.generate(7, (i) {
                      final entry = slots[i];
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: entry == null
                              ? _emptyRow(i)
                              : _entryRow(entry),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 6),
                Container(height: 1, color: _line),
                const SizedBox(height: 7),
                if (showExcerpt && excerpt.isNotEmpty)
                  Text(
                    '「$excerpt」',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _text(10, color: _ink2, height: 1.5),
                  )
                else
                  Text(
                    '日子不必连续，来过就有痕迹。',
                    style: _text(10, color: _ink2, letterSpacing: .6),
                  ),
                const SizedBox(height: 2),
                Text(
                  'citro · 每日打卡',
                  style: _num(8, color: const Color(0xFFA99586)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashRowPainter extends CustomPainter {
  final Color color;

  _DashRowPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 4.0;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashRowPainter old) => old.color != color;
}
