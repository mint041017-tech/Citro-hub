import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../overlays/qr_login_view.dart';
import '../services/orientation.dart';
import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/home_background.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'legal_page.dart';

/// 强制登录页。
///
/// 启动后未登录时由 SplashGate 展示；登录成功、背景预载完成后才回调
/// [onAuthenticated] 进入主界面。视觉上和启动页、主界面同一套语言：
/// 奶米底 + 棕墨 + 青瓷，圆体、大圆角、充足留白。
class CitroLoginPage extends StatefulWidget {
  final String initialMode;
  final void Function(bool needProfilePrompt)? onAuthenticated;

  const CitroLoginPage({
    super.key,
    this.initialMode = 'login',
    this.onAuthenticated,
  });

  @override
  State<CitroLoginPage> createState() => _CitroLoginPageState();
}

class _CitroLoginPageState extends State<CitroLoginPage> {
  late String mode = widget.initialMode;
  String method = 'phone';
  final phone = TextEditingController();
  final email = TextEditingController();
  final name = TextEditingController();
  final pw = TextEditingController();
  bool loading = false;
  bool _agreed = false;
  bool _qrMode = false;
  bool _entering = false;
  String? error;

  static final _phoneRe = RegExp(r'^1[3-9]\d{9}$');
  static final _emailRe = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );
  static final _nameRe = RegExp(r'^[一-龥A-Za-z0-9_]{2,16}$');

  @override
  void initState() {
    super.initState();
    // 启动页已经开始预载背景；这里再把当前那张塞进 Flutter 图片缓存，
    // 登录页的背景首帧就不再现场解码。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await CitroAmbientBackground.prepare();
      if (mounted) CitroAmbientBackground.precache(context);
    });
  }

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

  /// 扫码登录入口只出现在桌面 Web、Windows 与 iPad（大屏）。
  bool get _qrSupported {
    if (kIsWeb) return true;
    if (platform.isWindows) return true;
    if (platform.isIOS) {
      return CitroOrientation.padSize(MediaQuery.sizeOf(context));
    }
    return false;
  }

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
      AppToast.show(
        context,
        mode == 'login' ? '登录成功，欢迎回来' : '注册成功，欢迎加入',
      );
      await _enter();
    } on Exception catch (e) {
      if (mounted) {
        setState(
          () => error = e.toString().replaceFirst('ApiException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// 登录成功后：等背景预载完成，再通知 SplashGate 进入主界面。
  ///
  /// 这一步是「登录页等待首页背景加载完成」的落点——背景没好之前
  /// 停在登录页的加载态，避免进主界面时背景还在转圈 / 闪白。
  Future<void> _enter() async {
    if (_entering) return;
    setState(() => _entering = true);
    try {
      await CitroAmbientBackground.prepare().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    } catch (_) {}
    if (!mounted) return;
    CitroAmbientBackground.precache(context);
    final user = AppState.instance.user;
    widget.onAuthenticated?.call(user != null && !user.profileDone);
  }

  Future<void> _onQrConfirmed() async {
    if (!mounted) return;
    AppToast.show(context, '扫码登录成功，欢迎回来');
    await _enter();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // 登录页用纯色底：不铺背景图，视觉干净、也不和主界面抢。
          Positioned.fill(child: ColoredBox(color: c.bg)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 32 : 20,
                  vertical: 24,
                ),
                child: Center(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _brandMark(c),
                        const SizedBox(height: 24),
                        _card(c),
                        const SizedBox(height: 16),
                        Text(
                          '© 2026 chimu',
                          style: context.body(
                            size: CitroType.micro,
                            color: c.inkSoft,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
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

  Widget _brandMark(CitroColors c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.line),
            boxShadow: CitroColors.shadows.float(c),
          ),
          child: Image.asset('assets/images/logo.webp', cacheWidth: 120),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Citro',
              style: context.heading(
                size: CitroType.titleLg,
                weight: CitroType.strong,
                color: c.ink,
                letterSpacing: .4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '今天也要开心',
              style: context.body(
                size: CitroType.caption,
                color: c.inkSoft,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _card(CitroColors c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.modal),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.card(c),
      ),
      child: _qrMode ? _qrContent(c) : _passwordContent(c),
    );
  }

  Widget _qrContent(CitroColors c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(c, '扫码登录', '用手机 Citro App 扫一扫，这里立即登录'),
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
                  size: CitroType.caption,
                  weight: CitroType.medium,
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
        _title(
          c,
          mode == 'login' ? '欢迎回来' : '加入 Citro',
          mode == 'login' ? '用手机号或邮箱继续' : '手机号 / 邮箱都可以注册',
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
                    size: CitroType.caption,
                    weight: CitroType.medium,
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
          loading: loading || _entering,
          onTap: _submit,
        ),
        const SizedBox(height: 12),
        if (mode == 'register')
          Text(
            '昵称会公开展示，别用真名哦。',
            textAlign: TextAlign.center,
            style: context.body(size: CitroType.small, color: c.inkSoft),
          )
        else
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '登录即表示你同意',
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
              _legalLink('《用户协议》', LegalDoc.terms),
              Text(
                '和',
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
              _legalLink('《隐私政策》', LegalDoc.privacy),
            ],
          ),
        if (mode == 'login' && _qrSupported) ...[
          const SizedBox(height: 10),
          _qrEntry(c),
        ],
        if (_entering) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: c.accent),
              ),
              const SizedBox(width: 8),
              Text(
                '正在为你准备首页…',
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
            ],
          ),
        ],
        const SizedBox(height: 2),
      ],
    );
  }

  Widget _title(CitroColors c, String title, String subtitle) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: context.heading(
            size: CitroType.heading,
            color: c.ink,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: context.body(size: CitroType.caption, color: c.inkSoft, height: 1.5),
        ),
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
            borderRadius: BorderRadius.circular(CitroColors.radii.chip),
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
                  size: CitroType.caption,
                  weight: CitroType.medium,
                  color: c.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeSwitch() {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.line2),
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
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
            borderRadius: BorderRadius.circular(CitroColors.radii.chip),
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
                size: CitroType.body,
                weight: CitroType.medium,
                color: active ? c.onAccent : c.inkSoft,
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
              ? c.accentLt.withAlpha(c.dark ? 90 : 170)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(CitroColors.radii.small),
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
                  size: CitroType.meta,
                  weight: CitroType.medium,
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
                borderRadius: BorderRadius.circular(CitroColors.radii.xs),
                border: Border.all(
                  color: _agreed ? c.accent : c.line2,
                  width: 1.2,
                ),
              ),
              child: _agreed
                  ? Center(
                      child: AppIcon(
                        '<path d="M20 6 9 17l-5-5"/>',
                        size: 11,
                        color: c.onAccent,
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
              Text(
                '我已阅读并同意',
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
              _legalLink('《用户协议》', LegalDoc.terms),
              Text(
                '和',
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
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
            size: CitroType.small,
            weight: CitroType.medium,
            color: context.c.accentInk,
          ),
        ),
      ),
    );
  }
}
