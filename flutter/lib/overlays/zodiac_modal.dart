import 'dart:async';

import 'package:flutter/material.dart';

import '../services/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import '../widgets/weather_widgets.dart';

Future<void> showZodiacModal(BuildContext context) async {
  await showCitroDialog(context, builder: (ctx) => const _ZodiacDialog());
}

class _ZodiacDialog extends StatefulWidget {
  const _ZodiacDialog();
  @override
  State<_ZodiacDialog> createState() => _ZodiacDialogState();
}

class _ZodiacDialogState extends State<_ZodiacDialog> {
  String? selectedSign;

  @override
  void initState() {
    super.initState();
    final state = AppState.instance;
    selectedSign = state.zodiacSign;
    if (selectedSign != null) unawaited(state.refreshZodiacFortune());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = context.app;
    final sign = zodiacById(state.zodiacSign);
    return PaperDialog(
      maxWidth: 420,
      padding: const EdgeInsets.fromLTRB(20, 42, 20, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '星象',
            textAlign: TextAlign.center,
            style: context.heading(size: 24),
          ),
          const SizedBox(height: 12),
          if (sign == null)
            _picker(c, state)
          else
            _daily(context, c, state, sign),
        ],
      ),
    );
  }

  Widget _picker(CitroColors c, AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '选择你的本命星座，选定后不可更改',
          textAlign: TextAlign.center,
          style: context.body(size: 11.5, color: c.inkSoft),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.05,
          children: [
            for (final z in kZodiacSigns)
              GestureDetector(
                onTap: () => setState(() => selectedSign = z.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: selectedSign == z.id
                        ? (c.dark ? c.hl : const Color(0x4DF2A43C))
                        : c.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selectedSign == z.id ? c.accent : c.line,
                      width: selectedSign == z.id ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        z.symbol,
                        style: context.display(size: 24, color: c.accentInk),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        z.name,
                        style: context.body(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        AccentButton(
          text: '锁定我的星座',
          onTap: selectedSign == null
              ? null
              : () async {
                  await state.setZodiacSign(selectedSign!);
                  if (mounted) setState(() {});
                },
        ),
        const SizedBox(height: 8),
        Text(
          '登录后随账号同步；未登录将绑定当前设备',
          textAlign: TextAlign.center,
          style: context.body(size: 10, color: c.inkSoft),
        ),
      ],
    );
  }

  Widget _daily(
    BuildContext context,
    CitroColors c,
    AppState state,
    ZodiacSign sign,
  ) {
    final f = state.zodiacFortune;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${now.year}年${now.month}月${now.day}日 · 今日星语',
          textAlign: TextAlign.center,
          style: context.body(size: 11, color: c.inkSoft),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.dark ? const Color(0x0DFFFFFF) : const Color(0x0D23211C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: c.dark ? c.hl : const Color(0x47F7BC78),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        sign.symbol,
                        style: context.display(size: 28, color: c.accentInk),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sign.name, style: context.heading(size: 22)),
                        Text(
                          '${sign.range} · ${sign.element}象星座',
                          style: context.body(size: 10.5, color: c.inkSoft),
                        ),
                        const SizedBox(height: 3),
                        if (f != null)
                          Text(
                            '✦ ${f.tag}',
                            style: context.body(size: 11.5, color: c.accentInk),
                          )
                        else
                          Text(
                            state.zodiacLoading
                                ? '星语生成中…'
                                : (state.zodiacError != null
                                      ? '星语生成失败'
                                      : '等待生成今日星语'),
                            style: context.body(
                              size: 11.5,
                              color: state.zodiacError != null
                                  ? c.stamp
                                  : c.inkSoft,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (f != null)
                    ZodiacRing(score: f.score)
                  else
                    SizedBox(
                      width: 70,
                      height: 70,
                      child: Center(
                        child: state.zodiacLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                '✦',
                                style: context.display(
                                  size: 22,
                                  color: c.inkSoft.withAlpha(120),
                                ),
                              ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              DashedLine(color: c.line2),
              const SizedBox(height: 10),
              if (f != null) ...[
                Text(
                  f.text,
                  style: context.body(size: 13, color: c.ink2, height: 1.7),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _lucky(context, c, '幸运色', f.color),
                    _lucky(context, c, '幸运数字', f.number),
                    _lucky(context, c, '幸运物', f.item),
                  ],
                ),
              ] else if (state.zodiacLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'AI 正在写今天的星语…',
                          style: context.body(size: 12.5, color: c.ink2),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Text(
                  state.zodiacError ?? '今日星语还没有生成。',
                  style: context.body(
                    size: 12.5,
                    color: state.zodiacError != null ? c.stamp : c.ink2,
                    height: 1.6,
                  ),
                ),
                if (state.zodiacError != null) ...[
                  const SizedBox(height: 10),
                  AccentButton(
                    text: '重新生成',
                    height: 38,
                    onTap: () => state.refreshZodiacFortune(force: true),
                  ),
                ],
              ],
            ],
          ),
        ),
        if (f != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.dark ? const Color(0x0DFFFFFF) : const Color(0x0A23211C),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                Text(
                  '今日指数',
                  style: context.heading(size: 14, color: c.accentInk),
                ),
                const SizedBox(height: 10),
                _bar(context, c, '爱情', f.love, const Color(0xFFF2A43C)),
                _bar(context, c, '事业', f.work, const Color(0xFF8FC7A0)),
                _bar(context, c, '财运', f.wealth, const Color(0xFFE8C25A)),
                _bar(context, c, '健康', f.health, const Color(0xFF8CBEDC)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Center(
          child: GestureDetector(
            onTap: state.zodiacLoading
                ? null
                : () => state.refreshZodiacFortune(force: true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  strokeSvg(AppIcons.refresh, width: 2),
                  size: 13,
                  color: state.zodiacLoading
                      ? c.inkSoft.withAlpha(100)
                      : c.accentInk,
                ),
                const SizedBox(width: 4),
                Text(
                  state.zodiacLoading ? '生成中…' : '刷新运势',
                  style: context.body(
                    size: 11,
                    color: state.zodiacLoading
                        ? c.inkSoft.withAlpha(100)
                        : c.accentInk,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '星座运势由 AI 生成，仅供娱乐，开心最重要。',
          textAlign: TextAlign.center,
          style: context.body(size: 10, color: c.inkSoft),
        ),
      ],
    );
  }

  Widget _lucky(
    BuildContext context,
    CitroColors c,
    String label,
    String value,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: context.body(size: 9.5, color: c.inkSoft)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.body(
              size: 11.5,
              weight: FontWeight.w600,
              color: c.ink2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(
    BuildContext context,
    CitroColors c,
    String label,
    int value,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(label, style: context.body(size: 11, color: c.inkSoft)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: value.clamp(0, 100) / 100,
                minHeight: 6,
                backgroundColor: c.dark
                    ? const Color(0x14FFFFFF)
                    : const Color(0x1223211C),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: context.display(size: 13, color: c.accentInk),
            ),
          ),
        ],
      ),
    );
  }
}
