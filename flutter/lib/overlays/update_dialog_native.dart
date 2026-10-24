import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/updater.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

enum UpdateDialogResult { dismissed, installStarted }

bool _checking = false;
bool _dialogOpen = false;

Future<void> checkForUpdates(
  BuildContext context, {
  bool manual = false,
}) async {
  if (!Platform.isAndroid) return;
  if (_checking || _dialogOpen) {
    if (manual && context.mounted) {
      AppToast.show(context, '正在检查更新，请稍候');
    }
    return;
  }
  if (!manual &&
      (!UpdatePrefs.shouldAutoCheck || AppState.instance.popupActive)) {
    return;
  }

  _checking = true;
  final service = UpdateService();
  BuildContext? checkingCtx;
  if (manual) {
    unawaited(
      showCitroDialog<void>(
        context,
        dismissible: false,
        builder: (ctx) {
          checkingCtx = ctx;
          return const _CheckingDialog();
        },
      ),
    );
  }

  UpdateInfo? info;
  InstalledVersion? installed;
  Object? error;
  try {
    final values = await Future.wait<Object?>([
      service.fetchLatest(),
      UpdateService.installedVersion(),
      if (manual) Future<void>.delayed(const Duration(milliseconds: 350)),
    ]);
    info = values[0] as UpdateInfo?;
    installed = values[1] as InstalledVersion;
    await UpdatePrefs.markChecked();
  } catch (e) {
    error = e;
  } finally {
    _checking = false;
    service.close();
    final checking = checkingCtx;
    if (checking != null && checking.mounted) {
      Navigator.of(checking).pop();
    }
  }
  if (!context.mounted) return;

  if (error != null) {
    if (manual) {
      AppToast.show(
        context,
        error is UpdateException ? error.message : '检查更新失败，请稍后重试',
      );
    }
    return;
  }
  if (info == null) {
    if (manual) AppToast.show(context, '暂无可用更新');
    return;
  }

  final current = installed ?? await UpdateService.installedVersion();
  if (!context.mounted) return;
  if (!info.isNewerThan(current)) {
    if (manual) {
      AppToast.show(
        context,
        current.version == 'dev' ? '当前已是最新版本' : '当前已是最新版本 v${current.version}',
      );
    }
    return;
  }
  if (!manual &&
      info.versionCode > 0 &&
      UpdatePrefs.skippedVersion == info.versionCode) {
    return;
  }

  _dialogOpen = true;
  UpdateDialogResult result;
  try {
    result = await showUpdateDialog(context, info: info, installed: current);
  } finally {
    _dialogOpen = false;
  }
  if (result == UpdateDialogResult.installStarted && context.mounted) {
    AppToast.show(context, '已打开系统安装程序');
  }
}

Future<UpdateDialogResult> showUpdateDialog(
  BuildContext context, {
  required UpdateInfo info,
  required InstalledVersion installed,
}) async {
  final result = await showCitroDialog<UpdateDialogResult>(
    context,
    dismissible: !info.force,
    builder: (_) => _UpdateDialog(info: info, installed: installed),
  );
  return result ?? UpdateDialogResult.dismissed;
}

enum _Phase { idle, downloading, permission, installing, error }

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final InstalledVersion installed;

  const _UpdateDialog({required this.info, required this.installed});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.idle;
  int _received = 0;
  int _total = 0;
  String? _error;
  http.Client? _client;
  File? _file;
  int _runId = 0;
  int _lastPct = -1;
  DateTime _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _busy => _phase == _Phase.downloading || _phase == _Phase.installing;

  @override
  void dispose() {
    _runId++;
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final info = widget.info;
    return PopScope(
      canPop: !info.force && !_busy,
      child: PaperDialog(
        showClose: !info.force && !_busy,
        padding: const EdgeInsets.fromLTRB(22, 38, 22, 22),
        maxWidth: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(c),
            const SizedBox(height: 14),
            _versionCard(c),
            const SizedBox(height: 14),
            _sectionLabel(c, '更新内容'),
            const SizedBox(height: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 168),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (info.notes.isEmpty)
                      _note(c, '修复已知问题，优化使用体验。')
                    else
                      for (final note in info.notes) _note(c, note),
                  ],
                ),
              ),
            ),
            if (info.size > 0 || info.publishedAt != null) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (info.size > 0) _sizeText(info.size),
                  if (info.publishedAt != null) info.publishedAt!,
                ].join(' · '),
                style: context.body(size: 10.5, color: c.inkSoft),
              ),
            ],
            const SizedBox(height: 18),
            _actions(c),
          ],
        ),
      ),
    );
  }

  Widget _header(CitroColors c) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: c.hl,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line2),
          ),
          child: Center(
            child: AppIcon(
              strokeSvg(AppIcons.download, width: 2),
              size: 20,
              color: c.accentInk,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('发现新版本', style: context.heading(size: 20)),
              const SizedBox(height: 2),
              Text(
                'Citro v${widget.info.version}',
                style: context.body(size: 11.5, color: c.inkSoft),
              ),
            ],
          ),
        ),
        if (widget.info.force)
          HandChip(
            '重要更新',
            bg: c.stamp.withAlpha(16),
            color: c.stamp,
            border: Border.all(color: c.stamp.withAlpha(80)),
          ),
      ],
    );
  }

  Widget _versionCard(CitroColors c) {
    final current = widget.installed.version;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Text(
            current.isEmpty ? '当前版本' : '当前 v$current',
            style: context.body(size: 11.5, color: c.inkSoft),
          ),
          const Spacer(),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: c.hl, shape: BoxShape.circle),
            child: Center(
              child: AppIcon(
                strokeSvg(AppIcons.arrowRight, width: 2.2),
                size: 12,
                color: c.accentInk,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '最新 v${widget.info.version}',
            style: context.body(
              size: 12.5,
              weight: FontWeight.w800,
              color: c.accentInk,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(CitroColors c, String text) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: context.body(
            size: 11,
            weight: FontWeight.w800,
            color: c.accentInk,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _note(CitroColors c, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 7, right: 8),
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              text,
              style: context.body(size: 12.5, color: c.ink2, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(CitroColors c) {
    switch (_phase) {
      case _Phase.downloading:
        return _downloading(c);
      case _Phase.permission:
        return _permission(c);
      case _Phase.installing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: c.accent,
              ),
            ),
            const SizedBox(width: 10),
            Text('正在打开系统安装程序…', style: context.body(size: 13, color: c.ink2)),
          ],
        );
      case _Phase.error:
        return _errorActions(c);
      case _Phase.idle:
        return _idleActions(c);
    }
  }

  Widget _idleActions(CitroColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.info.force) ...[
          Text(
            '此版本包含重要更新，完成更新后才能继续使用。',
            style: context.body(size: 11.5, color: c.stamp, height: 1.5),
          ),
          const SizedBox(height: 10),
        ],
        AccentButton(text: '立即更新', onTap: _startDownload),
        if (!widget.info.force) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  text: '稍后',
                  outlined: true,
                  height: 42,
                  onTap: () =>
                      Navigator.of(context).pop(UpdateDialogResult.dismissed),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AccentButton(
                  text: '跳过此版本',
                  outlined: true,
                  height: 42,
                  onTap: _skipVersion,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _downloading(CitroColors c) {
    final pct = _total > 0
        ? (_received * 100 / _total).clamp(0, 100).floor()
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: pct == null ? null : pct / 100,
            minHeight: 8,
            color: c.accent,
            backgroundColor: c.line,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            pct == null ? '正在下载安装包' : '正在下载 $pct%',
            if (_received > 0 && _total > 0)
              '${(_received / (1024 * 1024)).toStringAsFixed(1)} / ${_sizeText(_total)}'
            else if (_received > 0)
              _sizeText(_received),
          ].join(' · '),
          style: context.body(size: 11.5, color: c.inkSoft),
        ),
        const SizedBox(height: 12),
        AccentButton(
          text: '取消下载',
          outlined: true,
          height: 42,
          onTap: _cancelDownload,
        ),
      ],
    );
  }

  Widget _permission(CitroColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Android 需要先允许 Citro 安装应用。授权后回到这里继续安装。',
          style: context.body(size: 11.5, color: c.ink2, height: 1.55),
        ),
        const SizedBox(height: 12),
        AccentButton(text: '去系统设置', onTap: _openSettings),
        const SizedBox(height: 8),
        AccentButton(
          text: '我已允许，继续安装',
          outlined: true,
          height: 42,
          onTap: () => _install(_runId),
        ),
      ],
    );
  }

  Widget _errorActions(CitroColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _error ?? '安装失败，请重试',
          style: context.body(size: 12, color: c.stamp, height: 1.55),
        ),
        const SizedBox(height: 12),
        AccentButton(text: '重试', onTap: _startDownload),
      ],
    );
  }

  Future<void> _startDownload() async {
    final run = ++_runId;
    setState(() {
      _phase = _Phase.downloading;
      _error = null;
      _received = 0;
      _total = widget.info.size;
      _lastPct = -1;
    });

    final client = http.Client();
    _client = client;
    try {
      final directory = await updateDownloadDirectory();
      if (!mounted || run != _runId) return;
      final file = await UpdateDownloader(client: client, directory: directory)
          .download(
            widget.info,
            onProgress: (received, total) {
              if (!mounted || run != _runId) return;
              final pct = total > 0 ? received * 100 ~/ total : -1;
              final now = DateTime.now();
              if (pct == _lastPct &&
                  now.difference(_lastProgressAt) <
                      const Duration(milliseconds: 250)) {
                _received = received;
                _total = total;
                return;
              }
              _lastPct = pct;
              _lastProgressAt = now;
              setState(() {
                _received = received;
                _total = total > 0 ? total : widget.info.size;
              });
            },
          );
      if (!mounted || run != _runId) return;
      _file = file;
      setState(() {
        if (widget.info.size > 0) {
          _received = widget.info.size;
          _total = widget.info.size;
        }
        _phase = _Phase.installing;
      });
      await _install(run);
    } catch (e) {
      if (!mounted || run != _runId) return;
      setState(() {
        _phase = _Phase.error;
        _error = e is UpdateException ? e.message : '下载失败，请检查网络与存储空间';
      });
    } finally {
      if (identical(_client, client)) _client = null;
      client.close();
    }
  }

  Future<void> _install(int run) async {
    final file = _file;
    if (file == null || !mounted || run != _runId) return;
    setState(() {
      _phase = _Phase.installing;
      _error = null;
    });

    final allowed = await UpdateInstaller.canInstall();
    if (!mounted || run != _runId) return;
    if (!allowed) {
      setState(() => _phase = _Phase.permission);
      return;
    }

    final result = await UpdateInstaller.install(file.path);
    if (!mounted || run != _runId) return;
    if (result.status == InstallStatus.started) {
      Navigator.of(context).pop(UpdateDialogResult.installStarted);
    } else if (result.status == InstallStatus.permission) {
      setState(() => _phase = _Phase.permission);
    } else {
      setState(() {
        _phase = _Phase.error;
        _error = result.message ?? '安装失败，请重试';
      });
    }
  }

  void _cancelDownload() {
    _runId++;
    _client?.close();
    _client = null;
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _received = 0;
      _total = widget.info.size;
      _error = null;
    });
  }

  Future<void> _openSettings() async {
    final ok = await UpdateInstaller.openInstallSettings();
    if (!ok && mounted) {
      AppToast.show(context, '请到系统设置中允许 Citro 安装应用');
    }
  }

  Future<void> _skipVersion() async {
    await UpdatePrefs.skip(widget.info.versionCode);
    if (mounted) {
      Navigator.of(context).pop(UpdateDialogResult.dismissed);
    }
  }

  static String _sizeText(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb >= 10
        ? '${mb.toStringAsFixed(0)} MB'
        : '${mb.toStringAsFixed(1)} MB';
  }
}

class _CheckingDialog extends StatelessWidget {
  const _CheckingDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PopScope(
      canPop: false,
      child: PaperDialog(
        showClose: false,
        maxWidth: 300,
        padding: const EdgeInsets.fromLTRB(24, 34, 24, 26),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: c.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '正在检查更新…',
                style: context.body(size: 13.5, color: c.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
