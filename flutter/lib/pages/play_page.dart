import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      if (mounted && remaining > 0) setState(() {});
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
          _PlayRecord(
            '${j['t']}',
            int.tryParse('${j['ts']}') ?? 0,
            you: true,
          ),
        );
      } catch (_) {}
    }
    setState(() {});
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
    final cd = int.tryParse('${j['cd'] ?? 0}') ?? 0;
    final until = DateTime.now().millisecondsSinceEpoch + cd;
    if (until != cooldownUntil) {
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
    var cooling = false;
    String? drawError;
    try {
      remote = await Api.playDraw(
        deviceId: state.gid,
        name: state.loggedIn ? null : state.guestName,
      );
    } on ApiException catch (e) {
      if (e.code == 429) {
        cooling = true;
      } else {
        drawError = e.message;
      }
    } catch (e) {
      drawError = '$e';
    }
    if (!mounted) return;
    if (cooling) {
      setState(() {
        rolling = false;
        stageText = '还在冷却，等一会儿再抽';
      });
      await _refreshRemote(silent: true);
      if (mounted) AppToast.show(context, '冷却中，稍后再抽');
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
    cooldownUntil = ts + 10 * 60 * 1000;
    await Prefs.setInt(PrefKeys.playCooldown, cooldownUntil);
    final list = Prefs.getStringList(PrefKeys.playRecords)
      ..add(jsonEncode({'t': pick, 'ts': ts}));
    await Prefs.setStringList(
      PrefKeys.playRecords,
      list.length > 30 ? list.sublist(list.length - 30) : list,
    );
    if (!mounted) return;
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
      if (drawError != null) {
        AppToast.show(context, '网络开小差，已按本机记录抽签');
      }
    }
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
      body: PaperBackground(
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
                            weight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '不知道这局怎么玩？抽一个，整活正式开始。每 10 分钟限抽 1 次。',
                          textAlign: TextAlign.center,
                          style: context.body(
                            size: 13,
                            color: c.inkSoft,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 20),
                        RepaintBoundary(
                          key: stageKey,
                          child: Container(
                            height: 230,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: c.line),
                              boxShadow: CitroColors.shadows.paper(c),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 4,
                                  left: 6,
                                  child: Text(
                                    '“',
                                    style: context.display(
                                      size: 42,
                                      color: c.hl,
                                      height: 1,
                                    ),
                                  ),
                                ),
                                Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 160),
                                    child: Text(
                                      stageText,
                                      key: ValueKey(stageText),
                                      textAlign: TextAlign.center,
                                      style: context.display(
                                        size: stageText.length > 14 ? 24 : 31,
                                        weight: FontWeight.w700,
                                        color: rolling ? c.inkSoft : c.ink,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 4,
                                  bottom: 0,
                                  child: Text(
                                    'Citro · 玩法抽签',
                                    style: context.hand(
                                      size: 13,
                                      color: c.inkSoft,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Pressable(
                                onTap: _draw,
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: left > 0
                                        ? c.accent.withAlpha(90)
                                        : c.accent,
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: CitroColors.shadows.note(c),
                                  ),
                                  child: Center(
                                    child: Text(
                                      rolling
                                          ? '停止抽取'
                                          : (left > 0
                                                ? '冷却中 ${_fmtCd(left)}'
                                                : '开始抽取'),
                                      style: context.body(
                                        size: 14,
                                        weight: FontWeight.w800,
                                        color: const Color(0xFF2E2C22),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _ghostButton(
                              c,
                              kIsWeb ? '复制截图' : '分享截图',
                              AppIcons.image,
                              _shareShot,
                            ),
                            const SizedBox(width: 8),
                            _ghostButton(c, '清空', AppIcons.refresh, _clear),
                          ],
                        ),
                        if (left > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            '每 10 分钟限抽 1 次 · 剩余 ${_fmtCd(left)}',
                            textAlign: TextAlign.center,
                            style: context.body(size: 11, color: c.accentInk),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: c.line),
                          ),
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
                                      size: 11,
                                      color: c.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (records.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  child: Text(
                                    '还没有记录，抽一签试试',
                                    textAlign: TextAlign.center,
                                    style: context.body(
                                      size: 12,
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
                                            Container(
                                              width: 4,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: c.accent,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Text(
                                                r.text,
                                                style: context.body(
                                                  size: 12.5,
                                                  color: c.ink2,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _time(r.ts),
                                              style: context.body(
                                                size: 10,
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
                        const SizedBox(height: 12),
                        _communityPanel(c),
                        const SizedBox(height: 14),
                        Text(
                          '玩法仅供参考，快乐第一。',
                          textAlign: TextAlign.center,
                          style: context.body(size: 10.5, color: c.inkSoft),
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            AppIcon(strokeSvg(icon, width: 2), size: 15, color: c.accentInk),
            const SizedBox(width: 4),
            Text(
              label,
              style: context.body(
                size: 11.5,
                weight: FontWeight.w700,
                color: c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _communityPanel(CitroColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(
                strokeSvg(AppIcons.users, width: 2),
                size: 15,
                color: c.accentInk,
              ),
              const SizedBox(width: 6),
              Text('大家的抽签', style: context.heading(size: 16)),
              const Spacer(),
              if (remoteLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
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
          const SizedBox(height: 8),
          if (remoteLoading && remote.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '正在同步全站记录…',
                textAlign: TextAlign.center,
                style: context.body(size: 12, color: c.inkSoft),
              ),
            )
          else if (remoteError != null && remote.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Text(
                    '暂时连不上全站记录',
                    style: context.body(size: 12, color: c.inkSoft),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '抽签仍可继续，联网后会自动同步',
                    style: context.body(size: 10, color: c.inkSoft),
                  ),
                ],
              ),
            )
          else if (remote.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '还没有人抽，做第一个',
                textAlign: TextAlign.center,
                style: context.body(size: 12, color: c.inkSoft),
              ),
            )
          else
            ...remote.take(20).map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(top: 1),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: r.you ? c.accent : c.hl,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.line2),
                      ),
                      child: Text(
                        r.name.isEmpty ? '?' : r.name.characters.last,
                        style: context.body(
                          size: 9,
                          weight: FontWeight.w700,
                          color: r.you ? const Color(0xFF2E2C22) : c.accentInk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
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
                                    size: 10.5,
                                    weight: FontWeight.w700,
                                    color: r.you ? c.accentInk : c.inkSoft,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _time(r.ts),
                                style: context.body(
                                  size: 9.5,
                                  color: c.inkSoft.withAlpha(200),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            r.text,
                            style: context.body(
                              size: 12,
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

  String _fmtCd(int ms) {
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _time(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
