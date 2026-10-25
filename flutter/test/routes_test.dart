import 'package:citro/pages/cook_page.dart';
import 'package:citro/pages/me_page.dart';
import 'package:citro/pages/play_page.dart';
import 'package:citro/pages/root_shell.dart';
import 'package:citro/pages/search_page.dart';
import 'package:citro/pages/sens_page.dart';
import 'package:citro/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes original web hashes', () {
    expect(CitroRoutes.normalize(null), '/home');
    expect(CitroRoutes.normalize('/'), '/home');
    expect(CitroRoutes.normalize('#/g2048'), '/g2048');
    expect(CitroRoutes.normalize('games'), '/games');
    expect(CitroRoutes.normalize('/search'), '/search');
    expect(CitroRoutes.normalize('/missing'), '/home');
  });

  test('restores primary tabs from routes', () {
    for (var i = 0; i < CitroRoutes.tabs.length; i++) {
      final page = CitroRoutes.pageFor(CitroRoutes.tabs[i]);
      expect(page, isA<RootShell>());
      expect((page as RootShell).initialIndex, i);
    }
  });

  test('restores secondary pages from routes', () {
    expect(CitroRoutes.pageFor('/cook'), isA<CookPage>());
    expect(CitroRoutes.pageFor('/me'), isA<MePage>());
    expect(CitroRoutes.pageFor('/play'), isA<PlayPage>());
    expect(CitroRoutes.pageFor('/sens'), isA<SensPage>());
    expect(CitroRoutes.pageFor('/search'), isA<SearchPage>());
  });
}
