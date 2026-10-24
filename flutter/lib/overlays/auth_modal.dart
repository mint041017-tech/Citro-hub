import 'package:flutter/material.dart';

import '../pages/legal_page.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'profile_modal.dart';

Future<void> showAuthModal(
  BuildContext context, {
  String mode = 'login',
  VoidCallback? onDone,
}) async {
  await showCitroDialog(
    context,
    builder: (ctx) => _AuthDialog(initialMode: mode, onDone: onDone),
  );
  final user = AppState.instance.user;
  if (user != null && !user.profileDone && context.mounted) {
    await showProfileModal(context);
  }
}

class _AuthDialog extends StatefulWidget {
  final String initialMode;
  final VoidCallback? onDone;
  const _AuthDialog({required this.initialMode, this.onDone});

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  late String mode = widget.initialMode;
  final phone = TextEditingController();
  final name = TextEditingController();
  final pw = TextEditingController();
  final invite = TextEditingController();
  bool loading = false;
  bool _agreed = false;
  String? error;

  @override
  void dispose() {
    phone.dispose();
    name.dispose();
    pw.dispose();
    invite.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final state = context.app;
    final p = phone.text.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(p)) {
      setState(() => error = '请填写正确的 11 位手机号');
      return;
    }
    if (mode == 'register') {
      if (!RegExp(r'^[\u4e00-\u9fa5A-Za-z0-9_]{2,16}$')
          .hasMatch(name.text.trim())) {
        setState(() => error = '昵称需 2-16 位，中英文/数字/下划线');
        return;
      }
      if (name.text.trim().startsWith('游客')) {
        setState(() => error = '该昵称不可用，换一个吧');
        return;
      }
      if (!_agreed) {
        setState(() => error = '请先阅读并同意《用户协议》和《隐私政策》');
        return;
      }
    }
    if (pw.text.length < 6 || pw.text.length > 32) {
      setState(() => error = '密码需 6-32 位');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (mode == 'login') {
        await state.login(p, pw.text);
      } else {
        await state.register(p, name.text.trim(), pw.text, invite.text.trim());
      }
      if (!mounted) return;
      AppToast.show(context, mode == 'login' ? '登录成功，欢迎回来' : '注册成功，欢迎加入');
      Navigator.of(context).pop();
      widget.onDone?.call();
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    } on Exception catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      padding: const EdgeInsets.fromLTRB(26, 40, 26, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.line2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(children: [_tab('登录', 'login'), _tab('注册', 'register')]),
          ),
          const SizedBox(height: 20),
          CitroField(
            label: '手机号',
            hint: '请输入 11 位手机号',
            controller: phone,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            onChanged: (_) {
              if (error != null) setState(() => error = null);
            },
          ),
          if (mode == 'register') ...[
            const SizedBox(height: 14),
            CitroField(
              label: '昵称',
              hint: '2-16 位，中英文/数字/下划线',
              controller: name,
              maxLength: 16,
            ),
          ],
          const SizedBox(height: 14),
          CitroField(
            label: '密码',
            hint: '6-32 位密码',
            controller: pw,
            obscure: true,
            maxLength: 32,
          ),
          if (mode == 'register') ...[
            const SizedBox(height: 14),
            CitroField(
              label: '邀请码',
              hint: '注册需要邀请码',
              controller: invite,
              maxLength: 20,
            ),
            const SizedBox(height: 7),
            Text(
              '🔒 邀请码请通过添加站长微信获取',
              style: context.body(
                size: 11.5,
                weight: FontWeight.w600,
                color: c.accentInk,
              ),
            ),
            const SizedBox(height: 12),
            _agreeRow(),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: context.body(
                size: 11.5,
                weight: FontWeight.w600,
                color: c.stamp,
              ),
            ),
          ],
          const SizedBox(height: 18),
          AccentButton(
            text: mode == 'login' ? '登录' : '注册',
            loading: loading,
            onTap: _submit,
          ),
          const SizedBox(height: 10),
          if (mode == 'register')
            Text(
              '昵称会公开展示，别用真名哦。',
              textAlign: TextAlign.center,
              style: context.body(size: 11, color: c.inkSoft),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '登录即表示你同意',
                  style: context.body(size: 10.5, color: c.inkSoft),
                ),
                _legalLink('《用户协议》', LegalDoc.terms),
                Text('和', style: context.body(size: 10.5, color: c.inkSoft)),
                _legalLink('《隐私政策》', LegalDoc.privacy),
              ],
            ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _agreeRow() {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _agreed = !_agreed;
              if (_agreed && error != null) error = null;
            });
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 1, right: 8, bottom: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: _agreed ? c.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: _agreed ? c.accent : c.line2,
                  width: 1.2,
                ),
              ),
              child: _agreed
                  ? const Center(
                      child: AppIcon(
                        '<path d="M20 6 9 17l-5-5"/>',
                        size: 11,
                        color: Color(0xFF2E2C22),
                      ),
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('我已阅读并同意', style: context.body(size: 11, color: c.inkSoft)),
              _legalLink('《用户协议》', LegalDoc.terms),
              Text('和', style: context.body(size: 11, color: c.inkSoft)),
              _legalLink('《隐私政策》', LegalDoc.privacy),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legalLink(String label, LegalDoc doc) {
    return GestureDetector(
      onTap: () => showLegalPage(context, doc),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          label,
          style: context.body(
            size: 11,
            weight: FontWeight.w700,
            color: context.c.accentInk,
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, String value) {
    final c = context.c;
    final active = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (loading) return;
          setState(() {
            mode = value;
            error = null;
            if (value == 'register') _agreed = false;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 38,
          decoration: BoxDecoration(
            color: active ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: c.ink.withAlpha(20),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: context.body(
                size: 13.5,
                weight: FontWeight.w700,
                color: active ? const Color(0xFF2E2C22) : c.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
