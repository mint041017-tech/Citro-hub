import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'games/game_loader.dart';
import 'services/platform.dart' as platform;
import 'pages/me_page.dart';
import 'pages/res_page.dart';
import 'pages/root_shell.dart';
import 'theme/crisp_page_route.dart';
import 'theme/motion.dart';
import 'widgets/lazy_page.dart';

// 非首屏页面全部 deferred：不进 main.dart.js，第一次打开时才下载代码分片。
// 首页 / 计划 / 游戏 / 社区 / 资源库这五个 Tab 是静态导入（RootShell 里直接用），
// 保证切 Tab 零等待。前缀统一带 Lib 后缀，避免和下面的路由常量同名。
import 'calendar/calendar_page.dart' deferred as calendarLib;
import 'mbti/mbti_page.dart' deferred as mbtiLib;
import 'assessments/tests_hub_page.dart' deferred as testsHubLib;
import 'kei/kei_page.dart' deferred as keiLib;
import 'pages/checkin_scroll_page.dart' deferred as checkinLib;
import 'pages/cook_page.dart' deferred as cookLib;
import 'pages/play_page.dart' deferred as playLib;
import 'pages/search_page.dart' deferred as searchLib;
import 'ledger/ledger_page.dart' deferred as ledgerLib;
import 'tingyu/tingyu_page.dart' deferred as tingyuLib;
import 'todo/todo_focus.dart' deferred as todoFocusLib;
import 'todo/todo_page.dart' deferred as todoLib;

class CitroRoutes {
  static const home = '/home';
  static const plan = '/plan';
  static const resources = '/res';
  static const games = '/games';
  static const community = '/trash';
  static const cook = '/cook';
  static const me = '/me';
  static const play = '/play';
  static const search = '/search';
  static const tingyu = '/tingyu';
  static const todo = '/todo';
  static const todoFocus = '/todo/focus';
  static const ledger = '/ledger';
  static const calendar = '/calendar';
  static const mbti = '/mbti';
  static const tests = '/tests';
  static const kei = '/kei';
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
        path == cook ||
        path == todo ||
        path == todoFocus ||
        path == ledger ||
        path == calendar ||
        path == mbti ||
        path == tests ||
        path == kei ||
        path == checkinScroll ||
        path == me ||
        path == play ||
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
      final tab = args is int ? args : 0;
      return CitroLazyPage(
        load: () async {
          await todoLib.loadLibrary();
          return todoLib.TodoPage(initialTab: tab);
        },
      );
    }
    if (route == todoFocus) {
      return CitroLazyPage(
        load: () async {
          await todoFocusLib.loadLibrary();
          return todoFocusLib.TodoFocusPage();
        },
      );
    }
    if (route == ledger) {
      final tab = args is int ? args : 0;
      return CitroLazyPage(
        load: () async {
          await ledgerLib.loadLibrary();
          return ledgerLib.LedgerPage(initialTab: tab);
        },
      );
    }
    if (route == calendar) {
      return CitroLazyPage(
        load: () async {
          await calendarLib.loadLibrary();
          return calendarLib.CalendarPage();
        },
      );
    }
    if (route == mbti) {
      return CitroLazyPage(
        load: () async {
          await mbtiLib.loadLibrary();
          return mbtiLib.MbtiPage();
        },
      );
    }
    if (route == tests) {
      return CitroLazyPage(
        load: () async {
          await testsHubLib.loadLibrary();
          return testsHubLib.TestsHubPage();
        },
      );
    }
    if (route == kei) {
      return CitroLazyPage(
        load: () async {
          await keiLib.loadLibrary();
          return keiLib.KeiPage();
        },
      );
    }
    if (route == checkinScroll) {
      final volume = args is int ? args : null;
      return CitroLazyPage(
        load: () async {
          await checkinLib.loadLibrary();
          return checkinLib.CheckinScrollPage(initialVolume: volume);
        },
      );
    }
    if (route == cook) {
      return CitroLazyPage(
        load: () async {
          await cookLib.loadLibrary();
          return cookLib.CookPage();
        },
      );
    }
    if (route == me) return const MePage();
    // 资源库：非 Windows 直接开独立页；Windows 落进 RootShell 的第 5 个 Tab
    // （见 CitroRoutes.tabs 与 RootShell._pageAt）。
    if (route == resources && !platform.isWindows) return const ResPage();
    if (route == play) {
      return CitroLazyPage(
        load: () async {
          await playLib.loadLibrary();
          return playLib.PlayPage();
        },
      );
    }
    if (route == search) {
      return CitroLazyPage(
        load: () async {
          await searchLib.loadLibrary();
          return searchLib.SearchPage();
        },
      );
    }
    if (route == tingyu) {
      return CitroLazyPage(
        load: () async {
          await tingyuLib.loadLibrary();
          return tingyuLib.TingyuPage();
        },
      );
    }
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
    if (route == play || route == mbti || route == tests || route == kei) {
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
