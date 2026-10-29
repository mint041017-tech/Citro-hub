import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/tingyu/tingyu_controller_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance
      ..gid = 'tingyu-controller-test'
      ..guestName = '游客·听隅控制器';
  });

  test('native controller loads mix, timer, volume and favorites', () async {
    final c = NookController.instance;
    await c.initialize();
    expect(c.ready, isTrue);

    expect(
      await c.send('load', {
        'tracks': [
          {'id': 'rain', 'volume': 60},
          {'id': 'brown', 'volume': 20},
        ],
        'title': '测试混音',
        'autoplay': false,
      }),
      isTrue,
    );
    expect(c.tracks.length, 2);
    expect(c.title, '测试混音');
    c.markLoaded();
    expect(c.dirty, isFalse);

    expect(
      await c.send('volume', {'id': 'rain', 'value': 40}),
      isTrue,
    );
    expect(c.dirty, isTrue);

    expect(
      await c.send('timer', {'seconds': 60, 'fadeSeconds': 10}),
      isTrue,
    );
    expect(c.timerStatus, 'armed');
    expect(c.timerDuration, 60);

    expect(c.saveFavorite('测试收藏'), isTrue);
    expect(c.favorites.any((f) => f['name'] == '测试收藏'), isTrue);

    expect(await c.send('cancelTimer'), isTrue);
    expect(c.hasTimer, isFalse);
  });
}
