import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// 仅用于本地性能验收：默认关闭，构建时传
/// `--dart-define=CITRO_PERF_PROBE=true` 才自动跑切页/滚动采样。
class PerfProbe {
  PerfProbe._();

  static const bool enabled = bool.fromEnvironment('CITRO_PERF_PROBE');
  static final Stopwatch _clock = Stopwatch()..start();
  static final List<FrameTiming> _frames = <FrameTiming>[];
  static bool _collecting = false;
  static Future<void> _logTail = Future<void>.value();

  static void start() {
    if (!enabled || !kDebugMode) return;
    _clock.reset();
    _clock.start();
    _logTail = _resetLog();
  }

  static void homeReady(void Function(int) switchTab) {
    if (!enabled || !kDebugMode) return;
    unawaited(_log('CITRO_PERF home_ready_ms=${_clock.elapsedMilliseconds}'));
    unawaited(_runAuto(switchTab));
  }

  static Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/citro_perf.log');
  }

  static Future<void> _resetLog() async {
    try {
      await (await _logFile()).writeAsString('', flush: true);
    } catch (_) {}
  }

  static Future<void> _log(String line) {
    final next = _logTail.then((_) async {
      debugPrint(line);
      try {
        await (await _logFile()).writeAsString(
          '$line\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
    });
    _logTail = next.catchError((_) {});
    return next;
  }

  static void beginFrameCollection() {
    if (!enabled || !kDebugMode) return;
    if (_collecting) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    }
    _frames.clear();
    _collecting = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void endFrameCollection(String label) {
    if (!enabled || !kDebugMode || !_collecting) return;
    _collecting = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _report(label);
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (_collecting) _frames.addAll(timings);
  }

  static void _report(String label) {
    if (_frames.isEmpty) {
      unawaited(_log('CITRO_PERF $label frames=0'));
      return;
    }
    final totals =
        _frames.map((t) => t.totalSpan.inMicroseconds / 1000.0).toList()
          ..sort();
    final builds =
        _frames.map((t) => t.buildDuration.inMicroseconds / 1000.0).toList()
          ..sort();
    final rasters =
        _frames.map((t) => t.rasterDuration.inMicroseconds / 1000.0).toList()
          ..sort();
    double p(List<double> xs, double q) =>
        xs[((xs.length - 1) * q).round().clamp(0, xs.length - 1)];
    final jank = totals.where((t) => t > 16.7).length;
    unawaited(
      _log(
        'CITRO_PERF $label frames=${totals.length} '
        'p50=${p(totals, .5).toStringAsFixed(1)}ms '
        'p90=${p(totals, .9).toStringAsFixed(1)}ms '
        'max=${totals.last.toStringAsFixed(1)}ms '
        'buildP50=${p(builds, .5).toStringAsFixed(1)}ms '
        'buildP90=${p(builds, .9).toStringAsFixed(1)}ms '
        'rasterP50=${p(rasters, .5).toStringAsFixed(1)}ms '
        'rasterP90=${p(rasters, .9).toStringAsFixed(1)}ms '
        'jank=$jank',
      ),
    );
  }

  static Future<void> _runAuto(void Function(int) switchTab) async {
    try {
      await _log('CITRO_PERF auto_start');
      await Future<void>.delayed(const Duration(seconds: 1));
      for (final i in <int>[1, 2, 0]) {
        await _log('CITRO_PERF auto_switch_$i');
        switchTab(i);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await _log('CITRO_PERF auto_after_$i');
      }
      beginFrameCollection();
      await _drag();
      endFrameCollection('scroll_home');
      await _log('CITRO_PERF auto_done');
    } catch (e, st) {
      await _log('CITRO_PERF auto_error $e\n$st');
    }
  }

  static Future<void> _drag() async {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    final size = view.physicalSize / view.devicePixelRatio;
    final start = Offset(size.width / 2, size.height * 0.72);
    final binding = GestureBinding.instance;
    const pointer = 9901;
    var position = start;
    binding.handlePointerEvent(
      PointerDownEvent(
        pointer: pointer,
        kind: PointerDeviceKind.touch,
        position: position,
        buttons: kPrimaryButton,
      ),
    );
    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final next = start - Offset(0, size.height * 0.22 * i / 10);
      binding.handlePointerEvent(
        PointerMoveEvent(
          pointer: pointer,
          kind: PointerDeviceKind.touch,
          position: next,
          delta: next - position,
          buttons: kPrimaryButton,
          timeStamp: Duration(milliseconds: 16 * i),
        ),
      );
      position = next;
    }
    binding.handlePointerEvent(
      PointerUpEvent(
        pointer: pointer,
        kind: PointerDeviceKind.touch,
        position: position,
        timeStamp: const Duration(milliseconds: 176),
      ),
    );
  }
}
