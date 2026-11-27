import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/cards.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/card_morph.dart';
import '../widgets/feedback.dart';
import '../widgets/paper.dart';
import 'card_draw.dart';
import '../widgets/modal.dart';

Future<void> showCardCollection(BuildContext context) {
  unawaited(AppState.instance.syncCardsFromCloud());
  return showCitroGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭卡面收藏',
    barrierColor: context.c.scrim,
    transitionDuration: CitroMotion.modal,
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: CitroMotion.easeOut,
        reverseCurve: CitroMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: .97, end: 1.0).animate(curved),
          child: const _CardCollectionDialog(),
        ),
      );
    },
  );
}

class _CardCollectionDialog extends StatefulWidget {
  const _CardCollectionDialog();

  @override
  State<_CardCollectionDialog> createState() => _CardCollectionDialogState();
}

class _CardCollectionDialogState extends State<_CardCollectionDialog> {
  late Future<void> _loading;

  @override
  void initState() {
    super.initState();
    _loading = CardCatalog.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760;
    final width = math.min(980.0, size.width - (wide ? 64 : 0));
    final height = size.height * (wide ? .88 : 1);
    final radius = wide ? CitroColors.radii.card : 0.0;
    return Center(
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: CitroBackground(
              child: SafeArea(
                child: FutureBuilder<void>(
                  future: _loading,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: CitroSkeleton.grid(
                          count: 9,
                          columns: 3,
                          aspect: .68,
                          padding: const EdgeInsets.all(16),
                        ),
                      );
                    }
                    return AnimatedBuilder(
                      animation: state,
                      builder: (context, _) => _body(context, state, wide),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppState state, bool wide) {
    final c = context.c;
    final owned = state.ownedCards;
    final total = CardCatalog.all.length;
    final unlocked = CardCatalog.all
        .where((card) => owned.contains(card.id))
        .length;
    final columns = wide
        ? (MediaQuery.sizeOf(context).width >= 1100 ? 6 : 5)
        : (MediaQuery.sizeOf(context).width < 560 ? 3 : 4);
    final padding = wide ? 26.0 : 16.0;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(padding, 12, padding, 8),
            child: Row(
              children: [
                Pressable(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.line),
                      boxShadow: CitroColors.shadows.card(c),
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(AppIcons.arrowLeft, width: 2.2),
                        size: 16,
                        color: c.ink2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '卡面收藏',
                        style: context.heading(size: wide ? 26 : 21),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '已收集 $unlocked / $total · 抽到才会点亮',
                        style: context.body(
                          size: CitroType.small,
                          color: c.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.cardCredits > 0)
                  Pressable(
                    onTap: () => showCardDrawOverlay(context),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [c.accent, c.accent2]),
                        borderRadius: BorderRadius.circular(
                          CitroColors.radii.chip,
                        ),
                        boxShadow: CitroColors.shadows.sm(c),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            strokeSvg(AppIcons.sparkle, width: 2),
                            size: 14,
                            color: c.onAccent,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '抽卡 ${state.cardCredits}',
                            style: context.body(
                              size: CitroType.caption,
                              weight: CitroType.medium,
                              color: c.onAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (CardCatalog.categories.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                '卡面目录暂时没加载出来，联网后再试',
                style: context.body(size: CitroType.caption, color: c.inkSoft),
              ),
            ),
          ),
        for (final category in CardCatalog.categories) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padding, 18, padding, 10),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    category.name,
                    style: context.display(
                      size: wide ? 18 : 15,
                      weight: CitroType.medium,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${category.cards.where((e) => owned.contains(e.id)).length}/${category.cards.length}',
                    style: context.body(
                      size: CitroType.micro,
                      color: c.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: CitroDivider(color: c.line2.withValues(alpha: c.line2.a * (140) / 255))),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding, 0, padding, 4),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: wide ? 16 : 10,
                crossAxisSpacing: wide ? 14 : 9,
                // 卡面原图是 3:4（750×1000）。格子按同一个比例给，
                // 卡面图正好铺满整格、不裁切，状态文字移到卡面角标上。
                childAspectRatio: .75,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final card = category.cards[index];
                final has = owned.contains(card.id);
                return _CardTile(card: card, unlocked: has);
              }, childCount: category.cards.length),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(padding, 26, padding, 28),
            child: Text(
              '卡面通过每日打卡、转运、完成游戏、发图文动态、公开菜谱和找 CiCi 聊天获得',
              textAlign: TextAlign.center,
              style: context.body(
                size: CitroType.micro,
                color: c.inkSoft,
                height: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card, required this.unlocked});

  final CardFace card;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () =>
          unlocked ? _open(context) : AppToast.show(context, '抽到这张后才会点亮'),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(CitroColors.radii.small),
          border: Border.all(
            color: unlocked ? c.accent.withAlpha(120) : c.line2,
          ),
          boxShadow: unlocked ? CitroColors.shadows.sm(c) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CitroColors.radii.small),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (unlocked)
                CardFaceImage(
                  card: card,
                  cacheWidth: 320,
                  borderRadius: BorderRadius.zero,
                )
              else ...[
                ColorFiltered(
                  colorFilter: const ColorFilter.matrix(<double>[
                    .2126,
                    .7152,
                    .0722,
                    0,
                    0,
                    .2126,
                    .7152,
                    .0722,
                    0,
                    0,
                    .2126,
                    .7152,
                    .0722,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ]),
                  child: Opacity(
                    opacity: .34,
                    child: CardFaceImage(
                      card: card,
                      cacheWidth: 240,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
                Container(color: c.scrim),
                Center(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c.scrim,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.surface.withValues(alpha: c.surface.a * (160) / 255)),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: c.surface,
                      ),
                    ),
                  ),
                ),
              ],
              // 状态文字收进卡面角标，整格都留给卡面。
              Positioned(
                right: 6,
                top: 6,
                child: _CardBadge(text: unlocked ? '已收集' : '未解锁'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    // 从被点的那一格长到屏幕中央：卡片放大统一走 CitroCardMorph，
    // 起点就是这一格，「回」也回到这一格。
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    CitroCardMorph.showPreview(
      context,
      source: rect,
      barrier: context.c.scrim,
      builder: (_) => _CardZoom(card: card),
    );
  }
}

/// 卡面角标：状态文字贴在卡片角落，不占卡面排版。
class _CardBadge extends StatelessWidget {
  const _CardBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: c.scrim,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(color: Colors.white.withAlpha(60)),
      ),
      child: Text(
        text,
        style: context.body(
          size: CitroType.micro,
          weight: CitroType.medium,
          color: Colors.white,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _CardZoom extends StatelessWidget {
  const _CardZoom({required this.card});

  final CardFace card;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              Center(
                // 保持卡面原始宽高比，别被目标矩形拉变形。
                child: AspectRatio(
                  aspectRatio: card.aspect.clamp(.6, .85),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      CitroColors.radii.inner,
                    ),
                    child: InteractiveViewer(
                      minScale: .9,
                      maxScale: 4,
                      child: CardFaceImage(
                        card: card,
                        cacheWidth: 1200,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                right: 14,
                child: Pressable(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.scrim,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.surface.withValues(alpha: c.surface.a * (140) / 255)),
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(AppIcons.close, width: 2),
                        size: 18,
                        color: c.surface,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: MediaQuery.paddingOf(context).bottom + 20,
                child: Text(
                  '${card.categoryName} · ${card.label}',
                  style: context.body(
                    size: CitroType.small,
                    weight: CitroType.medium,
                    color: c.surface.withValues(alpha: c.surface.a * (230) / 255),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 首页的「卡面收藏」入口卡：和首页其他纸卡同一套语言。
///
/// 第一行是入口标题、可抽数与箭头（明示可点）；第二行左侧是收集数量 +
/// 进度条，右侧扇形铺开最近收集的三张卡面。
/// 首页「卡面收藏」入口卡：小正方形，标题 + 已收集进度。
class CardCollectionEntry extends StatelessWidget {
  const CardCollectionEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final owned = context.app.ownedCards;
    final unlocked = CardCatalog.all.where((card) => owned.contains(card.id));
    final total = CardCatalog.all.length;
    final progress = total == 0 ? 0.0 : unlocked.length / total;
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => showCardCollection(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 极窄（分栏右栏的两格宽）：图标缩小、去掉角标箭头，只留标题。
          final tiny = constraints.maxWidth < 150;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _EntryTile(size: tiny ? 26 : 32),
                  SizedBox(width: tiny ? 6 : AppSpacing.x1),
                  Expanded(
                    child: Text(
                      '卡面收藏',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.heading(size: CitroType.title),
                    ),
                  ),
                  if (!tiny) _EntryArrow(size: 26),
                ],
              ),
          const Spacer(),
          if (total == 0)
            Text(
              '正在整理卡面…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(size: CitroType.small, color: c.inkSoft),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${unlocked.length}',
                  style: context.hand(
                    size: 28,
                    weight: CitroType.strong,
                    color: c.ink,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  '/ $total',
                  style: context.body(size: CitroType.meta, color: c.inkSoft),
                ),
              ],
            ),
            // 两行高的卡：间距压到 4，给 web 端字体行高差留出余量，
            // 否则底部会溢出 1~2px。
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: c.surface2,
                valueColor: AlwaysStoppedAnimation(c.accent),
              ),
            ),
            // 底部说明只在放得下时出现：两行高的卡在 Web 字体行高下会溢出 1~3px。
            if (constraints.maxHeight >= 112) ...[
              const SizedBox(height: 4),
              Text(
                '抽到才会点亮',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: CitroType.micro, color: c.inkSoft),
              ),
            ],
          ],
            ],
          );
        },
      ),
    );
  }
}

/// 入口图标砖：粉彩底 + 圆角 + 青瓷图标，和首页其他卡片一致。
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.tintYellow,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Center(
        child: AppIcon(
          strokeSvg(AppIcons.sparkle, width: 2),
          size: size * .5,
          color: c.accentInk,
        ),
      ),
    );
  }
}

/// 小圆底箭头，指向卡片可点开。
class _EntryArrow extends StatelessWidget {
  const _EntryArrow({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.accentLt,
        shape: BoxShape.circle,
        border: Border.all(color: c.line),
      ),
      child: Center(
        child: AppIcon(
          strokeSvg(AppIcons.arrowRight, width: 2),
          size: size * .48,
          color: c.accentInk,
        ),
      ),
    );
  }
}
