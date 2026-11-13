import 'package:citro/data/poems.dart';
import 'package:citro/games/game_ui.dart';
import 'package:citro/games/gfeihua.dart';
import 'package:citro/games/gidiom.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget view) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildCitroTheme(CitroColors.light),
  home: view,
);

void main() {
  setUpAll(() => GameScaffold.liveEnabled = false);
  tearDownAll(() => GameScaffold.liveEnabled = true);

  testWidgets('idiom input sends Enter to the enter callback', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final input = TextEditingController();
    var enter = 0;
    var button = 0;
    await tester.pumpWidget(
      _host(
        GameIdiomView(
          phase: IdiomPhase.playing,
          input: input,
          need: 'long',
          onSubmit: () => button++,
          onEnter: () => enter++,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '龙凤呈祥');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(enter, 1);
    expect(button, 0);
    input.dispose();
  });

  testWidgets('feihua input sends Enter to the enter callback', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final input = TextEditingController();
    var enter = 0;
    var button = 0;
    await tester.pumpWidget(
      _host(
        GameFeihuaView(
          phase: FeihuaPhase.playing,
          input: input,
          ch: '月',
          onSubmit: () => button++,
          onEnter: () => enter++,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '举头望明月');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(enter, 1);
    expect(button, 0);
    input.dispose();
  });

  test('飞花令：半句与整句归一化到同一条', () {
    // 词库里存的是整句「床前明月光，疑是地上霜」。玩家只打半句时，
    // 必须归一化到整句，否则 AI 会拿整句来「重复」玩家刚说的那半句。
    expect(canonicalPoemLine('床前明月光'), '床前明月光，疑是地上霜');
    expect(
      canonicalPoemLine('床前明月光，疑是地上霜'),
      '床前明月光，疑是地上霜',
    );
    // 玩家多打了下半句，同样回到词库里的那一联。
    expect(
      canonicalPoemLine('床前明月光，疑是地上霜，举头望明月'),
      '床前明月光，疑是地上霜',
    );
    // 词库外的句子原样返回。
    expect(canonicalPoemLine('词库外的一句'), '词库外的一句');
    // 同一句诗的另一种标点写法也算同一条（词库里确实存在这种重复条目）
    expect(poemKey('床前明月光，疑是地上霜'), poemKey('床前明月光。疑是地上霜'));
    expect(
      canonicalPoemLine('春花秋月何时了？往事知多少'),
      canonicalPoemLine('春花秋月何时了，往事知多少'),
    );
    // 横跨标点打过来也能接上半句
    expect(canonicalPoemLine('明月光疑是'), '床前明月光，疑是地上霜');
    // 词库里同一句诗存在两种标点写法，归一化后必须算同一句，
    // 否则 AI 会换个标点再把同一联接回去。
    final a = '春花秋月何时了，往事知多少';
    final b = '春花秋月何时了？往事知多少';
    expect(poemKey(a), poemKey(b));
    expect(kPoemLines.any((p) => p.line == a), isTrue);
    expect(kPoemLines.any((p) => p.line == b), isTrue);
    expect(canonicalPoemLine(a), canonicalPoemLine(b));
  });

  test('成语接龙：多音字按任意一读都算同音', () {
    // 「乐」的默认读法是 le，但还有 yue 一读；玩家接「月」(yue)
    // 以前会被误判成不同音。
    final le = PinyinHelper.convertToPinyinArray(
      '乐',
      PinyinFormat.WITHOUT_TONE,
    );
    expect(le, containsAll(const ['le', 'yue']));
    expect(
      PinyinHelper.getPinyinE('乐', separator: '', format: PinyinFormat.WITHOUT_TONE),
      'le',
    );
    expect(
      PinyinHelper.convertToPinyinArray('月', PinyinFormat.WITHOUT_TONE),
      const ['yue'],
    );
  });



  testWidgets('飞花令：半句之后整句被算作重复', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'feihua-test'
      ..guestName = '游客';
    await tester.pumpWidget(_host(const GameFeihuaPage()));
    await tester.pump();
    await tester.tap(find.text('开始飞花令'));
    await tester.pump();

    // 从界面读出本局的令字（「令字 X」那个胶囊）
    var ch = '';
    for (final e in find.byType(Text).evaluate()) {
      final t = e.widget as Text;
      final plain = t.data ?? t.textSpan?.toPlainText() ?? '';
      final i = plain.indexOf('令字');
      if (i >= 0 && i + 2 < plain.length) {
        ch = plain.substring(i + 2).trim();
        break;
      }
    }
    expect(ch, isNotEmpty, reason: '应该能从界面读出令字');

    // 取词库里含令字的一句，截出含令字的连续 5 字当「半句」
    final full = kPoemLines.firstWhere((p) => p.line.contains(ch)).line;
    var start = full.indexOf(ch) - 2;
    if (start < 0) start = 0;
    var end = start + 5;
    if (end > full.length) {
      end = full.length;
      start = end - 5;
    }
    final half = full.substring(start, end);
    expect(half, isNot(full), reason: '半句应当比整句短');

    await tester.enterText(find.byType(TextField), half);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    // 归一化命中词库 → 直接收下，不该走 AI 判定
    expect(find.textContaining('AI 判定'), findsNothing);

    // 等 AI 回合跑完
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(seconds: 1));

    // 同一联的整句再交一次，必须被拦下来
    await tester.enterText(find.byType(TextField), full);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('这句已经说过了'), findsOneWidget);
    // 让 120s 倒计时自己走完（_end 会取消定时器），再摘掉页面
    await tester.pump(const Duration(seconds: 130));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
