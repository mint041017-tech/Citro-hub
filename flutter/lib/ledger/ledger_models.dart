import 'package:flutter/material.dart';

/// 记账模块的数据模型。
///
/// 金额统一用「分」的整数保存，避免 0.1 + 0.2 这类浮点误差；
/// JSON 字段和项目里的 TodoCategory / CookIngredient 保持同一套手写容错风格。

// ---------------------------------------------------------------------------
// 枚举
// ---------------------------------------------------------------------------

enum LedgerKind { expense, income }

extension LedgerKindX on LedgerKind {
  String get label => this == LedgerKind.expense ? '支出' : '收入';

  String get actionLabel => this == LedgerKind.expense ? '记支出' : '记收入';

  static LedgerKind fromName(String? raw) => LedgerKind.values.firstWhere(
    (k) => k.name == raw,
    orElse: () => LedgerKind.expense,
  );
}

enum LedgerSource { manual, scan, cici }

extension LedgerSourceX on LedgerSource {
  String get label => switch (this) {
    LedgerSource.manual => '手动',
    LedgerSource.scan => '截图',
    LedgerSource.cici => 'cici',
  };

  static LedgerSource fromName(String? raw) => LedgerSource.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => LedgerSource.manual,
  );
}

// ---------------------------------------------------------------------------
// 分类
// ---------------------------------------------------------------------------

class LedgerCategory {
  final String id;
  final String name;
  final LedgerKind kind;
  final int color;
  final String iconKey;
  final bool builtIn;

  /// 隐藏的分类不再出现在选择器里，但历史账单仍然能显示分类名。
  final bool active;

  const LedgerCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.color,
    required this.iconKey,
    this.builtIn = false,
    this.active = true,
  });

  Color get tint => Color(color);

  LedgerCategory copyWith({
    String? name,
    int? color,
    String? iconKey,
    bool? active,
  }) => LedgerCategory(
    id: id,
    name: name ?? this.name,
    kind: kind,
    color: color ?? this.color,
    iconKey: iconKey ?? this.iconKey,
    builtIn: builtIn,
    active: active ?? this.active,
  );

  factory LedgerCategory.fromJson(Map<String, dynamic> j) => LedgerCategory(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    kind: LedgerKindX.fromName(
      j['kind'] is String ? j['kind'] as String : null,
    ),
    color: _asInt(j['color'], 0xFF8A7F6A),
    iconKey: '${j['icon'] ?? 'flag'}',
    builtIn: j['builtIn'] == true,
    active: j['active'] != false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'color': color,
    'icon': iconKey,
    'builtIn': builtIn,
    'active': active,
  };
}

// ---------------------------------------------------------------------------
// 账单
// ---------------------------------------------------------------------------

class LedgerEntry {
  final String id;
  final LedgerKind kind;
  final int amountCents;
  final String categoryId;
  final String note;
  final DateTime occurredAt;
  final DateTime createdAt;
  final LedgerSource source;

  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.amountCents,
    required this.categoryId,
    this.note = '',
    required this.occurredAt,
    required this.createdAt,
    this.source = LedgerSource.manual,
  });

  String get dayKey => LedgerDates.dayKey(occurredAt);

  String get monthKey => LedgerDates.monthKey(occurredAt);

  double get amountYuan => amountCents / 100.0;

  LedgerEntry copyWith({
    LedgerKind? kind,
    int? amountCents,
    String? categoryId,
    String? note,
    DateTime? occurredAt,
    LedgerSource? source,
  }) => LedgerEntry(
    id: id,
    kind: kind ?? this.kind,
    amountCents: amountCents ?? this.amountCents,
    categoryId: categoryId ?? this.categoryId,
    note: note ?? this.note,
    occurredAt: occurredAt ?? this.occurredAt,
    createdAt: createdAt,
    source: source ?? this.source,
  );

  factory LedgerEntry.fromJson(Map<String, dynamic> j) {
    final occurred = _asInt(j['occurredAt'], 0);
    final created = _asInt(j['createdAt'], occurred);
    return LedgerEntry(
      id: '${j['id'] ?? ''}',
      kind: LedgerKindX.fromName(
        j['kind'] is String ? j['kind'] as String : null,
      ),
      amountCents: _asInt(j['amount'], 0),
      categoryId: '${j['category'] ?? ''}',
      note: '${j['note'] ?? ''}',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(occurred),
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
      source: LedgerSourceX.fromName(
        j['source'] is String ? j['source'] as String : null,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'amount': amountCents,
    'category': categoryId,
    'note': note,
    'occurredAt': occurredAt.millisecondsSinceEpoch,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'source': source.name,
  };
}

// ---------------------------------------------------------------------------
// 每月预算 / 收入
// ---------------------------------------------------------------------------

class LedgerPlan {
  final String monthKey;

  /// 本月总支出预算；0 表示还没设置。
  final int budgetCents;

  /// 本月收入目标；0 表示还没设置。
  final int incomeCents;

  /// 分类预算：categoryId -> 分。只对支出分类生效。
  final Map<String, int> categoryBudgets;

  const LedgerPlan({
    required this.monthKey,
    this.budgetCents = 0,
    this.incomeCents = 0,
    this.categoryBudgets = const {},
  });

  bool get hasBudget => budgetCents > 0;

  bool get hasIncome => incomeCents > 0;

  int budgetFor(String categoryId) => categoryBudgets[categoryId] ?? 0;

  LedgerPlan copyWith({
    int? budgetCents,
    int? incomeCents,
    Map<String, int>? categoryBudgets,
  }) => LedgerPlan(
    monthKey: monthKey,
    budgetCents: budgetCents ?? this.budgetCents,
    incomeCents: incomeCents ?? this.incomeCents,
    categoryBudgets: categoryBudgets ?? this.categoryBudgets,
  );

  factory LedgerPlan.fromJson(String monthKey, Map<String, dynamic> j) {
    final raw = j['categoryBudgets'];
    final budgets = <String, int>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = '${entry.key}';
        final value = _asInt(entry.value, 0);
        if (key.isNotEmpty && value > 0) budgets[key] = value;
      }
    }
    return LedgerPlan(
      monthKey: monthKey,
      budgetCents: _asInt(j['budget'], 0),
      incomeCents: _asInt(j['income'], 0),
      categoryBudgets: budgets,
    );
  }

  Map<String, dynamic> toJson() => {
    'budget': budgetCents,
    'income': incomeCents,
    'categoryBudgets': categoryBudgets,
  };
}

// ---------------------------------------------------------------------------
// 待确认草稿（截图识别 / cici 代记账）
// ---------------------------------------------------------------------------

class LedgerDraft {
  final LedgerKind kind;
  final int amountCents;
  final String categoryId;
  final String note;
  final DateTime occurredAt;

  /// 识别置信度 0~1；手动输入或 cici 文本解析时为 1。
  final double confidence;

  /// 识别出的商户/来源文字，便于在草稿卡上展示原始信息。
  final String rawText;

  const LedgerDraft({
    required this.kind,
    required this.amountCents,
    required this.categoryId,
    this.note = '',
    required this.occurredAt,
    this.confidence = 1,
    this.rawText = '',
  });

  LedgerDraft copyWith({
    LedgerKind? kind,
    int? amountCents,
    String? categoryId,
    String? note,
    DateTime? occurredAt,
    double? confidence,
  }) => LedgerDraft(
    kind: kind ?? this.kind,
    amountCents: amountCents ?? this.amountCents,
    categoryId: categoryId ?? this.categoryId,
    note: note ?? this.note,
    occurredAt: occurredAt ?? this.occurredAt,
    confidence: confidence ?? this.confidence,
    rawText: rawText,
  );

  bool get needsReview => confidence > 0 && confidence < 0.7;
}

// ---------------------------------------------------------------------------
// 月度汇总
// ---------------------------------------------------------------------------

class LedgerSummary {
  final String monthKey;
  final int expenseCents;
  final int incomeCents;
  final int budgetCents;
  final int incomeTargetCents;
  final int entryCount;
  final Map<String, int> categorySpend;

  const LedgerSummary({
    required this.monthKey,
    required this.expenseCents,
    required this.incomeCents,
    required this.budgetCents,
    required this.incomeTargetCents,
    required this.entryCount,
    required this.categorySpend,
  });

  int get balanceCents => incomeCents - expenseCents;

  int get budgetRemainingCents =>
      budgetCents > 0 ? budgetCents - expenseCents : 0;

  bool get overBudget => budgetCents > 0 && expenseCents > budgetCents;

  double get budgetProgress =>
      budgetCents <= 0 ? 0 : (expenseCents / budgetCents).clamp(0.0, 1.0);

  /// 储蓄率：结余 / 收入。没有收入时返回 0，避免除零。
  double get savingRate =>
      incomeCents <= 0 ? 0 : (balanceCents / incomeCents).clamp(-1.0, 1.0);

  double get incomeProgress => incomeTargetCents <= 0
      ? 0
      : (incomeCents / incomeTargetCents).clamp(0.0, 1.0);
}

// ---------------------------------------------------------------------------
// 日期与金额工具
// ---------------------------------------------------------------------------

class LedgerDates {
  const LedgerDates._();

  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  static String dayKey(DateTime d) =>
      '${monthKey(d)}-${d.day.toString().padLeft(2, '0')}';

  static DateTime monthStart(String monthKey) {
    final parts = monthKey.split('-');
    final year = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 2000;
    final month = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
    return DateTime(year, month);
  }

  static DateTime monthEnd(String monthKey) {
    final start = monthStart(monthKey);
    return DateTime(start.year, start.month + 1, 0, 23, 59, 59, 999);
  }

  static String monthLabel(String monthKey) {
    final start = monthStart(monthKey);
    return '${start.year} 年 ${start.month} 月';
  }

  static String shortMonthLabel(String monthKey) {
    final start = monthStart(monthKey);
    return '${start.month} 月';
  }

  static String monthKeyOfOffset(String key, int offset) {
    final start = monthStart(key);
    return LedgerDates.monthKey(DateTime(start.year, start.month + offset));
  }

  static bool isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  static int daysInMonth(String monthKey) => monthEnd(monthKey).day;

  static String weekLabel(DateTime d) {
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    return '周${week[d.weekday - 1]}';
  }

  static String timeLabel(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 金额显示：默认带 ¥，大额加千分位，整数不强行补 .00。
String ledgerMoney(int cents, {bool symbol = true, bool compact = false}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final yuan = abs ~/ 100;
  final fen = abs % 100;
  String number;
  if (compact && yuan >= 10000) {
    final wan = yuan / 10000;
    number = '${_trimZero(wan.toStringAsFixed(wan >= 100 ? 0 : 1))}万';
  } else {
    final grouped = _groupDigits(yuan);
    number = fen == 0 ? grouped : '$grouped.${fen.toString().padLeft(2, '0')}';
  }
  return '${negative ? '-' : ''}${symbol ? '¥' : ''}$number';
}

/// 输入解析：支持 "12"、"12.3"、"12.34"、"￥12.34"、"，" 千分位。
int? ledgerParseAmount(String raw) {
  var text = raw.trim().replaceAll('¥', '').replaceAll('￥', '');
  text = text.replaceAll(',', '').replaceAll('，', '');
  if (text.isEmpty) return null;
  final match = RegExp(r'^\d+(\.\d{0,2})?$').firstMatch(text);
  if (match == null) return null;
  final parts = text.split('.');
  final yuan = int.tryParse(parts[0]) ?? 0;
  var fen = 0;
  if (parts.length > 1 && parts[1].isNotEmpty) {
    fen = int.parse(parts[1].padRight(2, '0').substring(0, 2));
  }
  return yuan * 100 + fen;
}

String _groupDigits(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) buffer.write(',');
    buffer.write(raw[i]);
  }
  return buffer.toString();
}

String _trimZero(String value) {
  if (!value.contains('.')) return value;
  return value.replaceFirst(RegExp(r'\.?0+$'), '');
}

int _asInt(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
