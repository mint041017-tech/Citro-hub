import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'room_models.dart';
import 'room_api.dart';
import 'share_quality.dart';

/// 房间 WebSocket 事件。
///
/// 字段按事件类型填，用 [type] 区分。这样 Flutter 侧一个 switch 就能处理，
/// 不用为每个事件建一个类。
class WsEvent {
  const WsEvent({required this.type, required this.raw});

  final String type;
  final Map<String, dynamic> raw;

  String? get uid => raw['uid'] as String?;
  // chat 事件里 message 是 Map，这里只接字符串形态；不做类型判断的话
  // `as String?` 会在收到 Map 时直接抛 TypeError。
  String? get message => raw['message'] is String ? raw['message'] as String : null;
  String? get code => raw['code'] as String?;
  String? get reason => raw['reason'] as String?;
  int? get count => (raw['count'] as num?)?.toInt();

  RoomMember? get member => raw['member'] is Map
      ? RoomMember.fromJson(Map<String, dynamic>.from(raw['member'] as Map))
      : null;

  ChatMessage? get chat => raw['message'] is Map
      ? ChatMessage.fromJson(Map<String, dynamic>.from(raw['message'] as Map))
      : null;

  ShareQuality get quality => ShareQuality.sanitize(
        raw['quality'] as Map<String, dynamic>?,
      );

  List<RoomTrack> get tracks => (raw['tracks'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => RoomTrack.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  /// `publisher_joined` / `track_added` 里的 SFU sessionId。
  String? get sessionId => raw['sessionId'] as String?;

  /// hello 快照：自己（带 self 标记）。
  RoomMember? get selfMember => raw['self'] is Map
      ? RoomMember.fromJson(Map<String, dynamic>.from(raw['self'] as Map))
      : null;

  /// hello 快照：房间信息。
  RoomInfo? get room => raw['room'] is Map
      ? RoomInfo.fromJson(Map<String, dynamic>.from(raw['room'] as Map))
      : null;

  /// hello 快照：全体成员。
  List<RoomMember> get members => (raw['members'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => RoomMember.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  /// hello 快照：历史聊天记录。
  List<ChatMessage> get chatHistory => (raw['chatHistory'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  factory WsEvent.parse(Map<String, dynamic> json) =>
      WsEvent(type: (json['type'] as String? ?? 'unknown'), raw: json);
}

/// 房间事件通道：带指数退避重连（1s → 2s → 4s → 8s，上限 30s）。
///
/// 断线重连时不需要重新 join —— 房间 token 还在有效期内，
/// 重连后服务端会重新推 hello 快照，客户端按快照补齐发布者。
class RoomWs {
  RoomWs._({
    required this.roomId,
    required this.token,
    required this.onEvent,
    required this.onStateChanged,
  });

  final String roomId;
  final String token;
  final void Function(WsEvent event) onEvent;
  final void Function(bool connected) onStateChanged;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _attempt = 0;
  bool _closedByUser = false;
  bool _connected = false;
  bool get isConnected => _connected;

  static RoomWs start({
    required String roomId,
    required String token,
    required void Function(WsEvent event) onEvent,
    required void Function(bool connected) onStateChanged,
  }) {
    final ws = RoomWs._(
      roomId: roomId,
      token: token,
      onEvent: onEvent,
      onStateChanged: onStateChanged,
    );
    ws._connect();
    return ws;
  }

  String get _url {
    final base = kShareApiBase.replaceFirst(RegExp('^http'), 'ws');
    return '$base/api/rooms/$roomId/ws?token=${Uri.encodeQueryComponent(token)}';
  }

  void _connect() {
    if (_closedByUser) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url));
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _sub = _channel!.stream.listen(
      _onMessage,
      onDone: _onDone,
      onError: (_) => _onDone(),
      cancelOnError: true,
    );
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(jsonDecode(data) as Map);
    } catch (_) {
      return;
    }
    if (json['type'] == 'hello') {
      _attempt = 0;
      _connected = true;
      onStateChanged(true);
      _startPing();
    }
    onEvent(WsEvent.parse(json));
  }

  void _onDone() {
    _connected = false;
    _stopPing();
    onStateChanged(false);
    _channel = null;
    if (!_closedByUser) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closedByUser || _reconnectTimer != null) return;
    // 1s, 2s, 4s, 8s, 16s, 30s, 30s...
    final delay = _attempt >= 5
        ? 30
        : (1 << (_attempt < 0 ? 0 : _attempt)).clamp(1, 30);
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _reconnectTimer = null;
      _connect();
    });
  }

  /// 心跳：30 秒一次，防止 NAT / 运营商把空闲连接掐掉。
  void _startPing() {
    _stopPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) => send({'type': 'ping'}));
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null || !_connected) return;
    try {
      ch.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void sendChat(String text) => send({'type': 'chat', 'text': text});

  void sendPublishState(List<RoomTrack> tracks) => send({
        'type': 'publish_state',
        'tracks': tracks.map((t) => t.toJson()).toList(),
      });

  void sendQuality(ShareQuality q) => send({'type': 'quality', 'quality': q.toJson()});

  void close() {
    _closedByUser = true;
    _stopPing();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    if (_connected) {
      _connected = false;
      onStateChanged(false);
    }
  }
}
