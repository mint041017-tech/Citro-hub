import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/resources.dart';
import '../games/game_registry.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import '../widgets/tablet_shell.dart';

class GamesPage extends StatelessWidget {
  const GamesPage({super.key});

  static const _keep = ['玩法抽签', '灵敏度', '瞬投', 'KOOK', 'NN语音', 'UU远程', '青柠起始页'];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final layout = CitroLayoutScope.maybeOf(context);
    final width = layout?.contentWidth ?? MediaQuery.sizeOf(context).width;
    final tabletNav = layout?.tabletNav ?? false;
    final maxWidth = tabletNav ? 1120.0 : 840.0;
    final side = math.max(8.0, (width - maxWidth) / 2);
    final duo = layout?.duo == true;
    final gameColumns = duo
        ? (width >= 820 ? 5 : (width >= 520 ? 4 : 3))
        : (width >= 1040 ? 5 : (width >= 760 ? 4 : 3));
    final toolColumns = duo
        ? (width >= 820 ? 4 : 3)
        : (width >= 980 ? 4 : (width >= 700 ? 3 : 2));
    final tools = kTools.where((t) => _keep.contains(t.name)).toList();
    final games = kGameCards;
    return PaperBackground(
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(side, 8, side, tabletNav ? 32 : 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  PaperCard(
                    color: c.surface2,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -18,
                          bottom: -34,
                          child: IgnorePointer(
                            child: Transform.rotate(
                              angle: -9 * math.pi / 180,
                              child: Opacity(
                                opacity: .08,
                                child: Image.asset(
                                  'assets/images/logo.webp',
                                  width: 170,
                                  cacheWidth: 340,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: HighlightedText(
                                '游戏',
                                style: context.heading(
                                  size: 33.4,
                                  color: c.ink,
                                  letterSpacing: 4,
                                ),
                                highlight: c.hl,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Center(
                              child: Text(
                                '账号同步 · 全站排行',
                                style: context.body(
                                  size: 13,
                                  weight: FontWeight.w500,
                                  color: c.inkSoft,
                                  letterSpacing: .78,
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Center(
                              child: Transform.rotate(
                                angle: -1 * math.pi / 180,
                                child: Container(
                                  width: 56,
                                  height: 6,
                                  color: c.hl,
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: gameColumns,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 107.66 / 112,
                                  ),
                              itemCount: games.length,
                              itemBuilder: (_, i) => _GameCard(entry: games[i]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: -9,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Transform.rotate(
                        angle: -2.5 * math.pi / 180,
                        child: ClipPath(
                          clipper: _TapeClip(),
                          child: Container(
                            width: 110,
                            height: 26,
                            color: c.tape2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PaperCard(
                rotate: -.6,
                tapeColor: c.tape,
                tapeAngle: -3,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionTitle('小工具', size: toolColumns >= 3 ? 26 : 23),
                    const SizedBox(height: 10),
                    DashedLine(color: c.line2.withAlpha(150)),
                    const SizedBox(height: 4),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: toolColumns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 0,
                        childAspectRatio: (layout?.duo == true && width < 520)
                            ? 1.22
                            : 1.34,
                      ),
                      itemCount: tools.length + 1,
                      itemBuilder: (_, i) {
                        if (i >= tools.length)
                          return _ToolCard.fill(
                            context,
                            onLongPress: () => _openRes(context),
                          );
                        return _ToolCard(tool: tools[i]);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PaperCard(
                padding: const EdgeInsets.all(12),
                onTap: () =>
                    _openExternal(context, 'https://chimu-claw.xyz/#/res'),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c.hl,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.monitor, width: 2),
                          size: 19,
                          color: c.accentInk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '更多游戏 Mod / 工具 / 外设驱动请移步 PC 版',
                            style: context
                                .heading(size: 15, color: c.ink, height: 1.35)
                                .copyWith(letterSpacing: .1),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'chimu-claw.xyz',
                            style: context.body(
                              size: 12,
                              color: c.accentInk,
                              letterSpacing: .48,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppIcon(
                      strokeSvg(AppIcons.arrowUpRight, width: 2.2),
                      size: 15,
                      color: c.accentInk,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () => _openRes(context),
                  child: Text(
                    '资源库 · Mod / 工具 / 外设驱动',
                    style: context.body(size: 11, color: c.inkSoft),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRes(BuildContext context) {
    Navigator.of(context).pushNamed('/res');
  }

  Future<void> _openExternal(BuildContext context, String url) async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('前往外部页面？', style: context.heading(size: 20)),
            const SizedBox(height: 8),
            Text(
              url,
              textAlign: TextAlign.center,
              style: context.body(size: 11, color: ctx.c.inkSoft),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '取消',
                    outlined: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AccentButton(
                    text: '前往',
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}

class _TapeClip extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .02, size.height * .06)
    ..lineTo(size.width, 0)
    ..lineTo(size.width * .97, size.height * .94)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

class _GameCard extends StatelessWidget {
  final GameCardData entry;
  const _GameCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final layout = CitroLayoutScope.maybeOf(context);
    final tablet = layout?.tabletNav ?? false;
    final compact =
        (layout?.duo ?? false) && CitroLayoutScope.widthOf(context) < 520;
    final large = tablet && !compact;
    return Pressable(
      onTap: () => Navigator.of(context).pushNamed('/${entry.key}'),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(1),
                padding: EdgeInsets.all(compact ? 6 : 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: entry.gradient(c),
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(9),
                    bottomRight: Radius.circular(9),
                  ),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: entry.art(context),
                  ),
                ),
              ),
            ),
            Container(
              height: large ? 48 : (compact ? 36 : 39),
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: large ? 12 : 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.heading(
                  size: large ? 19 : 15.5,
                  color: c.ink,
                  letterSpacing: .27,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final ToolItem? tool;
  final VoidCallback? onLongPress;
  const _ToolCard({this.tool, this.onLongPress});

  factory _ToolCard.fill(BuildContext context, {VoidCallback? onLongPress}) =>
      _ToolCard(onLongPress: onLongPress);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final layout = CitroLayoutScope.maybeOf(context);
    final tablet = layout?.tabletNav ?? false;
    final compact =
        (layout?.duo ?? false) && CitroLayoutScope.widthOf(context) < 520;
    final large = tablet && !compact;
    final isFill = tool == null;
    final name = tool?.name ?? '更多敬请期待';
    final desc = tool?.desc ?? '持续收录实用小工具';
    final iconSvg = isFill
        ? strokeSvg(
            '<circle cx="12" cy="12" r="9" stroke-dasharray="2 2"/><path d="M12 8v4l2 2"/>',
            width: 2,
          )
        : strokeSvg(tool!.icon, width: 2);
    return GestureDetector(
      onLongPress: onLongPress,
      onTap: () {
        if (isFill) return;
        if (tool!.name == '灵敏度') {
          Navigator.of(context).pushNamed('/sens');
        } else if (tool!.name == '玩法抽签') {
          Navigator.of(context).pushNamed('/play');
        } else if (tool!.url != null) {
          _launch(context, tool!.url!);
        }
      },
      child: Container(
        padding: EdgeInsets.fromLTRB(
          large ? 14 : 10,
          large ? 14 : (compact ? 8 : 10),
          large ? 10 : 6,
          large ? 12 : (compact ? 7 : 9),
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line2.withAlpha(120))),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: large ? 42 : (compact ? 30 : 34),
                    height: large ? 42 : (compact ? 30 : 34),
                    decoration: BoxDecoration(
                      color: isFill ? c.surface : c.hl,
                      borderRadius: BorderRadius.circular(large ? 12 : 10),
                      border: isFill ? Border.all(color: c.line2) : null,
                    ),
                    child: Center(
                      child: AppIcon(
                        iconSvg,
                        size: large ? 21 : (compact ? 16 : 17),
                        color: isFill ? c.inkSoft : c.accentInk,
                      ),
                    ),
                  ),
                  SizedBox(height: large ? 8 : (compact ? 4 : 6)),
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isFill ? c.line2 : c.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.body(
                            size: large ? 16 : (compact ? 12.5 : 13),
                            weight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: large ? 4 : 2),
                  Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: large ? 13 : (compact ? 10.5 : 11),
                      color: c.inkSoft,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (url.contains('小工具/') || url.contains('外设驱动/')) {
      final ok = await showCitroDialog<bool>(
        context,
        builder: (ctx) => PaperDialog(
          showClose: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('确认下载？', style: context.heading(size: 20)),
              const SizedBox(height: 8),
              Text(
                url.split('/').last,
                textAlign: TextAlign.center,
                style: context.body(size: 11, color: ctx.c.inkSoft),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: AccentButton(
                      text: '取消',
                      outlined: true,
                      onTap: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AccentButton(
                      text: '下载',
                      onTap: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      if (ok != true) return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
