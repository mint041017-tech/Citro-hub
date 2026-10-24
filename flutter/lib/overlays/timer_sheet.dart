import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/cook_timer.dart';
import '../theme/app_theme.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

Future<int?> showTimerMinutesSheet(
  BuildContext context, {
  int initial = 10,
}) async {
  var minutes = initial.clamp(1, 180);
  final controller = FixedExtentScrollController(initialItem: minutes - 1);
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.c;
      return Container(
        height: 342,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: c.line),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 9),
                decoration: BoxDecoration(
                  color: c.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 8, 0),
                child: Row(
                  children: [
                    Text('设定计时', style: ctx.heading(size: 19)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          '取消',
                          style: ctx.body(size: 12, color: c.inkSoft),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoPicker(
                  itemExtent: 40,
                  scrollController: controller,
                  onSelectedItemChanged: (i) => minutes = i + 1,
                  children: [
                    for (var m = 1; m <= 180; m++)
                      Center(
                        child: Text(
                          '$m 分钟',
                          style: ctx.body(
                            size: 16,
                            weight: m == minutes
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: m == minutes ? c.accentInk : c.ink2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: AccentButton(
                  text: '开始计时',
                  height: 42,
                  onTap: () => Navigator.pop(ctx, minutes),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showTimerManageSheet(BuildContext context) async {
  final timer = CookTimer.instance;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.c;
      return AnimatedBuilder(
        animation: timer,
        builder: (ctx, _) {
          final tick = timer.tick;
          if (tick == null) {
            return Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: Border.all(color: c.line),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('计时已结束', style: ctx.heading(size: 18)),
                    const SizedBox(height: 12),
                    AccentButton(
                      text: '好',
                      height: 42,
                      onTap: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
            );
          }
          final total = math.max(1, tick.remainingSeconds);
          return Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border.all(color: c.line),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.line2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('计时中', style: ctx.heading(size: 19)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: AppIcon(
                            strokeSvg(AppIcons.close, width: 2.2),
                            size: 18,
                            color: c.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tick.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ctx.body(size: 11, color: c.inkSoft),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tick.timeText,
                    style: ctx.display(
                      size: 46,
                      weight: FontWeight.w700,
                      color: c.accentInk,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '剩余 $total 秒 · 常驻在页面左下角',
                    style: ctx.body(size: 10, color: c.inkSoft),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _option(ctx, '+1 分钟', () => timer.addMinutes(1)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _option(ctx, '+5 分钟', () => timer.addMinutes(5)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _option(ctx, '修改时间', () async {
                          final label = tick.label;
                          Navigator.pop(ctx);
                          final minutes = await showTimerMinutesSheet(
                            context,
                            initial: math.max(
                              1,
                              tick.remainingSeconds ~/ 60 + 1,
                            ),
                          );
                          if (minutes != null) {
                            CookTimer.instance.start(label, minutes);
                          }
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: AccentButton(
                      text: '取消计时',
                      danger: true,
                      height: 42,
                      onTap: () {
                        timer.cancel();
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _option(BuildContext context, String label, VoidCallback onTap) {
  final c = context.c;
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line2),
      ),
      child: Text(
        label,
        style: context.body(size: 11, weight: FontWeight.w600, color: c.ink2),
      ),
    ),
  );
}
