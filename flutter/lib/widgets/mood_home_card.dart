import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/native.dart';
import '../theme/tokens.dart';
import '../todo/todo_models.dart';
import '../todo/todo_mood.dart';
import '../todo/todo_store.dart';
import '../todo/todo_ui.dart';
import 'paper.dart';

/// 首页心情卡：先看到最近一次；卡片空间越大，今天的记录展开得越多。
class MoodHomeCard extends StatelessWidget {
  const MoodHomeCard({super.key});

  String _hm(MoodEntry m) =>
      '${m.ts.hour.toString().padLeft(2, '0')}:${m.ts.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListenableBuilder(
      listenable: TodoStore.instance,
      builder: (context, _) {
        final store = TodoStore.instance;
        final today = [...store.moodsOn(DateTime.now())]
          ..sort((a, b) => a.ts.compareTo(b.ts));
        final latest = today.isEmpty ? null : today.last;
        return PaperCard(
          tapeColor: c.tape,
          tapeAngle: -1.6,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          onTap: () =>
              showMoodDetail(context, initial: latest?.ts ?? DateTime.now()),
          child: LayoutBuilder(
            builder: (context, box) {
              final h = box.maxHeight;
              // 三档：一行极简 / 一条摘要 / 按高度铺开全部记录。
              if (h.isFinite && h < 124) return _tiny(context, c, latest);
              if (h.isFinite && h >= 148) return _many(context, c, today);
              return _one(context, c, latest, today.length);
            },
          ),
        );
      },
    );
  }

  Widget _title(BuildContext context, Color ink) => Row(
    children: [
      AppIcon(strokeSvg(AppIcons.smile, width: 1.9), size: 18, color: ink),
      const SizedBox(width: 6),
      Text(
        '心情',
        style: context.heading(size: 13, color: ink, letterSpacing: .3),
      ),
    ],
  );

  /// 极小尺寸：表情 + 最近一条 + 记录按钮，压成一行。
  Widget _tiny(BuildContext context, CitroColors c, MoodEntry? latest) {
    if (latest == null) {
      return Row(
        children: [
          _title(context, c.accentInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '今天还没记录',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(size: CitroType.caption, color: c.inkSoft),
            ),
          ),
          _recordChip(context, c),
        ],
      );
    }
    return Pressable(
      onTap: () => showMoodDetail(context, initial: latest.ts),
      scale: .99,
      child: Row(
        children: [
          MoodFace(kind: latest.kind, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${latest.kind.label} · ${_hm(latest)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.ui(
                size: CitroType.bodyLg,
                weight: CitroType.strong,
                color: c.ink2,
              ),
            ),
          ),
          _recordChip(context, c),
        ],
      ),
    );
  }

  Widget _one(
    BuildContext context,
    CitroColors c,
    MoodEntry? latest,
    int count,
  ) {
    final hm = latest == null ? '' : _hm(latest);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _title(context, c.accentInk),
            const Spacer(),
            if (count == 0)
              Text(
                '今天还没记录',
                style: context.ui(size: CitroType.caption, color: c.inkSoft),
              )
            else
              _recordChip(context, c),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (latest != null)
              MoodFace(kind: latest.kind, size: 38)
            else
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.accent.withAlpha(20),
                  shape: BoxShape.circle,
                  border: Border.all(color: c.line),
                ),
                child: Center(
                  child: AppIcon(
                    strokeSvg(AppIcons.smile, width: 1.8),
                    size: 18,
                    color: c.inkSoft,
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    latest == null ? '今天还没有记录' : latest.kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.ui(
                      size: CitroType.title,
                      weight: CitroType.strong,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    latest == null ? '记下此刻，方便以后回看。' : '最近一次 $hm',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.ui(
                      size: CitroType.caption,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 小尺寸卡片也保留一个紧凑的「记录」入口。
  Widget _recordChip(BuildContext context, CitroColors c) => Pressable(
    onTap: () => showMoodSheet(context),
    scale: .94,
    child: Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.accent.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.accent.withAlpha(80)),
      ),
      child: Text(
        '记录',
        style: context.ui(
          size: CitroType.caption,
          weight: CitroType.strong,
          color: c.accentInk,
        ),
      ),
    ),
  );

  Widget _many(BuildContext context, CitroColors c, List<MoodEntry> today) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _title(context, c.accentInk),
            const SizedBox(width: 6),
            Text(
              today.isEmpty ? '' : '今天 ${today.length} 次',
              style: context.ui(size: CitroType.caption, color: c.inkSoft),
            ),
            const Spacer(),
            Pressable(
              onTap: () => showMoodSheet(context),
              scale: .94,
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.accent.withAlpha(80)),
                ),
                child: Text(
                  '记录',
                  style: context.ui(
                    size: CitroType.caption,
                    weight: CitroType.strong,
                    color: c.accentInk,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: today.isEmpty
              ? Text(
                  '今天还没有记录，点「记录」选一个此刻的心情。',
                  style: context.ui(
                    size: CitroType.caption,
                    color: c.inkSoft,
                    height: 1.6,
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: today.length,
                  itemBuilder: (context, i) {
                    // 新的在上：最近一次永远第一眼看到。
                    final m = today[today.length - 1 - i];
                    return Pressable(
                      onTap: () => showMoodDetail(context, initial: m.ts),
                      scale: .99,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            MoodFace(kind: m.kind, size: 26),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                m.kind.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.ui(
                                  size: CitroType.body,
                                  color: c.ink2,
                                ),
                              ),
                            ),
                            Text(
                              _hm(m),
                              style: context.ui(
                                size: CitroType.caption,
                                color: c.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
