import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/global_search.dart';
import '../widgets/paper.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Pressable(
                          onTap: () => popOrHome(context),
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: c.line),
                              boxShadow: CitroColors.shadows.paper(c),
                            ),
                            child: Row(
                              children: [
                                AppIcon(
                                  strokeSvg(AppIcons.arrowLeft, width: 2.2),
                                  size: 16,
                                  color: c.ink2,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '返回',
                                  style: context.body(
                                    size: 11.5,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('全站搜索', style: context.heading(size: 27)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    PaperCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '按名称或关键词找页面、游戏、Mod、工具和驱动',
                            style: context.body(
                              size: 12,
                              color: c.inkSoft,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const GlobalSearch(hint: '搜索页面 / 游戏 / Mod / 工具 / 驱动'),
                          const SizedBox(height: 10),
                          Text(
                            '支持上下键选择，回车直接打开；没有本地结果时回退到必应。',
                            style: context.body(
                              size: 10.5,
                              color: c.inkSoft.withAlpha(200),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    PaperCard(
                      tapeColor: c.tape2,
                      tapeAngle: 2,
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in const [
                            ('小游戏', '15 款原生小游戏'),
                            ('资源库', 'Mod / 工具 / 外设驱动'),
                            ('食谱日记', '菜谱 / 冰箱 / 购物清单'),
                            ('Citro 社区', '动态 / 评论 / 消息'),
                            ('效率工具', '番茄钟 / 天气 / 星象'),
                          ])
                            _SearchHint(label: item.$1, desc: item.$2),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  final String label;
  final String desc;

  const _SearchHint({required this.label, required this.desc});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.hl.withAlpha(c.dark ? 24 : 90),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line2.withAlpha(150)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.body(
              size: 11.5,
              weight: FontWeight.w700,
              color: c.accentInk,
            ),
          ),
          const SizedBox(width: 5),
          Text(desc, style: context.body(size: 10, color: c.inkSoft)),
        ],
      ),
    );
  }
}
