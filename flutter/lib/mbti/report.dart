import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'copy.dart';
import 'models.dart';
import 'persona.dart';
import 'scoring.dart';

/// 单维度百分比条 + 倾向强度标签。
class DimBar extends StatelessWidget {
  final DimScore score;
  final DimMeta meta;

  const DimBar({super.key, required this.score, required this.meta});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final copy = mbtiDimCopy[score.dim]!;
    final leftWin = score.letter == meta.left;
    final bandText = switch (score.band) {
      DimBand.center => '倾向不明显',
      DimBand.mild => '倾向温和',
      DimBand.clear => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${meta.left} · ${meta.leftName} ${score.pctLeft}%',
              style: context.body(
                size: CitroType.caption,
                weight: leftWin ? CitroType.strong : CitroType.regular,
                color: leftWin ? c.accentInk : c.inkSoft,
              ),
            ),
            const Spacer(),
            Text(
              copy.title,
              style: context.body(size: CitroType.small, color: c.inkSoft),
            ),
            const Spacer(),
            Text(
              '${score.pctRight}% ${meta.rightName} · ${meta.right}',
              style: context.body(
                size: CitroType.caption,
                weight: leftWin ? CitroType.regular : CitroType.strong,
                color: leftWin ? c.inkSoft : c.accentInk,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                Expanded(
                  flex: score.pctLeft,
                  child: Container(color: leftWin ? c.accent : c.accentLt),
                ),
                Expanded(
                  flex: score.pctRight,
                  child: Container(color: leftWin ? c.accentLt : c.accent),
                ),
              ],
            ),
          ),
        ),
        if (bandText != null) ...[
          const SizedBox(height: 4),
          Text(
            bandText,
            style: context.body(size: CitroType.small, color: c.stamp),
          ),
        ],
      ],
    );
  }
}

/// 类型头卡：四字母 + 昵称 + 一句话画像。
class TypeHeaderCard extends StatelessWidget {
  final String displayType;
  final TypeContent content;

  const TypeHeaderCard({
    super.key,
    required this.displayType,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CitroCard(
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            displayType,
            textAlign: TextAlign.center,
            style: context.display(
              size: 44,
              weight: CitroType.strong,
              color: c.accentInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${content.name} · ${content.group}',
            textAlign: TextAlign.center,
            style: context.heading(size: CitroType.titleLg, color: c.ink),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            content.tagline,
            textAlign: TextAlign.center,
            style: context.body(
              size: CitroType.body,
              color: c.ink2,
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in content.keywords)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: c.accentLt,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    k,
                    style: context.body(
                      size: CitroType.caption,
                      weight: CitroType.medium,
                      color: c.accentInk,
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

/// 专属切片：用本次维度分推出来的个性化摘要，放在结果页靠前位置。
class ResultPersonaCard extends StatelessWidget {
  final MbtiResult result;
  final MbtiBank bank;
  final TypeContent content;
  final String? confirmed;

  const ResultPersonaCard({
    super.key,
    required this.result,
    required this.bank,
    required this.content,
    this.confirmed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final persona = buildMbtiPersona(
      result: result,
      bank: bank,
      content: content,
      confirmed: confirmed,
    );
    return CitroCard(
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.fingerprint_rounded, size: 18, color: c.accentInk),
              const SizedBox(width: 6),
              Text(
                '你的专属人格切片',
                style: context.heading(
                  size: CitroType.title,
                  color: c.accentInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            persona.headline,
            style: context.heading(
              size: CitroType.titleLg,
              color: c.ink,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            persona.summary,
            style: context.body(
              size: CitroType.body,
              color: c.ink2,
              height: 1.75,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final trait in persona.traits)
                CitroChip(
                  trait,
                  background: c.accentLt,
                  color: c.accentInk,
                  borderColor: Colors.transparent,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Container(
            padding: const EdgeInsets.all(AppSpacing.x2),
            decoration: BoxDecoration(
              color: c.tintYellow,
              borderRadius: BorderRadius.circular(CitroColors.radii.inner),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  persona.strongestLine,
                  style: context.heading(
                    size: CitroType.label,
                    color: c.accentInk,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  persona.balanceLine,
                  style: context.body(
                    size: CitroType.caption,
                    color: c.ink2,
                    height: 1.6,
                  ),
                ),
                if (persona.atLine != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    persona.atLine!,
                    style: context.body(
                      size: CitroType.caption,
                      color: c.ink2,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.today_outlined, size: 16, color: c.stamp),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  persona.tip,
                  style: context.body(
                    size: CitroType.caption,
                    color: c.ink2,
                    height: 1.65,
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

const String mbtiTestUrl = 'https://chimu-claw.xyz/#/mbti';

/// 真正进入截图、带测试二维码的结果长图。
/// 使用固定的浅色纸面配色，深色模式下分享出去也保持可读。
class MbtiShareCard extends StatelessWidget {
  final MbtiResult result;
  final TypeContent content;
  final MbtiPersona persona;
  final String displayType;
  final MbtiBank bank;
  final String? confirmed;

  const MbtiShareCard({
    super.key,
    required this.result,
    required this.content,
    required this.persona,
    required this.displayType,
    required this.bank,
    this.confirmed,
  });

  static const _paper = Color(0xFFFAF6EB);
  static const _paperDeep = Color(0xFFF0E5CF);
  static const _ink = Color(0xFF24211B);
  static const _inkSoft = Color(0xFF6A6254);
  static const _accent = Color(0xFF365D4B);
  static const _line = Color(0xFFD9CBAB);

  @override
  Widget build(BuildContext context) {
    final code = confirmed ?? result.typeRaw;
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
                  'CITRO · 16 PERSONALITIES',
                  style: context
                      .body(size: 9, weight: CitroType.strong, color: _accent)
                      .copyWith(letterSpacing: 1.2),
                ),
                const Spacer(),
                Text(
                  '96 题 · 16 型',
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
                        displayType,
                        style: context.display(
                          size: 42,
                          weight: CitroType.strong,
                          color: _accent,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        content.name,
                        style: context.heading(size: 18, color: _ink),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    content.group,
                    style: context.body(
                      size: 9,
                      weight: CitroType.medium,
                      color: _paper,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              content.tagline,
              style: context.body(size: 11.5, color: _ink, height: 1.55),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final trait in persona.traits.take(4))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _line),
                    ),
                    child: Text(
                      trait,
                      style: context.body(
                        size: 9.5,
                        weight: CitroType.medium,
                        color: _accent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    persona.headline,
                    style: context.heading(size: 12, color: _ink),
                  ),
                  const SizedBox(height: 8),
                  for (final dim in ['EI', 'SN', 'TF', 'JP'])
                    if (result.scores[dim] != null) ...[
                      _shareDimRow(
                        context,
                        dim: dim,
                        letter:
                            code.length > ['EI', 'SN', 'TF', 'JP'].indexOf(dim)
                            ? code[['EI', 'SN', 'TF', 'JP'].indexOf(dim)]
                            : result.scores[dim]!.letter,
                      ),
                      if (dim != 'JP') const SizedBox(height: 6),
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
                    data: mbtiTestUrl,
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
                        '扫码测你的 16 型',
                        style: context.heading(size: 13, color: _ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'chimu-claw.xyz/mbti',
                        style: context.body(
                          size: 10,
                          color: _accent,
                          weight: CitroType.medium,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '结果代表你当下的偏好，\n不是给自己贴死的标签。',
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

  Widget _shareDimRow(
    BuildContext context, {
    required String dim,
    required String letter,
  }) {
    final score = result.scores[dim]!;
    final meta = bank.dimensions[dim]!;
    final isLeft = letter == meta.left;
    final pct = isLeft ? score.pctLeft : score.pctRight;
    final name = isLeft ? meta.leftName : meta.rightName;
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            name,
            style: context.body(
              size: 9.5,
              weight: CitroType.medium,
              color: _accent,
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
                  Container(color: _line.withValues(alpha: .5)),
                  FractionallySizedBox(
                    widthFactor: pct / 100,
                    child: Container(color: _accent),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            '$pct%',
            textAlign: TextAlign.right,
            style: context.body(
              size: 9.5,
              weight: CitroType.strong,
              color: _ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// 完整报告：优势 / 盲点 / 四场景 / 功能栈 / 成长建议。
class TypeReportSections extends StatelessWidget {
  final TypeContent content;

  const TypeReportSections({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bulletCard(context, '你的优势', content.strengths, Icons.star_rounded),
        const SizedBox(height: AppSpacing.x2),
        _bulletCard(
          context,
          '容易踩的坑',
          content.pitfalls,
          Icons.warning_amber_rounded,
        ),
        const SizedBox(height: AppSpacing.x2),
        CitroCard(
          padding: const EdgeInsets.all(AppSpacing.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(context, '场景里的你', Icons.place_rounded),
              const SizedBox(height: AppSpacing.x2),
              for (final key in ['work', 'love', 'social', 'stress']) ...[
                Text(
                  mbtiSceneTitles[key]!,
                  style: context.heading(
                    size: CitroType.body,
                    color: context.c.accentInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content.scenes[key]!,
                  style: context.body(
                    size: CitroType.body,
                    color: context.c.ink2,
                    height: 1.7,
                  ),
                ),
                if (key != 'stress') const SizedBox(height: AppSpacing.x2),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        CitroCard(
          padding: const EdgeInsets.all(AppSpacing.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(context, '你的内在工作方式（进阶）', Icons.psychology_rounded),
              const SizedBox(height: AppSpacing.x1),
              Text(
                content.stack.join(' → '),
                style: context.body(
                  size: CitroType.caption,
                  weight: CitroType.medium,
                  color: context.c.inkSoft,
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                content.stackText,
                style: context.body(
                  size: CitroType.body,
                  color: context.c.ink2,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        _bulletCard(context, '给自己的小建议', content.growth, Icons.eco_rounded),
      ],
    );
  }

  Widget _bulletCard(
    BuildContext context,
    String title,
    List<String> items,
    IconData icon,
  ) {
    final c = context.c;
    return CitroCard(
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(context, title, icon),
          const SizedBox(height: AppSpacing.x2),
          for (var i = 0; i < items.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(icon, size: 15, color: c.accentInk),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    items[i],
                    style: context.body(
                      size: CitroType.body,
                      color: c.ink2,
                      height: 1.7,
                    ),
                  ),
                ),
              ],
            ),
            if (i < items.length - 1) const SizedBox(height: AppSpacing.x1),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon) {
    final c = context.c;
    return Row(
      children: [
        Icon(icon, size: 18, color: c.accentInk),
        const SizedBox(width: 6),
        Text(
          title,
          style: context.heading(size: CitroType.title, color: c.ink),
        ),
      ],
    );
  }
}
