import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../overlays/qr_login_view.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
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
typedef AuthLoginInvoker = Future<void> Function(
  String account,
  String password,
);

/// 注册提交：参数命名与可空性对齐 `AppState.register`。昵称由表单生成
/// 临时唯一名，注册后的首次资料引导再让用户修改。
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
  final account = TextEditingController();
  final pw = TextEditingController();
  final pwConfirm = TextEditingController();
  bool loading = false;
  bool _agreed = false;
  bool _qrMode = false;
  bool _methodHover = false;
  String? error;

  static final _phoneRe = RegExp(r'^1[3-9]\d{9}$');
  static final _emailRe = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );

  @override
  void dispose() {
    account.dispose();
    pw.dispose();
    pwConfirm.dispose();
    super.dispose();
  }

  bool get _isEmail =>
      mode == 'register' ? method == 'email' : account.text.contains('@');

  String get _account {
    final raw = account.text.trim();
    return _isEmail ? raw : raw.replaceAll(RegExp(r'\D'), '');
  }

  String _temporaryName() {
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '新友$stamp${math.Random().nextInt(36).toRadixString(36)}';
  }

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
      if (!_agreed) {
        setState(() => error = '请先阅读并同意《用户协议》和《隐私政策》');
        return;
      }
    }
    if (pw.text.length < 6 || pw.text.length > 32) {
      setState(() => error = '密码需 6-32 位');
      return;
    }
    if (mode == 'register' && pwConfirm.text != pw.text) {
      setState(() => error = '两次输入的密码不一致');
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
          name: _temporaryName(),
          password: pw.text,
        );
      }
      if (!mounted) return;
      AppToast.show(context, mode == 'login' ? '登录成功，欢迎回来' : '注册成功，欢迎加入');
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
    final reduce = CitroMotion.reduced(context);
    final child = _qrMode ? _qrContent(c) : _passwordContent(c);
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : CitroMotion.size,
      switchInCurve: CitroMotion.easeOut,
      switchOutCurve: CitroMotion.exit,
      transitionBuilder: (child, animation) {
        if (reduce) return child;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .035),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey(_qrMode ? 'qr' : mode), child: child),
    );
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
        CitroField(
          key: const ValueKey('auth-account'),
          label: mode == 'login' ? '手机号 / 邮箱' : (_isEmail ? '邮箱' : '手机号'),
          hint: mode == 'login'
              ? '输入手机号或邮箱'
              : (_isEmail ? 'name@example.com' : '请输入 11 位手机号'),
          controller: account,
          keyboardType: _isEmail
              ? TextInputType.emailAddress
              : TextInputType.phone,
          maxLength: mode == 'register' && !_isEmail ? 11 : 64,
          suffix: mode == 'register'
              ? Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _methodSelector(),
                )
              : null,
          onChanged: (_) {
            setState(() {
              if (error != null) error = null;
            });
          },
        ),
        const SizedBox(height: 14),
        CitroField(
          key: const ValueKey('auth-password'),
          label: '密码',
          hint: '6-32 位密码',
          controller: pw,
          obscure: true,
          maxLength: 32,
        ),
        if (mode == 'register') ...[
          const SizedBox(height: 14),
          CitroField(
            key: const ValueKey('auth-password-confirm'),
            label: '确认密码',
            hint: '再次输入密码',
            controller: pwConfirm,
            obscure: true,
            maxLength: 32,
          ),
        ],
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
            '注册后可在个人资料中设置昵称和生日。',
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
              _legalLink('《用户协议》', AuthLegalDoc.terms),
              Text(
                '和',
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
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
          style: context.body(
            size: CitroType.caption,
            color: c.inkSoft,
            height: 1.5,
          ),
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
    // iOS 分段控件：灰色轨道 + 白色浮起滑块。
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(10),
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
          height: 34,
          decoration: BoxDecoration(
            color: active
                ? (c.dark ? const Color(0xFF636366) : const Color(0xFFFFFFFF))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: context.body(
                size: CitroType.body,
                weight: active ? CitroType.strong : CitroType.medium,
                color: active ? c.ink : c.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _methodSelector() {
    final c = context.c;
    final label = method == 'phone' ? '手机号' : '邮箱';
    return SizedBox(
      width: 92,
      height: 36,
      child: Semantics(
        button: true,
        label: '注册方式，$label',
        child: Builder(
          builder: (selectorContext) => MouseRegion(
            cursor: loading
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            onEnter: (_) {
              if (!_methodHover) setState(() => _methodHover = true);
            },
            onExit: (_) {
              if (_methodHover) setState(() => _methodHover = false);
            },
            child: GestureDetector(
              key: const ValueKey('auth-method-select'),
              behavior: HitTestBehavior.opaque,
              onTap: loading
                  ? null
                  : () async {
                      final box = selectorContext.findRenderObject();
                      final overlay = Overlay.of(selectorContext).context
                          .findRenderObject();
                      if (box is! RenderBox ||
                          !box.hasSize ||
                          overlay is! RenderBox ||
                          !overlay.hasSize) {
                        return;
                      }
                      final anchor =
                          box.localToGlobal(Offset.zero, ancestor: overlay) &
                          box.size;
                      final screen = Offset.zero & overlay.size;
                      final selected = await showMenu<String>(
                        context: selectorContext,
                        color: c.sheet,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            CitroColors.radii.field,
                          ),
                          side: BorderSide(color: c.line),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 120,
                          maxWidth: 120,
                        ),
                        position: RelativeRect.fromRect(
                          Rect.fromLTWH(
                            anchor.right - 120,
                            anchor.bottom + 8,
                            120,
                            0,
                          ),
                          screen,
                        ),
                        items: [
                          for (final value in const ['phone', 'email'])
                            PopupMenuItem<String>(
                              key: ValueKey('auth-method-option-$value'),
                              value: value,
                              height: 38,
                              child: Row(
                                children: [
                                  AppIcon(
                                    value == 'phone'
                                        ? AppIcons.phone
                                        : AppIcons.mail,
                                    size: 14,
                                    color: c.ink2,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    value == 'phone' ? '手机号' : '邮箱',
                                    style: context.body(
                                      size: CitroType.meta,
                                      weight: CitroType.medium,
                                      color: c.ink,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (method == value)
                                    AppIcon(
                                      AppIcons.check,
                                      size: 14,
                                      color: c.accent,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                      if (!mounted || selected == null || selected == method) {
                        return;
                      }
                      setState(() {
                        method = selected;
                        error = null;
                      });
                    },
              child: AnimatedContainer(
                duration: CitroMotion.hover,
                curve: CitroMotion.easeOut,
                width: 92,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _methodHover
                      ? c.accentLt.withValues(alpha: c.dark ? .28 : .52)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(CitroColors.radii.field),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: CitroType.small,
                        weight: CitroType.medium,
                        color: _methodHover ? c.accentInk : c.ink2,
                      ),
                    ),
                    const SizedBox(width: 2),
                    AppIcon(
                      AppIcons.chevronDown,
                      size: 11,
                      color: _methodHover ? c.accentInk : c.inkSoft,
                    ),
                  ],
                ),
              ),
            ),
          ),
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
          key: const ValueKey('auth-agree'),
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
              _legalLink('《用户协议》', AuthLegalDoc.terms),
              Text(
                '和',
                style: context.body(size: CitroType.small, color: c.inkSoft),
              ),
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
