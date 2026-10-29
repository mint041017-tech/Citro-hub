import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/cards.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'card_draw.dart';

Future<void> showCardCollection(BuildContext context) {
  unawaited(AppState.instance.syncCardsFromCloud());
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭卡面收藏',
    barrierColor: const Color(0xCC1B1712),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
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
    final radius = wide ? 24.0 : 0.0;
    return Center(
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: PaperBackground(
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
                      boxShadow: CitroColors.shadows.paper(c),
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
                      Text('卡面收藏', style: context.heading(size: wide ? 26 : 21)),
                      const SizedBox(height: 2),
                      Text(
                        '已收集 $unlocked / $total · 抽到才会点亮',
                        style: context.body(size: 10.5, color: c.inkSoft),
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
                        gradient: LinearGradient(
                          colors: [c.accent, c.accent2],
                        ),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: CitroColors.shadows.note(c),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            strokeSvg(AppIcons.sparkle, width: 2),
                            size: 14,
                            color: const Color(0xFF2E2C22),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '抽卡 ${state.cardCredits}',
                            style: context.body(
                              size: 11.5,
                              weight: FontWeight.w800,
                              color: const Color(0xFF2E2C22),
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
                style: context.body(size: 12, color: c.inkSoft),
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
                  const SizedBox(width: 7),
                  Text(
                    category.name,
                    style: context.display(
                      size: wide ? 18 : 15,
                      weight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${category.cards.where((e) => owned.contains(e.id)).length}/${category.cards.length}',
                    style: context.body(size: 10, color: c.inkSoft),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: DashedLine(color: c.line2.withAlpha(140))),
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
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final card = category.cards[index];
                  final has = owned.contains(card.id);
                  return _CardTile(card: card, unlocked: has);
                },
                childCount: category.cards.length,
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(padding, 26, padding, 28),
            child: Text(
              '卡面通过每日打卡、转运、完成游戏、发图文动态、公开菜谱和找 CiCi 聊天获得',
              textAlign: TextAlign.center,
              style: context.body(size: 10, color: c.inkSoft, height: 1.6),
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
      onTap: () => unlocked
          ? _open(context)
          : AppToast.show(context, '抽到这张后才会点亮'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: unlocked ? c.accent.withAlpha(120) : c.line2,
                ),
                boxShadow: unlocked ? CitroColors.shadows.note(c) : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
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
                          .2126, .7152, .0722, 0, 0,
                          .2126, .7152, .0722, 0, 0,
                          .2126, .7152, .0722, 0, 0,
                          0, 0, 0, 1, 0,
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
                      Container(color: const Color(0x661B1712)),
                      Center(
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(90),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withAlpha(60)),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.lock_outline_rounded,
                              size: 16,
                              color: Colors.white70,
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
                          decoration: const BoxDecoration(
                            color: Color(0xCCF2C46B),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Color(0xFF2E2C22),
                          ),
                        ),
                      ),
                  ],
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
              size: 9.5,
              weight: unlocked ? FontWeight.w600 : FontWeight.w400,
              color: unlocked ? c.ink2 : c.inkSoft,
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭卡面',
      barrierColor: const Color(0xF21B1712),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: .92, end: 1.0).animate(curved),
            child: _CardZoom(card: card),
          ),
        );
      },
    );
  }
}

class _CardZoom extends StatelessWidget {
  const _CardZoom({required this.card});

  final CardFace card;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width - 28, 620.0);
    final height = math.min(size.height - 110, width / card.aspect.clamp(.6, .85));
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Center(
            child: SizedBox(
              width: width,
              height: height,
              child: InteractiveViewer(
                minScale: .9,
                maxScale: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
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
                  color: Colors.white.withAlpha(28),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withAlpha(50)),
                ),
                child: Center(
                  child: AppIcon(
                    strokeSvg(AppIcons.close, width: 2),
                    size: 17,
                    color: Colors.white.withAlpha(230),
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
                size: 11,
                weight: FontWeight.w600,
                color: Colors.white.withAlpha(190),
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
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
    return Pressable(
      onTap: () => showCardCollection(context),
      child: Container(
        padding: EdgeInsets.fromLTRB(16, compact ? 13 : 16, 12, compact ? 13 : 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: c.dark
                ? const [Color(0xFF3A2E20), Color(0xFF241C15)]
                : const [Color(0xFFFFF2D8), Color(0xFFF4E0BC)],
          ),
          border: Border.all(color: c.accent.withAlpha(90)),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 40 : 46,
              height: compact ? 40 : 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [c.accent, c.accent2]),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.sparkle, width: 2),
                  size: compact ? 19 : 22,
                  color: const Color(0xFF2E2C22),
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '卡面收藏',
                        style: context.display(
                          size: compact ? 16 : 18,
                          weight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      if (state.cardCredits > 0) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '可抽 ${state.cardCredits}',
                            style: context.body(
                              size: 8.5,
                              weight: FontWeight.w800,
                              color: const Color(0xFF2E2C22),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    total == 0
                        ? '正在整理卡面…'
                        : '已收集 ${unlockedCards.length} / $total · 抽到才会点亮',
                    style: context.body(size: 10, color: c.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: compact ? 88 : 104,
              height: compact ? 58 : 68,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < 3; i++)
                    Positioned(
                      left: i * (compact ? 22 : 27),
                      top: i.isOdd ? 3 : 0,
                      child: Transform.rotate(
                        angle: (i - 1) * .1,
                        child: Container(
                          width: compact ? 38 : 45,
                          height: compact ? 51 : 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: c.surface,
                              width: 1.4,
                            ),
                            boxShadow: CitroColors.shadows.paper(c),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
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
                                      color: Colors.white.withAlpha(160),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            AppIcon(
              strokeSvg(AppIcons.chevronRight, width: 2),
              size: 15,
              color: c.inkSoft.withAlpha(160),
            ),
          ],
        ),
      ),
    );
  }
}
