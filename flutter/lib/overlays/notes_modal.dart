import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

Future<void> showNotesModal(BuildContext context) async {
  if (!context.app.loggedIn) {
    AppToast.show(context, '登录后才能使用笔记');
    return;
  }
  await showCitroDialog(context, builder: (ctx) => const _NotesDialog());
}

class _NotesDialog extends StatefulWidget {
  const _NotesDialog();
  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  List<Note> notes = [];
  bool loading = true;
  bool editing = false;
  String? editingId;
  final title = TextEditingController();
  final content = TextEditingController();
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    title.dispose();
    content.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await Api.notes();
      if (mounted) setState(() => notes = list);
    } on Exception catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _startNew() {
    setState(() {
      editing = true;
      editingId = null;
      title.text = '';
      content.text = '';
    });
  }

  void _startEdit(Note n) {
    setState(() {
      editing = true;
      editingId = n.id;
      title.text = n.title;
      content.text = n.content;
    });
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty && content.text.trim().isEmpty) {
      AppToast.show(context, '笔记不能为空');
      return;
    }
    try {
      final n = await Api.saveNote(
        id: editingId,
        title: title.text.trim(),
        content: content.text,
      );
      setState(() {
        notes.removeWhere((e) => e.id == n.id);
        notes.insert(0, n);
        editing = false;
      });
      if (mounted) AppToast.show(context, '已保存');
    } on Exception catch (e) {
      if (mounted) AppToast.show(context, e.toString());
    }
  }

  Future<void> _delete() async {
    if (editingId == null) return;
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('删除这条笔记？', style: context.heading(size: 20)),
            const SizedBox(height: 8),
            Text(
              '删除后无法恢复',
              style: context.body(size: 12, color: context.c.inkSoft),
            ),
            const SizedBox(height: 18),
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
    await Api.deleteNote(editingId!);
    setState(() {
      notes.removeWhere((e) => e.id == editingId);
      editing = false;
    });
    if (mounted) AppToast.show(context, '已删除');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(maxWidth: 440, child: editing ? _editor(c) : _list(c));
  }

  Widget _list(CitroColors c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '我的笔记',
          textAlign: TextAlign.center,
          style: context.heading(size: 22),
        ),
        const SizedBox(height: 3),
        Text(
          '${notes.length} 条记录 · 每一个灵光乍现',
          textAlign: TextAlign.center,
          style: context.body(size: 11, color: c.inkSoft),
        ),
        const SizedBox(height: 14),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error!,
              style: context.body(size: 12, color: c.stamp),
              textAlign: TextAlign.center,
            ),
          )
        else if (notes.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                Text('📝', style: TextStyle(fontSize: 30)),
                const SizedBox(height: 8),
                Text(
                  '还没有笔记，点下面新建',
                  style: context.body(size: 12, color: c.inkSoft),
                ),
              ],
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final n = notes[i];
                return Pressable(
                  onTap: () => _startEdit(n),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.title.isEmpty ? '无标题' : n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.heading(size: 14.5, color: c.ink),
                        ),
                        if (n.content.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            n.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.body(
                              size: 12,
                              color: c.inkSoft,
                              height: 1.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 5),
                        Text(
                          _time(n.updated),
                          style: context.body(
                            size: 10,
                            color: c.inkSoft.withAlpha(180),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 14),
        AccentButton(text: '新建笔记', onTap: _startNew),
      ],
    );
  }

  Widget _editor(CitroColors c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Pressable(
              onTap: () => setState(() => editing = false),
              child: Row(
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.arrowLeft, width: 2.2),
                    size: 17,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '返回',
                    style: context.body(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: c.accentInk,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              editingId == null ? '新建笔记' : '编辑笔记',
              style: context.heading(size: 17),
            ),
            const Spacer(),
            const SizedBox(width: 44),
          ],
        ),
        const SizedBox(height: 16),
        CitroField(label: '', hint: '标题（可选）', controller: title, maxLength: 50),
        const SizedBox(height: 10),
        CitroField(label: '', hint: '写点什么…', controller: content, maxLines: 10),
        const SizedBox(height: 16),
        Row(
          children: [
            if (editingId != null) ...[
              Expanded(
                child: AccentButton(text: '删除', outlined: true, onTap: _delete),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: AccentButton(text: '保存', onTap: _save),
            ),
          ],
        ),
      ],
    );
  }

  String _time(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
