import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/desktop_shell.dart';
import '../../widgets/modal.dart';
import '../../widgets/paper.dart';
import '../services/platform.dart' as platform;
import 'danmaku_bridge.dart';
import 'room_models.dart';
import 'screen_capture.dart';
import 'screen_share_controller.dart';
import 'screen_share_theme.dart';
import 'widgets/chat_panel.dart';
import 'widgets/danmaku_layer.dart';
import 'widgets/members_panel.dart';
import 'widgets/mini_window.dart';
import 'widgets/remote_view.dart';
import 'widgets/share_quality_picker.dart';
import 'widgets/share_source_picker.dart';

/// 「一起看」房间页：大画面 + 成员 + 悬浮控制条。
///
/// 参照 KOOK 重做过：舞台占满，人数 / 画质挂在标题下面，底部是一条
/// 悬浮控制条（一起看 / 开麦 / 聊天 / 成员 / 设置）。退出只留左上角
/// 返回一个入口，不再和底部的离开键重复。麦克风只有主持端有（Dock 的
/// 开麦键由 isHost 门禁）；观众说话走文字聊天，观众之间没有实时语音。
class ScreenShareRoomPage extends StatefulWidget {
  const ScreenShareRoomPage({super.key, required this.controller});

  final ScreenShareController controller;

  @override
  State<ScreenShareRoomPage> createState() => _ScreenShareRoomPageState();
}

class _ScreenShareRoomPageState extends State<ScreenShareRoomPage> {
  String? _selectedUid;
  bool _endedShown = false;
  String? _lastError;

  /// 全屏放映压着的整页路由；null 表示没有。
  FullscreenStageRoute? _fullscreenRoute;

  /// 舞台重建纪元:退出全屏后 +1,给舞台子树换 key 强制 RTCVideoView
  /// 重新绑定 texture(方向恢复后首帧尺寸可能停在横屏值,画面被压成
  /// 一条)。见 _syncFullscreenRoute 的注释。
  int _stageEpoch = 0;

  ScreenShareController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onControllerChanged);
    if (c.ended) _showEnded();
  }

  @override
  void dispose() {
    c.removeListener(_onControllerChanged);
    // 全屏路由还压着就摘掉（不 pop，避免触发它的返回逻辑）。
    _fullscreenRoute?.navigator?.removeRoute(_fullscreenRoute!);
    _fullscreenRoute = null;
    c.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final err = c.error;
    if (err != null && err != _lastError) {
      _lastError = err;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppToast.show(context, err);
      });
    }
    if (c.ended) _showEnded();
    _syncFullscreenRoute();
  }

  /// 跟随控制器的 fullscreen 标记压 / 弹整页放映路由。
  ///
  /// 控制器只管状态和系统栏 / 方向；路由在页面这层做，因为
  /// Navigator 的 context 在这。didPop（系统返回手势）也会走到
  /// exitFullscreen，保证标记和路由不会失步。
  ///
  /// 退出必须走 pop（反向动画渐隐），不能用 removeRoute 硬拆：
  /// removeRoute 同帧销毁全屏树 + 恢复房间树，此刻系统栏和竖屏方向
  /// 还在异步恢复，RTC 的 texture 尺寸来不及重协商——画面被压成
  /// 顶部一条（用户实测截图）。pop 让两层树在 200ms 反向过渡里
  /// 交接，texture 有时间跟上布局变化。
  void _syncFullscreenRoute() {
    final want = c.fullscreen;
    final has = _fullscreenRoute != null;
    if (want && !has) {
      final route = FullscreenStageRoute(controller: c);
      _fullscreenRoute = route;
      Navigator.of(context).push(route).whenComplete(() {
        // 路由被 pop（含系统返回）后若标记还在，说明不是走控制器
        // 的退出路径，补一次收尾。
        if (c.fullscreen && mounted) c.exitFullscreen();
        if (_fullscreenRoute == route) _fullscreenRoute = null;
        // 出栈完成后强制房间页舞台重建：方向恢复后的首帧 texture
        // 尺寸可能还停在横屏值，重建让 RTCVideoView 重新绑定。
        if (mounted) {
          setState(() => _stageEpoch++);
        }
      });
    } else if (!want && has) {
      final route = _fullscreenRoute!;
      _fullscreenRoute = null;
      if (route.navigator != null && route.navigator!.canPop()) {
        if (route.isActive) {
          route.navigator!.pop();
        } else {
          // 已经被系统/手势 pop 掉,只是 whenComplete 还没跑:无需处理。
        }
      }
    }
  }

  void _showEnded() {
    if (_endedShown || !mounted) return;
    _endedShown = true;
    // 房间结束等于共享终结：主持人的弹幕悬浮窗不能再留在屏幕上
    //（dispose 里刻意不收——主持人最小化 App 继续共享时必须留着，
    // 只有真正结束才走这里收）。观众端从未显示过，hide 无害。
    unawaited(DanmakuBridge.hide());
    showCitroDialog<void>(
      context,
      dismissible: false,
      builder: (ctx) => ShareTheme(
        child: PaperDialog(
          showClose: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset(
                  'assets/images/logo.webp',
                  width: 56,
                  height: 56,
                  cacheWidth: 140,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                '一起看结束了',
                textAlign: TextAlign.center,
                style: ctx.heading(size: CitroType.subtitle),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                c.endReason ?? '主持人已结束一起看',
                textAlign: TextAlign.center,
                style: ctx.body(size: CitroType.meta, color: ctx.c.inkSoft),
              ),
              const SizedBox(height: AppSpacing.x3),
              CitroButton(
                label: '知道了',
                style: CitroButtonStyle.accent,
                expanded: true,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _pop());
  }

  void _pop() {
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _confirmExit() async {
    final isHost = c.isHost;
    final action = await showCitroDialog<String>(
      context,
      builder: (ctx) => ShareTheme(
        child: PaperDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isHost ? '结束一起看？' : '离开一起看？',
                style: ctx.heading(size: CitroType.subtitle),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                isHost ? '结束后所有人都会离开，房间立刻关闭。' : '离开后可以随时用房间号再进来。',
                style: ctx.body(size: CitroType.meta, color: ctx.c.inkSoft),
              ),
              const SizedBox(height: AppSpacing.x3),
              if (isHost) ...[
                CitroButton(
                  label: '结束一起看',
                  icon: const AppIcon(AppIcons.close, size: 18),
                  style: CitroButtonStyle.danger,
                  expanded: true,
                  onPressed: () => Navigator.of(ctx).pop('end'),
                ),
                const SizedBox(height: AppSpacing.x1),
              ],
              CitroButton(
                label: isHost ? '只离开，不结束' : '离开',
                style: CitroButtonStyle.outline,
                expanded: true,
                onPressed: () => Navigator.of(ctx).pop('leave'),
              ),
              const SizedBox(height: AppSpacing.x1),
              CitroButton(
                label: '再待一会儿',
                style: CitroButtonStyle.ghost,
                expanded: true,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'end') {
      await c.endRoom();
    } else {
      await c.leave();
    }
    // 房间都退了，本机的弹幕悬浮窗自然不能再留。
    unawaited(DanmakuBridge.hide());
    _pop();
  }

  /// 开始 / 停止一起看。
  ///
  /// 桌面端先弹源选择：整块屏幕，或某一个应用窗口 —— `getDisplayMedia`
  /// 的 `deviceId.exact` 只认 `getSources()` 枚举过的 id，选完再采集。
  /// Android / iOS 走系统授权，没有选择器。
  Future<void> _toggleSharing() async {
    if (c.publishing) {
      await c.stopSharing();
      // 停止共享后画面流里不再有本机屏幕，弹幕悬浮窗跟着收掉
      //（主持人在房间里继续看别人的画面时，屏幕上不该残留弹幕）。
      unawaited(DanmakuBridge.hide());
      return;
    }
    if (!ScreenShareController.canPublish) return;
    if (!platform.isWindows && !platform.isMacOS) {
      await c.startSharing();
      await _afterStartShare();
      return;
    }
    final sources = await ScreenCapture.listSources();
    if (!mounted) return;
    if (sources.isEmpty) {
      AppToast.show(context, '没有找到可共享的屏幕或窗口');
      return;
    }
    final picked = await showShareSourcePicker(
      context,
      sources,
      quality: c.quality,
    );
    if (!mounted || picked == null) return;
    await c.setQuality(picked.quality);
    await c.startSharing(sourceId: picked.source.id, withAudio: picked.withAudio);
    await _afterStartShare();
  }

  /// 共享刚起来时给一次明确反馈：失败原因，或「这段没有系统声音」。
  ///
  /// 手机上 Android / iOS 系统根本不提供第三方 App 的播放回环
  /// （iOS 连整屏采集都要走 ReplayKit 广播扩展），不是这里漏写；
  /// 桌面端则是 WASAPI loopback 初始化失败时会静默丢音轨。两种情况
  /// 都要说清楚，免得用户以为对方「听不到」是房间出了问题。
  Future<void> _afterStartShare() async {
    if (!mounted) return;
    if (!c.publishing) {
      final err = c.error;
      if (err != null && err.isNotEmpty) AppToast.show(context, err);
      return;
    }
    // 主持人的屏幕里要采到观众弹幕（App 最小化也在滚），悬浮窗随共享
    // 一起拉起。弹幕是锦上添花：拿不到悬浮窗权限就静默降级，只在设置
    // 弹层的开关旁提示缺权限，不打断共享流程。
    if (c.isHost && DanmakuBridge.enabled) {
      unawaited(DanmakuBridge.show());
    }
    if (c.hasSystemAudio) return;
    AppToast.show(
      context,
      platform.isAndroid || platform.isIOS
          ? '手机系统不允许录制其他应用的声音：对方只能听到画面'
          : '这次没有采到系统声音：对方只能听到画面',
    );
  }

  Future<void> _showSettings() {
    return showCitroSheet<void>(
      context: context,
      backgroundColor: shareColors.surface,
      builder: (_) => ShareTheme(child: _SettingsSheet(controller: c)),
    );
  }

  /// 主持人开/闭麦。开关结果由控制器 notifyListeners 刷 UI；失败时
  /// 控制器置 error，上面 _onControllerChanged 的 toast 兜底提示。
  void _toggleMic() {
    unawaited(c.toggleMic());
  }

  @override
  Widget build(BuildContext context) {
    // 宽屏（Windows 默认 1200 宽、平板横屏）右侧多一栏房间信息；
    // 窄屏只留舞台 + 底部控制条。
    final wide = MediaQuery.sizeOf(context).width >= 920;
    return ShareTheme(
      child: Scaffold(
        backgroundColor: shareColors.bg,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Stack(
              children: [
                Column(
                  children: [
                    _RoomTopBar(controller: c, onBack: _confirmExit),
                    Expanded(
                      child: wide
                          ? Row(
                              children: [
                                Expanded(
                                  child: _StageArea(
                                    controller: c,
                                    selectedUid: _selectedUid,
                                    onSelect: (uid) =>
                                        setState(() => _selectedUid = uid),
                                    stageEpoch: _stageEpoch,
                                  ),
                                ),
                                _SideRail(
                                  controller: c,
                                  onMembers: () => showMembersPanel(context, c),
                                ),
                              ],
                            )
                          : _StageArea(
                              controller: c,
                              selectedUid: _selectedUid,
                              onSelect: (uid) =>
                                  setState(() => _selectedUid = uid),
                              stageEpoch: _stageEpoch,
                            ),
                    ),
                    _Dock(
                      controller: c,
                      wide: wide,
                      onToggleShare: _toggleSharing,
                      onToggleMic: _toggleMic,
                      onChat: () => showChatPanel(context, c),
                      onMembers: () => showMembersPanel(context, c),
                      onSettings: _showSettings,
                    ),
                  ],
                ),
                if (c.miniWindow && c.mainRenderer != null)
                  ShareMiniWindow(
                    renderer: c.mainRenderer!,
                    label: c.mainPublisher?.displayName ?? '我的画面',
                    onExpand: c.closeMiniWindow,
                    onClose: () {
                      c.closeMiniWindow();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 顶栏 ────────────────────────────────────────────────────────────────

class _RoomTopBar extends StatelessWidget {
  const _RoomTopBar({required this.controller, required this.onBack});

  final ScreenShareController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final room = controller.room;
    final connected = controller.wsConnected;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.x1,
        AppSpacing.x1,
        // 右侧避开 Windows 悬浮的窗控（其他端 inset 为 0）。
        AppSpacing.x1 + CitroDesktopShell.windowControlsInset,
        AppSpacing.x1,
      ),
      child: Row(
        children: [
          _RoundIcon(icon: AppIcons.arrowLeft, tooltip: '返回', onTap: onBack),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room?.title.isNotEmpty == true ? room!.title : '一起看',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.heading(size: CitroType.bodyLg, color: c.ink),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: connected ? c.mint : c.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        connected
                            ? '${room?.viewerCount ?? 0} 人在线 · ${controller.quality.label} · ${room?.roomCode ?? ''}'
                            : '连接中…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(
                          size: CitroType.caption,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _MediaLinkBadge(controller: controller),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 当前媒体链路徽标：声网（Agora）或 Cloudflare。
///
/// 数据来自控制器：`agoraConnected` = 声网已连；否则一律显示 CF
///（未配证书 / 声网失败 / 观众端没切过去都是这个状态）。主持人共享中
/// 还会区分「声网已发布画面」—— 画面只走 CF 时提示声网未发布。
class _MediaLinkBadge extends StatelessWidget {
  const _MediaLinkBadge({required this.controller});

  final ScreenShareController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final onAgora = controller.agoraConnected;
    final label = onAgora ? '声网' : 'Cloudflare';
    final color = onAgora ? c.mint : c.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: context.body(
          size: CitroType.caption,
          weight: CitroType.medium,
          color: onAgora ? c.mint : c.accent,
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: AppSpacing.touch,
        height: AppSpacing.touch,
        child: Pressable(
          onTap: onTap,
          scale: 1,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
            child: AppIcon(strokeSvg(icon, width: 2), size: 18, color: c.ink2),
          ),
        ),
      ),
    );
  }
}

// ── 舞台 ────────────────────────────────────────────────────────────────

class _StageArea extends StatelessWidget {
  const _StageArea({
    required this.controller,
    required this.selectedUid,
    required this.onSelect,
    required this.stageEpoch,
  });

  final ScreenShareController controller;
  final String? selectedUid;
  final ValueChanged<String?> onSelect;

  /// 舞台重建纪元,由 State 传入:退出全屏后 +1,舞台子树换 key
  /// 强制 RTCVideoView 重新绑定 texture(方向恢复后首帧尺寸可能停在
  /// 横屏值,画面被压成一条)。
  final int stageEpoch;

  @override
  Widget build(BuildContext context) {
    final publishers = controller.remotePublishers;
    final selfUid = controller.selfUid;
    final sel = selectedUid;

    // 主持人自己也在共享时，舞台切换条里必须有「我的画面」——
    // 旧版只列远端，别人一开共享，主持人就回不到自己的画面了。
    final showSelf = controller.publishing && sel != null && sel == selfUid;
    final selectedRemote = (sel != null && sel != selfUid)
        ? publishers.where((m) => m.uid == sel).firstOrNull
        : null;
    final remote = showSelf
        ? null
        : (selectedRemote ?? controller.mainPublisher);
    final showLocal = controller.publishing && (showSelf || remote == null);

    final entries = <_StageEntry>[
      if (controller.publishing && selfUid != null)
        _StageEntry(uid: selfUid, name: '我的画面', isSelf: true),
      for (final m in publishers)
        _StageEntry(uid: m.uid, name: m.displayName, hasMic: m.hasMic),
    ];
    final activeUid = showLocal
        ? selfUid
        : (remote?.uid ?? (entries.isEmpty ? null : entries.first.uid));

    Widget stage;
    if (remote != null) {
      // 与全屏页共用同一判定（useAgoraRemoteRender）：两处同帧同结果，
      // 全屏 ↔ 房间切换时渲染器不切换、画面不闪黑。
      // key 带上 _stageEpoch:退出全屏后强制重建,RTC texture 重新协商
      // 尺寸(方向骤变后首帧可能停在横屏值,画面被压成一条)。
      if (controller.useAgoraRemoteRender) {
        stage = _AgoraRemoteView(
          key: ValueKey('agora-stage-$stageEpoch-${controller.agoraRemoteUid}'),
          uid: controller.agoraRemoteUid!,
          connection: RtcConnection(
            channelId: controller.roomId,
            localUid: controller.agoraSelfUid ?? 0,
          ),
          placeholder: '${remote.displayName} 的画面还没出来',
          label: remote.displayName,
        );
      } else {
        stage = RemoteView(
          key: ValueKey('cf-stage-$stageEpoch-${remote.uid}'),
          renderer: controller.rendererFor(remote.uid, 'screen'),
          placeholder: '${remote.displayName} 的画面还没出来',
          label: remote.displayName,
          live: true,
        );
      }
    } else if (showLocal) {
      stage = RemoteView(
        renderer: controller.localRenderer,
        placeholder: '正在准备画面…',
        highlighted: true,
        label: '我的画面',
        sublabel: '朋友正在看你的屏幕',
      );
    } else {
      stage = _WaitingStage(isHost: controller.isHost);
    }

    final horizontal = MediaQuery.sizeOf(context).width >= 920 ? 16.0 : 12.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        AppSpacing.x1,
        horizontal,
        AppSpacing.x1,
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                stage,
                // 弹幕浮在画面上，不吃指针事件，也不影响底下的切换条。
                IgnorePointer(child: DanmakuLayer(controller: controller)),
                // 观众端的舞台控制：全屏 + 音量。只在有远端画面时出现；
                // 主持人看自己的预览时不需要（共享源自己就有声音控制）。
                if (remote != null)
                  _StageControls(controller: controller, uid: remote.uid),
              ],
            ),
          ),
          if (entries.length > 1) ...[
            const SizedBox(height: AppSpacing.x1),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.x1),
                itemBuilder: (context, i) {
                  final e = entries[i];
                  return _StageChip(
                    entry: e,
                    active: activeUid == e.uid,
                    onTap: () => onSelect(e.uid),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 舞台右下角的观众控制：全屏 + 音量。
///
/// 只在观众看远端画面时出现（[_StageArea] 控制）。全屏走控制器的
/// 沉浸式 + 横屏逻辑；音量弹出观众面板（观看音量）。
class _StageControls extends StatelessWidget {
  const _StageControls({required this.controller, required this.uid});

  final ScreenShareController controller;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: AppSpacing.x2,
      bottom: AppSpacing.x2,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final fullscreen = controller.fullscreen;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StageControlButton(
                icon: AppIcons.volume,
                label: '音量',
                onTap: () => showCitroSheet<void>(
                  context: context,
                  backgroundColor: shareColors.surface,
                  builder: (_) => ShareTheme(
                    child: _ViewerVolumeSheet(controller: controller),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.x1),
              _StageControlButton(
                icon: fullscreen ? AppIcons.restore : AppIcons.maximize,
                label: fullscreen ? '退出全屏' : '全屏',
                onTap: () => controller.toggleFullscreen(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 舞台控制按钮：半透明圆角底 + 图标 + 小字。
class _StageControlButton extends StatelessWidget {
  const _StageControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x9B000000),
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: context.body(
                size: CitroType.micro,
                weight: CitroType.medium,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 观众音量面板：观看音量（远端 system 等全部远端音轨）。
class _ViewerVolumeSheet extends StatelessWidget {
  const _ViewerVolumeSheet({required this.controller});

  final ScreenShareController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '音量',
                    style: context.heading(
                      size: CitroType.subtitle,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  _VolumeRow(
                    icon: AppIcons.volume,
                    label: '观看音量',
                    hint: '共享画面里的声音大小',
                    value: controller.viewerVolume,
                    enabled: true,
                    onChanged: controller.setViewerVolume,
                    onCommit: controller.commitViewerVolume,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 切换条里的一项。uid 是自己时走 `我的画面`。
class _StageEntry {
  const _StageEntry({
    required this.uid,
    required this.name,
    this.isSelf = false,
    this.hasMic = false,
  });

  final String uid;
  final String name;
  final bool isSelf;
  final bool hasMic;
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    required this.entry,
    required this.active,
    required this.onTap,
  });

  final _StageEntry entry;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: 1,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.accentLt : c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: active ? c.accent : c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              entry.isSelf ? AppIcons.monitor : AppIcons.wave,
              size: 13,
              color: active ? c.accentInk : c.inkSoft,
            ),
            if (entry.hasMic) ...[
              const SizedBox(width: 5),
              AppIcon(
                AppIcons.mic,
                size: 12,
                color: active ? c.accentInk : c.mint,
              ),
            ],
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(
                  size: CitroType.meta,
                  weight: active ? CitroType.medium : CitroType.regular,
                  color: active ? c.accentInk : c.ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingStage extends StatelessWidget {
  const _WaitingStage({required this.isHost});

  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
        border: Border.all(color: c.line),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo.webp',
                width: 66,
                height: 66,
                cacheWidth: 160,
                opacity: const AlwaysStoppedAnimation<double>(.92),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                isHost ? '还没有开始一起看' : '等待主持人开始一起看',
                textAlign: TextAlign.center,
                style: context.heading(size: CitroType.title, color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                isHost ? '点下面的「一起看」，朋友就能看到你的屏幕' : '画面开始后会出现在这里',
                textAlign: TextAlign.center,
                style: context.body(size: CitroType.meta, color: c.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 底部悬浮控制条 ──────────────────────────────────────────────────────

class _Dock extends StatelessWidget {
  const _Dock({
    required this.controller,
    required this.wide,
    required this.onToggleShare,
    required this.onToggleMic,
    required this.onChat,
    required this.onMembers,
    required this.onSettings,
  });

  final ScreenShareController controller;
  final bool wide;
  final VoidCallback onToggleShare;
  final VoidCallback onToggleMic;
  final VoidCallback onChat;
  final VoidCallback onMembers;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final publishing = controller.publishing;
    final showSettings = controller.isHost || controller.publishing;
    final items = <Widget>[
      // 服务端只允许主持人发布画面，观众端不摆一个按了会被拒的按钮。
      if (controller.isHost || publishing)
        _DockItem(
          icon: publishing ? AppIcons.close : AppIcons.monitor,
          label: publishing ? '停止' : '一起看',
          tone: publishing ? _DockTone.danger : _DockTone.accent,
          busy: controller.busy,
          onTap: ScreenShareController.canPublish ? onToggleShare : null,
        ),
      // 主持人专属麦键：观众纯文字（isHost 门禁），开麦态用 accent 底色
      // 强调、闭麦态回中性。仅声网连上才可点。
      if (controller.isHost && controller.agoraConnected)
        _DockItem(
          icon: AppIcons.mic,
          label: controller.micOn ? '闭麦' : '开麦',
          tone: controller.micOn ? _DockTone.accent : _DockTone.normal,
          busy: controller.micBusy,
          onTap: onToggleMic,
        ),
      _DockItem(icon: AppIcons.comment, label: '聊天', onTap: onChat),
      _DockItem(icon: AppIcons.users, label: '成员', onTap: onMembers),
      if (showSettings)
        _DockItem(icon: AppIcons.settings, label: '设置', onTap: onSettings),
    ];
    final dock = Container(
      constraints: BoxConstraints(maxWidth: wide ? 560 : double.infinity),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.page),
        border: Border.all(color: c.line),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: .45),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(children: [for (final item in items) Expanded(child: item)]),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        4,
        AppSpacing.x2,
        AppSpacing.x2,
      ),
      child: Center(child: dock),
    );
  }
}

enum _DockTone { normal, accent, danger }

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone = _DockTone.normal,
    this.busy = false,
  });

  final String icon;
  final String label;
  final VoidCallback? onTap;
  final _DockTone tone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final disabled = onTap == null || busy;
    final (bg, border, fg) = switch (tone) {
      _DockTone.accent => (c.accent, c.accent, c.onAccent),
      _DockTone.danger => (
        c.dangerSoft,
        c.danger.withValues(alpha: .45),
        c.danger,
      ),
      _DockTone.normal => (c.surface2, c.line, c.ink2),
    };
    return Pressable(
      onTap: disabled ? null : onTap,
      scale: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: disabled ? bg.withValues(alpha: .6) : bg,
              shape: BoxShape.circle,
              border: Border.all(color: border),
            ),
            child: busy
                ? SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : AppIcon(
                    strokeSvg(icon, width: 2),
                    size: 19,
                    color: disabled ? fg.withValues(alpha: .55) : fg,
                  ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.body(
              size: CitroType.micro + 1,
              weight: CitroType.medium,
              color: disabled ? c.inkSoft.withValues(alpha: .6) : c.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 宽屏右栏：房间信息 + 画质 + 成员 ────────────────────────────────────

class _SideRail extends StatelessWidget {
  const _SideRail({required this.controller, required this.onMembers});

  final ScreenShareController controller;
  final VoidCallback onMembers;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final room = controller.room;
    final members = controller.members.where((m) => m.online).toList()
      ..sort((a, b) {
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        return a.displayName.compareTo(b.displayName);
      });
    // 悬浮的圆角面板，不再是一条贴边的满高栏。
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        0,
        AppSpacing.x1,
        AppSpacing.x1,
        AppSpacing.x1,
      ),
      child: Container(
        width: 300,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CitroColors.radii.card),
          border: Border.all(color: c.line),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            18,
            AppSpacing.x2,
            18,
            AppSpacing.x2,
          ),
          children: [
            Text(
              '房间号',
              style: context.body(size: CitroType.caption, color: c.inkSoft),
            ),
            const SizedBox(height: 2),
            Text(
              room?.roomCode ?? '------',
              style: context.display(
                size: CitroType.heading,
                color: c.ink,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.x1),
            CitroButton(
              label: '复制邀请链接',
              icon: const AppIcon(AppIcons.arrowUpRight, size: 17),
              style: CitroButtonStyle.outline,
              expanded: true,
              onPressed: room == null
                  ? null
                  : () => copyText(
                      room.inviteLink,
                      context: context,
                      tip: '邀请链接已复制',
                    ),
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              '朋友没装 App？浏览器打开链接也能看。',
              style: context.body(size: CitroType.caption, color: c.inkSoft),
            ),
            const SizedBox(height: AppSpacing.x2),
            Divider(color: c.line),
            const SizedBox(height: AppSpacing.x2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '在线成员',
                    style: context.heading(
                      size: CitroType.bodyLg,
                      color: c.ink,
                    ),
                  ),
                ),
                Text(
                  '${members.length}',
                  style: context.hand(size: CitroType.label, color: c.inkSoft),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x1),
            for (final m in members.take(8))
              _RailMember(member: m, controller: controller),
            if (members.length > 8)
              TextButton(
                onPressed: onMembers,
                child: Text(
                  '查看全部 ${members.length} 人',
                  style: context.body(size: CitroType.meta, color: c.accentInk),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailMember extends StatelessWidget {
  const _RailMember({required this.member, required this.controller});

  final RoomMember member;
  final ScreenShareController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final name = member.displayName;
    // 主持人的麦状态跟控制器走（声网发布链不进 WS 轨道列表，
    // member.hasMic 只反映旧版客户端的 SFU mic 轨）。
    final hasMic = member.self ? controller.micOn : member.hasMic;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          CitroAvatar(
            text: name.isEmpty ? '?' : name.characters.first,
            size: 32,
          ),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.self ? '$name（我）' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: CitroType.label, color: c.ink),
                ),
                Text(
                  member.hasScreen ? '正在一起看' : (hasMic ? '开着麦' : '在线'),
                  style: context.body(
                    size: CitroType.caption,
                    color: c.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          if (member.isHost) _RailBadge(text: '主持', mint: true),
          if (member.hasScreen) _RailBadge(text: '放映'),
          if (hasMic) ...[
            const SizedBox(width: 4),
            AppIcon(AppIcons.mic, size: 12, color: c.mint),
          ],
        ],
      ),
    );
  }
}

class _RailBadge extends StatelessWidget {
  const _RailBadge({required this.text, this.mint = false});

  final String text;
  final bool mint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: mint ? c.mintSoft : c.accentLt,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(
          color: mint ? c.mintLine : c.accent.withValues(alpha: .3),
        ),
      ),
      child: Text(
        text,
        style: context.body(
          size: CitroType.micro,
          weight: CitroType.medium,
          color: mint ? c.mintInk : c.accentInk,
        ),
      ),
    );
  }
}

// ── 设置弹层 ────────────────────────────────────────────────────────────

/// 音量区：观众是「观看音量」（远端全部音轨），主持人是「系统音量」
/// （共享内容里的声音）。
///
/// 设置弹层本身是 Stateless 的，控制器变化不会重建它；这里单独监听
/// 控制器，拖动滑杆时数字和轨道能实时跟手。
class _VolumeSection extends StatelessWidget {
  const _VolumeSection({required this.controller});

  final ScreenShareController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = context.c;
        final system = controller.hasSystemAudio;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '音量',
              style: context.body(size: CitroType.meta, color: c.inkSoft),
            ),
            const SizedBox(height: 2),
            // 观众（没在共享）的滑杆：控制听到的远端音量。
            if (!controller.publishing) ...[
              _VolumeRow(
                icon: AppIcons.volume,
                label: '观看音量',
                hint: controller.remotePublishers.isNotEmpty
                    ? '共享画面里的声音大小'
                    : '有人开始共享后可调',
                value: controller.viewerVolume,
                enabled: controller.remotePublishers.isNotEmpty,
                onChanged: controller.setViewerVolume,
                onCommit: controller.commitViewerVolume,
              ),
            ] else ...[
              _VolumeRow(
                icon: AppIcons.volume,
                label: '系统音量',
                hint: system
                    ? '共享画面里的声音大小'
                    : (controller.publishing ? '这段共享没有系统声音' : '开始一起看后可调'),
                value: controller.systemVolume,
                enabled: system,
                onChanged: controller.setSystemVolume,
                onCommit: controller.commitSystemVolume,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onCommit,
  });

  final String icon;
  final String label;
  final String hint;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final Future<void> Function() onCommit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(
                icon,
                size: 15,
                color: enabled ? c.ink2 : c.inkSoft.withValues(alpha: .5),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.body(
                  size: CitroType.body,
                  color: enabled ? c.ink : c.inkSoft,
                ),
              ),
              const Spacer(),
              Text(
                '${(value * 100).round()}%',
                style: context.hand(
                  size: CitroType.meta,
                  color: enabled ? c.accentInk : c.inkSoft,
                ),
              ),
            ],
          ),
          Text(
            hint,
            style: context.body(size: CitroType.caption, color: c.inkSoft),
          ),
          SizedBox(
            height: 32,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: c.accent,
                inactiveTrackColor: c.surface2,
                thumbColor: c.accent,
                disabledActiveTrackColor: c.line2,
                disabledInactiveTrackColor: c.surface2,
                disabledThumbColor: c.inkSoft.withValues(alpha: .4),
                overlayColor: c.accent.withValues(alpha: .14),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: value,
                onChanged: enabled ? onChanged : null,
                onChangeEnd: enabled ? (_) => onCommit() : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.controller});

  final ScreenShareController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '一起看设置',
                style: context.heading(size: CitroType.subtitle, color: c.ink),
              ),
              const SizedBox(height: AppSpacing.x2),
              if (controller.isHost) ...[
                Text(
                  '画质',
                  style: context.body(size: CitroType.meta, color: c.inkSoft),
                ),
                const SizedBox(height: 6),
                ShareQualityPicker(
                  value: controller.quality,
                  onChanged: controller.setQuality,
                  label: '目标画质',
                ),
                const SizedBox(height: AppSpacing.x2),
              ],
              Text(
                '共享内容',
                style: context.body(size: CitroType.meta, color: c.inkSoft),
              ),
              const SizedBox(height: 4),
              Text(
                controller.canPickSource
                    ? '开始一起看时可以选整块屏幕，或只共享一个应用窗口。'
                    : '手机上开始一起看时会走系统授权，整块屏幕共享。',
                style: context.body(size: CitroType.caption, color: c.ink2),
              ),
              const SizedBox(height: AppSpacing.x2),
              _VolumeSection(controller: controller),
              if (controller.publishing) ...[
                const SizedBox(height: AppSpacing.x2),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '小窗预览',
                            style: context.body(
                              size: CitroType.body,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            '把画面缩成小窗，边看边做别的事',
                            style: context.body(
                              size: CitroType.caption,
                              color: c.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: controller.miniWindow,
                      onChanged: (_) => controller.toggleMiniWindow(),
                      activeThumbColor: c.onAccent,
                      activeTrackColor: c.accent,
                      inactiveThumbColor: c.inkSoft,
                      inactiveTrackColor: c.surface2,
                    ),
                  ],
                ),
              ],
              // 弹幕悬浮窗只有 Android / Windows 有（iOS 系统不允许悬浮
              // 于其他应用之上，Web 走页面内弹幕层），开关只在这两端给
              // 主持人看。开关是全局静态态， onChanged 里 setState 让本行
              // 即时刷新，同时 notifyListeners 同步房间页其他监听者。
              if (controller.isHost && DanmakuBridge.isSupported)
                _DanmakuRow(controller: controller),
              const SizedBox(height: AppSpacing.x2),
              Divider(color: c.line),
              const SizedBox(height: AppSpacing.x2),
              Text(
                '邀请朋友',
                style: context.body(size: CitroType.meta, color: c.inkSoft),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: CitroButton(
                      label: '复制房间号',
                      icon: const AppIcon(AppIcons.copy, size: 16),
                      style: CitroButtonStyle.outline,
                      onPressed: controller.room == null
                          ? null
                          : () => copyText(
                              controller.room!.roomCode,
                              context: context,
                              tip: '房间号已复制',
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x1),
                  Expanded(
                    child: CitroButton(
                      label: '复制邀请链接',
                      icon: const AppIcon(AppIcons.arrowUpRight, size: 16),
                      style: CitroButtonStyle.outline,
                      onPressed: controller.room == null
                          ? null
                          : () => copyText(
                              controller.room!.inviteLink,
                              context: context,
                              tip: '邀请链接已复制',
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x3),
              CitroButton(
                label: '完成',
                style: CitroButtonStyle.accent,
                expanded: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「观众弹幕」开关行：把观众的聊天变成悬浮窗弹幕，滚在主持人的
/// 屏幕画面上（App 被最小化也在滚，MediaProjection 才能把它采进流）。
///
/// 弹幕开关是全局静态态（[DanmakuBridge.enabled]），行内 setState 只管
/// 本行刷新，再 notifyListeners 让房间页同一帧同步；开关关掉时悬浮窗
/// 直接收起，打开则尝试重新拉起（Android 缺悬浮窗权限时只给提示，
/// 不擅自跳系统设置页打断设置流程）。
class _DanmakuRow extends StatefulWidget {
  const _DanmakuRow({required this.controller});

  final ScreenShareController controller;

  @override
  State<_DanmakuRow> createState() => _DanmakuRowState();
}

class _DanmakuRowState extends State<_DanmakuRow> {
  bool _canShow = true;

  @override
  void initState() {
    super.initState();
    // Android 未必已授予「显示在其他应用上层」权限；先查一次，缺权限
    // 时在开关旁给一行小字提示。结果异步回来只影响提示文案。
    DanmakuBridge.canShow().then((ok) {
      if (mounted) setState(() => _canShow = ok);
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => DanmakuBridge.enabled = value);
    // 弹幕开关是全局态，控制器不持有它；手动广播一次，让监听控制器的
    // 界面（舞台弹幕层等）同一帧跟着刷新。这是本页持有控制的刻意调用，
    // 屏蔽 protected / for-testing 两条 lint。
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    widget.controller.notifyListeners();
    if (value) {
      final ok = await DanmakuBridge.canShow();
      if (ok) {
        await DanmakuBridge.show();
        if (mounted) setState(() => _canShow = true);
      } else {
        // 不弹系统设置页打断设置流程，只在开关旁给小字提示。
        if (mounted) setState(() => _canShow = false);
      }
    } else {
      await DanmakuBridge.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '观众弹幕',
                  style: context.body(size: CitroType.body, color: c.ink),
                ),
                Text(
                  '观众的聊天变成弹幕滚在画面上',
                  style: context.body(
                    size: CitroType.caption,
                    color: c.inkSoft,
                  ),
                ),
                if (!_canShow)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '需授予悬浮窗权限',
                      style: context.body(
                        size: CitroType.caption,
                        color: c.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: DanmakuBridge.enabled,
            onChanged: (v) => unawaited(_toggle(v)),
            activeThumbColor: c.onAccent,
            activeTrackColor: c.accent,
            inactiveThumbColor: c.inkSoft,
            inactiveTrackColor: c.surface2,
          ),
        ],
      ),
    );
  }
}

// ── 整页全屏放映 ─────────────────────────────────────────────────────────

/// 全屏放映路由：从下往上滑入，黑色背景，页面本身就是「放映」。
///
/// 和房间页里那种「藏了系统栏但顶栏 / Dock 还在」的假全屏不同，
/// 这一条路由只渲染远端画面 + 弹幕 + 悬浮控制，没有任何 SafeArea /
/// Scaffold 装饰，连手势条区域都盖住 —— 真正一屏全是画面。
class FullscreenStageRoute extends PageRouteBuilder<void> {
  FullscreenStageRoute({required ScreenShareController controller})
    : super(
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => _FullscreenStagePage(controller: controller),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );
}

class _FullscreenStagePage extends StatelessWidget {
  const _FullscreenStagePage({required this.controller});

  final ScreenShareController controller;

  @override
  Widget build(BuildContext context) {
    // PopScope：系统返回手势走控制器的退出路径，让系统栏 / 方向一并恢复，
    // 标记和路由不失步。
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        controller.exitFullscreen();
      },
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final publishers = controller.remotePublishers;
          final selfUid = controller.selfUid;
          final selectedRemote = publishers.isNotEmpty
              ? publishers.first
              : null;
          final showSelf =
              controller.publishing &&
              selfUid != null &&
              selectedRemote == null;

          final Widget stage;
          if (selectedRemote != null) {
            // 与房间页舞台共用同一判定（useAgoraRemoteRender）：全屏 ↔
            // 房间切换时两处同帧同结果，渲染器不切换、画面不闪黑。
            if (controller.useAgoraRemoteRender) {
              stage = _AgoraRemoteView(
                key: ValueKey('agora-stage-${controller.agoraRemoteUid}'),
                uid: controller.agoraRemoteUid!,
                connection: RtcConnection(
                  channelId: controller.roomId,
                  localUid: controller.agoraSelfUid ?? 0,
                ),
                placeholder: '${selectedRemote.displayName} 的画面还没出来',
                label: selectedRemote.displayName,
              );
            } else {
              stage = _FullscreenVideo(
                renderer: controller.rendererFor(selectedRemote.uid, 'screen'),
                placeholder: '${selectedRemote.displayName} 的画面还没出来',
                label: selectedRemote.displayName,
              );
            }
          } else if (showSelf) {
            stage = _FullscreenVideo(
              renderer: controller.localRenderer,
              placeholder: '正在准备画面…',
              label: '我的画面',
            );
          } else {
            stage = _FullscreenVideo(
              renderer: null,
              placeholder: '当前没有正在放映的画面',
              label: null,
            );
          }

          return Scaffold(
            // 纯黑背景：放映时黑边也是黑的，不是页面底色。
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                stage,
                IgnorePointer(child: DanmakuLayer(controller: controller)),
                if (selectedRemote != null)
                  _StageControls(
                    controller: controller,
                    uid: selectedRemote.uid,
                  ),
                // 左下角：聊天 —— 放映时不动手掌位置就能说一句
                // （右下角已有音量 / 全屏）。
                Positioned(
                  left: AppSpacing.x2,
                  bottom: AppSpacing.x2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StageControlButton(
                        icon: AppIcons.comment,
                        label: '聊天',
                        onTap: () => showChatPanel(context, controller),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 全屏页里的画面：铺满 + contain（屏幕内容会被裁掉，放映必须 contain）。
class _FullscreenVideo extends StatelessWidget {
  const _FullscreenVideo({
    required this.renderer,
    required this.placeholder,
    required this.label,
  });

  final RTCVideoRenderer? renderer;
  final String placeholder;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final r = renderer;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (r != null)
          RTCVideoView(
            r,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            placeholderBuilder: (_) => Center(
              child: Text(
                placeholder,
                textAlign: TextAlign.center,
                style: context.body(
                  size: CitroType.meta,
                  color: Colors.white60,
                ),
              ),
            ),
          )
        else
          Center(
            child: Text(
              placeholder,
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: Colors.white60),
            ),
          ),
        if (label != null)
          Positioned(
            left: AppSpacing.x3,
            top: AppSpacing.x3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x9B000000),
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              ),
              child: Text(
                label!,
                style: context.body(
                  size: CitroType.meta,
                  weight: CitroType.medium,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 声网链路的远端画面：原生渲染，走 Agora 的渲染通道。
///
/// 和 [RemoteView]（RTCVideoRenderer）并存：控制器的 `agoraRemoteUid`
/// 非 null 且链路已连接时舞台用它。控制器 builder 已监听控制器变化，
/// Agora 状态翻转（connected / uid 变化）时舞台会自动切到这或切回去。
class _AgoraRemoteView extends StatelessWidget {
  const _AgoraRemoteView({
    super.key,
    required this.uid,
    required this.connection,
    required this.placeholder,
    required this.label,
  });

  final int uid;
  final RtcConnection connection;
  final String placeholder;
  final String label;

  @override
  Widget build(BuildContext context) {
    final engine = createAgoraRtcEngine();
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: engine,
              canvas: VideoCanvas(
                uid: uid,
                renderMode: RenderModeType.renderModeFit,
              ),
              connection: connection,
            ),
          ),
          // 首帧加载动画：声网 Texture 首帧前是纯黑，盖一层呼吸圆点。
          // 首帧渲染出来后原生 Texture 会盖不住它 —— 所以动画层自己
          // 3 秒后淡出（正常网络 1-2 秒内必然已出画面）。
          const Positioned.fill(
            child: _AgoraLoadingVeil(),
          ),
          Positioned(
            left: AppSpacing.x2,
            top: AppSpacing.x2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x9B000000),
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
              ),
              child: Text(
                label,
                style: context.body(
                  size: CitroType.meta,
                  weight: CitroType.medium,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 声网舞台的首帧加载幕：呼吸圆点 + 文案，3 秒后自动淡出。
/// 不能等「首帧事件」再拆（事件在 controller 层，这里拿不到），
/// 固定时长是可接受的近似 —— 画面出来后被拆掉的只是已经淡出的空层。
class _AgoraLoadingVeil extends StatefulWidget {
  const _AgoraLoadingVeil();

  @override
  State<_AgoraLoadingVeil> createState() => _AgoraLoadingVeilState();
}

class _AgoraLoadingVeilState extends State<_AgoraLoadingVeil> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 450),
      child: IgnorePointer(
        child: Container(
          color: const Color(0x8A17120F),
          alignment: Alignment.center,
          child: _visible
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _StageLoadingDots(),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      '正在加载画面…',
                      style: context.body(
                        size: CitroType.meta,
                        color: c.inkSoft,
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// 呼吸圆点（舞台版）：与 widgets/remote_view.dart 的 _LoadingDots
/// 同视觉参数（9px、accent、1150ms、0.16s 相位差），此处独立实现
/// 避免把房间页对 widgets 的依赖再拉高一层。
class _StageLoadingDots extends StatefulWidget {
  const _StageLoadingDots();

  @override
  State<_StageLoadingDots> createState() => _StageLoadingDotsState();
}

class _StageLoadingDotsState extends State<_StageLoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget dot(int i) {
      final t = Curves.easeInOut.transform(
        ((_c.value - i * 0.16) % 1.0).abs() * 2,
      );
      final lift = (1.0 - t).clamp(0.0, 1.0);
      return Opacity(
        opacity: 0.45 + 0.55 * lift,
        child: Transform.translate(
          offset: Offset(0, -7 * lift),
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: c.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.5),
            child: dot(i),
          ),
      ],
    );
  }
}
