import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

const kReportReasons = <String>['垃圾广告', '辱骂攻击', '色情低俗', '违法违规', '侵犯隐私', '其他'];

Future<void> showReportSheet(
  BuildContext context, {
  required String type,
  String? postId,
  String? commentId,
  String? targetNick,
  String? preview,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(
      type: type,
      postId: postId,
      commentId: commentId,
      targetNick: targetNick,
      preview: preview,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.type,
    this.postId,
    this.commentId,
    this.targetNick,
    this.preview,
  });

  final String type;
  final String? postId;
  final String? commentId;
  final String? targetNick;
  final String? preview;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _detail = TextEditingController();
  String _reason = '';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (_reason.isEmpty) {
      setState(() => _error = '请选择举报原因');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await Api.report(
        type: widget.type,
        postId: widget.postId,
        commentId: widget.commentId,
        targetNick: widget.targetNick,
        reason: _reason,
        detail: _detail.text.trim(),
      );
      if (!mounted) return;
      AppToast.show(context, '举报已提交，我们会尽快处理');
      Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('ApiException: ', '');
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final preview = (widget.preview ?? '').trim();
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.lg(c),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.line2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.type == 'comment' ? '举报评论' : '举报动态',
                        style: context.heading(size: 21, color: c.ink),
                      ),
                    ),
                    GestureDetector(
                      onTap: _sending
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: AppIcon(
                          strokeSvg(AppIcons.close, width: 2.2),
                          size: 17,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.line),
                    ),
                    child: Text(
                      preview.length > 80
                          ? '${preview.substring(0, 80)}…'
                          : preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: 11,
                        color: c.inkSoft,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  '选择原因',
                  style: context.body(
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: c.inkSoft,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final reason in kReportReasons)
                      GestureDetector(
                        onTap: _sending
                            ? null
                            : () => setState(() {
                                _reason = reason;
                                _error = null;
                              }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _reason == reason ? c.hl : c.surface2,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _reason == reason ? c.accent : c.line2,
                            ),
                          ),
                          child: Text(
                            reason,
                            style: context.body(
                              size: 11.5,
                              weight: _reason == reason
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _reason == reason ? c.accentInk : c.ink2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _detail,
                  enabled: !_sending,
                  maxLength: 200,
                  maxLines: 3,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  style: context.body(size: 12.5, height: 1.5),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '补充说明（选填）',
                    hintStyle: context.body(size: 12, color: c.inkSoft),
                    filled: true,
                    fillColor: c.surface2,
                    contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.line2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.accent),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    style: context.body(
                      size: 11,
                      weight: FontWeight.w600,
                      color: c.stamp,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                AccentButton(
                  text: '提交举报',
                  danger: true,
                  loading: _sending,
                  onTap: _submit,
                ),
                const SizedBox(height: 4),
                Text(
                  '恶意举报可能影响账号使用。我们会在合理期限内审核。',
                  textAlign: TextAlign.center,
                  style: context.body(size: 9.5, color: c.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
