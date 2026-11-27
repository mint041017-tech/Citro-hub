import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../checkin/checkin_store.dart';
import '../data/cards.dart';
import '../mbti/store.dart';
import '../kei/store.dart';
import '../services/ai.dart';
import '../services/api.dart';
import '../services/location.dart';
import '../services/models.dart';
import '../services/prefs.dart';
import '../services/notifications.dart';
import '../services/push_notifications.dart';
import '../services/weather_api.dart';

/// 服务端抽好的具体签位置，必须是 0..5；旧响应没有这个字段时返回 null。
int? _fortuneSlotValue(Object? raw) {
  final slot = int.tryParse('${raw ?? ''}');
  if (slot == null || slot < 0 || slot >= 6) return null;
  return slot;
}

class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._();

  ThemeMode themeMode = ThemeMode.system;
  User? user;
  bool booting = true;
  bool online = true;
  WeatherNow weather = WeatherNow.fallback;
  bool weatherLoading = false;
  String? weatherError;
  double _weatherLat = 21.4735;
  double _weatherLon = 109.1193;
  String _weatherCity = '北海';
  Future<void>? _weatherRequest;
  String _weatherInFlightKey = '';
  int _weatherEpoch = 0;
  bool _locationAsked = false;

  /// 用户手动选过城市：启动时的自动定位不再覆盖，只有点「定位并刷新」才重新定位。
  bool _weatherCityManual = false;
  int unread = 0;
  bool notificationsEnabled = true;
  bool _pushBindingBlocked = false;

  /// 登录态代数：登出清理是异步的，期间可能已经重新登录。
  /// 每次登录 / 登出自增，旧的清理流程发现代数变了就停手，
  /// 避免把新会话的 token / 卡面缓存又清掉。
  int _authEpoch = 0;
  bool reduceMotion = false;
  // HyperOS / MIUI 在后台会限制网络与 CPU；退到后台后暂停未读/动态轮询，
  // 回前台再补一次，避免每分钟醒来发请求。
  bool _foreground = true;

  /// CiCi 的自定义性格；空字符串表示使用内置的默认性格。
  String ciciPersona = '';
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
    PushNotifications.onToken = (_) => unawaited(_syncPushBinding());
    CardCatalog.onChanged = () => notifyListeners();
    unawaited(CardCatalog.ensureLoaded());
    notificationsEnabled = Prefs.getBool(PrefKeys.notificationsEnabled, true);
    Notifications.enabled = notificationsEnabled;
    reduceMotion = Prefs.getBool(PrefKeys.reduceMotion, false);
    ciciPersona = Prefs.getString(PrefKeys.ciciPersona) ?? '';
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
    _weatherCityManual = Prefs.getBool(PrefKeys.weatherCityManual);
    // 上次选的 / 定位到的城市先显示出来，别让卡片一直停在默认城市上等接口。
    weather = weather.copyWith(city: _weatherCity);
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
    await CheckinStore.instance.ensureInit(account: user?.name);
    booting = false;
    notifyListeners();
    unawaited(refreshWeather());
  }

  Future<void> _restoreUser() async {
    try {
      final j = await Api.me().timeout(const Duration(seconds: 8));
      if (_pushBindingBlocked) return;
      final token = j['token']?.toString() ?? '';
      if (token.isNotEmpty) Api.token = token;
      final u = User.fromJson(j['user']);
      if (u == null) {
        await MbtiStore.clearLocal();
        await KeiStore.clearLocal();
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
        unawaited(CheckinStore.instance.onAccountChanged(u.name));
        _startNotifyPolling();
        unawaited(syncCardsFromCloud());
        unawaited(MbtiStore.syncFromAccount(account: u.name, force: true));
        unawaited(KeiStore.syncFromAccount(account: u.name, force: true));
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
    _pushBindingBlocked = true;
    final epoch = ++_authEpoch;
    final account = user?.name;
    _notifyTimer?.cancel();
    _postSeeded = false;
    _lastPostTs = null;
    unread = 0;
    _cloudStreak = 0;
    _cloudCheckedToday = false;
    user = null;
    Api.token = null;
    unawaited(CheckinStore.instance.onAccountChanged(null));
    // 先通知，让 SplashGate 立刻切登录页。Push 解绑和 8 个 Prefs 写入
    // 都放到通知之后 —— 弱网时它们可能要几十秒，不能把登出 UI 卡住。
    notifyListeners();
    try {
      await PushNotifications.setActive(account: account, enabled: false);
    } catch (_) {}
    // 这期间用户可能已经重新登录：旧清理流程不能再动新会话。
    if (epoch != _authEpoch) return;
    await Prefs.setString(PrefKeys.token, null);
    await Prefs.setString(PrefKeys.authUser, null);
    await Prefs.setString(PrefKeys.cardOwner, null);
    if (epoch != _authEpoch) return;
    await _clearLocalCardState();
  }

  Future<void> login(String account, String password) async {
    final j = await Api.login(account, password);
    Api.token = j['token']?.toString();
    user = User.fromJson(j['user']);
    _pushBindingBlocked = false;
    _authEpoch++;
    await _persistAuth();
    notifyListeners();
    unawaited(CheckinStore.instance.onAccountChanged(user?.name));
    _startNotifyPolling();
    unawaited(_loadCheckin());
    unawaited(syncCardsFromCloud());
    unawaited(MbtiStore.syncFromAccount(account: user?.name, force: true));
    unawaited(KeiStore.syncFromAccount(account: user?.name, force: true));
  }

  /// 扫码登录成功：桌面端轮询拿到 token 与用户信息后落到本地会话。
  Future<void> applyQrLogin(String token, Map<String, dynamic> userJson) async {
    Api.token = token;
    user = User.fromJson(userJson);
    _pushBindingBlocked = false;
    _authEpoch++;
    await _persistAuth();
    notifyListeners();
    unawaited(CheckinStore.instance.onAccountChanged(user?.name));
    _startNotifyPolling();
    unawaited(_loadCheckin());
    unawaited(syncCardsFromCloud());
    unawaited(MbtiStore.syncFromAccount(account: user?.name, force: true));
    unawaited(KeiStore.syncFromAccount(account: user?.name, force: true));
  }

  Future<void> register({
    String? phone,
    String? email,
    required String name,
    required String password,
  }) async {
    final j = await Api.register(
      phone: phone,
      email: email,
      name: name,
      password: password,
    );
    Api.token = j['token']?.toString();
    user = User.fromJson(j['user']);
    _pushBindingBlocked = false;
    _authEpoch++;
    await _persistAuth();
    notifyListeners();
    unawaited(CheckinStore.instance.onAccountChanged(user?.name));
    _startNotifyPolling();
    unawaited(_loadCheckin());
    unawaited(syncCardsFromCloud());
    unawaited(MbtiStore.syncFromAccount(account: user?.name, force: true));
    unawaited(KeiStore.syncFromAccount(account: user?.name, force: true));
  }

  Future<void> logout() async {
    _pushBindingBlocked = true;
    final account = user?.name;
    final authToken = Api.token;
    await MbtiStore.clearLocal();
    await KeiStore.clearLocal();
    // 服务端退登要清 Cookie / 推送绑定，但绝不能挡登录页：先把 token
    // 抓在手里，后台拿 Push token 再发请求；UI 走本地优先的 _clearAuth。
    final serverLogout = () async {
      String? pushToken;
      try {
        pushToken = (await PushNotifications.currentToken().timeout(
          const Duration(seconds: 2),
        ))?.token;
      } catch (_) {}
      try {
        await Api.logoutWithToken(authToken, pushToken);
      } catch (_) {}
    }();
    unawaited(
      PushNotifications.setActive(
        account: account,
        enabled: false,
      ).catchError((_) {}),
    );
    await _clearAuth();
    unawaited(serverLogout);
  }

  /// 注销账号：服务端删除账号与全部个人数据，本机同步清理登录态与账号缓存。
  Future<void> deleteAccount(String password) async {
    await Api.deleteAccount(password);
    await CheckinStore.instance.clearLocalForDeletedAccount();
    await MbtiStore.clearLocal();
    await KeiStore.clearLocal();
    await _clearAuth();
    try {
      await Prefs.clearAccountData();
    } catch (_) {}
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
    unawaited(_syncPushBinding());
    _refreshUnread();
    _postSeeded = false;
    _lastPostTs = null;
    unawaited(_seedCommunityPosts());
    _armNotifyTimer();
  }

  Future<void> _syncPushBinding() async {
    if (_pushBindingBlocked) return;
    try {
      await PushNotifications.setActive(
        account: user?.name,
        enabled: loggedIn && notificationsEnabled,
      );
    } catch (_) {}
  }

  /// 60 秒一次的前台轮询；退到后台时由 [setForeground] 取消，
  /// 避免整夜拿着定时器反复唤醒进程。
  void _armNotifyTimer() {
    _notifyTimer?.cancel();
    _notifyTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_foreground) return;
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
    if (!_foreground) return;
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
    if (!loggedIn || !_foreground) return;
    try {
      final j = await Api.notifications();
      final n = int.tryParse('${j['unread'] ?? 0}') ?? 0;
      if (n != unread) {
        final grew = n > unread && unread >= 0;
        unread = n;
        notifyListeners();
        if (grew && notificationsEnabled) {
          // 本地通知不要只说「你有 N 条新消息」：从同一份响应里取最新
          // 一条未读，带上类型、昵称和正文，锁屏上就能直接看懂发生了什么。
          final items =
              (j['notifications'] as List<dynamic>? ?? const <dynamic>[])
                  .whereType<Map>()
                  .map((e) => InboxItem.fromJson(Map<String, dynamic>.from(e)))
                  .toList();
          InboxItem? latest;
          for (final item in items) {
            if (item.unread) {
              latest = item;
              break;
            }
          }
          if (latest == null) {
            unawaited(Notifications.show('Citro 社区', '你有 $n 条新消息'));
          } else {
            unawaited(
              Notifications.show(_inboxTitle(latest), _inboxBody(latest, n)),
            );
          }
        }
      }
    } catch (_) {}
  }

  /// 消息通知标题：谁做了什么。
  static String _inboxTitle(InboxItem item) {
    switch (item.type) {
      case 'reply':
        return '${item.nick} 回复了你';
      case 'comment':
        return '${item.nick} 评论了你的动态';
      case 'like':
        return '${item.nick} 赞了你的动态';
      default:
        return 'Citro 社区';
    }
  }

  /// 消息通知正文：优先评论/回复内容，其次原动态摘要。
  static String _inboxBody(InboxItem item, int total) {
    String clip(String value, int max) {
      final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      return text.length > max ? '${text.substring(0, max)}…' : text;
    }

    final text = clip(item.text, 80);
    final post = clip(item.postText, 60);
    if (item.type == 'like') {
      return post.isNotEmpty ? '动态：$post' : '送了你一个赞';
    }
    if (text.isNotEmpty) return text;
    if (post.isNotEmpty) return '动态：$post';
    return '你有 $total 条新消息';
  }

  /// App 前后台切换：后台暂停轮询，回前台立即补一次未读与动态。
  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) {
      _notifyTimer?.cancel();
      return;
    }
    if (loggedIn) {
      unawaited(_refreshUnread());
      unawaited(_refreshCommunityPosts());
      _armNotifyTimer();
    }
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
    unawaited(_syncPushBinding());
    notifyListeners();
  }

  Future<void> setReduceMotion(bool value) async {
    if (reduceMotion == value) return;
    reduceMotion = value;
    await Prefs.setBool(PrefKeys.reduceMotion, value);
    notifyListeners();
  }

  /// 保存 CiCi 的自定义性格，空字符串即恢复默认。
  Future<void> setCiciPersona(String value) async {
    final next = value.trim();
    if (ciciPersona == next) return;
    ciciPersona = next;
    await Prefs.setString(PrefKeys.ciciPersona, next);
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

  /// 定位并刷新天气。
  ///
  /// [fromUser] 区分两种触发：用户点「定位并刷新」传 true，启动时的自动定位不传。
  /// 只有自动定位才会被「已经问过定位」「用户手动选过城市」拦住；用户主动点时
  /// 必须真的去定位，否则那次点击永远只会弹「定位失败」。
  Future<bool> refreshWeatherWithLocation({
    bool force = false,
    bool fromUser = false,
  }) async {
    if (!fromUser && (_weatherCityManual || _locationAsked)) return false;
    _locationAsked = true;
    final loc = await LocationService.current();
    if (loc == null) return false;
    // 定位期间用户手动选了城市：以用户的选择为准，别让自动定位把它盖掉。
    if (!fromUser && _weatherCityManual) return false;
    _weatherLat = loc.latitude;
    _weatherLon = loc.longitude;
    _weatherCity = loc.city.isNotEmpty ? loc.city : '当前位置';
    _weatherCityManual = false;
    // 先让界面换上新的城市名，再去拉天气：数据源慢的时候也不会看起来「没反应」。
    weather = weather.copyWith(city: _weatherCity);
    notifyListeners();
    await Prefs.setString(PrefKeys.weatherLat, '$_weatherLat');
    await Prefs.setString(PrefKeys.weatherLon, '$_weatherLon');
    await Prefs.setString(PrefKeys.weatherCity, _weatherCity);
    await Prefs.setBool(PrefKeys.weatherCityManual, false);
    unawaited(refreshWeather());
    return true;
  }

  /// 手动选择城市：写经纬度与城市名并立即刷新。
  ///
  /// 选过一次之后，启动时的自动定位会被 [_weatherCityManual] 拦住，
  /// 除非用户再点「定位并刷新」重新授权。城市名立刻生效，不再等网络。
  Future<void> setWeatherCity({
    required String city,
    required double lat,
    required double lon,
  }) async {
    _weatherLat = lat;
    _weatherLon = lon;
    _weatherCity = city;
    _weatherCityManual = true;
    _locationAsked = true;
    weather = weather.copyWith(city: city);
    notifyListeners();
    await Prefs.setString(PrefKeys.weatherLat, '$lat');
    await Prefs.setString(PrefKeys.weatherLon, '$lon');
    await Prefs.setString(PrefKeys.weatherCity, city);
    await Prefs.setBool(PrefKeys.weatherCityManual, true);
    unawaited(refreshWeather());
  }

  /// 当前天气对应的城市名（定位 / 选城市后立即更新）。
  String get weatherCity => _weatherCity;

  String get _weatherKey =>
      '${_weatherLat.toStringAsFixed(3)},${_weatherLon.toStringAsFixed(3)}';

  Future<void> refreshWeather() {
    final key = _weatherKey;
    final ongoing = _weatherRequest;
    // 同坐标的在途请求直接复用；坐标变了（切城市 / 重新定位）必须重新发，
    // 否则切完城市拿回来的还是旧城市的天气。
    if (ongoing != null && _weatherInFlightKey == key) return ongoing;
    final epoch = ++_weatherEpoch;
    // 放到下一轮微任务再改状态：调用方有可能在 build 期间触发（例如打开天气
    // 弹窗时发现还没数据，顺手补一次），同步 notifyListeners 会撞上 build。
    final future = Future.microtask(() => _doRefreshWeather(epoch));
    _weatherRequest = future;
    _weatherInFlightKey = key;
    future.whenComplete(() {
      if (identical(_weatherRequest, future)) {
        _weatherRequest = null;
        _weatherInFlightKey = '';
      }
    });
    return future;
  }

  Future<void> _doRefreshWeather(int epoch) async {
    weatherLoading = true;
    weatherError = null;
    notifyListeners();
    try {
      final result = await WeatherApi.fetch(
        lat: _weatherLat,
        lon: _weatherLon,
        city: _weatherCity,
      );
      // 期间用户又换了城市：这次结果已经过期，丢弃。
      if (epoch != _weatherEpoch) return;
      weather = result.copyWith(city: _weatherCity);
      weatherError = null;
      online = true;
    } catch (e) {
      if (epoch != _weatherEpoch) return;
      weatherError = '天气加载失败';
    } finally {
      if (epoch == _weatherEpoch) {
        weatherLoading = false;
        notifyListeners();
      }
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

  /// 本地最佳用时（秒）；0 表示没有记录。分数不是线性可逆的，
  /// 所以最佳用时单独存一份，不再从最佳分反推。
  int localBestTime(String game) {
    final raw = Prefs.getString(PrefKeys.gameBestTime);
    if (raw == null) return 0;
    try {
      final m = jsonDecode(raw) as Map;
      return _i(m[game]);
    } catch (_) {
      return 0;
    }
  }

  Future<void> saveLocalBestTime(String game, int seconds) async {
    if (seconds <= 0) return;
    final best = localBestTime(game);
    if (best > 0 && seconds >= best) return;
    Map<String, dynamic> m = {};
    try {
      m = jsonDecode(
        Prefs.getString(PrefKeys.gameBestTime) ?? '{}',
      ) as Map<String, dynamic>;
    } catch (_) {}
    m[game] = seconds;
    await Prefs.setString(PrefKeys.gameBestTime, jsonEncode(m));
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

  List<String> _cardCandidates() => [
    for (final card in CardCatalog.all) card.id,
  ];

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

  /// 今天的签存在本机，但必须按账号区分：同一台设备换账号时，
  /// 不能把上一个账号抽到的签（常常就是那支「上上签」）接着发给下一个人。
  /// 游客记 guest，登录用户记昵称。
  String get _fortuneOwner => user?.name ?? 'guest';

  String get _todayKey => _dayKey(DateTime.now());

  /// 缓存格式 `日期:档位:账号`（旧）或 `日期:档位:位置:账号`（新）。
  /// 旧的两段格式没有账号标记，一律当作过期——当天重新向服务端取一次，
  /// 各端也就对齐了。
  List<String>? get _fortuneCacheParts {
    final raw = Prefs.getString(PrefKeys.checkinFortune);
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length == 4 && parts[3] == _fortuneOwner) return parts;
    if (parts.length == 3 && parts[2] == _fortuneOwner) return parts;
    return null;
  }

  int? get todayFortuneIdx {
    final parts = _fortuneCacheParts;
    if (parts == null || parts[0] != _todayKey) return null;
    return int.tryParse(parts[1]);
  }

  /// 当天服务端随机抽好的同等级内位置；旧缓存没有这一项时返回 null，
  /// 由 `fortuneForDay` 用日期散列兜底。
  int? get todayFortuneSlot {
    final parts = _fortuneCacheParts;
    if (parts == null || parts.length != 4 || parts[0] != _todayKey) {
      return null;
    }
    return _fortuneSlotValue(parts[2]);
  }

  Future<void> _saveTodayFortune(int idx, int slot) => Prefs.setString(
    PrefKeys.checkinFortune,
    '$_todayKey:$idx:$slot:$_fortuneOwner',
  );

  /// 抽签身份：服务端按 deviceId + 日期 记一次，同一台设备换个人登录时
  /// 会直接拿回上一个账号的签。所以抽签类请求按账号派生一个 id，
  /// 云端打卡统计仍用 gid，不受影响。
  String get _drawId {
    final owner = _fortuneOwner;
    if (owner.isEmpty || owner == 'guest') return gid;
    var h = 0x811c9dc5;
    for (final u in owner.codeUnits) {
      h ^= u;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return '$gid-${h.toRadixString(36)}';
  }

  Future<int> drawFortuneIdx() async {
    final cached = todayFortuneIdx;
    if (cached != null) {
      // 登录状态下即使本地有缓存，也向服务端确认/补一次打卡，保证跨端天数一致。
      await _syncCloudCheckin(migrate: true);
      // 另一台设备做过「转运」时，把服务端结果同步回来。
      try {
        final j = await Api.draw(deviceId: _drawId);
        final remoteIdx = int.tryParse('${j['idx']}');
        final remoteSlot = _fortuneSlotValue(j['slot']);
        final slotChanged =
            remoteSlot != null && remoteSlot != todayFortuneSlot;
        if (remoteIdx != null && (remoteIdx != cached || slotChanged)) {
          await _saveTodayFortune(
            remoteIdx,
            remoteSlot ?? todayFortuneSlot ?? Random().nextInt(6),
          );
          if (j['transfer'] == true) {
            await Prefs.setString(PrefKeys.checkinTransferUsed, _transferStamp);
          }
          notifyListeners();
          return remoteIdx;
        }
      } catch (_) {}
      if (todayFortuneSlot == null) {
        // 旧三段缓存没有具体签位置：补随机一次并升级成四段，避免继续用
        // 日期轮换的旧规则。
        await _saveTodayFortune(cached, Random().nextInt(6));
      }
      return cached;
    }
    int? idx;
    int? slot;
    try {
      final j = await Api.drawTake(deviceId: _drawId);
      idx = int.tryParse('${j['idx']}');
      slot = _fortuneSlotValue(j['slot']);
    } catch (_) {}
    idx ??= Random().nextInt(8);
    slot ??= Random().nextInt(6);
    await _saveTodayFortune(idx, slot);
    final last = Prefs.getString(PrefKeys.checkinLast) ?? '';
    if (last != _todayKey) {
      final streak = Prefs.getInt(PrefKeys.checkinStreak, 0);
      final yesterday = _dayKey(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      final newStreak = last == yesterday ? streak + 1 : 1;
      await Prefs.setString(PrefKeys.checkinLast, _todayKey);
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

  /// 转运机会同样按账号记，否则换个人登录会白拿上一个账号的机会。
  String get _transferStamp => '$_todayKey:$_fortuneOwner';

  bool get fortuneTransferUsed =>
      Prefs.getString(PrefKeys.checkinTransferUsed) == _transferStamp;

  /// 跟 CiCi 分享好事后到账的转运机会（当天有效，用一次）。
  bool get fortuneTransferReady {
    if (fortuneTransferUsed || !fortuneIsBad) return false;
    return Prefs.getString(PrefKeys.checkinTransfer) == _transferStamp;
  }

  Future<void> grantFortuneTransfer() async {
    if (!fortuneIsBad || fortuneTransferUsed) return;
    await Prefs.setString(PrefKeys.checkinTransfer, _transferStamp);
    notifyListeners();
  }

  /// 消耗转运机会重抽一签：服务端只允许下签重抽一次，且只给 0..5 的签。
  Future<int?> useFortuneTransfer() async {
    if (!fortuneTransferReady) return null;
    int? idx;
    int? slot;
    var offline = false;
    var rejected = false;
    try {
      final j = await Api.drawReroll(deviceId: _drawId);
      idx = int.tryParse('${j['idx']}');
      slot = _fortuneSlotValue(j['slot']);
    } on ApiException catch (e) {
      if (e.code == 409) {
        // 服务端已经转运过（比如另一台设备）：取回当前结果，不再本地重抽。
        try {
          final j = await Api.draw(deviceId: _drawId);
          idx = int.tryParse('${j['idx']}');
          slot = _fortuneSlotValue(j['slot']);
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
    slot ??= Random().nextInt(6);
    await _saveTodayFortune(idx, slot);
    await Prefs.setString(PrefKeys.checkinTransferUsed, _transferStamp);
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
