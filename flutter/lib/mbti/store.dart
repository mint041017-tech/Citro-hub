import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/api.dart';
import '../services/platform.dart' as platform;
import '../services/prefs.dart';
import 'scoring.dart';

class MbtiRecord {
  final String id;
  final int takenAtMs;
  final MbtiResult result;

  /// 自评校准后的类型（不含 AT 后缀）；为空表示未做校准。
  final String? typeConfirmed;
  final String? aiInsight;

  /// 最后修改时间：新增、自评校准、AI 解读回写都会更新。
  /// 账号同步时用它判断同一条记录哪一份更新。
  final int updatedAtMs;

  const MbtiRecord({
    required this.id,
    required this.takenAtMs,
    required this.result,
    this.typeConfirmed,
    this.aiInsight,
    this.updatedAtMs = 0,
  });

  /// 展示用最终类型（校准优先，附情绪后缀）。
  String get displayType =>
      '${typeConfirmed ?? result.typeRaw}${result.atSuffix}';

  int get effectiveUpdatedAt => updatedAtMs > 0 ? updatedAtMs : takenAtMs;

  MbtiRecord copyWith({
    String? aiInsight,
    int? updatedAtMs,
  }) => MbtiRecord(
    id: id,
    takenAtMs: takenAtMs,
    result: result,
    typeConfirmed: typeConfirmed,
    aiInsight: aiInsight ?? this.aiInsight,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'takenAt': takenAtMs,
    'updatedAt': effectiveUpdatedAt,
    'result': result.toJson(),
    'typeConfirmed': typeConfirmed,
    'aiInsight': aiInsight,
  };

  factory MbtiRecord.fromJson(Map<String, dynamic> j) {
    final taken = j['takenAt'];
    final updated = j['updatedAt'];
    return MbtiRecord(
      id: '${j['id'] ?? ''}',
      takenAtMs: taken is num ? taken.toInt() : 0,
      result: MbtiResult.fromJson(
        Map<String, dynamic>.from(j['result'] as Map),
      ),
      typeConfirmed: j['typeConfirmed'] as String?,
      aiInsight: j['aiInsight'] as String?,
      updatedAtMs: updated is num ? updated.toInt() : 0,
    );
  }
}

class MbtiStore {
  static const String historyKey = 'citro_mbti_history_v1';
  static const String ownerKey = 'citro_mbti_owner_v1';
  static const int maxRecords = 30;

  /// 记录变化时通知首页卡片与历史页刷新，避免跨页面手动重载。
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static bool _syncInFlight = false;
  static int _lastSyncAt = 0;
  static int _syncEpoch = 0;
  static String? _account;
  static Timer? _pushTimer;

  static List<MbtiRecord> load() {
    final raw = Prefs.getString(historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => MbtiRecord.fromJson(Map<String, dynamic>.from(e)))
          .where((r) => r.id.isNotEmpty)
          .toList(growable: true);
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(
    List<MbtiRecord> records, {
    bool push = true,
  }) async {
    final next = _sortAndLimit(records);
    await Prefs.setString(
      historyKey,
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
    changes.value++;
    if (push) _schedulePush();
  }

  /// 新增一条测试记录，返回其 id（用于后续校准/AI 结果回写）。
  static Future<String> add(MbtiResult result) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final records = load();
    final id = now.toString();
    records.insert(
      0,
      MbtiRecord(id: id, takenAtMs: now, result: result, updatedAtMs: now),
    );
    await _write(records);
    return id;
  }

  static Future<void> update(MbtiRecord record) async {
    final records = load();
    final index = records.indexWhere((e) => e.id == record.id);
    if (index < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    records[index] = record.copyWith(updatedAtMs: now);
    await _write(records);
  }

  static Future<void> remove(String id) async {
    final records = load()..removeWhere((e) => e.id == id);
    await _write(records);
  }

  /// 用户主动清空历史：本地清空，并同步到当前账号。
  static Future<void> clear() async {
    _pushTimer?.cancel();
    await Prefs.setString(historyKey, null);
    changes.value++;
    _schedulePush(immediate: true);
  }

  /// 退出登录时清掉本机记录，避免下一个账号看到上一个人的结果。
  /// 不推送云端，因为服务端已经保留了原账号的数据。
  static Future<void> clearLocal() async {
    _pushTimer?.cancel();
    _syncEpoch++;
    _account = null;
    _lastSyncAt = 0;
    await Prefs.setString(historyKey, null);
    await Prefs.setString(ownerKey, null);
    changes.value++;
  }

  /// 登录后把本地与账号云端记录合并：同一条取 updatedAt 更新的版本。
  static Future<void> syncFromAccount({
    String? account,
    bool force = false,
  }) async {
    if (platform.isTest) return;
    if (account != null) _account = account;
    final hasAccount = _account != null || (Api.token?.isNotEmpty ?? false);
    if (!hasAccount) return;
    if (_syncInFlight) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastSyncAt < 15000) return;
    _syncInFlight = true;
    _lastSyncAt = now;
    final epoch = _syncEpoch;
    try {
      final owner = Prefs.getString(ownerKey);
      if (account != null &&
          owner != null &&
          owner.isNotEmpty &&
          owner != account) {
        // 已明确属于另一个账号的旧记录，不能带到当前账号。
        await Prefs.setString(historyKey, null);
      }
      final json = await Api.mbtiGet();
      if (epoch != _syncEpoch) return;
      final remote = <MbtiRecord>[];
      final raw = json['history'];
      if (raw is List) {
        for (final e in raw.whereType<Map>()) {
          try {
            remote.add(MbtiRecord.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      }
      final local = load();
      final merged = mergeRecords(local, remote);
      await Prefs.setString(
        historyKey,
        jsonEncode(merged.map((e) => e.toJson()).toList()),
      );
      if (account != null) {
        await Prefs.setString(ownerKey, account);
      }
      changes.value++;
      if (epoch != _syncEpoch) return;
      // 把合并后的完整历史写回，保证其它设备下次拿到同一份。
      await Api.mbtiSave(merged.map((e) => e.toJson()).toList());
    } catch (_) {
      // 离线时保持本地记录；下次进入测试页或登录成功后再试。
    } finally {
      _syncInFlight = false;
    }
  }

  /// 纯合并逻辑，供同步与测试复用。
  static List<MbtiRecord> mergeRecords(
    Iterable<MbtiRecord> local,
    Iterable<MbtiRecord> remote,
  ) {
    final byId = <String, MbtiRecord>{};
    for (final record in [...local, ...remote]) {
      if (record.id.isEmpty) continue;
      final existing = byId[record.id];
      if (existing == null ||
          record.effectiveUpdatedAt > existing.effectiveUpdatedAt) {
        byId[record.id] = record;
      }
    }
    return _sortAndLimit(byId.values.toList());
  }

  static List<MbtiRecord> _sortAndLimit(List<MbtiRecord> records) {
    final out = List<MbtiRecord>.of(records)
      ..sort((a, b) => b.takenAtMs.compareTo(a.takenAtMs));
    if (out.length > maxRecords) out.removeRange(maxRecords, out.length);
    return out;
  }

  static void _schedulePush({bool immediate = false}) {
    if (platform.isTest) return;
    if (_account == null && (Api.token?.isEmpty ?? true)) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 900),
      _pushRemote,
    );
  }

  static Future<void> _pushRemote() async {
    if (_account == null && (Api.token?.isEmpty ?? true)) return;
    try {
      await Api.mbtiSave(load().map((e) => e.toJson()).toList());
    } catch (_) {
      // 网络恢复后的下一次新增 / 修改会再次推送。
    }
  }

  /// 测试用：重置静态同步状态。
  static void resetForTest() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _syncInFlight = false;
    _lastSyncAt = 0;
    _account = null;
  }
}
