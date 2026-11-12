import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/cards.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/card_morph.dart';
import '../widgets/paper.dart';
import '../widgets/shared_element.dart';
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
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
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
        : (MediaQuery.sizeOf(context).width < 390 ? 3 : 4);
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
                  Expanded(child: CitroDivider(color: c.line2.withAlpha(140))),
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
                childAspectRatio: .63,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CitroHero(
              tag: CitroHero.tagOf('card', card.id),
              enabled: unlocked,
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
                              border: Border.all(
                                color: c.surface.withAlpha(160),
                              ),
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
                      if (unlocked)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 12,
                              color: c.onAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            unlocked ? '${card.categoryName} · ${card.label}' : '未解锁',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.body(
              size: CitroType.micro,
              weight: unlocked ? CitroType.medium : CitroType.regular,
              color: unlocked ? c.ink2 : c.inkSoft,
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context) {
    // 从被点的那一格长到屏幕中央：卡片放大统一走 CitroCardMorph，
    // 起点就是这一格，「回」也回到这一格。
    // （这里原来用 CitroHero，但网格在 DialogRoute 里，Hero 从来不飞，是死代码。）
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
                  border: Border.all(color: c.surface.withAlpha(140)),
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
                color: c.surface.withAlpha(230),
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

/// 「我的」页的卡面收藏入口：预览最近三张 + 收集进度。
class CardCollectionEntry extends StatelessWidget {
  const CardCollectionEntry({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = context.app;
    final owned = state.ownedCards;
    final unlockedCards = [
      for (final card in CardCatalog.all)
        if (owned.contains(card.id)) card,
    ];
    final preview = unlockedCards.take(3).toList();
    final total = CardCatalog.all.length;
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => showCardCollection(context),
      child: Column(
        children: [
          // 第一行：图标 + 标题 + 可抽数 + 箭头
          Row(
            children: [
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [c.accent, c.accent2]),
                ),
                child: Center(
                  child: AppIcon(
                    strokeSvg(AppIcons.sparkle, width: 2),
                    size: compact ? 18 : 21,
                    color: c.onAccent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '卡面收藏',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.display(
                    size: compact ? 16 : 18,
                    weight: CitroType.medium,
                    color: c.ink,
                  ),
                ),
              ),
              if (state.cardCredits > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                  ),
                  child: Text(
                    '可抽 ${state.cardCredits}',
                    maxLines: 1,
                    style: context.body(
                      size: CitroType.micro,
                      weight: CitroType.medium,
                      color: c.onAccent,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              AppIcon(
                strokeSvg(AppIcons.chevronRight, width: 2),
                size: 15,
                color: c.inkSoft.withAlpha(160),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 第二行：进度文案 + 三张预览卡
          Row(
            children: [
              Expanded(
                child: Text(
                  total == 0
                      ? '正在整理卡面…'
                      : '已收集 ${unlockedCards.length} / $total · 抽到才会点亮',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: CitroType.micro, color: c.inkSoft),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: compact ? 84 : 100,
                height: compact ? 54 : 64,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Positioned(
                        left: i * (compact ? 21 : 26),
                        top: i.isOdd ? 3 : 0,
                        child: Transform.rotate(
                          angle: (i - 1) * .1,
                          child: Container(
                            width: compact ? 36 : 43,
                            height: compact ? 50 : 58,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                CitroColors.radii.xs,
                              ),
                              border: Border.all(color: c.surface, width: 1.4),
                              boxShadow: CitroColors.shadows.card(c),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                CitroColors.radii.xs,
                              ),
                              child: i < preview.length
                                  ? CardFaceImage(
                                      card: preview[i],
                                      cacheWidth: 120,
                                      borderRadius: BorderRadius.zero,
                                    )
                                  : Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            c.accent.withAlpha(80),
                                            c.ink.withAlpha(60),
                                          ],
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.lock_outline_rounded,
                                        size: 13,
                                        color: c.surface.withAlpha(200),
                                      ),
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
        ],
      ),
    );
  }
}
