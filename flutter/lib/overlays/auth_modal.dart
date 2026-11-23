import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../pages/legal_page.dart';
import '../services/orientation.dart';
import '../services/platform.dart' as platform;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/auth_form_kit.dart';
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
  /// 扫码登录入口只出现在桌面 Web、Windows 与 iPad（大屏）。
  bool get _qrSupported {
    if (kIsWeb) return true;
    if (platform.isWindows) return true;
    if (platform.isIOS) {
      return CitroOrientation.padSize(MediaQuery.sizeOf(context));
    }
    return false;
  }

  /// 密码登录 / 注册成功：kit 已弹成功 toast，这里关闭弹窗并回调调用方。
  Future<void> _onSuccess(bool isRegister) async {
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onDone?.call();
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
  }

  Future<void> _onQrConfirmed() async {
    if (!mounted) return;
    AppToast.show(context, '扫码登录成功，欢迎回来');
    Navigator.of(context).pop();
    widget.onDone?.call();
  }

  void _openLegal(AuthLegalDoc doc) {
    showLegalPage(
      context,
      doc == AuthLegalDoc.terms ? LegalDoc.terms : LegalDoc.privacy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PaperDialog(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 22),
      child: AuthFormKit(
        initialMode: widget.initialMode,
        qrSupported: _qrSupported,
        headerLeading: _brandRow(),
        qrSubtitle: '用手机 Citro App 扫一扫，电脑端立即登录',
        login: context.app.login,
        register: context.app.register,
        onSuccess: _onSuccess,
        onQrConfirmed: _onQrConfirmed,
        onOpenLegal: _openLegal,
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
          decoration: BoxDecoration(
            color: c.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'CITRO',
          style: context.body(
            size: CitroType.small,
            weight: CitroType.medium,
            color: c.inkSoft,
            letterSpacing: 2.4,
          ),
        ),
      ],
    );
  }
}
