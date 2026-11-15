import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/api.dart';
import 'room_models.dart';
import 'share_quality.dart';

/// 屏幕共享信令 REST 客户端。
///
/// 完全独立于 [Api]：和仓库里的 `lantern_api.dart` 一样，自己持有一个
/// http.Client、自己拼 header，只从 [Api] 借 `token`（`X-Trash-Token`）。
/// 这样信令域名变化时不会污染主站 API。
class ShareApiException implements Exception {
  const ShareApiException(this.message, [this.statusCode = 0]);

  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

/// Worker 地址。
///
/// 默认指向正式子域；POC 阶段用 `--dart-define=SHARE_API_BASE=...` 指向
/// workers.dev，避免为了测试去改 DNS。
const String kShareApiBase = String.fromEnvironment(
  'SHARE_API_BASE',
  defaultValue: 'https://share.mint1017.cn',
);

class RoomApi {
  RoomApi._();

  static final RoomApi instance = RoomApi._();

  final http.Client _client = http.Client();

  static const Duration _timeout = Duration(seconds: 20);

  Map<String, String> _headers({
    bool json = false,
    String? roomToken,
    bool withTrashToken = true,
  }) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    // 主站登录态：用于创建房间。加入房间走游客身份（见 joinRoom），
    // 否则手机和电脑登录同一账号时，两边会落到同一个 uid 上，
    // 观众端会把自己当成发布者本人，永远订阅不到画面。
    final trash = Api.token;
    if (withTrashToken && trash != null && trash.isNotEmpty) {
      h['X-Trash-Token'] = trash;
    }
    // 房间 token：用于房间内的其余接口。
    if (roomToken != null && roomToken.isNotEmpty) {
      h['Authorization'] = 'Bearer $roomToken';
    }
    return h;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Object? body,
    String? roomToken,
    Map<String, String>? query,
    Duration timeout = _timeout,
    bool withTrashToken = true,
  }) async {
    final uri = Uri.parse(
      '$kShareApiBase$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
    try {
      final headers = _headers(
        json: body != null,
        roomToken: roomToken,
        withTrashToken: withTrashToken,
      );
      final encoded = body == null ? null : jsonEncode(body);
      final res = await switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers, body: encoded),
        'PUT' => _client.put(uri, headers: headers, body: encoded),
        'DELETE' => _client.delete(uri, headers: headers, body: encoded),
        _ => throw const ShareApiException('不支持的请求方法'),
      }.timeout(timeout);
      return _decode(res);
    } on ShareApiException {
      rethrow;
    } on TimeoutException {
      throw const ShareApiException('网络超时，请稍后再试');
    } catch (_) {
      throw const ShareApiException('网络连接失败，请检查网络');
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw ShareApiException('服务未响应（${res.statusCode}）', res.statusCode);
    }
    if (res.statusCode >= 400) {
      final msg = data is Map
          ? '${data['err'] ?? '请求失败'}'
          : '请求失败（${res.statusCode}）';
      throw ShareApiException(msg, res.statusCode);
    }
    if (data is! Map) throw const ShareApiException('服务返回了意外内容');
    return Map<String, dynamic>.from(data);
  }

  // ── 房间 ──────────────────────────────────────────────────────────────

  /// 向 Worker 换声网 RTC token。返回 null 表示 Worker 没配证书（走 CF）。
  ///
  /// [channel] 用 roomId；uid 由 Worker 从房间 token 里算（数字 uid 是
  /// 房间 uid 字符串的 FNV-1a 哈希，收发两端各自算一致）。
  Future<({String appId, String channel, int uid, String token})?>
  fetchAgoraToken({
    required String roomToken,
    String? channel,
  }) async {
    try {
      final data = await _request(
        'POST',
        '/api/agora/token',
        body: <String, dynamic>{if (channel != null) 'channel': channel},
        roomToken: roomToken,
      );
      if (data['enabled'] != true) return null;
      return (
        appId: data['appId'] as String? ?? '',
        channel: data['channel'] as String? ?? '',
        uid: (data['uid'] as num?)?.toInt() ?? 0,
        token: data['token'] as String? ?? '',
      );
    } on ShareApiException catch (e) {
      // 没配证书 / 老版本 Worker 没有 /agora/token → 安静回退。
      debugPrint('fetchAgoraToken 回退 CF：$e');
      return null;
    }
  }

  /// 创建房间。返回宿主身份的房间 token。
  Future<JoinResult> createRoom({
    String title = '',
    String roomType = 'one_to_many',
    ShareQuality quality = ShareQuality.fallback,
  }) async {
    final data = await _request(
      'POST',
      '/api/rooms',
      body: <String, dynamic>{
        if (title.trim().isNotEmpty) 'title': title.trim(),
        'roomType': roomType,
        'quality': quality.toJson(),
      },
    );
    return JoinResult.fromJson(data);
  }

  /// 用房间码加入（观众）。
  ///
  /// **刻意不带 X-Trash-Token**：带登录态时服务端会按账号 uid 建成员，
  /// 手机和电脑登录同一账号就会共用同一个成员，观众端把自己认成发布者，
  /// 于是永远订阅不到画面/声音。游客身份每次进房都有独立 uid，显示名
  /// 仍然用 [name]，和网页观看端的行为一致。
  Future<JoinResult> joinRoom(
    String roomId, {
    String? code,
    String? name,
  }) async {
    final trimmed = name?.trim() ?? '';
    final data = await _request(
      'POST',
      '/api/rooms/$roomId/join',
      body: <String, dynamic>{if (trimmed.isNotEmpty) 'name': trimmed},
      query: code == null || code.isEmpty
          ? null
          : <String, String>{'code': code},
      withTrashToken: false,
    );
    return JoinResult.fromJson(data);
  }

  /// 查询房间状态（成员列表、发布者 session）。
  Future<({RoomInfo room, List<RoomMember> members})> getRoom(
    String roomId, {
    required String roomToken,
  }) async {
    final data = await _request(
      'GET',
      '/api/rooms/$roomId',
      roomToken: roomToken,
    );
    return (
      room: RoomInfo.fromJson(
        Map<String, dynamic>.from(data['room'] as Map? ?? <String, dynamic>{}),
      ),
      members: (data['members'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => RoomMember.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  // ── 发布 / 订阅 ───────────────────────────────────────────────────────

  /// 发布：把客户端 offer 交给 Worker，由 Worker 转发到 SFU，拿回 answer。
  Future<SfuSessionResult> publish(
    String roomId, {
    required String roomToken,
    required String sdp,
    required List<RoomTrack> tracks,
  }) async {
    final data = await _request(
      'POST',
      '/api/rooms/$roomId/publish',
      body: <String, dynamic>{
        'sdp': sdp,
        'type': 'offer',
        'tracks': tracks.map((t) => t.toJson()).toList(),
      },
      roomToken: roomToken,
    );
    return SfuSessionResult.fromJson(data);
  }

  /// 订阅：一次把发布者的多路 track 转进我们的 session，返回一个 offer。
  ///
  /// 批量是必须的：分开订阅时 `system` 音频会叠在已跑起来的 `screen`
  /// 上做二次 renegotiation，那一步失败就只剩画面没有声音。
  Future<SfuSessionResult> subscribe(
    String roomId, {
    required String roomToken,
    required String publisherSessionId,
    required List<String> trackNames,
  }) async {
    final data = await _request(
      'POST',
      '/api/rooms/$roomId/subscribe',
      body: <String, dynamic>{
        'publisherSessionId': publisherSessionId,
        'trackNames': trackNames,
      },
      roomToken: roomToken,
    );
    return SfuSessionResult.fromJson(data);
  }

  /// 提交订阅侧的 answer，触发 SFU renegotiate。
  Future<void> sendAnswer(
    String roomId, {
    required String roomToken,
    required String sessionId,
    required String sdp,
  }) async {
    await _request(
      'POST',
      '/api/rooms/$roomId/answer',
      body: <String, dynamic>{
        'sessionId': sessionId,
        'sdp': sdp,
        'type': 'answer',
      },
      roomToken: roomToken,
    );
  }

  // ── 生命周期 ──────────────────────────────────────────────────────────

  Future<void> leave(String roomId, {required String roomToken}) async {
    try {
      await _request(
        'POST',
        '/api/rooms/$roomId/leave',
        body: <String, dynamic>{},
        roomToken: roomToken,
        // 离开是收尾动作，不能拿默认 20 s 超时拖住退出流程。
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      // 离开失败不影响本地清理。
    }
  }

  Future<void> endRoom(String roomId, {required String roomToken}) async {
    try {
      await _request(
        'POST',
        '/api/rooms/$roomId/end',
        body: <String, dynamic>{},
        roomToken: roomToken,
        // 结束房间同理：本地已经断开，服务端请求不该卡住界面。
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {}
  }

  /// 主持人踢人。
  Future<void> kick(
    String roomId, {
    required String roomToken,
    required String uid,
  }) async {
    await _request(
      'POST',
      '/api/rooms/$roomId/kick',
      body: <String, dynamic>{'uid': uid},
      roomToken: roomToken,
    );
  }

  /// 取短期 ICE（TURN）凭证。
  Future<List<Map<String, dynamic>>> getIceServers(
    String roomId, {
    required String roomToken,
  }) async {
    final data = await _request('GET', '/api/ice', roomToken: roomToken);
    return (data['iceServers'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
