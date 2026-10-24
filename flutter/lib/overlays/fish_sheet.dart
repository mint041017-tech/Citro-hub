import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/fish.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

Future<void> showFishSheetDialog(BuildContext context) async {
  await showCitroDialog(context, builder: (ctx) => const _FishDialog());
}

class _FishDialog extends StatefulWidget {
  const _FishDialog();
  @override
  State<_FishDialog> createState() => _FishDialogState();
}

class _FishDialogState extends State<_FishDialog> {
  late FishConfig cfg = FishConfig.load();
  bool showSettings = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _pull();
  }

  Future<void> _pull() async {
    final state = AppState.instance;
    if (!state.loggedIn) return;
    try {
      final j = await Api.moyuGet();
      final raw = j['config'];
      if (raw is Map && mounted) {
        setState(
          () => cfg = FishConfig.fromJson(Map<String, dynamic>.from(raw)),
        );
        await cfg.save();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => saving = true);
    await cfg.save();
    final state = context.app;
    if (state.loggedIn) {
      try {
        await Api.moyuSave(cfg.toJson());
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      saving = false;
      showSettings = false;
    });
    AppToast.show(context, state.loggedIn ? '已保存，并同步到云端 🐟' : '已保存（登录后可多设备同步）');
  }

  Future<void> _pickTime({required bool start}) async {
    final current = FishState.minutes(start ? cfg.start : cfg.end);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          timePickerTheme: TimePickerThemeData(
            backgroundColor: context.c.surface,
            hourMinuteColor: context.c.surface2,
            dayPeriodColor: context.c.hl,
            dialBackgroundColor: context.c.surface2,
            dialHandColor: context.c.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final v =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => start ? cfg.start = v : cfg.end = v);
  }

  Future<void> _pickBreak({required bool start}) async {
    final current = FishState.minutes(
      start ? (cfg.breakStart ?? '12:00') : (cfg.breakEnd ?? '13:00'),
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final v =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (start) {
        cfg.breakStart = v;
      } else {
        cfg.breakEnd = v;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    final info = FishState.info(now, cfg);
    final subtitle =
        '${now.month}月${now.day}日 · 星期${'日一二三四五六'[now.weekday % 7]}';
    final next = FishState.nextRest(now, cfg);
    final (pct, total, inBreak) = FishState.progress(now, cfg);
    final nowM = now.hour * 60 + now.minute;
    final startM = FishState.minutes(cfg.start);
    final endM = FishState.minutes(cfg.end);
    var status = '';
    var detail = '';
    var showProgress = false;
    if (info.type == 'holiday') {
      status = '${info.name}假期';
      detail = '假期第 ${info.idx} 天 / 共 ${info.total} 天';
    } else if (info.type == 'rest') {
      status = '休息日';
      detail = '放心睡懒觉～';
    } else if (info.type == 'makeup') {
      status = '调休补班日';
      detail = '补班也是为了更好的假期 💪';
    } else if (nowM < startM) {
      status = '休息中';
      detail = '距上班还有 ${startM - nowM} 分钟';
    } else if (nowM >= endM) {
      status = '休息中';
      detail = '已下班 🎉 摸鱼成功';
    } else if (inBreak) {
      status = '休息中';
      detail = '午休时间，喘口气';
      showProgress = true;
    } else {
      status = '摸鱼中';
      detail = '今日工时进度 ${pct.toStringAsFixed(1)}%';
      showProgress = true;
    }
    final countdown = switch (info.type) {
      'holiday' || 'makeup' => next != null ? '距下个休息日 $next 天' : '',
      'work' => next != null ? '距下个休息日 $next 天' : '',
      _ => total > 0 ? '' : '',
    };

    return PaperDialog(
      maxWidth: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('🐟 摸鱼日历', style: context.heading(size: 18, color: c.accentInk)),
          const SizedBox(height: 10),
          Text(
            info.type == 'rest' ? '休息中' : status,
            style: context.display(
              size: 28,
              weight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: context.body(size: 11.5, color: c.inkSoft)),
          if (showProgress) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 7,
                backgroundColor: c.surface2,
                valueColor: AlwaysStoppedAnimation(c.accent),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: context.body(size: 12, color: c.ink2),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: context.body(
                size: detail.startsWith('距上班还有') ? 16 : 12,
                weight: detail.startsWith('距上班还有')
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: detail.startsWith('距上班还有') ? c.ink : c.ink2,
                height: detail.startsWith('距上班还有') ? 1.45 : null,
              ),
            ),
          ],
          if (countdown.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              countdown,
              textAlign: TextAlign.center,
              style: context.body(
                size: 16,
                weight: FontWeight.w600,
                color: c.accentInk,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (!showSettings)
            AccentButton(
              text: '⚙ 设置休息日与上班时间',
              outlined: true,
              height: 42,
              onTap: () => setState(() => showSettings = true),
            )
          else
            _settings(c),
        ],
      ),
    );
  }

  Widget _settings(CitroColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 2),
        Text(
          '每周休息日（可多选）',
          style: context.body(
            size: 11.5,
            weight: FontWeight.w700,
            color: c.inkSoft,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 7; i++)
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (cfg.rest.contains(i)) {
                      cfg.rest = [...cfg.rest]..remove(i);
                    } else {
                      cfg.rest = [...cfg.rest, i]..sort();
                    }
                  });
                },
                child: Container(
                  width: 38,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cfg.rest.contains(i) ? c.hl : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: cfg.rest.contains(i) ? c.accent : c.line2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${'日一二三四五六'[i]}',
                      style: context.body(
                        size: 12,
                        weight: FontWeight.w600,
                        color: cfg.rest.contains(i) ? c.accentInk : c.inkSoft,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _timeButton(
                c,
                '上班时间',
                cfg.start,
                () => _pickTime(start: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _timeButton(
                c,
                '下班时间',
                cfg.end,
                () => _pickTime(start: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() {
            if (cfg.breakStart == null) {
              cfg.breakStart = '12:00';
              cfg.breakEnd = '13:00';
            } else {
              cfg.breakStart = null;
              cfg.breakEnd = null;
            }
          }),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: cfg.breakStart != null ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: cfg.breakStart != null ? c.accent : c.line2,
                  ),
                ),
                child: cfg.breakStart != null
                    ? const Icon(
                        Icons.check,
                        size: 14,
                        color: Color(0xFF2E2C22),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text('中途有休息（午休等）', style: context.body(size: 12, color: c.ink2)),
            ],
          ),
        ),
        if (cfg.breakStart != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _timeButton(
                  c,
                  '休息开始',
                  cfg.breakStart!,
                  () => _pickBreak(start: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _timeButton(
                  c,
                  '休息结束',
                  cfg.breakEnd!,
                  () => _pickBreak(start: false),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        AccentButton(text: '保存', height: 42, loading: saving, onTap: _save),
      ],
    );
  }

  Widget _timeButton(
    CitroColors c,
    String label,
    String value,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.line2),
        ),
        child: Row(
          children: [
            Text(label, style: context.body(size: 11, color: c.inkSoft)),
            const Spacer(),
            Text(
              value,
              style: context.display(
                size: 15,
                weight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
