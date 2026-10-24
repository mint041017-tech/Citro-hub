import 'dart:convert';

import 'prefs.dart';

class FishConfig {
  List<int> rest;
  String start;
  String end;
  String? breakStart;
  String? breakEnd;
  FishConfig({
    this.rest = const [0, 6],
    this.start = '09:00',
    this.end = '18:00',
    this.breakStart,
    this.breakEnd,
  });

  factory FishConfig.fromJson(Map<String, dynamic> j) => FishConfig(
    rest:
        (j['rest'] as List?)?.map((e) => int.tryParse('$e') ?? 0).toList() ??
        const [0, 6],
    start: '${j['start'] ?? '09:00'}',
    end: '${j['end'] ?? '18:00'}',
    breakStart: j['breakStart']?.toString(),
    breakEnd: j['breakEnd']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'rest': rest,
    'start': start,
    'end': end,
    'breakStart': breakStart,
    'breakEnd': breakEnd,
  };

  static FishConfig load() {
    final raw = Prefs.getString(PrefKeys.fishConfig);
    if (raw != null) {
      try {
        return FishConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    return FishConfig();
  }

  Future<void> save() async {
    await Prefs.setString(PrefKeys.fishConfig, jsonEncode(toJson()));
  }
}

class FishInfo {
  final String type; // holiday | makeup | rest | work
  final String name;
  final int idx;
  final int total;
  final int? nextRest;
  const FishInfo(
    this.type, {
    this.name = '',
    this.idx = 0,
    this.total = 0,
    this.nextRest,
  });
}

class FishState {
  // 法定节假日（2026，与站点 FISH_OFF 同源）
  static const _holidays = [
    ('元旦', '2026-01-01', '2026-01-03'),
    ('春节', '2026-02-15', '2026-02-22'),
    ('清明', '2026-04-04', '2026-04-06'),
    ('劳动节', '2026-05-01', '2026-05-05'),
    ('端午', '2026-06-19', '2026-06-21'),
    ('中秋', '2026-09-25', '2026-09-27'),
    ('国庆', '2026-10-01', '2026-10-07'),
  ];
  static const _makeup = [
    '2026-02-14',
    '2026-02-28',
    '2026-05-09',
    '2026-10-10',
  ];

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static FishInfo info(DateTime now, FishConfig cfg) {
    final ds = dateKey(now);
    for (final h in _holidays) {
      if (ds.compareTo(h.$2) >= 0 && ds.compareTo(h.$3) <= 0) {
        final start = DateTime.parse(h.$2);
        final end = DateTime.parse(h.$3);
        return FishInfo(
          'holiday',
          name: h.$1,
          idx: now.difference(start).inDays + 1,
          total: end.difference(start).inDays + 1,
        );
      }
    }
    if (_makeup.contains(ds)) return FishInfo('makeup');
    if (cfg.rest.contains(now.weekday % 7)) return FishInfo('rest');
    return FishInfo('work');
  }

  static int? nextRest(DateTime now, FishConfig cfg) {
    for (var i = 1; i <= 366; i++) {
      final t = info(DateTime(now.year, now.month, now.day + i), cfg).type;
      if (t == 'rest' || t == 'holiday') return i;
    }
    return null;
  }

  static int minutes(String t) {
    final p = t.split(':');
    return (int.tryParse(p.first) ?? 0) * 60 +
        (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  static String chipText(DateTime now, FishConfig cfg) {
    final inf = info(now, cfg);
    if (inf.type == 'holiday') return '${inf.name}假期中';
    if (inf.type == 'makeup') {
      final n = nextRest(now, cfg);
      return '补班中 😩${n != null ? ' · 距休息日 $n 天' : ''}';
    }
    if (inf.type == 'work') {
      final nowM = now.hour * 60 + now.minute;
      final inBreak =
          cfg.breakStart != null &&
          cfg.breakEnd != null &&
          nowM >= minutes(cfg.breakStart!) &&
          nowM < minutes(cfg.breakEnd!);
      final inWork =
          nowM >= minutes(cfg.start) && nowM < minutes(cfg.end) && !inBreak;
      final n = nextRest(now, cfg);
      return '${inWork ? '摸鱼中' : '休息中'}${n != null ? ' · 距休息日 $n 天' : ''}';
    }
    return '休息中';
  }

  static (double, double, bool) progress(DateTime now, FishConfig cfg) {
    final nowM = now.hour * 60 + now.minute;
    var startM = minutes(cfg.start), endM = minutes(cfg.end);
    var segs = [(startM, endM)];
    var inBreak = false;
    if (cfg.breakStart != null && cfg.breakEnd != null) {
      final bs = minutes(cfg.breakStart!), be = minutes(cfg.breakEnd!);
      if (bs >= startM && be <= endM && bs < be) {
        if (nowM >= bs && nowM < be) inBreak = true;
        segs = [
          (startM, bs < endM ? bs : endM),
          (be > startM ? be : startM, endM),
        ]..removeWhere((s) => s.$2 <= s.$1);
      }
    }
    var total = 0, elapsed = 0;
    for (final s in segs) {
      total += s.$2 - s.$1;
      elapsed += (nowM.clamp(s.$1, s.$2) - s.$1).clamp(0, s.$2 - s.$1);
    }
    final pct = total > 0 ? (elapsed / total * 100).clamp(0, 100) : 0.0;
    return (pct.toDouble(), total.toDouble(), inBreak);
  }
}

class FishStateView {
  static String get chipText =>
      FishState.chipText(DateTime.now(), FishConfig.load());
}
