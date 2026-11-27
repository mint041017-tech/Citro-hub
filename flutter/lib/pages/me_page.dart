import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../data/cards.dart';
import '../overlays/auth_modal.dart';
import '../overlays/blocked_users.dart';
import '../overlays/delete_account.dart';
import '../overlays/profile_modal.dart';
import '../overlays/scan_modal.dart';
import '../overlays/update_dialog.dart';
import '../services/api.dart';
import '../services/models.dart';
import '../services/notifications.dart';
import '../services/orientation.dart';
import '../services/platform.dart' as platform;
import '../services/updater.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/card_morph.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import '../widgets/shared_element.dart';
import '../widgets/tablet_shell.dart';
import 'legal_page.dart';

/// 「我的」以左侧抽屉展示：四端统一。
///
/// 入口是首页左上角的头像，所以从左边滑出；宽度在手机上占屏宽 88%，
/// 平板 / 桌面最宽 420。点遮罩、按 Esc、往左拖都能收起，拖动时面板
/// 跟手走，松手按位置和速度决定收起还是弹回。
void openMePage(BuildContext context) => showMeSidebar(context);

/// 兼容旧调用：浮窗入口也改成抽屉。
Future<void> showMeWindow(BuildContext context) => showMeSidebar(context);

Future<void> showMeSidebar(BuildContext context) {
  final reduce = CitroMotion.reduced(context);
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: context.c.scrim,
      barrierDismissible: true,
      barrierLabel: '关闭我的',
      settings: const RouteSettings(name: '/me'),
      transitionDuration: reduce ? Duration.zero : CitroMotion.sheet,
      reverseTransitionDuration: reduce
          ? Duration.zero
          : CitroMotion.sheetReverse,
      pageBuilder: (ctx, _, _) => const _MeSidebar(),
      transitionsBuilder: (ctx, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: CitroMotion.drawer,
          reverseCurve: CitroMotion.exit,
        );
        if (reduce) return FadeTransition(opacity: curved, child: child);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

class _MeSidebar extends StatefulWidget {
  const _MeSidebar();

  @override
  State<_MeSidebar> createState() => _MeSidebarState();
}

class _MeSidebarState extends State<_MeSidebar>
    with SingleTickerProviderStateMixin {
  /// 跟手拖动的位移（≤ 0，向左为负）。
  late final AnimationController _drag = AnimationController(
    vsync: this,
    lowerBound: -1,
    upperBound: 0,
    value: 0,
  );
  double _width = 1;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    _drag.value = (_drag.value + d.primaryDelta! / _width).clamp(-1.0, 0.0);
  }

  void _onEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    // 拖过三分之一，或者向左甩得够快：收起。
    if (_drag.value < -.33 || v < -700) {
      Navigator.of(context).maybePop();
    } else {
      _drag.animateTo(
        0,
        duration: CitroMotion.guard(context, CitroMotion.sheetReverse),
        curve: CitroMotion.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 600;
    _width = wide
        ? math.min(420.0, media.size.width * .5)
        : media.size.width * .88;
    const radius = Radius.circular(28);
    final panel = SizedBox(
      width: _width,
      height: media.size.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.horizontal(right: radius),
          boxShadow: CitroColors.shadows.lg(context.c),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(right: radius),
          child: MediaQuery(
            // 面板就是「我的」的全部视口：宽度换成面板宽，右侧不再有安全区。
            data: media.copyWith(
              size: Size(_width, media.size.height),
              padding: media.padding.copyWith(right: 0),
              viewPadding: media.viewPadding.copyWith(right: 0),
            ),
            child: const MePage(floating: true),
          ),
        ),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: _onEnd,
        child: AnimatedBuilder(
          animation: _drag,
          builder: (context, child) => Transform.translate(
            offset: Offset(_drag.value * _width, 0),
            child: child,
          ),
          child: RepaintBoundary(child: panel),
        ),
      ),
    );
  }
}

class MePage extends StatelessWidget {
  final bool floating;

  /// 作为 RootShell 的 Tab 页嵌入时不再显示关闭按钮，并为底部导航留出空间。
  final bool embedded;

  const MePage({super.key, this.floating = false, this.embedded = false});

  static void _downloadApp() {
    // 文件名跟着当前版本走，发新版不用再改这里。
    launchUrl(
      Uri.parse(
        'https://obs.chimu-claw.xyz/APK/Citro-v$kCitroVersion-release.apk',
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final user = state.user;
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final web = kIsWeb && !floating && !embedded;
    final side = width >= 700 ? 20.0 : 16.0;
    return Scaffold(
      body: CitroBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              side,
              AppSpacing.pageTop(width),
              side,
              embedded ? 100 : 32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context),
                    const SizedBox(height: 20),
                    _accountGroup(context, state, user),
                    const SizedBox(height: 18),
                    _preferencesGroup(context, state),
                    const SizedBox(height: 18),
                    _resourcesGroup(context, web: web),
                    const SizedBox(height: 18),
                    _aboutGroup(context, web: web),
                    const SizedBox(height: 18),
                    _contactGroup(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showScan = !kIsWeb && (platform.isAndroid || platform.isIOS);
    return Row(
      children: [
        Expanded(
          child: Text(
            '设置',
            style: context.heading(
              size: width >= 700 ? CitroType.hero : CitroType.display,
            ),
          ),
        ),
        if (showScan) ...[
          const SizedBox(width: AppSpacing.x1),
          _CircleIconButton(
            icon: AppIcons.scan,
            strokeWidth: 2,
            onTap: () => showScanLogin(context),
          ),
        ],
        if (!embedded) ...[
          const SizedBox(width: AppSpacing.x1),
          _CircleIconButton(
            icon: AppIcons.close,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
    );
  }

  /// 账号与安全：头像入口 + 打卡/收藏/抽卡数据 + 退出与注销。
  Widget _accountGroup(BuildContext context, AppState state, User? user) {
    // 色场：资料卡单独一块主色色块，是这一页的视觉重心；
    // 退出 / 注销留在下面普通的分组里，危险色不被主色吃掉。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CitroFieldScope(
          tone: FieldTone.primary,
          child: _GroupCard(
            children: [
              _ProfileCell(
                state: state,
                user: user,
                // 「我的」全形态共用同一个 Hero tag：平板侧栏 / Duo 栏 / 浮窗 /
                // 手机路由都从这颗头像飞进飞出。tag 不一致时 Hero 不生效，
                // 就只剩浮窗淡入，看不出「从哪来」。
                heroTag: CitroHero.tagOf('profile', 'me'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _accountActions(context),
      ],
    );
  }

  Widget _accountActions(BuildContext context) {
    return _GroupCard(
      children: [
        _SettingsRow(
          icon: AppIcons.logout,
          label: '退出登录',
          danger: true,
          onTap: () => _confirmLogout(context),
        ),
        const _RowDivider(),
        _SettingsRow(
          icon: AppIcons.trash,
          label: '注销账号（永久删除）',
          danger: true,
          onTap: () => _deleteAccount(context),
        ),
      ],
    );
  }

  /// 偏好设置：主题、通知与动态效果。
  Widget _preferencesGroup(BuildContext context, AppState state) {
    return _GroupCard(
      children: [
        const _ThemeRow(),
        const _RowDivider(),
        _SettingsSwitchRow(
          icon: AppIcons.bell,
          label: '通知提醒',
          hint: platform.isWindows ? '桌面端以应用内提醒呈现' : '社区消息与烹饪计时',
          value: state.notificationsEnabled,
          onChanged: (v) => _setNotifications(context, v),
        ),
        const _RowDivider(),
        _SettingsSwitchRow(
          icon: AppIcons.sparkle,
          label: '减弱动态效果',
          hint: '关闭页面滑动、缩放与呼吸动画',
          value: state.reduceMotion,
          onChanged: (v) => state.setReduceMotion(v),
        ),
      ],
    );
  }

  /// 资源与工具：黑名单 / 下载。卡面收藏与笔记已分别挪进首页卡片区和删除。
  Widget _resourcesGroup(BuildContext context, {required bool web}) {
    return _GroupCard(
      children: [
        _SettingsRow(
          icon: AppIcons.users,
          label: '黑名单',
          onTap: () => showBlockedUsersSheet(context),
        ),
        if (web) ...[
          const _RowDivider(),
          _SettingsRow(
            icon: AppIcons.download,
            label: '下载 App',
            onTap: _downloadApp,
          ),
        ] else if (platform.isAndroid || platform.isWindows) ...[
          const _RowDivider(),
          _SettingsRow(
            icon: AppIcons.refresh,
            label: '检查更新',
            onTap: () => checkForUpdates(context, manual: true),
          ),
        ],
      ],
    );
  }

  /// 关于：版本与法律信息。
  Widget _aboutGroup(BuildContext context, {required bool web}) {
    return _GroupCard(
      children: [
        const _SettingsRow(
          icon: AppIcons.info,
          label: '当前版本',
          trailing: _VersionLabel(),
        ),
        const _RowDivider(),
        _SettingsRow(
          icon: AppIcons.lock,
          label: '隐私政策',
          onTap: () => showLegalPage(context, LegalDoc.privacy),
        ),
        const _RowDivider(),
        _SettingsRow(
          icon: AppIcons.book,
          label: '用户协议',
          onTap: () => showLegalPage(context, LegalDoc.terms),
        ),
        if (web) ...[
          const _RowDivider(),
          _SettingsRow(
            icon: AppIcons.book,
            label: '账号注销说明',
            onTap: () => launchUrl(
              Uri.parse('/account-deletion.html'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ],
    );
  }

  /// 联系我们：点按复制对应账号。
  Widget _contactGroup(BuildContext context) {
    return _GroupCard(
      children: [
        _SettingsRow(
          icon: AppIcons.community,
          label: 'KOOK',
          value: '25343821',
          onTap: () =>
              copyText('25343821', context: context, tip: '已复制 25343821'),
        ),
        const _RowDivider(),
        _SettingsRow(
          icon: AppIcons.comment,
          label: '微信',
          value: 'Tangerine-1017',
          onTap: () => copyText(
            'Tangerine-1017',
            context: context,
            tip: '已复制 Tangerine-1017',
          ),
        ),
        const _RowDivider(),
        _SettingsRow(
          icon: AppIcons.mail,
          label: '邮箱',
          value: 'mint10177@outlook.com',
          onTap: () => copyText(
            'mint10177@outlook.com',
            context: context,
            tip: '已复制 mint10177@outlook.com',
          ),
        ),
      ],
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final deleted = await showDeleteAccountDialog(context);
    if (deleted && context.mounted) {
      AppToast.show(context, '账号已注销，所有个人数据已删除');
    }
  }

  Future<void> _setNotifications(BuildContext context, bool value) async {
    final state = context.app;
    if (!value) {
      await state.setNotificationsEnabled(false);
      await Notifications.cancelAll();
      if (context.mounted) AppToast.show(context, '已关闭通知提醒');
      return;
    }
    if (platform.isWindows) {
      await state.setNotificationsEnabled(true);
      if (context.mounted) AppToast.show(context, '应用内提醒已开启');
      return;
    }
    final systemEnabled = await Notifications.areEnabled();
    final ok = systemEnabled || await Notifications.requestPermission();
    if (!context.mounted) return;
    if (!ok) {
      AppToast.show(context, '通知未开启，请到系统设置中允许');
      return;
    }
    await state.setNotificationsEnabled(true);
    if (context.mounted) AppToast.show(context, '通知提醒已开启');
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('退出登录？', style: context.heading(size: CitroType.titleLg)),
            const SizedBox(height: AppSpacing.x1),
            Text(
              '退出后仍会保留社区内容',
              style: context.body(
                size: CitroType.caption,
                color: context.c.inkSoft,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '取消',
                    outlined: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: AppSpacing.x1),
                Expanded(
                  child: AccentButton(
                    text: '退出',
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await context.app.logout();
      if (context.mounted) AppToast.show(context, '已退出登录');
    }
  }
}

/// 白色大圆角分组卡：组内行高一致，行间用缩进细线分隔。
class _GroupCard extends StatelessWidget {
  final List<Widget> children;

  const _GroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // 在色场里（资料卡）：交给 CitroCard 画成彩色玻璃块。
    if (CitroFieldScope.toneOf(context) != null) {
      return CitroCard(
        padding: EdgeInsets.zero,
        clip: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }
    // iOS 分组列表：沿用全局玻璃表面，深色下保持半透明而不是白色实底。
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner + 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CitroColors.radii.inner + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// 组内细线：从图标右侧起，不到卡片最左（对齐行标题）。
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Padding(
    // 16 内边距 + 36 图标块 + 12 间距：细线对齐行标题。
    // 16 内边距 + 32 图标块 + 12 间距：细线对齐行标题。
    padding: const EdgeInsets.only(left: 60, right: 0),
    child: CitroDivider(color: context.c.line),
  );
}

/// 设置行左侧的图标块：accentLt 圆角底 + accentInk 图标，随背景主题色变。
/// 危险行（退出 / 注销）改用 dangerSoft + danger。
class _IconTile extends StatelessWidget {
  final String icon;
  final bool danger;

  const _IconTile(this.icon, {this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // iOS 设置页的图标块：实心色底 + 白色线性图标，上亮下深一点点。
    final base = danger ? c.danger : c.accent2;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: AppIcon(
        strokeSvg(icon, width: 2.2),
        size: 18,
        color: danger ? const Color(0xFFFFFFFF) : c.onAccent,
      ),
    );
  }
}

/// 整行宽的组内细线，用于无图标的块（资料卡、收藏入口）之后。
class _BlockDivider extends StatelessWidget {
  const _BlockDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: CitroDivider(color: context.c.line),
  );
}

/// 圆形图标按钮：白底 + 1px 描边，标题栏右侧的关闭 / 扫一扫共用。
class _CircleIconButton extends StatelessWidget {
  final String icon;
  final double strokeWidth;
  final VoidCallback onTap;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.strokeWidth = 2.2,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.card(c),
        ),
        child: Center(
          child: AppIcon(
            strokeSvg(icon, width: strokeWidth),
            size: 16,
            color: c.ink2,
          ),
        ),
      ),
    );
  }
}

/// 账号资料块：头像 + 昵称 + 状态徽章 + 打卡/收藏/抽卡数据。
class _ProfileCell extends StatefulWidget {
  final AppState state;
  final User? user;
  final String heroTag;

  const _ProfileCell({
    required this.state,
    required this.user,
    required this.heroTag,
  });

  @override
  State<_ProfileCell> createState() => _ProfileCellState();
}

class _ProfileCellState extends State<_ProfileCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final user = widget.user;
    const avatarSize = 52.0;
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hover ? c.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          ),
          child: InkWell(
            onTap: () {
              if (user == null) {
                showAuthModal(context);
              } else {
                showProfileModal(context);
              }
            },
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CitroHero(
                        tag: widget.heroTag,
                        child: Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(
                              CitroColors.radii.inner,
                            ),
                            border: Border.all(color: c.line),
                            image: user?.av != null
                                ? DecorationImage(
                                    image: ResizeImage(
                                      NetworkImage(Api.imageUrl(user!.av)),
                                      width: 160,
                                    ),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: user?.av != null
                              ? null
                              : Center(
                                  child: Text(
                                    user?.name.isNotEmpty == true
                                        ? user!.name[0]
                                        : '友',
                                    style: context.heading(
                                      size: CitroType.titleLg,
                                      color: c.ink2,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user?.name ?? '未登录',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.heading(
                                      size: CitroType.titleLg,
                                      color: c.ink,
                                    ),
                                  ),
                                ),
                                if (user != null) ...[
                                  const SizedBox(width: AppSpacing.x1),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.mintSoft,
                                      borderRadius: BorderRadius.circular(
                                        CitroColors.radii.chip,
                                      ),
                                      border: Border.all(color: c.mintLine),
                                    ),
                                    child: Text(
                                      widget.state.loggedIn ? '云端同步' : '游客',
                                      style: context.body(
                                        size: CitroType.micro,
                                        weight: CitroType.medium,
                                        color: c.mintInk,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              user == null
                                  ? '点击登录 / 注册，收藏与记录会跟着你'
                                  : '今天也把日子过成喜欢的样子',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.body(
                                size: CitroType.small,
                                color: c.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (user != null)
                        AppIcon(
                          strokeSvg(AppIcons.chevronRight, width: 2),
                          size: 18,
                          color: c.inkSoft,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(
                        CitroColors.radii.inner,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _heroStat(
                            context,
                            '连续打卡',
                            '${widget.state.checkinStreak} 天',
                          ),
                        ),
                        _heroDivider(c),
                        Expanded(
                          child: _heroStat(
                            context,
                            '卡面收藏',
                            CardCatalog.all.isEmpty
                                ? '—'
                                : '${widget.state.cardOwnedCount}/${CardCatalog.all.length}',
                          ),
                        ),
                        _heroDivider(c),
                        Expanded(
                          child: _heroStat(
                            context,
                            '抽卡机会',
                            '${widget.state.cardCredits} 次',
                          ),
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
    );
  }
}

Widget _heroDivider(CitroColors c) => Container(
  width: 1,
  height: 24,
  margin: const EdgeInsets.symmetric(horizontal: 4),
  color: c.line,
);

Widget _heroStat(BuildContext context, String label, String value) {
  final c = context.c;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.hand(
          size: CitroType.titleLg,
          weight: CitroType.strong,
          color: c.ink,
          height: 1.1,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: context.body(size: CitroType.micro, color: c.inkSoft),
      ),
    ],
  );
}

/// 通用设置行：24px 描边图标 + 标题 + 右侧灰字值 + 箭头。
class _SettingsRow extends StatefulWidget {
  final String icon;
  final String label;
  final String? value;
  final bool danger;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.label,
    this.value,
    this.danger = false,
    this.trailing,
    this.onTap,
  });

  @override
  State<_SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<_SettingsRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = widget.danger ? c.danger : c.ink;
    return Semantics(
      button: widget.onTap != null,
      enabled: widget.onTap != null,
      child: MouseRegion(
        cursor: widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hover ? c.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _IconTile(widget.icon, danger: widget.danger),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.body(
                              size: CitroType.bodyLg,
                              weight: CitroType.medium,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.value != null) ...[
                      const SizedBox(width: AppSpacing.x1),
                      Flexible(
                        child: Text(
                          widget.value!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: context.body(
                            size: CitroType.meta,
                            color: c.inkSoft,
                          ),
                        ),
                      ),
                    ],
                    if (widget.trailing != null) ...[
                      const SizedBox(width: AppSpacing.x1),
                      widget.trailing!,
                    ],
                    if (widget.onTap != null && widget.trailing == null)
                      AppIcon(
                        strokeSvg(AppIcons.chevronRight, width: 2),
                        size: 16,
                        color: c.inkSoft,
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
}

/// 开关设置行：图标 + 标题（+ 说明）+ 右侧 Switch。
class _SettingsSwitchRow extends StatefulWidget {
  final String icon;
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SettingsSwitchRow({
    required this.icon,
    required this.label,
    this.hint,
    required this.value,
    this.onChanged,
  });

  @override
  State<_SettingsSwitchRow> createState() => _SettingsSwitchRowState();
}

class _SettingsSwitchRowState extends State<_SettingsSwitchRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      toggled: widget.value,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hover ? c.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _IconTile(widget.icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.body(
                            size: CitroType.bodyLg,
                            weight: CitroType.medium,
                            color: c.ink,
                          ),
                        ),
                        if (widget.hint != null)
                          Text(
                            widget.hint!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.body(
                              size: CitroType.small,
                              color: c.inkSoft,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // iOS 原生开关：强调色轨道。
                  CupertinoSwitch(
                    value: widget.value,
                    onChanged: widget.onChanged,
                    activeTrackColor: c.accent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 主题行：左侧图标 + 标题，右侧一行内嵌的三段式分段控件。
class _ThemeRow extends StatelessWidget {
  const _ThemeRow();

  static const _modes = <ThemeMode>[
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];

  static String _label(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };

  static String _icon(ThemeMode mode) => switch (mode) {
    ThemeMode.system => AppIcons.monitor,
    ThemeMode.light => AppIcons.sun,
    ThemeMode.dark => AppIcons.moon,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final current = context.app.themeMode;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _IconTile(_icon(current)),
            const SizedBox(width: 12),
            Text(
              '主题',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(
                size: CitroType.bodyLg,
                weight: CitroType.medium,
                color: c.ink,
              ),
            ),
            // 右侧一枚图标分段控件：滑块指示当前项，不再是三段各自渐变。
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 132,
                  child: _ThemeSegments(
                    current: current,
                    onChanged: context.app.setThemeMode,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 三段式分段控件：surface2 容器 + 999 圆角；选中段 ink 底 + bg 字。
class _ThemeSegments extends StatelessWidget {
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeSegments({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = CitroMotion.reduced(context);
    final modes = _ThemeRow._modes;
    final currentIndex = modes.indexOf(current).clamp(0, modes.length - 1);
    // iOS 分段控件：灰色轨道 + 白色浮起滑块，圆角矩形而不是胶囊。
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(9),
      ),
      child: LayoutBuilder(
        builder: (context, cons) {
          final segW = cons.maxWidth / modes.length;
          return Stack(
            children: [
              // 一枚滑块指示当前项：surface 浮起块 + accent 光晕，
              // 图标用 accentInk，像系统分段控件，也跟随背景主题色。
              AnimatedAlign(
                duration: reduce ? Duration.zero : CitroMotion.indicator,
                curve: CitroMotion.emphasized,
                alignment: Alignment(
                  -1 + 2 * currentIndex / (modes.length - 1),
                  0,
                ),
                child: Container(
                  width: segW,
                  decoration: BoxDecoration(
                    color: c.dark
                        ? const Color(0xFF636366)
                        : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                      BoxShadow(color: Color(0x0A000000), blurRadius: 1),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final mode in modes)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: mode == current,
                        label: _ThemeRow._label(mode),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(mode),
                          child: SizedBox(
                            height: 30,
                            child: Center(
                              child: AppIcon(
                                strokeSvg(_ThemeRow._icon(mode), width: 2),
                                size: 17,
                                color: mode == current ? c.ink : c.inkSoft,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return FutureBuilder<InstalledVersion>(
      future: UpdateService.installedVersion(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '';
        if (version.isEmpty) return const SizedBox.shrink();
        return Text(
          version == 'dev' ? '开发版' : 'v$version',
          style: context.body(size: CitroType.small, color: c.inkSoft),
        );
      },
    );
  }
}
