import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/card_flight.dart';
import '../widgets/card_morph.dart';
import '../widgets/paper.dart';
import 'mbti_page.dart';
import 'models.dart';
import 'store.dart';

/// 首页 Bento 卡片：人格测试入口。
///
/// 测过之后直接显示最近一次的结果（类型 + 昵称），没测过则展示引导文案；
/// 点按进入测试页，返回后刷新卡片上的最近结果。
class MbtiHomeCard extends StatefulWidget {
  const MbtiHomeCard({super.key});

  @override
  State<MbtiHomeCard> createState() => _MbtiHomeCardState();
}

class _MbtiHomeCardState extends State<MbtiHomeCard> {
  /// 类型昵称表按需加载；卡片只取昵称，不阻塞入口。
  TypeLibrary? library;
  List<MbtiRecord> records = MbtiStore.load();

  @override
  void initState() {
    super.initState();
    MbtiStore.changes.addListener(_reload);
    unawaited(MbtiStore.syncFromAccount(account: AppState.instance.user?.name));
    _loadNames();
  }

  @override
  void dispose() {
    MbtiStore.changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => records = MbtiStore.load());
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
      await Navigator.of(context).pushNamed('/mbti');
    } else {
      await CitroCardMorph.openCardPage<void>(
        context,
        source: rect,
        settings: const RouteSettings(name: '/mbti'),
        builder: (_) => const MbtiPage(),
        snapshot: CitroCardFlight.snapshotOf(anchor, rect),
      );
    }
    if (!mounted) return;
    setState(() => records = MbtiStore.load());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final latest = records.isEmpty ? null : records.first;
    final content = latest == null
        ? null
        : library?.byCode(latest.typeConfirmed ?? latest.result.typeRaw);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 120;
        return CitroCard(
          padding: EdgeInsets.fromLTRB(
            14,
            compact ? 10 : 12,
            14,
            compact ? 10 : 12,
          ),
          onTap: () => _open(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 30 : 34,
                    height: compact ? 30 : 34,
                    decoration: BoxDecoration(
                      color: c.tintYellow,
                      borderRadius: BorderRadius.circular(
                        (compact ? 30 : 34) * .3,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.psychology_alt_rounded,
                        size: compact ? 17 : 19,
                        color: c.accentInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '人格测试',
                    style: context.heading(size: CitroType.label, color: c.ink),
                  ),
                  const Spacer(),
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
                  latest == null
                      ? '16 型 · 四个维度看懂自己'
                      : '${latest.displayType}${content != null ? ' · ${content.name}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.heading(size: CitroType.titleLg, color: c.ink),
                ),
              ] else ...[
                const Spacer(),
                Text(
                  latest == null
                      ? '你是哪一型？'
                      : '${latest.displayType}${content != null ? ' · ${content.name}' : ''}',
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
                  latest == null
                      ? '约 8 分钟，四个维度看懂你的默认设置'
                      : '已测 ${records.length} 次 · 点开看完整报告或再测一次',
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
