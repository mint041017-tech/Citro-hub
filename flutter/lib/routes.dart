import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'games/game_loader.dart';
import 'services/platform.dart' as platform;
import 'pages/cook_page.dart';
import 'pages/me_page.dart';
import 'pages/play_page.dart';
import 'pages/root_shell.dart';
import 'pages/search_page.dart';
import 'pages/sens_page.dart';
import 'theme/motion.dart';
import 'tingyu/tingyu_page.dart';

class CitroRoutes {
  static const home = '/home';
  static const resources = '/res';
  static const games = '/games';
  static const community = '/trash';
  static const cook = '/cook';
  static const me = '/me';
  static const play = '/play';
  static const sens = '/sens';
  static const search = '/search';
  static const tingyu = '/tingyu';

  static const tabs = <String>[home, games, community, resources];
  static const _games = <String>{
    '/g2048',
    '/gmem',
    '/gsudoku',
    '/gnono',
    '/gslide',
    '/gsnake',
    '/gsheep',
    '/gjump',
    '/gpeng',
    '/gbrake',
    '/gidiom',
    '/gfeihua',
    '/gliquid',
    '/gknockwater',
  };

  static String normalize(String? raw) {
    var value = (raw ?? '').trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.isEmpty || value == '/') return home;
    if (!value.startsWith('/')) value = '/$value';
    final path = Uri.parse(value).path;
    if (path == '/' || path == home) return home;
    // 异形数独已并入统一数独入口，旧链接直接落到数独模式选择。
    if (path == '/gjigsaw') return '/gsudoku';
    // 网页端已移除资源页，旧链接直接回首页；原生端仍保留资源库。
    if (kIsWeb && path == resources) return home;
    if (tabs.contains(path) ||
        path == cook ||
        path == me ||
        path == play ||
        path == sens ||
        path == search ||
        path == tingyu ||
        _games.contains(path)) {
      return path;
    }
    return home;
  }

  static Widget pageFor(String? raw) {
    final route = normalize(raw);
    if (route == cook) return const CookPage();
    if (route == me) return const MePage();
    if (route == play) return const PlayPage();
    if (route == sens) return const SensPage();
    if (route == search) return const SearchPage();
    if (route == tingyu) return const TingyuPage();
    if (_games.contains(route)) return buildGamePage(route.substring(1));
    return RootShell(initialIndex: tabs.indexOf(route));
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final route = normalize(settings.name);
    return _CitroPageRoute<dynamic>(
      settings: RouteSettings(name: route, arguments: settings.arguments),
      builder: (_) => pageFor(route),
    );
  }
}

class _CitroPageRoute<T> extends MaterialPageRoute<T> {
  _CitroPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration =>
      kIsWeb || platform.isWindows
      ? CitroMotion.pageDesktop
      : CitroMotion.pageTouch;

  @override
  Duration get reverseTransitionDuration =>
      kIsWeb || platform.isWindows
      ? CitroMotion.pageDesktopReverse
      : CitroMotion.pageTouchReverse;
}
