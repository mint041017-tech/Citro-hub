import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'games/game_loader.dart';
import 'calendar/calendar_page.dart';
import 'mbti/mbti_page.dart';
import 'services/platform.dart' as platform;
import 'pages/checkin_scroll_page.dart';
import 'pages/cook_page.dart';
import 'pages/me_page.dart';
import 'pages/play_page.dart';
import 'pages/res_page.dart';
import 'pages/root_shell.dart';
import 'pages/search_page.dart';
import 'pages/sens_page.dart';
import 'ledger/ledger_page.dart';
import 'theme/crisp_page_route.dart';
import 'theme/motion.dart';
import 'tingyu/tingyu_page.dart';
import 'todo/todo_focus.dart';
import 'todo/todo_page.dart';

class CitroRoutes {
  static const home = '/home';
  static const plan = '/plan';
  static const resources = '/res';
  static const games = '/games';
  static const community = '/trash';
  static const cook = '/cook';
  static const me = '/me';
  static const play = '/play';
  static const sens = '/sens';
  static const search = '/search';
  static const tingyu = '/tingyu';
  static const todo = '/todo';
  static const todoFocus = '/todo/focus';
  static const ledger = '/ledger';
  static const calendar = '/calendar';
  static const mbti = '/mbti';
  static const checkinScroll = '/checkin/scroll';

  // Tab 顺序与 RootShell._pageAt 一致：0 首页 / 1 计划 / 2 游戏 / 3 社区 / 4 资源库。
  // 资源库在 Windows 侧栏里是真 Tab，其他端 /res 仍开独立页。
  static const tabs = <String>[home, plan, games, community, resources];
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
        path == plan ||
        path == cook ||
        path == todo ||
        path == todoFocus ||
        path == ledger ||
        path == calendar ||
        path == mbti ||
        path == checkinScroll ||
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

  static Widget pageFor(String? raw, {Object? args}) {
    final route = normalize(raw);
    if (route == todo) {
      return TodoPage(initialTab: args is int ? args : 0);
    }
    if (route == todoFocus) return const TodoFocusPage();
    if (route == ledger) {
      return LedgerPage(initialTab: args is int ? args : 0);
    }
    if (route == calendar) return const CalendarPage();
    if (route == mbti) return const MbtiPage();
    if (route == checkinScroll) {
      return CheckinScrollPage(initialVolume: args is int ? args : null);
    }
    if (route == cook) return const CookPage();
    if (route == me) return const MePage();
    // 资源库：非 Windows 直接开独立页；Windows 落进 RootShell 的第 5 个 Tab
    // （见 CitroRoutes.tabs 与 RootShell._pageAt）。
    if (route == resources && !platform.isWindows) return const ResPage();
    if (route == play) return const PlayPage();
    if (route == sens) return const SensPage();
    if (route == search) return const SearchPage();
    if (route == tingyu) return const TingyuPage();
    if (_games.contains(route)) return buildGamePage(route.substring(1));
    return RootShell(initialIndex: tabs.indexOf(route));
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final route = normalize(settings.name);
    final routeSettings = RouteSettings(
      name: route,
      arguments: settings.arguments,
    );
    // 工具页退场要干净：完整淡出，而不是全站转场那种 18% 淡出后瞬间移除。
    if (route == sens || route == play || route == mbti) {
      return CitroCrispPageRoute<dynamic>(
        settings: routeSettings,
        builder: (_) => pageFor(route, args: settings.arguments),
      );
    }
    return _CitroPageRoute<dynamic>(
      settings: routeSettings,
      builder: (_) => pageFor(route, args: settings.arguments),
    );
  }
}

class _CitroPageRoute<T> extends MaterialPageRoute<T> {
  _CitroPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => kIsWeb || platform.isWindows
      ? CitroMotion.pageDesktop
      : CitroMotion.pageTouch;

  @override
  Duration get reverseTransitionDuration => kIsWeb || platform.isWindows
      ? CitroMotion.pageDesktopReverse
      : CitroMotion.pageTouchReverse;
}
