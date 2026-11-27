/// 打卡数据的云端同步与离线队列。
///
/// 规则（执行方案 10）：
/// - 本机先写，再尝试同步；失败不回滚文字。
/// - 同类操作按「日期 + 字段」合并，多次修改只同步最后一次。
/// - 创建当天记录必须先于行动 / 回签。
/// - 409 保留本地草稿并带最新 rev 重试；429 不做无限重试。
library;

import 'dart:convert';

import '../services/api.dart';
import '../services/prefs.dart';
import 'checkin_models.dart';

class CheckinSyncOp {
  final String kind; // create / action / reflection
  final String date;
  final Map<String, Object?> payload;
  final int ts;
  final bool conflict;

  const CheckinSyncOp({
    required this.kind,
    required this.date,
    required this.payload,
    required this.ts,
    this.conflict = false,
  });

  Map<String, Object?> toJson() => {
    'kind': kind,
    'date': date,
    'payload': payload,
    'ts': ts,
    'conflict': conflict,
  };

  static CheckinSyncOp? fromJson(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    final kind = '${raw['kind'] ?? ''}'.trim();
    final date = '${raw['date'] ?? ''}'.trim();
    if (!const ['create', 'action', 'reflection'].contains(kind)) return null;
    if (!isCheckinDate(date)) return null;
    final payload = raw['payload'];
    return CheckinSyncOp(
      kind: kind,
      date: date,
      payload: payload is Map
          ? Map<String, Object?>.from(payload)
          : <String, Object?>{},
      ts: (raw['ts'] is num)
          ? (raw['ts'] as num).toInt()
          : int.tryParse('${raw['ts']}') ?? 0,
      conflict: raw['conflict'] == true,
    );
  }
}

class CheckinSyncRun {
  final int remaining;
  final bool conflict;
  final String? message;

  const CheckinSyncRun({
    this.remaining = 0,
    this.conflict = false,
    this.message,
  });
}

class CheckinSync {
  CheckinSync._();

  static const _create = 'create';
  static const _action = 'action';
  static const _reflection = 'reflection';

  static String _key(String account) =>
      'citro_checkin_outbox_v1_$account';

  static List<CheckinSyncOp> load(String account) {
    try {
      final raw = Prefs.getString(_key(account));
      if (raw == null || raw.isEmpty) return <CheckinSyncOp>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CheckinSyncOp>[];
      return decoded
          .whereType<Map>()
          .map((e) => CheckinSyncOp.fromJson(e))
          .whereType<CheckinSyncOp>()
          .toList();
    } catch (_) {
      return <CheckinSyncOp>[];
    }
  }

  static Future<void> save(String account, List<CheckinSyncOp> ops) async {
    try {
      if (ops.isEmpty) {
        await Prefs.setString(_key(account), null);
      } else {
        await Prefs.setString(
          _key(account),
          jsonEncode(ops.map((e) => e.toJson()).toList()),
        );
      }
    } catch (_) {}
  }

  /// 入队：创建每天最多一条，行动 / 回签各一条；后写覆盖前写。
  static Future<void> enqueue(
    String account, {
    required String kind,
    required String date,
    required Map<String, Object?> payload,
  }) async {
    final ops = load(account);
    final index = ops.indexWhere((e) => e.kind == kind && e.date == date);
    final op = CheckinSyncOp(
      kind: kind,
      date: date,
      payload: payload,
      ts: DateTime.now().millisecondsSinceEpoch,
      conflict: false,
    );
    if (index >= 0) {
      ops[index] = op;
    } else {
      ops.add(op);
    }
    await save(account, _sort(ops));
  }

  static Future<void> forget(String account, String date, String kind) async {
    final ops = load(account)
        .where((e) => !(e.date == date && e.kind == kind))
        .toList();
    await save(account, ops);
  }

  static List<CheckinSyncOp> _sort(List<CheckinSyncOp> ops) {
    final list = List<CheckinSyncOp>.from(ops);
    list.sort((a, b) {
      final byKind = _weight(a.kind) - _weight(b.kind);
      if (byKind != 0) return byKind;
      return a.ts.compareTo(b.ts);
    });
    return list;
  }

  static int _weight(String kind) => switch (kind) {
    _create => 0,
    _action => 1,
    _reflection => 2,
    _ => 3,
  };

  static Future<Map<String, dynamic>> bootstrap({int days = 35}) async {
    if (Api.token == null || Api.token!.isEmpty) return const {};
    try {
      return await Api.checkinBootstrap(days: days);
    } catch (_) {
      return const {};
    }
  }

  /// 按顺序推送队列。
  ///
  /// [entryOf] 返回本机记录，用于补齐请求字段；[onRemote] 把服务端记录
  /// 合并回本机；`conflict` 由调用方决定如何提示。
  static Future<CheckinSyncRun> flush({
    required String account,
    required CheckinDayEntry? Function(String date) entryOf,
    required void Function(CheckinDayEntry remote) onRemote,
    void Function(CheckinDayEntry latest)? onConflict,
  }) async {
    if (Api.token == null || Api.token!.isEmpty) {
      return const CheckinSyncRun(
        message: '已存本机，联网后再同步',
      );
    }
    var ops = _sort(load(account));
    if (ops.isEmpty) return const CheckinSyncRun();
    var conflict = false;
    String? message;
    while (ops.isNotEmpty) {
      final op = ops.first;
      final entry = entryOf(op.date);
      if (entry == null) {
        ops.removeAt(0);
        continue;
      }
      try {
        Map<String, dynamic> res;
        if (op.kind == _create) {
          res = await Api.checkinTake(snapshot: entry.creationPayload());
        } else if (op.kind == _action) {
          res = await Api.checkinAction(
            date: op.date,
            done: entry.actionDone,
            actionText: entry.actionText,
            actionType: entry.actionType,
            linkedId: entry.linkedId,
            rev: entry.rev,
          );
        } else if (op.kind == _reflection) {
          res = await Api.checkinReflection(
            date: op.date,
            mood: entry.reflectionMood ?? CheckinMood.unrated,
            text: entry.reflectionText,
            rev: entry.rev,
          );
        } else {
          ops.removeAt(0);
          continue;
        }
        final remote = _dayOf(res);
        if (remote != null) onRemote(remote);
        ops.removeAt(0);
      } on ApiException catch (e) {
        if (e.code == 409) {
          conflict = true;
          final latest = _dayOf(e.body);
          if (latest != null) {
            // 只交给界面处理 rev；本机草稿由 Store 保留，不能被覆盖。
            onConflict?.call(latest);
          }
          message = '另一台设备也修改过这条记录';
          // 保留本机草稿，更新 rev 后不再自动重试；用户下次保存会替换这一条。
          ops[0] = CheckinSyncOp(
            kind: op.kind,
            date: op.date,
            payload: op.payload,
            ts: DateTime.now().millisecondsSinceEpoch,
            conflict: true,
          );
          if (latest != null) {
            ops[0] = CheckinSyncOp(
              kind: op.kind,
              date: op.date,
              payload: {
                ...op.payload,
                'rev': latest.rev,
              },
              ts: DateTime.now().millisecondsSinceEpoch,
              conflict: true,
            );
          }
          break;
        }
        if (e.code == 429 || e.code == 401) {
          message = e.code == 429 ? '同步太频繁，稍后再试' : '登录状态已过期';
          break;
        }
        if (e.code == 404) {
          // 服务端没有这条记录：先补一次创建，再重排队。
          ops.removeAt(0);
          ops.insert(
            0,
            CheckinSyncOp(
              kind: _create,
              date: op.date,
              payload: entry.creationPayload(),
              ts: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          message = '记录正在补建';
          break;
        }
        message = '已存本机，联网后再同步';
        break;
      } catch (_) {
        message = '已存本机，联网后再同步';
        break;
      }
    }
    await save(account, ops);
    return CheckinSyncRun(
      remaining: ops.length,
      conflict: conflict,
      message: message,
    );
  }

  static CheckinDayEntry? _dayOf(Map<String, dynamic>? map) {
    if (map == null) return null;
    final raw = map['day'] ?? map['today'];
    if (raw is Map) return CheckinDayEntry.fromJson(raw);
    return null;
  }
}
