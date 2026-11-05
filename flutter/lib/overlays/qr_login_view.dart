import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';

/// 二维码内容协议：手机 App 扫到后解析 id，再调用 /api/auth/qr/confirm。
const String kQrLoginPrefix = 'citro://qr?id=';

/// 桌面端（Web / Windows / iPad）扫码登录面板。
///
/// 拿到一次性 id 后渲染二维码，并每 2 秒轮询后端；手机 App 确认后
/// 直接落到本地会话并回调 [onConfirmed]。
class QrLoginView extends StatefulWidget {
  final VoidCallback onConfirmed;

  const QrLoginView({super.key, required this.onConfirmed});

  @override
  State<QrLoginView> createState() => _QrLoginViewState();
}

class _QrLoginViewState extends State<QrLoginView> {
  String? _id;
  String _status = 'creating';
  String? _error;
  int _seconds = 300;
  bool _loading = true;
  bool _polling = false;
  Timer? _pollTimer;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _pollTimer = null;
    _tickTimer = null;
  }

  Future<void> _create() async {
    _stopTimers();
    setState(() {
      _loading = true;
      _error = null;
      _status = 'creating';
      _id = null;
      _seconds = 300;
    });
    try {
      final j = await Api.qrCreate();
      final id = j['id']?.toString() ?? '';
      if (id.isEmpty) throw Exception('二维码创建失败');
      final ttl = (j['expiresIn'] as num?)?.toInt() ?? 300;
      if (!mounted) return;
      setState(() {
        _id = id;
        _seconds = ttl;
        _status = 'pending';
        _loading = false;
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _status != 'pending') return;
        if (_seconds <= 1) {
          _stopTimers();
          setState(() {
            _seconds = 0;
            _status = 'expired';
          });
        } else {
          setState(() => _seconds--);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'error';
        _error = e.toString().replaceFirst('ApiException: ', '');
      });
    }
  }

  Future<void> _poll() async {
    final id = _id;
    if (id == null || _status != 'pending' || _polling) return;
    _polling = true;
    try {
      final j = await Api.qrPoll(id);
      final status = j['status']?.toString() ?? '';
      if (!mounted) return;
      if (status == 'confirmed') {
        _stopTimers();
        setState(() => _status = 'confirmed');
        final token = j['token']?.toString() ?? '';
        final rawUser = j['user'];
        if (token.isNotEmpty && rawUser is Map) {
          await AppState.instance.applyQrLogin(
            token,
            Map<String, dynamic>.from(rawUser),
          );
        }
        if (mounted) widget.onConfirmed();
      } else if (status == 'expired') {
        _stopTimers();
        setState(() => _status = 'expired');
      }
    } catch (_) {
      // 网络抖动不打断倒计时，下一轮继续。
    } finally {
      _polling = false;
    }
  }

  String get _countdown {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 184,
          height: 184,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line2),
            boxShadow: c.dark
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x1A5A4A2C),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
          ),
          child: _id == null
              ? Center(
                  child: _loading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.accent,
                          ),
                        )
                      : AppIcon(
                          strokeSvg(AppIcons.qr, width: 2),
                          size: 34,
                          color: c.inkSoft,
                        ),
                )
              : QrImageView(
                  data: '$kQrLoginPrefix$_id',
                  version: QrVersions.auto,
                  size: 160,
                  gapless: true,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                  errorStateBuilder: (context, error) => Center(
                    child: Text(
                      '二维码生成失败',
                      style: context.body(size: 11.5, color: c.stamp),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        _statusLine(c),
        const SizedBox(height: 4),
        if (_status == 'pending')
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                strokeSvg(AppIcons.scan, width: 2),
                size: 13,
                color: c.inkSoft,
              ),
              const SizedBox(width: 5),
              Text(
                '打开 Citro App →「我的」→「扫一扫」',
                style: context.body(size: 10.5, color: c.inkSoft),
              ),
            ],
          ),
        if (_status == 'pending') ...[
          const SizedBox(height: 6),
          Text(
            '有效期 $_countdown',
            style: context.body(size: 10.5, color: c.inkSoft),
          ),
        ],
        if (_status == 'expired' || _status == 'error') ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _create,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.line2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.refresh, width: 2),
                    size: 13,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _status == 'error' ? '重新加载' : '刷新二维码',
                    style: context.body(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: c.ink2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _statusLine(CitroColors c) {
    final (text, color, weight) = switch (_status) {
      'confirmed' => ('扫码成功，正在登录…', c.accentInk, FontWeight.w700),
      'expired' => ('二维码已过期', c.stamp, FontWeight.w600),
      'error' => (_error ?? '加载失败，请重试', c.stamp, FontWeight.w600),
      'creating' => ('正在生成二维码…', c.inkSoft, FontWeight.w400),
      _ => ('请用手机扫码登录', c.ink, FontWeight.w600),
    };
    return Text(
      text,
      textAlign: TextAlign.center,
      style: context.body(size: 12.5, weight: weight, color: color),
    );
  }
}
