import 'platform.dart' as platform;
import 'prefs.dart';

/// 每天在游戏里花的时间：轻量记在本地，复盘时用来判断是不是玩太久耽误了任务。
class PlayLog {
  PlayLog._();

  static const _key = 'citro_play_seconds_v1';

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int secondsOn(DateTime day) {
    final raw = Prefs.getString(_key);
    if (raw == null || raw.isEmpty) return 0;
    final parts = raw.split(':');
    if (parts.length != 2) return 0;
    if (parts[0] != _dayKey(day)) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  static int minutesOn(DateTime day) => (secondsOn(day) / 60).round();

  /// 记录一段游戏时长；跨天会自动从新的一天重新计。
  static void add(Duration span) {
    if (span.inSeconds <= 0) return;
    // 测试环境不写盘，避免留下未完成的平台通道调用。
    if (platform.isTest) return;
    final today = DateTime.now();
    final base = secondsOn(today);
    Prefs.setString(_key, '${_dayKey(today)}:${base + span.inSeconds}');
  }
}
