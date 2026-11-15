/// 房间信令的数据模型。
///
/// 字段与 `screen-share/src/types.ts` 一一对应，改动时两边一起改。
/// 这里刻意不做 codable/json_serializable —— 仓库里其它服务（api.dart、
/// lantern_api.dart）都是手写 fromJson，跟随既有做法。
library;

import 'share_quality.dart';

class RoomTrack {
  const RoomTrack({required this.name, required this.kind, this.mid});

  /// `screen`（视频）或 `mic`（音频）。
  final String name;
  final String kind;

  /// 这路 track 在客户端 SDP 里的 m-line 序号。
  ///
  /// 发布时必须如实上报：SFU 靠它把 local track 对到正确的 m-line 上，
  /// 硬编码 "0" 在加了第二路（麦克风）之后会指错。
  /// 订阅时由 Worker 回传，用来匹配 `onTrack` 事件。
  final String? mid;

  bool get isAudio => kind == 'audio';

  factory RoomTrack.fromJson(Map<String, dynamic> json) => RoomTrack(
    name: (json['name'] as String? ?? 'screen'),
    kind: (json['kind'] as String? ?? 'video') == 'audio' ? 'audio' : 'video',
    mid: json['mid'] as String?,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'kind': kind,
    if (mid != null && mid!.isNotEmpty) 'mid': mid,
  };

  @override
  bool operator ==(Object other) => other is RoomTrack && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

class RoomMember {
  const RoomMember({
    required this.uid,
    required this.name,
    required this.role,
    required this.online,
    required this.tracks,
    required this.sfuSessionId,
    this.self = false,
  });

  final String uid;
  final String name;

  /// `host` / `publisher` / `viewer`。
  final String role;
  final bool online;
  final List<RoomTrack> tracks;
  final String? sfuSessionId;
  final bool self;

  bool get isHost => role == 'host';
  bool get isPublisher => tracks.isNotEmpty;
  bool get hasScreen => tracks.any((t) => t.name == 'screen');
  bool get hasMic => tracks.any((t) => t.name == 'mic');

  String get displayName => name.isEmpty ? '观众' : name;

  factory RoomMember.fromJson(Map<String, dynamic> json) => RoomMember(
    uid: (json['uid'] as String? ?? ''),
    name: (json['name'] as String? ?? '观众'),
    role: (json['role'] as String? ?? 'viewer'),
    online: json['online'] as bool? ?? false,
    tracks: (json['tracks'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => RoomTrack.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    sfuSessionId: json['sfuSessionId'] as String?,
    self: json['self'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uid': uid,
    'name': name,
    'role': role,
    'online': online,
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'sfuSessionId': sfuSessionId,
    'self': self,
  };

  RoomMember copyWith({bool? self, List<RoomTrack>? tracks, bool? online}) =>
      RoomMember(
        uid: uid,
        name: name,
        role: role,
        online: online ?? this.online,
        tracks: tracks ?? this.tracks,
        sfuSessionId: sfuSessionId,
        self: self ?? this.self,
      );
}

class RoomInfo {
  const RoomInfo({
    required this.roomId,
    required this.roomCode,
    required this.title,
    required this.roomType,
    required this.status,
    required this.hostUid,
    required this.quality,
    required this.maxViewers,
    required this.createdAt,
    required this.expiresAt,
    required this.viewerCount,
    required this.publisherCount,
  });

  final String roomId;
  final String roomCode;
  final String title;

  /// `one_to_many` / `one_to_one` / `multi_party`。
  final String roomType;
  final String status;
  final String hostUid;
  final ShareQuality quality;
  final int maxViewers;
  final int createdAt;
  final int expiresAt;
  final int viewerCount;
  final int publisherCount;

  bool get live => status == 'live' || status == 'waiting';
  bool get ended => status == 'ended';

  /// 邀请链接。装了 App 的会落到房间页，没装的落网页观众页。
  String get inviteLink => 'https://share.mint1017.cn/?room=$roomCode';

  factory RoomInfo.fromJson(Map<String, dynamic> json) => RoomInfo(
    roomId: (json['roomId'] as String? ?? ''),
    roomCode: (json['roomCode'] as String? ?? ''),
    title: (json['title'] as String? ?? '一起看'),
    roomType: (json['roomType'] as String? ?? 'one_to_many'),
    status: (json['status'] as String? ?? 'waiting'),
    hostUid: (json['hostUid'] as String? ?? ''),
    quality: ShareQuality.sanitize(json['quality'] as Map<String, dynamic>?),
    maxViewers: (json['maxViewers'] as num?)?.toInt() ?? 50,
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    expiresAt: (json['expiresAt'] as num?)?.toInt() ?? 0,
    viewerCount: (json['viewerCount'] as num?)?.toInt() ?? 0,
    publisherCount: (json['publisherCount'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'roomId': roomId,
    'roomCode': roomCode,
    'title': title,
    'roomType': roomType,
    'status': status,
    'hostUid': hostUid,
    'quality': quality.toJson(),
    'maxViewers': maxViewers,
    'viewerCount': viewerCount,
    'publisherCount': publisherCount,
  };

  /// 只覆盖会随时间变化的字段（观看人数、房间状态、画质）。
  RoomInfo copyWithLive({
    String? status,
    int? viewerCount,
    int? publisherCount,
    ShareQuality? quality,
    String? title,
  }) => RoomInfo(
    roomId: roomId,
    roomCode: roomCode,
    title: title ?? this.title,
    roomType: roomType,
    status: status ?? this.status,
    hostUid: hostUid,
    quality: quality ?? this.quality,
    maxViewers: maxViewers,
    createdAt: createdAt,
    expiresAt: expiresAt,
    viewerCount: viewerCount ?? this.viewerCount,
    publisherCount: publisherCount ?? this.publisherCount,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.uid,
    required this.name,
    required this.text,
    required this.at,
    this.local = false,
  });

  final String id;
  final String uid;
  final String name;
  final String text;
  final int at;
  final bool local;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: (json['id'] as String? ?? ''),
    uid: (json['uid'] as String? ?? ''),
    name: (json['name'] as String? ?? '观众'),
    text: (json['text'] as String? ?? ''),
    at: (json['at'] as num?)?.toInt() ?? 0,
    local: json['local'] as bool? ?? false,
  );
}

/// 创建房间 / 加入房间的响应。
class JoinResult {
  const JoinResult({
    required this.roomToken,
    required this.iceServers,
    required this.room,
    required this.members,
    required this.chatHistory,
    this.agoraEnabled = false,
  });

  final String roomToken;
  final List<Map<String, dynamic>> iceServers;
  final RoomInfo room;
  final List<RoomMember> members;
  final List<ChatMessage> chatHistory;

  /// Worker 配置了声网证书时为 true：媒体优先走 Agora。
  final bool agoraEnabled;

  factory JoinResult.fromJson(Map<String, dynamic> json) => JoinResult(
    roomToken: (json['roomToken'] as String? ?? ''),
    iceServers: (json['iceServers'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(),
    room: RoomInfo.fromJson(
      Map<String, dynamic>.from(json['room'] as Map? ?? <String, dynamic>{}),
    ),
    agoraEnabled: json['agora'] is Map
        ? (json['agora'] as Map)['enabled'] == true
        : false,
    members: (json['members'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => RoomMember.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    chatHistory: (json['chatHistory'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

/// 发布 / 订阅的 SDP 交换结果。
class SfuSessionResult {
  const SfuSessionResult({
    required this.sessionId,
    required this.sdp,
    required this.type,
    this.mid = '',
    this.mids = const <String, String>{},
  });

  final String sessionId;
  final String sdp;

  /// `answer`（发布）或 `offer`（订阅）。
  final String type;

  /// 只有订阅才有：第一路在我们这一侧 session 里分配的 mid（兼容旧 Worker）。
  final String mid;

  /// 批量订阅时 trackName → mid。Worker 不认批量时会为空，调用方回落到 [mid]。
  final Map<String, String> mids;

  factory SfuSessionResult.fromJson(Map<String, dynamic> json) {
    final desc = Map<String, dynamic>.from(
      json['sessionDescription'] as Map? ?? <String, dynamic>{},
    );
    final mids = <String, String>{};
    for (final item in json['tracks'] as List<dynamic>? ?? const <dynamic>[]) {
      if (item is! Map) continue;
      final name = item['trackName'];
      final mid = item['mid'];
      if (name is String &&
          name.isNotEmpty &&
          mid is String &&
          mid.isNotEmpty) {
        mids[name] = mid;
      }
    }
    return SfuSessionResult(
      sessionId: (json['sessionId'] as String? ?? ''),
      sdp: (desc['sdp'] as String? ?? ''),
      type: (desc['type'] as String? ?? 'answer'),
      mid: (json['mid'] as String? ?? ''),
      mids: mids,
    );
  }
}

/// 发布 / 订阅所用的 SFU 会话句柄，交给 `SfuClient` 管理。
class SfuSession {
  const SfuSession({
    required this.sessionId,
    required this.sdp,
    required this.type,
  });

  final String sessionId;
  final String sdp;
  final String type;
}
