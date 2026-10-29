import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../services/prefs.dart';

class CardFace {
  const CardFace({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.file,
    required this.width,
    required this.height,
  });

  final String id;
  final String categoryId;
  final String categoryName;
  final String file;
  final int width;
  final int height;

  String get url {
    final encoded = file.split('/').map(Uri.encodeComponent).join('/');
    return '${CardCatalog.base}/$encoded';
  }

  String get label {
    final raw = id.split('/').last;
    return RegExp(r'^\d+$').hasMatch(raw) ? raw : '特别';
  }

  double get aspect =>
      width > 0 && height > 0 ? width / height : 3 / 4;

  static CardFace? fromJson(
    Map<String, dynamic> json,
    String categoryId,
    String categoryName,
  ) {
    final id = '${json['id'] ?? ''}'.trim();
    final file = '${json['file'] ?? ''}'.trim();
    if (id.isEmpty || file.isEmpty) return null;
    final w = (json['w'] as num?)?.toInt() ?? 750;
    final h = (json['h'] as num?)?.toInt() ?? 1000;
    return CardFace(
      id: id,
      categoryId: categoryId,
      categoryName: categoryName,
      file: file,
      width: w,
      height: h,
    );
  }
}

class CardCategory {
  const CardCategory({
    required this.id,
    required this.name,
    required this.cards,
  });

  final String id;
  final String name;
  final List<CardFace> cards;
}

/// OBS 卡面目录：内置一份清单保证离线可用，联网后再用远端 index.json 更新。
class CardCatalog {
  static const String base = 'https://obs.chimu-claw.xyz/card';
  static const String remoteIndexUrl = '$base/index.json';
  static const String _bundledAsset = 'assets/cards_index.json';

  static List<CardCategory> categories = const [];
  static List<CardFace> _all = const [];
  static bool _loaded = false;
  static Future<void>? _loading;

  /// 目录异步加载完成时通知界面（由 AppState 注入）。
  static void Function()? onChanged;

  static List<CardFace> get all => _all;
  static bool get isEmpty => _all.isEmpty;

  static CardFace? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final card in _all) {
      if (card.id == id) return card;
    }
    return null;
  }

  static List<CardFace> inCategory(String id) {
    for (final category in categories) {
      if (category.id == id) return category.cards;
    }
    return const [];
  }

  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final running = _loading;
    if (running != null) return running;
    final future = _load();
    _loading = future;
    return future;
  }

  static Future<void> _load() async {
    // 上次落盘的远端目录优先，启动后无需等网络就能显示收藏。
    final cached = Prefs.getString(PrefKeys.cardsIndexCache);
    if (cached != null && _applyRaw(cached)) {
      _loaded = true;
    }
    if (!_loaded) {
      try {
        final raw = await rootBundle.loadString(_bundledAsset);
        _applyRaw(raw);
      } catch (_) {}
      _loaded = true;
    }
    unawaited(_refreshRemote());
  }

  static Future<void> _refreshRemote() async {
    try {
      final res = await http
          .get(Uri.parse(remoteIndexUrl))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final raw = utf8.decode(res.bodyBytes);
      if (_applyRaw(raw)) {
        await Prefs.setString(PrefKeys.cardsIndexCache, raw);
      }
    } catch (_) {}
  }

  static bool _applyRaw(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return false;
      final rawCategories = json['categories'];
      if (rawCategories is! List || rawCategories.isEmpty) return false;
      final parsed = <CardCategory>[];
      for (final item in rawCategories) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = '${map['id'] ?? ''}'.trim();
        final name = '${map['name'] ?? id}'.trim();
        final rawCards = map['cards'];
        if (id.isEmpty || rawCards is! List) continue;
        final cards = <CardFace>[];
        for (final card in rawCards) {
          if (card is! Map) continue;
          final face = CardFace.fromJson(
            Map<String, dynamic>.from(card),
            id,
            name,
          );
          if (face != null) cards.add(face);
        }
        if (cards.isNotEmpty) {
          parsed.add(CardCategory(id: id, name: name, cards: cards));
        }
      }
      if (parsed.isEmpty) return false;
      categories = List.unmodifiable(parsed);
      _all = List.unmodifiable([for (final c in parsed) ...c.cards]);
      onChanged?.call();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 抽一张卡面；优先没收集过的，避免总是重复。
  static CardFace? pick({
    Set<String> owned = const {},
    String? exclude,
    bool preferNew = true,
    Random? random,
  }) {
    if (_all.isEmpty) return null;
    final rnd = random ?? Random();
    final fresh = <CardFace>[
      for (final card in _all)
        if (!owned.contains(card.id) && card.id != exclude) card,
    ];
    final pool = preferNew && fresh.isNotEmpty
        ? fresh
        : [
            for (final card in _all)
              if (card.id != exclude) card,
          ];
    if (pool.isEmpty) return _all[rnd.nextInt(_all.length)];
    return pool[rnd.nextInt(pool.length)];
  }
}
