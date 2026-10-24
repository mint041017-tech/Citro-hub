import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/lunar.dart';
import 'api.dart';

class LanternWindow {
  final String date;
  final DateTime start;
  final DateTime end;

  const LanternWindow({
    required this.date,
    required this.start,
    required this.end,
  });

  String get closedAfter {
    final chinaEnd = end.toUtc().add(const Duration(hours: 8));
    return '${LanternApi.dayKey(chinaEnd)} 03:00';
  }

  String get welcomeDeadline {
    final chinaEnd = end.toUtc().add(const Duration(hours: 8));
    return '${chinaEnd.month}月${chinaEnd.day}日 03:00';
  }
}

class LanternSolver {
  final String name;
  final int timestamp;

  const LanternSolver({required this.name, this.timestamp = 0});

  factory LanternSolver.fromJson(Map<String, dynamic> json) => LanternSolver(
    name: '${json['name'] ?? ''}',
    timestamp: _asInt(json['ts']),
  );
}

class LanternRiddle {
  final int id;
  final String question;
  final List<LanternSolver> solvers;

  const LanternRiddle({
    required this.id,
    required this.question,
    this.solvers = const [],
  });

  factory LanternRiddle.fromJson(Map<String, dynamic> json) => LanternRiddle(
    id: _asInt(json['id']),
    question: '${json['q'] ?? ''}',
    solvers: _asList(json['solvers'])
        .whereType<Map>()
        .map((item) => LanternSolver.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
  );
}

class LanternBoardEntry {
  final String name;
  final double score;
  final int solvedCount;
  final int bonus;

  const LanternBoardEntry({
    required this.name,
    required this.score,
    this.solvedCount = 0,
    this.bonus = 0,
  });

  factory LanternBoardEntry.fromJson(Map<String, dynamic> json) =>
      LanternBoardEntry(
        name: '${json['name'] ?? ''}',
        score: _asDouble(json['score']),
        solvedCount: _asInt(json['solvedCount']),
        bonus: _asInt(json['bonus']),
      );
}

class LanternEmojiCurrent {
  final int id;
  final String emoji;

  const LanternEmojiCurrent({required this.id, required this.emoji});
}

class LanternEmojiState {
  final LanternEmojiCurrent? current;
  final Set<int> solved;
  final int total;
  final double score;

  const LanternEmojiState({
    this.current,
    this.solved = const {},
    this.total = 30,
    this.score = 0,
  });

  factory LanternEmojiState.fromJson(Map<String, dynamic> json) {
    final current = json['current'];
    return LanternEmojiState(
      current: current is Map
          ? LanternEmojiCurrent(
              id: _asInt(current['id']),
              emoji: '${current['emoji'] ?? ''}',
            )
          : null,
      solved: _asList(json['solved']).map(_asInt).toSet(),
      total: _asInt(json['total'], fallback: 30),
      score: _asDouble(json['score']),
    );
  }
}

class LanternSnapshot {
  final String date;
  final bool open;
  final bool midAutumn;
  final String closedAfter;
  final List<LanternRiddle> riddles;
  final List<LanternBoardEntry> board;
  final String? meName;
  final Set<int> meSolved;
  final double meScore;
  final LanternEmojiState? emoji;

  const LanternSnapshot({
    required this.date,
    required this.open,
    required this.midAutumn,
    required this.closedAfter,
    required this.riddles,
    required this.board,
    this.meName,
    this.meSolved = const {},
    this.meScore = 0,
    this.emoji,
  });

  factory LanternSnapshot.fromJson(Map<String, dynamic> json) {
    final me = json['me'];
    final emoji = json['emoji'];
    return LanternSnapshot(
      date: '${json['date'] ?? ''}',
      open: json['open'] == true,
      midAutumn: json['midAutumn'] == true,
      closedAfter: '${json['closedAfter'] ?? '次日 03:00'}',
      riddles: _asList(json['riddles'])
          .whereType<Map>()
          .map(
            (item) => LanternRiddle.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      board: _asList(json['board'])
          .whereType<Map>()
          .map(
            (item) =>
                LanternBoardEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      meName: me is Map ? '${me['name'] ?? ''}' : null,
      meSolved: me is Map
          ? _asList(me['solved']).map(_asInt).toSet()
          : const {},
      meScore: me is Map ? _asDouble(me['score']) : 0,
      emoji: emoji is Map
          ? LanternEmojiState.fromJson(Map<String, dynamic>.from(emoji))
          : null,
    );
  }
}

/// 中秋灯谜独立服务：沿用 Api.base 与 X-Trash-Token，不改动通用 Api。
class LanternApi {
  static final http.Client _client = http.Client();

  static const List<LanternRiddle> fallbackRiddles = [
    LanternRiddle(id: 1, question: '十五的月亮（打一成语）'),
    LanternRiddle(id: 2, question: '中秋赏菊（打一成语）'),
    LanternRiddle(id: 3, question: '举头望明月（打一中药名）'),
    LanternRiddle(id: 4, question: '广寒宫中伴嫦娥（打一动物）'),
    LanternRiddle(id: 5, question: '圆圆甜饼香又甜，中秋家家都尝鲜（打一食物）'),
    LanternRiddle(id: 6, question: '夜空挂银盘，十五圆又满（打一天体）'),
    LanternRiddle(id: 7, question: '云盖中秋月（打一字）'),
    LanternRiddle(id: 8, question: '中秋去旅游（打一成语）'),
    LanternRiddle(id: 9, question: '八月十五的月亮（打一山西地名）'),
    LanternRiddle(id: 10, question: '嫦娥的居所（打一神话地名）'),
    LanternRiddle(id: 11, question: '中秋桂下叙家常（打一成语）'),
    LanternRiddle(id: 12, question: '十五天（打一字）'),
    LanternRiddle(id: 13, question: '掬水月在手（打一成语）'),
    LanternRiddle(id: 14, question: '八月十五分月饼（打一成语）'),
    LanternRiddle(id: 15, question: '中秋国庆传捷报（打一成语）'),
    LanternRiddle(id: 16, question: '中秋结伴去出游（打一旅游名词）'),
    LanternRiddle(id: 17, question: '中秋过后又重阳（打一俗语）'),
    LanternRiddle(id: 18, question: '嫦娥奔月（打一成语）'),
    LanternRiddle(id: 19, question: '中秋家家庆团圆（打一成语）'),
    LanternRiddle(id: 20, question: '月有阴晴圆缺（打一财经名词）'),
    LanternRiddle(id: 21, question: '一轮明月照窗前（打一礼貌用语）'),
    LanternRiddle(id: 22, question: '广寒宫的桂树（打一成语）'),
    LanternRiddle(id: 23, question: '一轮明月挂疏林（打一字）'),
    LanternRiddle(id: 24, question: '广寒宫中奏仙乐（打一成语）'),
    LanternRiddle(id: 25, question: '明月松间照（打一成语）'),
    LanternRiddle(id: 26, question: '中秋前后巧相逢（打一字）'),
    LanternRiddle(id: 27, question: '中秋大丰收（打一江苏城市）'),
    LanternRiddle(id: 28, question: '明月照我还（打一成语）'),
    LanternRiddle(id: 29, question: '闰八月（打一成语）'),
    LanternRiddle(id: 30, question: '举杯邀月成三人（打一成语）'),
  ];

  /// 活动窗口为中秋 00:00 至次日 03:00（UTC+8）。
  static LanternWindow? currentWindow([DateTime? at]) {
    final now = (at ?? DateTime.now()).toUtc();
    for (final entry in kFestivals.entries) {
      if (entry.value != 'zhongqiu') continue;
      final start = DateTime.parse('${entry.key}T00:00:00+08:00');
      final end = DateTime.parse(
        '${dayKey(start.toUtc().add(const Duration(days: 1, hours: 8)))}T03:00:00+08:00',
      );
      if (!now.isBefore(start) && now.isBefore(end)) {
        return LanternWindow(date: entry.key, start: start, end: end);
      }
    }
    return null;
  }

  static String dayKey([DateTime? at]) {
    final china = (at ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
    return '${china.year.toString().padLeft(4, '0')}-'
        '${china.month.toString().padLeft(2, '0')}-'
        '${china.day.toString().padLeft(2, '0')}';
  }

  static Future<LanternSnapshot> state() async {
    final json = await _request('GET', '/api/lantern');
    return LanternSnapshot.fromJson(json);
  }

  static Future<Map<String, dynamic>> answer(int id, String answer) =>
      _request('POST', '/api/lantern/answer', {'id': id, 'answer': answer});

  static Future<Map<String, dynamic>> drawEmoji() =>
      _request('POST', '/api/lantern/emoji/draw', const {});

  static Future<Map<String, dynamic>> answerEmoji(String answer) =>
      _request('POST', '/api/lantern/emoji/answer', {'answer': answer});

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    final token = Api.token;
    if (token != null && token.isNotEmpty) {
      headers['X-Trash-Token'] = token;
    }
    final uri = Uri.parse('${Api.base}$path');
    http.Response response;
    try {
      response = await switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const {}),
        ),
        _ => throw ApiException('不支持的请求方法'),
      }.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('网络超时，请稍后再试');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('网络连接失败，请检查网络');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiException('服务未响应（${response.statusCode}）', response.statusCode);
    }
    final data = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode >= 400) {
      throw ApiException(
        '${data['err'] ?? '请求失败（${response.statusCode}）'}',
        response.statusCode,
      );
    }
    return data;
  }
}

List<dynamic> _asList(dynamic value) => value is List ? value : const [];

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}
