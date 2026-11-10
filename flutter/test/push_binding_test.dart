import 'package:citro/services/push_binding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activation binds the current account and APNs environment', () async {
    final calls = <Map<String, String>>[];
    final controller = PushBindingCoordinator(
      tokenProvider: () async =>
          (token: 'a'.padLeft(64, 'a'), environment: 'production'),
      bind: (call) async => calls.add(call),
      unbind: (call) async => calls.add(call),
    );

    await controller.setActive(account: 'alice', enabled: true);

    expect(calls, [
      {'account': 'alice', 'token': 'a' * 64, 'environment': 'production'},
    ]);
  });

  test(
    'a slow activation for a previous account cannot bind after switching',
    () async {
      final calls = <Map<String, String>>[];
      final controller = PushBindingCoordinator(
        tokenProvider: () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return (token: 'b'.padLeft(64, 'b'), environment: 'production');
        },
        bind: (call) async => calls.add(call),
        unbind: (call) async => calls.add(call),
      );

      final stale = controller.setActive(account: 'alice', enabled: true);
      await controller.setActive(account: 'bob', enabled: true);
      await stale;

      expect(calls.map((call) => call['account']), ['bob']);
    },
  );

  test(
    'disabling or clearing binds no token and unbinds the active device',
    () async {
      final calls = <Map<String, String>>[];
      final controller = PushBindingCoordinator(
        tokenProvider: () async =>
            (token: 'c'.padLeft(64, 'c'), environment: 'production'),
        bind: (call) async => calls.add(call),
        unbind: (call) async => calls.add(call),
      );
      await controller.setActive(account: 'alice', enabled: true);
      await controller.setActive(account: 'alice', enabled: false);
      await controller.setActive(account: null, enabled: true);

      expect(calls, [
        {'account': 'alice', 'token': 'c' * 64, 'environment': 'production'},
        {'account': 'alice', 'token': 'c' * 64, 'environment': 'production'},
      ]);
    },
  );

  test('a slow bind completes before the later unbind', () async {
    final calls = <Map<String, String>>[];
    final controller = PushBindingCoordinator(
      tokenProvider: () async =>
          (token: 'd'.padLeft(64, 'd'), environment: 'production'),
      bind: (call) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        calls.add(call);
      },
      unbind: (call) async => calls.add(call),
    );

    final activation = controller.setActive(account: 'alice', enabled: true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await controller.setActive(account: 'alice', enabled: false);
    await activation;

    expect(calls.map((call) => call['token']), ['d' * 64, 'd' * 64]);
  });

  test('a replacement token unbinds the old token and binds the new token', () async {
    var token = 'e'.padLeft(64, 'e');
    final calls = <Map<String, String>>[];
    final controller = PushBindingCoordinator(
      tokenProvider: () async =>
          (token: token, environment: 'production'),
      bind: (call) async => calls.add(call),
      unbind: (call) async => calls.add(call),
    );

    await controller.setActive(account: 'alice', enabled: true);
    token = 'f'.padLeft(64, 'f');
    await controller.setActive(account: 'alice', enabled: true);

    expect(calls.map((call) => call['token']), ['e' * 64, 'e' * 64, 'f' * 64]);
  });
}
