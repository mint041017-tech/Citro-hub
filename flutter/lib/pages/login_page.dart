import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/orientation.dart';
import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import '../widgets/auth_form_kit.dart';
import '../widgets/home_background.dart';
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
  bool _entering = false;

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

  /// 扫码登录入口只出现在桌面 Web、Windows 与 iPad（大屏）。
  bool get _qrSupported {
    if (kIsWeb) return true;
    if (platform.isWindows) return true;
    if (platform.isIOS) {
      return CitroOrientation.padSize(MediaQuery.sizeOf(context));
    }
    return false;
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

  /// 密码登录 / 注册成功：kit 已弹成功 toast，这里等背景预载完成再进主界面。
  Future<void> _onSuccess(bool isRegister) => _enter();

  Future<void> _onQrConfirmed() async {
    if (!mounted) return;
    AppToast.show(context, '扫码登录成功，欢迎回来');
    await _enter();
  }

  void _openLegal(AuthLegalDoc doc) {
    showLegalPage(
      context,
      doc == AuthLegalDoc.terms ? LegalDoc.terms : LegalDoc.privacy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;
    // 沉浸式：登录页就铺上首页同一张背景图（模糊 + 罩面），表单是一块
    // 磨砂卡片——第一眼就是新界面的样子。
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: CitroBackground(child: const SizedBox.expand()),
          ),
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
          width: 60,
          height: 60,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            // App 图标的样子：白底 + iOS 连续圆角 + 柔和投影。
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(15),
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
                size: 28,
                weight: CitroType.strong,
                color: c.ink,
                letterSpacing: -.4,
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
    return CitroGlass(
      borderRadius: BorderRadius.circular(CitroColors.radii.modal),
      tint: c.dark
          ? Colors.white.withValues(alpha: .10)
          : c.surface.withValues(alpha: .56),
      borderColor: Colors.white.withValues(alpha: c.dark ? .12 : .44),
      highlight: true,
      shadow: CitroColors.shadows.lg(c),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
      child: AuthFormKit(
        initialMode: widget.initialMode,
        qrSupported: _qrSupported,
        busy: _entering,
        qrSubtitle: '用手机 Citro App 扫一扫，这里立即登录',
        login: context.app.login,
        register: context.app.register,
        onSuccess: _onSuccess,
        onQrConfirmed: _onQrConfirmed,
        onOpenLegal: _openLegal,
        trailing: _entering ? _enteringRow(c) : null,
      ),
    );
  }

  Widget _enteringRow(CitroColors c) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: c.accent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '正在为你准备首页…',
              style: context.body(size: CitroType.small, color: c.inkSoft),
            ),
          ],
        ),
      ],
    );
  }
}
