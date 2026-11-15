import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/puns.dart';
import '../services/api.dart';
import '../services/clipboard_image.dart';
import '../services/prefs.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/paper.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({super.key});
  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayRecord {
  final String text;
  final int ts;
  final String name;
  final bool you;
  const _PlayRecord(this.text, this.ts, {this.name = '', this.you = false});
}

/// 一次 POST /api/play 的结果：正常返回、冷却、错误三选一。
class _DrawOutcome {
  final Map<String, dynamic>? remote;
  final int coolingMs;
  final String? error;
  const _DrawOutcome({this.remote, this.coolingMs = 0, this.error});
}

class _PlayPageState extends State<PlayPage> {
  final math.Random rnd = math.Random();
  final stageKey = GlobalKey();
  String stageText = '点击「开始抽取」，命运交给橘子';
  String? lastPun;
  bool rolling = false;
  bool _cancelRoll = false;
  int cooldownUntil = 0;

  /// 最近一次由云端 POST 确认的本人记录。
  ///
  /// 页面打开时可能还挂着一次更早的 GET，它返回的列表可能还没包含刚抽到
  /// 的签；用这条记录在短时间内补位，避免「抽了没计入」。
  _PlayRecord? _lastConfirmed;
  List<_PlayRecord> remote = [];
  bool remoteLoading = true;
  bool remoteBusy = false;
  String? remoteError;
  Timer? _cdTimer;
  Timer? _pollTimer;

  /// 云端列表的版本号：POST 返回的全站快照比在途的旧 GET 新。
  /// GET 出发时记下版本，回来发现变过就丢弃，避免旧快照把刚抽到的签
  /// 从「大家的抽签」里覆盖掉。
  int _remoteVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshRemote();
    // 别人的抽签要能看到：页面停留期间每 10 秒静默拉一次全站列表。
    // 服务端 GET 限流 60 次/分钟，10 秒一次远低于阈值。
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || rolling || remoteBusy) return;
      // 切到别的 Tab 后页面仍挂在 IndexedStack 里，但 TickerMode 会被
      // RootShell 关掉：不可见时不再发请求，省流量也省服务端配额。
      if (!TickerMode.getValuesNotifier(context).value.enabled) return;
      unawaited(_refreshRemote(silent: true));
    });
    _cdTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // 归零的那一秒也要刷一次，否则按钮会永远停在「0:01」。
      if (!mounted) return;
      if (remaining > 0) {
        setState(() {});
      } else if (cooldownUntil != 0) {
        cooldownUntil = 0;
        setState(() {});
        _cdTimer?.cancel();
        _cdTimer = null;
        if (!kIsWeb) HapticFeedback.selectionClick();
      }
    });
  }

  @override
  void dispose() {
    _cdTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _load() {
    cooldownUntil = Prefs.getInt(PrefKeys.playCooldown);
    if (mounted) setState(() {});
  }

  List<_PlayRecord> _parseRemote(dynamic raw) {
    return ((raw as List?) ?? const [])
        .whereType<Map>()
        .map(
          (e) => _PlayRecord(
            '${e['t'] ?? ''}'.trim(),
            int.tryParse('${e['ts']}') ?? 0,
            name: '${e['name'] ?? '游客'}',
            you: e['you'] == true,
          ),
        )
        .where((e) => e.text.isNotEmpty)
        .toList();
  }

  /// 两分钟内刚由云端确认的签：用于抵挡晚到的旧 GET 快照。
  _PlayRecord? _recentConfirmed() {
    final rec = _lastConfirmed;
    if (rec == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - rec.ts < 120000 ? rec : null;
  }

  void _applyRemote(Map<String, dynamic> j, {_PlayRecord? pending}) {
    final list = _parseRemote(j['records']);
    // 列表里连不上那张刚抽到的签时（服务端写入与这次返回之间有极短的
    // 时间差），只补这一条刚由云端确认的签；不会再把本地兜底生成的
    // 记录混进「大家的抽签」。
    final carry = pending ?? _recentConfirmed();
    if (carry != null) {
      if (!list.any((r) => r.text == carry.text && r.ts == carry.ts)) {
        list.insert(0, carry);
      }
    }
    final cd = int.tryParse('${j['cd'] ?? 0}') ?? 0;
    // 只许延长、不许缩短：页面打开时可能还挂着一次更早的 GET /api/play，
    // 它带回来的 cd 是旧快照（甚至 0），直接覆盖会把刚设好的冷却清掉，
    // 用户接着点就吃 429 —— 这正是「抽了没计入」的来源之一。
    final until = DateTime.now().millisecondsSinceEpoch + cd;
    if (until > cooldownUntil) {
      cooldownUntil = until;
      Prefs.setInt(PrefKeys.playCooldown, cooldownUntil);
    }
    if (mounted) {
      setState(() {
        remote = list;
        remoteError = null;
        remoteLoading = false;
      });
    }
  }

  Future<void> _refreshRemote({bool silent = false}) async {
    if (remoteBusy) return;
    remoteBusy = true;
    final version = _remoteVersion;
    if (!silent && mounted) {
      setState(() {
        remoteLoading = true;
        remoteError = null;
      });
    }
    try {
      final j = await Api.playRecords(deviceId: AppState.instance.gid);
      if (!mounted) return;
      // 这段时间里 POST 已经返回更新的全站快照：旧 GET 丢弃。
      if (version != _remoteVersion) {
        if (mounted && !silent) setState(() => remoteLoading = false);
        return;
      }
      _applyRemote(j);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        remoteError = '$e';
        remoteLoading = false;
      });
    } finally {
      remoteBusy = false;
    }
  }

  int get remaining =>
      math.max(0, cooldownUntil - DateTime.now().millisecondsSinceEpoch);

  /// 把这一次抽签立刻发给服务端，结果（或错误）包装成 [_DrawOutcome]。
  ///
  /// 所有异常都在这里吃掉：调用方在揭开动画之后统一 await，不需要
  /// 再区分「POST 失败」和「页面已退出」。
  Future<_DrawOutcome> _postDraw(AppState state) async {
    try {
      final remote = await Api.playDraw(
        deviceId: state.gid,
        name: state.loggedIn ? null : state.guestName,
      );
      return _DrawOutcome(remote: remote);
    } on ApiException catch (e) {
      if (e.code == 429) {
        // 429 有两种：冷却（body 带 cd / records）和限流（只有 err）。
        // 只有真冷却才进冷却分支，限流按普通错误提示，别把按钮锁住。
        final cd = int.tryParse('${e.body?['cd'] ?? 0}') ?? 0;
        if (cd > 0 || e.body?['records'] != null) {
          return _DrawOutcome(coolingMs: cd);
        }
        return _DrawOutcome(
          error: e.message.isEmpty ? '操作太频繁，稍后再试' : e.message,
        );
      }
      return _DrawOutcome(error: e.message);
    } catch (e) {
      return _DrawOutcome(error: '$e');
    }
  }

  Future<void> _draw() async {
    if (rolling) {
      // 再点一次只是提前结束揭晓动画；POST 已经在路上，抽签不会丢。
      _cancelRoll = true;
      return;
    }
    if (remaining > 0) return;
    _cancelRoll = false;
    setState(() {
      rolling = true;
      stageText = '正在抽取…';
    });
    final state = AppState.instance;
    // 关键顺序：先上传、再播动画。以前是动画跑完 1.6 秒才 POST，
    // 中途退出 / 切后台 / 动画取消都会让这次抽签根本没发出去，
    // 服务端没记录，界面自然「不计入」。现在点击那一刻就已落库，
    // 动画只负责揭晓服务端给出的签。
    final pending = _postDraw(state);
    var settled = false;
    unawaited(pending.whenComplete(() => settled = true));

    final seq = List.generate(16, (_) => kPuns[rnd.nextInt(kPuns.length)]);
    for (var i = 0; i < seq.length; i++) {
      if (!mounted || _cancelRoll) break;
      setState(() => stageText = seq[i]);
      await Future<void>.delayed(Duration(milliseconds: 55 + i * 6));
    }
    if (!mounted) return;
    if (!settled) {
      // 动画放完了结果还没回来，或者用户按了停止：别把最后一帧的
      // 随机签当成抽到的签，明确显示正在写入服务端。
      setState(() => stageText = '正在记录这次抽签…');
    }

    final out = await pending;
    if (!mounted) return; // 服务端已经记下了，页面不在也不影响记录
    if (out.coolingMs > 0) {
      // 服务端这次没发签：本地不落账，否则和全站列表对不上。
      cooldownUntil = DateTime.now().millisecondsSinceEpoch + out.coolingMs;
      await Prefs.setInt(PrefKeys.playCooldown, cooldownUntil);
      if (!mounted) return;
      setState(() {
        rolling = false;
        stageText = '服务器还在冷却，剩余 ${_fmtCd(out.coolingMs)}';
      });
      await _refreshRemote(silent: true);
      if (mounted) AppToast.show(context, '服务器还在冷却，稍后再抽');
      return;
    }
    // 强制云端抽签：服务端没有返回签面就当作失败，不再用本地签池兜底。
    // 本地兜底会让签面出现一条「大家的抽签」里没有的签，对不上，
    // 正是「抽了没计入」的来源。
    final text = '${out.remote?['t'] ?? ''}'.trim();
    if (text.isEmpty) {
      final msg = (out.error == null || out.error!.isEmpty)
          ? '云端抽签失败，请稍后重试'
          : out.error!;
      setState(() {
        rolling = false;
        stageText = '抽签失败，请联网后重试';
        remoteError = msg;
      });
      AppToast.show(context, msg);
      unawaited(_refreshRemote(silent: true));
      return;
    }
    final ts =
        int.tryParse('${out.remote!['ts']}') ??
        DateTime.now().millisecondsSinceEpoch;
    final rec = _PlayRecord(text, ts, name: state.displayName, you: true);
    _lastConfirmed = rec;
    _remoteVersion++;
    setState(() {
      lastPun = text;
      stageText = text;
      rolling = false;
      remoteError = null;
    });
    // POST 已返回最新全站列表：用同一份数据刷新「大家的抽签」，
    // 保证刚抽到的签马上出现。
    _applyRemote(out.remote!, pending: rec);
  }

  /// 刷新云端记录：「大家的抽签」只认云端，本地不再留存。
  void _refresh() {
    unawaited(_refreshRemote());
    if (mounted) AppToast.show(context, '正在刷新云端抽签记录');
  }

  Future<void> _shareShot() async {
    try {
      final boundary =
          stageKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final bytes = data.buffer.asUint8List();
      if (kIsWeb && await copyImageToClipboard(bytes)) {
        if (mounted) AppToast.show(context, '截图已复制到剪贴板');
        return;
      }
      final file = XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: 'citro_play_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await Share.shareXFiles([file], text: 'Citro · 玩法抽签');
    } catch (e) {
      if (mounted) AppToast.show(context, '截图失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final left = remaining;
    return Scaffold(
      body: CitroBackground(
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 64, 18, 30),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '无畏契约 · 玩法抽签',
                          textAlign: TextAlign.center,
                          style: context.display(
                            size: 30,
                            weight: CitroType.strong,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '不知道这局怎么玩？抽一个，整活正式开始。',
                          textAlign: TextAlign.center,
                          style: context.body(
                            size: CitroType.meta,
                            color: c.inkSoft,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x3),
                        RepaintBoundary(
                          key: stageKey,
                          child: CitroCard(
                            padding: const EdgeInsets.all(24),
                            child: SizedBox(
                              height: 180,
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 160),
                                  child: Text(
                                    stageText,
                                    key: ValueKey(stageText),
                                    textAlign: TextAlign.center,
                                    // 签面长度差得很多（最短 5 字，最长快 60 字），
                                    // 两档字号兜不住：长签在手机上有溢出卡片的风险。
                                    style: context.display(
                                      size: _stageSize(stageText.length),
                                      weight: CitroType.strong,
                                      color: rolling ? c.inkSoft : c.ink,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        Row(
                          children: [
                            Expanded(
                              child: CitroButton(
                                label: rolling
                                    ? '停止抽取'
                                    : (left > 0
                                          ? '冷却中 ${_fmtCd(left)}'
                                          : '开始抽取'),
                                style: left > 0
                                    ? CitroButtonStyle.surface
                                    : CitroButtonStyle.accent,
                                expanded: true,
                                onPressed: _draw,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x1),
                            _ghostButton(
                              c,
                              kIsWeb ? '复制截图' : '分享截图',
                              AppIcons.image,
                              _shareShot,
                            ),
                            const SizedBox(width: AppSpacing.x1),
                            _ghostButton(c, '刷新', AppIcons.refresh, _refresh),
                          ],
                        ),
                        if (left > 0) ...[
                          const SizedBox(height: AppSpacing.x1),
                          Text(
                            '冷却中 · 剩余 ${_fmtCd(left)}',
                            textAlign: TextAlign.center,
                            style: context.body(
                              size: CitroType.small,
                              color: c.accentInk,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.x2),
                        _communityPanel(c),
                        const SizedBox(height: AppSpacing.x2),
                        Text(
                          '玩法仅供参考，快乐第一。',
                          textAlign: TextAlign.center,
                          style: context.body(
                            size: CitroType.small,
                            color: c.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 12,
                child: Pressable(
                  onTap: () => popOrHome(context),
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
                        strokeSvg(AppIcons.arrowLeft, width: 2.2),
                        size: 18,
                        color: c.ink2,
                      ),
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

  Widget _ghostButton(
    CitroColors c,
    String label,
    String icon,
    VoidCallback onTap,
  ) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CitroColors.radii.chip),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            AppIcon(strokeSvg(icon, width: 2), size: 15, color: c.accentInk),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.body(
                size: CitroType.caption,
                weight: CitroType.medium,
                color: c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _communityPanel(CitroColors c) {
    return CitroCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('大家的抽签', style: context.heading(size: 16)),
              const Spacer(),
              if (remoteLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: c.accent,
                  ),
                )
              else
                Pressable(
                  onTap: _refreshRemote,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AppIcon(
                      strokeSvg(AppIcons.refresh, width: 2),
                      size: 14,
                      color: c.inkSoft,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x1),
          if (remoteLoading && remote.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
              child: Text(
                '正在同步全站记录…',
                textAlign: TextAlign.center,
                style: context.body(size: CitroType.caption, color: c.inkSoft),
              ),
            )
          else if (remoteError != null && remote.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
              child: Column(
                children: [
                  Text(
                    '暂时连不上全站记录',
                    style: context.body(
                      size: CitroType.caption,
                      color: c.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '暂时连不上云端，稍后再试',
                    style: context.body(
                      size: CitroType.micro,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
            )
          else if (remote.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
              child: Text(
                '还没有人抽，做第一个',
                textAlign: TextAlign.center,
                style: context.body(size: CitroType.caption, color: c.inkSoft),
              ),
            )
          else
            ...remote
                .take(20)
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(top: 1),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: r.you ? c.accent : c.surface2,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: r.you ? c.accent : c.line2,
                            ),
                          ),
                          child: Text(
                            r.name.isEmpty ? '?' : r.name.characters.last,
                            style: context.body(
                              size: CitroType.micro,
                              weight: CitroType.medium,
                              color: r.you ? c.onAccent : c.inkSoft,
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
                                      r.you ? '你' : r.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.body(
                                        size: CitroType.small,
                                        weight: CitroType.medium,
                                        color: r.you ? c.accentInk : c.inkSoft,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _time(r.ts),
                                    style: context.hand(
                                      size: CitroType.micro,
                                      color: c.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 1),
                              Text(
                                r.text,
                                style: context.body(
                                  size: CitroType.caption,
                                  color: c.ink2,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  /// 签面字号：越长字越小，保证 180 高的卡面放得下（手机宽度约 290）。
  double _stageSize(int len) {
    if (len <= 14) return 30;
    if (len <= 24) return 24;
    if (len <= 36) return 20;
    return 17;
  }

  String _fmtCd(int ms) {
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _time(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
