import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Web 端性能探针。
///
/// 默认关闭；构建时传 `--dart-define=CITRO_PERF_PROBE=true` 且处于 debug
/// 模式时才记录启动耗时与切页/滚动期间的帧耗时。浏览器无法落盘，结果统一
/// 输出到控制台，便于配合 Chrome DevTools 对比优化前后。
class PerfProbe {
  PerfProbe._();

  static const bool enabled = bool.fromEnvironment('CITRO_PERF_PROBE');
  static final Stopwatch _clock = Stopwatch()..start();
  static final List<FrameTiming> _frames = <FrameTiming>[];
  static bool _collecting = false;

  static void start() {
    if (!enabled || !kDebugMode) return;
    _clock.reset();
    _clock.start();
    debugPrint('CITRO_PERF web_start');
  }

  static void homeReady(void Function(int) switchTab) {
    if (!enabled || !kDebugMode) return;
    debugPrint('CITRO_PERF home_ready_ms=${_clock.elapsedMilliseconds}');
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
      debugPrint(
        'CITRO_PERF $label frames=0 elapsed_ms=${_clock.elapsedMilliseconds}',
      );
      return;
    }
    final totals =
        _frames.map((t) => t.totalSpan.inMicroseconds / 1000.0).toList()
          ..sort();
    final builds =
        _frames.map((t) => t.buildDuration.inMicroseconds / 1000.0).toList()
          ..sort();
    final rasters =
        _frames
            .map((t) => t.rasterDuration.inMicroseconds / 1000.0)
            .toList()
          ..sort();
    double p(List<double> xs, double q) =>
        xs[((xs.length - 1) * q).round().clamp(0, xs.length - 1)];
    final jank = totals.where((t) => t > 16.7).length;
    debugPrint(
      'CITRO_PERF $label frames=${totals.length} '
      'p50=${p(totals, .5).toStringAsFixed(1)}ms '
      'p90=${p(totals, .9).toStringAsFixed(1)}ms '
      'max=${totals.last.toStringAsFixed(1)}ms '
      'buildP50=${p(builds, .5).toStringAsFixed(1)}ms '
      'buildP90=${p(builds, .9).toStringAsFixed(1)}ms '
      'rasterP50=${p(rasters, .5).toStringAsFixed(1)}ms '
      'rasterP90=${p(rasters, .9).toStringAsFixed(1)}ms '
      'jank=$jank',
    );
  }
}