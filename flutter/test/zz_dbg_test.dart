import 'package:citro/services/prefs.dart';
import 'package:citro/widgets/home_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });
  test('debug moves', () {
    final store = HomeLayoutStore.instance;
    for (final target in [0, 3, 6, 9]) {
      store.reset(HomeLayoutKey.widePortrait);
      final ok = store.move(HomeLayoutKey.widePortrait, HomeCardId.fish, target, 0);
      final slots = store.slots(HomeLayoutKey.widePortrait);
      final overlaps = <String>[];
      for (final s in slots) {
        for (final o in slots) {
          if (o.key != s.key && s.overlaps(o)) overlaps.add('${s.id}x${o.id}');
        }
      }
      // ignore: avoid_print
      print('target=$target ok=$ok overlaps=$overlaps')
      ;
    }
  });
}
