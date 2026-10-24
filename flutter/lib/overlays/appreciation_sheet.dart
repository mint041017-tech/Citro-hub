import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/modal.dart';

Future<void> showAppreciationSheet(BuildContext context) async {
  await showCitroDialog(context, builder: (_) => const _AppreciationDialog());
}

class _AppreciationDialog extends StatelessWidget {
  const _AppreciationDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      maxWidth: 380,
      tapeColor: c.tape3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '给广告费！！！',
            textAlign: TextAlign.center,
            style: context.heading(size: 24, color: c.ink),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: Colors.white,
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.asset(
                  'assets/images/appreciation.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, _, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '赞赏码图片加载失败，请稍后再试',
                        textAlign: TextAlign.center,
                        style: context.body(size: 13, color: c.inkSoft),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
