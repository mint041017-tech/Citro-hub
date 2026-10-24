import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../data/puns.dart';
import '../services/clipboard_image.dart';
import '../services/prefs.dart';
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
  const _PlayRecord(this.text, this.ts);
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
  Timer? _cdTimer;

  @override
  void initState() {
    super.initState();
    _load();
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
        records.add(_PlayRecord('${j['t']}', int.tryParse('${j['ts']}') ?? 0));
      } catch (_) {}
    }
    setState(() {});
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
    final pick = kPuns[rnd.nextInt(kPuns.length)];
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rec = _PlayRecord(pick, ts);
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
    });
  }

  void _clear() {
    Prefs.setStringList(PrefKeys.playRecords, []);
    Prefs.setInt(PrefKeys.playCooldown, 0);
    setState(() {
      records = [];
      cooldownUntil = 0;
      stageText = '点击「开始抽取」，命运交给橘子';
      lastPun = null;
    });
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

  String _fmtCd(int ms) {
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _time(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
