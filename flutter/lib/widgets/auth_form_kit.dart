import 'package:flutter/material.dart';

import '../overlays/qr_login_view.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'modal.dart';
import 'paper.dart';

// =============================================================================
// 认证表单共享套件：弹窗壳（auth_modal）与整页壳（login_page）共用的同一份
// 字段、校验、协议勾选、提交状态与二维码入口。
//
// 本文件不直接依赖 lib/state、lib/services：登录/注册调用、协议页跳转、
// 成功后的导航都由壳层通过回调注入；平台扫码入口是否展示也由壳层判定后
// 以 [qrSupported] 传入。壳层只负责容器（弹窗尺寸/圆角/关闭 vs 整页
// Scaffold/品牌头/返回）与成功后的导航。
// =============================================================================

/// 协议文档标识（kit 本地枚举；壳层映射到 `LegalDoc`，避免 widgets 依赖 pages）。
enum AuthLegalDoc { terms, privacy }

/// 登录提交：账号（手机号或邮箱，已按规则清洗）+ 密码。
typedef AuthLoginInvoker = Future<void> Function(String account, String password);

/// 注册提交：参数命名与可空性对齐 `AppState.register`。
typedef AuthRegisterInvoker = Future<void> Function({
  String? phone,
  String? email,
  required String name,
  required String password,
});

/// 密码登录 / 注册成功后的回调；[isRegister] 区分注册。壳层负责弹层关闭
/// 或路由导航，kit 不做跳转。
typedef AuthSuccessCallback = Future<void> Function(bool isRegister);

/// 认证表单：登录/注册两种模式、手机号/邮箱两种方式、协议勾选与扫码入口
/// 的唯一一份实现。控制器、倒计时（无）、焦点与提交状态都在本组件内部持有。
class AuthFormKit extends StatefulWidget {
  /// 初始模式：`login` / `register`。
  final String initialMode;

  /// 注入：调用登录服务。
  final AuthLoginInvoker login;

  /// 注入：调用注册服务。
  final AuthRegisterInvoker register;

  /// 注入：密码登录 / 注册成功（kit 已弹成功 toast）后的导航回调。
  final AuthSuccessCallback? onSuccess;

  /// 注入：扫码确认成功后的回调（toast 与导航由壳层处理）。
  final VoidCallback? onQrConfirmed;

  /// 注入：协议 / 隐私页跳转。
  final ValueChanged<AuthLegalDoc>? onOpenLegal;

  /// 当前端是否展示扫码登录入口（平台判定在壳层完成）。
  final bool qrSupported;

  /// 壳层追加的忙碌态（如整页等待首页背景预载），并入提交按钮 loading。
  final bool busy;

  /// 标题上方的品牌槽位（弹窗的小品牌行；整页留空）。
  final Widget? headerLeading;

  /// 扫码面板副标题（两端措辞不同）。
  final String qrSubtitle;

  /// 表单列末尾的壳层槽位（整页进入中转圈行）。
  final Widget? trailing;

  const AuthFormKit({
    super.key,
    this.initialMode = 'login',
    required this.login,
    required this.register,
    this.onSuccess,
    this.onQrConfirmed,
    this.onOpenLegal,
    this.qrSupported = false,
    this.busy = false,
    this.headerLeading,
    this.qrSubtitle = '用手机 Citro App 扫一扫，这里立即登录',
    this.trailing,
  });

  @override
  State<AuthFormKit> createState() => _AuthFormKitState();
}

class _AuthFormKitState extends State<AuthFormKit> {
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
        await widget.login(_account, pw.text);
      } else {
        await widget.register(
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
      await widget.onSuccess?.call(mode == 'register');
    } on Exception catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('ApiException: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return _qrMode ? _qrContent(c) : _passwordContent(c);
  }

  Widget _qrContent(CitroColors c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.headerLeading != null) ...[
          widget.headerLeading!,
          const SizedBox(height: 14),
        ],
        _title(c, '扫码登录', widget.qrSubtitle),
        const SizedBox(height: 18),
        QrLoginView(onConfirmed: () => widget.onQrConfirmed?.call()),
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
        if (widget.headerLeading != null) ...[
          widget.headerLeading!,
          const SizedBox(height: 14),
        ],
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
          loading: loading || widget.busy,
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
              Text('登录即表示你同意', style: context.body(size: CitroType.small, color: c.inkSoft)),
              _legalLink('《用户协议》', AuthLegalDoc.terms),
              Text('和', style: context.body(size: CitroType.small, color: c.inkSoft)),
              _legalLink('《隐私政策》', AuthLegalDoc.privacy),
            ],
          ),
        if (mode == 'login' && widget.qrSupported) ...[
          const SizedBox(height: 10),
          _qrEntry(c),
        ],
        if (widget.trailing != null) widget.trailing!,
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
              Text('我已阅读并同意', style: context.body(size: CitroType.small, color: c.inkSoft)),
              _legalLink('《用户协议》', AuthLegalDoc.terms),
              Text('和', style: context.body(size: CitroType.small, color: c.inkSoft)),
              _legalLink('《隐私政策》', AuthLegalDoc.privacy),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legalLink(String label, AuthLegalDoc doc) {
    return GestureDetector(
      onTap: () => widget.onOpenLegal?.call(doc),
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
