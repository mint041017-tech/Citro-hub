import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'ledger_add_tab.dart';
import 'ledger_cici.dart';
import 'ledger_home_tab.dart';
import 'ledger_intake.dart';
import 'ledger_models.dart';
import 'ledger_rail.dart';
import 'ledger_store.dart';
import 'ledger_theme.dart';
import 'ledger_widgets.dart';

/// 记账模块一级页面：首页 / 记一笔 / cici。
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
  late int _tab = widget.initialTab.clamp(0, 2);
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

  void _back(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final desktop = CitroMotion.desktopLike;
    final top =
        (desktop ? AppSpacing.pageTop(media.size.width) : 4.0) +
        media.padding.top;
    final wide = media.size.width >= 900;
    final pages = <Widget>[
      LedgerHomeTab(
        monthKey: _monthKey,
        onMonthChanged: (value) => setState(() => _monthKey = value),
        onOpenAdd: () => _switchTab(1),
        onOpenCici: () => _switchTab(2),
      ),
      LedgerAddTab(onSaved: () => _switchTab(0)),
      LedgerCiciTab(monthKey: _monthKey),
    ];
    return LedgerScope(
      child: Builder(
        builder: (context) {
          final c = context.c;
          return Scaffold(
            backgroundColor: c.bg,
            body: PaperBackground(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) _rail(context),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.zero,
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
                          if (!wide)
                            AnimatedSize(
                              duration: const Duration(milliseconds: 180),
                              curve: CitroMotion.easeOut,
                              alignment: Alignment.bottomCenter,
                              child:
                                  MediaQuery.viewInsetsOf(context).bottom == 0
                                  ? _bottomBar(context)
                                  : const SizedBox(width: double.infinity),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
      2 => 'cici',
      _ => 'home',
    },
    onBack: () => _back(context),
    onSelect: (key) {
      switch (key) {
        case 'home':
          _switchTab(0);
        case 'add':
          _switchTab(1);
        case 'cici':
          _switchTab(2);
      }
    },
  );

  Widget _header(BuildContext context, {required bool wide}) {
    final c = context.c;
    final title = switch (_tab) {
      1 => '记一笔',
      2 => 'CiCi',
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
              borderRadius: BorderRadius.circular(99),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.line),
                  boxShadow: CitroColors.shadows.paper(c),
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
          const SizedBox(width: 8),
          const Spacer(),
          const SizedBox(width: 8),
          if (wide) ...[
            LedgerSyncBadge(signedIn: AppState.instance.loggedIn),
            const SizedBox(width: 12),
          ],
          if (wide && _tab != 1) ...[
            Pressable(
              key: const ValueKey('ledger-header-add'),
              onTap: () => _switchTab(1),
              scale: .94,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: c.accent.withAlpha(40),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.plus, width: 2.2, color: '#2E2C22'),
                      size: 16,
                      color: const Color(0xFF2E2C22),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '记一笔',
                      style: context.lui(
                        size: CitroType.label,
                        weight: CitroType.strong,
                        color: const Color(0xFF2E2C22),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final c = context.c;
    const items = [
      (0, '首页', AppIcons.wallet),
      (1, '记一笔', AppIcons.plus),
      (2, 'CiCi', AppIcons.sparkle),
    ];
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: _tab == item.$1,
                    label: item.$2,
                    child: GestureDetector(
                      key: ValueKey('ledger-tab-${item.$1}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _switchTab(item.$1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: _tab == item.$1 ? 1.05 : 1,
                            duration: CitroMotion.reduced(context)
                                ? Duration.zero
                                : CitroMotion.indicator,
                            curve: CitroMotion.easeOut,
                            child: AppIcon(
                              strokeSvg(item.$3, width: 1.9),
                              size: 22,
                              color: _tab == item.$1 ? c.accentInk : c.inkSoft,
                            ),
                          ),
                          const SizedBox(height: 5),
                          AnimatedDefaultTextStyle(
                            duration: CitroMotion.reduced(context)
                                ? Duration.zero
                                : CitroMotion.indicator,
                            style: context.lui(
                              size: 12,
                              weight: _tab == item.$1
                                  ? CitroType.strong
                                  : FontWeight.w400,
                              color: _tab == item.$1 ? c.accentInk : c.inkSoft,
                            ),
                            child: Text(
                              item.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
