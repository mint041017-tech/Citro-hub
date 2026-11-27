import 'dart:async';

import 'package:flutter/material.dart';

import '../kei/models.dart';
import '../kei/store.dart';
import '../mbti/models.dart';
import '../mbti/store.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';

class TestsHubPage extends StatefulWidget {
  const TestsHubPage({super.key});

  @override
  State<TestsHubPage> createState() => _TestsHubPageState();
}

class _TestsHubPageState extends State<TestsHubPage> {
  List<MbtiRecord> mbti = MbtiStore.load();
  List<KeiRecord> kei = KeiStore.load();
  TypeLibrary? mbtiLibrary;

  @override
  void initState() {
    super.initState();
    MbtiStore.changes.addListener(_reload);
    KeiStore.changes.addListener(_reload);
    unawaited(MbtiStore.syncFromAccount(account: AppState.instance.user?.name));
    unawaited(KeiStore.syncFromAccount(account: AppState.instance.user?.name));
    unawaited(_loadLibrary());
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
      mbti = MbtiStore.load();
      kei = KeiStore.load();
    });
  }

  Future<void> _loadLibrary() async {
    try {
      final library = await TypeLibrary.load();
      if (!mounted) return;
      setState(() => mbtiLibrary = library);
    } catch (_) {}
  }

  Future<void> _open(String route) async {
    await Navigator.of(context).pushNamed(route);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final latestMbti = mbti.isEmpty ? null : mbti.first;
    final latestKei = kei.isEmpty ? null : kei.first;
    final mbtiName = mbtiLibrary
        ?.byCode(latestMbti?.typeConfirmed ?? latestMbti?.result.typeRaw)
        ?.name;
    return Scaffold(
      body: CitroBackground(
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 70, 20, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '测试',
                          textAlign: TextAlign.center,
                          style: context.display(
                            size: 34,
                            weight: CitroType.strong,
                            color: c.ink,
                            letterSpacing: -.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '两种视角，看见更完整的自己。',
                          textAlign: TextAlign.center,
                          style: context.body(
                            size: CitroType.meta,
                            color: c.inkSoft,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x3),
                        _TestEntryCard(
                          icon: Icons.psychology_alt_rounded,
                          tint: c.tintYellow,
                          title: '16 型测试',
                          subtitle: '四个维度与情绪稳定性，生成完整的人格报告。',
                          meta: latestMbti == null
                              ? '尚未测试 · 约 12 分钟'
                              : [
                                  latestMbti.displayType,
                                  if (mbtiName != null) mbtiName,
                                  '已测 ${mbti.length} 次',
                                ].join(' · '),
                          onTap: () => _open('/mbti'),
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        _TestEntryCard(
                          icon: Icons.favorite_border_rounded,
                          tint: c.tintPink,
                          title: '十二系亲密关系',
                          subtitle: '40 题、5 个维度，定位你在关系里的默认姿态。',
                          meta: latestKei == null
                              ? '尚未测试 · 约 8 分钟'
                              : '${latestKei.result.typeName} · 已测 ${kei.length} 次',
                          onTap: () => _open('/kei'),
                        ),
                        const SizedBox(height: AppSpacing.x3),
                        Text(
                          '测试仅用于自我觉察，不构成心理或临床诊断。',
                          textAlign: TextAlign.center,
                          style: context.body(
                            size: CitroType.small,
                            color: c.inkSoft,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  icon: Icon(Icons.close_rounded, color: c.ink),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestEntryCard extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final String meta;
  final VoidCallback onTap;

  const _TestEntryCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CitroCard(
      padding: const EdgeInsets.all(AppSpacing.x3),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(child: Icon(icon, color: c.accentInk, size: 26)),
          ),
          const SizedBox(width: AppSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.heading(size: CitroType.titleLg, color: c.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: CitroType.caption,
                    color: c.inkSoft,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: CitroType.small,
                    weight: CitroType.medium,
                    color: c.accentInk,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_rounded, size: 18, color: c.inkSoft),
        ],
      ),
    );
  }
}
