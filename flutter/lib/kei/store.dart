import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/api.dart';
import '../services/platform.dart' as platform;
import '../services/prefs.dart';
import 'models.dart';

class KeiStore {
  static const String historyKey = 'citro_kei_history_v1';
  static const String ownerKey = 'citro_kei_owner_v1';
  static const int maxRecords = 20;

  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static bool _syncInFlight = false;
  static int _lastSyncAt = 0;
  static int _syncEpoch = 0;
  static String? _account;
  static Timer? _pushTimer;

  static List<KeiRecord> load() {
    final raw = Prefs.getString(historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => KeiRecord.fromJson(Map<String, dynamic>.from(e)))
          .where((r) => r.id.isNotEmpty)
          .toList(growable: true);
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(
    List<KeiRecord> records, {
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

  static Future<String> add(KeiResult result) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final records = load();
    final id = now.toString();
    records.insert(
      0,
      KeiRecord(id: id, takenAtMs: now, result: result, updatedAtMs: now),
    );
    await _write(records);
    return id;
  }

  static Future<void> remove(String id) async {
    final records = load()..removeWhere((e) => e.id == id);
    await _write(records);
  }

  static Future<void> clear() async {
    _pushTimer?.cancel();
    await Prefs.setString(historyKey, null);
    changes.value++;
    _schedulePush(immediate: true);
  }

  static Future<void> clearLocal() async {
    _pushTimer?.cancel();
    _syncEpoch++;
    _account = null;
    _lastSyncAt = 0;
    await Prefs.setString(historyKey, null);
    await Prefs.setString(ownerKey, null);
    changes.value++;
  }

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
        await Prefs.setString(historyKey, null);
      }
      final json = await Api.keiGet();
      if (epoch != _syncEpoch) return;
      final remote = <KeiRecord>[];
      final raw = json['history'];
      if (raw is List) {
        for (final e in raw.whereType<Map>()) {
          try {
            remote.add(KeiRecord.fromJson(Map<String, dynamic>.from(e)));
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
      await Api.keiSave(merged.map((e) => e.toJson()).toList());
    } catch (_) {
      // 离线时保留本地记录，下次进入测试页再同步。
    } finally {
      _syncInFlight = false;
    }
  }

  static List<KeiRecord> mergeRecords(
    Iterable<KeiRecord> local,
    Iterable<KeiRecord> remote,
  ) {
    final byId = <String, KeiRecord>{};
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

  static List<KeiRecord> _sortAndLimit(List<KeiRecord> records) {
    final out = List<KeiRecord>.of(records)
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
      await Api.keiSave(load().map((e) => e.toJson()).toList());
    } catch (_) {}
  }

  static void resetForTest() {
    _pushTimer?.cancel();
    _pushTimer = null;
    _syncInFlight = false;
    _lastSyncAt = 0;
    _account = null;
  }
}
