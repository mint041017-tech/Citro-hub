import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../overlays/ai_chat.dart';
import '../overlays/auth_modal.dart';
import '../overlays/cook_editor.dart';
import '../overlays/ingredient_library.dart';
import '../overlays/timer_sheet.dart';
import '../services/api.dart';
import '../services/cook_timer.dart';
import '../services/models.dart';
import '../services/prefs.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/app_image.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import '../widgets/tablet_shell.dart';
import 'web_scrapbook.dart';

class CookPage extends StatefulWidget {
  const CookPage({super.key});
  @override
  State<CookPage> createState() => _CookPageState();
}

class _CookPageState extends State<CookPage> {
  List<Recipe> mine = [];
  List<Recipe> square = [];
  List<ShoppingItem> shopping = [];
  List<FridgeItem> fridge = [];
  String tab = 'recipes';
  static const _cookTabOrder = [
    'recipes',
    'square',
    'food',
    'find',
    'shopping',
  ];
  static const _navItems = <(String, String, String)>[
    ('recipes', '食谱库', AppIcons.book),
    ('square', '食谱广场', AppIcons.globe),
    ('food', '吃什么', AppIcons.fork),
    ('find', '找菜', AppIcons.search),
    ('shopping', '购物清单', AppIcons.cart),
  ];
  static const _desktopNavItems = <(String, String, String)>[
    ('recipes', '食谱库', AppIcons.book),
    ('square', '食谱广场', AppIcons.globe),
    ('find', '找菜', AppIcons.search),
    ('shopping', '购物清单', AppIcons.cart),
    ('food', '吃什么', AppIcons.fork),
  ];
  // 内部视图切换的方向：底 Tab 按左右顺序、进详情向前、返回向后。
  String _lastBodyKey = '';
  String _prevTab = 'recipes';
  String? _prevDetailId;
  String _prevFindView = 'fridge';
  int _bodyDir = 1;
  bool foodActive = false;
  String cat = '';
  String search = '';
  bool loading = false;
  bool loaded = false;
  String? error;
  Recipe? detail;
  String detailSource = 'mine';
  bool detailLoading = false;
  Timer? searchDebounce;
  AppState? _app;
  String? _lastUser;
  final shoppingInput = TextEditingController();
  final findInput = TextEditingController();
  String findView = 'fridge';
  final List<String> dishSel = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.app;
    if (_app != app) {
      _app?.removeListener(_onApp);
      _app = app;
      app.addListener(_onApp);
      _lastUser = app.user?.name;
      if (app.loggedIn) _load();
    }
  }

  void _onApp() {
    final name = _app?.user?.name;
    if (name != _lastUser) {
      _lastUser = name;
      if (name != null) {
        _load();
      } else {
        setState(() {
          mine = [];
          square = [];
          shopping = [];
          fridge = [];
          loaded = false;
          detail = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _app?.removeListener(_onApp);
    searchDebounce?.cancel();
    shoppingInput.dispose();
    findInput.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!context.app.loggedIn) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final j = await Api.cookData();
      if (!mounted) return;
      final recipes = ((j['recipes'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => Recipe.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      for (final r in recipes) {
        r.mine = true;
        r.owner = _app?.user?.name;
      }
      final shop = ((j['shopping'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => ShoppingItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final fr = ((j['fridge'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => FridgeItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      setState(() {
        mine = recipes;
        shopping = shop;
        fridge = fr;
        loaded = true;
      });
      _precacheCovers(recipes);
      _ensureSquare();
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString().replaceFirst('ApiException: ', '');
          loaded = true;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _ensureSquare() async {
    if (!context.app.loggedIn) return;
    try {
      final list = await Api.cookSquare();
      if (mounted) {
        setState(() => square = list);
        _precacheCovers(list);
      }
    } catch (_) {}
  }

  void _precacheCovers(List<Recipe> list) {
    final urls = list
        .take(20)
        .where((r) => r.cover.isNotEmpty)
        .map((r) => Api.imageUrl(r.cover));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppImage.precache(context, urls);
    });
  }

  void _openAuth() {
    showAuthModal(context, onDone: _load);
  }

  Future<void> _newRecipe() async {
    if (!context.app.loggedIn) {
      _openAuth();
      return;
    }
    final saved = await showCookEditor(context, null);
    if (saved != null && mounted) {
      saved.mine = true;
      saved.owner = context.app.user?.name;
      setState(() {
        mine.removeWhere((r) => r.id == saved.id);
        mine.insert(0, saved);
      });
      _ensureSquare();
    }
  }

  Future<void> _openDetail(Recipe r, String source) async {
    Recipe target = r;
    if (source == 'square' && r.mine) {
      final hit = mine.where((e) => e.id == r.id);
      if (hit.isNotEmpty) target = hit.first;
    }
    setState(() {
      detail = target;
      detailSource = source;
      detailLoading = false;
    });
  }

  void _switchTab(String t) {
    if (t == 'food') {
      _openFoodDraw();
      return;
    }
    setState(() {
      tab = t;
      detail = null;
      cat = '';
      search = '';
    });
    if (t == 'square') _ensureSquare();
  }

  Future<void> _openFoodDraw() async {
    setState(() => foodActive = true);
    try {
      final picked = await showFoodSheet(context, mine);
      if (picked != null && mounted) {
        await _openDetail(picked, 'mine');
      }
    } finally {
      if (mounted) setState(() => foodActive = false);
    }
  }

  Future<bool> _saveShopping() async {
    try {
      final list = await Api.saveShopping(shopping);
      if (mounted) setState(() => shopping = list);
      return true;
    } catch (e) {
      if (mounted) AppToast.show(context, '清单保存失败');
      return false;
    }
  }

  Future<void> _addIngredientsToShopping(Recipe r) async {
    final seen = {for (final it in shopping) it.text.trim()};
    var added = 0;
    for (final it in r.ingredients) {
      final name = it.name.trim();
      if (name.isEmpty) continue;
      final amount = it.amount.trim();
      final text = amount.isEmpty ? name : '$name $amount';
      if (!seen.add(text)) continue;
      shopping.add(ShoppingItem(text: text));
      added++;
    }
    if (added == 0) {
      if (mounted) AppToast.show(context, '食材已经在购物清单里了');
      return;
    }
    final ok = await _saveShopping();
    if (ok && mounted) AppToast.show(context, '已加入 $added 项到购物清单');
  }

  Future<void> _saveFridge() async {
    try {
      final list = await Api.saveFridge(fridge);
      if (mounted) setState(() => fridge = list);
    } catch (e) {
      if (mounted) AppToast.show(context, '冰箱保存失败');
    }
  }

  Future<void> _customTimer() async {
    final minutes = await showTimerMinutesSheet(context, initial: 10);
    if (minutes != null) CookTimer.instance.start('自定义计时', minutes);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final bodyKey = '${tab}-${detail?.id ?? 'list'}-$findView';
    if (bodyKey != _lastBodyKey) {
      if ((detail?.id ?? '') != (_prevDetailId ?? '')) {
        _bodyDir = _prevDetailId == null ? 1 : -1;
      } else if (tab != _prevTab) {
        final a = _cookTabOrder.indexOf(_prevTab);
        final b = _cookTabOrder.indexOf(tab);
        _bodyDir = b >= a ? 1 : -1;
      } else {
        _bodyDir = _prevFindView == 'fridge' ? 1 : -1;
      }
      _prevTab = tab;
      _prevDetailId = detail?.id;
      _prevFindView = findView;
      _lastBodyKey = bodyKey;
    }
    final media = MediaQuery.of(context);
    final duo = CitroForm.duoDevice(media.size);
    final tablet = media.size.width >= 900;
    final main = Column(
      children: [
        _topBar(context, app),
        if (app.loggedIn &&
            detail == null &&
            (tab == 'recipes' || tab == 'square'))
          _searchAndCats(context),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) {
              final isNew = child.key == ValueKey(bodyKey);
              final d = isNew ? _bodyDir : -_bodyDir;
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: Offset(d * 0.05, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey('${tab}-${detail?.id ?? 'list'}-$findView'),
              child: !app.loggedIn
                  ? _loginGate(context)
                  : (!loaded && loading
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : (error != null && mine.isEmpty)
                        ? _errorView(context)
                        : detail != null
                        ? _detailView(context)
                        : _body(context)),
            ),
          ),
        ),
      ],
    );
    if (duo) {
      final railWidth = media.padding.right > 84 ? media.padding.right : 84.0;
      final contentMedia = media.copyWith(
        padding: media.padding.copyWith(right: 0),
        viewPadding: media.viewPadding.copyWith(right: 0),
      );
      return PopScope(
        canPop: detail == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && detail != null) setState(() => detail = null);
        },
        child: Scaffold(
          body: PaperBackground(
            child: SafeArea(
              left: false,
              right: false,
              bottom: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: MediaQuery(
                      data: contentMedia,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: main,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: railWidth,
                    child: CitroDuoCookRail(
                      items: _navItems,
                      activeKey: tab,
                      foodActive: foodActive,
                      onSelect: _switchTab,
                      onBack: () {
                        if (detail != null) {
                          setState(() => detail = null);
                        } else {
                          popOrHome(context);
                        }
                      },
                      topInset: CitroForm.duoRailTopInset(media.size),
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: null,
        ),
      );
    }
    return PopScope(
      canPop: detail == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && detail != null) setState(() => detail = null);
      },
      child: Scaffold(
        body: PaperBackground(
          child: SafeArea(
            bottom: tablet,
            child: tablet
                ? Row(
                    children: [
                      SizedBox(
                        width: kIsWeb ? 248 : 220,
                        child: _sideNav(context),
                      ),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1040),
                            child: main,
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: main,
                    ),
                  ),
          ),
        ),
        bottomNavigationBar: tablet ? null : _bottomNav(context),
      ),
    );
  }

  Widget _sideNav(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 18),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/logo.webp',
                    width: 38,
                    height: 38,
                    cacheWidth: 114,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '食谱日记',
                        style: context.heading(size: 17, color: c.ink),
                      ),
                      Text(
                        'NOMBOOK',
                        style: context.body(
                          size: 9,
                          weight: FontWeight.w700,
                          color: c.inkSoft,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          DashedLine(color: c.line2.withAlpha(150)),
          const SizedBox(height: 12),
          for (final item in _desktopNavItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _sideTab(
                context,
                key: item.$1,
                label: item.$2,
                icon: item.$3,
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '把喜欢的味道，一页页收好。',
              style: context.hand(size: 13, color: c.inkSoft),
            ),
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: WebHomeBackPill(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sideTab(
    BuildContext context, {
    required String key,
    required String label,
    required String icon,
  }) {
    final c = context.c;
    final active = key == 'food' ? foodActive : tab == key;
    return Pressable(
      onTap: () => _switchTab(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: active ? c.hl : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? c.accent.withAlpha(110) : Colors.transparent,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: c.accent.withAlpha(20),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            AppIcon(
              strokeSvg(icon, width: 2),
              size: 18,
              color: active ? c.accentInk : c.inkSoft,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: context.body(
                  size: 13.5,
                  weight: FontWeight.w700,
                  color: active ? c.accentInk : c.ink2,
                ),
              ),
            ),
            if (active)
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, AppState app) {
    final c = context.c;
    final media = MediaQuery.sizeOf(context);
    final duo = CitroForm.duoDevice(media);
    final webSide = kIsWeb && CitroForm.tabletNav(media);
    final isDetail = detail != null;
    final logged = app.loggedIn;
    final title = isDetail
        ? detail!.name
        : (!logged
              ? '食谱日记'
              : switch (tab) {
                  'square' => '食谱广场',
                  'find' => '找菜',
                  'shopping' => '购物清单',
                  _ => '食谱库',
                });
    final sub = isDetail
        ? (detailSource == 'square' ? '来自食谱广场' : 'NOMBOOK · RECIPE DIARY')
        : !logged
        ? '登录后开始'
        : switch (tab) {
            'square' => '大家公开的拿手菜',
            'find' => '看看冰箱里能做什么',
            'shopping' => '顺手记下要买的',
            _ => 'NOMBOOK · RECIPE DIARY',
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 2),
      child: Row(
        children: [
          if (!duo && (!webSide || isDetail)) ...[
            Pressable(
              onTap: () {
                if (isDetail) {
                  setState(() => detail = null);
                } else {
                  popOrHome(context);
                }
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.line),
                  boxShadow: CitroColors.shadows.paper(c),
                ),
                child: Center(
                  child: AppIcon(
                    strokeSvg(AppIcons.arrowLeft, width: 2.2),
                    size: 16,
                    color: c.ink2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.heading(size: 20, color: c.ink),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                Text(
                  sub,
                  style: context.body(
                    size: 9,
                    color: c.accentInk,
                    letterSpacing: .7,
                  ),
                ),
              ],
            ),
          ),
          if (isDetail && logged) ...[
            Pressable(
              onTap: () => showAiChat(context, recipe: detail),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: c.hl,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.accent.withAlpha(120)),
                  boxShadow: CitroColors.shadows.note(c),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.sparkle, width: 2),
                      size: 16,
                      color: c.accentInk,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'AI',
                      style: context.body(
                        size: 12,
                        weight: FontWeight.w700,
                        color: c.accentInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (logged && !isDetail && (tab == 'recipes' || tab == 'square'))
            Pressable(
              onTap: _newRecipe,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: CitroColors.shadows.note(c),
                ),
                child: Center(
                  child: Text(
                    '＋ 新食谱',
                    style: context.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: const Color(0xFF2E2C22),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchAndCats(BuildContext context) {
    final c = context.c;
    final src = tab == 'square' ? square : mine;
    final catMap = <String, int>{};
    for (final r in src) {
      for (final t in r.tags) {
        catMap[t] = (catMap[t] ?? 0) + 1;
      }
    }
    final cats = catMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tab == 'recipes' || tab == 'square')
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.line2),
              ),
              child: Row(
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.search, width: 2),
                    size: 15,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => search = v),
                      style: context.body(size: 12.5),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: '搜食谱 / 标签 / 食材',
                        hintStyle: context.body(size: 12, color: c.inkSoft),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (cats.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              children: [
                _catChip(context, '', '全部', src.length),
                for (final e in cats.take(10))
                  _catChip(context, e.key, e.key, e.value),
              ],
            ),
          ),
      ],
    );
  }

  Widget _catChip(BuildContext context, String value, String label, int count) {
    final c = context.c;
    final on = cat == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => cat = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: on ? c.accent : c.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? c.accent : c.line2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: context.body(
                  size: 11,
                  weight: FontWeight.w600,
                  color: on ? const Color(0xFF2E2C22) : c.inkSoft,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: on ? const Color(0x332E2C22) : c.line,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: context.body(
                    size: 8.5,
                    color: on ? const Color(0xFF2E2C22) : c.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loginGate(BuildContext context) {
    final c = context.c;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
      child: Column(
        children: [
          Image.asset(
            'assets/images/logo.webp',
            width: 110,
            cacheWidth: 240,
            opacity: const AlwaysStoppedAnimation(.9),
          ),
          const SizedBox(height: 18),
          Text(
            '登录后开始写你的食谱日记',
            textAlign: TextAlign.center,
            style: context.body(size: 13.5, color: c.ink2, height: 1.8),
          ),
          const SizedBox(height: 6),
          Text(
            '收藏菜谱、记每次下厨的心得，购物清单随账号同步，换设备也不丢。',
            textAlign: TextAlign.center,
            style: context.body(size: 12, color: c.inkSoft, height: 1.7),
          ),
          const SizedBox(height: 22),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width >= 900
                  ? 300
                  : double.infinity,
            ),
            child: Pressable(
              onTap: _openAuth,
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: CitroColors.shadows.note(c),
                ),
                child: Center(
                  child: Text(
                    '登录 / 注册',
                    style: context.body(
                      size: 14.5,
                      weight: FontWeight.w700,
                      color: const Color(0xFF2E2C22),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(BuildContext context) {
    final c = context.c;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('⚠️', style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          Text(
            error ?? '加载失败',
            textAlign: TextAlign.center,
            style: context.body(size: 12, color: c.inkSoft),
          ),
          const SizedBox(height: 12),
          AccentButton(text: '重试', width: 130, height: 40, onTap: _load),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (tab == 'find') return _findView(context);
    if (tab == 'shopping') return _shoppingView(context);
    final src = tab == 'square' ? square : mine;
    final q = search.trim().toLowerCase();
    var list = src.where((r) {
      if (cat.isNotEmpty && !r.tags.contains(cat)) return false;
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) ||
          '${r.cuisine} ${r.dishType}'.toLowerCase().contains(q) ||
          r.tags.join(' ').toLowerCase().contains(q) ||
          r.ingredients.map((e) => e.name).join(' ').contains(q);
    }).toList();
    if (tab == 'recipes') {
      list = _sortWithPins(list);
    }
    return RefreshIndicator(
      color: context.c.accent,
      onRefresh: tab == 'square' ? _ensureSquare : _load,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                Center(child: Text('🍳', style: const TextStyle(fontSize: 40))),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    tab == 'square'
                        ? '广场上还没有公开食谱'
                        : (mine.isEmpty ? '还没有食谱——从第一道拿手菜开始记吧' : '没有匹配的食谱'),
                    textAlign: TextAlign.center,
                    style: context.body(size: 12, color: context.c.inkSoft),
                  ),
                ),
                if (tab == 'recipes' && mine.isEmpty) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: AccentButton(
                      text: '＋ 新建第一个食谱',
                      width: 190,
                      height: 42,
                      onTap: _newRecipe,
                    ),
                  ),
                ],
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final usable = math.max(0.0, constraints.maxWidth - 20);
                final columns = usable >= 1000
                    ? 5
                    : usable >= 760
                    ? 4
                    : usable >= 560
                    ? 3
                    : 2;
                final cardWidth = (usable - (columns - 1) * 10) / columns;
                return GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: cardWidth + 70,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) =>
                      _recipeCard(context, list[i], tab == 'square'),
                );
              },
            ),
    );
  }

  List<Recipe> _sortWithPins(List<Recipe> list) {
    final pinned = _pinned();
    return [...list]..sort((a, b) {
      final pa = pinned.contains(a.id) ? 0 : 1;
      final pb = pinned.contains(b.id) ? 0 : 1;
      if (pa != pb) return pa - pb;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  List<String> _pinned() => PrefsCook.pinned;

  Widget _recipeCard(BuildContext context, Recipe r, bool square) {
    final c = context.c;
    final pinned = _pinned().contains(r.id);
    return Pressable(
      onTap: () => _openDetail(r, square ? 'square' : 'mine'),
      onLongPress: !square && r.mine
          ? () {
              HapticFeedback.mediumImpact();
              _deleteRecipe(r);
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                margin: const EdgeInsets.fromLTRB(7, 7, 7, 0),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.dark
                      ? const Color(0xFF24231D)
                      : const Color(0xFFFCF7E8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.line.withAlpha(160)),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _GridPainter(c.grid)),
                    ),
                    if (r.cover.isEmpty)
                      Center(
                        child: Text(
                          r.emoji.isEmpty ? '🍳' : r.emoji,
                          style: const TextStyle(fontSize: 48),
                        ),
                      ),
                    if (r.cover.isNotEmpty)
                      Positioned.fill(
                        child: AppImage(
                          Api.imageUrl(r.cover),
                          fit: BoxFit.cover,
                          cacheWidth: 540,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: square
                          ? _ownerPill(context, r)
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (r.visibility == 'public'
                                            ? c.hl
                                            : c.surface2)
                                        .withAlpha(240),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: c.line),
                              ),
                              child: Text(
                                r.visibility == 'public' ? '🌐 公开' : '🔒 私密',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.body(
                                  size: 8.5,
                                  color: r.visibility == 'public'
                                      ? c.accentInk
                                      : c.inkSoft,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pinned ? '📌 ' : ''}${r.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.heading(size: 15, color: c.ink),
                  ),
                  const SizedBox(height: 3),
                  if (r.cuisine.isNotEmpty || r.dishType.isNotEmpty)
                    Text(
                      [
                        r.cuisine,
                        r.dishType,
                      ].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(size: 9.5, color: c.inkSoft),
                    ),
                  if (r.calories > 0)
                    Text(
                      '${r.calories} 千卡/100g',
                      style: context.body(
                        size: 9.5,
                        weight: FontWeight.w600,
                        color: c.accentInk,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ownerPill(BuildContext context, Recipe r) {
    final c = context.c;
    final name = (r.owner != null && r.owner!.trim().isNotEmpty)
        ? r.owner!.trim()
        : (_app?.user?.name ?? '匿名');
    final av = r.ownerAv ?? '';
    Widget fallback() => Container(
      color: c.hl,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name[0],
        style: context.body(
          size: 9,
          weight: FontWeight.w700,
          color: c.accentInk,
        ),
      ),
    );
    return Container(
      constraints: const BoxConstraints(maxWidth: 126),
      padding: const EdgeInsets.fromLTRB(3, 2, 8, 2),
      decoration: BoxDecoration(
        color: c.surface2.withAlpha(240),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: SizedBox(
              width: 17,
              height: 17,
              child: av.isNotEmpty
                  ? AppImage(
                      Api.imageUrl(av),
                      fit: BoxFit.cover,
                      cacheWidth: 54,
                      errorBuilder: (_, __, ___) => fallback(),
                    )
                  : fallback(),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(size: 8.8, color: c.ink2),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRecipe(Recipe r) async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('删除《${r.name}》？', style: context.heading(size: 20)),
            const SizedBox(height: 6),
            Text(
              '删除后无法恢复',
              style: context.body(size: 12, color: ctx.c.inkSoft),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '取消',
                    outlined: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AccentButton(
                    text: '删除',
                    danger: true,
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteRecipe(r.id);
      PrefsCook.forget(r.id);
      if (mounted)
        setState(() {
          mine.removeWhere((e) => e.id == r.id);
          square.removeWhere((e) => e.id == r.id);
          if (detail?.id == r.id) detail = null;
        });
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
    }
  }

  Widget _detailView(BuildContext context) {
    final r = detail!;
    final c = context.c;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(r.name, style: context.heading(size: 24, color: c.ink)),
            const SizedBox(height: 6),
            Container(width: 150, height: 8, color: c.hl),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (r.cuisine.isNotEmpty) _pill(context, r.cuisine),
                if (r.dishType.isNotEmpty) _pill(context, r.dishType),
                if (r.calories > 0)
                  _pill(context, '${r.calories} 千卡/100g', color: c.hl),
                if (r.prepMin + r.cookMin > 0)
                  _pill(context, '⏱ ${r.prepMin + r.cookMin} 分钟', color: c.hl),
                if (r.servings > 0) _pill(context, '份量 ${r.servings} 人'),
                for (final t in r.tags)
                  if (t != r.cuisine && t != r.dishType) _pill(context, t),
                _pill(context, '做过 ${r.diary.length} 次'),
              ],
            ),
            if (r.source.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '来源：${r.source}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: 10, color: c.accentInk),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'by ${r.owner ?? _app?.user?.name ?? ''}',
                        style: context.body(size: 10.5, color: c.accentInk),
                      ),
                      Text(
                        _date(r.updatedAt),
                        style: context.body(size: 10, color: c.inkSoft),
                      ),
                    ],
                  ),
                ),
                if (r.mine) ...[
                  _detailAction(
                    context,
                    '编辑',
                    onTap: () async {
                      final saved = await showCookEditor(context, r);
                      if (saved != null && mounted) {
                        saved.mine = true;
                        saved.owner = context.app.user?.name;
                        setState(() {
                          mine.removeWhere((e) => e.id == saved.id);
                          mine.insert(0, saved);
                          detail = saved;
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  _detailAction(
                    context,
                    '删除',
                    danger: true,
                    onTap: () => _deleteRecipe(r),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            DashedLine(color: c.line2),
            const SizedBox(height: 12),
            Row(
              children: [
                _sectionTitle(context, '食材'),
                const Spacer(),
                GestureDetector(
                  onTap: () => _addIngredientsToShopping(r),
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: c.hl,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.accent.withAlpha(110)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          strokeSvg(AppIcons.cart, width: 2),
                          size: 13,
                          color: c.accentInk,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '加入购物清单',
                          style: context.body(
                            size: 10.5,
                            weight: FontWeight.w700,
                            color: c.accentInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ingredients(context, r),
            const SizedBox(height: 14),
            Row(
              children: [
                _sectionTitle(context, '步骤'),
                const Spacer(),
                GestureDetector(
                  onTap: _customTimer,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.line2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          strokeSvg(
                            '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
                            width: 2,
                          ),
                          size: 13,
                          color: c.accentInk,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '自定义计时',
                          style: context.body(
                            size: 10.5,
                            weight: FontWeight.w600,
                            color: c.accentInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (r.steps.isEmpty)
              Text('还没有写步骤', style: context.body(size: 11.5, color: c.inkSoft))
            else
              for (var i = 0; i < r.steps.length; i++) _step(context, r, i),
            if (r.note.isNotEmpty) ...[
              const SizedBox(height: 14),
              _sectionTitle(context, '小记'),
              const SizedBox(height: 5),
              Text(
                r.note,
                style: context.body(size: 14.5, color: c.ink2, height: 1.75),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                _sectionTitle(context, '下厨日记'),
                const SizedBox(width: 6),
                Text(
                  '${r.diary.length} 次',
                  style: context.body(size: 10, color: c.inkSoft),
                ),
                const Spacer(),
                if (r.mine)
                  GestureDetector(
                    onTap: () async {
                      final updated = await showDiaryDialog(context, r);
                      if (updated != null && mounted) {
                        updated.mine = true;
                        updated.owner = context.app.user?.name;
                        setState(() {
                          final idx = mine.indexWhere(
                            (e) => e.id == updated.id,
                          );
                          if (idx >= 0) mine[idx] = updated;
                          detail = updated;
                        });
                      }
                    },
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.hl,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.accent.withAlpha(110)),
                      ),
                      child: Center(
                        child: Text(
                          '＋ 记一笔',
                          style: context.body(
                            size: 11.5,
                            weight: FontWeight.w700,
                            color: c.accentInk,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (r.diary.isEmpty)
              Text(
                '还没有下厨记录，做一次就记一笔吧',
                style: context.body(size: 11, color: c.inkSoft),
              )
            else
              for (final d in r.diary.reversed.take(5)) _diaryTile(context, d),
            const SizedBox(height: 14),
            if (detailSource == 'square' && !r.mine)
              Row(
                children: [
                  Expanded(
                    child: AccentButton(
                      text: '＋ 收藏到我的食谱库',
                      height: 42,
                      onTap: () => _collect(r),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AccentButton(
                      text: '复制文本',
                      height: 42,
                      outlined: true,
                      onTap: () => _copyRecipe(r),
                    ),
                  ),
                ],
              )
            else if (r.mine)
              Row(
                children: [
                  Expanded(
                    child: AccentButton(
                      text: '复制文本',
                      height: 42,
                      outlined: true,
                      onTap: () => _copyRecipe(r),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailAction(
    BuildContext context,
    String label, {
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: danger ? c.stamp.withAlpha(c.dark ? 28 : 16) : c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: danger ? c.stamp.withAlpha(160) : c.line2),
        ),
        child: Text(
          label,
          style: context.body(
            size: 13,
            weight: FontWeight.w700,
            color: danger ? c.stamp : c.accentInk,
          ),
        ),
      ),
    );
  }

  Future<void> _collect(Recipe r) async {
    final copy = Recipe(
      name: r.name,
      emoji: r.emoji,
      tags: List<String>.from(r.tags),
      cuisine: r.cuisine,
      dishType: r.dishType,
      cover: r.cover,
      prepMin: r.prepMin,
      cookMin: r.cookMin,
      calories: r.calories,
      source: r.source,
      servings: r.servings,
      ingredients: r.ingredients
          .map(
            (e) =>
                CookIngredient(name: e.name, amount: e.amount, group: e.group),
          )
          .toList(),
      steps: r.steps
          .map((e) => CookStep(text: e.text, img: e.img, timer: e.timer))
          .toList(),
      note: r.note,
      visibility: 'private',
    );
    try {
      final saved = await Api.saveRecipe(copy);
      saved.mine = true;
      saved.owner = context.app.user?.name;
      if (!mounted) return;
      setState(() {
        mine.insert(0, saved);
        detail = saved;
        detailSource = 'mine';
      });
      AppToast.show(context, '已收藏《${r.name}》到你的食谱库 ✨');
    } catch (e) {
      if (mounted) AppToast.show(context, '$e');
    }
  }

  void _copyRecipe(Recipe r) {
    final b = StringBuffer();
    b.writeln('${r.emoji} ${r.name}');
    final meta = <String>[
      if (r.cuisine.isNotEmpty) '菜系：${r.cuisine}',
      if (r.dishType.isNotEmpty) '类型：${r.dishType}',
      if (r.servings > 0) '分量：${r.servings} 人份',
      if (r.prepMin + r.cookMin > 0) '用时：${r.prepMin + r.cookMin} 分钟',
      if (r.calories > 0) '热量：${r.calories} 千卡/100g',
    ];
    if (meta.isNotEmpty) b.writeln(meta.join(' ｜ '));
    if (r.tags.isNotEmpty) b.writeln('标签：${r.tags.join('、')}');
    if (r.ingredients.isNotEmpty) {
      b.writeln();
      b.writeln('【食材】');
      for (final it in r.ingredients) {
        b.writeln('· ${it.name}${it.amount.isEmpty ? '' : ' ${it.amount}'}');
      }
    }
    if (r.steps.isNotEmpty) {
      b.writeln();
      b.writeln('【步骤】');
      for (var i = 0; i < r.steps.length; i++) {
        final t = r.steps[i].text.split(String.fromCharCode(10)).join(' ');
        b.writeln(
          '${i + 1}. $t${r.steps[i].timer > 0 ? '（约 ${r.steps[i].timer} 分钟）' : ''}',
        );
      }
    }
    if (r.note.isNotEmpty) {
      b.writeln();
      b.writeln('【私房笔记】${r.note}');
    }
    if (r.source.isNotEmpty) {
      b.writeln();
      b.writeln('来源：${r.source}');
    }
    copyText(b.toString(), context: context, tip: '食谱已复制，去分享吧');
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final c = context.c;
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(text, style: context.heading(size: 15, color: c.accentInk)),
      ],
    );
  }

  Widget _pill(BuildContext context, String text, {Color? color}) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line2),
      ),
      child: Text(text, style: context.body(size: 10.5, color: c.ink2)),
    );
  }

  Widget _ingredients(BuildContext context, Recipe r) {
    final c = context.c;
    if (r.ingredients.isEmpty)
      return Text('还没有食材', style: context.body(size: 11.5, color: c.inkSoft));
    final groups = <String, List<CookIngredient>>{};
    for (final it in r.ingredients) {
      final group = it.group == 'season' ? 'season' : 'main';
      groups.putIfAbsent(group, () => []).add(it);
    }
    const names = {'main': '食材', 'season': '调料'};
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final e in groups.entries) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
              color: c.dark ? const Color(0x0DFFFFFF) : const Color(0x0DF2A43C),
              child: Text(
                names[e.key] ?? '主料',
                style: context.body(
                  size: 9.5,
                  weight: FontWeight.w700,
                  color: c.accentInk,
                ),
              ),
            ),
            for (final it in e.value)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line.withAlpha(120))),
                ),
                child: Row(
                  children: [
                    _IngredientCheck(name: it.name),
                    const Spacer(),
                    Text(
                      it.amount,
                      style: context.body(size: 11, color: c.inkSoft),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _step(BuildContext context, Recipe r, int i) {
    final c = context.c;
    final step = r.steps[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: c.accent,
              shape: BoxShape.circle,
              boxShadow: CitroColors.shadows.note(c),
            ),
            child: Center(
              child: Text(
                '${i + 1}',
                style: context.body(
                  size: 10,
                  weight: FontWeight.w700,
                  color: const Color(0xFF2E2C22),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (step.text.isNotEmpty)
                  Text(
                    step.text,
                    style: context.body(
                      size: 14.5,
                      color: c.ink2,
                      height: 1.75,
                    ),
                  ),
                if (step.img.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 88,
                      height: 88,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AppImage(
                          Api.imageUrl(step.img),
                          fit: BoxFit.cover,
                          cacheWidth: 280,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        ),
                      ),
                    ),
                  ),
                ],
                if (step.timer > 0) ...[
                  const SizedBox(height: 5),
                  GestureDetector(
                    onTap: () => CookTimer.instance.start(
                      '${r.name} · 第 ${i + 1} 步',
                      step.timer,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.hl,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.accent.withAlpha(100)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            strokeSvg(
                              '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
                              width: 2,
                            ),
                            size: 11,
                            color: c.accentInk,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '计时 ${step.timer} 分钟',
                            style: context.body(size: 9.5, color: c.accentInk),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _diaryTile(BuildContext context, CookDiary d) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.line.withAlpha(160)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                d.date,
                style: context.display(size: 13, color: c.accentInk),
              ),
              const SizedBox(width: 6),
              Text(
                '${'★' * d.rating}${'☆' * (5 - d.rating)}',
                style: TextStyle(fontSize: 10, color: c.accentInk),
              ),
            ],
          ),
          if (d.tweaks.isNotEmpty)
            Text(
              '改动：${d.tweaks}',
              style: context.body(size: 10.5, color: c.inkSoft),
            ),
          if (d.result.isNotEmpty)
            Text(
              d.result,
              style: context.body(size: 11.5, color: c.ink2, height: 1.6),
            ),
        ],
      ),
    );
  }

  Widget _findView(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.line2),
            ),
            child: Row(
              children: [
                _seg(context, '我的冰箱 ${fridge.length}', 'fridge'),
                _seg(
                  context,
                  '做什么菜${dishSel.isNotEmpty ? ' ${dishSel.length}' : ''}',
                  'dish',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: findView == 'fridge'
              ? _fridgeView(context)
              : _dishView(context),
        ),
      ],
    );
  }

  Widget _seg(BuildContext context, String label, String value) {
    final c = context.c;
    final on = findView == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => findView = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          decoration: BoxDecoration(
            color: on ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: context.body(
                size: 12,
                weight: FontWeight.w700,
                color: on ? const Color(0xFF2E2C22) : c.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dishView(BuildContext context) {
    final c = context.c;
    final matches = _matchDishRecipes();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
      children: [
        Text(
          '告诉我手头有什么，我来找能做的菜。冰箱里有的可以直接点选。',
          style: context.body(size: 11.5, color: c.inkSoft, height: 1.6),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _sectionTitle(context, '已选食材'),
            const SizedBox(width: 6),
            Text(
              '${dishSel.length}',
              style: context.body(size: 10, color: c.inkSoft),
            ),
            const Spacer(),
            if (dishSel.isNotEmpty)
              GestureDetector(
                onTap: () => setState(dishSel.clear),
                child: Text(
                  '清空',
                  style: context.body(size: 10.5, color: c.inkSoft),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (dishSel.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: c.surface2.withAlpha(150),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.line.withAlpha(140)),
            ),
            child: Text(
              '还没选食材 —— 从冰箱挑，或在下面直接手打',
              style: context.body(size: 11, color: c.inkSoft),
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in dishSel)
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 5, 5, 5),
                  decoration: BoxDecoration(
                    color: c.hl,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.accent.withAlpha(110)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: context.body(size: 11, color: c.accentInk),
                      ),
                      const SizedBox(width: 3),
                      GestureDetector(
                        onTap: () => setState(() => dishSel.remove(name)),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: AppIcon(
                            strokeSvg(AppIcons.close, width: 2.2),
                            size: 11,
                            color: c.accentInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            GestureDetector(
              onTap: _pickDishFromLibrary,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.line2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      strokeSvg(AppIcons.book, width: 1.8),
                      size: 14,
                      color: c.accentInk,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '食材库',
                      style: context.body(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: c.accentInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('可多选，选完直接匹配', style: context.body(size: 10, color: c.inkSoft)),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle(context, '从冰箱选'),
        const SizedBox(height: 6),
        if (fridge.isEmpty)
          Text(
            '冰箱还是空的，先去「我的冰箱」加几样食材',
            style: context.body(size: 11, color: c.inkSoft),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final it in fridge)
                GestureDetector(
                  onTap: () => setState(() {
                    if (dishSel.contains(it.name)) {
                      dishSel.remove(it.name);
                    } else {
                      dishSel.add(it.name);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: dishSel.contains(it.name) ? c.accent : c.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: dishSel.contains(it.name) ? c.accent : c.line2,
                      ),
                    ),
                    child: Text(
                      it.name,
                      style: context.body(
                        size: 11,
                        weight: FontWeight.w600,
                        color: dishSel.contains(it.name)
                            ? const Color(0xFF2E2C22)
                            : c.ink2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.line2),
                ),
                child: TextField(
                  controller: findInput,
                  onSubmitted: (_) => _addDishInput(),
                  style: context.body(size: 12),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: '直接手打，如：剩米饭',
                    hintStyle: context.body(size: 11.5, color: c.inkSoft),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _addDishInput,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  child: Text(
                    '加入',
                    style: context.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: const Color(0xFF2E2C22),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (dishSel.isNotEmpty) ...[
          Row(
            children: [
              _sectionTitle(context, '可以做的菜'),
              const Spacer(),
              Text('按匹配度排序', style: context.body(size: 9.5, color: c.inkSoft)),
            ],
          ),
          const SizedBox(height: 8),
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '没找到匹配的食谱——食谱里的食材写详细点，或者换几样试试',
                textAlign: TextAlign.center,
                style: context.body(size: 11.5, color: c.inkSoft),
              ),
            )
          else
            for (final m in matches.take(30)) _dishResult(context, m),
        ],
      ],
    );
  }

  void _addDishInput() {
    final name = findInput.text.trim();
    if (name.isEmpty) return;
    if (dishSel.any((e) => e == name)) {
      AppToast.show(context, '已经在列表里了');
      return;
    }
    setState(() => dishSel.add(name));
    findInput.clear();
  }

  Future<void> _pickDishFromLibrary() async {
    FocusScope.of(context).unfocus();
    final picked = await showIngredientLibrary(
      context,
      title: '从食材库选',
      selected: dishSel,
    );
    if (picked == null || !mounted) return;
    var added = 0;
    setState(() {
      for (final name in picked) {
        if (dishSel.any((e) => _sameIng(e, name))) continue;
        dishSel.add(name);
        added++;
      }
    });
    if (added == 0) AppToast.show(context, '这些食材已经选过了');
  }

  String _normIng(String name) =>
      name.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[（）()]'), '');

  bool _sameIng(String a, String b) {
    final x = _normIng(a);
    final y = _normIng(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    if (x.length >= 2 && y.length >= 2 && (x.contains(y) || y.contains(x)))
      return true;
    return false;
  }

  List<_DishMatch> _matchDishRecipes() {
    if (dishSel.isEmpty) return [];
    final all = <({Recipe r, bool mine})>[];
    for (final r in mine) {
      all.add((r: r, mine: true));
    }
    for (final r in square) {
      if (!mine.any((m) => m.id == r.id)) all.add((r: r, mine: false));
    }
    final out = <_DishMatch>[];
    for (final item in all) {
      final groups = <String, List<CookIngredient>>{};
      for (final ing in item.r.ingredients) {
        final group = switch (ing.group) {
          'aux' => 'aux',
          'season' => 'season',
          _ => 'main',
        };
        groups.putIfAbsent(group, () => []).add(ing);
      }
      int? hitOf(String group, List<String> miss) {
        final list = groups[group];
        if (list == null || list.isEmpty) return null;
        var hit = 0;
        for (final ing in list) {
          if (dishSel.any((n) => _sameIng(n, ing.name))) {
            hit++;
          } else {
            miss.add(ing.name);
          }
        }
        return hit;
      }

      final mainMiss = <String>[];
      final auxMiss = <String>[];
      final seasonMiss = <String>[];
      final mainHit = hitOf('main', mainMiss) ?? 0;
      final auxHit = hitOf('aux', auxMiss) ?? 0;
      final seasonHit = hitOf('season', seasonMiss) ?? 0;
      final mainTotal = groups['main']?.length ?? 0;
      final auxTotal = groups['aux']?.length ?? 0;
      final seasonTotal = groups['season']?.length ?? 0;
      if (mainHit + auxHit + seasonHit == 0) continue;
      var weight = 0.0;
      var score = 0.0;
      if (mainTotal > 0) {
        score += .70 * mainHit / mainTotal;
        weight += .70;
      }
      if (auxTotal > 0) {
        score += .18 * auxHit / auxTotal;
        weight += .18;
      }
      if (seasonTotal > 0) {
        score += .12 * seasonHit / seasonTotal;
        weight += .12;
      }
      final fullMain = mainTotal > 0 && mainHit == mainTotal;
      out.add(
        _DishMatch(
          recipe: item.r,
          mine: item.mine,
          mainHit: mainHit,
          mainTotal: mainTotal,
          score: weight > 0 ? score / weight : 0,
          missing: [...mainMiss, ...auxMiss, ...seasonMiss],
          fullMain: fullMain,
        ),
      );
    }
    out.sort((a, b) {
      if (a.fullMain != b.fullMain) return a.fullMain ? -1 : 1;
      final am = a.mainTotal - a.mainHit;
      final bm = b.mainTotal - b.mainHit;
      if (am != bm) return am.compareTo(bm);
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      return b.recipe.updatedAt.compareTo(a.recipe.updatedAt);
    });
    return out;
  }

  Widget _dishResult(BuildContext context, _DishMatch m) {
    final c = context.c;
    final r = m.recipe;
    return GestureDetector(
      onTap: () => _openDetail(r, m.mine ? 'mine' : 'square'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 54,
                height: 54,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: c.dark
                          ? const Color(0xFF24231D)
                          : const Color(0xFFFCF7E8),
                      child: Center(
                        child: Text(
                          r.emoji.isEmpty ? '🍳' : r.emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
                    if (r.cover.isNotEmpty)
                      AppImage(
                        Api.imageUrl(r.cover),
                        fit: BoxFit.cover,
                        cacheWidth: 180,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.heading(size: 14, color: c.ink),
                        ),
                      ),
                      if (m.fullMain) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: c.mintSoft,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: c.mintLine),
                          ),
                          child: Text(
                            '食材齐了',
                            style: context.body(
                              size: 8,
                              weight: FontWeight.w700,
                              color: c.mintInk,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${m.mine ? '我的食谱' : '🌐 ${r.owner ?? '广场'}'} · 食材 ${m.mainHit}/${m.mainTotal}',
                    style: context.body(size: 9.5, color: c.inkSoft),
                  ),
                  if (m.missing.isNotEmpty)
                    Text(
                      '还缺 ${m.missing.length} 样：${m.missing.take(5).join('、')}${m.missing.length > 5 ? '…' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(size: 9.5, color: c.stamp),
                    ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: m.score.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: c.line,
                      valueColor: AlwaysStoppedAnimation(c.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fridgeView(BuildContext context) {
    final c = context.c;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
          children: [
            if (fridge.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 50),
                child: Column(
                  children: [
                    const Text('🧊', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text(
                      '冰箱还是空的，先加几样食材吧',
                      style: context.body(size: 12, color: c.inkSoft),
                    ),
                  ],
                ),
              )
            else
              for (final it in fridge)
                Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    children: [
                      const Text('🥬', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.name,
                              style: context.body(
                                size: 12.5,
                                weight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                            Text(
                              '${it.qty} ${it.unit}${it.expDate.isNotEmpty ? ' · 到期 ${it.expDate}' : ''}',
                              style: context.body(
                                size: 9.5,
                                color:
                                    it.expDate.isNotEmpty &&
                                        it.expDate.compareTo(_today()) < 0
                                    ? c.stamp
                                    : c.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final edited = await showFridgeDialog(context, it);
                          if (edited != null && mounted) {
                            setState(() {
                              if (it.id.isEmpty) {
                                fridge.add(edited);
                              } else {
                                final idx = fridge.indexWhere(
                                  (e) => e.id == it.id,
                                );
                                if (idx >= 0) fridge[idx] = edited;
                              }
                            });
                            _saveFridge();
                          }
                        },
                        child: Text(
                          '编辑',
                          style: context.body(size: 10, color: c.accentInk),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() => fridge.remove(it));
                          _saveFridge();
                        },
                        child: Text(
                          '删除',
                          style: context.body(size: 10, color: c.stamp),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 78,
          child: GestureDetector(
            onTap: () async {
              final item = await showFridgeDialog(context, null);
              if (item != null && mounted) {
                setState(() => fridge.add(item));
                _saveFridge();
              }
            },
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
                boxShadow: CitroColors.shadows.lg(c),
              ),
              child: Center(
                child: AppIcon(
                  strokeSvg(AppIcons.plus, width: 2.4),
                  size: 20,
                  color: const Color(0xFF2E2C22),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _shoppingView(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            children: [
              for (final it in shopping)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() => it.done = !it.done);
                          _saveShopping();
                        },
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: it.done ? c.accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: it.done ? c.accent : c.line2,
                            ),
                          ),
                          child: it.done
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Color(0xFF2E2C22),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          it.text,
                          style: context
                              .body(
                                size: 12.5,
                                color: it.done ? c.inkSoft : c.ink,
                                height: 1.5,
                              )
                              .copyWith(
                                decoration: it.done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() => shopping.remove(it));
                          _saveShopping();
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c.stamp.withAlpha(c.dark ? 28 : 16),
                            shape: BoxShape.circle,
                            border: Border.all(color: c.stamp.withAlpha(150)),
                          ),
                          child: Center(
                            child: AppIcon(
                              strokeSvg(AppIcons.close, width: 2.2),
                              size: 15,
                              color: c.stamp,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (shopping.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 50),
                  child: Column(
                    children: [
                      const Text('🛒', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 8),
                      Text(
                        '清单是空的，加一点要买的',
                        style: context.body(size: 12, color: c.inkSoft),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.line2),
                  ),
                  child: TextField(
                    controller: shoppingInput,
                    onSubmitted: (_) => _addShopping(),
                    style: context.body(size: 12.5),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: '添加要买的东西…',
                      hintStyle: context.body(size: 12, color: c.inkSoft),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _addShopping,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                    boxShadow: CitroColors.shadows.note(c),
                  ),
                  child: Center(
                    child: AppIcon(
                      strokeSvg(AppIcons.plus, width: 2.2),
                      size: 18,
                      color: const Color(0xFF2E2C22),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _addShopping() {
    final t = shoppingInput.text.trim();
    if (t.isEmpty) return;
    setState(() {
      shopping.add(ShoppingItem(text: t));
      shoppingInput.clear();
    });
    _saveShopping();
  }

  Widget _bottomNav(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
        boxShadow: [
          BoxShadow(
            color: c.ink.withAlpha(20),
            blurRadius: 18,
            spreadRadius: -8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final it in _navItems)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _switchTab(it.$1),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: it.$1 == 'food'
                            ? (foodActive ? c.mint : c.mintSoft.withAlpha(170))
                            : (tab == it.$1 ? c.hl : Colors.transparent),
                        borderRadius: BorderRadius.circular(10),
                        border: it.$1 == 'food'
                            ? Border.all(color: c.mintLine)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppIcon(
                            strokeSvg(it.$3, width: 2),
                            size: it.$1 == 'food' ? 19 : 18,
                            color: it.$1 == 'food'
                                ? c.mintInk
                                : (tab == it.$1 ? c.accentInk : c.inkSoft),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            it.$2,
                            style: context.body(
                              size: 9.5,
                              weight: FontWeight.w700,
                              color: it.$1 == 'food'
                                  ? c.mintInk
                                  : (tab == it.$1 ? c.accentInk : c.inkSoft),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _date(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }
}

class _DishMatch {
  final Recipe recipe;
  final bool mine;
  final int mainHit;
  final int mainTotal;
  final double score;
  final List<String> missing;
  final bool fullMain;
  const _DishMatch({
    required this.recipe,
    required this.mine,
    required this.mainHit,
    required this.mainTotal,
    required this.score,
    required this.missing,
    required this.fullMain,
  });
}

class _IngredientCheck extends StatefulWidget {
  final String name;
  const _IngredientCheck({required this.name});
  @override
  State<_IngredientCheck> createState() => _IngredientCheckState();
}

class _IngredientCheckState extends State<_IngredientCheck> {
  bool checked = false;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () => setState(() => checked = !checked),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: checked ? c.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: checked ? c.accent : c.line2),
            ),
            child: checked
                ? const Icon(Icons.check, size: 11, color: Color(0xFF2E2C22))
                : null,
          ),
          const SizedBox(width: 7),
          Text(
            widget.name,
            style: context.body(size: 12, color: checked ? c.inkSoft : c.ink2),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = .6;
    for (var y = 12.0; y < size.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    for (var x = 12.0; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PrefsCook {
  static List<String> get pinned {
    final raw = Prefs.getString('citro_cook_pinned');
    return raw == null
        ? []
        : raw.split(',').where((e) => e.isNotEmpty).toList();
  }

  static void togglePin(String id) {
    final list = pinned;
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.insert(0, id);
    }
    Prefs.setString('citro_cook_pinned', list.join(','));
  }

  static void forget(String id) {
    final list = pinned..remove(id);
    Prefs.setString('citro_cook_pinned', list.join(','));
  }
}
