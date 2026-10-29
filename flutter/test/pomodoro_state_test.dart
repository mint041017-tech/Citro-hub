import 'package:citro/services/pomodoro.dart';
import 'package:citro/services/prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  test('focus completion publishes next mode and waits for the dialog', () async {
    final state = PomodoroState.instance;
    state.ensureInit();
    state.switchMode('focus');
    final before = state.todayCount;

    state.remain = .08;
    state.start();
    expect(state.running, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(state.running, isFalse);
    expect(state.done, isTrue);
    expect(state.todayCount, before + 1);
    final next = state.finished.value;
    expect(next, 'short');

    state.settleFinished();
    expect(state.done, isFalse);
    expect(state.mode, next);
    expect(state.running, isFalse);
    expect(state.remain, state.total.toDouble());
  });
}
