import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/cook_library.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

Future<List<String>?> showIngredientLibrary(
  BuildContext context, {
  String title = '食材库',
  bool multi = true,
  List<String> selected = const [],
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8A23211C),
    builder: (_) =>
        _IngredientLibrarySheet(title: title, multi: multi, selected: selected),
  );
}

class _IngredientLibrarySheet extends StatefulWidget {
  final String title;
  final bool multi;
  final List<String> selected;
  const _IngredientLibrarySheet({
    required this.title,
    required this.multi,
    required this.selected,
  });
  @override
  State<_IngredientLibrarySheet> createState() =>
      _IngredientLibrarySheetState();
}

class _IngredientLibrarySheetState extends State<_IngredientLibrarySheet> {
  final search = TextEditingController();
  late final List<String> picked = List<String>.from(widget.selected);

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _toggle(String name) {
    if (!widget.multi) {
      Navigator.of(context).pop([name]);
      return;
    }
    setState(() {
      if (picked.contains(name)) {
        picked.remove(name);
      } else {
        picked.add(name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final screen = MediaQuery.sizeOf(context).height;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final height = math.min(screen * .88, screen - insets - 12);
    final keyword = cookNormName(search.text.trim());
    final groups = <String, List<String>>{};
    var shown = 0;
    for (final entry in cookLibrary.entries) {
      final hits = entry.value
          .where((n) => keyword.isEmpty || cookNormName(n).contains(keyword))
          .toList();
      if (hits.isNotEmpty) {
        groups[entry.key] = hits;
        shown += hits.length;
      }
    }
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: c.line),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: c.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: context.heading(size: 21)),
                          const SizedBox(height: 1),
                          Text(
                            widget.multi ? '可多选，选完点「加入」' : '选一个食材',
                            style: context.body(size: 10, color: c.inkSoft),
                          ),
                        ],
                      ),
                    ),
                    _roundClose(c),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                        color: c.inkSoft,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: TextField(
                          controller: search,
                          onChanged: (_) => setState(() {}),
                          style: context.body(size: 12.5),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            hintText: '搜食材，如：番茄',
                            hintStyle: context.body(size: 12, color: c.inkSoft),
                          ),
                        ),
                      ),
                      if (search.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            search.clear();
                            setState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: AppIcon(
                              strokeSvg(AppIcons.close, width: 2.2),
                              size: 13,
                              color: c.inkSoft,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.multi && picked.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: picked.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final name = picked[i];
                      return Center(
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.fromLTRB(10, 0, 5, 0),
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
                                style: context.body(
                                  size: 11,
                                  color: c.accentInk,
                                ),
                              ),
                              const SizedBox(width: 2),
                              GestureDetector(
                                onTap: () => _toggle(name),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
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
                      );
                    },
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                  child: Text(
                    keyword.isEmpty ? '共 $shown 样食材' : '找到 $shown 样食材',
                    style: context.body(size: 10, color: c.inkSoft),
                  ),
                ),
              ),
              Expanded(
                child: shown == 0
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '食材库里没有「${search.text.trim()}」\n换个词，或直接在输入框里手打',
                            textAlign: TextAlign.center,
                            style: context.body(
                              size: 12,
                              color: c.inkSoft,
                              height: 1.7,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                        children: [
                          for (final entry in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 7),
                              child: Row(
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: c.accent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    entry.key,
                                    style: context.heading(
                                      size: 14,
                                      color: c.accentInk,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${entry.value.length}',
                                    style: context.body(
                                      size: 9,
                                      color: c.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final name in entry.value) _chip(c, name),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                        ],
                      ),
              ),
              if (widget.multi)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: picked.isEmpty
                            ? null
                            : () => setState(picked.clear),
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: c.line2),
                          ),
                          child: Text(
                            '清空',
                            style: context.body(
                              size: 12,
                              weight: FontWeight.w600,
                              color: picked.isEmpty ? c.inkSoft : c.ink2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AccentButton(
                          text: picked.isEmpty
                              ? '加入食材'
                              : '加入 ${picked.length} 样食材',
                          height: 42,
                          onTap: picked.isEmpty
                              ? null
                              : () =>
                                    Navigator.of(context)
                                        .pop(List<String>.from(picked)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundClose(CitroColors c) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
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
            size: 21,
            color: c.inkSoft,
          ),
        ),
      ),
    );
  }

  Widget _chip(CitroColors c, String name) {
    final on = picked.contains(name);
    return GestureDetector(
      onTap: () => _toggle(name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: on ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? c.accent : c.line2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (on) ...[
              const Icon(Icons.check, size: 13, color: Color(0xFF2E2C22)),
              const SizedBox(width: 3),
            ],
            Text(
              name,
              style: context.body(
                size: 12,
                weight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? const Color(0xFF2E2C22) : c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
