import 'package:citro/services/models.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    AppState.instance.user = null;
  });

  test('同一台设备换账号，不会接着上一个人抽到的那支签', () async {
    final today = _dayKey(DateTime.now());
    await Prefs.setString(PrefKeys.checkinFortune, '$today:0:甲');

    AppState.instance.user = const User(name: '甲');
    expect(AppState.instance.todayFortuneIdx, 0);

    // 换个人登录：缓存属于上一个账号，应当当作没有，重新向服务端取。
    AppState.instance.user = const User(name: '乙');
    expect(AppState.instance.todayFortuneIdx, isNull);

    // 退回游客同样不接着用。
    AppState.instance.user = null;
    expect(AppState.instance.todayFortuneIdx, isNull);
  });

  test('旧的两段缓存不算数，当天重新取一次', () async {
    final today = _dayKey(DateTime.now());
    await Prefs.setString(PrefKeys.checkinFortune, '$today:0');
    expect(AppState.instance.todayFortuneIdx, isNull);
  });

  test('转运机会也按账号记，换人登录不能白拿', () async {
    final today = _dayKey(DateTime.now());
    AppState.instance.user = const User(name: '甲');
    await Prefs.setString(PrefKeys.checkinFortune, '$today:7:甲');
    await Prefs.setString(PrefKeys.checkinTransfer, '$today:甲');
    await Prefs.setString(PrefKeys.checkinTransferUsed, null);

    expect(AppState.instance.fortuneIsBad, isTrue);
    expect(AppState.instance.fortuneTransferReady, isTrue);

    AppState.instance.user = const User(name: '乙');
    expect(AppState.instance.fortuneIsBad, isFalse);
    expect(AppState.instance.fortuneTransferReady, isFalse);
  });
}
