const String _initialRoute = String.fromEnvironment('CITRO_INITIAL_ROUTE');

/// 桌面/移动端没有 URL。本地验收时可用
/// `--dart-define=CITRO_INITIAL_ROUTE=/gliquid` 直接进入指定页面；
/// 未传时仍然从首页启动。
String? currentWebRoute() => _initialRoute.isEmpty ? null : _initialRoute;
