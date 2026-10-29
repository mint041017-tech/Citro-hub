import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  static late SharedPreferences _sp;

  static Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
  }

  static String? getString(String key) => _sp.getString(key);
  static Future<void> setString(String key, String? value) async {
    if (value == null) {
      await _sp.remove(key);
    } else {
      await _sp.setString(key, value);
    }
  }

  static int getInt(String key, [int fallback = 0]) =>
      _sp.getInt(key) ?? fallback;
  static Future<void> setInt(String key, int value) => _sp.setInt(key, value);
  static bool getBool(String key, [bool fallback = false]) =>
      _sp.getBool(key) ?? fallback;
  static Future<void> setBool(String key, bool value) =>
      _sp.setBool(key, value);
  static List<String> getStringList(String key) =>
      _sp.getStringList(key) ?? <String>[];
  static Future<void> setStringList(String key, List<String> value) =>
      _sp.setStringList(key, value);

  /// 注销账号时清理本机上的账号相关数据；主题、通知、天气城市等设备偏好保留。
  static Future<void> clearAccountData() async {
    const keys = <String>[
      PrefKeys.token,
      PrefKeys.authUser,
      PrefKeys.zodiacSign,
      PrefKeys.checkinLast,
      PrefKeys.checkinStreak,
      PrefKeys.checkinFortune,
      PrefKeys.checkinTransfer,
      PrefKeys.checkinTransferUsed,
      PrefKeys.gameBest,
      PrefKeys.playRecords,
      PrefKeys.playCooldown,
      PrefKeys.fishConfig,
      PrefKeys.cardsOwned,
      PrefKeys.cardsToday,
      PrefKeys.cardCredits,
      PrefKeys.cardGameRounds,
      PrefKeys.cardGameDraws,
      PrefKeys.cardPostDay,
      PrefKeys.cardRecipeDay,
      PrefKeys.cardChatDay,
    ];
    for (final key in keys) {
      await _sp.remove(key);
    }
    for (final key in _sp.getKeys().toList()) {
      if (key.startsWith('citro_zodiac_ai_')) await _sp.remove(key);
    }
  }

  static const duration = Duration(milliseconds: 220);
}

class PrefKeys {
  static const theme = 'cm-theme-mode';
  static const token = 'chimu_auth_token';
  static const authUser = 'chimu_auth_user';
  static const gid = 'citro_gid';
  static const guestName = 'citro_guest_name';
  static const playRecords = 'citro_play_records';
  static const playCooldown = 'citro_play_cooldown';
  static const fishConfig = 'citro_fish_config';
  static const zodiacSign = 'citro_zodiac_sign';
  static const checkinLast = 'citro_checkin_last';
  static const checkinStreak = 'citro_checkin_streak';
  static const checkinFortune = 'citro_checkin_fortune';
  static const checkinTransfer = 'citro_checkin_transfer';
  static const checkinTransferUsed = 'citro_checkin_transfer_used';
  static const gameBest = 'citro_game_best';
  static const gameMuted = 'citro_game_mute';
  static const cardsOwned = 'citro_cards_owned';
  static const cardsToday = 'citro_cards_today';
  static const cardCredits = 'citro_card_credits';
  static const cardGameRounds = 'citro_card_game_rounds';
  static const cardGameDraws = 'citro_card_game_draws';
  static const cardPostDay = 'citro_card_post_day';
  static const cardRecipeDay = 'citro_card_recipe_day';
  static const cardChatDay = 'citro_card_chat_day';
  static const cardsIndexCache = 'citro_cards_index';
  static const weatherLat = 'citro_weather_lat';
  static const weatherLon = 'citro_weather_lon';
  static const weatherCity = 'citro_weather_city';
  static const notificationsEnabled = 'citro_notifications_enabled';
  static const blockedUsers = 'citro_blocked_users';
  static const updateLastCheck = 'citro_update_last_check';
  static const updateSkippedVersion = 'citro_update_skipped_version';
}
