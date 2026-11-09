import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/api.dart';
import '../services/platform.dart' as platform;
import '../services/prefs.dart';
import '../state/app_state.dart';
import 'ledger_models.dart';

/// 记账模块的唯一数据源。
///
/// 和 TodoStore 一样是独立单例，避免首页、cici 这些长页面跟着账单变化重建；
/// 数据先落本地 Prefs，登录后按 updatedAt 与云端合并。
class LedgerStore extends ChangeNotifier {
  LedgerStore._();

  static final LedgerStore instance = LedgerStore._();

  static const String prefsKey = PrefKeys.ledger;

  bool _inited = false;
  bool get inited => _inited;

  /// 数据版本：cici 洞察等缓存用它判断是否需要重新请求。
  int get revision => _updatedAt;

  /// 测试用：把单例恢复到「未初始化」状态，随后可重新 ensureInit。
  @visibleForTesting
  void resetForTest() {
    _pushTimer?.cancel();
    _inited = false;
    _accountSynced = false;
    _updatedAt = 0;
    _entries = [];
    _categories = _defaultCategories();
    _plans = {};
    _invalidateSummary();
  }

  int _updatedAt = 0;
  bool _accountSynced = false;
  Timer? _pushTimer;

  /// 只有账号与 token 同时就绪才请求云端；测试 / 游客状态一律走本地。
  bool get _signedIn =>
      AppState.instance.loggedIn && (Api.token?.isNotEmpty ?? false);

  List<LedgerEntry> _entries = [];
  List<LedgerCategory> _categories = _defaultCategories();
  Map<String, LedgerPlan> _plans = {};

  final Map<String, LedgerSummary> _summaryCache = {};
  int _summaryVersion = -1;

  List<LedgerEntry> get entries => List.unmodifiable(_entries);

  List<LedgerCategory> get categories => List.unmodifiable(_categories);

  List<LedgerCategory> get expenseCategories => _categories
      .where((c) => c.kind == LedgerKind.expense && c.active)
      .toList();

  List<LedgerCategory> get incomeCategories => _categories
      .where((c) => c.kind == LedgerKind.income && c.active)
      .toList();

  List<LedgerCategory> categoriesFor(LedgerKind kind) =>
      kind == LedgerKind.expense ? expenseCategories : incomeCategories;

  LedgerPlan planFor(String monthKey) =>
      _plans[monthKey] ?? LedgerPlan(monthKey: monthKey);

  LedgerCategory categoryOf(String id, {LedgerKind? kind}) {
    for (final category in _categories) {
      if (category.id == id) {
        return category.active ? category : category.copyWith(active: true);
      }
    }
    final fallbackKind = kind ?? LedgerKind.expense;
    return _otherCategory(fallbackKind);
  }

  LedgerCategory otherCategory(LedgerKind kind) => _otherCategory(kind);

  // -------------------------------------------------------------------------
  // 初始化与持久化
  // -------------------------------------------------------------------------

  Future<void> ensureInit() async {
    if (_inited) return;
    _inited = true;
    await _load();
    notifyListeners();
    unawaited(syncFromAccount());
  }

  Future<void> _load() async {
    _entries = [];
    _categories = _defaultCategories();
    _plans = {};
    _updatedAt = 0;
    final raw = Prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      _invalidateSummary();
      return;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return;
      final map = Map<String, dynamic>.from(json);
      final cats = (map['categories'] as List?)
          ?.whereType<Map>()
          .map((e) => LedgerCategory.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
          .toList();
      if (cats != null && cats.isNotEmpty) _categories = cats;

      // 版本升级新增的内置分类自动补齐；用户隐藏过的分类保留原状态。
      for (final category in _defaultCategories()) {
        if (_categories.every((c) => c.id != category.id)) {
          _categories.add(category);
        }
      }

      _entries =
          (map['entries'] as List?)
              ?.whereType<Map>()
              .map((e) => LedgerEntry.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.id.isNotEmpty && e.amountCents > 0)
              .toList() ??
          [];
      _entries.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

      final plans = map['plans'];
      if (plans is Map) {
        _plans = {
          for (final entry in plans.entries)
            if (entry.value is Map)
              '${entry.key}': LedgerPlan.fromJson(
                '${entry.key}',
                Map<String, dynamic>.from(entry.value as Map),
              ),
        };
      }
      final at = map['updatedAt'];
      _updatedAt = at is int ? at : (at is num ? at.toInt() : 0);
    } catch (_) {
      // 坏数据不阻塞模块启动，回到空账本。
      _entries = [];
      _categories = _defaultCategories();
      _plans = {};
      _updatedAt = 0;
    }
    _invalidateSummary();
  }

  Map<String, Object?> _payload() => {
    'entries': _entries.map((e) => e.toJson()).toList(),
    'categories': _categories.map((c) => c.toJson()).toList(),
    'plans': _plans.map((key, value) => MapEntry(key, value.toJson())),
    'updatedAt': _updatedAt,
  };

  Future<void> _save() async {
    _updatedAt = DateTime.now().millisecondsSinceEpoch;
    _invalidateSummary();
    await Prefs.setString(prefsKey, jsonEncode(_payload()));
    notifyListeners();
    _schedulePush();
  }

  void _invalidateSummary() {
    _summaryCache.clear();
    _summaryVersion = _updatedAt;
  }

  void _ensureSummaryVersion() {
    if (_summaryVersion != _updatedAt) _invalidateSummary();
  }

  // -------------------------------------------------------------------------
  // 账单
  // -------------------------------------------------------------------------

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  LedgerEntry addEntry({
    required LedgerKind kind,
    required int amountCents,
    required String categoryId,
    String note = '',
    DateTime? occurredAt,
    LedgerSource source = LedgerSource.manual,
  }) {
    final now = DateTime.now();
    final entry = LedgerEntry(
      id: _newId(kind == LedgerKind.expense ? 'exp' : 'inc'),
      kind: kind,
      amountCents: amountCents,
      categoryId: categoryId,
      note: note.trim(),
      occurredAt: occurredAt ?? now,
      createdAt: now,
      source: source,
    );
    _entries.add(entry);
    _entries.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    unawaited(_save());
    return entry;
  }

  void updateEntry(LedgerEntry entry) {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index < 0) return;
    _entries[index] = entry;
    _entries.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    unawaited(_save());
  }

  void removeEntry(String id) {
    final before = _entries.length;
    _entries.removeWhere((e) => e.id == id);
    if (_entries.length == before) return;
    unawaited(_save());
  }

  /// 撤销删除：把刚删除的账单按原 id 放回去。
  void restoreEntry(LedgerEntry entry) {
    if (_entries.any((e) => e.id == entry.id)) return;
    _entries.add(entry);
    _entries.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    unawaited(_save());
  }

  LedgerEntry? entryById(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  List<LedgerEntry> entriesInMonth(String monthKey) =>
      _entries.where((e) => e.monthKey == monthKey).toList(growable: false);

  List<LedgerEntry> recentEntries({int limit = 5}) =>
      _entries.take(limit).toList(growable: false);

  List<LedgerEntry> entriesOnDay(DateTime day) {
    final key = LedgerDates.dayKey(day);
    return _entries.where((e) => e.dayKey == key).toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // 预算 / 收入
  // -------------------------------------------------------------------------

  void setPlan(LedgerPlan plan) {
    _plans[plan.monthKey] = plan;
    unawaited(_save());
  }

  void setBudget(String monthKey, int budgetCents) {
    setPlan(planFor(monthKey).copyWith(budgetCents: budgetCents));
  }

  void setIncomeTarget(String monthKey, int incomeCents) {
    setPlan(planFor(monthKey).copyWith(incomeCents: incomeCents));
  }

  void setCategoryBudget(String monthKey, String categoryId, int budgetCents) {
    final plan = planFor(monthKey);
    final budgets = Map<String, int>.of(plan.categoryBudgets);
    if (budgetCents <= 0) {
      budgets.remove(categoryId);
    } else {
      budgets[categoryId] = budgetCents;
    }
    setPlan(plan.copyWith(categoryBudgets: budgets));
  }

  /// 从上月复制预算与收入目标，省得每月重新填。
  void copyPlanFrom(String monthKey, String sourceMonthKey) {
    final source = planFor(sourceMonthKey);
    setPlan(
      planFor(monthKey).copyWith(
        budgetCents: source.budgetCents,
        incomeCents: source.incomeCents,
        categoryBudgets: Map<String, int>.of(source.categoryBudgets),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 分类
  // -------------------------------------------------------------------------

  LedgerCategory addCategory({
    required String name,
    required LedgerKind kind,
    int color = 0xFF8A7F6A,
    String iconKey = 'flag',
  }) {
    final category = LedgerCategory(
      id: _newId(kind == LedgerKind.expense ? 'cat' : 'incat'),
      name: name.trim(),
      kind: kind,
      color: color,
      iconKey: iconKey,
    );
    _categories.add(category);
    unawaited(_save());
    return category;
  }

  void updateCategory(LedgerCategory category) {
    final index = _categories.indexWhere((c) => c.id == category.id);
    if (index < 0) return;
    _categories[index] = category;
    unawaited(_save());
  }

  /// 内置分类只能隐藏；自定义分类删除时把历史账单迁移到「其他」。
  void removeCategory(String id) {
    final index = _categories.indexWhere((c) => c.id == id);
    if (index < 0) return;
    final category = _categories[index];
    if (category.builtIn) {
      _categories[index] = category.copyWith(active: false);
      unawaited(_save());
      return;
    }
    final fallback = _otherCategory(category.kind);
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].categoryId == id) {
        _entries[i] = _entries[i].copyWith(categoryId: fallback.id);
      }
    }
    for (final key in _plans.keys.toList()) {
      final plan = _plans[key]!;
      if (plan.categoryBudgets.containsKey(id)) {
        final budgets = Map<String, int>.of(plan.categoryBudgets)..remove(id);
        _plans[key] = plan.copyWith(categoryBudgets: budgets);
      }
    }
    _categories.removeAt(index);
    unawaited(_save());
  }

  // -------------------------------------------------------------------------
  // 统计
  // -------------------------------------------------------------------------

  LedgerSummary summaryFor(String monthKey) {
    _ensureSummaryVersion();
    final cached = _summaryCache[monthKey];
    if (cached != null) return cached;

    final plan = planFor(monthKey);
    var expense = 0;
    var income = 0;
    var count = 0;
    final categorySpend = <String, int>{};
    for (final entry in _entries) {
      if (entry.monthKey != monthKey) continue;
      count++;
      if (entry.kind == LedgerKind.expense) {
        expense += entry.amountCents;
        categorySpend[entry.categoryId] =
            (categorySpend[entry.categoryId] ?? 0) + entry.amountCents;
      } else {
        income += entry.amountCents;
      }
    }
    final summary = LedgerSummary(
      monthKey: monthKey,
      expenseCents: expense,
      incomeCents: income,
      budgetCents: plan.budgetCents,
      incomeTargetCents: plan.incomeCents,
      entryCount: count,
      categorySpend: Map.unmodifiable(categorySpend),
    );
    _summaryCache[monthKey] = summary;
    return summary;
  }

  /// 每日收支：按天补零，图表与「今天花了多少」都直接取这份数据。
  List<({DateTime day, int expense, int income})> dailyTotals(String monthKey) {
    final start = LedgerDates.monthStart(monthKey);
    final days = LedgerDates.daysInMonth(monthKey);
    final expense = List<int>.filled(days, 0);
    final income = List<int>.filled(days, 0);
    for (final entry in _entries) {
      if (entry.monthKey != monthKey) continue;
      final index = entry.occurredAt.day - 1;
      if (index < 0 || index >= days) continue;
      if (entry.kind == LedgerKind.expense) {
        expense[index] += entry.amountCents;
      } else {
        income[index] += entry.amountCents;
      }
    }
    return [
      for (var i = 0; i < days; i++)
        (
          day: DateTime(start.year, start.month, i + 1),
          expense: expense[i],
          income: income[i],
        ),
    ];
  }

  int todayExpense([DateTime? now]) {
    final day = now ?? DateTime.now();
    var total = 0;
    for (final entry in entriesOnDay(day)) {
      if (entry.kind == LedgerKind.expense) total += entry.amountCents;
    }
    return total;
  }

  int todayIncome([DateTime? now]) {
    final day = now ?? DateTime.now();
    var total = 0;
    for (final entry in entriesOnDay(day)) {
      if (entry.kind == LedgerKind.income) total += entry.amountCents;
    }
    return total;
  }

  /// 分类预算执行情况，按使用比例从高到低排序；超支的排最前。
  List<({LedgerCategory category, int spent, int budget})> categoryBudgets(
    String monthKey,
  ) {
    final plan = planFor(monthKey);
    final summary = summaryFor(monthKey);
    final out = <({LedgerCategory category, int spent, int budget})>[];
    for (final category in _categories) {
      if (category.kind != LedgerKind.expense) continue;
      final budget = plan.budgetFor(category.id);
      if (budget <= 0) continue;
      out.add((
        category: category,
        spent: summary.categorySpend[category.id] ?? 0,
        budget: budget,
      ));
    }
    out.sort((a, b) {
      final aRatio = a.spent / a.budget;
      final bRatio = b.spent / b.budget;
      return bRatio.compareTo(aRatio);
    });
    return out;
  }

  // -------------------------------------------------------------------------
  // 默认分类
  // -------------------------------------------------------------------------

  static List<LedgerCategory> _defaultCategories() => [
    // 支出
    LedgerCategory(
      id: 'food',
      name: '餐饮',
      kind: LedgerKind.expense,
      color: 0xFFC08A4A,
      iconKey: 'fork',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'transport',
      name: '交通',
      kind: LedgerKind.expense,
      color: 0xFF6F8CA8,
      iconKey: 'location',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'shopping',
      name: '购物',
      kind: LedgerKind.expense,
      color: 0xFFB5717A,
      iconKey: 'cart',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'home',
      name: '居住',
      kind: LedgerKind.expense,
      color: 0xFF6E9A78,
      iconKey: 'home',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'fun',
      name: '娱乐',
      kind: LedgerKind.expense,
      color: 0xFF9A8FA6,
      iconKey: 'games',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'health',
      name: '医疗',
      kind: LedgerKind.expense,
      color: 0xFFC4855D,
      iconKey: 'heart',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'study',
      name: '学习',
      kind: LedgerKind.expense,
      color: 0xFF8FA6BE,
      iconKey: 'book',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'social',
      name: '人情',
      kind: LedgerKind.expense,
      color: 0xFFA79E8C,
      iconKey: 'users',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'other_expense',
      name: '其他',
      kind: LedgerKind.expense,
      color: 0xFF8A7F6A,
      iconKey: 'flag',
      builtIn: true,
    ),
    // 收入
    LedgerCategory(
      id: 'salary',
      name: '工资',
      kind: LedgerKind.income,
      color: 0xFF6E9A78,
      iconKey: 'note',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'bonus',
      name: '奖金',
      kind: LedgerKind.income,
      color: 0xFFE0A03E,
      iconKey: 'trophy',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'invest',
      name: '理财',
      kind: LedgerKind.income,
      color: 0xFF6F8CA8,
      iconKey: 'board',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'parttime',
      name: '兼职',
      kind: LedgerKind.income,
      color: 0xFFC08A4A,
      iconKey: 'clock',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'gift',
      name: '红包',
      kind: LedgerKind.income,
      color: 0xFFB5717A,
      iconKey: 'heart',
      builtIn: true,
    ),
    LedgerCategory(
      id: 'other_income',
      name: '其他',
      kind: LedgerKind.income,
      color: 0xFF8A7F6A,
      iconKey: 'flag',
      builtIn: true,
    ),
  ];

  LedgerCategory _otherCategory(LedgerKind kind) {
    final id = kind == LedgerKind.expense ? 'other_expense' : 'other_income';
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    return kind == LedgerKind.expense
        ? const LedgerCategory(
            id: 'other_expense',
            name: '其他',
            kind: LedgerKind.expense,
            color: 0xFF8A7F6A,
            iconKey: 'flag',
          )
        : const LedgerCategory(
            id: 'other_income',
            name: '其他',
            kind: LedgerKind.income,
            color: 0xFF8A7F6A,
            iconKey: 'flag',
          );
  }

  // -------------------------------------------------------------------------
  // 账号同步
  // -------------------------------------------------------------------------

  Future<void> syncFromAccount({bool force = false}) async {
    if (platform.isTest) return;
    if (!force && _accountSynced) return;
    if (!_signedIn) return;
    // 登录可能发生在首页记账卡初始化之前；先把本地读进来，
    // 否则会把空账本当成最新数据推上去。
    if (!_inited) {
      _inited = true;
      await _load();
      notifyListeners();
    }
    _accountSynced = true;
    try {
      final json = await Api.ledgerGet();
      final remote = json['ledger'];
      final at = json['at'] is num ? (json['at'] as num).toInt() : 0;
      if (remote is Map && at > _updatedAt) {
        await _applyRemote(Map<String, dynamic>.from(remote), at);
        return;
      }
      _schedulePush(immediate: true);
    } catch (_) {
      // 离线或服务端未部署：继续使用本地数据。
    }
  }

  /// 登出时清掉本机账本，避免下一个账号在同一台设备看到上一个人的账。
  Future<void> clearLocal() async {
    _pushTimer?.cancel();
    _accountSynced = false;
    _inited = true;
    _updatedAt = 0;
    _entries = [];
    _categories = _defaultCategories();
    _plans = {};
    _invalidateSummary();
    try {
      await Prefs.setString(prefsKey, null);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _applyRemote(Map<String, dynamic> remote, int at) async {
    await Prefs.setString(prefsKey, jsonEncode({...remote, 'updatedAt': at}));
    _inited = true;
    await _load();
    _updatedAt = at;
    _invalidateSummary();
    notifyListeners();
  }

  void _schedulePush({bool immediate = false}) {
    if (platform.isTest) return;
    if (!_signedIn) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 900),
      _pushRemote,
    );
  }

  Future<void> _pushRemote() async {
    if (!_signedIn) return;
    try {
      await Api.ledgerSave(_payload());
    } catch (_) {
      // 网络恢复后下一次修改会再次推送。
    }
  }
}
