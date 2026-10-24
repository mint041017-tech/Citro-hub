import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

Future<bool> showDeleteAccountDialog(BuildContext context) async {
  final done = await showCitroDialog<bool>(
    context,
    dismissible: false,
    builder: (_) => const _DeleteAccountDialog(),
  );
  return done == true;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _confirmed = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_confirmed) {
      setState(() => _error = '请先勾选确认永久注销');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = '请输入登录密码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppState.instance.deleteAccount(_password.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('ApiException: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      showClose: false,
      padding: const EdgeInsets.fromLTRB(22, 36, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.stamp.withAlpha(24),
                shape: BoxShape.circle,
                border: Border.all(color: c.stamp.withAlpha(90)),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.trash, width: 2),
                  size: 20,
                  color: c.stamp,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '注销账号',
            textAlign: TextAlign.center,
            style: context.heading(size: 23, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            '注销后，以下数据会被永久删除且无法恢复：',
            textAlign: TextAlign.center,
            style: context.body(size: 11.5, color: c.inkSoft),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: c.stamp.withAlpha(c.dark ? 18 : 12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.stamp.withAlpha(55)),
            ),
            child: Text(
              '账号与登录信息 · 帖子 / 评论 / 图片 / 语音\n'
              '笔记 · 食谱 / 冰箱 / 购物清单 · 游戏成绩\n'
              '头像 · 星座绑定与相关缓存',
              style: context.body(size: 11, color: c.ink2, height: 1.75),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _loading
                ? null
                : () => setState(() {
                    _confirmed = !_confirmed;
                    if (_confirmed) _error = null;
                  }),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _confirmed ? c.stamp : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: _confirmed ? c.stamp : c.line2,
                        width: 1.2,
                      ),
                    ),
                    child: _confirmed
                        ? const Center(
                            child: AppIcon(
                              '<path d="M20 6 9 17l-5-5"/>',
                              size: 11,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
                Expanded(
                  child: Text(
                    '我已了解注销不可恢复，并确认永久删除账号',
                    style: context.body(
                      size: 11.5,
                      color: _confirmed ? c.stamp : c.ink2,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CitroField(
            label: '登录密码',
            hint: '输入密码确认注销',
            controller: _password,
            obscure: true,
            maxLength: 32,
            enabled: !_loading,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: context.body(
                size: 11,
                weight: FontWeight.w600,
                color: c.stamp,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  text: '取消',
                  outlined: true,
                  onTap: _loading
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AccentButton(
                  text: '永久注销',
                  danger: true,
                  loading: _loading,
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
