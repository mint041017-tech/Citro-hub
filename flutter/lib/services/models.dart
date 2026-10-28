class User {
  final String name;
  final String? av;
  final int? bdayMonth;
  final int? bdayDay;
  final bool profileDone;
  final bool guest;

  const User({
    required this.name,
    this.av,
    this.bdayMonth,
    this.bdayDay,
    this.profileDone = true,
    this.guest = false,
  });

  User copyWith({
    String? name,
    String? av,
    int? bdayMonth,
    int? bdayDay,
    bool? profileDone,
  }) => User(
    name: name ?? this.name,
    av: av ?? this.av,
    bdayMonth: bdayMonth ?? this.bdayMonth,
    bdayDay: bdayDay ?? this.bdayDay,
    profileDone: profileDone ?? this.profileDone,
  );

  static User? fromJson(dynamic j) {
    if (j == null) return null;
    final b = j['bday'];
    return User(
      name: (j['name'] ?? '').toString(),
      av: j['av']?.toString(),
      bdayMonth: b is Map ? int.tryParse('${b['month']}') : null,
      bdayDay: b is Map ? int.tryParse('${b['day']}') : null,
      profileDone: j['profileDone'] != false,
    );
  }
}

class PostComment {
  final String id;
  final bool anon;
  final String nick;
  final String? av;
  final String text;
  final String? replyTo;
  final String? voice;
  final int voiceDur;
  final List<String> imgs;
  final bool mine;
  final int ts;

  const PostComment({
    required this.id,
    required this.anon,
    required this.nick,
    this.av,
    required this.text,
    this.replyTo,
    this.voice,
    this.voiceDur = 0,
    this.imgs = const [],
    this.mine = false,
    required this.ts,
  });

  factory PostComment.fromJson(Map<String, dynamic> j) => PostComment(
    id: '${j['id']}',
    anon: j['anon'] == true,
    nick: '${j['nick'] ?? ''}',
    av: j['av']?.toString(),
    text: '${j['text'] ?? ''}',
    replyTo: j['replyTo']?.toString(),
    voice: j['voice']?.toString(),
    voiceDur: _asInt(j['voiceDur']),
    imgs: _asStringList(j['imgs']),
    mine: j['mine'] == true,
    ts: _asInt(j['ts']),
  );
}

class Post {
  final String id;
  final bool anon;
  final String nick;
  final String? av;
  final bool mine;
  final String text;
  final int likes;
  final int hugs;
  final String? voice;
  final int voiceDur;
  final List<String> imgs;
  final bool liked;
  final bool hugged;
  final int nComments;
  final List<PostComment> comments;
  final int ts;

  const Post({
    required this.id,
    required this.anon,
    required this.nick,
    this.av,
    this.mine = false,
    required this.text,
    this.likes = 0,
    this.hugs = 0,
    this.voice,
    this.voiceDur = 0,
    this.imgs = const [],
    this.liked = false,
    this.hugged = false,
    this.nComments = 0,
    this.comments = const [],
    required this.ts,
  });

  Post copyWith({
    int? likes,
    int? hugs,
    bool? liked,
    bool? hugged,
    int? nComments,
    List<PostComment>? comments,
  }) => Post(
    id: id,
    anon: anon,
    nick: nick,
    av: av,
    mine: mine,
    text: text,
    likes: likes ?? this.likes,
    hugs: hugs ?? this.hugs,
    voice: voice,
    voiceDur: voiceDur,
    imgs: imgs,
    liked: liked ?? this.liked,
    hugged: hugged ?? this.hugged,
    nComments: nComments ?? this.nComments,
    comments: comments ?? this.comments,
    ts: ts,
  );

  factory Post.fromJson(Map<String, dynamic> j) => Post(
    id: '${j['id']}',
    anon: j['anon'] == true,
    nick: '${j['nick'] ?? ''}',
    av: j['av']?.toString(),
    mine: j['mine'] == true,
    text: '${j['text'] ?? ''}',
    likes: _asInt(j['likes']),
    hugs: _asInt(j['hugs']),
    voice: j['voice']?.toString(),
    voiceDur: _asInt(j['voiceDur']),
    imgs: _asStringList(j['imgs']),
    liked: j['liked'] == true,
    hugged: j['hugged'] == true,
    nComments: _asInt(j['nComments']),
    comments: (j['comments'] is List)
        ? (j['comments'] as List)
              .whereType<Map>()
              .map((e) => PostComment.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : const [],
    ts: _asInt(j['ts']),
  );
}

class InboxItem {
  final String id;
  final String postId;
  final String type; // reply | comment | like
  final String nick;
  final bool anon;
  final String text;
  final String postText;
  final int ts;
  final bool unread;

  const InboxItem({
    required this.id,
    required this.postId,
    required this.type,
    required this.nick,
    required this.anon,
    required this.text,
    required this.postText,
    required this.ts,
    required this.unread,
  });

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
    id: '${j['id']}',
    postId: '${j['postId']}',
    type: '${j['type']}',
    nick: '${j['nick'] ?? ''}',
    anon: j['anon'] == true,
    text: '${j['text'] ?? ''}',
    postText: '${j['postText'] ?? ''}',
    ts: _asInt(j['ts']),
    unread: j['unread'] == true,
  );

  InboxItem asRead() => InboxItem(
    id: id,
    postId: postId,
    type: type,
    nick: nick,
    anon: anon,
    text: text,
    postText: postText,
    ts: ts,
    unread: false,
  );
}

class Note {
  final String id;
  final String uid;
  final String title;
  final String content;
  final int ts;
  final int updated;

  const Note({
    required this.id,
    required this.uid,
    required this.title,
    required this.content,
    required this.ts,
    required this.updated,
  });

  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: '${j['id']}',
    uid: '${j['uid'] ?? ''}',
    title: '${j['title'] ?? ''}',
    content: '${j['content'] ?? ''}',
    ts: _asInt(j['ts']),
    updated: _asInt(j['updated']),
  );
}

class CookIngredient {
  String name;
  String amount;
  String group;
  CookIngredient({required this.name, this.amount = '', this.group = 'main'});

  factory CookIngredient.fromJson(Map<String, dynamic> j) => CookIngredient(
    name: '${j['name'] ?? ''}',
    amount: '${j['amount'] ?? ''}',
    group: '${j['group'] ?? 'main'}',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'group': group,
  };
}

class CookStep {
  String text;
  String img;
  int timer;
  CookStep({this.text = '', this.img = '', this.timer = 0});

  factory CookStep.fromJson(Map<String, dynamic> j) => CookStep(
    text: '${j['text'] ?? ''}',
    img: '${j['img'] ?? ''}',
    timer: _asInt(j['timer']),
  );

  Map<String, dynamic> toJson() => {'text': text, 'img': img, 'timer': timer};
}

class CookDiary {
  String id;
  String date;
  String tweaks;
  int rating;
  String result;
  int ts;
  CookDiary({
    this.id = '',
    this.date = '',
    this.tweaks = '',
    this.rating = 0,
    this.result = '',
    this.ts = 0,
  });

  factory CookDiary.fromJson(Map<String, dynamic> j) => CookDiary(
    id: '${j['id'] ?? ''}',
    date: '${j['date'] ?? ''}',
    tweaks: '${j['tweaks'] ?? ''}',
    rating: _asInt(j['rating']),
    result: '${j['result'] ?? ''}',
    ts: _asInt(j['ts']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'tweaks': tweaks,
    'rating': rating,
    'result': result,
    'ts': ts,
  };
}

class Recipe {
  String id;
  String name;
  String emoji;
  List<String> tags;
  String cuisine;
  String dishType;
  String cover;
  int prepMin;
  int cookMin;
  int calories;
  String source;
  int servings;
  List<CookIngredient> ingredients;
  List<CookStep> steps;
  String note;
  List<CookDiary> diary;
  String visibility;
  int createdAt;
  int updatedAt;
  String? owner;
  String? ownerAv;

  /// 从食谱广场收藏时的原作者；自己写的食谱为空
  String fromOwner;
  bool mine;
  int cookCount;

  Recipe({
    this.id = '',
    this.name = '',
    this.emoji = '🍳',
    this.tags = const [],
    this.cuisine = '',
    this.dishType = '',
    this.cover = '',
    this.prepMin = 0,
    this.cookMin = 0,
    this.calories = 0,
    this.source = '',
    this.servings = 0,
    this.ingredients = const [],
    this.steps = const [],
    this.note = '',
    this.diary = const [],
    this.visibility = 'private',
    this.createdAt = 0,
    this.updatedAt = 0,
    this.owner,
    this.ownerAv,
    this.fromOwner = '',
    this.mine = false,
    this.cookCount = 0,
  });

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    emoji: '${j['emoji'] ?? '🍳'}',
    tags: _asStringList(j['tags']),
    cuisine: '${j['cuisine'] ?? ''}',
    dishType: '${j['dishType'] ?? ''}',
    cover: '${j['cover'] ?? ''}',
    prepMin: _asInt(j['prepMin']),
    cookMin: _asInt(j['cookMin']),
    calories: _asInt(j['calories']),
    source: '${j['source'] ?? ''}',
    servings: _asInt(j['servings']),
    ingredients: (j['ingredients'] is List)
        ? (j['ingredients'] as List)
              .whereType<Map>()
              .map((e) => CookIngredient.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : [],
    steps: (j['steps'] is List)
        ? (j['steps'] as List)
              .whereType<Map>()
              .map((e) => CookStep.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : [],
    note: '${j['note'] ?? ''}',
    diary: (j['diary'] is List)
        ? (j['diary'] as List)
              .whereType<Map>()
              .map((e) => CookDiary.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : [],
    visibility: '${j['visibility'] ?? 'private'}',
    createdAt: _asInt(j['createdAt']),
    updatedAt: _asInt(j['updatedAt']),
    owner: j['owner']?.toString(),
    ownerAv: j['ownerAv']?.toString(),
    fromOwner: '${j['fromOwner'] ?? ''}',
    mine: j['mine'] == true,
    cookCount: _asInt(j['cookCount']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'tags': tags,
    'cuisine': cuisine,
    'dishType': dishType,
    'cover': cover,
    'prepMin': prepMin,
    'cookMin': cookMin,
    'calories': calories,
    'source': source,
    'servings': servings,
    'ingredients': ingredients.map((e) => e.toJson()).toList(),
    'steps': steps.map((e) => e.toJson()).toList(),
    'note': note,
    'diary': diary.map((e) => e.toJson()).toList(),
    'fromOwner': fromOwner,
    'visibility': visibility,
    'createdAt': createdAt,
  };
}

class ShoppingItem {
  String id;
  String text;
  bool done;
  ShoppingItem({this.id = '', required this.text, this.done = false});

  factory ShoppingItem.fromJson(Map<String, dynamic> j) => ShoppingItem(
    id: '${j['id'] ?? ''}',
    text: '${j['text'] ?? ''}',
    done: j['done'] == true,
  );

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};
}

class FridgeItem {
  String id;
  String name;
  String qty;
  String unit;
  String buyDate;
  String expDate;
  FridgeItem({
    this.id = '',
    required this.name,
    this.qty = '1',
    this.unit = '个',
    this.buyDate = '',
    this.expDate = '',
  });

  factory FridgeItem.fromJson(Map<String, dynamic> j) => FridgeItem(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    qty: '${j['qty'] ?? '1'}',
    unit: '${j['unit'] ?? '个'}',
    buyDate: '${j['buyDate'] ?? ''}',
    expDate: '${j['expDate'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'qty': qty,
    'unit': unit,
    'buyDate': buyDate,
    'expDate': expDate,
  };
}

class BoardEntry {
  final int rank;
  final String name;
  final String? av;
  final int score;
  final int ts;
  final bool you;
  const BoardEntry({
    required this.rank,
    required this.name,
    this.av,
    required this.score,
    required this.ts,
    required this.you,
  });

  factory BoardEntry.fromJson(Map<String, dynamic> j) => BoardEntry(
    rank: _asInt(j['rank']),
    name: '${j['name'] ?? ''}',
    av: j['av']?.toString(),
    score: _asInt(j['score']),
    ts: _asInt(j['ts']),
    you: j['you'] == true,
  );
}

class WeatherNow {
  final double temp;
  final double feels;
  final int humidity;
  final double wind;
  final double windDir;
  final int code;
  final String city;
  final String updated;
  final List<DailyWeather> daily;
  final List<HourlyWeather> hourly;

  const WeatherNow({
    required this.temp,
    required this.feels,
    required this.humidity,
    required this.wind,
    required this.code,
    required this.city,
    required this.updated,
    required this.daily,
    this.windDir = 0,
    this.hourly = const [],
  });

  String get windDirection => weatherWindDirection(windDir);

  static const fallback = WeatherNow(
    temp: 26,
    feels: 28,
    humidity: 65,
    wind: 8,
    code: 0,
    city: '北海',
    updated: '刚刚',
    daily: [],
  );

  String get desc => weatherText(code);
  String get emoji => weatherEmoji(code);
}

class HourlyWeather {
  final DateTime time;
  final int code;
  final double temp;
  final int rain;

  const HourlyWeather({
    required this.time,
    required this.code,
    required this.temp,
    this.rain = 0,
  });
}

class DailyWeather {
  final DateTime date;
  final int code;
  final double max;
  final double min;
  final int rain;
  final DateTime? sunrise;
  final DateTime? sunset;
  const DailyWeather({
    required this.date,
    required this.code,
    required this.max,
    required this.min,
    this.rain = 0,
    this.sunrise,
    this.sunset,
  });
}

String weatherWindDirection(double degrees) {
  const labels = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
  final index = ((degrees % 360) / 45).round() % labels.length;
  return '${labels[index]}风';
}

String weatherText(int code) {
  if (code == 0) return '晴';
  if (code == 1) return '大致晴朗';
  if (code == 2) return '多云';
  if (code == 3) return '阴';
  if (code == 45 || code == 48) return '雾';
  if (code >= 51 && code <= 57) return '毛毛雨';
  if (code >= 61 && code <= 67) return '雨';
  if (code >= 71 && code <= 77) return '雪';
  if (code >= 80 && code <= 82) return '阵雨';
  if (code >= 85 && code <= 86) return '阵雪';
  if (code >= 95) return '雷雨';
  return '多云';
}

String weatherEmoji(int code) {
  if (code == 0) return '☀️';
  if (code == 1) return '🌤️';
  if (code == 2) return '⛅';
  if (code == 3) return '☁️';
  if (code == 45 || code == 48) return '🌫️';
  if (code >= 51 && code <= 67) return '🌧️';
  if (code >= 71 && code <= 77) return '❄️';
  if (code >= 80 && code <= 82) return '🌦️';
  if (code >= 85 && code <= 86) return '🌨️';
  if (code >= 95) return '⛈️';
  return '⛅';
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

List<String> _asStringList(dynamic v) {
  if (v is! List) return const [];
  return v.map((e) => '$e').toList();
}

class ZodiacSign {
  final String id;
  final String name;
  final String symbol;
  final String range;
  final String element;
  const ZodiacSign(this.id, this.name, this.symbol, this.range, this.element);
}

const List<ZodiacSign> kZodiacSigns = [
  ZodiacSign('aries', '白羊座', '♈', '3.21 - 4.19', '火'),
  ZodiacSign('taurus', '金牛座', '♉', '4.20 - 5.20', '土'),
  ZodiacSign('gemini', '双子座', '♊', '5.21 - 6.21', '风'),
  ZodiacSign('cancer', '巨蟹座', '♋', '6.22 - 7.22', '水'),
  ZodiacSign('leo', '狮子座', '♌', '7.23 - 8.22', '火'),
  ZodiacSign('virgo', '处女座', '♍', '8.23 - 9.22', '土'),
  ZodiacSign('libra', '天秤座', '♎', '9.23 - 10.23', '风'),
  ZodiacSign('scorpio', '天蝎座', '♏', '10.24 - 11.22', '水'),
  ZodiacSign('sagittarius', '射手座', '♐', '11.23 - 12.21', '火'),
  ZodiacSign('capricorn', '摩羯座', '♑', '12.22 - 1.19', '土'),
  ZodiacSign('aquarius', '水瓶座', '♒', '1.20 - 2.18', '风'),
  ZodiacSign('pisces', '双鱼座', '♓', '2.19 - 3.20', '水'),
];

ZodiacSign? zodiacById(String? id) {
  if (id == null) return null;
  for (final z in kZodiacSigns) {
    if (z.id == id) return z;
  }
  return null;
}

class ZodiacFortune {
  final int score;
  final String tag;
  final String text;
  final int love;
  final int work;
  final int wealth;
  final int health;
  final String color;
  final String number;
  final String item;
  final String date;
  const ZodiacFortune({
    required this.score,
    required this.tag,
    required this.text,
    required this.love,
    required this.work,
    required this.wealth,
    required this.health,
    required this.color,
    required this.number,
    required this.item,
    required this.date,
  });

  factory ZodiacFortune.fromJson(Map<String, dynamic> j) => ZodiacFortune(
    score: _asInt(j['score']),
    tag: '${j['tag'] ?? ''}',
    text: '${j['text'] ?? ''}',
    love: _asInt(j['love']),
    work: _asInt(j['work']),
    wealth: _asInt(j['wealth']),
    health: _asInt(j['health']),
    color: '${j['color'] ?? ''}',
    number: '${j['number'] ?? ''}',
    item: '${j['item'] ?? ''}',
    date: '${j['date'] ?? ''}',
  );

  bool get isComplete =>
      tag.isNotEmpty &&
      text.isNotEmpty &&
      color.isNotEmpty &&
      number.isNotEmpty &&
      item.isNotEmpty;

  static ZodiacFortune? fromAiJson(Map<String, dynamic> j) {
    final tag = _aiText(j['tag'], maxRunes: 10);
    final text = _aiText(j['text'], maxRunes: 160);
    final color = _aiText(j['color'], maxRunes: 6);
    final number = _aiText(j['number'], maxRunes: 4);
    final item = _aiText(j['item'], maxRunes: 8);
    if (tag.isEmpty ||
        text.isEmpty ||
        color.isEmpty ||
        number.isEmpty ||
        item.isEmpty ||
        j['love'] == null ||
        j['work'] == null ||
        j['wealth'] == null ||
        j['health'] == null) {
      return null;
    }
    int scoreOf(String key) => _asInt(j[key]).clamp(0, 100).toInt();
    final love = scoreOf('love');
    final work = scoreOf('work');
    final wealth = scoreOf('wealth');
    final health = scoreOf('health');
    final score = j['score'] == null
        ? ((love + work + wealth + health) / 4).round()
        : scoreOf('score');
    return ZodiacFortune(
      score: score,
      tag: tag,
      text: text,
      love: love,
      work: work,
      wealth: wealth,
      health: health,
      color: color,
      number: number,
      item: item,
      date: '',
    );
  }

  static String _aiText(dynamic value, {required int maxRunes}) {
    var s = (value ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');
    final runes = s.runes.toList();
    if (runes.length > maxRunes) {
      s = String.fromCharCodes(runes.take(maxRunes));
    }
    return s;
  }

  Map<String, dynamic> toJson() => {
    'score': score,
    'tag': tag,
    'text': text,
    'love': love,
    'work': work,
    'wealth': wealth,
    'health': health,
    'color': color,
    'number': number,
    'item': item,
    'date': date,
  };
}
