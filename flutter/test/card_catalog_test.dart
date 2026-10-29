import 'package:citro/data/cards.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    await CardCatalog.ensureLoaded();
  });

  test('OBS catalog loads all three folders', () {
    expect(CardCatalog.categories.length, 3);
    expect(CardCatalog.all.length, greaterThan(100));
    expect(CardCatalog.inCategory('cici').length, 30);
    expect(CardCatalog.byId('cici/1'), isNotNull);
    expect(CardCatalog.byId('cici/1')!.url,
        'https://obs.chimu-claw.xyz/card/cici/1.webp');
  });

  test('today card stays stable and transfer rerolls it', () async {
    final state = AppState.instance;
    await Prefs.setStringList(PrefKeys.cardsOwned, const []);
    await Prefs.setString(PrefKeys.cardsToday, null);

    final first = await state.ensureTodayCard();
    final second = await state.ensureTodayCard();
    expect(first, isNotNull);
    expect(second!.id, first!.id);
    expect(state.ownedCards.contains(first.id), isTrue);

    final reroll = await state.redrawTodayCard();
    expect(reroll, isNotNull);
    expect(reroll!.id, isNot(first.id));
    expect(state.todayCardId, reroll.id);
    expect(state.ownedCards.length, 2);
  });

  test('daily routes award limited credits', () async {
    final state = AppState.instance;
    await Prefs.setInt(PrefKeys.cardCredits, 0);
    await Prefs.setString(PrefKeys.cardPostDay, null);

    expect(await state.grantPostCardDraw(), isTrue);
    expect(await state.grantPostCardDraw(), isFalse);
    expect(state.cardCredits, 1);

    await Prefs.setString(PrefKeys.cardGameRounds, null);
    await Prefs.setString(PrefKeys.cardGameDraws, null);
    var awards = 0;
    for (var i = 1; i <= 21; i++) {
      if (await state.noteGameRound()) awards++;
    }
    expect(awards, 2);
  });
}
