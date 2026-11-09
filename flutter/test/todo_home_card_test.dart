import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/todo/todo_store.dart';
import 'package:citro/widgets/todo_home_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => AppScope(
  state: AppState.instance,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildCitroTheme(CitroColors.light),
    home: Scaffold(body: Center(child: child)),
  ),
);

Future<void> _pumpCard(WidgetTester tester, Size size) async {
  await tester.pumpWidget(
    _host(
      SizedBox(
        width: size.width,
        height: size.height,
        child: const TodoHomeCard(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final store = TodoStore.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    // 直接使用内存数据，避免异步 _save 在测试之间把旧任务写回缓存。
    store.resetForTest();
    final now = DateTime.now();
    store.createTask(
      title: '写周报',
      categoryId: 'work',
      listId: 'default',
      dueAt: DateTime(now.year, now.month, now.day, 18),
    );
    final doing = store.createTask(
      title: '整理房间',
      categoryId: 'health',
      listId: 'default',
      dueAt: DateTime(now.year, now.month, now.day, 20),
    );
    doing.doing = true;
    store.updateTask(doing);
    store.createTask(title: '读二十页书', categoryId: 'study', listId: 'default');
    final done = store.createTask(
      title: '喝水',
      categoryId: 'health',
      listId: 'default',
    );
    done.done = true;
    store.updateTask(done);
  });

  testWidgets('3×2 小卡显示剩余、完成率和专注信息', (tester) async {
    await _pumpCard(tester, const Size(180, 96));
    expect(tester.takeException(), isNull);
    expect(find.text('待办'), findsOneWidget);
    expect(find.textContaining('件'), findsWidgets);
  });

  testWidgets('标准档显示任务与三枚指标块', (tester) async {
    await _pumpCard(tester, const Size(300, 180));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('专注'), findsWidgets);
    expect(find.textContaining('连续'), findsOneWidget);
    expect(find.textContaining('本周'), findsOneWidget);
    expect(find.text('写周报'), findsOneWidget);
  });

  testWidgets('大卡自动列出更多任务，进行中带标记', (tester) async {
    await _pumpCard(tester, const Size(520, 230));
    expect(tester.takeException(), isNull);
    expect(find.text('整理房间'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.textContaining('本周'), findsOneWidget);
  });

  testWidgets('宽卡与极窄小卡都不溢出', (tester) async {
    await _pumpCard(tester, const Size(260, 108));
    expect(tester.takeException(), isNull);
    await _pumpCard(tester, const Size(160, 104));
    expect(tester.takeException(), isNull);
    await _pumpCard(tester, const Size(360, 144));
    expect(tester.takeException(), isNull);
  });
}
