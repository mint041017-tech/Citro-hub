import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'auth_modal.dart';
import 'qr_login_view.dart';

/// 手机端「扫一扫」：扫描桌面端二维码并在手机侧确认登录。
Future<void> showScanLogin(BuildContext context) async {
  await showCitroDialog(context, builder: (_) => const _ScanDialog());
}

class _ScanDialog extends StatefulWidget {
  const _ScanDialog();

  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _parseQrId(String raw) {
    if (raw.startsWith(kQrLoginPrefix)) {
      final id = raw.substring(kQrLoginPrefix.length).trim();
      return id.isEmpty ? null : id;
    }
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'citro' && uri.host == 'qr') {
      final id = uri.queryParameters['id']?.trim();
      return (id == null || id.isEmpty) ? null : id;
    }
    return null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled || _busy) return;
    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (raw == null) return;
    final id = _parseQrId(raw);
    if (id == null) return;
    if (AppState.instance.user == null) {
      setState(() {
        _handled = true;
        _error = '请先在手机登录账号，再扫码确认';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.qrConfirm(id);
      _handled = true;
      if (!mounted) return;
      AppToast.show(context, '已确认登录');
      Navigator.of(context).pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('ApiException: ', '');
      });
    }
  }

  void _retry() {
    setState(() {
      _handled = false;
      _busy = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      padding: const EdgeInsets.fromLTRB(20, 34, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '扫一扫',
            textAlign: TextAlign.center,
            style: context.heading(size: 22, color: c.ink, letterSpacing: .4),
          ),
          const SizedBox(height: 4),
          Text(
            '扫描电脑端登录二维码，确认后电脑立即登录',
            textAlign: TextAlign.center,
            style: context.body(size: 11, color: c.inkSoft, height: 1.45),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 300,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error, child) => ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            '相机不可用\n${error.errorCode}',
                            textAlign: TextAlign.center,
                            style: context.body(
                              size: 12,
                              color: Colors.white70,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 208,
                        height: 208,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withAlpha(210),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, state, _) {
                        final torchOn = state.torchState == TorchState.on;
                        return GestureDetector(
                          onTap: () => _controller.toggleTorch(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(110),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: AppIcon(
                                strokeSvg(AppIcons.flash, width: 2),
                                size: 18,
                                color: torchOn
                                    ? const Color(0xFFFFD166)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_busy)
                    ColoredBox(
                      color: Colors.black.withAlpha(120),
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: c.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: context.body(
                size: 12,
                weight: FontWeight.w700,
                color: c.stamp,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            if (AppState.instance.user == null)
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  showAuthModal(
                    context,
                    onDone: () {
                      if (context.mounted) showScanLogin(context);
                    },
                  );
                },
                child: _pill(c, '去登录'),
              )
            else
              GestureDetector(onTap: _retry, child: _pill(c, '重新扫描')),
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  strokeSvg(AppIcons.qr, width: 2),
                  size: 13,
                  color: c.inkSoft,
                ),
                const SizedBox(width: 5),
                Text(
                  '将二维码放入框内，即可自动识别',
                  style: context.body(size: 11, color: c.inkSoft),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _pill(CitroColors c, String label) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line2),
        ),
        child: Text(
          label,
          style: context.body(
            size: 12,
            weight: FontWeight.w700,
            color: c.accentInk,
          ),
        ),
      ),
    );
  }
}
