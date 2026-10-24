// 农历 / 节气 / 节日：与站点 index.html 的查表实现完全一致（2025-2040）。
const List<String> kTermNames = [
  "小寒",
  "大寒",
  "立春",
  "雨水",
  "惊蛰",
  "春分",
  "清明",
  "谷雨",
  "立夏",
  "小满",
  "芒种",
  "夏至",
  "小暑",
  "大暑",
  "立秋",
  "处暑",
  "白露",
  "秋分",
  "寒露",
  "霜降",
  "立冬",
  "小雪",
  "大雪",
  "冬至",
];

const Map<int, String> kTermDays = {
  2025: '010501200203021803050320040404200505052106050621070707220807082309070923100810231107112212071221',
  2026: '010501200204021803050320040504200505052106050621070707230807082309070923100810231107112212071222',
  2027: '010501200204021903060321040504200506052106060621070707230808082309080923100810231107112212071222',
  2028: '010601200204021903050320040404190505052006050621070607220807082209070922100810231107112212061221',
  2029: '010501200203021803050320040404200505052106050621070707220807082309070923100810231107112212071221',
  2030: '010501200204021803050320040504200505052106050621070707230807082309070923100810231107112212071222',
  2031: '010501200204021903060321040504200506052106060621070707230808082309080923100810231107112212071222',
  2032: '010601200204021903050320040404190505052006050621070607220807082209070922100810231107112212061221',
  2033: '010501200203021803050320040404200505052106050621070707220807082309070923100810231107112212071221',
  2034: '010501200204021803050320040504200505052106050621070707230807082309070923100810231107112212071222',
  2035: '010501200204021903060321040504200505052106060621070707230807082309080923100810231107112212071222',
  2036: '010601200204021903050320040404190505052006050621070607220807082209070922100810231107112212061221',
  2037: '010501200203021803050320040404200505052106050621070707220807082309070923100810231107112212071221',
  2038: '010501200204021803050320040504200505052106050621070707230807082309070923100810231107112212071222',
  2039: '010501200204021903060321040504200505052106060621070707230807082309080923100810231107112212071222',
  2040: '010601200204021903050320040404190505052006050621070607220807082209070922100810231107112212061221',
};

const String kLunarMonths =
    "20241231,20250129,20250228,20250329,20250428,20250527,20250625,20250725,20250823,20250922,20251021,20251120,20251220,20260119,20260217,20260319,20260417,20260517,20260615,20260714,20260813,20260911,20261010,20261109,20261209,20270108,20270206,20270308,20270407,20270506,20270605,20270704,20270802,20270901,20270930,20271029,20271128,20271228,20280126,20280225,20280326,20280425,20280524,20280623,20280722,20280820,20280919,20281018,20281116,20281216,20290115,20290213,20290315,20290414,20290513,20290612,20290711,20290810,20290908,20291008,20291106,20291205,20300104,20300203,20300304,20300403,20300502,20300601,20300701,20300730,20300829,20300927,20301027,20301125,20301225,20310123,20310221,20310323,20310422,20310521,20310620,20310719,20310818,20310917,20311016,20311115,20311214,20320113,20320211,20320312,20320410,20320509,20320608,20320707,20320806,20320905,20321004,20321103,20321203,20330101,20330131,20330301,20330331,20330429,20330528,20330627,20330726,20330825,20330923,20331023,20331122,20331222,20340120,20340219,20340320,20340419,20340518,20340616,20340716,20340814,20340913,20341012,20341111,20341211,20350109,20350208,20350310,20350408,20350508,20350606,20350705,20350804,20350902,20351001,20351031,20351130,20351229,20360128,20360227,20360328,20360426,20360526,20360624,20360723,20360822,20360920,20361019,20361118,20361217,20370116,20370215,20370317,20370416,20370515,20370614,20370713,20370811,20370910,20371009,20371107,20371207,20380105,20380204,20380306,20380405,20380504,20380603,20380702,20380801,20380830,20380929,20381028,20381126,20381226,20390124,20390223,20390325,20390423,20390523,20390622,20390721,20390820,20390918,20391018,20391116,20391216,20400114,20400212,20400313,20400411,20400511,20400610,20400709,20400808,20400906,20401006,20401105,20401204,20410103,20410201";
const String kLunarNames =
    "C1234566789ABC123456789ABC123456789ABC1234556789ABC123456789ABC123456789ABC1233456789ABC123456789ABC123456789ABbC123456789ABC123456789ABC1234566789ABC123456789ABC123456789ABC1234556789ABC123456789ABC1";
const String kLunarLeap =
    "00000001000000000000000000000000000000000001000000000000000000000000000000000010000000000000000000000000000000010000000000000000000000000000000100000000000000000000000000000000000100000000000000000000";
const List<String> kLunarMonthNames = [
  "正月",
  "二月",
  "三月",
  "四月",
  "五月",
  "六月",
  "七月",
  "八月",
  "九月",
  "十月",
  "冬月",
  "腊月",
];
const List<String> kLunarDayNames = [
  "初一",
  "初二",
  "初三",
  "初四",
  "初五",
  "初六",
  "初七",
  "初八",
  "初九",
  "初十",
  "十一",
  "十二",
  "十三",
  "十四",
  "十五",
  "十六",
  "十七",
  "十八",
  "十九",
  "二十",
  "廿一",
  "廿二",
  "廿三",
  "廿四",
  "廿五",
  "廿六",
  "廿七",
  "廿八",
  "廿九",
  "三十",
];
const Map<String, String> kFestivals = {
  '2025-01-29': 'chunjie',
  '2025-02-12': 'yuanxiao',
  '2025-03-01': 'longtaitou',
  '2025-04-04': 'qingming',
  '2025-05-31': 'duanwu',
  '2025-08-29': 'qixi',
  '2025-09-06': 'zhongyuan',
  '2025-10-06': 'zhongqiu',
  '2025-10-29': 'chongyang',
  '2026-01-26': 'laba',
  '2026-02-10': 'xiaonian',
  '2026-02-16': 'chuxi',
  '2026-02-17': 'chunjie',
  '2026-03-03': 'yuanxiao',
  '2026-03-20': 'longtaitou',
  '2026-04-05': 'qingming',
  '2026-06-19': 'duanwu',
  '2026-08-19': 'qixi',
  '2026-08-27': 'zhongyuan',
  '2026-09-25': 'zhongqiu',
  '2026-10-18': 'chongyang',
  '2027-01-15': 'laba',
  '2027-01-30': 'xiaonian',
  '2027-02-05': 'chuxi',
  '2027-02-06': 'chunjie',
  '2027-02-20': 'yuanxiao',
  '2027-03-09': 'longtaitou',
  '2027-04-05': 'qingming',
  '2027-06-09': 'duanwu',
  '2027-08-08': 'qixi',
  '2027-08-16': 'zhongyuan',
  '2027-09-15': 'zhongqiu',
  '2027-10-08': 'chongyang',
  '2028-01-04': 'laba',
  '2028-01-19': 'xiaonian',
  '2028-01-25': 'chuxi',
  '2028-01-26': 'chunjie',
  '2028-02-09': 'yuanxiao',
  '2028-02-26': 'longtaitou',
  '2028-04-04': 'qingming',
  '2028-05-28': 'duanwu',
  '2028-08-26': 'qixi',
  '2028-09-03': 'zhongyuan',
  '2028-10-03': 'zhongqiu',
  '2028-10-26': 'chongyang',
  '2029-01-22': 'laba',
  '2029-02-06': 'xiaonian',
  '2029-02-12': 'chuxi',
  '2029-02-13': 'chunjie',
  '2029-02-27': 'yuanxiao',
  '2029-03-16': 'longtaitou',
  '2029-04-04': 'qingming',
  '2029-06-16': 'duanwu',
  '2029-08-16': 'qixi',
  '2029-08-24': 'zhongyuan',
  '2029-09-22': 'zhongqiu',
  '2029-10-16': 'chongyang',
  '2030-01-11': 'laba',
  '2030-01-26': 'xiaonian',
  '2030-02-02': 'chuxi',
  '2030-02-03': 'chunjie',
  '2030-02-17': 'yuanxiao',
  '2030-03-05': 'longtaitou',
  '2030-04-05': 'qingming',
  '2030-06-05': 'duanwu',
  '2030-08-05': 'qixi',
  '2030-08-13': 'zhongyuan',
  '2030-09-12': 'zhongqiu',
  '2030-10-05': 'chongyang',
  '2031-01-01': 'laba',
  '2031-01-16': 'xiaonian',
  '2031-01-22': 'chuxi',
  '2031-01-23': 'chunjie',
  '2031-02-06': 'yuanxiao',
  '2031-02-22': 'longtaitou',
  '2031-04-05': 'qingming',
  '2031-06-24': 'duanwu',
  '2031-08-24': 'qixi',
  '2031-09-01': 'zhongyuan',
  '2031-10-01': 'zhongqiu',
  '2031-10-24': 'chongyang',
  '2032-01-20': 'laba',
  '2032-02-04': 'xiaonian',
  '2032-02-10': 'chuxi',
  '2032-02-11': 'chunjie',
  '2032-02-25': 'yuanxiao',
  '2032-03-13': 'longtaitou',
  '2032-04-04': 'qingming',
  '2032-06-12': 'duanwu',
  '2032-08-12': 'qixi',
  '2032-08-20': 'zhongyuan',
  '2032-09-19': 'zhongqiu',
  '2032-10-12': 'chongyang',
  '2033-01-08': 'laba',
  '2033-01-23': 'xiaonian',
  '2033-01-30': 'chuxi',
  '2033-01-31': 'chunjie',
  '2033-02-14': 'yuanxiao',
  '2033-03-02': 'longtaitou',
  '2033-04-04': 'qingming',
  '2033-06-01': 'duanwu',
  '2033-08-01': 'qixi',
  '2033-08-09': 'zhongyuan',
  '2033-09-08': 'zhongqiu',
  '2033-10-01': 'chongyang',
  '2034-01-27': 'laba',
  '2034-02-11': 'xiaonian',
  '2034-02-18': 'chuxi',
  '2034-02-19': 'chunjie',
  '2034-03-05': 'yuanxiao',
  '2034-03-21': 'longtaitou',
  '2034-04-05': 'qingming',
  '2034-06-20': 'duanwu',
  '2034-08-20': 'qixi',
  '2034-08-28': 'zhongyuan',
  '2034-09-27': 'zhongqiu',
  '2034-10-20': 'chongyang',
  '2035-01-16': 'laba',
  '2035-01-31': 'xiaonian',
  '2035-02-07': 'chuxi',
  '2035-02-08': 'chunjie',
  '2035-02-22': 'yuanxiao',
  '2035-03-11': 'longtaitou',
  '2035-04-05': 'qingming',
  '2035-06-10': 'duanwu',
  '2035-08-10': 'qixi',
  '2035-08-18': 'zhongyuan',
  '2035-09-16': 'zhongqiu',
  '2035-10-09': 'chongyang',
  '2036-01-05': 'laba',
  '2036-01-20': 'xiaonian',
  '2036-01-27': 'chuxi',
  '2036-01-28': 'chunjie',
  '2036-02-11': 'yuanxiao',
  '2036-02-28': 'longtaitou',
  '2036-04-04': 'qingming',
  '2036-05-30': 'duanwu',
  '2036-08-28': 'qixi',
  '2036-09-05': 'zhongyuan',
  '2036-10-04': 'zhongqiu',
  '2036-10-27': 'chongyang',
  '2037-01-23': 'laba',
  '2037-02-07': 'xiaonian',
  '2037-02-14': 'chuxi',
  '2037-02-15': 'chunjie',
  '2037-03-01': 'yuanxiao',
  '2037-03-18': 'longtaitou',
  '2037-04-04': 'qingming',
  '2037-06-18': 'duanwu',
  '2037-08-17': 'qixi',
  '2037-08-25': 'zhongyuan',
  '2037-09-24': 'zhongqiu',
  '2037-10-17': 'chongyang',
  '2038-01-12': 'laba',
  '2038-01-27': 'xiaonian',
  '2038-02-03': 'chuxi',
  '2038-02-04': 'chunjie',
  '2038-02-18': 'yuanxiao',
  '2038-03-07': 'longtaitou',
  '2038-04-05': 'qingming',
  '2038-06-07': 'duanwu',
  '2038-08-07': 'qixi',
  '2038-08-15': 'zhongyuan',
  '2038-09-13': 'zhongqiu',
  '2038-10-07': 'chongyang',
  '2039-01-02': 'laba',
  '2039-01-17': 'xiaonian',
  '2039-01-23': 'chuxi',
  '2039-01-24': 'chunjie',
  '2039-02-07': 'yuanxiao',
  '2039-02-24': 'longtaitou',
  '2039-04-05': 'qingming',
  '2039-05-27': 'duanwu',
  '2039-08-26': 'qixi',
  '2039-09-03': 'zhongyuan',
  '2039-10-02': 'zhongqiu',
  '2039-10-26': 'chongyang',
  '2040-01-21': 'laba',
  '2040-02-05': 'xiaonian',
  '2040-02-11': 'chuxi',
  '2040-02-12': 'chunjie',
  '2040-02-26': 'yuanxiao',
  '2040-03-14': 'longtaitou',
  '2040-04-04': 'qingming',
  '2040-06-14': 'duanwu',
  '2040-08-14': 'qixi',
  '2040-08-22': 'zhongyuan',
  '2040-09-20': 'zhongqiu',
  '2040-10-14': 'chongyang',
};

class LunarDate {
  final int month;
  final int day;
  final bool leap;
  final String name;
  const LunarDate(this.month, this.day, this.leap, this.name);
}

DateTime? _parseYmd(String s) {
  try {
    return DateTime.utc(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
    );
  } catch (_) {
    return null;
  }
}

final List<int> _lunarStarts = kLunarMonths
    .split(',')
    .map((s) => _parseYmd(s)!.millisecondsSinceEpoch ~/ 86400000)
    .toList();

LunarDate? lunarOf(DateTime date) {
  final n =
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
      86400000;
  if (n < _lunarStarts.first || n >= _lunarStarts.last) return null;
  var lo = 0, hi = _lunarStarts.length - 2, idx = 0;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (_lunarStarts[mid] <= n) {
      idx = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  final leap = kLunarLeap[idx] == '1';
  final m = int.parse(kLunarNames[idx], radix: 36);
  final dd = n - _lunarStarts[idx] + 1;
  return LunarDate(
    m,
    dd,
    leap,
    '${leap ? "闰" : ""}${kLunarMonthNames[m - 1]}${kLunarDayNames[dd - 1]}',
  );
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String? festivalIdOf(DateTime date) => kFestivals[_ymd(date)];

String festivalName(String id) => switch (id) {
  'chunjie' => '春节',
  'yuanxiao' => '元宵节',
  'longtaitou' => '龙抬头',
  'qingming' => '清明节',
  'duanwu' => '端午节',
  'qixi' => '七夕节',
  'zhongyuan' => '中元节',
  'zhongqiu' => '中秋节',
  'chongyang' => '重阳节',
  'laba' => '腊八节',
  'xiaonian' => '小年',
  'chuxi' => '除夕',
  _ => id,
};

/// 当日节气名（仅交节日）。
String? termToday(DateTime date) {
  final s = kTermDays[date.year];
  if (s == null) return null;
  final md =
      '${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  for (var i = 0; i < 24; i++) {
    if (s.substring(i * 4, i * 4 + 4) == md) return kTermNames[i];
  }
  return null;
}

class TermInfo {
  final int index;
  final String name;
  final int year;
  const TermInfo(this.index, this.name, this.year);
}

TermInfo? termAt(DateTime date) {
  final s = kTermDays[date.year];
  final md =
      '${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  if (s != null) {
    var best = -1;
    for (var i = 0; i < 24; i++) {
      if (s.substring(i * 4, i * 4 + 4).compareTo(md) <= 0) best = i;
    }
    if (best >= 0) return TermInfo(best, kTermNames[best], date.year);
  }
  final prev = kTermDays[date.year - 1];
  if (prev != null) return TermInfo(23, kTermNames[23], date.year - 1);
  return null;
}

DateTime? nextTerm(DateTime date) {
  final t = termAt(date);
  if (t == null) return null;
  if (t.index < 23) {
    final md = kTermDays[t.year]!.substring(
      (t.index + 1) * 4,
      (t.index + 1) * 4 + 4,
    );
    return DateTime(
      t.year,
      int.parse(md.substring(0, 2)),
      int.parse(md.substring(2, 4)),
    );
  }
  final ny = kTermDays[t.year + 1];
  if (ny == null) return null;
  final md = ny.substring(0, 4);
  return DateTime(
    t.year + 1,
    int.parse(md.substring(0, 2)),
    int.parse(md.substring(2, 4)),
  );
}

int dayDiff(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

String weekdayChinese(DateTime d) {
  const wk = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return wk[d.weekday - 1];
}
