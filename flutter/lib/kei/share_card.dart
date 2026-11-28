import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'models.dart';

const String keiTestUrl = 'https://chimu-claw.xyz/#/kei';

/// 分享/复制十二系测评的纯文本摘要。
String keiShareText({
  required KeiResult result,
  required KeiPrototype? proto,
}) {
  final tagline = proto?.tagline ?? '';
  final aux = result.ranked.length > 1
      ? ' · 次核 ${result.ranked[1].name} ${result.ranked[1].pct.toStringAsFixed(1)}%'
      : '';
  return '我的十二系亲密关系原型是「${result.typeName}」（${result.attachment}）\n'
      '${tagline.isEmpty ? '' : '$tagline\n\n'}'
      '主型稳定率 ${result.stabilityPct}% · 轮廓集中度 ${result.sharpness}/100$aux\n\n'
      '来 Citro 测测你的关系原型 → $keiTestUrl';
}

/// 用于截图分享的十二系亲密关系长图卡片。
///
/// 采用固定的浅色纸面配色，保证深色模式下导出图片依旧清晰易读。
class KeiShareCard extends StatelessWidget {
  final KeiResult result;
  final KeiPrototype? proto;
  final Color accent;

  const KeiShareCard({
    super.key,
    required this.result,
    required this.proto,
    required this.accent,
  });

  static const _paper = Color(0xFFFAF6EB);
  static const _paperDeep = Color(0xFFF0E5CF);
  static const _ink = Color(0xFF24211B);
  static const _inkSoft = Color(0xFF6A6254);
  static const _line = Color(0xFFD9CBAB);

  @override
  Widget build(BuildContext context) {
    final aux = result.ranked.length > 1 ? result.ranked[1] : null;
    final tags = <String>[
      result.profileMode,
      '稳定率 ${result.stabilityPct}%',
      '集中度 ${result.sharpness}/100',
      if (aux != null) '次核 ${aux.name}',
    ];

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_paper, _paperDeep],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'CITRO · TWELVE KEI',
                  style: context
                      .body(size: 9, weight: CitroType.strong, color: accent)
                      .copyWith(letterSpacing: 1.2),
                ),
                const Spacer(),
                Text(
                  '40 题 · 十二系',
                  style: context.body(size: 9, color: _inkSoft),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.typeName,
                        style: context.display(
                          size: 36,
                          weight: CitroType.strong,
                          color: accent,
                          height: 1.05,
                        ),
                      ),
                      if (proto != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          proto!.en.toUpperCase(),
                          style: context
                              .body(
                                size: 10,
                                weight: CitroType.medium,
                                color: _inkSoft,
                              )
                              .copyWith(letterSpacing: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    result.attachment,
                    style: context.body(
                      size: 9.5,
                      weight: CitroType.medium,
                      color: _paper,
                    ),
                  ),
                ),
              ],
            ),
            if (proto != null) ...[
              const SizedBox(height: 10),
              Text(
                proto!.tagline,
                style: context.body(size: 11.5, color: _ink, height: 1.55),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .48),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _line),
                    ),
                    child: Text(
                      tag,
                      style: context.body(
                        size: 9.5,
                        weight: CitroType.medium,
                        color: accent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .48),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '五维关系坐标',
                    style: context.heading(size: 12, color: _ink),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < result.dimensions.length; i++) ...[
                    _shareDimRow(context, result.dimensions[i]),
                    if (i < result.dimensions.length - 1)
                      const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _line),
                  ),
                  child: QrImageView(
                    data: keiTestUrl,
                    version: QrVersions.auto,
                    gapless: true,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: _ink,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: _ink,
                    ),
                    errorStateBuilder: (_, _) => const Center(
                      child: Text(
                        '二维码生成失败',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 8, color: _inkSoft),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '扫码测你的十二系',
                        style: context.heading(size: 13, color: _ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'chimu-claw.xyz/kei',
                        style: context.body(
                          size: 10,
                          color: accent,
                          weight: CitroType.medium,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '结果映照当下的关系姿态，\n不是给亲密贴死的标签。',
                        style: context.body(
                          size: 9.5,
                          color: _inkSoft,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareDimRow(BuildContext context, KeiDimensionScore d) {
    final pct = ((d.mean + 1) / 2 * 100).round().clamp(0, 100);
    final side = d.mean >= 0 ? d.high : d.low;
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            d.name,
            style: context.body(
              size: 9.5,
              weight: CitroType.medium,
              color: _ink,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(color: _line.withValues(alpha: .55)),
                  FractionallySizedBox(
                    widthFactor: (pct / 100).clamp(0.05, 1.0),
                    child: Container(color: accent),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          child: Text(
            side,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.body(
              size: 9,
              weight: CitroType.strong,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }
}
