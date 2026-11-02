import 'package:web/web.dart' as web;

String? currentWebRoute() {
  final fragment = Uri.base.fragment.trim();
  return fragment.isEmpty ? null : fragment;
}

/// 原地切换 Tab 时同步地址栏（不新增历史条目）。
///
/// 四端共用一套壳内切换，Web 只把当前 Tab 写回 hash，
/// 这样刷新/分享仍能落到同一页，而切换本身不再走整页路由跳转。
void syncWebRoute(String route) {
  final value = route.startsWith('/') ? route : '/$route';
  final target = '#$value';
  final location = web.window.location;
  if (location.hash == target) return;
  try {
    web.window.history.replaceState(null, '', target);
  } catch (_) {}
}
