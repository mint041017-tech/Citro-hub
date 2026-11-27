import 'dart:async';

import 'package:flutter/material.dart';

import '../assessments/tests_hub_page.dart' deferred as testsPage;
import '../kei/models.dart';
import '../kei/store.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/card_flight.dart';
import '../widgets/card_morph.dart';
import '../widgets/paper.dart';
import '../widgets/lazy_page.dart';
import 'models.dart';
import 'store.dart';

/// 首页 Bento 卡片：测试中心入口。
class MbtiHomeCard extends StatefulWidget {
  const MbtiHomeCard({super.key});

  @override
  State<MbtiHomeCard> createState() => _MbtiHomeCardState();
}

class _MbtiHomeCardState extends State<MbtiHomeCard> {
  /// 类型昵称表按需加载；卡片只取昵称，不阻塞入口。
  TypeLibrary? library;
  List<MbtiRecord> records = MbtiStore.load();
  List<KeiRecord> keiRecords = KeiStore.load();

  @override
  void initState() {
    super.initState();
    MbtiStore.changes.addListener(_reload);
    KeiStore.changes.addListener(_reload);
    unawaited(MbtiStore.syncFromAccount(account: AppState.instance.user?.name));
    unawaited(KeiStore.syncFromAccount(account: AppState.instance.user?.name));
    _loadNames();
  }

  @override
  void dispose() {
    MbtiStore.changes.removeListener(_reload);
    KeiStore.changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      records = MbtiStore.load();
      keiRecords = KeiStore.load();
    });
  }

  Future<void> _loadNames() async {
    try {
      final l = await TypeLibrary.load();
      if (!mounted) return;
      setState(() => library = l);
    } catch (_) {}
  }

  /// 与听隅一致的打开方式：卡片纸面本身长成整页，返回时原路缩回。
  Future<void> _open(BuildContext anchor) async {
    final rect = CitroCardFlight.rectOf(anchor);
    if (rect.isEmpty) {
      await Navigator.of(context).pushNamed('/tests');
    } else {
      await CitroCardMorph.openCardPage<void>(
        context,
        source: rect,
        settings: const RouteSettings(name: '/tests'),
        builder: (_) => CitroLazyPage(
          load: () async {
            await testsPage.loadLibrary();
            return testsPage.TestsHubPage();
          },
        ),
        snapshot: CitroCardFlight.snapshotOf(anchor, rect),
      );
    }
    if (!mounted) return;
    setState(() {
      records = MbtiStore.load();
      keiRecords = KeiStore.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final latestMbti = records.isEmpty ? null : records.first;
    final latestKei = keiRecords.isEmpty ? null : keiRecords.first;
    final useKei =
        latestKei != null &&
        (latestMbti == null || latestKei.takenAtMs > latestMbti.takenAtMs);
    final mbtiContent = latestMbti == null
        ? null
        : library?.byCode(
            latestMbti.typeConfirmed ?? latestMbti.result.typeRaw,
          );
    final latestLabel = useKei
        ? '${latestKei.result.typeName} · 十二系'
        : latestMbti == null
        ? null
        : [
            latestMbti.displayType,
            if (mbtiContent != null) mbtiContent.name,
          ].join(' · ');
    final total = records.length + keiRecords.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 首页给的是小正方形卡片：高度和宽度都紧，标题压到一行。
        final compact =
            constraints.maxHeight < 150 || constraints.maxWidth < 220;
        // 极窄（分栏右栏的两格宽）：图标缩小、去掉角标箭头，只留标题。
        final tiny = constraints.maxWidth < 150;
        final iconSize = tiny ? 24.0 : (compact ? 30.0 : 34.0);
        return CitroCard(
          padding: EdgeInsets.fromLTRB(
            tiny ? 10 : 14,
            compact ? 10 : 12,
            tiny ? 10 : 14,
            compact ? 10 : 12,
          ),
          onTap: () => _open(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: c.tintYellow,
                      borderRadius: BorderRadius.circular(iconSize * .3),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.psychology_alt_rounded,
                        size: tiny ? 14 : (compact ? 17 : 19),
                        color: c.accentInk,
                      ),
                    ),
                  ),
                  SizedBox(width: tiny ? 6 : 8),
                  Expanded(
                    child: Text(
                      '测试',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.heading(
                        size: CitroType.label,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (!tiny)
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: c.accentLt,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.line),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 13,
                          color: c.accentInk,
                        ),
                      ),
                    ),
                ],
              ),
              if (compact) ...[
                const Spacer(),
                Text(
                  latestLabel ?? 'MBTI 与十二系 · 看见自己',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.heading(size: CitroType.titleLg, color: c.ink),
                ),
              ] else ...[
                const Spacer(),
                Text(
                  latestLabel ?? '两种测试，看见更完整的自己',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.display(
                    size: 26,
                    weight: CitroType.strong,
                    color: c.accentInk,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  latestLabel == null
                      ? 'MBTI 与十二系 · 约 8–12 分钟'
                      : '已测 $total 次 · 点开测试中心',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: CitroType.small, color: c.inkSoft),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
