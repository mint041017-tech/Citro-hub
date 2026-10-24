import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/resources.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'play_page.dart';
import 'sens_page.dart';
import 'web_resources.dart';

class ResPage extends StatefulWidget {
  const ResPage({super.key});
  @override
  State<ResPage> createState() => _ResPageState();
}

class _ResPageState extends State<ResPage> {
  final search = TextEditingController();
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1025) {
      return const WebResourcesPage();
    }
    final c = context.c;
    final q = query.trim().toLowerCase();
    final mods = q.isEmpty
        ? kMods
        : kMods
              .where(
                (m) => '${m.name}${m.desc}${m.tag}'.toLowerCase().contains(q),
              )
              .toList();
    final tools = q.isEmpty
        ? kTools
        : kTools
              .where(
                (t) =>
                    '${t.name}${t.desc}${t.section}'.toLowerCase().contains(q),
              )
              .toList();
    final drivers = q.isEmpty
        ? [...kDriversWeb, ...kDriversClient]
        : [
            ...kDriversWeb,
            ...kDriversClient,
          ].where((d) => d.name.toLowerCase().contains(q)).toList();
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 30),
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
                        Text('资源库', style: context.heading(size: 27)),
                        const Spacer(),
                        Text(
                          '全部资源',
                          style: context.body(size: 10.5, color: c.inkSoft),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    PaperCard(
                      padding: const EdgeInsets.all(8),
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: c.dark
                                ? [
                                    const Color(0xBF382A1D),
                                    const Color(0x8B2C2318),
                                  ]
                                : [
                                    const Color(0xA8FFFFFF),
                                    const Color(0x73FFF7EA),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: c.line.withAlpha(160)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            AppIcon(
                              strokeSvg(AppIcons.search, width: 2),
                              size: 17,
                              color: c.accentInk,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: search,
                                textAlign: TextAlign.center,
                                onChanged: (v) => setState(() => query = v),
                                onSubmitted: (v) async {
                                  if (v.trim().isEmpty) return;
                                  final hasLocal =
                                      mods.isNotEmpty ||
                                      tools.isNotEmpty ||
                                      drivers.isNotEmpty;
                                  if (!hasLocal) {
                                    await launchUrl(
                                      Uri.parse(
                                        'https://www.bing.com/search?q=${Uri.encodeQueryComponent(v)}',
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                                style: context.body(size: 14, color: c.ink),
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintText: '搜索功能 / Mod / 工具，回车必应',
                                  hintStyle: context.body(
                                    size: 13,
                                    color: c.inkSoft.withAlpha(220),
                                  ),
                                ),
                              ),
                            ),
                            if (query.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  search.clear();
                                  setState(() => query = '');
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: AppIcon(
                                    strokeSvg(AppIcons.close, width: 2),
                                    size: 14,
                                    color: c.inkSoft,
                                  ),
                                ),
                              )
                            else
                              const SizedBox(width: 40),
                          ],
                        ),
                      ),
                    ),
                    if (query.isNotEmpty &&
                        mods.isEmpty &&
                        tools.isEmpty &&
                        drivers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Text('没有找到本地资源', style: context.heading(size: 17)),
                            const SizedBox(height: 5),
                            Text(
                              '按回车去必应搜索「${query.trim()}」',
                              style: context.body(size: 11.5, color: c.inkSoft),
                            ),
                          ],
                        ),
                      ),
                    if (mods.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      PaperCard(
                        rotate: -.4,
                        tapeColor: c.tape,
                        tapeAngle: -3,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionTitle('游戏 Mod', size: 26),
                            const SizedBox(height: 10),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: .86,
                                  ),
                              itemCount: mods.length,
                              itemBuilder: (_, i) => _modCard(context, mods[i]),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (tools.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      PaperCard(
                        rotate: .5,
                        tapeColor: c.tape2,
                        tapeAngle: 2.5,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionTitle('小工具', size: 26),
                            const SizedBox(height: 10),
                            DashedLine(color: c.line2.withAlpha(150)),
                            const SizedBox(height: 4),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 0,
                                    childAspectRatio: 1.34,
                                  ),
                              itemCount: tools.length,
                              itemBuilder: (_, i) =>
                                  _toolCard(context, tools[i]),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (drivers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      PaperCard(
                        rotate: -.4,
                        tapeColor: c.tape3,
                        tapeAngle: -2.5,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionTitle('外设驱动', size: 26),
                            const SizedBox(height: 10),
                            Text(
                              '网页驱动',
                              style: context.heading(
                                size: 16,
                                color: c.accentInk,
                                letterSpacing: 1.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            for (final d in kDriversWeb.where(
                              (d) => drivers.contains(d),
                            ))
                              _driverRow(context, d),
                            const SizedBox(height: 10),
                            Text(
                              '客户端驱动',
                              style: context.heading(
                                size: 16,
                                color: c.accentInk,
                                letterSpacing: 1.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            for (final d in kDriversClient.where(
                              (d) => drivers.contains(d),
                            ))
                              _driverRow(context, d),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    PaperCard(
                      padding: const EdgeInsets.all(12),
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
                                  '更多资源请移步 PC 版',
                                  style: context.heading(size: 15),
                                ),
                                Text(
                                  'chimu-claw.xyz',
                                  style: context.body(
                                    size: 12,
                                    color: c.accentInk,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modCard(BuildContext context, ModItem m) {
    final c = context.c;
    return Pressable(
      onTap: () => _confirmOpen(context, '《${m.name}》Mod', m.url),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        padding: const EdgeInsets.fromLTRB(7, 7, 7, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      m.image,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                      errorBuilder: (_, __, ___) => Container(color: c.noteG),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: c.line2),
                        ),
                        child: Text(
                          m.tag,
                          style: context.body(
                            size: 9.5,
                            weight: FontWeight.w600,
                            color: c.accentInk,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(m.name, style: context.heading(size: 17)),
              ],
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: c.hl.withAlpha(120),
                border: Border.all(color: c.accentInk.withAlpha(75)),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: c.accent.withAlpha(18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.download, width: 2),
                    size: 10,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '网盘下载',
                      style: context.body(
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: c.accentInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AppIcon(
                    strokeSvg(AppIcons.arrowUpRight, width: 2),
                    size: 9,
                    color: c.accentInk,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolCard(BuildContext context, ToolItem tool) {
    final c = context.c;
    return GestureDetector(
      onTap: () {
        if (tool.name == '灵敏度') {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SensPage()));
        } else if (tool.name == '玩法抽签') {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PlayPage()));
        } else if (tool.url != null) {
          _confirmOpen(
            context,
            tool.name,
            tool.url!,
            warn: tool.warn,
            versions: tool.versions,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 9),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line2.withAlpha(120))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.hl,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(tool.icon, width: 2),
                  size: 17,
                  color: c.accentInk,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tool.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 15,
                      weight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              tool.desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(size: 12, color: c.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _driverRow(BuildContext context, DriverItem d) {
    final c = context.c;
    return InkWell(
      onTap: () => _confirmOpen(context, d.name, d.url, download: d.client),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line2.withAlpha(100))),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                d.name,
                style: context.body(
                  size: 14,
                  weight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.hl,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                d.client ? '客户端' : '网页',
                style: context.body(
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: c.accentInk,
                ),
              ),
            ),
            const SizedBox(width: 5),
            AppIcon(
              strokeSvg(AppIcons.arrowUpRight, width: 2),
              size: 13,
              color: c.accentInk,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmOpen(
    BuildContext context,
    String title,
    String url, {
    String? warn,
    List<ResourceVersion> versions = const [],
    bool download = false,
  }) async {
    ResourceVersion? chosen;
    final isDownload =
        download ||
        RegExp(
          r'\.(exe|zip|7z|apk|msi)(\?|$)',
          caseSensitive: false,
        ).hasMatch(url);
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              versions.isNotEmpty ? '选择版本' : (isDownload ? '确认下载' : '前往外部页面'),
              style: context.heading(size: 20),
            ),
            const SizedBox(height: 8),
            if (warn != null) ...[
              Text(
                '⚠ $warn',
                textAlign: TextAlign.center,
                style: context.body(size: 11, color: context.c.stamp),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.body(size: 12, color: ctx.c.inkSoft),
            ),
            if (versions.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final v in versions)
                GestureDetector(
                  onTap: () {
                    chosen = v;
                    Navigator.pop(ctx, true);
                  },
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ctx.c.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ctx.c.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.name,
                          style: context.body(
                            size: 12.5,
                            weight: FontWeight.w700,
                            color: ctx.c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          v.desc,
                          style: context.body(size: 10.5, color: ctx.c.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ),
            ] else
              Text(
                url,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: 10, color: ctx.c.inkSoft),
              ),
            const SizedBox(height: 14),
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
                    text: isDownload || versions.isNotEmpty ? '下载' : '前往',
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
    final target = chosen?.url ?? url;
    await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
  }
}
