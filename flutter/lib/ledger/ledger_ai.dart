import 'dart:convert';

import '../services/ai.dart';
import 'ledger_models.dart';

/// 记账模块的 AI 能力。
///
/// 和 TodoAi 一样：所有解析都做成纯函数，测试时不用联网；
/// 截图识别走 AiService 的多模态 content，cici 对话仍由调用方流式处理。
class LedgerAi {
  LedgerAi._();

  /// 测试钩子：文字请求（分析与自然语言记账）。
  static Future<String> Function(String prompt, String system)? completer;

  /// 测试钩子：图片识别。参数为 (prompt, system, dataUrl)。
  static Future<String> Function(String prompt, String system, String dataUrl)?
  visionCompleter;

  static Future<String> _complete(
    String prompt,
    String system, {
    int maxTokens = 900,
    double temperature = .3,
  }) {
    final hook = completer;
    if (hook != null) return hook(prompt, system);
    return AiService.complete(
      prompt: prompt,
      system: system,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  // -------------------------------------------------------------------------
  // 上下文
  // -------------------------------------------------------------------------

  /// 给 cici 与月度分析共用的账本摘要。只喂必要数据，避免提示词过长。
  static String contextFor({
    required String monthKey,
    required LedgerSummary summary,
    required LedgerPlan plan,
    required List<({LedgerCategory category, int spent, int budget})> budgets,
    required List<LedgerEntry> recent,
    required List<LedgerEntry> monthEntries,
    required List<LedgerCategory> categories,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final days = LedgerDates.daysInMonth(monthKey);
    final leftDays = (days - today.day + 1).clamp(1, 31);
    final buffer = StringBuffer()
      ..writeln('当前月份：${LedgerDates.monthLabel(monthKey)}')
      ..writeln(
        '本月支出 ${ledgerMoney(summary.expenseCents)}，'
        '收入 ${ledgerMoney(summary.incomeCents)}，'
        '结余 ${ledgerMoney(summary.balanceCents)}；共 ${summary.entryCount} 笔。',
      );
    if (plan.hasBudget) {
      buffer.writeln(
        '总预算 ${ledgerMoney(plan.budgetCents)}，'
        '已用 ${ledgerMoney(summary.expenseCents)}，'
        '剩余 ${ledgerMoney(summary.budgetRemainingCents)}，'
        '本月还剩 $leftDays 天，日均可用 '
        '${ledgerMoney((summary.budgetRemainingCents / leftDays).round())}。',
      );
    } else {
      buffer.writeln('本月还没有设置总预算。');
    }
    if (plan.hasIncome) {
      buffer.writeln(
        '收入目标 ${ledgerMoney(plan.incomeCents)}，'
        '完成度 ${(summary.incomeProgress * 100).toStringAsFixed(0)}%。',
      );
    }
    if (budgets.isNotEmpty) {
      buffer.writeln('分类预算执行：');
      for (final row in budgets) {
        final over = row.spent > row.budget;
        buffer.writeln(
          '- ${row.category.name}：已用 ${ledgerMoney(row.spent)} / '
          '预算 ${ledgerMoney(row.budget)}'
          '${over ? '（已超支 ${ledgerMoney(row.spent - row.budget)}）' : ''}',
        );
      }
    }
    final categoryNames = categories
        .where((c) => c.active)
        .map((c) => '${c.name}(${c.kind.label})')
        .join('、');
    buffer.writeln('可用分类：$categoryNames');
    if (monthEntries.isNotEmpty) {
      final top = Map<String, int>.of(summary.categorySpend).entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final labels = <String>[];
      for (final entry in top.take(5)) {
        final category = categories.firstWhere(
          (c) => c.id == entry.key,
          orElse: () => LedgerCategory(
            id: entry.key,
            name: '其他',
            kind: LedgerKind.expense,
            color: 0xFF8A7F6A,
            iconKey: 'flag',
          ),
        );
        labels.add('${category.name} ${ledgerMoney(entry.value)}');
      }
      if (labels.isNotEmpty) buffer.writeln('本月支出分类：${labels.join('、')}。');
    }
    if (recent.isNotEmpty) {
      buffer.writeln('最近账单：');
      for (final entry in recent.take(8)) {
        final category = categories.firstWhere(
          (c) => c.id == entry.categoryId,
          orElse: () => categories.isEmpty
              ? const LedgerCategory(
                  id: 'other_expense',
                  name: '其他',
                  kind: LedgerKind.expense,
                  color: 0xFF8A7F6A,
                  iconKey: 'flag',
                )
              : categories.first,
        );
        buffer.writeln(
          '- ${entry.occurredAt.month}月${entry.occurredAt.day}日 '
          '${LedgerDates.timeLabel(entry.occurredAt)} '
          '${entry.kind.label} ${ledgerMoney(entry.amountCents)} '
          '${category.name}${entry.note.isEmpty ? '' : ' ${entry.note}'}',
        );
      }
    }
    return buffer.toString().trim();
  }

  // -------------------------------------------------------------------------
  // cici 的系统提示
  // -------------------------------------------------------------------------

  static const String assistantSystem =
      '你是 Citro 记账模块里的 cici。你帮用户看账、分析消费、给可执行的省钱建议，也可以帮用户记账。\n'
      '规则：\n'
      '1. 只根据下面提供的真实账本数据回答，不编造金额、分类或账单；数据不足时直接说不知道。\n'
      '2. 金额都用元，保留到分；不要输出表格，建议 2～5 条，口语、简洁。\n'
      '3. 用户让你记一笔时，先在正文用一句话确认，再在末尾输出一个 ledger 代码块：\n'
      '```ledger\n'
      '{"entries":[{"kind":"expense","amount":18.5,"category":"餐饮","note":"咖啡","at":"2026-11-09 08:30"}]}\n'
      '```\n'
      '4. ledger 块只放用户明确说过的账；amount 用元；kind 只能是 expense / income；'
      'category 只能从可用分类里选，无法判断用「其他」。\n'
      '5. 不要直接说"已经记好了"，最终是否入账由用户点确认按钮决定。\n'
      '6. 除了代码块，不要在正文里重复 JSON。';

  // -------------------------------------------------------------------------
  // 月度分析
  // -------------------------------------------------------------------------

  static Future<String> analyze({
    required String monthKey,
    required LedgerSummary summary,
    required LedgerPlan plan,
    required List<({LedgerCategory category, int spent, int budget})> budgets,
    required List<LedgerEntry> recent,
    required List<LedgerEntry> monthEntries,
    required List<LedgerCategory> categories,
    DateTime? now,
  }) async {
    final context = contextFor(
      monthKey: monthKey,
      summary: summary,
      plan: plan,
      budgets: budgets,
      recent: recent,
      monthEntries: monthEntries,
      categories: categories,
      now: now,
    );
    const system =
        '你是冷静、具体的记账分析师。只依据给出的数据，不编造；'
        '不要空泛鼓励，不要评价人格。用中文输出 3 条短建议，每条一行，以「·」开头；'
        '每条不超过 32 字，必须带上具体金额或分类。';
    final prompt =
        '请分析这个月的收支与预算执行，指出最值得注意的 3 件事，'
        '并给出可以直接执行的调整建议。\n\n$context';
    return _complete(prompt, system, maxTokens: 500, temperature: .25);
  }

  // -------------------------------------------------------------------------
  // 截图识别
  // -------------------------------------------------------------------------

  static String _receiptPrompt(List<LedgerCategory> categories) {
    final names = categories
        .where((c) => c.active)
        .map((c) => '${c.name}(${c.kind.label})')
        .join('、');
    return '''
识别这张账单/支付截图里的所有收支明细。只输出严格 JSON，不要代码块，不要解释。
格式：
{"entries":[{"kind":"expense","amount":18.50,"category":"餐饮","note":"瑞幸咖啡","at":"2026-11-09 08:30","confidence":0.92}]}
规则：
1. 金额用元，保留两位小数；不要输出 ¥ 或千分位。
2. kind 只能是 expense（支出）或 income（收入），默认 expense。
3. category 只能从这些分类里选：$names；无法判断时支出用「其他」，收入用「其他」。
4. note 写商户或商品名，不超过 20 字；at 用 yyyy-MM-dd HH:mm，截图没有日期就用今天。
5. confidence 是 0 到 1 的数字；模糊、遮挡或不确定时降低。
6. 一张截图可能有多笔，全部输出；没有可识别账单时输出 {"entries":[]}。
''';
  }

  static const _receiptSystem =
      '你是账单 OCR 助手，只做识别与结构化，不推测用户没看到的金额。'
      '只输出严格 JSON，不要代码块。';

  static Future<List<LedgerDraft>> parseReceipt(
    String dataUrl, {
    required List<LedgerCategory> categories,
    DateTime? now,
  }) async {
    final prompt = _receiptPrompt(categories);
    final hook = visionCompleter;
    final String raw;
    if (hook != null) {
      raw = await hook(prompt, _receiptSystem, dataUrl);
    } else {
      raw = await AiService.completeContent(
        [
          {'type': 'text', 'text': prompt},
          {
            'type': 'image_url',
            'image_url': {'url': dataUrl},
          },
        ],
        system: _receiptSystem,
        maxTokens: 1600,
        temperature: .1,
      );
    }
    return parseDrafts(raw, categories: categories, now: now);
  }

  // -------------------------------------------------------------------------
  // 自然语言记账
  // -------------------------------------------------------------------------

  static Future<List<LedgerDraft>> parseText(
    String text, {
    required List<LedgerCategory> categories,
    DateTime? now,
  }) async {
    final names = categories
        .where((c) => c.active)
        .map((c) => '${c.name}(${c.kind.label})')
        .join('、');
    final prompt =
        '''
把用户这句话里的收支整理成账单。只输出严格 JSON：
{"entries":[{"kind":"expense","amount":18.5,"category":"餐饮","note":"咖啡","at":"2026-11-09 08:30","confidence":1}]}
规则：amount 用元；kind 只能是 expense / income；category 从 $names 里选，判断不了用「其他」；
at 用 yyyy-MM-dd HH:mm，用户没说时间就用今天；没有明确金额时输出 {"entries":[]}。
用户原话：$text
''';
    const system = '你是记账解析器。只提取用户明确说出的金额，不编造。只输出严格 JSON。';
    final raw = await _complete(
      prompt,
      system,
      maxTokens: 900,
      temperature: .1,
    );
    return parseDrafts(raw, categories: categories, now: now);
  }

  // -------------------------------------------------------------------------
  // 解析纯函数
  // -------------------------------------------------------------------------

  static List<LedgerDraft> parseDrafts(
    String raw, {
    required List<LedgerCategory> categories,
    DateTime? now,
  }) {
    final map = _decodeObject(raw);
    if (map == null) return const [];
    final list = map['entries'] ?? map['records'] ?? map['items'];
    if (list is! List) return const [];
    final today = now ?? DateTime.now();
    final out = <LedgerDraft>[];
    for (final item in list) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final kind = LedgerKindX.fromName(
        json['kind'] is String ? json['kind'] as String : null,
      );
      final amount = _asDouble(json['amount']);
      if (amount == null || amount <= 0) continue;
      final cents = (amount * 100).round();
      if (cents <= 0 || cents > 100000000000) continue;
      final categoryText = '${json['category'] ?? ''}'.trim();
      final category = _resolveCategory(categoryText, kind, categories);
      final note =
          '${json['note'] ?? json['merchant'] ?? json['desc'] ?? json['title'] ?? ''}'
              .trim();
      final at = _parseDate(
        '${json['at'] ?? json['date'] ?? json['time'] ?? ''}'.trim(),
        today,
      );
      final confidence = _asDouble(json['confidence']) ?? .8;
      out.add(
        LedgerDraft(
          kind: kind,
          amountCents: cents,
          categoryId: category.id,
          note: note,
          occurredAt: at,
          confidence: confidence.clamp(0.0, 1.0),
          rawText: categoryText.isEmpty ? note : categoryText,
        ),
      );
      if (out.length >= 20) break;
    }
    out.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return out;
  }

  /// 从 cici 回复里拆出正文和 ledger 动作块。代码块会从正文移除。
  static (String, List<LedgerDraft>) parseReply(
    String raw, {
    required List<LedgerCategory> categories,
    DateTime? now,
  }) {
    final drafts = <LedgerDraft>[];
    var clean = raw;
    final fence = RegExp(r'```(?:ledger|json)?\s*([\s\S]*?)```');
    for (final match in fence.allMatches(raw).toList()) {
      final body = match.group(1)?.trim() ?? '';
      if (!body.contains('"entries"') && !body.contains('"records"')) {
        continue;
      }
      final parsed = parseDrafts(body, categories: categories, now: now);
      if (parsed.isEmpty) continue;
      drafts.addAll(parsed);
      clean = clean.replaceFirst(match.group(0)!, '');
    }
    if (drafts.isEmpty && raw.contains('"entries"')) {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final candidate = raw.substring(start, end + 1);
        final parsed = parseDrafts(candidate, categories: categories, now: now);
        if (parsed.isNotEmpty) {
          drafts.addAll(parsed);
          clean = clean.replaceFirst(candidate, '');
        }
      }
    }
    return (clean.trim(), drafts.take(20).toList(growable: false));
  }

  static LedgerCategory _resolveCategory(
    String text,
    LedgerKind kind,
    List<LedgerCategory> categories,
  ) {
    if (text.isNotEmpty) {
      for (final category in categories) {
        if (category.kind == kind &&
            (category.id == text || category.name == text)) {
          return category;
        }
      }
      for (final category in categories) {
        if (category.kind == kind &&
            (category.name.contains(text) || text.contains(category.name))) {
          return category;
        }
      }
    }
    final otherId = kind == LedgerKind.expense
        ? 'other_expense'
        : 'other_income';
    for (final category in categories) {
      if (category.id == otherId) return category;
    }
    return LedgerCategory(
      id: otherId,
      name: '其他',
      kind: kind,
      color: 0xFF8A7F6A,
      iconKey: 'flag',
    );
  }

  static DateTime _parseDate(String text, DateTime fallback) {
    if (text.isEmpty) return fallback;
    final normalized = text.replaceAll('/', '-');
    DateTime? parsed = DateTime.tryParse(normalized);
    if (parsed != null) return parsed;
    final date = RegExp(
      r'(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2}))?',
    ).firstMatch(normalized);
    if (date != null) {
      final year = int.tryParse(date.group(1) ?? '') ?? fallback.year;
      final month = int.tryParse(date.group(2) ?? '') ?? fallback.month;
      final day = int.tryParse(date.group(3) ?? '') ?? fallback.day;
      final hour = int.tryParse(date.group(4) ?? '') ?? fallback.hour;
      final minute = int.tryParse(date.group(5) ?? '') ?? fallback.minute;
      try {
        return DateTime(year, month, day, hour, minute);
      } catch (_) {
        return fallback;
      }
    }
    // 只有时间时补上今天日期。
    final time = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(normalized);
    if (time != null) {
      return DateTime(
        fallback.year,
        fallback.month,
        fallback.day,
        int.tryParse(time.group(1) ?? '') ?? 0,
        int.tryParse(time.group(2) ?? '') ?? 0,
      );
    }
    return fallback;
  }

  static Map<String, dynamic>? _decodeObject(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      final json = jsonDecode(text);
      if (json is Map) return Map<String, dynamic>.from(json);
      if (json is List) return {'entries': json};
    } catch (_) {}
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final json = jsonDecode(text.substring(start, end + 1));
      if (json is Map) return Map<String, dynamic>.from(json);
      if (json is List) return {'entries': json};
    } catch (_) {}
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(cleaned);
    }
    return null;
  }
}
