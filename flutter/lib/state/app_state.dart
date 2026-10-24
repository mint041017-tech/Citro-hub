import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

  /// 弹层开合非常频繁；用独立 notifier 通知计时胶囊，不触发 AppScope
  /// 全量重建（否则每开一个弹窗都会重建后台社区页与首页卡片）。
  final ValueNotifier<bool> popupActiveNotifier = ValueNotifier<bool>(false);
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
        await _persistAuth();
        notifyListeners();
        _startNotifyPolling();
        unawaited(syncZodiac());
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
    user = null;
    Api.token = null;
    await Prefs.setString(PrefKeys.token, null);
    await Prefs.setString(PrefKeys.authUser, null);
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

  Future<Map<String, dynamic>> submitScore(String game, int score) async {
    await saveLocalBest(game, score);
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
    if (cached != null) return cached;
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
    notifyListeners();
    return idx;
  }

  int get checkinStreak {
    final last = Prefs.getString(PrefKeys.checkinLast) ?? '';
    final today = _dayKey(DateTime.now());
    final yesterday = _dayKey(DateTime.now().subtract(const Duration(days: 1)));
    if (last == today || last == yesterday)
      return Prefs.getInt(PrefKeys.checkinStreak, 0);
    return 0;
  }

  bool get checkedInToday =>
      Prefs.getString(PrefKeys.checkinLast) == _dayKey(DateTime.now());

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
