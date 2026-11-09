import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/media.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'ledger_ai.dart';
import 'ledger_category_sheet.dart';
import 'ledger_date_picker.dart';
import 'ledger_intake.dart';
import 'ledger_models.dart';
import 'ledger_receipt.dart';
import 'ledger_store.dart';
import 'ledger_theme.dart';
import 'ledger_widgets.dart';

/// 记一笔：手动录入 + 截图识别草稿确认。
class LedgerAddTab extends StatefulWidget {
  final VoidCallback onSaved;

  const LedgerAddTab({super.key, required this.onSaved});

  @override
  State<LedgerAddTab> createState() => _LedgerAddTabState();
}

class _LedgerAddTabState extends State<LedgerAddTab> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  LedgerKind _kind = LedgerKind.expense;
  String _categoryId = 'food';
  DateTime _at = DateTime.now();
  bool _scanning = false;
  int? _lastSavedCents;
  StreamSubscription<void>? _intakeSub;

  @override
  void initState() {
    super.initState();
    _intakeSub = LedgerIntake.instance.pending.listen((_) => _consumeIntake());
    // 冷启动时原生侧在监听注册前就把截图交上来了，首帧后主动取一次。
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeIntake());
  }

  @override
  void dispose() {
    _intakeSub?.cancel();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 取走系统分享（Android / iOS ShareExtension）送来的截图并开始识别。
  void _consumeIntake() {
    if (!mounted) return;
    final error = LedgerIntake.instance.takeError();
    if (error != null) ledgerToast(context, error);
    if (_scanning) return;
    final image = LedgerIntake.instance.takePending();
    if (image == null) return;
    unawaited(_scanBytes(image.bytes));
  }

  void _switchKind(LedgerKind kind) {
    final list = LedgerStore.instance.categoriesFor(kind);
    setState(() {
      _kind = kind;
      if (list.isNotEmpty && !list.any((c) => c.id == _categoryId)) {
        _categoryId = list.first.id;
      }
    });
  }

  void _quickAdd(int cents) {
    final current = ledgerParseAmount(_amount.text) ?? 0;
    final value = current + cents;
    setState(() {
      _amount.text = value % 100 == 0
          ? '${value ~/ 100}'
          : (value / 100).toStringAsFixed(2);
      _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
    });
  }

  Future<void> _save() async {
    final cents = ledgerParseAmount(_amount.text) ?? 0;
    if (cents <= 0) {
      ledgerToast(context, '先填一个金额吧');
      return;
    }
    final store = LedgerStore.instance;
    final category = store.categoryOf(_categoryId, kind: _kind);
    store.addEntry(
      kind: _kind,
      amountCents: cents,
      categoryId: category.id,
      note: _note.text.trim(),
      occurredAt: _at,
    );
    setState(() {
      _lastSavedCents = cents;
      _amount.clear();
      _note.clear();
      _at = DateTime.now();
    });
    ledgerToast(context, '已记下 ${_kind.label} ${ledgerMoney(cents)}');
  }

  Future<void> _pickDate() async {
    final picked = await showLedgerDatePicker(context, initial: _at);
    if (picked == null) return;
    setState(
      () => _at = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _at.hour,
        _at.minute,
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showLedgerTimePicker(context, initial: _at);
    if (picked == null) return;
    setState(
      () => _at = DateTime(
        _at.year,
        _at.month,
        _at.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  Future<void> _showScanOptions() async {
    if (_scanning) return;
    final camera = await showCitroSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ctx.c.line2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '识别账单截图',
                style: ctx.lheading(size: CitroType.subtitle, color: ctx.c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                '支持微信 / 支付宝 / 银行账单，识别后会先生成草稿',
                style: ctx.lui(size: CitroType.caption, color: ctx.c.inkSoft),
              ),
              const SizedBox(height: 14),
              _scanOption(
                ctx,
                icon: AppIcons.image,
                title: '从相册选择',
                hint: '已有的账单截图',
                onTap: () => Navigator.of(ctx).pop(false),
              ),
              const SizedBox(height: 8),
              _scanOption(
                ctx,
                icon: AppIcons.camera,
                title: '拍一张',
                hint: '对着纸质小票或付款页面',
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
    if (camera == null) return;
    await _scan(camera: camera);
  }

  Widget _scanOption(
    BuildContext context, {
    required String icon,
    required String title,
    required String hint,
    required VoidCallback onTap,
  }) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: .985,
      hoverLift: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            LedgerIconTile(
              iconKey: icon == AppIcons.camera ? 'flag' : 'wallet',
              tint: c.accent,
              size: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: context.lui(
                      size: CitroType.body,
                      weight: CitroType.strong,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    hint,
                    style: context.lui(
                      size: CitroType.caption,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            AppIcon(
              strokeSvg(AppIcons.arrowRight, width: 2),
              size: 16,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scan({required bool camera}) async {
    Uint8List? raw;
    try {
      raw = await MediaService.pickImageBytes(
        camera: camera,
        maxWidth: 1800,
        quality: 92,
      );
    } catch (e) {
      if (mounted) {
        ledgerToast(context, '$e'.replaceFirst('AiException: ', ''));
      }
      return;
    }
    if (raw == null || raw.isEmpty) return;
    await _scanBytes(raw);
  }

  /// 系统分享（Android / iOS ShareExtension）送来的图片直接走同一条识别链路。
  Future<void> _scanBytes(Uint8List raw) async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final compressed = await MediaService.compressCookImage(
        raw,
        maxDim: 1400,
        quality: 84,
        limit: 420 * 1024,
      );
      final dataUrl = MediaService.dataUrl(compressed);
      final drafts = await LedgerAi.parseReceipt(
        dataUrl,
        categories: LedgerStore.instance.categories,
      );
      if (!mounted) return;
      if (drafts.isEmpty) {
        ledgerToast(context, '没有识别到账单，换一张更清晰的截图试试');
        return;
      }
      final count = await showLedgerDraftsSheet(
        context,
        drafts: drafts,
        source: LedgerSource.scan,
      );
      if (!mounted || count == null || count == 0) return;
      ledgerToast(context, '已确认入账 $count 笔');
      setState(() => _lastSavedCents = null);
    } catch (e) {
      if (!mounted) return;
      ledgerToast(context, '$e'.replaceFirst('AiException: ', ''));
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
        // 连续分享多张时继续处理队列里的下一张。
        _consumeIntake();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = LedgerStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final categories = store.categoriesFor(_kind);
        final c = context.c;
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: LedgerKindToggle(
                            value: _kind,
                            onChanged: _switchKind,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: '分类管理',
                          child: Semantics(
                            button: true,
                            label: '分类管理',
                            child: Pressable(
                              onTap: () => showLedgerCategorySheet(context),
                              scale: .92,
                              hoverLift: 0,
                              borderRadius: BorderRadius.circular(99),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: c.accentLt,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: c.accent.withAlpha(110),
                                  ),
                                ),
                                child: Center(
                                  child: AppIcon(
                                    strokeSvg(AppIcons.menu, width: 2),
                                    size: 18,
                                    color: c.accentInk,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _amountCard(context),
                    const SizedBox(height: 10),
                    _quickAmounts(context),
                    const SizedBox(height: 12),
                    LedgerSectionTitle(
                      title: '分类',
                      hint: _kind == LedgerKind.expense ? '这笔钱花在哪' : '这笔钱从哪来',
                    ),
                    const SizedBox(height: 8),
                    LedgerCategoryPicker(
                      categories: categories,
                      selectedId: _categoryId,
                      onSelected: (category) =>
                          setState(() => _categoryId = category.id),
                    ),
                    const SizedBox(height: 12),
                    _dateCard(context),
                    const SizedBox(height: 12),
                    CitroField(
                      label: '备注',
                      hint: '例如：和同事吃午饭',
                      controller: _note,
                      maxLength: 40,
                    ),
                    const SizedBox(height: 12),
                    _scanCard(context),
                    const SizedBox(height: 12),
                    if (_lastSavedCents != null) ...[
                      _savedBanner(context),
                      const SizedBox(height: 10),
                    ],
                    AccentButton(text: '记下来', height: 52, onTap: _save),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '截图识别与 cici 代记账都会先生成草稿，确认后才写入账本',
                        textAlign: TextAlign.center,
                        style: context.lui(
                          size: CitroType.small,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _amountCard(BuildContext context) {
    final c = context.c;
    return PaperCard(
      tapeColor: c.tape3,
      tapeAngle: -1.8,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _kind == LedgerKind.expense ? '花了多少' : '收到多少',
            style: context.lui(
              size: CitroType.caption,
              weight: CitroType.strong,
              color: c.inkSoft,
            ),
          ),
          TextField(
            controller: _amount,
            autofocus: false,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: context.ldisplay(
              size: 40,
              weight: FontWeight.w700,
              color: c.ink,
              height: 1.2,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              prefixText: '¥ ',
              prefixStyle: context.ldisplay(
                size: 24,
                weight: FontWeight.w700,
                color: c.inkSoft,
              ),
              hintText: '0.00',
              hintStyle: context.ldisplay(
                size: 40,
                weight: FontWeight.w700,
                color: c.inkSoft.withAlpha(90),
              ),
              contentPadding: const EdgeInsets.only(top: 6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAmounts(BuildContext context) {
    final c = context.c;
    final values = _kind == LedgerKind.expense
        ? const [1000, 2000, 3000, 5000]
        : const [100000, 500000, 1000000];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final cents in values)
          LedgerChip(
            text: '+${ledgerMoney(cents, symbol: false)}',
            color: c.inkSoft,
            onTap: () => _quickAdd(cents),
          ),
        LedgerChip(
          text: '清空',
          color: c.inkSoft,
          onTap: () => setState(() => _amount.clear()),
        ),
      ],
    );
  }

  Widget _dateCard(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _dateTimeButton(
            context,
            key: const ValueKey('ledger-date-button'),
            icon: AppIcons.calendar,
            label: '日期',
            value: '${_at.year}年${_at.month}月${_at.day}日',
            onTap: _pickDate,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _dateTimeButton(
            context,
            key: const ValueKey('ledger-time-button'),
            icon: AppIcons.clock,
            label: '时间',
            value: LedgerDates.timeLabel(_at),
            onTap: _pickTime,
          ),
        ),
      ],
    );
  }

  Widget _dateTimeButton(
    BuildContext context, {
    Key? key,
    required String icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final c = context.c;
    return Pressable(
      key: key,
      onTap: onTap,
      scale: .985,
      hoverLift: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(CitroColors.radii.inner),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            AppIcon(
              strokeSvg(icon, width: 1.9),
              size: 17,
              color: c.accentInk,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: context.lui(
                      size: CitroType.small,
                      color: c.inkSoft,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.lui(
                      size: CitroType.meta,
                      weight: CitroType.strong,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
            AppIcon(
              strokeSvg(AppIcons.chevronRight, width: 2),
              size: 14,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanCard(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: _scanning ? null : _showScanOptions,
      scale: .99,
      hoverLift: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.noteB,
          borderRadius: BorderRadius.circular(CitroColors.radii.card),
          border: Border.all(color: c.line),
          boxShadow: CitroColors.shadows.paper(c),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.line),
              ),
              child: Center(
                child: _scanning
                    ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.accent,
                        ),
                      )
                    : AppIcon(
                        strokeSvg(AppIcons.scan, width: 1.9),
                        size: 20,
                        color: c.accentInk,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _scanning ? '正在识别账单…' : '截图识别账单',
                    style: context.lui(
                      size: CitroType.body,
                      weight: CitroType.strong,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    _scanning ? '金额、商户、分类会自动整理成草稿' : '相册或拍照，识别后可以逐笔修改',
                    style: context.lui(
                      size: CitroType.caption,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            AppIcon(
              strokeSvg(AppIcons.arrowRight, width: 2),
              size: 16,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }

  Widget _savedBanner(BuildContext context) {
    final c = context.c;
    final cents = _lastSavedCents ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.mintSoft,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: c.mintLine),
      ),
      child: Row(
        children: [
          AppIcon(
            strokeSvg(AppIcons.check, width: 2.2),
            size: 15,
            color: c.mintInk,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '刚记下 ${ledgerMoney(cents)}，可以继续记下一笔',
              style: context.lui(size: CitroType.caption, color: c.mintInk),
            ),
          ),
          Pressable(
            onTap: widget.onSaved,
            scale: .95,
            hoverLift: 0,
            child: Text(
              '看首页',
              style: context.lui(
                size: CitroType.caption,
                weight: CitroType.strong,
                color: c.accentInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
