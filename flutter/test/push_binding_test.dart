import 'dart:async';

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

  test(
    'a replacement token unbinds the old token and binds the new token',
    () async {
      var token = 'e'.padLeft(64, 'e');
      final calls = <Map<String, String>>[];
      final controller = PushBindingCoordinator(
        tokenProvider: () async => (token: token, environment: 'production'),
        bind: (call) async => calls.add(call),
        unbind: (call) async => calls.add(call),
      );

      await controller.setActive(account: 'alice', enabled: true);
      token = 'f'.padLeft(64, 'f');
      await controller.setActive(account: 'alice', enabled: true);

      expect(calls.map((call) => call['token']), [
        'e' * 64,
        'e' * 64,
        'f' * 64,
      ]);
    },
  );
  test('failed unbind retains the token for a later retry', () async {
    final attempts = <String>[];
    final controller = PushBindingCoordinator(
      tokenProvider: () async => (token: 'a' * 64, environment: 'production'),
      bind: (_) async {},
      unbind: (call) async {
        attempts.add(call['token']!);
        if (attempts.length == 1) throw StateError('offline');
      },
    );
    await controller.setActive(account: 'alice', enabled: true);
    await expectLater(
      controller.setActive(account: 'alice', enabled: false),
      throwsStateError,
    );
    await controller.setActive(account: 'alice', enabled: false);
    expect(attempts, ['a' * 64, 'a' * 64]);
  });

  test(
    'a superseded disable does not lose the token needed for cleanup',
    () async {
      final calls = <String>[];
      final controller = PushBindingCoordinator(
        tokenProvider: () async => (token: 'a' * 64, environment: 'production'),
        bind: (_) async {},
        unbind: (call) async => calls.add(call['token']!),
      );
      await controller.setActive(account: 'alice', enabled: true);
      final first = controller.setActive(account: null, enabled: false);
      final second = controller.setActive(account: null, enabled: false);
      await Future.wait([first, second]);
      expect(calls, ['a' * 64]);
    },
  );

  test(
    'failed replacement unbind retains the original account for retry',
    () async {
      var token = 'a' * 64;
      final attempts = <Map<String, String>>[];
      final controller = PushBindingCoordinator(
        tokenProvider: () async => (token: token, environment: 'production'),
        bind: (_) async {},
        unbind: (call) async {
          attempts.add(call);
          if (attempts.length == 1) throw StateError('offline');
        },
      );
      await controller.setActive(account: 'alice', enabled: true);
      token = 'b' * 64;
      await expectLater(
        controller.setActive(account: 'bob', enabled: true),
        throwsStateError,
      );
      await controller.setActive(account: null, enabled: false);
      expect(attempts.map((call) => call['account']), ['alice', 'alice']);
      expect(attempts.map((call) => call['token']), ['a' * 64, 'a' * 64]);
    },
  );

  test('logout cancels an activation waiting for a token', () async {
    final token = Completer<PushToken?>();
    final requested = Completer<void>();
    final calls = <String>[];
    final controller = PushBindingCoordinator(
      tokenProvider: () {
        requested.complete();
        return token.future;
      },
      bind: (_) async => calls.add('bind'),
      unbind: (_) async => calls.add('unbind'),
    );
    final activation = controller.setActive(account: 'alice', enabled: true);
    await requested.future;
    final logout = controller.setActive(account: null, enabled: false);
    token.complete((token: 'a' * 64, environment: 'production'));
    await Future.wait([activation, logout]);
    expect(calls, isEmpty);
  });

  test('logout unbinds after an already started bind completes', () async {
    final started = Completer<void>();
    final finish = Completer<void>();
    final calls = <String>[];
    final controller = PushBindingCoordinator(
      tokenProvider: () async => (token: 'a' * 64, environment: 'production'),
      bind: (_) async {
        started.complete();
        await finish.future;
        calls.add('bind');
      },
      unbind: (_) async => calls.add('unbind'),
    );
    final activation = controller.setActive(account: 'alice', enabled: true);
    await started.future;
    final logout = controller.setActive(account: null, enabled: false);
    finish.complete();
    await Future.wait([activation, logout]);
    expect(calls, ['bind', 'unbind']);
  });
}
