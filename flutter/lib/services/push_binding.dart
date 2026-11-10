import 'dart:async';

typedef PushToken = ({String token, String environment});
typedef PushCall = Future<void> Function(Map<String, String> call);

final class PushBindingCoordinator {
  final Future<PushToken?> Function() tokenProvider;
  final PushCall bind;
  final PushCall unbind;
  Future<void> _queue = Future<void>.value();
  int _generation = 0;
  String? _activeAccount;
  PushToken? _activeToken;

  PushBindingCoordinator({
    required this.tokenProvider,
    required this.bind,
    required this.unbind,
  });

  Future<void> setActive({required String? account, required bool enabled}) {
    final generation = ++_generation;
    final operation = _queue.then(
      (_) => _setActive(
        generation: generation,
        account: account,
        enabled: enabled,
      ),
    );
    _queue = operation.then((_) {}, onError: (_) {});
    return operation;
  }

  Future<void> _setActive({
    required int generation,
    required String? account,
    required bool enabled,
  }) async {
    final target = account?.trim();
    if (target == null || target.isEmpty || !enabled) {
      final previous = _activeAccount;
      final previousToken = _activeToken;
      if (generation != _generation ||
          previous == null ||
          previousToken == null) {
        return;
      }
      await unbind(_call(previous, previousToken));
      _activeAccount = null;
      _activeToken = null;
      return;
    }

    final pushToken = await tokenProvider();
    if (generation != _generation || pushToken == null) return;
    if (_activeToken != null && _activeToken != pushToken) {
      await unbind(_call(_activeAccount!, _activeToken!));
      _activeAccount = null;
      _activeToken = null;
      if (generation != _generation) return;
    }
    await bind(_call(target, pushToken));
    _activeAccount = target;
    _activeToken = pushToken;
  }

  Map<String, String> _call(String account, PushToken pushToken) => {
    'account': account,
    'token': pushToken.token,
    'environment': pushToken.environment,
  };
}
