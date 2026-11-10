import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/cards.dart';
import '../overlays/auth_modal.dart';
import '../overlays/blocked_users.dart';
import '../overlays/card_collection.dart';
import '../overlays/delete_account.dart';
import '../overlays/notes_modal.dart';
import '../overlays/profile_modal.dart';
import '../overlays/scan_modal.dart';
import '../overlays/update_dialog.dart';
import '../services/api.dart';
import '../services/device_settings.dart';
import '../services/models.dart';
import '../services/notifications.dart';
import '../services/orientation.dart';
import '../services/platform.dart' as platform;
import '../services/updater.dart';
import '../state/app_state.dart';
import '../state/negative_screen.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import '../widgets/shared_element.dart';
import 'legal_page.dart';

Future<void> showMeWindow(BuildContext context) {
  // 透明 PageRoute：Hero 只在 PageRoute 之间飞行，Dialog 路由不会。
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: context.c.scrim,
      barrierDismissible: true,
      barrierLabel: '关闭我的',
      transitionDuration: CitroMotion.modal,
      reverseTransitionDuration: CitroMotion.modalReverse,
      pageBuilder: (ctx, _, __) {
        final media = MediaQuery.of(ctx);
        final width = math.min(720.0, media.size.width - 48);
        final height = math.min(760.0, media.size.height - 48);
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(CitroColors.radii.modal),
                boxShadow: CitroColors.shadows.lg(context.c),
              ),
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(CitroColors.radii.modal),
                child: MediaQuery(
                  data: media.copyWith(size: Size(width, height)),
                  child: const MePage(floating: true),
                ),
              ),
            ),
          ),
        );
      },
      transitionsBuilder: (ctx, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: CitroMotion.easeOut,
          reverseCurve: CitroMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// Windows 与 iPad 统一用浮窗展示「我的」；手机端仍保持整页路由。
void openMePage(BuildContext context) {
  final floating =
      !kIsWeb &&
      (platform.isWindows ||
          CitroOrientation.padSize(MediaQuery.sizeOf(context)));
  if (floating) {
    showMeWindow(context);
    return;
  }
  Navigator.of(context).pushNamed('/me');
}

class MePage extends StatelessWidget {
  final bool floating;

  /// 作为 RootShell 的 Tab 页嵌入时不再显示返回按钮，并为底部导航留出空间。
  final bool embedded;

  const MePage({super.key, this.floating = false, this.embedded = false});

  static void _downloadApp() {
    launchUrl(
      Uri.parse('https://obs.chimu-claw.xyz/APK/Citro-v2.1.0-release.apk'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final user = state.user;
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final duo = !platform.isWindows && CitroForm.duoDevice(size);
    final web = kIsWeb && !floating && !embedded;
    final twoColumn = width >= 700;
    final maxWidth = web ? 1040.0 : (duo ? 980.0 : 760.0);
    final side = math.max(10.0, (width - maxWidth) / 2);
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
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _pageHeader(context, web: web, duo: duo),
                    SizedBox(height: web ? 20 : 12),
                    if (twoColumn)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: web ? 320 : 288,
                            child: _profileColumn(context, state, user),
                          ),
                          const SizedBox(width: 22),
                          Expanded(
                            child: _settingsColumn(
                              context,
                              state,
                              user,
                              web: web,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      RepaintBoundary(
                        child: _profileHero(
                          context,
                          state,
                          user,
                          web: false,
                          floating: floating,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const CardCollectionEntry(compact: true),
                      const SizedBox(height: 18),
                      RepaintBoundary(
                        child: _quickGrid(context, state, web: web),
                      ),
                      const SizedBox(height: 18),
                      _settingsColumn(
                        context,
                        state,
                        user,
                        web: web,
                        accountAfterLegal: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageHeader(
    BuildContext context, {
    required bool web,
    required bool duo,
  }) {
    final p = context.c;
    return Row(
      children: [
        if (!duo && !floating && !embedded) ...[
          Pressable(
            onTap: () => popOrHome(context),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                border: Border.all(color: p.line),
                boxShadow: CitroColors.shadows.card(p),
              ),
              child: Row(
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.arrowLeft, width: 2.2),
                    size: 16,
                    color: p.ink2,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '返回',
                    style: context.body(
                      size: CitroType.label,
                      weight: CitroType.medium,
                      color: p.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
        ],
        Text('我的', style: context.heading(size: web ? 28 : 22)),
        if (web) ...[
          const SizedBox(width: AppSpacing.x2),
          Text(
            'ACCOUNT & PREFERENCES',
            style: context.body(
              size: CitroType.micro,
              weight: CitroType.medium,
              color: p.inkSoft,
              letterSpacing: 1.7,
            ),
          ),
        ],
        const Spacer(),
        if (floating)
          Pressable(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.surface,
                shape: BoxShape.circle,
                border: Border.all(color: p.line),
                boxShadow: CitroColors.shadows.card(p),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.close, width: 2.2),
                  size: 16,
                  color: p.ink2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _accountGroup(BuildContext context, User? user) {
    if (user == null) return const SizedBox.shrink();
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(c, '账号'),
        const SizedBox(height: AppSpacing.x1),
        _rows(c, [
          _MeRow(
            icon: AppIcons.logout,
            label: '退出登录',
            danger: true,
            onTap: () => _confirmLogout(context),
          ),
          _MeRow(
            icon: AppIcons.trash,
            label: '注销账号（永久删除）',
            danger: true,
            onTap: () => _deleteAccount(context),
          ),
        ]),
      ],
    );
  }

  Widget _profileColumn(BuildContext context, AppState state, User? user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _profileHero(context, state, user, web: false, floating: floating),
        const SizedBox(height: 12),
        const CardCollectionEntry(compact: true),
        const SizedBox(height: 14),
        _quickGrid(context, state, web: false),
        const SizedBox(height: 14),
        _accountGroup(context, user),
      ],
    );
  }

  Widget _settingsColumn(
    BuildContext context,
    AppState state,
    User? user, {
    required bool web,
    bool accountAfterLegal = false,
  }) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(c, '通知与外观'),
        const SizedBox(height: AppSpacing.x1),
        _rows(c, [
          _MeToggleRow(
            icon: AppIcons.bell,
            label: '通知提醒',
            hint: platform.isWindows ? '桌面端以应用内提醒呈现' : '社区消息与烹饪计时',
            value: state.notificationsEnabled,
            onChanged: (v) => _setNotifications(context, v),
          ),
          _MeToggleRow(
            icon: AppIcons.sparkle,
            label: '减弱动态效果',
            hint: '关闭页面滑动、缩放与呼吸动画',
            value: state.reduceMotion,
            onChanged: (v) => state.setReduceMotion(v),
          ),
          const _ThemeRow(),
          if (!web && DeviceSettings.canOpenAppSettings)
            _MeRow(
              icon: AppIcons.refresh,
              label: '后台运行设置',
              trailing: Text(
                'HyperOS',
                textAlign: TextAlign.right,
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
              onTap: () => _openBackgroundSettings(context),
            ),
        ]),
        const SizedBox(height: AppSpacing.x3),
        _section(c, '隐私与协议'),
        const SizedBox(height: AppSpacing.x1),
        _rows(c, [
          _MeRow(
            icon: AppIcons.lock,
            label: '隐私政策',
            onTap: () => showLegalPage(context, LegalDoc.privacy),
          ),
          _MeRow(
            icon: AppIcons.book,
            label: '用户协议',
            onTap: () => showLegalPage(context, LegalDoc.terms),
          ),
          if (web)
            _MeRow(
              icon: AppIcons.book,
              label: '账号注销说明',
              onTap: () => launchUrl(
                Uri.parse('/account-deletion.html'),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ]),
        const SizedBox(height: AppSpacing.x3),
        if (accountAfterLegal) ...[
          _accountGroup(context, user),
          const SizedBox(height: AppSpacing.x3),
        ],
        _section(c, '资源'),
        const SizedBox(height: AppSpacing.x1),
        _rows(c, [
          _MeRow(
            icon: AppIcons.library,
            label: '资源库',
            trailing: AppIcon(
              strokeSvg(AppIcons.chevronRight, width: 2),
              size: 18,
              color: c.inkSoft,
            ),
            onTap: () => openNegativeScreen(),
          ),
        ]),
        const SizedBox(height: AppSpacing.x3),
        _section(c, '关于'),
        const SizedBox(height: AppSpacing.x1),
        _rows(c, [
          const _MeRow(
            icon: AppIcons.book,
            label: '当前版本',
            trailing: _VersionLabel(),
          ),
        ]),
        const SizedBox(height: AppSpacing.x3),
        _section(c, '联系我们'),
        const SizedBox(height: AppSpacing.x1),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          ),
          child: Wrap(
            spacing: AppSpacing.x1,
            runSpacing: AppSpacing.x1,
            children: [
              _contactChip(context, 'KOOK 25343821', '25343821'),
              _contactChip(context, '微信 Tangerine-1017', 'Tangerine-1017'),
              _contactChip(
                context,
                '邮箱 mint10177@outlook.com',
                'mint10177@outlook.com',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
      ],
    );
  }

  Widget _quickGrid(BuildContext context, AppState state, {required bool web}) {
    final items = <Widget>[
      _QuickTile(
        icon: AppIcons.note,
        label: '我的笔记',
        onTap: () => showNotesModal(context),
      ),
      _QuickTile(
        icon: AppIcons.users,
        label: '黑名单',
        onTap: () => showBlockedUsersSheet(context),
      ),
      if (web)
        const _QuickTile(
          icon: AppIcons.download,
          label: '下载 App',
          onTap: _downloadApp,
        )
      else if (platform.isAndroid || platform.isWindows)
        _QuickTile(
          icon: AppIcons.refresh,
          label: '检查更新',
          onTap: () => checkForUpdates(context, manual: true),
        ),
      if (!kIsWeb && (platform.isAndroid || platform.isIOS))
        _QuickTile(
          icon: AppIcons.scan,
          label: '扫一扫',
          onTap: () => showScanLogin(context),
        ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 320
            ? (items.length <= 4 ? items.length : 5)
            : 2;
        const spacing = AppSpacing.x1;
        final itemWidth = (box.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items) SizedBox(width: itemWidth, child: item),
          ],
        );
      },
    );
  }

  Widget _profileHero(
    BuildContext context,
    AppState state,
    User? user, {
    required bool web,
    required bool floating,
  }) {
    final c = context.c;
    final avatarSize = web ? 66.0 : (floating ? 58.0 : 52.0);
    return Pressable(
      onTap: () {
        if (user == null) {
          showAuthModal(context);
        } else {
          showProfileModal(context);
        }
      },
      child: CitroCard(
        padding: EdgeInsets.fromLTRB(
          web ? 22 : 18,
          web ? 20 : 16,
          web ? 18 : 16,
          web ? 18 : 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CitroHero(
                  // 侧栏/折叠栏的头像才参与容器变换；Tab 内与浮层里的
                  // 副本用独立 tag，避免同一路由子树出现两个相同 Hero。
                  tag: CitroHero.tagOf(
                    'profile',
                    embedded || floating ? 'tab' : 'me',
                  ),
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius:
                          BorderRadius.circular(CitroColors.radii.inner),
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
                                size: avatarSize * .42,
                                color: c.ink2,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.x2),
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
                                size: web ? 22 : (floating ? 20 : 18),
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
                                borderRadius:
                                    BorderRadius.circular(CitroColors.radii.chip),
                                border: Border.all(color: c.mintLine),
                              ),
                              child: Text(
                                state.loggedIn ? '云端同步' : '游客',
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
                      const SizedBox(height: 4),
                      Text(
                        user == null
                            ? '点击登录 / 注册，收藏与记录会跟着你'
                            : '今天也把日子过成喜欢的样子',
                        maxLines: 2,
                        style: context.body(
                          size: CitroType.small,
                          color: c.inkSoft,
                          height: 1.45,
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
            SizedBox(height: web ? 18 : 14),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: web ? 14 : 4,
                vertical: web ? 12 : 10,
              ),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(CitroColors.radii.inner),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _heroStat(
                      context,
                      '连续打卡',
                      '${state.checkinStreak} 天',
                    ),
                  ),
                  _heroDivider(c),
                  Expanded(
                    child: _heroStat(
                      context,
                      '卡面收藏',
                      CardCatalog.all.isEmpty
                          ? '—'
                          : '${state.cardOwnedCount}/${CardCatalog.all.length}',
                    ),
                  ),
                  _heroDivider(c),
                  Expanded(
                    child: _heroStat(
                      context,
                      '抽卡机会',
                      '${state.cardCredits} 次',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _section(CitroColors c, String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(CitroColors.radii.xs),
          ),
        ),
        const SizedBox(width: AppSpacing.x2),
        Builder(
          builder: (ctx) => Text(
            title,
            style: ctx.heading(
              size: CitroType.label,
              color: c.ink,
            ),
          ),
        ),
      ],
    );
  }

  Widget _rows(CitroColors c, List<Widget> children) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CitroColors.radii.card),
          boxShadow: CitroColors.shadows.card(c),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) CitroDivider(color: c.line, margin: const EdgeInsets.symmetric(vertical: 2)),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _contactChip(BuildContext context, String label, String value) {
    final c = context.c;
    return Pressable(
      onTap: () => copyText(value, context: context, tip: '已复制 $value'),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: kIsWeb ? 18 : 14,
          vertical: kIsWeb ? 10 : 8,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: c.line2),
        ),
        child: Text(
          label,
          style: context.body(size: CitroType.meta, color: c.ink2),
        ),
      ),
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

  Future<void> _openBackgroundSettings(BuildContext context) async {
    final go = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('后台运行设置', style: context.heading(size: 20)),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'HyperOS / MIUI 的省电策略可能限制后台计时、定位与音频。'
              '若提醒不准时或听隅被暂停，请在本应用的「省电策略」中选择「无限制」。',
              style: context.body(
                size: CitroType.caption,
                color: context.c.inkSoft,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '稍后',
                    outlined: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: AppSpacing.x1),
                Expanded(
                  child: AccentButton(
                    text: '去设置',
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (go != true) return;
    final ok = await DeviceSettings.openAppSettings();
    if (context.mounted && !ok) AppToast.show(context, '未能打开系统设置');
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('退出登录？', style: context.heading(size: 20)),
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

class _MeToggleRow extends StatelessWidget {
  final String icon;
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _MeToggleRow({
    required this.icon,
    required this.label,
    this.hint = '',
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kIsWeb ? 14 : 10,
        vertical: kIsWeb ? 12 : 8,
      ),
      child: Row(
        children: [
          AppIcon(strokeSvg(icon, width: 2), size: 20, color: c.accentInk),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.body(size: CitroType.body, color: c.ink),
                ),
                if (hint.isNotEmpty)
                  Text(
                    hint,
                    style: context.body(size: CitroType.micro, color: c.inkSoft),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: c.surface,
            activeTrackColor: c.accent,
            inactiveThumbColor: c.inkSoft,
            inactiveTrackColor: c.line2,
          ),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kIsWeb ? 14 : 10,
        vertical: kIsWeb ? 12 : 8,
      ),
      child: Row(
        children: [
          AppIcon(
            strokeSvg(AppIcons.sun, width: 2),
            size: 20,
            color: c.accentInk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题', style: context.body(size: CitroType.body, color: c.ink)),
                Text(
                  '浅色、深色或跟随系统',
                  style: context.body(size: CitroType.micro, color: c.inkSoft),
                ),
              ],
            ),
          ),
          const _ThemeDropdown(),
        ],
      ),
    );
  }
}

class _ThemeDropdown extends StatefulWidget {
  const _ThemeDropdown();

  @override
  State<_ThemeDropdown> createState() => _ThemeDropdownState();
}

class _ThemeDropdownState extends State<_ThemeDropdown> {
  static const _modes = <ThemeMode>[
    ThemeMode.light,
    ThemeMode.dark,
    ThemeMode.system,
  ];

  static String _label(ThemeMode mode) => switch (mode) {
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
    ThemeMode.system => '跟随系统',
  };

  static String _icon(ThemeMode mode) => switch (mode) {
    ThemeMode.light => AppIcons.sun,
    ThemeMode.dark => AppIcons.moon,
    ThemeMode.system => AppIcons.monitor,
  };

  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  void _toggle() {
    if (_entry == null) {
      _show();
    } else {
      _close();
    }
  }

  void _show() {
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (overlayContext) {
        final c = overlayContext.c;
        final current = AppScope.of(overlayContext).themeMode;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 6),
              child: _menu(overlayContext, c, current),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
    setState(() {});
  }

  void _close() {
    _removeEntry();
    if (mounted) setState(() {});
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _select(ThemeMode mode) {
    _close();
    AppScope.of(context).setThemeMode(mode);
  }

  Widget _menu(BuildContext context, CitroColors c, ThemeMode current) {
    final width = kIsWeb ? 152.0 : 144.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: .96 + .04 * t,
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
      child: Material(
        color: c.surface,
        elevation: 16,
        shadowColor: c.scrim,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CitroColors.radii.card),
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          key: const ValueKey('me-theme-menu'),
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in _modes) _item(context, c, mode, current),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    CitroColors c,
    ThemeMode mode,
    ThemeMode current,
  ) {
    final active = mode == current;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: () => _select(mode),
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        hoverColor: c.surface2,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? c.accentLt.withAlpha(120) : Colors.transparent,
            borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          ),
          child: Row(
            children: [
              AppIcon(
                strokeSvg(_icon(mode), width: 2),
                size: 18,
                color: active ? c.accentInk : c.inkSoft,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _label(mode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(
                    size: CitroType.meta,
                    weight: active ? CitroType.medium : CitroType.regular,
                    color: active ? c.accentInk : c.ink2,
                  ),
                ),
              ),
              if (active)
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final current = context.app.themeMode;
    final width = kIsWeb ? 118.0 : 110.0;
    return CompositedTransformTarget(
      link: _link,
      child: Semantics(
        button: true,
        label: '主题，当前${_label(current)}',
        child: Pressable(
          key: const ValueKey('me-theme-dropdown'),
          onTap: _toggle,
          child: Container(
            width: width,
            height: kIsWeb ? 34 : 32,
            padding: const EdgeInsets.only(left: 10, right: 8),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              border: Border.all(color: c.line2),
            ),
            child: Row(
              children: [
                AppIcon(
                  strokeSvg(_icon(current), width: 2),
                  size: 14,
                  color: c.accentInk,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _label(current),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: CitroType.caption,
                      weight: CitroType.medium,
                      color: c.ink2,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                AppIcon(
                  strokeSvg(AppIcons.chevronDown, width: 2),
                  size: 12,
                  color: c.inkSoft,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MeRow extends StatefulWidget {
  final String icon;
  final String label;
  final bool danger;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _MeRow({
    required this.icon,
    required this.label,
    this.danger = false,
    this.onTap,
    this.trailing,
  });

  @override
  State<_MeRow> createState() => _MeRowState();
}

class _MeRowState extends State<_MeRow> {
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
              constraints: const BoxConstraints(minHeight: kIsWeb ? 54 : 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kIsWeb ? 14 : 10,
                  vertical: kIsWeb ? 12 : 8,
                ),
                child: Row(
                  children: [
                    AppIcon(
                      strokeSvg(widget.icon, width: 2),
                      size: 20,
                      color: widget.danger ? c.danger : c.accentInk,
                    ),
                    const SizedBox(width: kIsWeb ? 12 : 10),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: context.body(
                          size: kIsWeb ? CitroType.body : CitroType.meta,
                          weight: kIsWeb ? CitroType.medium : CitroType.regular,
                          color: color,
                        ),
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: widget.trailing!,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x1),
                    ],
                    if (widget.onTap != null)
                      AppIcon(
                        strokeSvg(AppIcons.chevronRight, width: 2),
                        size: 15,
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

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.label, this.onTap});

  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CitroColors.radii.card),
          boxShadow: CitroColors.shadows.card(c),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.surface2,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(icon, width: 2),
                  size: 18,
                  color: c.ink2,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(
                size: CitroType.small,
                weight: CitroType.medium,
                color: c.ink2,
              ),
            ),
          ],
        ),
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
