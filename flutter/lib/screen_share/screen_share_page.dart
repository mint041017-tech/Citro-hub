import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../services/prefs.dart';
import '../../state/app_state.dart';
import '../../widgets/paper.dart';
import 'screen_share_controller.dart';
import 'screen_share_room_page.dart';
import 'screen_share_theme.dart';

const String _recentRoomsKey = 'citro_share_recent_rooms';

/// 「一起看」入口：发起一起看 / 用房间号加入。
///
/// 参照 KOOK 的房间入口重做过：这一页只做两件事，不再堆模式、画质这些
/// 设置 —— 画质放到房间内的「一起看设置」里，由主持人调整。
/// 控制器是「每次尝试一个新的」，成功后交给房间页持有。
class ScreenSharePage extends StatefulWidget {
  const ScreenSharePage({super.key, this.initialCode});

  /// 从邀请链接带进来的房间码，直接填进输入框。
  final String? initialCode;

  @override
  State<ScreenSharePage> createState() => _ScreenSharePageState();
}

class _ScreenSharePageState extends State<ScreenSharePage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _code = TextEditingController();

  /// `create` / `join` / null。分开记是为了只让真正在跑的那个按钮转圈。
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    final code = widget.initialCode?.trim() ?? '';
    if (RegExp(r'^\d{6}$').hasMatch(code)) _code.text = code;
  }

  @override
  void dispose() {
    _title.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(
    String action,
    Future<void> Function(ScreenShareController) fn,
  ) async {
    if (_busyAction != null) return;
    setState(() => _busyAction = action);
    final controller = ScreenShareController();
    try {
      await fn(controller);
      if (!mounted) {
        controller.dispose();
        return;
      }
      if (controller.inRoom) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ScreenShareRoomPage(controller: controller),
          ),
        );
        return;
      }
      AppToast.show(context, controller.error ?? '操作失败，请稍后再试');
    } finally {
      // 只有失败时才在这里回收；成功的话所有权已经交给房间页。
      if (!controller.inRoom) controller.dispose();
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _create() {
    final title = _title.text.trim();
    return _run(
      'create',
      (c) => c.createRoom(title: title.isEmpty ? '一起看' : title),
    );
  }

  Future<void> _join() {
    final raw = _code.text.trim();
    if (raw.isEmpty) {
      AppToast.show(context, '请输入 6 位房间号');
      return Future<void>.value();
    }
    // 支持直接粘贴完整邀请链接。房间号就是 DO 的 key，不需要 roomId。
    final code = extractRoomCode(raw);
    return _run(
      'join',
      (c) => c.joinRoom(
        roomId: code,
        code: code,
        // 信令侧走游客 uid，这里只把昵称带进去做显示。
        name: context.app.user?.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = width >= 700 ? 48.0 : AppSpacing.x2;
    // 手机（Android / iPhone）上整页压紧一档：入口页只是「发起 / 加入」，
    // 卡片不该占掉大半屏。iPad 与桌面保持原来的呼吸感。
    final compact = width < 600;
    return ShareTheme(
      child: Scaffold(
        backgroundColor: shareColors.bg,
        body: Stack(
          children: [
            // 舞台顶灯：只在标题后面亮一团暖橙，别把整页照亮。
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -1.15),
                      radius: 1.1,
                      colors: <Color>[Color(0x33E8703A), Color(0x00E8703A)],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // 返回固定在页面左上角：不跟 480 宽的正文列走，也不留桌面
                  // 那 48px 的大边距。贴住安全区左上角，和房间页的返回同一个位置。
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.x1,
                      AppSpacing.x1,
                      side,
                      0,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _PillButton(
                        icon: AppIcons.arrowLeft,
                        label: '返回',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        side,
                        compact ? AppSpacing.x2 : AppSpacing.x3,
                        side,
                        compact ? AppSpacing.x3 : 40,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: _LobbyBody(
                            title: _title,
                            code: _code,
                            busyAction: _busyAction,
                            compact: compact,
                            onCreate: _create,
                            onJoin: _join,
                            onRecent: (code) {
                              _code.text = code;
                              _join();
                            },
                          ),
                        ),
                      ),
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
}

class _LobbyBody extends StatelessWidget {
  const _LobbyBody({
    required this.title,
    required this.code,
    required this.busyAction,
    required this.compact,
    required this.onCreate,
    required this.onJoin,
    required this.onRecent,
  });

  final TextEditingController title;
  final TextEditingController code;
  final String? busyAction;

  /// 手机窄屏：品牌区、卡片内边距和间距整体收紧。
  final bool compact;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final ValueChanged<String> onRecent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final recent = Prefs.getStringList(_recentRoomsKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 品牌区：网页观看端用的是同一张 logo，App 里也用它，别再用字母占位。
        Column(
          children: [
            Image.asset(
              'assets/images/logo.webp',
              width: compact ? 68 : 96,
              height: compact ? 68 : 96,
              cacheWidth: 220,
            ),
            SizedBox(height: compact ? 6.0 : AppSpacing.x2),
            Text(
              '一起看',
              textAlign: TextAlign.center,
              style: context.display(
                size: compact ? CitroType.display : CitroType.hero,
                color: c.ink,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '把屏幕放进房间，和朋友一起看',
              textAlign: TextAlign.center,
              style: context.body(
                size: compact ? CitroType.meta : CitroType.body,
                color: c.ink2,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 22.0 : 36.0),
        if (!ScreenShareController.canPublish) ...[
          _Notice(icon: AppIcons.info, text: '当前平台只能观看，不能发起一起看。'),
          const SizedBox(height: AppSpacing.x2),
        ],
        CitroCard(
          padding: EdgeInsets.all(compact ? 16 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '和朋友一起看',
                style: context.heading(
                  size: compact ? CitroType.title : CitroType.titleLg,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '开一个房间，把 6 位房间号发给朋友',
                style: context.body(size: CitroType.meta, color: c.inkSoft),
              ),
              SizedBox(height: compact ? 12 : AppSpacing.x2),
              CitroTextField(
                controller: title,
                hint: '房间名（可留空）',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (ScreenShareController.canPublish) onCreate();
                },
              ),
              SizedBox(height: compact ? 12 : 14),
              CitroButton(
                label: '发起一起看',
                icon: AppIcon(AppIcons.monitor, size: 18, color: c.onAccent),
                style: CitroButtonStyle.accent,
                expanded: true,
                height: compact ? 46 : 52,
                busy: busyAction == 'create',
                onPressed: ScreenShareController.canPublish ? onCreate : null,
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 12 : AppSpacing.x2),
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            compact ? 14 : 18,
            16,
            compact ? 16 : 20,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(CitroColors.radii.card),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '有房间号？',
                style: context.heading(size: CitroType.title, color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                '输入朋友给你的 6 位房间号，直接进去看',
                style: context.body(size: CitroType.meta, color: c.inkSoft),
              ),
              SizedBox(height: compact ? 12 : AppSpacing.x2),
              Row(
                children: [
                  Expanded(
                    child: CitroTextField(
                      controller: code,
                      hint: '例如 123456',
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onSubmitted: (_) => onJoin(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  CitroButton(
                    label: '加入',
                    style: CitroButtonStyle.primary,
                    busy: busyAction == 'join',
                    onPressed: busyAction == null ? onJoin : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (recent.isNotEmpty) ...[
          SizedBox(height: compact ? AppSpacing.x2 : AppSpacing.x3),
          Text(
            '最近去过',
            style: context.body(size: CitroType.meta, color: c.inkSoft),
          ),
          const SizedBox(height: AppSpacing.x1),
          Wrap(
            spacing: AppSpacing.x1,
            runSpacing: AppSpacing.x1,
            children: [
              for (final entry in recent)
                _RecentChip(
                  // 存的是 `房间码:roomId`，给用户看的只有房间码。
                  code: entry.split(':').first,
                  onTap: () => onRecent(entry.split(':').first),
                ),
            ],
          ),
        ],
        SizedBox(height: compact ? 24.0 : 40.0),
        Text(
          '朋友没装 App？把邀请链接发给他，浏览器打开就能看。',
          textAlign: TextAlign.center,
          style: context.body(size: CitroType.caption, color: c.inkSoft),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(strokeSvg(icon, width: 2.2), size: 15, color: c.ink2),
            const SizedBox(width: 5),
            Text(
              label,
              style: context.body(
                size: CitroType.label,
                weight: CitroType.medium,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.code, required this.onTap});

  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(AppIcons.clock, size: 13),
            const SizedBox(width: 6),
            Text(
              code,
              style: context.hand(size: CitroType.label, color: c.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: c.accentLt,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: c.accent.withValues(alpha: .32)),
      ),
      child: Row(
        children: [
          AppIcon(icon, size: 16, color: c.accentInk),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              text,
              style: context.body(size: CitroType.meta, color: c.accentInk),
            ),
          ),
        ],
      ),
    );
  }
}

/// 从用户输入里取出 6 位房间号。
///
/// 接受的形态：`123456`、`房间号 123456`、以及完整邀请链接
/// `https://share.mint1017.cn/?room=123456`。
///
/// 公开是为了能测：邀请链接是需求里「链接邀请」的入口，解析错了就进不去。
String extractRoomCode(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri != null && uri.hasQuery) {
    final fromQuery = uri.queryParameters['room'];
    if (fromQuery != null && RegExp(r'^\d{6}$').hasMatch(fromQuery))
      return fromQuery;
  }
  final match = RegExp(r'\b(\d{6})\b').firstMatch(raw);
  return match?.group(1) ?? raw;
}
