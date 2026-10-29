import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/cards.dart';
import '../services/ai.dart';
import '../services/api.dart';
import '../services/location.dart';
import '../services/models.dart';
import '../services/prefs.dart';
import '../services/notifications.dart';

class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._();

  ThemeMode themeMode = ThemeMode.system;
  User? user;
  bool booting = true;
  bool online = true;
  WeatherNow weather = WeatherNow.fallback;
  String? zodiacSign;
  ZodiacFortune? zodiacFortune;
  String? _zodiacFortuneSign;
  String? _zodiacLoadingSign;
  int _zodiacRequestId = 0;
  bool zodiacLoading = false;
  String? zodiacError;
  bool weatherLoading = false;
  String? weatherError;
  double _weatherLat = 21.4735;
  double _weatherLon = 109.1193;
  String _weatherCity = '北海';
  Future<void>? _weatherRequest;
  bool _locationAsked = false;
  int unread = 0;
  bool notificationsEnabled = true;
  int _cloudStreak = 0;
  bool _cloudCheckedToday = false;

  /// 弹层开合非常频繁；用独立 notifier 通知计时胶囊，不触发 AppScope
  /// 全量重建（否则每开一个弹窗都会重建后台社区页与首页卡片）。
  final ValueNotifier<bool> popupActiveNotifier = ValueNotifier<bool>(false);

  /// 每完成 7 局游戏获得抽卡机会时 +1，由 RootShell 监听并弹出抽卡提示。
  final ValueNotifier<int> cardPromptTick = ValueNotifier<int>(0);
  bool get popupActive => popupActiveNotifier.value;
  Set<String> _blockedUsers = <String>{};
  Timer? _notifyTimer;
  int? _lastPostTs;
  bool _postSeeded = false;

  late String gid;
  late String guestName;

  bool get loggedIn => user != null;
  String get displayName => user?.name ?? guestName;
  String? get token => Api.token;

  String get themeModeKey => switch (themeMode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  Future<void> init() async {
    await Prefs.init();
    CardCatalog.onChanged = () => notifyListeners();
    unawaited(CardCatalog.ensureLoaded());
    notificationsEnabled = Prefs.getBool(PrefKeys.notificationsEnabled, true);
    Notifications.enabled = notificationsEnabled;
    final mode = Prefs.getString(PrefKeys.theme);
    themeMode = switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    gid = Prefs.getString(PrefKeys.gid) ?? '';
    if (gid.isEmpty) {
      gid = _randomId(20);
      unawaited(Prefs.setString(PrefKeys.gid, gid));
    }
    guestName = Prefs.getString(PrefKeys.guestName) ?? '';
    if (guestName.isEmpty) {
      const names = [
        '青松明月',
        '橘子汽水',
        '晚风微醺',
        '山野拾光',
        '海盐芝士',
        '云朵收藏家',
        '林间小鹿',
        '一颗青柠',
      ];
      guestName = '游客·${names[Random().nextInt(names.length)]}';
      unawaited(Prefs.setString(PrefKeys.guestName, guestName));
    }
    _blockedUsers = Prefs.getStringList(PrefKeys.blockedUsers)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    _weatherLat =
        double.tryParse(Prefs.getString(PrefKeys.weatherLat) ?? '') ?? 21.4735;
    _weatherLon =
        double.tryParse(Prefs.getString(PrefKeys.weatherLon) ?? '') ?? 109.1193;
    _weatherCity = Prefs.getString(PrefKeys.weatherCity) ?? '北海';
    zodiacSign = Prefs.getString(PrefKeys.zodiacSign);
    final token = Prefs.getString(PrefKeys.token);
    if (token != null && token.isNotEmpty) {
      Api.token = token;
      final saved = Prefs.getString(PrefKeys.authUser);
      if (saved != null) {
        try {
          user = User.fromJson(jsonDecode(saved));
        } catch (_) {}
      }
      notifyListeners();
      unawaited(_restoreUser());
    } else if (kIsWeb) {
      // 原版网站以 httpOnly Cookie 会话为主；即使没有本地 token 也向后端确认一次。
      unawaited(_restoreUser());
    }
    booting = false;
    notifyListeners();
    unawaited(refreshWeather());
    if (zodiacSign != null) unawaited(refreshZodiacFortune());
  }

  Future<void> _restoreUser() async {
    try {
      final j = await Api.me().timeout(const Duration(seconds: 8));
      final token = j['token']?.toString() ?? '';
      if (token.isNotEmpty) Api.token = token;
      final u = User.fromJson(j['user']);
      if (u == null) {
        await _clearAuth();
      } else {
        user = u;
        final checkin = j['user'] is Map ? (j['user'] as Map)['checkin'] : null;
        if (checkin is Map) {
          _cloudStreak = _i(checkin['streak']);
          _cloudCheckedToday = checkin['checkedInToday'] == true;
        }
        await _persistAuth();
        notifyListeners();
        _startNotifyPolling();
        unawaited(syncZodiac());
        unawaited(syncCardsFromCloud());
      }
    } catch (_) {
      // 离线时保留本地登录态，网络恢复后再校验。
    }
  }

  Future<void> _persistAuth() async {
    await Prefs.setString(PrefKeys.token, Api.token);
    if (user != null) {
      await Prefs.setString(
        PrefKeys.authUser,
        jsonEncode({
          'name': user!.name,
          'av': user!.av,
          'bday': user!.bdayMonth == null
              ? null
              : {'month': user!.bdayMonth, 'day': user!.bdayDay},
          'profileDone': user!.profileDone,
        }),
      );
    } else {
      await Prefs.setString(PrefKeys.authUser, null);
    }
  }

  Future<void> _clearAuth() async {
    _notifyTimer?.cancel();
    _postSeeded = false;
    _lastPostTs = null;
    unread = 0;
    _cloudStreak = 0;
    _cloudCheckedToday = false;
    user = null;
    Api.token = null;
    await Prefs.setString(PrefKeys.token, null);
    await Prefs.setString(PrefKeys.authUser, null);
    await Prefs.setString(PrefKeys.cardOwner, null);
    await _clearLocalCardState();
    notifyListeners();
  }

  Future<void> login(String phone, String password) async {
    final j = await Api.login(phone, password);
    Api.token = j['token']?.toString();
    user = User.fromJson(j['user']);
    await _persistAuth();
    notifyListeners();
    _startNotifyPolling();
    unawaited(syncZodiac());
    unawaited(_loadCheckin());
    unawaited(syncCardsFromCloud());
  }

  Future<void> register(
    String phone,
    String name,
    String password,
    String invite,
  ) async {
    final j = await Api.register(phone, name, password, invite);
    Api.token = j['token']?.toString();
    user = User.fromJson(j['user']);
    await _persistAuth();
    notifyListeners();
    _startNotifyPolling();
    unawaited(syncZodiac());
    unawaited(_loadCheckin());
    unawaited(syncCardsFromCloud());
  }

  Future<void> logout() async {
    try {
      await Api.logout();
    } catch (_) {}
    await _clearAuth();
  }

  /// 注销账号：服务端删除账号与全部个人数据，本机同步清理登录态与账号缓存。
  Future<void> deleteAccount(String password) async {
    await Api.deleteAccount(password);
    _zodiacRequestId++;
    await _clearAuth();
    try {
      await Prefs.clearAccountData();
    } catch (_) {}
    zodiacSign = null;
    zodiacFortune = null;
    _zodiacFortuneSign = null;
    _zodiacLoadingSign = null;
    zodiacLoading = false;
    zodiacError = null;
    notifyListeners();
  }

  Set<String> get blockedUsers => Set.unmodifiable(_blockedUsers);

  bool isBlocked(String nick) {
    final n = nick.trim();
    return n.isNotEmpty && _blockedUsers.contains(n);
  }

  bool canBlock(String nick) {
    final n = nick.trim();
    return n.isNotEmpty && n != user?.name;
  }

  Future<void> blockUser(String nick) async {
    final n = nick.trim();
    if (!canBlock(n) || !_blockedUsers.add(n)) return;
    await Prefs.setStringList(PrefKeys.blockedUsers, _blockedUsers.toList());
    notifyListeners();
  }

  Future<void> unblockUser(String nick) async {
    if (!_blockedUsers.remove(nick.trim())) return;
    await Prefs.setStringList(PrefKeys.blockedUsers, _blockedUsers.toList());
    notifyListeners();
  }

  Future<void> updateUser(User u) async {
    user = u;
    await _persistAuth();
    notifyListeners();
  }

  void _startNotifyPolling() {
    _notifyTimer?.cancel();
    _refreshUnread();
    _postSeeded = false;
    _lastPostTs = null;
    unawaited(_seedCommunityPosts());
    _notifyTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _refreshUnread();
      unawaited(_refreshCommunityPosts());
    });
  }

  Future<void> _seedCommunityPosts() async {
    if (!loggedIn) return;
    try {
      final list = await Api.posts();
      var newest = 0;
      for (final p in list) {
        if (p.ts > newest) newest = p.ts;
      }
      _lastPostTs = newest;
      _postSeeded = true;
    } catch (_) {}
  }

  Future<void> _refreshCommunityPosts() async {
    if (!loggedIn || !_postSeeded) {
      if (!_postSeeded) await _seedCommunityPosts();
      return;
    }
    try {
      final list = await Api.posts();
      if (list.isEmpty) return;
      final previous = _lastPostTs ?? 0;
      final fresh = list.where((p) => !p.mine && p.ts > previous).toList();
      var newest = previous;
      for (final p in list) {
        if (p.ts > newest) newest = p.ts;
      }
      _lastPostTs = newest;
      if (fresh.isEmpty || !notificationsEnabled) return;
      fresh.sort((a, b) => b.ts.compareTo(a.ts));
      final latest = fresh.first;
      final text = latest.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      final preview = text.isNotEmpty
          ? (text.length > 72 ? '${text.substring(0, 72)}…' : text)
          : latest.imgs.isNotEmpty
          ? '发布了新图片'
          : latest.voice != null
          ? '发布了语音动态'
          : '发布了新动态';
      await Notifications.show(
        'Citro 社区',
        text.isNotEmpty ? '${latest.nick}：$preview' : '${latest.nick} $preview',
      );
    } catch (_) {}
  }

  Future<void> _refreshUnread() async {
    if (!loggedIn) return;
    try {
      final j = await Api.notifications();
      final n = int.tryParse('${j['unread'] ?? 0}') ?? 0;
      if (n != unread) {
        final grew = n > unread && unread >= 0;
        unread = n;
        notifyListeners();
        if (grew && notificationsEnabled)
          unawaited(Notifications.show('Citro 社区', '你有 $n 条新消息'));
      }
    } catch (_) {}
  }

  void setUnread(int n) {
    if (unread == n) return;
    unread = n;
    notifyListeners();
  }

  void setPopupActive(bool active) {
    if (popupActiveNotifier.value == active) return;
    popupActiveNotifier.value = active;
  }

  Future<void> setNotificationsEnabled(bool value) async {
    if (notificationsEnabled == value) return;
    notificationsEnabled = value;
    Notifications.enabled = value;
    await Prefs.setBool(PrefKeys.notificationsEnabled, value);
    notifyListeners();
  }

  Future<void> updateGuestName(String name) async {
    guestName = name;
    await Prefs.setString(PrefKeys.guestName, name);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    Prefs.setString(PrefKeys.theme, themeModeKey);
    notifyListeners();
  }

  Future<bool> refreshWeatherWithLocation({bool force = false}) async {
    if (!force && _locationAsked) return false;
    _locationAsked = true;
    final loc = await LocationService.current();
    if (loc == null) return false;
    _weatherLat = loc.latitude;
    _weatherLon = loc.longitude;
    _weatherCity = loc.city.isNotEmpty ? loc.city : '当前位置';
    await Prefs.setString(PrefKeys.weatherLat, '$_weatherLat');
    await Prefs.setString(PrefKeys.weatherLon, '$_weatherLon');
    await Prefs.setString(PrefKeys.weatherCity, _weatherCity);
    await refreshWeather();
    return true;
  }

  Future<void> refreshWeather() {
    final ongoing = _weatherRequest;
    if (ongoing != null) return ongoing;
    final future = _doRefreshWeather();
    _weatherRequest = future;
    future.whenComplete(() {
      if (identical(_weatherRequest, future)) _weatherRequest = null;
    });
    return future;
  }

  Future<void> _doRefreshWeather() async {
    weatherLoading = true;
    weatherError = null;
    notifyListeners();
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '$_weatherLat',
        'longitude': '$_weatherLon',
        'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m',
        'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset',
        'hourly': 'temperature_2m,weather_code,precipitation_probability',
        'timezone': 'Asia/Shanghai',
        'forecast_days': '7',
        'forecast_hours': '24',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final cur = Map<String, dynamic>.from(j['current'] as Map);
      final daily = Map<String, dynamic>.from(j['daily'] as Map);
      final hourlyRaw = j['hourly'] is Map
          ? Map<String, dynamic>.from(j['hourly'] as Map)
          : <String, dynamic>{};
      final hourlyTimes = (hourlyRaw['time'] as List?) ?? [];
      final hourly = <HourlyWeather>[];
      for (var i = 0; i < hourlyTimes.length; i++) {
        final time = DateTime.tryParse('${hourlyTimes[i]}');
        if (time == null) continue;
        hourly.add(
          HourlyWeather(
            time: time,
            code: _i((hourlyRaw['weather_code'] as List?)?[i]),
            temp: _d((hourlyRaw['temperature_2m'] as List?)?[i]),
            rain: _i((hourlyRaw['precipitation_probability'] as List?)?[i]),
          ),
        );
      }
      final dates = (daily['time'] as List?) ?? [];
      final days = <DailyWeather>[];
      for (var i = 0; i < dates.length; i++) {
        days.add(
          DailyWeather(
            date: DateTime.tryParse('${dates[i]}') ?? DateTime.now(),
            code: _i((daily['weather_code'] as List)[i]),
            max: _d((daily['temperature_2m_max'] as List)[i]),
            min: _d((daily['temperature_2m_min'] as List)[i]),
            rain: _i((daily['precipitation_probability_max'] as List?)?[i]),
            sunrise: DateTime.tryParse('${(daily['sunrise'] as List)[i]}'),
            sunset: DateTime.tryParse('${(daily['sunset'] as List)[i]}'),
          ),
        );
      }
      final now = DateTime.now();
      weather = WeatherNow(
        temp: _d(cur['temperature_2m']),
        feels: _d(cur['apparent_temperature']),
        humidity: _i(cur['relative_humidity_2m']),
        wind: _d(cur['wind_speed_10m']),
        windDir: _d(cur['wind_direction_10m']),
        code: _i(cur['weather_code']),
        city: _weatherCity,
        updated:
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        daily: days,
        hourly: hourly,
      );
      online = true;
    } catch (e) {
      online = false;
      weatherError = '天气加载失败';
    } finally {
      weatherLoading = false;
      notifyListeners();
    }
  }

  int localBest(String game) {
    final raw = Prefs.getString(PrefKeys.gameBest);
    if (raw == null) return 0;
    try {
      final m = jsonDecode(raw) as Map;
      return _i(m[game]);
    } catch (_) {
      return 0;
    }
  }

  Future<void> saveLocalBest(String game, int score) async {
    if (score <= localBest(game)) return;
    Map<String, dynamic> m = {};
    try {
      m = jsonDecode(
        Prefs.getString(PrefKeys.gameBest) ?? '{}',
      ) as Map<String, dynamic>;
    } catch (_) {}
    m[game] = score;
    await Prefs.setString(PrefKeys.gameBest, jsonEncode(m));
  }

  Future<Map<String, dynamic>> submitScore(
    String game,
    int score, {
    bool countRound = true,
  }) async {
    await saveLocalBest(game, score);
    if (countRound) unawaited(noteGameRound());
    try {
      return await Api.gameScore(
        game,
        score,
        name: loggedIn ? null : guestName,
        gid: loggedIn ? null : gid,
      );
    } catch (e) {
      return {'ok': false, 'err': '$e'};
    }
  }

  Future<Map<String, dynamic>> fetchBoard(String game) async {
    try {
      return await Api.gameBoard(
        game,
        name: loggedIn ? null : guestName,
        gid: loggedIn ? null : gid,
      );
    } catch (e) {
      return {'ok': false, 'err': '$e'};
    }
  }

  Future<void> setZodiacSign(String sign) async {
    zodiacSign = sign;
    await Prefs.setString(PrefKeys.zodiacSign, sign);
    notifyListeners();
    unawaited(refreshZodiacFortune(force: true));
    unawaited(() async {
      try {
        await Api.zodiacLock(sign, gid);
      } catch (_) {}
    }());
  }

  Future<void> syncZodiac() async {
    try {
      final j = await Api.zodiacGet(gid);
      final sign = j['sign']?.toString();
      if (sign != null && sign.isNotEmpty) {
        final changed = zodiacSign != sign;
        zodiacSign = sign;
        await Prefs.setString(PrefKeys.zodiacSign, sign);
        notifyListeners();
        if (changed) unawaited(refreshZodiacFortune(force: true));
      }
    } catch (_) {}
  }

  Future<void> refreshZodiacFortune({bool force = false}) async {
    final sign = zodiacSign;
    if (sign == null) return;
    final signInfo = zodiacById(sign) ?? kZodiacSigns.first;
    final today = _dayKey(DateTime.now());
    final cacheKey = 'citro_zodiac_ai_${sign}_$today';
    if (_zodiacFortuneSign != sign) {
      zodiacFortune = null;
      _zodiacFortuneSign = sign;
      zodiacError = null;
      notifyListeners();
    }
    if (!force) {
      final raw = Prefs.getString(cacheKey);
      if (raw != null) {
        try {
          final parsed = ZodiacFortune.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
          if (parsed.isComplete) {
            zodiacFortune = parsed;
            zodiacError = null;
            notifyListeners();
            return;
          }
        } catch (_) {}
      }
    }
    if (zodiacLoading && _zodiacLoadingSign == sign) return;
    final requestId = ++_zodiacRequestId;
    _zodiacLoadingSign = sign;
    zodiacLoading = true;
    zodiacError = null;
    notifyListeners();
    try {
      final f = await _generateZodiacFortune(signInfo);
      if (requestId != _zodiacRequestId || zodiacSign != sign) return;
      zodiacFortune = f;
      _zodiacFortuneSign = sign;
      await Prefs.setString(cacheKey, jsonEncode(f.toJson()));
    } on AiException catch (e) {
      if (requestId == _zodiacRequestId) zodiacError = e.message;
    } catch (_) {
      if (requestId == _zodiacRequestId) zodiacError = '星语生成失败，请稍后再试';
    } finally {
      if (requestId == _zodiacRequestId) {
        zodiacLoading = false;
        _zodiacLoadingSign = null;
        notifyListeners();
      }
    }
  }

  Future<ZodiacFortune> _generateZodiacFortune(ZodiacSign sign) async {
    final now = DateTime.now();
    final prompt = [
      '日期：${now.year}年${now.month}月${now.day}日',
      '星座：${sign.name}（${sign.element}象星座，${sign.range}）',
      '请生成这个星座当天的专属运势。要求：',
      '1. 全部原创，具体、有画面感，语气温柔但不鸡汤；',
      '2. 不要提 AI、模型或提示词，不要 Markdown、标题、分点；',
      '3. 只输出一个 JSON 对象，不要代码块和解释，字段固定为：',
      '{"score":0到100的整数,"tag":"4到8个汉字的关键词","text":"50到80个汉字的今日短评","love":0到100的整数,"work":0到100的整数,"wealth":0到100的整数,"health":0到100的整数,"color":"2到4个汉字的幸运色","number":"1到99的幸运数字","item":"2到6个汉字的幸运物"}',
      '整体分数、四项指数和今日短评的情绪要一致。',
    ].join(String.fromCharCode(10));
    for (var attempt = 0; attempt < 2; attempt++) {
      final raw = await AiService.complete(
        prompt: prompt,
        system: '你是温柔、审美在线的中文星座编辑，擅长写短小、具体的每日运势。只输出严格 JSON。',
        maxTokens: 520,
        temperature: .95,
      );
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < 0 || end <= start) continue;
      try {
        final j = jsonDecode(raw.substring(start, end + 1));
        if (j is Map) {
          final f = ZodiacFortune.fromAiJson(Map<String, dynamic>.from(j));
          if (f != null) return f;
        }
      } catch (_) {}
    }
    throw AiException('星语格式异常，请重试');
  }

  /* ---------------- 卡面收藏 ---------------- */

  /// 卡面按北京时间跨日，和后端 dayStr() 对齐。
  static String _cardDayKey(DateTime d) {
    final c = d.toUtc().add(const Duration(hours: 8));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${c.year.toString().padLeft(4, '0')}-${two(c.month)}-${two(c.day)}';
  }

  Set<String> get ownedCards =>
      Prefs.getStringList(PrefKeys.cardsOwned).toSet();

  int get cardOwnedCount => ownedCards.length;

  int get cardCredits => Prefs.getInt(PrefKeys.cardCredits, 0);

  String? get todayCardId {
    final raw = Prefs.getString(PrefKeys.cardsToday);
    if (raw == null) return null;
    final split = raw.indexOf(':');
    if (split <= 0) return null;
    if (raw.substring(0, split) != _cardDayKey(DateTime.now())) return null;
    final id = raw.substring(split + 1);
    return id.isEmpty ? null : id;
  }

  List<String> _cardCandidates() => [for (final card in CardCatalog.all) card.id];

  Map<String, dynamic> _localCardPayload({required bool migrate}) {
    final day = _cardDayKey(DateTime.now());
    final payload = <String, dynamic>{
      'owned': ownedCards.toList(),
      'today': todayCardId,
      'migrate': migrate,
    };
    if (migrate) {
      payload['credits'] = cardCredits;
      payload['gameRounds'] = _todayCount(PrefKeys.cardGameRounds);
      payload['gameDraws'] = _todayCount(PrefKeys.cardGameDraws);
      payload['flags'] = {
        'post': Prefs.getString(PrefKeys.cardPostDay) == day,
        'recipe': Prefs.getString(PrefKeys.cardRecipeDay) == day,
        'chat': Prefs.getString(PrefKeys.cardChatDay) == day,
      };
    }
    return payload;
  }

  Future<void> _clearLocalCardState() async {
    await Prefs.setStringList(PrefKeys.cardsOwned, const []);
    await Prefs.setString(PrefKeys.cardsToday, null);
    await Prefs.setInt(PrefKeys.cardCredits, 0);
    await Prefs.setString(PrefKeys.cardGameRounds, null);
    await Prefs.setString(PrefKeys.cardGameDraws, null);
    await Prefs.setString(PrefKeys.cardPostDay, null);
    await Prefs.setString(PrefKeys.cardRecipeDay, null);
    await Prefs.setString(PrefKeys.cardChatDay, null);
    notifyListeners();
  }

  Future<void> _applyCardCloud(Map<String, dynamic> state) async {
    final owned = (state['owned'] as List? ?? const [])
        .whereType<String>()
        .toList();
    await Prefs.setStringList(PrefKeys.cardsOwned, owned);
    await Prefs.setInt(
      PrefKeys.cardCredits,
      (state['credits'] as num?)?.toInt() ?? 0,
    );
    final day = state['date']?.toString() ?? _cardDayKey(DateTime.now());
    final today = state['today']?.toString() ?? '';
    await Prefs.setString(
      PrefKeys.cardsToday,
      today.isEmpty ? null : '$day:$today',
    );
    await Prefs.setString(
      PrefKeys.cardGameRounds,
      '$day:${(state['gameRounds'] as num?)?.toInt() ?? 0}',
    );
    await Prefs.setString(
      PrefKeys.cardGameDraws,
      '$day:${(state['gameDraws'] as num?)?.toInt() ?? 0}',
    );
    final flags = state['flags'] is Map
        ? Map<String, dynamic>.from(state['flags'] as Map)
        : const <String, dynamic>{};
    await Prefs.setString(
      PrefKeys.cardPostDay,
      flags['post'] == true ? day : null,
    );
    await Prefs.setString(
      PrefKeys.cardRecipeDay,
      flags['recipe'] == true ? day : null,
    );
    await Prefs.setString(
      PrefKeys.cardChatDay,
      flags['chat'] == true ? day : null,
    );
    notifyListeners();
  }

  /// 登录后把本机已有机进度合并到账号，其他端随后会拿到同一份收藏与次数。
  Future<void> syncCardsFromCloud({bool force = false}) async {
    if (user == null || Api.token == null) return;
    try {
      final owner = Prefs.getString(PrefKeys.cardOwner);
      var migrate = owner == null || owner.isEmpty;
      if (!force && owner != null && owner.isNotEmpty && owner != user!.name) {
        await _clearLocalCardState();
        migrate = false;
      }
      final local = (owner == null || owner.isEmpty || owner == user!.name)
          ? _localCardPayload(migrate: migrate)
          : <String, dynamic>{};
      final j = await Api.cardsSync(local);
      await Prefs.setString(PrefKeys.cardOwner, user!.name);
      final state = j['state'] is Map
          ? Map<String, dynamic>.from(j['state'] as Map)
          : j;
      await _applyCardCloud(state);
    } catch (_) {}
  }

  Future<CardFace?> _cloudToday({required bool reroll}) async {
    if (user == null || Api.token == null) return null;
    await CardCatalog.ensureLoaded();
    final candidates = _cardCandidates();
    if (candidates.isEmpty) return null;
    try {
      final j = await Api.cardsToday(candidates: candidates, reroll: reroll);
      if (j['state'] is Map) {
        await _applyCardCloud(Map<String, dynamic>.from(j['state'] as Map));
      }
      return CardCatalog.byId(j['card']?.toString());
    } on ApiException catch (e) {
      if (e.code != 0 && e.code != 404) return null;
    } catch (_) {}
    return null;
  }

  Future<void> _unlockCard(String id) async {
    if (id.isEmpty) return;
    final owned = Prefs.getStringList(PrefKeys.cardsOwned);
    if (owned.contains(id)) return;
    owned.add(id);
    await Prefs.setStringList(PrefKeys.cardsOwned, owned);
  }

  /// 今日打卡的卡面：同一天保持稳定，打卡/转运时各抽一次。
  Future<CardFace?> ensureTodayCard() async {
    await CardCatalog.ensureLoaded();
    if (user != null && Api.token != null) {
      final cloud = await _cloudToday(reroll: false);
      if (cloud != null) return cloud;
    }
    final current = CardCatalog.byId(todayCardId);
    if (current != null) return current;
    final picked = CardCatalog.pick(owned: ownedCards);
    if (picked == null) return null;
    await Prefs.setString(
      PrefKeys.cardsToday,
      '${_cardDayKey(DateTime.now())}:${picked.id}',
    );
    await _unlockCard(picked.id);
    notifyListeners();
    return picked;
  }

  Future<CardFace?> redrawTodayCard() async {
    await CardCatalog.ensureLoaded();
    if (user != null && Api.token != null) {
      final cloud = await _cloudToday(reroll: true);
      if (cloud != null) return cloud;
    }
    final current = CardCatalog.byId(todayCardId);
    final picked = CardCatalog.pick(owned: ownedCards, exclude: current?.id);
    if (picked == null) return null;
    await Prefs.setString(
      PrefKeys.cardsToday,
      '${_cardDayKey(DateTime.now())}:${picked.id}',
    );
    await _unlockCard(picked.id);
    notifyListeners();
    return picked;
  }

  Future<CardFace?> drawCardFromCredit() async {
    if (cardCredits <= 0) return null;
    await CardCatalog.ensureLoaded();
    if (user != null && Api.token != null) {
      final candidates = _cardCandidates();
      if (candidates.isNotEmpty) {
        try {
          final j = await Api.cardsDraw(candidates);
          if (j['state'] is Map) {
            await _applyCardCloud(Map<String, dynamic>.from(j['state'] as Map));
          }
          final face = CardCatalog.byId(j['card']?.toString());
          if (face != null) return face;
        } on ApiException catch (e) {
          if (e.code != 0 && e.code != 404) {
            if (e.code == 400) await syncCardsFromCloud(force: true);
            return null;
          }
        } catch (_) {}
      }
    }
    final picked = CardCatalog.pick(owned: ownedCards);
    if (picked == null) return null;
    await Prefs.setInt(PrefKeys.cardCredits, cardCredits - 1);
    await _unlockCard(picked.id);
    notifyListeners();
    return picked;
  }

  Future<void> _addCardCredit() async {
    await Prefs.setInt(PrefKeys.cardCredits, cardCredits + 1);
    notifyListeners();
  }

  Future<bool> _firstToday(String key) async {
    final today = _cardDayKey(DateTime.now());
    if (Prefs.getString(key) == today) return false;
    await Prefs.setString(key, today);
    return true;
  }

  Future<bool> _grantCardDraw(String source, String dayKey) async {
    if (user != null && Api.token != null) {
      try {
        final j = await Api.cardsGrant(source);
        if (j['state'] is Map) {
          await _applyCardCloud(Map<String, dynamic>.from(j['state'] as Map));
        }
        return j['granted'] == true;
      } on ApiException catch (e) {
        if (e.code != 0 && e.code != 404) return false;
      } catch (_) {}
    }
    if (!await _firstToday(dayKey)) return false;
    await _addCardCredit();
    return true;
  }

  /// 每完成 7 局任意游戏给一次抽卡机会，每天最多两次。
  Future<bool> noteGameRound() async {
    if (user != null && Api.token != null) {
      try {
        final j = await Api.cardsGrant('gameRound');
        if (j['state'] is Map) {
          await _applyCardCloud(Map<String, dynamic>.from(j['state'] as Map));
        }
        final granted = j['granted'] == true;
        if (granted) cardPromptTick.value++;
        return granted;
      } on ApiException catch (e) {
        if (e.code != 0 && e.code != 404) return false;
      } catch (_) {}
    }
    final today = _cardDayKey(DateTime.now());
    final rounds = _bumpTodayCount(PrefKeys.cardGameRounds);
    if (rounds % 7 != 0) return false;
    final draws = _todayCount(PrefKeys.cardGameDraws);
    if (draws >= 2) return false;
    await Prefs.setString(PrefKeys.cardGameDraws, '$today:${draws + 1}');
    await _addCardCredit();
    cardPromptTick.value++;
    return true;
  }

  Future<bool> grantPostCardDraw() =>
      _grantCardDraw('post', PrefKeys.cardPostDay);

  Future<bool> grantRecipeCardDraw() =>
      _grantCardDraw('recipe', PrefKeys.cardRecipeDay);

  Future<bool> grantChatCardDraw() =>
      _grantCardDraw('chat', PrefKeys.cardChatDay);

  int _todayCount(String key) {
    final raw = Prefs.getString(key);
    if (raw == null) return 0;
    final split = raw.indexOf(':');
    if (split <= 0) return 0;
    if (raw.substring(0, split) != _cardDayKey(DateTime.now())) return 0;
    return int.tryParse(raw.substring(split + 1)) ?? 0;
  }

  int _bumpTodayCount(String key) {
    final next = _todayCount(key) + 1;
    Prefs.setString(key, '${_cardDayKey(DateTime.now())}:$next');
    return next;
  }

  Future<bool> checkIn() async {
    await drawFortuneIdx();
    return checkedInToday;
  }

  int? get todayFortuneIdx {
    final raw = Prefs.getString(PrefKeys.checkinFortune);
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    if (parts[0] != _dayKey(DateTime.now())) return null;
    return int.tryParse(parts[1]);
  }

  Future<int> drawFortuneIdx() async {
    final cached = todayFortuneIdx;
    if (cached != null) {
      // 登录状态下即使本地有缓存，也向服务端确认/补一次打卡，保证跨端天数一致。
      await _syncCloudCheckin(migrate: true);
      // 另一台设备做过「转运」时，把服务端结果同步回来。
      try {
        final j = await Api.draw(deviceId: gid);
        final remoteIdx = int.tryParse('${j['idx']}');
        final today = _dayKey(DateTime.now());
        if (remoteIdx != null && remoteIdx != cached) {
          await Prefs.setString(PrefKeys.checkinFortune, '$today:$remoteIdx');
          if (j['transfer'] == true) {
            await Prefs.setString(PrefKeys.checkinTransferUsed, today);
          }
          notifyListeners();
          return remoteIdx;
        }
      } catch (_) {}
      return cached;
    }
    int? idx;
    try {
      final j = await Api.drawTake(deviceId: gid);
      idx = int.tryParse('${j['idx']}');
    } catch (_) {}
    idx ??= Random().nextInt(8);
    final today = _dayKey(DateTime.now());
    await Prefs.setString(PrefKeys.checkinFortune, '$today:$idx');
    final last = Prefs.getString(PrefKeys.checkinLast) ?? '';
    if (last != today) {
      final streak = Prefs.getInt(PrefKeys.checkinStreak, 0);
      final yesterday = _dayKey(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      final newStreak = last == yesterday ? streak + 1 : 1;
      await Prefs.setString(PrefKeys.checkinLast, today);
      await Prefs.setInt(PrefKeys.checkinStreak, newStreak);
    }
    await _syncCloudCheckin(migrate: true);
    notifyListeners();
    return idx;
  }

  /// 今日抽到下签 / 下下签时才需要转运（idx 6 = 下签，7 = 下下签）。
  bool get fortuneIsBad {
    final idx = todayFortuneIdx;
    return idx == 6 || idx == 7;
  }

  bool get fortuneTransferUsed =>
      Prefs.getString(PrefKeys.checkinTransferUsed) ==
      _dayKey(DateTime.now());

  /// 跟 CiCi 分享好事后到账的转运机会（当天有效，用一次）。
  bool get fortuneTransferReady {
    if (fortuneTransferUsed || !fortuneIsBad) return false;
    return Prefs.getString(PrefKeys.checkinTransfer) == _dayKey(DateTime.now());
  }

  Future<void> grantFortuneTransfer() async {
    if (!fortuneIsBad || fortuneTransferUsed) return;
    await Prefs.setString(PrefKeys.checkinTransfer, _dayKey(DateTime.now()));
    notifyListeners();
  }

  /// 把跟 CiCi 分享的好事收进「好事记录」笔记（仅登录用户）。
  /// 只保留一份笔记、新内容放最上面；超过服务端 5000 字上限时裁掉最旧的。
  Future<bool> recordGoodDeed(String text) async {
    final body = text.trim();
    if (!loggedIn || body.isEmpty) return false;
    final now = DateTime.now();
    final stamp =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final entry = '$body\n$stamp';
    try {
      final list = await Api.notes();
      final existing = list.where((n) => n.title == '好事记录').toList();
      if (existing.isEmpty) {
        await Api.saveNote(title: '好事记录', content: entry);
        return true;
      }
      final note = existing.first;
      var content = note.content.trim();
      content = content.isEmpty ? entry : '$entry\n\n$content';
      if (content.length > 4800) {
        final parts = content.split('\n\n');
        final kept = <String>[];
        var length = 0;
        for (final part in parts) {
          final add = part.length + (kept.isEmpty ? 0 : 2);
          if (length + add > 4800) break;
          kept.add(part);
          length += add;
        }
        content = kept.join('\n\n');
      }
      await Api.saveNote(id: note.id, title: '好事记录', content: content);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 消耗转运机会重抽一签：服务端只允许下签重抽一次，且只给 0..5 的签。
  Future<int?> useFortuneTransfer() async {
    if (!fortuneTransferReady) return null;
    final today = _dayKey(DateTime.now());
    int? idx;
    var offline = false;
    var rejected = false;
    try {
      final j = await Api.drawReroll(deviceId: gid);
      idx = int.tryParse('${j['idx']}');
    } on ApiException catch (e) {
      if (e.code == 409) {
        // 服务端已经转运过（比如另一台设备）：取回当前结果，不再本地重抽。
        try {
          final j = await Api.draw(deviceId: gid);
          idx = int.tryParse('${j['idx']}');
        } catch (_) {}
        if (idx == null) rejected = true;
      } else if (e.code == 404 || e.code == 405 || e.code == 501) {
        // 后端还没部署转运接口：退回本机重抽，保证客户端先升级也能玩。
        offline = true;
      } else if (e.code >= 400) {
        rejected = true;
      } else {
        offline = true;
      }
    } catch (_) {
      offline = true;
    }
    if (rejected) return null;
    if (idx == null && !offline) return null;
    idx ??= Random().nextInt(6);
    await Prefs.setString(PrefKeys.checkinFortune, '$today:$idx');
    await Prefs.setString(PrefKeys.checkinTransferUsed, today);
    await Prefs.setString(PrefKeys.checkinTransfer, null);
    notifyListeners();
    return idx;
  }

  Future<void> _loadCheckin() async {
    if (!loggedIn) return;
    try {
      final j = await Api.checkinStats(gid);
      _cloudStreak = _i(j['streak']);
      _cloudCheckedToday = j['checkedInToday'] == true;
      notifyListeners();
      // 服务端还没有记录、本地却有连续天数：登录后立刻迁移，避免显示归零。
      if (_cloudStreak == 0 && !_cloudCheckedToday && _localStreak > 0) {
        await _syncCloudCheckin(migrate: true);
      }
    } catch (_) {}
  }

  Future<void> _syncCloudCheckin({bool migrate = false}) async {
    if (!loggedIn) return;
    try {
      final j = _cloudCheckedToday
          ? await Api.checkinStats(gid)
          : await Api.checkinTake(
              deviceId: gid,
              last: migrate ? Prefs.getString(PrefKeys.checkinLast) : null,
              streak: migrate ? Prefs.getInt(PrefKeys.checkinStreak, 0) : null,
            );
      _cloudStreak = _i(j['streak']);
      _cloudCheckedToday = j['checkedInToday'] == true;
      notifyListeners();
    } catch (_) {
      // 离线时保留本地记录兜底；恢复网络后再同步。
    }
  }

  int get _localStreak {
    final last = Prefs.getString(PrefKeys.checkinLast) ?? '';
    final today = _dayKey(DateTime.now());
    final yesterday = _dayKey(DateTime.now().subtract(const Duration(days: 1)));
    if (last == today || last == yesterday)
      return Prefs.getInt(PrefKeys.checkinStreak, 0);
    return 0;
  }

  bool get _localCheckedInToday =>
      Prefs.getString(PrefKeys.checkinLast) == _dayKey(DateTime.now());

  int get checkinStreak {
    if (loggedIn) return _cloudStreak > 0 ? _cloudStreak : _localStreak;
    return _localStreak;
  }

  bool get checkedInToday {
    if (loggedIn) return _cloudCheckedToday || _localCheckedInToday;
    return _localCheckedInToday;
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _randomId(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static int _i(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.round();
    return int.tryParse('$v') ?? 0;
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }
}

extension AppContextX on BuildContext {
  AppState get app => AppScope.of(this);
}
