import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'ledger_date_picker.dart';
import 'ledger_models.dart';
import 'ledger_store.dart';
import 'ledger_theme.dart';
import 'ledger_widgets.dart';

/// 截图识别 / cici 代记账的确认弹层。
///
/// AI 永远不直接写账本：先在这里展示可编辑草稿，用户勾选并确认后才入账。
Future<int?> showLedgerDraftsSheet(
  BuildContext context, {
  required List<LedgerDraft> drafts,
  required LedgerSource source,
  String title = '确认账单',
}) {
  if (drafts.isEmpty) return Future<int?>.value(0);
  return showCitroSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    builder: (ctx) => LedgerScope(
      child: _LedgerDraftSheet(drafts: drafts, source: source, title: title),
    ),
  );
}

class _LedgerDraftSheet extends StatefulWidget {
  final List<LedgerDraft> drafts;
  final LedgerSource source;
  final String title;

  const _LedgerDraftSheet({
    required this.drafts,
    required this.source,
    required this.title,
  });

  @override
  State<_LedgerDraftSheet> createState() => _LedgerDraftSheetState();
}

class _DraftEdit {
  LedgerDraft draft;
  final TextEditingController amount;
  final TextEditingController note;
  bool selected;

  _DraftEdit(this.draft)
    : amount = TextEditingController(text: _amountText(draft.amountCents)),
      note = TextEditingController(text: draft.note),
      selected = true;

  int get cents => ledgerParseAmount(amount.text) ?? 0;

  static String _amountText(int cents) =>
      cents % 100 == 0 ? '${cents ~/ 100}' : (cents / 100).toStringAsFixed(2);

  void dispose() {
    amount.dispose();
    note.dispose();
  }
}

class _LedgerDraftSheetState extends State<_LedgerDraftSheet> {
  late final List<_DraftEdit> _edits = [
    for (final draft in widget.drafts) _DraftEdit(draft),
  ];

  @override
  void dispose() {
    for (final edit in _edits) {
      edit.dispose();
    }
    super.dispose();
  }

  int get _total =>
      _edits.fold<int>(0, (sum, e) => sum + (e.selected ? e.cents : 0));

  void _confirm() {
    final store = LedgerStore.instance;
    var count = 0;
    for (final edit in _edits) {
      if (!edit.selected) continue;
      final cents = edit.cents;
      if (cents <= 0) continue;
      final category = store.categoryOf(
        edit.draft.categoryId,
        kind: edit.draft.kind,
      );
      store.addEntry(
        kind: edit.draft.kind,
        amountCents: cents,
        categoryId: category.id,
        note: edit.note.text.trim(),
        occurredAt: edit.draft.occurredAt,
        source: widget.source,
      );
      count++;
    }
    if (count == 0) {
      ledgerToast(context, '没有可入账的账单，请检查金额');
      return;
    }
    Navigator.of(context).pop(count);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final selectedCount = _edits.where((e) => e.selected).length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .88,
          minChildSize: .5,
          maxChildSize: .96,
          builder: (context, scroll) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: context.lheading(
                                size: CitroType.subtitle,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '识别到 ${_edits.length} 笔，确认前都可以修改',
                              style: context.lui(
                                size: CitroType.caption,
                                color: c.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      LedgerChip(
                        text: '已选 $selectedCount 笔',
                        filled: true,
                        onTap: () {
                          final all = selectedCount != _edits.length;
                          setState(() {
                            for (final edit in _edits) {
                              edit.selected = all;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    itemCount: _edits.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _card(_edits[index]),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '合计',
                              style: context.lui(
                                size: CitroType.caption,
                                color: c.inkSoft,
                              ),
                            ),
                            Text(
                              ledgerMoney(_total),
                              style: context.ldisplay(
                                size: 24,
                                weight: FontWeight.w700,
                                color: c.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AccentButton(
                        text: selectedCount == 0
                            ? '请选择账单'
                            : '确认入账 $selectedCount 笔',
                        width: 190,
                        onTap: selectedCount == 0 ? null : _confirm,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _card(_DraftEdit edit) {
    final c = context.c;
    final kind = edit.draft.kind;
    final categories = LedgerStore.instance.categoriesFor(kind);
    final category = LedgerStore.instance.categoryOf(
      edit.draft.categoryId,
      kind: kind,
    );
    return AnimatedOpacity(
      duration: CitroMotion.reduced(context)
          ? Duration.zero
          : CitroMotion.hover,
      opacity: edit.selected ? 1 : .55,
      child: PaperCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        color: c.surface2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Pressable(
                  onTap: () => setState(() => edit.selected = !edit.selected),
                  scale: .9,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: edit.selected ? c.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: edit.selected ? c.accent : c.line2,
                        width: 1.4,
                      ),
                    ),
                    child: edit.selected
                        ? const Center(
                            child: Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: Color(0xFF2E2C22),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: LedgerKindToggle(
                      compact: true,
                      value: kind,
                      onChanged: (value) {
                        final list = LedgerStore.instance.categoriesFor(value);
                        setState(() {
                          edit.draft = edit.draft.copyWith(
                            kind: value,
                            categoryId: list.isEmpty ? '' : list.first.id,
                          );
                        });
                      },
                    ),
                  ),
                ),
                if (edit.draft.needsReview) ...[
                  const SizedBox(width: 6),
                  LedgerChip(
                    text: '待确认',
                    color: c.stamp,
                    icon: AppIcons.info,
                    filled: true,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: edit.amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    style: context.ldisplay(
                      size: 28,
                      weight: FontWeight.w700,
                      color: c.ink,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      prefixText: '¥ ',
                      prefixStyle: context.ldisplay(
                        size: 18,
                        weight: FontWeight.w700,
                        color: c.inkSoft,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                Pressable(
                  onTap: () async {
                    final picked = await showLedgerDateTimePicker(
                      context,
                      initial: edit.draft.occurredAt,
                    );
                    if (picked == null) return;
                    setState(() {
                      edit.draft = edit.draft.copyWith(occurredAt: picked);
                    });
                  },
                  scale: .96,
                  hoverLift: 0,
                  child: LedgerChip(
                    text:
                        '${edit.draft.occurredAt.month}月${edit.draft.occurredAt.day}日 '
                        '${LedgerDates.timeLabel(edit.draft.occurredAt)}',
                    icon: AppIcons.clock,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 24,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final item in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Pressable(
                        onTap: () => setState(() {
                          edit.draft = edit.draft.copyWith(categoryId: item.id);
                        }),
                        scale: .95,
                        hoverLift: 0,
                        child: LedgerChip(
                          text: item.name,
                          color: item.tint,
                          filled: item.id == category.id,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: edit.note,
              maxLines: 1,
              style: context.lui(size: CitroType.meta, color: c.ink2),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '备注（商户、商品…）',
                hintStyle: context.lui(
                  size: CitroType.meta,
                  color: c.inkSoft.withAlpha(160),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
