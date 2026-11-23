import 'package:flutter/material.dart';

/// 信息流里的长文折叠：超过 [maxLines] 行才出现「展开全文」。
///
/// 用 TextPainter 先按真实宽度排一遍，不靠字符数猜，避免中英混排、
/// 大字号或窄屏下提前折叠。展开后保留原文换行，不重排段落。
class FoldableText extends StatefulWidget {
  const FoldableText({
    super.key,
    required this.text,
    required this.style,
    this.maxLines = 5,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  State<FoldableText> createState() => _FoldableTextState();
}

class _FoldableTextState extends State<FoldableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        )..layout(maxWidth: width);
        final over = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _open ? null : widget.maxLines,
              overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (over)
              Semantics(
                button: true,
                label: _open ? '收起长文' : '展开长文',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Text(
                      _open ? '收起' : '展开全文',
                      style: widget.style.copyWith(
                        fontSize: (widget.style.fontSize ?? 14) - 1,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
