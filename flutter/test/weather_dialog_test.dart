import 'package:citro/overlays/weather_sheet.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => AppScope(
  state: AppState.instance,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: child,
  ),
);

Widget _opener(String label, void Function(BuildContext) onTap) => Builder(
  builder: (ctx) => Scaffold(
    body: Center(
      child: TextButton(onPressed: () => onTap(ctx), child: Text(label)),
    ),
  ),
);

void main() {
  testWidgets('城市选择：显示当前城市、热门城市，选中后立即生效', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(_opener('open-picker', (ctx) => showCityPickerDialog(ctx))),
    );
    await tester.tap(find.text('open-picker'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('修改城市'), findsOneWidget);
    expect(find.textContaining('当前：'), findsOneWidget);
    expect(find.text('使用当前定位'), findsOneWidget);
    expect(find.text('热门城市'), findsOneWidget);
    expect(find.text('北京'), findsWidgets);

    await tester.tap(find.text('北京').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));

    // 选完立刻写进状态，不等天气接口回来。
    expect(AppState.instance.weatherCity, '北京');
    expect(AppState.instance.weather.city, '北京');
    expect(find.text('修改城市'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('天气详情：打开时无数据也不会在 build 期间刷新状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(_opener('open-weather', (ctx) => showWeatherDialog(ctx))),
    );
    await tester.tap(find.text('open-weather'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('天气详情'), findsOneWidget);
    expect(find.text('定位并刷新'), findsOneWidget);
    expect(find.text('修改城市'), findsOneWidget);

    await tester.pump(const Duration(seconds: 12));
  });
}
