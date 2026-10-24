import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../services/api.dart';
import '../services/media.dart';
import '../services/models.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'ingredient_library.dart';

Future<Recipe?> showCookEditor(BuildContext context, Recipe? initial) async {
  return showModalBottomSheet<Recipe>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CookEditor(initial: initial),
  );
}

const _cookUnits = [
  '个',
  '克',
  '斤',
  '盎司',
  '磅',
  '毫升',
  '茶匙',
  '汤匙',
  '瓣',
  '片',
  '颗',
  '根',
  '张',
  '块',
  '罐',
  '一小把',
  '少许',
  '少量',
  '适量',
];
const _freeAmountUnits = {'一小把', '少许', '少量', '适量'};

class _IngRow {
  String group;
  final name = TextEditingController();
  final qty = TextEditingController();
  String unit;

  _IngRow({
    this.group = 'main',
    String n = '',
    String q = '1',
    this.unit = '克',
  }) {
    name.text = n;
    qty.text = q;
  }

  bool get noQty => unit.isEmpty || _freeAmountUnits.contains(unit);
  bool get custom => unit == '自定义';
  String get unitLabel => unit.isEmpty ? '不用单位' : unit;

  String get amount {
    if (custom) return qty.text.trim();
    if (unit.isEmpty) return '';
    if (_freeAmountUnits.contains(unit)) return unit;
    final value = qty.text.trim();
    return value.isEmpty ? '' : '$value$unit';
  }

  factory _IngRow.fromAmount(String group, String name, String amount) {
    final raw = amount.trim();
    if (raw.isEmpty) return _IngRow(group: group, n: name, q: '', unit: '克');
    if (raw == '不用单位') return _IngRow(group: group, n: name, q: '', unit: '');
    if (_freeAmountUnits.contains(raw))
      return _IngRow(group: group, n: name, q: '', unit: raw);
    final units = _cookUnits.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final u in units) {
      if (raw.length > u.length && raw.endsWith(u)) {
        final head = raw.substring(0, raw.length - u.length).trim();
        if (head.isNotEmpty)
          return _IngRow(group: group, n: name, q: head, unit: u);
      }
    }
    return _IngRow(group: group, n: name, q: raw, unit: '自定义');
  }

  void dispose() {
    name.dispose();
    qty.dispose();
  }
}

class _QtyStepper extends StatelessWidget {
  static const _min = 0.5;
  static const _max = 99999.0;

  final TextEditingController controller;
  final bool textInput;

  const _QtyStepper({required this.controller, this.textInput = false});

  void _bump(double delta) {
    final current = double.tryParse(controller.text.trim());
    var next = current == null ? _min : current + delta;
    if (!next.isFinite) next = _min;
    if (next < _min) next = _min;
    if (next > _max) next = _max;
    var text = next == next.roundToDouble()
        ? next.toInt().toString()
        : next.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    }
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.line2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(c, AppIcons.minus, () => _bump(-0.5)),
          Container(width: 1, height: 20, color: c.line.withAlpha(150)),
          Center(
            child: SizedBox(
              width: 56,
              height: 22,
              child: TextField(
                controller: controller,
                textAlign: TextAlign.center,
                keyboardType: textInput
                    ? TextInputType.text
                    : const TextInputType.numberWithOptions(decimal: true),
                style: context.body(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: c.ink,
                ),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          Container(width: 1, height: 20, color: c.line.withAlpha(150)),
          _button(c, AppIcons.plus, () => _bump(0.5)),
        ],
      ),
    );
  }

  Widget _button(CitroColors c, String icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 38,
        child: Center(
          child: AppIcon(
            strokeSvg(icon, width: 2.4),
            size: 14,
            color: c.accentInk,
          ),
        ),
      ),
    );
  }
}

class _StepRow {
  final text = TextEditingController();
  final timer = TextEditingController();
  String img;
  _StepRow({String t = '', int tm = 0, this.img = ''}) {
    text.text = t;
    if (tm > 0) timer.text = '$tm';
  }
  void dispose() {
    text.dispose();
    timer.dispose();
  }
}

class _CookEditor extends StatefulWidget {
  final Recipe? initial;
  const _CookEditor({this.initial});
  @override
  State<_CookEditor> createState() => _CookEditorState();
}

class _CookEditorState extends State<_CookEditor> {
  static const _cuisines = [
    '中式',
    '意式',
    '日式',
    '韩式',
    '泰式',
    '墨西哥菜',
    '美式',
    '法式',
    '西班牙菜',
    '印度菜',
    '希腊菜',
    '越南菜',
    '地中海菜',
    '中东菜',
    '土耳其菜',
    '英式',
    '德式',
    '巴西菜',
    '加勒比菜',
  ];
  static const _dishTypes = [
    '凉菜',
    '早餐',
    '面食',
    '米饭',
    '主菜',
    '肉类',
    '海鲜',
    '素菜',
    '沙拉',
    '配菜',
    '蘸酱与酱汁',
    '汤类',
    '小吃',
    '烘焙',
    '甜点',
    '饮品',
    '其他',
  ];

  late final TextEditingController name;
  late final TextEditingController tags;
  late final TextEditingController calories;
  late final TextEditingController source;
  late final TextEditingController note;
  String emoji = '🍳';
  String cuisine = '';
  String dishType = '';
  bool visibilityPublic = false;
  String cover = '';
  int prepMin = 0;
  int cookMin = 0;
  int servingsValue = 2;
  List<_IngRow> ingredients = [];
  List<_StepRow> steps = [];
  int step = 1;
  bool saving = false;
  String? error;
  Uint8List? coverPreview;
  final ScrollController _scroll = ScrollController();
  late String _initialSig;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    name = TextEditingController(text: r?.name ?? '');
    tags = TextEditingController(text: _customTags(r).join('，'));
    servingsValue = (r?.servings ?? 0) > 0 ? r!.servings : 2;
    calories = TextEditingController(
      text: (r?.calories ?? 0) > 0 ? '${r!.calories}' : '',
    );
    source = TextEditingController(text: r?.source ?? '');
    note = TextEditingController(text: r?.note ?? '');
    emoji = r?.emoji ?? '🍳';
    cuisine = r?.cuisine ?? '';
    dishType = r?.dishType ?? '';
    visibilityPublic = r?.visibility == 'public';
    cover = r?.cover ?? '';
    prepMin = r?.prepMin ?? 0;
    cookMin = r?.cookMin ?? 0;
    ingredients = (r?.ingredients ?? [])
        .map(
          (e) => _IngRow.fromAmount(
            e.group == 'season' ? 'season' : 'main',
            e.name,
            e.amount,
          ),
        )
        .toList();
    for (final group in ['main', 'season']) {
      if (!ingredients.any((e) => e.group == group))
        ingredients.add(_IngRow(group: group));
    }
    steps = (r?.steps ?? [])
        .map((e) => _StepRow(t: e.text, tm: e.timer, img: e.img))
        .toList();
    if (steps.isEmpty) steps.add(_StepRow());
    _initialSig = _signature();
  }

  List<String> _customTags(Recipe? r) {
    if (r == null) return [];
    return r.tags.where((t) => t != r.cuisine && t != r.dishType).toList();
  }

  String _signature() => [
    name.text,
    cuisine,
    dishType,
    '$servingsValue',
    calories.text,
    source.text,
    note.text,
    tags.text,
    cover,
    visibilityPublic ? 'public' : 'private',
    '$prepMin',
    '$cookMin',
    for (final r in ingredients) '${r.group}|${r.name.text}|${r.amount}',
    for (final s in steps) '${s.text.text}|${s.img}|${s.timer.text}',
  ].join('\u0001');

  bool get _dirty => _signature() != _initialSig;

  @override
  void dispose() {
    name.dispose();
    tags.dispose();
    calories.dispose();
    source.dispose();
    note.dispose();
    _scroll.dispose();
    for (final e in ingredients) {
      e.dispose();
    }
    for (final e in steps) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCover() async {
    try {
      final bytes = await MediaService.pickImageBytes(
        maxWidth: 2400,
        quality: 92,
      );
      if (bytes == null || !mounted) return;
      final cropped = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CoverCropDialog(bytes: bytes),
      );
      if (cropped == null || !mounted) return;
      final compressed = await MediaService.compressCookImage(
        cropped,
        maxDim: 1200,
        quality: 82,
      );
      if (!mounted) return;
      final url = await Api.uploadCookImage(MediaService.dataUrl(compressed));
      if (!mounted) return;
      setState(() {
        cover = url;
        coverPreview = compressed;
      });
    } catch (e) {
      if (mounted) AppToast.show(context, '封面上传失败');
    }
  }

  Future<void> _pickStepImage(int i, {bool camera = false}) async {
    try {
      final bytes = await MediaService.pickImageBytes(
        camera: camera,
        maxWidth: 2400,
        quality: 92,
      );
      if (bytes == null || !mounted) return;
      final compressed = await MediaService.compressCookImage(
        bytes,
        maxDim: 1600,
        quality: 82,
      );
      if (!mounted) return;
      final url = await Api.uploadCookImage(MediaService.dataUrl(compressed));
      if (!mounted) return;
      setState(() => steps[i].img = url);
    } catch (e) {
      if (mounted) AppToast.show(context, '步骤图上传失败');
    }
  }

  Future<int?> _pickMinutes(String title, int initial, {int max = 300}) async {
    var current = initial.clamp(0, max).toInt();
    final controller = FixedExtentScrollController(initialItem: current);
    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.c;
        return Container(
          height: 306,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: c.line),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                  child: Row(
                    children: [
                      Text(title, style: ctx.heading(size: 17)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '取消',
                            style: ctx.body(size: 12, color: c.inkSoft),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx, current),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '确定',
                            style: ctx.body(
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: c.accentInk,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 40,
                    scrollController: controller,
                    onSelectedItemChanged: (i) => current = i,
                    children: [
                      for (var m = 0; m <= max; m++)
                        Center(
                          child: Text(
                            m == 0 ? '不设置' : '$m 分钟',
                            style: ctx.body(
                              size: 15,
                              weight: m == current
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: m == current ? c.accentInk : c.ink2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return result;
  }

  bool _validate(int n) {
    if (n == 1) {
      if (name.text.trim().isEmpty) return _fail('先给这道菜起个名字');
      if (cuisine.isEmpty) return _fail('选一个菜系');
      if (dishType.isEmpty) return _fail('选一个菜品类型');
      if (servingsValue <= 0) return _fail('选一下几人份');
      if (cover.isEmpty) return _fail('先上传一张封面');
      return true;
    }
    if (n == 2) {
      if (!ingredients.any(
        (e) => e.group == 'main' && e.name.text.trim().isNotEmpty,
      ))
        return _fail('主料至少写一样');
      if (!ingredients.any(
        (e) => e.group == 'season' && e.name.text.trim().isNotEmpty,
      ))
        return _fail('调料至少写一样');
      return true;
    }
    if (n == 3) {
      if (!steps.any((e) => e.text.text.trim().isNotEmpty || e.img.isNotEmpty))
        return _fail('至少写一步怎么做');
    }
    return true;
  }

  bool _fail(String message) {
    if (mounted) {
      setState(() => error = message);
      AppToast.show(context, message);
    }
    return false;
  }

  void _goStep(int n) {
    setState(() {
      step = n.clamp(1, 4);
      error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _next() {
    if (!_validate(step)) return;
    _goStep(step + 1);
  }

  Future<void> _save() async {
    if (saving) return;
    if (!_validate(1)) {
      _goStep(1);
      return;
    }
    if (!_validate(2)) {
      _goStep(2);
      return;
    }
    if (!_validate(3)) {
      _goStep(3);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final r = widget.initial ?? Recipe();
    r.name = name.text.trim();
    r.emoji = emoji;
    r.cuisine = cuisine;
    r.dishType = dishType;
    r.visibility = visibilityPublic ? 'public' : 'private';
    r.cover = cover;
    r.prepMin = prepMin;
    r.cookMin = cookMin;
    r.servings = servingsValue;
    r.calories = int.tryParse(calories.text.trim()) ?? 0;
    r.source = source.text.trim();
    r.note = note.text.trim();
    final custom = tags.text
        .split(RegExp(r'[,，]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    r.tags = <String>{
      cuisine,
      dishType,
      ...custom,
    }.where((e) => e.isNotEmpty).toList();
    r.ingredients = [
      for (final e in ingredients)
        if (e.name.text.trim().isNotEmpty)
          CookIngredient(
            name: e.name.text.trim(),
            amount: e.amount,
            group: e.group,
          ),
    ];
    r.steps = [
      for (final e in steps)
        if (e.text.text.trim().isNotEmpty || e.img.isNotEmpty)
          CookStep(
            text: e.text.text.trim(),
            img: e.img,
            timer: int.tryParse(e.timer.text.trim()) ?? 0,
          ),
    ];
    try {
      final saved = await Api.saveRecipe(r);
      if (!mounted) return;
      AppToast.show(context, '食谱已保存');
      Navigator.of(context).pop(saved);
    } on Exception catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _tryClose() async {
    if (saving) return;
    if (!_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final discard = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('还没保存', style: ctx.heading(size: 20)),
            const SizedBox(height: 6),
            Text(
              '关闭会丢掉刚写的内容，确定要放弃吗？',
              textAlign: TextAlign.center,
              style: ctx.body(size: 12, color: ctx.c.inkSoft, height: 1.6),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '继续写',
                    outlined: true,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AccentButton(
                    text: '放弃',
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  double _dragDy = 0;
  bool _dragging = false;

  void _dragStart(DragStartDetails _) => setState(() => _dragging = true);

  void _dragUpdate(DragUpdateDetails d) {
    setState(() => _dragDy = math.max(0, _dragDy + d.delta.dy));
  }

  void _dragEnd(DragEndDetails d) {
    final close = _dragDy > 92 || d.velocity.pixelsPerSecond.dy > 720;
    setState(() {
      _dragging = false;
      _dragDy = 0;
    });
    if (close) _tryClose();
  }

  void _dragCancel() => setState(() {
    _dragging = false;
    _dragDy = 0;
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final height =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final sheetHeight = height * .96;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tryClose();
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: AnimatedSlide(
          offset: Offset(0, sheetHeight <= 0 ? 0 : _dragDy / sheetHeight),
          duration: _dragging
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: Container(
            height: sheetHeight,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              border: Border.all(color: c.line),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: _dragStart,
                    onVerticalDragUpdate: _dragUpdate,
                    onVerticalDragEnd: _dragEnd,
                    onVerticalDragCancel: _dragCancel,
                    child: Column(
                      children: [
                        Container(
                          width: 46,
                          height: 5,
                          margin: const EdgeInsets.only(top: 7),
                          decoration: BoxDecoration(
                            color: c.line2,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 3, 10, 4),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: _tryClose,
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: c.surface2,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: c.line2),
                                  ),
                                  child: Center(
                                    child: AppIcon(
                                      strokeSvg(AppIcons.close, width: 2.2),
                                      size: 22,
                                      color: c.inkSoft,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Text(
                                widget.initial == null ? '新建食谱' : '编辑食谱',
                                style: context.heading(size: 20),
                              ),
                              const Spacer(),
                              Text(
                                '第 $step / 4 步',
                                style: context.body(
                                  size: 10.5,
                                  color: c.inkSoft,
                                ),
                              ),
                              const SizedBox(width: 2),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _stepChips(c),
                  const SizedBox(height: 4),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                          key: ValueKey(step),
                          child: _panel(c),
                        ),
                      ),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                      child: Text(
                        error!,
                        style: context.body(size: 11, color: c.stamp),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    ),
                    child: Row(
                      children: [
                        if (step > 1) ...[
                          Expanded(
                            child: AccentButton(
                              text: '上一步',
                              outlined: true,
                              height: 44,
                              onTap: () => _goStep(step - 1),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          flex: 2,
                          child: AccentButton(
                            text: step == 4
                                ? (widget.initial == null
                                      ? '✓ 完成，创建食谱'
                                      : '保存修改')
                                : '下一步 →',
                            height: 44,
                            loading: saving,
                            onTap: step == 4 ? _save : _next,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepChips(CitroColors c) {
    const labels = ['菜品', '食材', '步骤', '笔记'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.dark ? const Color(0x12FFFFFF) : const Color(0x0D23211C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line.withAlpha(150)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => _goStep(i + 1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 38,
                    decoration: BoxDecoration(
                      color: step == i + 1 ? c.surface2 : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: step == i + 1
                          ? CitroColors.shadows.paper(c)
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: i + 1 < step
                                ? c.accent
                                : (step == i + 1 ? c.hl : c.surface),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: step == i + 1 ? c.accent : c.line2,
                            ),
                          ),
                          child: Center(
                            child: i + 1 < step
                                ? const Icon(
                                    Icons.check,
                                    size: 12,
                                    color: Color(0xFF2E2C22),
                                  )
                                : Text(
                                    '${i + 1}',
                                    style: context.body(
                                      size: 9,
                                      weight: FontWeight.w700,
                                      color: step == i + 1
                                          ? c.accentInk
                                          : c.inkSoft,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          labels[i],
                          style: context.body(
                            size: 11.5,
                            weight: FontWeight.w700,
                            color: step == i + 1 ? c.accentInk : c.inkSoft,
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
    );
  }

  Widget _panel(CitroColors c) {
    if (step == 1) return _stepInfo(c);
    if (step == 2) return _stepIngredients(c);
    if (step == 3) return _stepSteps(c);
    return _stepNote(c);
  }

  Widget _panelHead(CitroColors c, String title, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.heading(size: 17, color: c.ink)),
        const SizedBox(height: 3),
        Text(
          desc,
          style: context.body(size: 11, color: c.inkSoft, height: 1.6),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _stepInfo(CitroColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHead(c, '这道菜是什么？', '封面、菜名、菜系、类型和分量是它的身份证；带 * 的必须填。'),
        _label(c, '封面', required: true),
        Center(child: _coverPicker(c)),
        const SizedBox(height: 5),
        Text(
          cover.isEmpty ? '封面必填 · 选图后可自由拖动、缩放裁成 1:1' : '点击封面可重新选图、裁切',
          textAlign: TextAlign.center,
          style: context.body(
            size: 9.5,
            color: cover.isEmpty ? c.stamp : c.inkSoft,
          ),
        ),
        const SizedBox(height: 12),
        _label(c, '菜名', required: true),
        _field(name, '例如：番茄牛腩', maxLength: 40),
        const SizedBox(height: 12),
        _label(c, '来源链接（选填）'),
        _field(source, '菜谱出处网址'),
        const SizedBox(height: 12),
        _label(c, '菜系', required: true),
        _chips(c, _cuisines, cuisine, (v) => setState(() => cuisine = v)),
        const SizedBox(height: 12),
        _label(c, '菜品类型', required: true),
        _chips(c, _dishTypes, dishType, (v) => setState(() => dishType = v)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_label(c, '分量', required: true), _servingsField(c)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(c, '热量（千卡 / 100g，选填）'),
                  _field(calories, '如：120', numeric: true),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _label(c, '用时（选填）'),
        Row(
          children: [
            Expanded(
              child: _timeBtn(c, '准备时间', prepMin, () async {
                final v = await _pickMinutes('准备要多久？', prepMin, max: 300);
                if (v != null) setState(() => prepMin = v);
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _timeBtn(c, '烹饪时间', cookMin, () async {
                final v = await _pickMinutes('烹饪要多久？', cookMin, max: 600);
                if (v != null) setState(() => cookMin = v);
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _coverPicker(CitroColors c) {
    final hasCover = cover.isNotEmpty || coverPreview != null;
    return GestureDetector(
      onTap: _pickCover,
      child: Container(
        width: 128,
        height: 128,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasCover ? c.line2 : c.accent.withAlpha(150),
          ),
          image: coverPreview != null
              ? DecorationImage(
                  image: ResizeImage(MemoryImage(coverPreview!), width: 384),
                  fit: BoxFit.cover,
                )
              : (cover.isNotEmpty
                    ? DecorationImage(
                        image: ResizeImage(
                          NetworkImage(Api.imageUrl(cover)),
                          width: 384,
                        ),
                        fit: BoxFit.cover,
                      )
                    : null),
        ),
        child: hasCover
            ? Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: c.ink.withAlpha(140),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(13),
                    ),
                  ),
                  child: Text(
                    '换封面',
                    textAlign: TextAlign.center,
                    style: context.body(size: 9.5, color: Colors.white),
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.camera, width: 1.8),
                    size: 28,
                    color: c.accentInk,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '上传封面 *',
                    style: context.body(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: c.accentInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '裁成 1:1',
                    style: context.body(size: 8.5, color: c.inkSoft),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _servingsField(CitroColors c) {
    return GestureDetector(
      onTap: _pickServings,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.line2),
        ),
        child: Row(
          children: [
            Text(
              '${servingsValue} 人份',
              style: context.body(size: 12.5, color: c.ink),
            ),
            const Spacer(),
            AppIcon(
              strokeSvg(AppIcons.chevronDown, width: 2),
              size: 12,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickServings() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.c;
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: c.line),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text('几人份', style: ctx.heading(size: 19)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 1; i <= 12; i++)
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx, i),
                        child: Container(
                          width: 52,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: servingsValue == i ? c.accent : c.surface2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: servingsValue == i ? c.accent : c.line2,
                            ),
                          ),
                          child: Text(
                            '$i',
                            style: ctx.body(
                              size: 14,
                              weight: FontWeight.w700,
                              color: servingsValue == i
                                  ? const Color(0xFF2E2C22)
                                  : c.ink2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) setState(() => servingsValue = picked);
  }

  Widget _stepIngredients(CitroColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHead(c, '食材和调料', '主料和辅料合并为食材；先填数量，再选单位。'),
        _ingredientGroup(c, 'main', '食材', required: true, hint: '主料 + 辅料'),
        const SizedBox(height: 16),
        _ingredientGroup(c, 'season', '调料', required: true, hint: '盐糖酱醋油…'),
      ],
    );
  }

  Future<void> _openLibrary(String group) async {
    final names = ingredients
        .where((e) => e.group == group)
        .map((e) => e.name.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final picked = await showIngredientLibrary(
      context,
      title: '从食材库选',
      selected: names,
    );
    if (picked == null || !mounted || picked.isEmpty) return;
    var added = 0;
    setState(() {
      final existing = names.toSet();
      final fresh = picked.where((n) => !existing.contains(n)).toList();
      if (fresh.isEmpty) return;
      final empties = ingredients
          .where((e) => e.group == group && e.name.text.trim().isEmpty)
          .toList();
      for (final row in empties) {
        if (fresh.isEmpty) break;
        row.name.text = fresh.removeAt(0);
        row.unit = group == 'season' ? '适量' : '克';
        row.qty.text = group == 'season' ? '' : '1';
        added++;
      }
      for (final n in fresh) {
        ingredients.add(
          _IngRow(
            group: group,
            n: n,
            q: group == 'season' ? '' : '1',
            unit: group == 'season' ? '适量' : '克',
          ),
        );
        added++;
      }
    });
    if (!mounted) return;
    AppToast.show(
      context,
      added > 0
          ? '已加入 $added 样${group == 'season' ? '调料' : '食材'}'
          : '这些食材已经在列表里了',
    );
  }

  Widget _ingredientGroup(
    CitroColors c,
    String group,
    String title, {
    bool required = false,
    String hint = '',
  }) {
    final rows = ingredients.where((e) => e.group == group).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: context.heading(size: 15, color: c.ink)),
            if (required) ...[
              const SizedBox(width: 3),
              Text(
                '*',
                style: context.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: c.stamp,
                ),
              ),
            ],
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: 9.5, color: c.inkSoft),
              ),
            ),
            GestureDetector(
              onTap: () => _openLibrary(group),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
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
                      size: 13,
                      color: c.accentInk,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '食材库',
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
        for (final row in rows) _ingredientRow(c, row),
        GestureDetector(
          onTap: () => setState(() => ingredients.add(_IngRow(group: group))),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: c.surface2.withAlpha(120),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.accent.withAlpha(110)),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.plus, width: 2.2),
                    size: 14,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    group == 'main' ? '加一个食材' : '加一个调料',
                    style: context.body(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: c.accentInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ingredientRow(CitroColors c, _IngRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line.withAlpha(160)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: row.name,
                    style: context.body(size: 13, color: c.ink),
                    decoration: InputDecoration(
                      hintText: '食材名',
                      hintStyle: context.body(size: 12, color: c.inkSoft),
                      filled: true,
                      fillColor: c.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 11,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide(color: c.line2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide(color: c.accent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _deleteBtn(
                c,
                () => setState(() {
                  if (ingredients.where((e) => e.group == row.group).length >
                      1) {
                    ingredients.remove(row);
                    row.dispose();
                  } else {
                    row.name.clear();
                    row.qty.text = '1';
                    row.unit = '克';
                  }
                }),
                size: 38,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              if (row.noQty)
                Flexible(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: c.line.withAlpha(150)),
                    ),
                    child: Text(
                      row.unit.isEmpty ? '不用单位，也不用填数量' : '用量写「${row.unit}」就行',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(size: 11, color: c.inkSoft),
                    ),
                  ),
                )
              else
                _QtyStepper(controller: row.qty, textInput: row.custom),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _pickUnit(row),
                child: Container(
                  height: 40,
                  constraints: const BoxConstraints(
                    minWidth: 70,
                    maxWidth: 132,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: c.hl,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.accent.withAlpha(95)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          row.unitLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.body(
                            size: 12,
                            weight: FontWeight.w700,
                            color: c.accentInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      AppIcon(
                        strokeSvg(AppIcons.chevronDown, width: 2),
                        size: 11,
                        color: c.accentInk,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickUnit(_IngRow row) async {
    FocusScope.of(context).unfocus();
    final options = [..._cookUnits, ''];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.c;
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: c.line),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text('选择单位', style: ctx.heading(size: 19)),
                const SizedBox(height: 5),
                Text(
                  '一小把、少许、少量、适量、不用单位不需要填数量',
                  textAlign: TextAlign.center,
                  style: ctx.body(size: 10.5, color: c.inkSoft),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * .62,
                  ),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final unit in options)
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx, unit),
                            child: Container(
                              height: 40,
                              constraints: const BoxConstraints(minWidth: 56),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: row.unit == unit ? c.accent : c.surface2,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: row.unit == unit ? c.accent : c.line2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    unit.isEmpty ? '不用单位' : unit,
                                    style: ctx.body(
                                      size: 12,
                                      weight: FontWeight.w700,
                                      color: row.unit == unit
                                          ? const Color(0xFF2E2C22)
                                          : c.ink2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      row.unit = picked;
      if (row.noQty) {
        row.qty.clear();
      } else if (row.qty.text.trim().isEmpty) {
        row.qty.text = '1';
      }
    });
  }

  Widget _stepSteps(CitroColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHead(c, '一步一步来', '每一步都能配一张图、挂一个倒计时；做菜时在详情页点计时就能用。'),
        for (var i = 0; i < steps.length; i++) _stepRow(c, i),
        GestureDetector(
          onTap: () => setState(() => steps.add(_StepRow())),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.accent.withAlpha(100)),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.plus, width: 2.2),
                    size: 13,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '加一步',
                    style: context.body(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: c.accentInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepRow(CitroColors c, int i) {
    final row = steps[i];
    final timer = int.tryParse(row.timer.text.trim()) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 9, 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
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
              const Spacer(),
              _toolBtn(c, AppIcons.image, '图片', () => _pickStepImage(i)),
              const SizedBox(width: 6),
              _toolBtn(c, null, timer > 0 ? '⏱ $timer 分' : '⏱ 计时', () async {
                final v = await _pickMinutes('这一步要多久？', timer, max: 300);
                if (v != null) setState(() => row.timer.text = '$v');
              }, accent: timer > 0),
              const SizedBox(width: 6),
              _deleteBtn(
                c,
                () => setState(() {
                  if (steps.length > 1) {
                    steps.removeAt(i);
                    row.dispose();
                  } else {
                    row.text.clear();
                    row.img = '';
                    row.timer.text = '';
                  }
                }),
                size: 36,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.text,
            maxLines: 3,
            style: context.body(size: 13, color: c.ink, height: 1.6),
            decoration: InputDecoration(
              hintText: '第 ${i + 1} 步：先做什么、火候多大、到什么状态算好…',
              hintStyle: context.body(size: 12, color: c.inkSoft),
              isDense: true,
              border: InputBorder.none,
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          if (row.img.isNotEmpty) ...[
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          Api.imageUrl(row.img),
                          fit: BoxFit.cover,
                          cacheWidth: 260,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 3,
                      top: 3,
                      child: GestureDetector(
                        onTap: () => setState(() => row.img = ''),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c.stamp,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.surface, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepNote(CitroColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHead(c, '私房笔记', '心得、小诀窍、家传秘方……写给自己，也可以公开给别人看。'),
        _label(c, '笔记'),
        _field(note, '例如：糖减到 40g 更好吃；外婆说一定要用猪油才香…', maxLines: 4),
        const SizedBox(height: 12),
        _label(c, '自定义标签（逗号分隔，选填）'),
        _field(tags, '例如：招待客人，一锅出'),
        const SizedBox(height: 14),
        _label(c, '谁可以看'),
        Row(
          children: [
            Expanded(child: _visBtn(c, false, '🔒 私密', '仅自己可见')),
            const SizedBox(width: 8),
            Expanded(child: _visBtn(c, true, '🌐 公开', '出现在食谱广场')),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          visibilityPublic
              ? '会出现在「食谱广场」，所有人都能看到这道菜（下厨日记仍只属于你）。'
              : '只有你自己能看到这份食谱。',
          style: context.body(size: 10, color: c.inkSoft, height: 1.6),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _visBtn(CitroColors c, bool pub, String label, String hint) {
    final on = visibilityPublic == pub;
    return GestureDetector(
      onTap: () => setState(() => visibilityPublic = pub),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: on ? c.hl : c.surface2,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: on ? c.accent : c.line2),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: context.body(
                size: 12.5,
                weight: FontWeight.w700,
                color: on ? c.accentInk : c.ink2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: context.body(size: 9, color: c.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(CitroColors c, String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Flexible(
            child: Text(
              text,
              style: context.body(
                size: 11,
                weight: FontWeight.w700,
                color: c.inkSoft,
              ),
            ),
          ),
          if (required) ...[
            const SizedBox(width: 2),
            Text(
              '*',
              style: context.body(
                size: 12,
                weight: FontWeight.w700,
                color: c.stamp,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chips(
    CitroColors c,
    List<String> options,
    String value,
    ValueChanged<String> onSelected,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final option in options)
          GestureDetector(
            onTap: () => onSelected(option),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: value == option ? c.accent : c.surface2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: value == option ? c.accent : c.line2),
              ),
              child: Text(
                option,
                style: context.body(
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: value == option ? const Color(0xFF2E2C22) : c.ink2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _timeBtn(
    CitroColors c,
    String label,
    int minutes,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.line2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.body(size: 9, color: c.inkSoft)),
                  const SizedBox(height: 1),
                  Text(
                    minutes > 0 ? '$minutes 分钟' : '未设置',
                    style: context.body(
                      size: 12,
                      weight: FontWeight.w600,
                      color: minutes > 0 ? c.accentInk : c.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            AppIcon(
              strokeSvg(AppIcons.chevronDown, width: 2),
              size: 12,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    int? maxLength,
    int maxLines = 1,
    bool numeric = false,
  }) {
    final c = context.c;
    return TextField(
      controller: ctrl,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      style: context.body(size: 12.5),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: context.body(size: 11.5, color: c.inkSoft),
        filled: true,
        fillColor: c.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 10,
        ),
        constraints: BoxConstraints(minHeight: maxLines > 1 ? 88 : 38),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: c.line2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: c.accent),
        ),
      ),
    );
  }

  Widget _toolBtn(
    CitroColors c,
    String? icon,
    String label,
    VoidCallback onTap, {
    bool accent = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: icon == null ? 12 : 10),
        decoration: BoxDecoration(
          color: accent ? c.hl : c.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: accent ? c.accent.withAlpha(110) : c.line2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AppIcon(strokeSvg(icon, width: 2), size: 15, color: c.accentInk),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: context.body(
                size: 11.5,
                weight: FontWeight.w600,
                color: c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deleteBtn(CitroColors c, VoidCallback onTap, {double size = 36}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.stamp.withAlpha(c.dark ? 28 : 16),
          shape: BoxShape.circle,
          border: Border.all(color: c.stamp.withAlpha(150)),
        ),
        child: Center(
          child: AppIcon(
            strokeSvg(AppIcons.close, width: 2.2),
            size: size * .42,
            color: c.stamp,
          ),
        ),
      ),
    );
  }
}

class _CoverCropDialog extends StatefulWidget {
  final Uint8List bytes;
  const _CoverCropDialog({required this.bytes});
  @override
  State<_CoverCropDialog> createState() => _CoverCropDialogState();
}

class _CoverCropDialogState extends State<_CoverCropDialog> {
  final TransformationController _controller = TransformationController();
  img.Image? _source;
  bool _fitted = false;
  bool busy = false;
  double _side = 280;
  double _k0 = 1;
  double _dw = 280;
  double _dh = 280;

  @override
  void initState() {
    super.initState();
    try {
      _source = img.decodeImage(widget.bytes);
    } catch (_) {
      _source = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_source != null && !_fitted) {
      _side = math.max(
        200.0,
        math.min(MediaQuery.sizeOf(context).width - 76, 330.0),
      );
      _fit();
      _fitted = true;
    }
  }

  void _fit() {
    final source = _source;
    if (source == null) return;
    _k0 = math.max(_side / source.width, _side / source.height).toDouble();
    _dw = source.width * _k0;
    _dh = source.height * _k0;
    _controller.value = Matrix4.identity()
      ..translate((_side - _dw) / 2, (_side - _dh) / 2);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    final source = _source;
    if (busy || source == null) return;
    setState(() => busy = true);
    try {
      final m = _controller.value;
      final total = _k0 * m.getMaxScaleOnAxis();
      var sideSrc = _side / total;
      final maxSide = math.min(source.width, source.height).toDouble();
      if (sideSrc > maxSide) sideSrc = maxSide;
      final sx = (-m.storage[12] / total)
          .clamp(0.0, math.max(0.0, source.width - sideSrc))
          .toDouble();
      final sy = (-m.storage[13] / total)
          .clamp(0.0, math.max(0.0, source.height - sideSrc))
          .toDouble();
      final sideInt = sideSrc
          .round()
          .clamp(1, math.min(source.width, source.height))
          .toInt();
      final left = sx
          .round()
          .clamp(0, math.max(0, source.width - sideInt))
          .toInt();
      final top = sy
          .round()
          .clamp(0, math.max(0, source.height - sideInt))
          .toInt();
      final cropped = img.copyCrop(
        source,
        x: left,
        y: top,
        width: sideInt,
        height: sideInt,
      );
      final out = math.min(1200, math.max(400, sideInt)).toInt();
      final resized = out == sideInt
          ? cropped
          : img.copyResize(
              cropped,
              width: out,
              height: out,
              interpolation: img.Interpolation.linear,
            );
      final data = Uint8List.fromList(img.encodeJpg(resized, quality: 90));
      if (!mounted) return;
      Navigator.of(context).pop(data);
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        AppToast.show(context, '裁切失败，请重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final source = _source;
    if (source == null) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('这张图读不出来', style: context.heading(size: 19, color: c.ink)),
              const SizedBox(height: 6),
              Text('换一张图片再试', style: context.body(size: 11, color: c.inkSoft)),
              const SizedBox(height: 14),
              AccentButton(
                text: '关闭',
                height: 42,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('裁切封面', style: context.heading(size: 20, color: c.ink)),
                const Spacer(),
                GestureDetector(
                  onTap: _fit,
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.line2),
                    ),
                    child: Text(
                      '重置',
                      style: context.body(
                        size: 10.5,
                        weight: FontWeight.w600,
                        color: c.ink2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '单指拖动 · 双指缩放 · 自由取景',
              style: context.body(size: 10.5, color: c.inkSoft),
            ),
            const SizedBox(height: 12),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: _side,
                  height: _side,
                  color: const Color(0xFF1B1A17),
                  child: Stack(
                    children: [
                      InteractiveViewer(
                        transformationController: _controller,
                        constrained: false,
                        minScale: 1,
                        maxScale: 4,
                        panEnabled: true,
                        scaleEnabled: true,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _dw,
                          height: _dh,
                          child: Image.memory(
                            widget.bytes,
                            width: _dw,
                            height: _dh,
                            fit: BoxFit.fill,
                            cacheWidth: 900,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: _CropGuidePainter(c)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    text: '取消',
                    outlined: true,
                    height: 42,
                    onTap: busy ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AccentButton(
                    text: busy ? '裁切中…' : '完成',
                    height: 42,
                    onTap: busy ? null : _done,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CropGuidePainter extends CustomPainter {
  final CitroColors c;
  _CropGuidePainter(this.c);
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withAlpha(90)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final d = size.width * i / 3;
      canvas.drawLine(Offset(d, 0), Offset(d, size.height), line);
      canvas.drawLine(Offset(0, d), Offset(size.width, d), line);
    }
    final edge = Paint()
      ..color = Colors.white.withAlpha(210)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(1, 1, size.width - 2, size.height - 2), edge);
  }

  @override
  bool shouldRepaint(covariant _CropGuidePainter oldDelegate) =>
      oldDelegate.c != c;
}

Future<Recipe?> showDiaryDialog(BuildContext context, Recipe recipe) async {
  final tweaks = TextEditingController();
  final result = TextEditingController();
  DateTime date = DateTime.now();
  int rating = 3;
  final saved = await showCitroDialog<Recipe>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.c;
        return PaperDialog(
          maxWidth: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '记一笔下厨日记',
                textAlign: TextAlign.center,
                style: context.heading(size: 20),
              ),
              const SizedBox(height: 4),
              Text(
                recipe.name,
                textAlign: TextAlign.center,
                style: context.body(size: 11.5, color: c.inkSoft),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d != null) setState(() => date = d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.line2),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '日期',
                        style: context.body(size: 11.5, color: c.inkSoft),
                      ),
                      const Spacer(),
                      Text(
                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                        style: context.body(size: 12, color: c.ink),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('评分', style: context.body(size: 11.5, color: c.inkSoft)),
                  const SizedBox(width: 8),
                  for (var i = 1; i <= 5; i++)
                    GestureDetector(
                      onTap: () => setState(() => rating = i),
                      child: Text(
                        i <= rating ? '★' : '☆',
                        style: TextStyle(fontSize: 22, color: c.accentInk),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              CitroField(
                label: '本次改动',
                hint: '例如：少放了盐，多炖了 10 分钟',
                controller: tweaks,
                maxLength: 200,
              ),
              const SizedBox(height: 8),
              CitroField(
                label: '成品 / 心得',
                hint: '味道怎么样？',
                controller: result,
                maxLines: 3,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: AccentButton(
                      text: '取消',
                      outlined: true,
                      onTap: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: AccentButton(
                      text: '保存',
                      onTap: () async {
                        final d = CookDiary(
                          id: '',
                          date:
                              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                          tweaks: tweaks.text.trim(),
                          rating: rating,
                          result: result.text.trim(),
                          ts: DateTime.now().millisecondsSinceEpoch,
                        );
                        recipe.diary.add(d);
                        try {
                          final updated = await Api.saveRecipe(recipe);
                          if (ctx.mounted) Navigator.pop(ctx, updated);
                        } catch (e) {
                          if (ctx.mounted) AppToast.show(ctx, '$e');
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
  return saved;
}

Future<FridgeItem?> showFridgeDialog(
  BuildContext context,
  FridgeItem? initial,
) async {
  final name = TextEditingController(text: initial?.name ?? '');
  final qty = TextEditingController(text: initial?.qty ?? '1');
  String unit = initial?.unit ?? '个';
  DateTime? buyDate = initial?.buyDate.isNotEmpty == true
      ? DateTime.tryParse(initial!.buyDate)
      : DateTime.now();
  DateTime? expDate = initial?.expDate.isNotEmpty == true
      ? DateTime.tryParse(initial!.expDate)
      : null;
  const units = ['个', '包', '瓶', '罐', '把', '克', '斤', '毫升', '升', '杯', '少许', '适量'];
  final result = await showCitroDialog<FridgeItem>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.c;
        String ds(DateTime? d) => d == null
            ? '未设置'
            : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        return PaperDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                initial == null ? '添加食材' : '编辑食材',
                textAlign: TextAlign.center,
                style: context.heading(size: 20),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: CitroField(
                      label: '食材名称 *',
                      hint: '如：牛腩',
                      controller: name,
                      maxLength: 40,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      FocusScope.of(ctx).unfocus();
                      final picked = await showIngredientLibrary(
                        ctx,
                        title: '从食材库选',
                        multi: false,
                      );
                      if (picked == null || picked.isEmpty || !ctx.mounted)
                        return;
                      final n = picked.first;
                      setState(() {
                        name.text = n;
                        if (RegExp(
                          r'粉|糖|盐|孜然|花椒|八角|肉桂|香叶|豆蔻|姜黄|咖喱|泡打粉|藏红花|味精|鸡精',
                        ).hasMatch(n)) {
                          unit = '克';
                        } else if (RegExp(r'油|醋|酱|酒|奶|汁|露|味淋|高汤|蜂蜜|糖浆|水')
                            .hasMatch(n)) {
                          unit = '毫升';
                        }
                      });
                    },
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: c.hl,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.accent.withAlpha(95)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '食材库',
                            style: context.body(
                              size: 11,
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
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '数量',
                  style: context.body(
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: c.inkSoft,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: _QtyStepper(controller: qty),
              ),
              const SizedBox(height: 10),
              Text(
                '单位',
                style: context.body(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: c.inkSoft,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final u in units)
                    GestureDetector(
                      onTap: () => setState(() => unit = u),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: unit == u ? c.accent : c.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: unit == u ? c.accent : c.line2,
                          ),
                        ),
                        child: Text(
                          u,
                          style: context.body(
                            size: 11.5,
                            weight: FontWeight.w600,
                            color: unit == u ? const Color(0xFF2E2C22) : c.ink2,
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
                    child: GestureDetector(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: buyDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => buyDate = d);
                      },
                      child: _dateBox(context, c, '购买日期', ds(buyDate)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate:
                              expDate ??
                              DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setState(() => expDate = d);
                      },
                      child: _dateBox(context, c, '到期日', ds(expDate)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: AccentButton(
                      text: '取消',
                      outlined: true,
                      onTap: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: AccentButton(
                      text: '保存',
                      onTap: () {
                        if (name.text.trim().isEmpty) {
                          AppToast.show(ctx, '请填写食材名称');
                          return;
                        }
                        Navigator.pop(
                          ctx,
                          FridgeItem(
                            id: initial?.id ?? '',
                            name: name.text.trim(),
                            qty: qty.text.trim().isEmpty
                                ? '1'
                                : qty.text.trim(),
                            unit: unit,
                            buyDate: ds(buyDate) == '未设置' ? '' : ds(buyDate),
                            expDate: ds(expDate) == '未设置' ? '' : ds(expDate),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
  return result;
}

Widget _dateBox(
  BuildContext context,
  CitroColors c,
  String label,
  String value,
) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: c.surface2,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.line2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.body(size: 9, color: c.inkSoft)),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.body(size: 11.5, color: c.ink),
        ),
      ],
    ),
  );
}

Future<Recipe?> showFoodSheet(BuildContext context, List<Recipe> mine) async {
  return showModalBottomSheet<Recipe>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8A23211C),
    builder: (_) => _FoodSheet(mine: mine),
  );
}

class _FoodSheet extends StatefulWidget {
  final List<Recipe> mine;
  const _FoodSheet({required this.mine});
  @override
  State<_FoodSheet> createState() => _FoodSheetState();
}

class _FoodSheetState extends State<_FoodSheet> {
  static const _recipeCat = '我的食谱';
  static const _categories = <String, List<String>>{
    '早餐': ['豆浆油条', '小笼包', '煎蛋三明治', '皮蛋瘦肉粥', '葱油拌面', '酸奶水果碗'],
    '午餐': ['番茄牛腩', '青椒炒蛋', '咖喱鸡饭', '照烧鸡腿饭', '麻婆豆腐', '蒜蓉西兰花'],
    '晚餐': ['清蒸鲈鱼', '红烧排骨', '白灼虾', '冬瓜丸子汤', '宫保鸡丁', '香菇青菜'],
    '夜宵': ['泡面加蛋', '烤冷面', '关东煮', '小龙虾', '炸鸡', '煎饺'],
    '饮品': ['柠檬气泡水', '冰美式', '杨枝甘露', '桂花乌龙', '草莓奶昔', '酸梅汤'],
    '酒水': ['精酿啤酒', '梅子酒', '威士忌高球', '莫吉托', '热红酒', '清酒'],
  };
  static const _icons = <String, String>{
    '早餐': '🌅',
    '午餐': '☀️',
    '晚餐': '🌙',
    '夜宵': '🍢',
    '饮品': '🥤',
    '酒水': '🍶',
    _recipeCat: '🍚',
  };

  final rnd = math.Random();
  String cat = '午餐';
  String result = '点一下下面的按钮，今日菜单马上揭晓';
  bool rolling = false;
  bool openingRecipe = false;
  Recipe? pendingRecipe;
  String? lastDish;
  String? lastRecipeId;
  double _dragDy = 0;
  bool _dragging = false;

  void _dragStart(DragStartDetails _) => setState(() => _dragging = true);

  void _dragUpdate(DragUpdateDetails d) {
    setState(() => _dragDy = math.max(0, _dragDy + d.delta.dy));
  }

  void _dragEnd(DragEndDetails d) {
    final close = _dragDy > 90 || d.velocity.pixelsPerSecond.dy > 700;
    setState(() {
      _dragging = false;
      _dragDy = 0;
    });
    if (close) Navigator.of(context).pop();
  }

  void _dragCancel() => setState(() {
    _dragging = false;
    _dragDy = 0;
  });

  void _select(String value) {
    if (rolling) return;
    setState(() {
      cat = value;
      result = _idleText;
      pendingRecipe = null;
    });
  }

  String get _idleText => cat == _recipeCat
      ? (widget.mine.isEmpty
            ? '你的食谱库还是空的，先去记一道菜吧'
            : '从你的 ${widget.mine.length} 道食谱里抽一道')
      : '点一下下面的按钮，今日菜单马上揭晓';

  String _recipeText(Recipe r) =>
      '${r.emoji.isEmpty ? '🍳' : r.emoji} ${r.name}';

  Future<void> _draw() async {
    if (rolling || openingRecipe) return;
    final isRecipe = cat == _recipeCat;
    if (isRecipe && widget.mine.isEmpty) {
      AppToast.show(context, '食谱库还是空的，先记一道菜吧');
      return;
    }
    final dishes = isRecipe ? null : _categories[cat]!;
    Recipe? finalRecipe;
    String? finalDish;
    if (isRecipe) {
      for (var i = 0; i < 8; i++) {
        final candidate = widget.mine[rnd.nextInt(widget.mine.length)];
        if (widget.mine.length < 2 || candidate.id != lastRecipeId) {
          finalRecipe = candidate;
          break;
        }
      }
      finalRecipe ??= widget.mine.first;
      lastRecipeId = finalRecipe.id;
    } else {
      do {
        finalDish = dishes![rnd.nextInt(dishes.length)];
      } while (dishes.length > 1 && finalDish == lastDish);
      lastDish = finalDish;
    }

    setState(() => rolling = true);
    for (var i = 0; i < 18; i++) {
      await Future<void>.delayed(
        Duration(milliseconds: 46 + (i * i / 18).round()),
      );
      if (!mounted) return;
      final preview = isRecipe
          ? _recipeText(widget.mine[rnd.nextInt(widget.mine.length)])
          : dishes![rnd.nextInt(dishes.length)];
      setState(() => result = preview);
    }
    if (!mounted) return;
    setState(() {
      result = isRecipe ? _recipeText(finalRecipe!) : finalDish!;
      rolling = false;
      pendingRecipe = finalRecipe;
      openingRecipe = finalRecipe != null;
    });
    if (finalRecipe != null) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop(finalRecipe);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final duo = CitroForm.duoDevice(MediaQuery.sizeOf(context));
    final height = MediaQuery.sizeOf(context).height * .68;
    return AnimatedSlide(
      offset: Offset(0, _dragDy / height),
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _dragStart,
        onVerticalDragUpdate: _dragUpdate,
        onVerticalDragEnd: _dragEnd,
        onVerticalDragCancel: _dragCancel,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: c.line),
          ),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: c.line2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
                      child: Row(
                        children: [
                          Text('今天吃什么', style: context.heading(size: 22)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: c.surface2,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.line2),
                              ),
                              child: Center(
                                child: AppIcon(
                                  strokeSvg(AppIcons.close, width: 2.2),
                                  size: 22,
                                  color: c.inkSoft,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in _categories.keys)
                              _catBtn(entry),
                            _catBtn(_recipeCat),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 160),
                            child: Container(
                              width: double.infinity,
                              height: 160,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: c.noteY.withAlpha(c.dark ? 80 : 190),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: c.line),
                                boxShadow: CitroColors.shadows.note(c),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) => FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SizedBox(
                                    width: constraints.maxWidth,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (cat == _recipeCat)
                                          Text(
                                            '我的食谱 · ${widget.mine.length} 道',
                                            style: context.body(
                                              size: 10,
                                              color: c.inkSoft,
                                            ),
                                          ),
                                        const SizedBox(height: 5),
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 80,
                                          ),
                                          transitionBuilder: (child, anim) =>
                                              ScaleTransition(
                                                scale: Tween(
                                                  begin: .92,
                                                  end: 1.0,
                                                ).animate(anim),
                                                child: FadeTransition(
                                                  opacity: anim,
                                                  child: child,
                                                ),
                                              ),
                                          child: Text(
                                            result,
                                            key: ValueKey(
                                              '$result-${rolling ? 'r' : 'f'}',
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.display(
                                              size: result.length > 12
                                                  ? 22
                                                  : 28,
                                              weight: FontWeight.w700,
                                              color: c.ink,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                        if (openingRecipe) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            '正在打开这道菜…',
                                            style: context.body(
                                              size: 10,
                                              color: c.accentInk,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Column(
                        children: [
                          AccentButton(
                            text: rolling
                                ? '命运安排中…'
                                : (openingRecipe ? '正在打开…' : '开始抽取'),
                            width: duo ? 320 : null,
                            onTap: rolling || openingRecipe ? null : _draw,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            cat == _recipeCat ? '抽到食谱会直接打开详情' : '抽到满意的，就去厨房试试吧',
                            textAlign: TextAlign.center,
                            style: context.body(size: 9.5, color: c.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _catBtn(String value) {
    final c = context.c;
    final on = cat == value;
    final label = value == _recipeCat
        ? '$value${widget.mine.isNotEmpty ? ' ${widget.mine.length}' : ''}'
        : value;
    return GestureDetector(
      onTap: () => _select(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: on ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? c.accent : c.line2),
          boxShadow: on ? CitroColors.shadows.note(c) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_icons[value] ?? ''} $label',
              style: context.body(
                size: 13,
                weight: FontWeight.w700,
                color: on ? const Color(0xFF2E2C22) : c.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
