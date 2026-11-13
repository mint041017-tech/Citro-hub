import 'dart:async';

import 'package:flutter/material.dart';

import '../services/platform.dart' as platform;
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../overlays/ai_chat.dart';
import '../widgets/glass_tab_bar.dart';
import '../widgets/paper.dart';
import '../widgets/tablet_shell.dart';
import 'ledger_add_tab.dart';
import 'ledger_home_tab.dart';
import 'ledger_intake.dart';
import 'ledger_models.dart';
import 'ledger_rail.dart';
import 'ledger_store.dart';
import 'ledger_theme.dart';

/// 记账模块一级页面：首页 / 记一笔。
///
/// 宽屏用左侧纸页侧栏，窄屏用贴底图标栏；切换动画与待办、听隅一致。
class LedgerPage extends StatefulWidget {
  final int initialTab;

  const LedgerPage({super.key, this.initialTab = 0});

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage>
    with SingleTickerProviderStateMixin {
  late int _tab = widget.initialTab.clamp(0, 1);
  late String _monthKey = LedgerDates.monthKey(DateTime.now());
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: CitroMotion.tab,
    value: 1,
  );
  StreamSubscription<void>? _intakeSub;

  @override
  void initState() {
    super.initState();
    LedgerStore.instance.ensureInit();
    // 系统分享进入时如果已经在账单页，直接切到「记一笔」。
    _intakeSub = LedgerIntake.instance.pending.listen((_) {
      if (mounted && _tab != 1) _switchTab(1);
    });
  }

  @override
  void dispose() {
    _intakeSub?.cancel();
    _fade.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
    if (!CitroMotion.reduced(context)) _fade.forward(from: 0);
  }

  /// 返回上一级：Windows 的记账是从计划页 push 出来的，pop 就回到计划页；
  /// 其他端（以及深链把 /ledger 当初始路由、没有上一级时）仍回首页。
  void _back(BuildContext context) {
    final nav = Navigator.of(context);
    if (platform.isWindows && nav.canPop()) {
      nav.pop();
      return;
    }
    nav.pushNamedAndRemoveUntil('/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final desktop = CitroMotion.desktopLike;
    final top =
        (desktop ? AppSpacing.pageTop(media.size.width) : 4.0) +
        media.padding.top;
    final wide =
        media.size.width >= 900 ||
        (CitroLayoutScope.maybeOf(context)?.tabletNav ?? false);
    final pages = <Widget>[
      LedgerHomeTab(
        monthKey: _monthKey,
        onMonthChanged: (value) => setState(() => _monthKey = value),
        onOpenAdd: () => _switchTab(1),
      ),
      LedgerAddTab(onSaved: () => _switchTab(0)),
    ];
    return LedgerScope(
      child: Builder(
        builder: (context) {
          final c = context.c;
          return Scaffold(
            backgroundColor: c.bg,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide) _rail(context),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
                              SizedBox(height: top),
                              // 页头单独铺满窗口宽度，右侧的同步/记一笔才真正贴右；
                              // 下面的内容区仍然保持 1120 的阅读宽度。
                              _header(context, wide: wide),
                              const SizedBox(height: 4),
                              // 记账页不再限制 1120 阅读宽度：右侧操作和月份行
                              // 都贴窗口右边，宽屏下不会出现按钮/预算左右错位。
                              Expanded(child: _pages(pages)),
                            ],
                          ),
                        ),
                        // 键盘弹起时收起底栏（下滑 + 淡出，逻辑同以前）。
                        if (!wide)
                          _bottomBar(
                            context,
                            visible:
                                MediaQuery.viewInsetsOf(context).bottom == 0,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _pages(List<Widget> pages) => Stack(
    children: [
      for (var i = 0; i < pages.length; i++)
        Offstage(
          offstage: _tab != i,
          child: TickerMode(
            enabled: _tab == i,
            child: _EnterVeil(
              animation: _fade,
              active: _tab == i,
              child: pages[i],
            ),
          ),
        ),
    ],
  );

  Widget _rail(BuildContext context) => LedgerRail(
    active: switch (_tab) {
      1 => 'add',
      _ => 'home',
    },
    onBack: () => _back(context),
    onSelect: (key) {
      switch (key) {
        case 'home':
          _switchTab(0);
        case 'add':
          _switchTab(1);
      }
    },
  );

  Widget _header(BuildContext context, {required bool wide}) {
    final c = context.c;
    final title = switch (_tab) {
      1 => '记一笔',
      _ => '账单',
    };
    return Padding(
      padding: wide
          ? const EdgeInsets.fromLTRB(16, 0, 16, 6)
          : const EdgeInsets.fromLTRB(10, 0, 12, 6),
      child: Row(
        children: [
          if (!wide) ...[
            Pressable(
              onTap: () => _back(context),
              scale: .92,
              borderRadius: BorderRadius.circular(CitroColors.radii.avatar),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.line),
                  boxShadow: CitroColors.shadows.card(c),
                ),
                child: Center(
                  child: AppIcon(
                    strokeSvg(AppIcons.arrowLeft, width: 2.2),
                    size: 18,
                    color: c.ink2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            title,
            style: context.lui(
              weight: CitroType.strong,
              size: CitroType.heading,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context, {bool visible = true}) {
    return GlassTabBar(
      tabs: const [
        GlassTab(
          key: ValueKey('ledger-tab-0'),
          label: '首页',
          svg: AppIcons.wallet,
        ),
        GlassTab(
          key: ValueKey('ledger-tab-1'),
          label: '记一笔',
          svg: AppIcons.plus,
        ),
      ],
      index: _tab,
      onChanged: _switchTab,
      showCici: true,
      onCiciTap: () => showAiChat(context),
      visible: visible,
    );
  }
}

class _EnterVeil extends StatelessWidget {
  final Animation<double> animation;
  final bool active;
  final Widget child;

  const _EnterVeil({
    required this.animation,
    required this.active,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (CitroMotion.reduced(context)) return child;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, inner) {
        final t = active ? Curves.easeOutCubic.transform(animation.value) : 1.0;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: FractionalTranslation(
            translation: Offset(.05 * (1 - t), 0),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }
}
