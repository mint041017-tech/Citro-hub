import 'package:flutter/material.dart';

import '../pages/in_app_web.dart';
import '../theme/app_theme.dart';
import '../widgets/modal.dart';

/// Web 端不调用任何 AI：所有 AI 入口统一弹这张卡，引导下载客户端。
Future<void> showAiClientOnly(BuildContext context) {
  return showCitroDialog<void>(
    context,
    builder: (ctx) => PaperDialog(
      maxWidth: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI 功能仅客户端可用',
            style: ctx.heading(size: 18, color: ctx.c.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Web 版不调用 AI。下载 Citro 客户端后可使用 CiCi、AI 对战、账本与食谱分析。',
            style: ctx.body(size: 13, color: ctx.c.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  text: '知道了',
                  outlined: true,
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AccentButton(
                  text: '下载客户端',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    openCitroPage(
                      ctx,
                      'https://dl.chimu-claw.xyz/',
                      title: 'Citro 下载站',
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}