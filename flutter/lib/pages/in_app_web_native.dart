import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/links.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

Future<void> openInAppPage(BuildContext context, String url, {String? title}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => InAppWebPage(url: url, title: title),
    ),
  );
}

class InAppWebPage extends StatefulWidget {
  final String url;
  final String? title;

  const InAppWebPage({super.key, required this.url, this.title});

  @override
  State<InAppWebPage> createState() => _InAppWebPageState();
}

class _InAppWebPageState extends State<InAppWebPage> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _loading = true;
  String? _error;

  static const _linkGuard = '''
(function(){
  if (window.__citroLinkGuard) return;
  window.__citroLinkGuard = true;
  var isDownload = function(u){
    return /\\.(exe|zip|7z|apk|msi)(\\?|#|\$)/i.test(String(u || ''));
  };
  var external = function(u){
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('citroDownload', String(u));
    }
  };
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var href = a.href || '';
    if (isDownload(href)) {
      e.preventDefault();
      e.stopPropagation();
      external(href);
      return;
    }
    if (a.target === '_blank') a.target = '_self';
  }, true);
  var open = window.open;
  window.open = function(u){
    if (!u) return null;
    var href = String(u);
    if (isDownload(href)) {
      external(href);
      return null;
    }
    window.location.href = href;
    return null;
  };
})();
''';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final host = Uri.tryParse(widget.url)?.host ?? widget.url;
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
              child: Row(
                children: [
                  _PageButton(
                    icon: AppIcons.arrowLeft,
                    label: '返回',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title?.trim().isNotEmpty == true
                              ? widget.title!.trim()
                              : host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.heading(size: 16, color: c.ink),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          widget.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.body(
                            size: 10.5,
                            color: c.inkSoft.withAlpha(190),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _PageButton(
                    icon: AppIcons.refresh,
                    label: '刷新',
                    onTap: () {
                      setState(() => _error = null);
                      _controller?.reload();
                    },
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 2,
              child: _loading && _error == null
                  ? LinearProgressIndicator(
                      value: _progress > 0 && _progress < 1 ? _progress : null,
                      minHeight: 2,
                      color: c.accent,
                      backgroundColor: c.line.withAlpha(70),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: InAppWebView(
                            initialUrlRequest: URLRequest(
                              url: WebUri(widget.url),
                            ),
                            initialSettings: InAppWebViewSettings(
                              javaScriptEnabled: true,
                              domStorageEnabled: true,
                              mediaPlaybackRequiresUserGesture: false,
                              allowsInlineMediaPlayback: true,
                              supportZoom: true,
                              useShouldOverrideUrlLoading: true,
                              javaScriptCanOpenWindowsAutomatically: false,
                              supportMultipleWindows: false,
                              transparentBackground: false,
                              allowFileAccess: false,
                              allowContentAccess: false,
                            ),
                            onWebViewCreated: (controller) {
                              _controller = controller;
                              controller.addJavaScriptHandler(
                                handlerName: 'citroDownload',
                                callback: (args) async {
                                  final value = args.isEmpty
                                      ? null
                                      : args.first?.toString();
                                  final uri = value == null
                                      ? null
                                      : Uri.tryParse(value);
                                  if (uri == null) return false;
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                  return true;
                                },
                              );
                            },
                            onLoadStart: (_, _) {
                              if (!mounted) return;
                              setState(() {
                                _loading = true;
                                _error = null;
                              });
                            },
                            onProgressChanged: (_, progress) {
                              if (!mounted) return;
                              setState(() {
                                _progress = progress / 100;
                                if (progress >= 100) _loading = false;
                              });
                            },
                            onLoadStop: (controller, _) async {
                              if (!mounted) return;
                              setState(() {
                                _loading = false;
                                _error = null;
                              });
                              try {
                                await controller.evaluateJavascript(
                                  source: _linkGuard,
                                );
                              } catch (_) {}
                            },
                            onReceivedError: (_, request, error) {
                              if (!mounted) return;
                              if (request.isForMainFrame == true) {
                                setState(() {
                                  _error = error.description;
                                  _loading = false;
                                });
                              }
                            },
                            shouldOverrideUrlLoading: (_, action) async {
                              final uri = action.request.url;
                              if (uri == null) {
                                return NavigationActionPolicy.ALLOW;
                              }
                              final value = uri.toString();
                              if (isDownloadLink(value)) {
                                await launchUrl(
                                  Uri.parse(value),
                                  mode: LaunchMode.externalApplication,
                                );
                                return NavigationActionPolicy.CANCEL;
                              }
                              final scheme = uri.scheme.toLowerCase();
                              if (scheme != 'http' &&
                                  scheme != 'https' &&
                                  scheme != 'about' &&
                                  scheme != 'blob' &&
                                  scheme != 'data') {
                                await launchUrl(
                                  Uri.parse(value),
                                  mode: LaunchMode.externalApplication,
                                );
                                return NavigationActionPolicy.CANCEL;
                              }
                              return NavigationActionPolicy.ALLOW;
                            },
                          ),
                        ),
                        if (_loading && _error == null)
                          Positioned.fill(
                            child: ColoredBox(
                              color: c.surface,
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
                          ),
                        if (_error != null)
                          Positioned.fill(
                            child: ColoredBox(
                              color: c.surface,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '页面没有加载出来',
                                        style: context.heading(
                                          size: 18,
                                          color: c.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _error!,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: context.body(
                                          size: 11.5,
                                          color: c.inkSoft,
                                          height: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      AccentButton(
                                        text: '重试',
                                        onTap: () {
                                          setState(() {
                                            _error = null;
                                            _loading = true;
                                          });
                                          _controller?.reload();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _PageButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.line),
            boxShadow: CitroColors.shadows.paper(c),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(strokeSvg(icon, width: 2.2), size: 15, color: c.ink2),
              const SizedBox(width: 3),
              Text(
                label,
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
    );
  }
}
