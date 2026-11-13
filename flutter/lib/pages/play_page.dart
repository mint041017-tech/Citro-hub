import 'dart:async';
import 'dart:convert';
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

class _PlayPageState extends State<PlayPage> {
  final math.Random rnd = math.Random();
  final stageKey = GlobalKey();
  String stageText = '点击「开始抽取」，命运交给橘子';
  String? lastPun;
  bool rolling = false;
  bool _cancelRoll = false;
  int cooldownUntil = 0;
  List<_PlayRecord> records = [];
  List<_PlayRecord> remote = [];
  bool remoteLoading = true;
  bool remoteBusy = false;
  String? remoteError;
  Timer? _cdTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshRemote();
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
    super.dispose();
  }

  void _load() {
    cooldownUntil = Prefs.getInt(PrefKeys.playCooldown);
    final list = Prefs.getStringList(PrefKeys.playRecords);
    records = [];
    for (final raw in list.reversed) {
      try {
        final j = jsonDecode(raw);
        records.add(
          _PlayRecord('${j['t']}', int.tryParse('${j['ts']}') ?? 0, you: true),
        );
      } catch (_) {}
    }
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

  void _applyRemote(Map<String, dynamic> j) {
    final list = _parseRemote(j['records']);
    // 刚抽到的签可能还没出现在这次返回里（服务端写入可见性 / 页面打开时
    // 就挂着的一次旧 GET 回来晚了），补回去，别让它从「大家的抽签」里消失。
    if (records.isNotEmpty &&
        !list.any(
          (r) => r.text == records.first.text && r.ts == records.first.ts,
        )) {
      list.insert(0, records.first);
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
    if (!silent && mounted) {
      setState(() {
        remoteLoading = true;
        remoteError = null;
      });
    }
    try {
      final j = await Api.playRecords(deviceId: AppState.instance.gid);
      if (!mounted) return;
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

  Future<void> _draw() async {
    if (rolling) {
      _cancelRoll = true;
      return;
    }
    if (remaining > 0) return;
    _cancelRoll = false;
    setState(() => rolling = true);
    final seq = List.generate(16, (_) => kPuns[rnd.nextInt(kPuns.length)]);
    for (var i = 0; i < seq.length; i++) {
      if (!mounted) return;
      if (_cancelRoll) {
        setState(() => rolling = false);
        return;
      }
      setState(() => stageText = seq[i]);
      await Future.delayed(Duration(milliseconds: 55 + i * 6));
    }
    if (!mounted) return;
    final state = AppState.instance;
    Map<String, dynamic>? remote;
    var coolingMs = 0;
    String? drawError;
    try {
      remote = await Api.playDraw(
        deviceId: state.gid,
        name: state.loggedIn ? null : state.guestName,
      );
    } on ApiException catch (e) {
      if (e.code == 429) {
        // 429 有两种：冷却（body 带 cd / records）和限流（只有 err）。
        // 只有真冷却才进冷却分支，限流按普通错误提示，别把按钮锁住。
        final cd = int.tryParse('${e.body?['cd'] ?? 0}') ?? 0;
        if (cd > 0 || e.body?['records'] != null) {
          coolingMs = cd;
        } else {
          drawError = e.message.isEmpty ? '操作太频繁，稍后再试' : e.message;
        }
      } else {
        drawError = e.message;
      }
    } catch (e) {
      drawError = '$e';
    }
    // 先记住页面还在不在：就算用户在这几毫秒里退掉了页面，
    // 抽到的签也要落盘，否则服务端记了、本机记录里没有，
    // 用户会以为「抽了没计入」。
    final alive = mounted;
    if (coolingMs > 0) {
      // 服务端这次没发签：本地不落账，否则和全站列表对不上。
      cooldownUntil =
          DateTime.now().millisecondsSinceEpoch + coolingMs;
      await Prefs.setInt(PrefKeys.playCooldown, cooldownUntil);
      if (!alive) return;
      setState(() {
        rolling = false;
        stageText = '服务器还在冷却，剩余 ${_fmtCd(coolingMs)}';
      });
      await _refreshRemote(silent: true);
      if (mounted) AppToast.show(context, '服务器还在冷却，稍后再抽');
      return;
    }
    final pick = remote != null && '${remote['t'] ?? ''}'.trim().isNotEmpty
        ? '${remote['t']}'
        : kPuns[rnd.nextInt(kPuns.length)];
    final ts =
        int.tryParse('${remote?['ts']}') ??
        DateTime.now().millisecondsSinceEpoch;
    final rec = _PlayRecord(pick, ts, you: true);
    records.insert(0, rec);
    // 本地不再自己加 10 分钟冷却：冷却完全由服务端下发（cd），
    // 客户端跟着显示即可。写死 10 分钟会和服务端的实际限制打架。
    await _saveRecord(rec);
    if (!alive) return;
    setState(() {
      lastPun = pick;
      stageText = pick;
      rolling = false;
      remoteError = drawError;
    });
    if (remote != null) {
      _applyRemote(remote);
    } else {
      // 服务端没抽成（离线）：本地照常展示，稍后刷新会带出真实冷却。
      unawaited(_refreshRemote(silent: true));
      if (drawError != null && mounted) {
        AppToast.show(context, '网络开小差，已按本机记录抽签');
      }
    }
  }

  /// 落盘一条抽取记录（最多留 30 条）。
  Future<void> _saveRecord(_PlayRecord rec) async {
    final list = Prefs.getStringList(PrefKeys.playRecords)
      ..add(jsonEncode({'t': rec.text, 'ts': rec.ts}));
    await Prefs.setStringList(
      PrefKeys.playRecords,
      list.length > 30 ? list.sublist(list.length - 30) : list,
    );
  }

  void _clear() {
    Prefs.setStringList(PrefKeys.playRecords, []);
    setState(() {
      records = [];
      stageText = '点击「开始抽取」，命运交给橘子';
      lastPun = null;
    });
    if (mounted) AppToast.show(context, '本机抽签记录已清空');
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
                            _ghostButton(c, '清空', AppIcons.refresh, _clear),
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
                        const SizedBox(height: AppSpacing.x3),
                        CitroCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '抽取记录',
                                    style: context.heading(size: 16),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${records.length} 条',
                                    style: context.body(
                                      size: CitroType.small,
                                      color: c.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.x1),
                              if (records.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.x3,
                                  ),
                                  child: Text(
                                    '还没有记录，抽一签试试',
                                    textAlign: TextAlign.center,
                                    style: context.body(
                                      size: CitroType.caption,
                                      color: c.inkSoft,
                                    ),
                                  ),
                                )
                              else
                                ...records
                                    .take(30)
                                    .map(
                                      (r) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                r.text,
                                                style: context.body(
                                                  size: CitroType.meta,
                                                  color: c.ink2,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _time(r.ts),
                                              style: context.hand(
                                                size: CitroType.micro,
                                                color: c.inkSoft,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                        ),
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
            AppIcon(
              strokeSvg(icon, width: 2),
              size: 15,
              color: c.accentInk,
            ),
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
                style: context.body(
                  size: CitroType.caption,
                  color: c.inkSoft,
                ),
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
                    '抽签仍可继续，联网后会自动同步',
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
                style: context.body(
                  size: CitroType.caption,
                  color: c.inkSoft,
                ),
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
