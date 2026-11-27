import 'package:citro/games/gliquid.dart';
import 'package:citro/widgets/lazy_page.dart';
import 'package:citro/pages/me_page.dart';
import 'package:citro/pages/root_shell.dart';
import 'package:citro/routes.dart';
import 'package:citro/theme/crisp_page_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes original web hashes', () {
    expect(CitroRoutes.normalize(null), '/home');
    expect(CitroRoutes.normalize('/'), '/home');
    expect(CitroRoutes.normalize('#/g2048'), '/g2048');
    expect(CitroRoutes.normalize('/gliquid'), '/gliquid');
    expect(CitroRoutes.normalize('#/gknockwater'), '/gknockwater');
    expect(CitroRoutes.normalize('/gjigsaw'), '/gsudoku');
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

  test('玩法抽签使用干净退场路由', () {
    expect(
      CitroRoutes.onGenerateRoute(const RouteSettings(name: '/play')),
      isA<CitroCrispPageRoute<dynamic>>(),
    );
    expect(
      CitroRoutes.onGenerateRoute(const RouteSettings(name: '/play')),
      isA<CitroCrispPageRoute<dynamic>>(),
    );
    expect(
      CitroRoutes.onGenerateRoute(const RouteSettings(name: '/me')),
      isNot(isA<CitroCrispPageRoute<dynamic>>()),
    );
  });

  test('restores secondary pages from routes', () {
    // 美食 / 抽签 / 搜索页都是懒加载壳：点开才拉代码。
    expect(CitroRoutes.pageFor('/cook'), isA<CitroLazyPage>());
    expect(CitroRoutes.pageFor('/me'), isA<MePage>());
    expect(CitroRoutes.pageFor('/play'), isA<CitroLazyPage>());
    expect(CitroRoutes.pageFor('/search'), isA<CitroLazyPage>());
    expect(CitroRoutes.pageFor('/ledger'), isA<CitroLazyPage>());
    expect(CitroRoutes.normalize('/ledger'), '/ledger');
    expect(CitroRoutes.normalize('/tests'), '/tests');
    expect(CitroRoutes.normalize('/kei'), '/kei');
    expect(CitroRoutes.pageFor('/tests'), isA<CitroLazyPage>());
    expect(CitroRoutes.pageFor('/kei'), isA<CitroLazyPage>());
    expect(CitroRoutes.pageFor('/gliquid'), isA<GameLiquidPage>());
  });
}
