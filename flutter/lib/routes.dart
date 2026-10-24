import 'package:flutter/material.dart';

import 'games/game_registry.dart';
import 'pages/cook_page.dart';
import 'pages/me_page.dart';
import 'pages/play_page.dart';
import 'pages/root_shell.dart';
import 'pages/sens_page.dart';

class CitroRoutes {
  static const home = '/home';
  static const resources = '/res';
  static const games = '/games';
  static const community = '/trash';
  static const cook = '/cook';
  static const me = '/me';
  static const play = '/play';
  static const sens = '/sens';

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
  };

  static String normalize(String? raw) {
    var value = (raw ?? '').trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.isEmpty || value == '/') return home;
    if (!value.startsWith('/')) value = '/$value';
    final path = Uri.parse(value).path;
    if (path == '/' || path == home) return home;
    if (tabs.contains(path) ||
        path == cook ||
        path == me ||
        path == play ||
        path == sens ||
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
    if (_games.contains(route)) return buildGamePage(route.substring(1));
    return RootShell(initialIndex: tabs.indexOf(route));
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final route = normalize(settings.name);
    return MaterialPageRoute<dynamic>(
      settings: RouteSettings(name: route, arguments: settings.arguments),
      builder: (_) => pageFor(route),
    );
  }
}
