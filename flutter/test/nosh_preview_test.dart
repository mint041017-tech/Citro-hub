import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/paper.dart';

/// flutter_test 不会自动加载 pubspec 里声明的字体，这里显式加载，
/// 否则 golden 里中文会退化成方块。
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(rootBundle.load(p));
    }
    await loader.load();
  }

  await load('RoundedCN', [
    'assets/fonts/rounded-400-app.ttf',
    'assets/fonts/rounded-500-app.ttf',
    'assets/fonts/rounded-700-app.ttf',
  ]);
  await load('XiaolaiMono', ['assets/fonts/mono-app.ttf']);
}

/// 设计系统预览：确认令牌、字体与基础组件渲染正常，并生成 golden 供人工查看。
Widget _preview(Brightness brightness) {
  final colors = brightness == Brightness.dark ? CitroColors.darkColors : CitroColors.light;
  return MaterialApp(
    theme: buildCitroTheme(colors),
    debugShowCheckedModeBanner: false,
    home: Builder(
      builder: (context) {
        final c = context.c;
        return Scaffold(
          backgroundColor: c.bg,
          body: Center(
            child: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('页面标题', style: context.heading(size: CitroType.heading)),
                    const SizedBox(height: 4),
                    Text('副标题 · 圆体 400', style: context.body(size: CitroType.body, color: c.inkSoft)),
                    const SizedBox(height: 20),
                    CitroCard(
                      onTap: () {},
                      child: Row(
                        children: [
                          CitroAvatar(text: '柑', size: 44, color: c.tintYellow),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('卡片标题', style: context.heading(size: CitroType.title)),
                                const SizedBox(height: 2),
                                Text('卡片描述文字', style: context.body(size: CitroType.meta, color: c.inkSoft)),
                              ],
                            ),
                          ),
                          AppIcon(strokeSvg(AppIcons.arrowRight, width: 2), size: 18, color: c.inkSoft),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    CitroCard(
                      color: c.tintYellow,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('数据读出', style: context.body(size: CitroType.meta, color: c.inkSoft)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text('1195', style: context.hand(size: 40, weight: CitroType.strong, color: c.ink)),
                                      const SizedBox(width: 4),
                                      Text('/ 2000 kcal', style: context.body(size: CitroType.meta, color: c.inkSoft)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const CitroProgressBar(value: .6),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: CitroButton(
                            label: '主操作',
                            style: CitroButtonStyle.primary,
                            onPressed: () {},
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CitroButton(
                            label: '次操作',
                            style: CitroButtonStyle.outline,
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        CitroChip('标签', icon: AppIcon(strokeSvg(AppIcons.sparkle, width: 2), size: 13, color: c.accent)),
                        CitroChip('已完成', background: c.mintSoft, color: c.mintInk),
                        CitroChip('提醒', background: c.tintPink, color: c.stamp),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CitroSectionHeader(
                      '分区标题',
                      subtitle: '一行说明文字',
                      action: CitroChip('操作', background: c.surface2),
                    ),
                    const SizedBox(height: 12),
                    CitroTextField(hint: '搜索点什么', prefix: AppIcon(strokeSvg(AppIcons.search, width: 2), size: 18, color: c.inkSoft)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        StickerFrame(
                          size: 88,
                          radius: 22,
                          child: ColoredBox(color: c.tintBlue),
                        ),
                        const SizedBox(width: 16),
                        StickerFrame(
                          size: 88,
                          circle: true,
                          child: ColoredBox(color: c.tintPink),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: CitroCard(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                Text('「每日一言」', style: context.heading(size: CitroType.titleLg, color: c.ink, height: 1.6)),
                                const SizedBox(height: 4),
                                Text('— quote', style: context.body(size: CitroType.meta, color: c.inkSoft)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  testWidgets('nosh light preview', (tester) async {
    await tester.runAsync(_loadFonts);
    await tester.pumpWidget(_preview(Brightness.light));
    await tester.pumpAndSettle();
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/nosh-light.png'));
  });

  testWidgets('nosh dark preview', (tester) async {
    await tester.runAsync(_loadFonts);
    await tester.pumpWidget(_preview(Brightness.dark));
    await tester.pumpAndSettle();
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/nosh-dark.png'));
  });
}
