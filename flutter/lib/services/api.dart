import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int code;
  ApiException(this.message, [this.code = 0]);
  @override
  String toString() => message;
}

class Api {
  static const String base = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://chimu-claw.xyz/trashapi',
  );
  static String? token;
  static final http.Client _client = createApiClient();

  static String imageUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    if (path.startsWith('/')) return '$base$path';
    return path;
  }

  static Map<String, String> _headers({bool json = false, bool auth = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    if (auth && token != null && token!.isNotEmpty) h['X-Trash-Token'] = token!;
    return h;
  }

  static Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    bool auth = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = Uri.parse('$base$path');
    http.Response res;
    try {
      final headers = _headers(json: body != null, auth: auth);
      final encoded = body == null ? null : jsonEncode(body);
      res = await switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers, body: encoded),
        'PUT' => _client.put(uri, headers: headers, body: encoded),
        'DELETE' => _client.delete(uri, headers: headers, body: encoded),
        _ => throw ApiException('不支持的请求方法'),
      }.timeout(timeout);
    } on TimeoutException {
      throw ApiException('网络超时，请稍后再试');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('网络连接失败，请检查网络');
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw ApiException('服务未响应（${res.statusCode}）', res.statusCode);
    }
    if (res.statusCode >= 400) {
      final msg = data is Map
          ? '${data['err'] ?? '请求失败'}'
          : '请求失败（${res.statusCode}）';
      throw ApiException(msg, res.statusCode);
    }
    return data;
  }

  static Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) async {
    var p = path;
    if (query != null && query.isNotEmpty) {
      final q = query.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&');
      p += (p.contains('?') ? '&' : '?') + q;
    }
    final r = await _request('GET', p, auth: auth);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> post(
    String path, [
    Object? body,
    bool auth = true,
  ]) async {
    final r = await _request('POST', path, body: body, auth: auth);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> del(String path, [Object? body]) async {
    final r = await _request('DELETE', path, body: body);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> me() => get('/api/auth/me');

  static Future<Map<String, dynamic>> login(String phone, String password) =>
      post('/api/auth/login', {'phone': phone, 'password': password}, false);

  static Future<Map<String, dynamic>> register(
    String phone,
    String name,
    String password,
    String invite,
  ) => post('/api/auth/register', {
    'phone': phone,
    'name': name,
    'password': password,
    'invite': invite,
  }, false);

  static Future<Map<String, dynamic>> logout() => post('/api/auth/logout');

  static Future<Map<String, dynamic>> deleteAccount(String password) =>
      post('/api/auth/delete', {'password': password});

  static Future<Map<String, dynamic>> report({
    required String type,
    String? postId,
    String? commentId,
    String? targetNick,
    required String reason,
    String detail = '',
  }) => post('/api/report', {
    'type': type,
    if (postId != null) 'postId': postId,
    if (commentId != null) 'commentId': commentId,
    if (targetNick != null) 'targetNick': targetNick,
    'reason': reason,
    'detail': detail,
  });

  static Future<Map<String, dynamic>> saveProfile({
    required String name,
    int? month,
    int? day,
  }) => post('/api/auth/profile', {
    'name': name,
    if (month != null && day != null) 'bday': {'month': month, 'day': day},
  });

  static Future<Map<String, dynamic>> uploadAvatar(String dataUrl) =>
      post('/api/auth/avatar', {'img': dataUrl});

  static Future<List<Post>> posts() async {
    final j = await get('/api/posts');
    return ((j['posts'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Post.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Post> createPost({
    required String text,
    List<String> imgs = const [],
    String? voice,
    int voiceDur = 0,
    bool anon = false,
  }) async {
    final j = await post('/api/posts', {
      'text': text,
      'imgs': imgs,
      if (voice != null) 'voice': voice,
      if (voice != null) 'voiceDur': voiceDur,
      'anon': anon,
    });
    return Post.fromJson(Map<String, dynamic>.from(j['post']));
  }

  static Future<Map<String, dynamic>> toggleLike(String id) =>
      post('/api/posts/$id/like');
  static Future<Map<String, dynamic>> toggleHug(String id) =>
      post('/api/posts/$id/hug');

  static Future<Map<String, dynamic>> comment(
    String id, {
    required String text,
    String? replyId,
    List<String> imgs = const [],
    String? voice,
    int voiceDur = 0,
    bool anon = false,
  }) => post('/api/posts/$id/comment', {
    'text': text,
    'replyId': replyId,
    'imgs': imgs,
    if (voice != null) 'voice': voice,
    if (voice != null) 'voiceDur': voiceDur,
    'anon': anon,
  });

  static Future<void> deletePost(String id) => del('/api/posts/$id');
  static Future<void> deleteComment(String postId, String commentId) =>
      del('/api/posts/$postId/comments/$commentId');

  static Future<Map<String, dynamic>> notifications() =>
      get('/api/notifications');
  static Future<void> readNotifications() => post('/api/notifications/read');

  static Future<List<Note>> notes() async {
    final j = await get('/api/notes');
    return ((j['notes'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Note.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Note> saveNote({
    String? id,
    required String title,
    required String content,
  }) async {
    final j = await post(id == null ? '/api/notes' : '/api/notes/$id', {
      'title': title,
      'content': content,
    });
    return Note.fromJson(Map<String, dynamic>.from(j['note']));
  }

  static Future<void> deleteNote(String id) => del('/api/notes/$id');

  static Future<Map<String, dynamic>> gameBoard(
    String game, {
    String? name,
    String? gid,
  }) => get(
    '/api/games/board',
    query: {
      'game': game,
      if (name != null) 'name': name,
      if (gid != null) 'gid': gid,
    },
    auth: true,
  );

  static Future<Map<String, dynamic>> gameScore(
    String game,
    int score, {
    String? name,
    String? gid,
  }) => post('/api/games/score', {
    'game': game,
    'score': score,
    if (name != null) 'name': name,
    if (gid != null) 'gid': gid,
  });

  static Future<Map<String, dynamic>> gameLive(
    String game, {
    String progress = '',
    bool leave = false,
    String? name,
    String? gid,
  }) => post('/api/games/live', {
    'game': game,
    'progress': progress,
    'leave': leave,
    if (name != null) 'name': name,
    if (gid != null) 'gid': gid,
  });

  static Future<Map<String, dynamic>> zodiacGet(String? deviceId) async {
    try {
      return await get(
        '/api/zodiac',
        query: {if (deviceId != null) 'deviceId': deviceId},
        auth: true,
      );
    } on ApiException catch (e) {
      if (e.code == 400) return {};
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> zodiacLock(
    String sign,
    String? deviceId,
  ) => post('/api/zodiac', {
    'sign': sign,
    if (deviceId != null) 'deviceId': deviceId,
  });

  static Future<Map<String, dynamic>> draw({String? deviceId}) =>
      get('/api/draw', query: {if (deviceId != null) 'deviceId': deviceId});
  static Future<Map<String, dynamic>> drawTake({String? deviceId}) =>
      post('/api/draw', {if (deviceId != null) 'deviceId': deviceId});

  static Future<Map<String, dynamic>> moyuGet() => get('/api/moyu/config');
  static Future<Map<String, dynamic>> moyuSave(Map<String, dynamic> config) =>
      _request('PUT', '/api/moyu/config', body: {'config': config}).then(
        (v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{},
      );

  static Future<Map<String, dynamic>> historyToday({bool force = false}) => get(
    '/api/history/today',
    query: force ? {'force': '1'} : null,
    auth: false,
  );

  static Future<Map<String, dynamic>> cookData() => get('/api/cook');
  static Future<List<Recipe>> cookSquare() async {
    final j = await get('/api/cook/square');
    return ((j['recipes'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Recipe.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Recipe> saveRecipe(Recipe r) async {
    final j = await post('/api/cook/recipe', {'recipe': r.toJson()});
    return Recipe.fromJson(Map<String, dynamic>.from(j['recipe']));
  }

  static Future<void> deleteRecipe(String id) =>
      post('/api/cook/recipe/delete', {'id': id});

  static Future<String> uploadCookImage(String dataUrl) async {
    final j = await post('/api/cook/img', {'img': dataUrl});
    return '${j['url'] ?? ''}';
  }

  static Future<List<ShoppingItem>> saveShopping(
    List<ShoppingItem> items,
  ) async {
    final j = await post('/api/cook/shopping', {
      'shopping': items.map((e) => e.toJson()).toList(),
    });
    return ((j['shopping'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => ShoppingItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<FridgeItem>> saveFridge(List<FridgeItem> items) async {
    final j = await post('/api/cook/fridge', {
      'fridge': items.map((e) => e.toJson()).toList(),
    });
    return ((j['fridge'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => FridgeItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>> checkinStats(String? deviceId) => get(
    '/api/checkin/stats',
    query: {if (deviceId != null) 'deviceId': deviceId},
    auth: true,
  );
}
