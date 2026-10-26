import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../overlays/auth_modal.dart';
import '../overlays/blocked_users.dart';
import '../overlays/delete_account.dart';
import '../overlays/notes_modal.dart';
import '../overlays/profile_modal.dart';
import '../overlays/update_dialog.dart';
import '../services/api.dart';
import '../services/notifications.dart';
import '../services/platform.dart' as platform;
import '../services/updater.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'legal_page.dart';

Future<void> showMeWindow(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭我的',
    barrierColor: const Color(0x8A23211C),
    transitionDuration: const Duration(milliseconds: 220),
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
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 30,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: MediaQuery(
                data: media.copyWith(size: Size(width, height)),
                child: const MePage(floating: true),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class MePage extends StatelessWidget {
  final bool floating;

  const MePage({super.key, this.floating = false});

  static void _downloadApp() {
    launchUrl(
      Uri.parse('https://obs.chimu-claw.xyz/APK/Citro-v1.8.0-release.apk'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.app;
    final c = context.c;
    final user = state.user;
    final duo =
        !platform.isWindows && CitroForm.duoDevice(MediaQuery.sizeOf(context));
    final width = MediaQuery.sizeOf(context).width;
    final web = kIsWeb && !floating;
    final side = math.max(8.0, (width - (web ? 760 : 640)) / 2);
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(side, web ? 22 : 8, side, 36),
            child: Stack(
              children: [
                Positioned(
                  right: -34,
                  bottom: -24,
                  child: IgnorePointer(
                    child: Transform.rotate(
                      angle: -8 * math.pi / 180,
                      child: Opacity(
                        opacity: .10,
                        child: Image.asset(
                          'assets/images/logo.webp',
                          width: 210,
                          cacheWidth: 420,
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (!duo && !floating) ...[
                          Pressable(
                            onTap: () => popOrHome(context),
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
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
                                    size: 15,
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
                        ],
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('我的', style: context.heading(size: web ? 30 : 20)),
                        if (web) ...[
                          const SizedBox(width: 12),
                          Text(
                            'ACCOUNT & PREFERENCES',
                            style: context.body(
                              size: 9.5,
                              weight: FontWeight.w700,
                              color: c.inkSoft,
                              letterSpacing: 1.7,
                            ),
                          ),
                        ],
                        if (floating) ...[
                          const Spacer(),
                          Pressable(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: c.surface2,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.line),
                                boxShadow: CitroColors.shadows.paper(c),
                              ),
                              child: Center(
                                child: AppIcon(
                                  strokeSvg(AppIcons.close, width: 2.2),
                                  size: 15,
                                  color: c.ink2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: web ? 22 : 16),
                    Pressable(
                      onTap: () {
                        if (user == null) {
                          showAuthModal(context);
                        } else {
                          showProfileModal(context);
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.all(web ? 20 : 14),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(web ? 18 : 14),
                          border: Border.all(color: c.line),
                          boxShadow: CitroColors.shadows.paper(c),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: web ? 64 : 48,
                              height: web ? 64 : 48,
                              decoration: BoxDecoration(
                                color: user == null ? c.accent : c.hl,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: c.line2),
                                image: user?.av != null
                                    ? DecorationImage(
                                        image: ResizeImage(
                                          NetworkImage(Api.imageUrl(user!.av)),
                                          width: 144,
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
                                        style: context.display(
                                          size: web ? 27 : 22,
                                          weight: FontWeight.w700,
                                          color: const Color(0xFF2E2C22),
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user?.name ?? '未登录',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.display(
                                      size: web ? 21 : 17,
                                      weight: FontWeight.w700,
                                      color: c.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    user == null
                                        ? '点击登录 / 注册'
                                        : '社区成员 · 数据云端同步',
                                    style: context.body(
                                      size: web ? 13 : 12,
                                      color: c.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (user != null)
                              AppIcon(
                                strokeSvg(AppIcons.chevronRight, width: 2),
                                size: 17,
                                color: c.inkSoft,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (kIsWeb) ...[
                      SizedBox(height: web ? 28 : 18),
                      _section(c, '应用'),
                      const SizedBox(height: 8),
                      _rows(c, [
                        _MeRow(
                          icon: AppIcons.download,
                          label: '下载 App 客户端',
                          trailing: Text(
                            'Android · v1.8.0 · 75.0MB',
                            style: context.body(size: 10.5, color: c.inkSoft),
                          ),
                          onTap: _downloadApp,
                        ),
                      ]),
                    ],
                    SizedBox(height: web ? 28 : 18),
                    _section(c, '账号'),
                    const SizedBox(height: 8),
                    _rows(c, [
                      _MeRow(
                        icon: AppIcons.note,
                        label: '我的笔记',
                        onTap: () => showNotesModal(context),
                      ),
                      _MeRow(
                        icon: AppIcons.user,
                        label: '更改信息',
                        onTap: () {
                          if (user == null) {
                            showAuthModal(context);
                          } else {
                            showProfileModal(context);
                          }
                        },
                      ),
                      if (user != null)
                        _MeRow(
                          icon: AppIcons.logout,
                          label: '退出登录',
                          danger: true,
                          onTap: () => _confirmLogout(context),
                        ),
                      if (user != null)
                        _MeRow(
                          icon: AppIcons.trash,
                          label: '注销账号（永久删除）',
                          danger: true,
                          onTap: () => _deleteAccount(context),
                        ),
                    ]),
                    SizedBox(height: web ? 28 : 18),
                    _section(c, '隐私与协议'),
                    const SizedBox(height: 8),
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
                      _MeRow(
                        icon: AppIcons.users,
                        label: state.blockedUsers.isEmpty
                            ? '黑名单'
                            : '黑名单（${state.blockedUsers.length}）',
                        onTap: () => showBlockedUsersSheet(context),
                      ),
                      if (kIsWeb)
                        _MeRow(
                          icon: AppIcons.book,
                          label: '账号注销说明',
                          onTap: () => launchUrl(
                            Uri.parse('/account-deletion.html'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                    ]),
                    SizedBox(height: web ? 28 : 18),
                    _section(c, '通知'),
                    const SizedBox(height: 8),
                    _rows(c, [
                      _MeToggleRow(
                        icon: AppIcons.bell,
                        label: '通知提醒',
                        hint: platform.isWindows ? '桌面端以应用内提醒呈现' : '社区消息与烹饪计时',
                        value: state.notificationsEnabled,
                        onChanged: (v) => _setNotifications(context, v),
                      ),
                    ]),
                    SizedBox(height: web ? 28 : 18),
                    _section(c, '外观'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _themeChip(context, '浅色', ThemeMode.light),
                        _themeChip(context, '深色', ThemeMode.dark),
                        _themeChip(context, '跟随系统', ThemeMode.system),
                      ],
                    ),
                    if (platform.isAndroid || platform.isWindows) ...[
                      const SizedBox(height: 18),
                      _section(c, '关于'),
                      const SizedBox(height: 8),
                      _rows(c, [
                        _MeRow(
                          icon: AppIcons.refresh,
                          label: '检查更新',
                          trailing: const _VersionLabel(),
                          onTap: () => checkForUpdates(context, manual: true),
                        ),
                      ]),
                    ],
                    SizedBox(height: web ? 28 : 18),
                    _section(c, '联系我们'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _contactChip(context, 'KOOK 25343821', '25343821'),
                        _contactChip(
                          context,
                          '微信 Tangerine-1017',
                          'Tangerine-1017',
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(CitroColors c, String title) {
    return Row(
      children: [
        Container(
          width: kIsWeb ? 7 : 6,
          height: kIsWeb ? 7 : 6,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Builder(
          builder: (ctx) => Text(
            title,
            style: ctx.body(
              size: kIsWeb ? 12.5 : 11.5,
              weight: FontWeight.w800,
              color: c.accentInk,
              letterSpacing: kIsWeb ? 1.3 : 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _rows(CitroColors c, List<Widget> children) {
    if (kIsWeb) {
      return Column(
        children: [
          for (final child in children)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.line),
                boxShadow: CitroColors.shadows.paper(c),
              ),
              child: child,
            ),
        ],
      );
    }
    final list = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      list.add(children[i]);
      if (i < children.length - 1) {
        list.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DashedLine(color: c.line2.withAlpha(140)),
          ),
        );
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.paper(c),
      ),
      child: Column(children: list),
    );
  }

  Widget _themeChip(BuildContext context, String label, ThemeMode mode) {
    final state = context.app;
    final active = state.themeMode == mode;
    final c = context.c;
    return Pressable(
      onTap: () => state.setThemeMode(mode),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: kIsWeb ? 18 : 14,
          vertical: kIsWeb ? 10 : 7,
        ),
        decoration: BoxDecoration(
          color: active ? c.hl : c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? c.accent : c.line2.withAlpha(150)),
        ),
        child: Text(
          label,
          style: context.body(
            size: 12.5,
            weight: FontWeight.w600,
            color: active ? c.accentInk : c.ink2,
          ),
        ),
      ),
    );
  }

  Widget _contactChip(BuildContext context, String label, String value) {
    final c = context.c;
    return Pressable(
      onTap: () => copyText(value, context: context, tip: '已复制 $value'),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: kIsWeb ? 18 : 14,
          vertical: kIsWeb ? 10 : 7,
        ),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line2.withAlpha(150)),
        ),
        child: Text(label, style: context.body(size: 12.5, color: c.ink2)),
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

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('退出登录？', style: context.heading(size: 21)),
            const SizedBox(height: 8),
            Text(
              '退出后仍会保留社区内容',
              style: context.body(size: 12, color: context.c.inkSoft),
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
      padding: EdgeInsets.symmetric(
        horizontal: kIsWeb ? 14 : 0,
        vertical: kIsWeb ? 11 : 8,
      ),
      child: Row(
        children: [
          AppIcon(strokeSvg(icon, width: 2), size: 20, color: c.accentInk),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.body(size: 13.5, color: c.ink)),
                if (hint.isNotEmpty)
                  Text(hint, style: context.body(size: 9.5, color: c.inkSoft)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: c.surface2,
            activeTrackColor: c.accent,
            inactiveThumbColor: c.inkSoft,
            inactiveTrackColor: c.line2,
          ),
        ],
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
    final dangerColor = c.dark
        ? const Color(0xFFFF8A80)
        : const Color(0xFFB42318);
    final color = widget.danger ? dangerColor : c.ink;
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
            color: _hover ? c.hl.withAlpha(45) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: kIsWeb ? 54 : 44),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: kIsWeb ? 15 : 0,
                  vertical: kIsWeb ? 10 : 12,
                ),
                child: Row(
                  children: [
                    AppIcon(
                      strokeSvg(widget.icon, width: 2),
                      size: kIsWeb ? 21 : 20,
                      color: widget.danger ? dangerColor : c.accentInk,
                    ),
                    SizedBox(width: kIsWeb ? 12 : 10),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: context.body(
                          size: kIsWeb ? 14.5 : 13.5,
                          weight: kIsWeb ? FontWeight.w600 : FontWeight.w400,
                          color: color,
                        ),
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      Flexible(child: widget.trailing!),
                      const SizedBox(width: 6),
                    ],
                    AppIcon(
                      strokeSvg(AppIcons.chevronRight, width: 2),
                      size: 15,
                      color: c.inkSoft.withAlpha(140),
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
          style: context.body(size: 11, color: c.inkSoft),
        );
      },
    );
  }
}
