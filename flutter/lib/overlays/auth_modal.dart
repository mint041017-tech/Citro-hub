import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../pages/legal_page.dart';
import '../services/orientation.dart';
import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'profile_modal.dart';
import 'qr_login_view.dart';

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
  String method = 'phone';
  final phone = TextEditingController();
  final email = TextEditingController();
  final name = TextEditingController();
  final pw = TextEditingController();
  bool loading = false;
  bool _agreed = false;
  bool _qrMode = false;
  String? error;

  static final _phoneRe = RegExp(r'^1[3-9]\d{9}$');
  static final _emailRe = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );
  static final _nameRe = RegExp(r'^[\u4e00-\u9fa5A-Za-z0-9_]{2,16}$');

  @override
  void dispose() {
    phone.dispose();
    email.dispose();
    name.dispose();
    pw.dispose();
    super.dispose();
  }

  bool get _isEmail => method == 'email';

  String get _account =>
      _isEmail ? email.text.trim() : phone.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _submit() async {
    final state = context.app;
    if (_isEmail) {
      if (!_emailRe.hasMatch(_account)) {
        setState(() => error = '请填写正确的邮箱地址');
        return;
      }
    } else if (!_phoneRe.hasMatch(_account)) {
      setState(() => error = '请填写正确的 11 位手机号');
      return;
    }
    if (mode == 'register') {
      if (!_nameRe.hasMatch(name.text.trim())) {
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
        await state.login(_account, pw.text);
      } else {
        await state.register(
          phone: _isEmail ? null : _account,
          email: _isEmail ? _account : null,
          name: name.text.trim(),
          password: pw.text,
        );
      }
      if (!mounted) return;
      AppToast.show(context, mode == 'login' ? '登录成功，欢迎回来' : '注册成功，欢迎加入');
      Navigator.of(context).pop();
      widget.onDone?.call();
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    } on Exception catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('ApiException: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// 扫码登录入口只出现在桌面 Web、Windows 与 iPad（大屏）。
  bool get _qrSupported {
    if (kIsWeb) return true;
    if (platform.isWindows) return true;
    if (platform.isIOS) {
      return CitroOrientation.padSize(MediaQuery.sizeOf(context));
    }
    return false;
  }

  Future<void> _onQrConfirmed() async {
    if (!mounted) return;
    AppToast.show(context, '扫码登录成功，欢迎回来');
    Navigator.of(context).pop();
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 22),
      child: _qrMode ? _qrContent(c) : _passwordContent(c),
    );
  }

  Widget _qrContent(CitroColors c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _brandRow(),
        const SizedBox(height: 14),
        Text(
          '扫码登录',
          textAlign: TextAlign.center,
          style: context.heading(size: 24, color: c.ink, letterSpacing: .4),
        ),
        const SizedBox(height: 5),
        Text(
          '用手机 Citro App 扫一扫，电脑端立即登录',
          textAlign: TextAlign.center,
          style: context.body(size: 12, color: c.inkSoft, height: 1.5),
        ),
        const SizedBox(height: 18),
        QrLoginView(onConfirmed: _onQrConfirmed),
        const SizedBox(height: 4),
        Center(
          child: GestureDetector(
            onTap: () => setState(() => _qrMode = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Text(
                '返回账号登录',
                style: context.body(
                  size: 12,
                  weight: FontWeight.w700,
                  color: c.accentInk,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _passwordContent(CitroColors c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _brandRow(),
        const SizedBox(height: 14),
        Text(
          mode == 'login' ? '欢迎回来' : '加入 Citro',
          textAlign: TextAlign.center,
          style: context.heading(size: 24, color: c.ink, letterSpacing: .4),
        ),
        const SizedBox(height: 5),
        Text(
          mode == 'login' ? '用手机号或邮箱继续' : '手机号 / 邮箱都可以注册',
          textAlign: TextAlign.center,
          style: context.body(size: 12, color: c.inkSoft, height: 1.5),
        ),
        const SizedBox(height: 18),
        _modeSwitch(),
        const SizedBox(height: 14),
        _methodSwitch(),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _isEmail
              ? CitroField(
                  key: const ValueKey('email'),
                  label: '邮箱',
                  hint: 'name@example.com',
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 64,
                  onChanged: (_) {
                    if (error != null) setState(() => error = null);
                  },
                )
              : CitroField(
                  key: const ValueKey('phone'),
                  label: '手机号',
                  hint: '请输入 11 位手机号',
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  onChanged: (_) {
                    if (error != null) setState(() => error = null);
                  },
                ),
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
        if (error != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 5),
                child: AppIcon(AppIcons.info, size: 12, color: c.stamp),
              ),
              Expanded(
                child: Text(
                  error!,
                  style: context.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: c.stamp,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (mode == 'register') ...[const SizedBox(height: 12), _agreeRow()],
        const SizedBox(height: 18),
        AccentButton(
          text: mode == 'login' ? '登录' : '创建账号',
          loading: loading,
          onTap: _submit,
        ),
        const SizedBox(height: 12),
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
              Text('登录即表示你同意', style: context.body(size: 11, color: c.inkSoft)),
              _legalLink('《用户协议》', LegalDoc.terms),
              Text('和', style: context.body(size: 11, color: c.inkSoft)),
              _legalLink('《隐私政策》', LegalDoc.privacy),
            ],
          ),
        if (mode == 'login' && _qrSupported) ...[
          const SizedBox(height: 10),
          _qrEntry(c),
        ],
        const SizedBox(height: 2),
      ],
    );
  }

  Widget _qrEntry(CitroColors c) {
    return Center(
      child: Pressable(
        onTap: () => setState(() => _qrMode = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.line2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                strokeSvg(AppIcons.qr, width: 2),
                size: 14,
                color: c.accentInk,
              ),
              const SizedBox(width: 6),
              Text(
                '扫码登录',
                style: context.body(
                  size: 12,
                  weight: FontWeight.w700,
                  color: c.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandRow() {
    final c = context.c;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF7A9BBE),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'CITRO',
          style: context.body(
            size: 11,
            weight: FontWeight.w700,
            color: c.inkSoft,
            letterSpacing: 2.4,
          ),
        ),
      ],
    );
  }

  Widget _modeSwitch() {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.line2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [_modeChip('登录', 'login'), _modeChip('注册', 'register')],
      ),
    );
  }

  Widget _modeChip(String label, String value) {
    final c = context.c;
    final active = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (loading || active) return;
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
                size: 14,
                weight: FontWeight.w700,
                color: active ? const Color(0xFF2E2C22) : c.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _methodSwitch() {
    return Row(
      children: [
        Expanded(child: _methodChip('手机号', 'phone', AppIcons.phone)),
        const SizedBox(width: 8),
        Expanded(child: _methodChip('邮箱', 'email', AppIcons.mail)),
      ],
    );
  }

  Widget _methodChip(String label, String value, String icon) {
    final c = context.c;
    final active = method == value;
    return GestureDetector(
      onTap: () {
        if (loading || active) return;
        setState(() {
          method = value;
          error = null;
        });
      },
      child: AnimatedContainer(
        key: ValueKey('auth-method-$value'),
        duration: const Duration(milliseconds: 180),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? c.hl.withAlpha(c.dark ? 90 : 120)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? c.accent : c.line2),
        ),
        // 文字在胶囊内真正居中；图标单独靠左，不参与文字居中的宽度计算。
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: Text(
                label,
                style: context.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: active ? c.ink : c.inkSoft,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: AppIcon(
                  icon,
                  size: 15,
                  color: active ? c.accentInk : c.inkSoft,
                ),
              ),
            ),
          ],
        ),
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
}
