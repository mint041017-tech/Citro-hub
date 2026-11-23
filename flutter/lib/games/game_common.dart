import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/models.dart';
import '../pages/me_page.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
import 'game_theme.dart';

/// “正在玩”列表每 4s 刷新一次；内容没变时不触发整页重建。
bool sameLiveList(List<dynamic> a, List<dynamic> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x is! Map || y is! Map) return false;
    if ('${x['name']}' != '${y['name']}' ||
        '${x['progress']}' != '${y['progress']}' ||
        '${x['av']}' != '${y['av']}' ||
        (x['you'] == true) != (y['you'] == true)) {
      return false;
    }
  }
  return true;
}

class GamePageShell extends StatefulWidget {
  final String gameKey;
  final String title;
  final String subtitle;
  final Widget child;
  final String note;
  final ValueNotifier<String>? liveProgress;
  final List<Widget> extraHud;

  const GamePageShell({
    super.key,
    required this.gameKey,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.note,
    this.liveProgress,
    this.extraHud = const [],
  });

  @override
  State<GamePageShell> createState() => _GamePageShellState();
}

class _GamePageShellState extends State<GamePageShell> {
  Timer? _liveTimer;
  List<dynamic> _live = [];
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _startLive();
  }

  Future<void> _startLive() async {
    await _tickLive();
    _liveTimer = Timer.periodic(const Duration(seconds: 4), (_) => _tickLive());
  }

  Future<void> _tickLive() async {
    if (_leaving) return;
    final state = AppState.instance;
    try {
      final j = await Api.gameLive(
        widget.gameKey,
        progress: widget.liveProgress?.value ?? '',
        name: state.loggedIn ? null : state.guestName,
        gid: state.loggedIn ? null : state.gid,
      );
      final list = (j['list'] as List?) ?? [];
      if (mounted && !sameLiveList(_live, list)) {
        setState(() => _live = list);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _leaving = true;
    _liveTimer?.cancel();
    final state = AppState.instance;
    Api.gameLive(
      widget.gameKey,
      leave: true,
      name: state.loggedIn ? null : state.guestName,
      gid: state.loggedIn ? null : state.gid,
    ).catchError((_) => <String, dynamic>{});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final duo = CitroForm.duoDevice(MediaQuery.sizeOf(context));
    final state = context.app;
    return Scaffold(
      backgroundColor: c.bg,
      body: CitroBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: Row(
                  children: [
                    if (!duo)
                      Pressable(
                        onTap: () => Navigator.of(context).maybePop(),
                        borderRadius: BorderRadius.circular(CitroColors.radii.button),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(CitroColors.radii.button),
                            border: Border.all(color: c.line),
                            boxShadow: CitroColors.shadows.sm(c),
                          ),
                          child: Row(
                            children: [
                              AppIcon(
                                strokeSvg(AppIcons.arrowLeft, width: 2.2),
                                size: 15,
                                color: c.ink2,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '返回',
                                style: context.body(
                                  size: CitroType.caption,
                                  weight: CitroType.strong,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/logo.webp',
                          width: 22,
                          cacheWidth: 66,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '游戏空间',
                          style: context.heading(size: CitroType.body, color: c.ink),
                        ),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => showGameAccount(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(CitroColors.radii.button),
                          border: Border.all(color: c.line),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: state.loggedIn ? c.accent : c.hl,
                                image: state.user?.av != null
                                    ? DecorationImage(
                                        image: ResizeImage(
                                          NetworkImage(
                                            Api.imageUrl(state.user!.av),
                                          ),
                                          width: 60,
                                        ),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: state.user?.av != null
                                  ? null
                                  : Center(
                                      child: Text(
                                        state.displayName.isEmpty
                                            ? '友'
                                            : state.displayName[0],
                                        style: context.body(
                                          size: 10,
                                          weight: FontWeight.w700,
                                          color: c.accentText,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              state.loggedIn ? state.displayName : '游客',
                              style: context.body(size: CitroType.small, color: c.ink2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: context.heading(size: CitroType.heading, color: c.ink),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: context.body(
                          size: CitroType.meta,
                          color: c.inkSoft,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (widget.extraHud.isNotEmpty) ...[
                        Row(children: widget.extraHud),
                        const SizedBox(height: 8),
                      ],
                      widget.child,
                      if (_live.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        LivePanel(list: _live),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        widget.note,
                        style: context.body(
                          size: CitroType.small,
                          color: c.inkSoft,
                          height: 1.65,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showGameAccount(BuildContext context) async {
  final state = context.app;
  if (state.loggedIn) {
    openMePage(context);
    return;
  }
  final controller = TextEditingController(
    text: state.guestName.replaceFirst('游客·', ''),
  );
  await showCitroDialog(
    context,
    builder: (ctx) => PaperDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('修改游客昵称', style: context.heading(size: 20)),
          const SizedBox(height: 6),
          Text(
            '前缀「游客·」固定，后面填 2-5 个中文',
            style: context.body(size: 11, color: ctx.c.inkSoft),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            maxLength: 5,
            style: context.body(size: CitroType.body),
            decoration: InputDecoration(
              counterText: '',
              prefixText: '游客·',
              filled: true,
              fillColor: ctx.c.surface2,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CitroColors.radii.field),
                borderSide: BorderSide(color: ctx.c.line2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CitroColors.radii.field),
                borderSide: BorderSide(color: ctx.c.accent),
              ),
            ),
          ),
          const SizedBox(height: 14),
          AccentButton(
            text: '保存',
            onTap: () async {
              final v = controller.text.trim();
              if (!RegExp(r'^[\u4e00-\u9fa5]{2,5}$').hasMatch(v)) {
                AppToast.show(ctx, '请输入 2-5 个中文');
                return;
              }
              await state.updateGuestName('游客·$v');
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    ),
  );
}

class LivePanel extends StatelessWidget {
  final List<dynamic> list;
  const LivePanel({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.sm(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                '正在玩 · ${list.length} 人',
                style: context.body(
                  size: CitroType.small,
                  weight: CitroType.strong,
                  color: c.ink2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          for (final raw in list.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${raw['name'] ?? '游客'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: CitroType.small,
                        color: (raw['you'] == true) ? c.accentInk : c.inkSoft,
                      ),
                    ),
                  ),
                  Text(
                    '${raw['progress'] ?? ''}',
                    style: context.body(size: CitroType.micro, color: c.inkSoft),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showGameLeaderboard(
  BuildContext context, {
  required String game,
  required String title,
  List<(String, String)> difficulties = const [],
  String initial = '',
  bool aiSplit = false,
}) async {
  await showCitroSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _LeaderboardSheet(
      game: game,
      title: title,
      difficulties: difficulties,
      initial: initial,
      aiSplit: aiSplit,
    ),
  );
}

/// 2048 榜单双分区（web index.html 17459-17467）：固定 AI 名单 + 十万分以上
/// 自动归 AI 榜，其余进玩家榜；分区是纯前端过滤，接口不区分。
const List<String> kAiBoardNames = <String>[
  'Kimi-K3（变态版）',
  '小橙子AI替身',
  'Kimi-K3',
  'GLM-5.3',
  'Seed-2.1 Pro',
  'Deepseek-V4.1-Flash',
  'Seed-Evolving',
  '豆包2.0',
  '月之暗面',
];

const int kAiBoardScoreThreshold = 100000;

bool g2048IsAiRecord(String name, int score) {
  if (kAiBoardNames.contains(name)) return true;
  return score > kAiBoardScoreThreshold;
}

// ---------------------------------------------------------------------------
// 排行榜版式
// ---------------------------------------------------------------------------

/// 榜单行几何（手机弹层与平板侧栏共用）。
///
/// 两个容器宽度差得很远（弹层 ~360px、侧栏 ~210px），所以这里统一的是
/// 「行高 / 间距 / 省略 / 数字对齐」的规则，而不是把两边做成同一宽度：
/// 行高由头像与上下内边距决定，行间距固定，名字超长省略，分数等宽右对齐。
const double _rankBadgeSize = 26;
const double _rankAvatarSize = 28;
const double _rankColumnGap = 8;
const double _rankScoreMax = 88;
const double _rankRowPadH = 12;
const double _rankRowPadV = 6;
const double _rankRowGap = 4;

/// 榜单行的时间：与社区同一套「刚刚 / N分钟前 / 日期」口吻。
/// [ts] 秒与毫秒都兼容（历史数据两种都出现过），缺失时返回 null 不显示。
String? rankTimeAgo(int ts) {
  if (ts <= 0) return null;
  final ms = ts < 100000000000 ? ts * 1000 : ts;
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  if (diff < 60000) return '刚刚';
  if (diff < 3600000) return '${diff ~/ 60000}分钟前';
  if (diff < 86400000) return '${diff ~/ 3600000}小时前';
  if (diff < 86400000 * 7) return '${diff ~/ 86400000}天前';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}.${d.month}.${d.day}';
}

/// 加载占位：转圈 + 一句话，比裸的 CircularProgressIndicator 有交代。
class _RankSpinner extends StatelessWidget {
  const _RankSpinner();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          '正在加载排行榜…',
          style: context.body(size: CitroType.small, color: c.inkSoft),
        ),
      ],
    );
  }
}

/// 榜单三态占位（失败 / 空态）统一用纸面 + 图标 + 一句话，
/// 切换难度时列表区不会因为换了一套组件而跳动。
class _RankPlaceholder extends StatelessWidget {
  const _RankPlaceholder({
    required this.title,
    this.icon,
    this.hint,
    this.onRetry,
  });

  final String title;
  final String? icon;
  final String? hint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      // 列表区很矮时（矮屏 + 双层分榜 + 我的排名底条）允许滚动，不撑破弹层。
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AppIcon(strokeSvg(icon!, width: 2), size: 32, color: c.inkSoft),
              const SizedBox(height: AppSpacing.x2),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.caption, color: c.inkSoft),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: context.body(size: CitroType.micro, color: c.inkSoft),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.x2),
              SizedBox(
                width: 150,
                child: AccentButton(text: '重新加载', onTap: onRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 表头：与 [_RankRow] 的列一一对齐（名次 / 玩家 / 分数）。
/// 没有表头时，名次徽章、头像和分数各自为政，看不出哪列是哪列。
///
/// [padH] 与同一容器里 [_RankRow] 的左右内边距保持一致，两处才列列对齐；
/// 手机弹层取 16（跟着标题行），平板侧栏取 0（跟着侧栏自己的标题）。
class _RankHeader extends StatelessWidget {
  const _RankHeader({this.padH = _rankRowPadH});

  final double padH;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = context.body(size: CitroType.micro, color: c.inkSoft);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: padH,
            vertical: AppSpacing.x1,
          ),
          child: Row(
            children: [
              SizedBox(
                width: _rankBadgeSize,
                child: Text('名次', textAlign: TextAlign.center, style: label),
              ),
              const SizedBox(width: _rankColumnGap),
              // 头像 + 间距 + 名字合起来是「玩家」一列。
              Expanded(child: Text('玩家', style: label)),
              SizedBox(
                width: _rankColumnGap + _rankScoreMax,
                child: Text('分数', textAlign: TextAlign.right, style: label),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padH),
          child: CitroDivider(color: c.line),
        ),
      ],
    );
  }
}

/// 榜单行：名次徽章 + 头像 + 名字（单行省略）+ 分数（等宽右对齐）+ 时间。
class _RankRow extends StatelessWidget {
  const _RankRow({required this.row, this.padH = _rankRowPadH});

  final BoardEntry row;
  final double padH;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = row.rank <= 3;
    final badgeColor = row.rank == 1
        ? c.accent
        : (top ? c.accentLt : c.surface2);
    final badgeFg = row.rank == 1
        ? c.accentText
        : (top ? c.accentInk : c.inkSoft);
    final time = rankTimeAgo(row.ts);
    return Container(
      margin: const EdgeInsets.only(bottom: _rankRowGap),
      padding: EdgeInsets.symmetric(
        horizontal: padH,
        vertical: _rankRowPadV,
      ),
      decoration: BoxDecoration(
        color: row.you ? c.accentLt.withAlpha(150) : Colors.transparent,
        borderRadius: BorderRadius.circular(CitroColors.radii.small),
        border: row.you ? Border.all(color: c.accent.withAlpha(120)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: _rankBadgeSize,
            height: _rankBadgeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
            child: Text(
              '${row.rank}',
              style: context.hand(
                size: CitroType.small,
                weight: CitroType.strong,
                color: badgeFg,
              ),
            ),
          ),
          const SizedBox(width: _rankColumnGap),
          Container(
            width: _rankAvatarSize,
            height: _rankAvatarSize,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface2),
            clipBehavior: Clip.antiAlias,
            child: row.av != null
                ? Image.network(
                    Api.imageUrl(row.av),
                    fit: BoxFit.cover,
                    cacheWidth: 84,
                  )
                : Center(
                    child: Text(
                      row.name.isEmpty ? '?' : row.name[0],
                      style: context.body(size: CitroType.small, color: c.ink2),
                    ),
                  ),
          ),
          const SizedBox(width: _rankColumnGap),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(
                size: CitroType.meta,
                weight: CitroType.strong,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: _rankColumnGap),
          // 分数列：超长时省略而不是撑破行；时间只做这一列的注脚。
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _rankScoreMax),
                child: Text(
                  '${row.score}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: context.hand(
                    size: CitroType.bodyLg,
                    weight: CitroType.strong,
                    color: c.accentInk,
                  ),
                ),
              ),
              if (time != null)
                Text(
                  time,
                  style: context.body(size: CitroType.small, color: c.inkSoft),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 「我的排名」底条：弹层与侧栏共用同一枚胶囊。
class _RankMeFooter extends StatelessWidget {
  const _RankMeFooter({required this.me});

  final Map<String, dynamic> me;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.accentLt.withAlpha(140),
        borderRadius: BorderRadius.circular(CitroColors.radii.small),
        border: Border.all(color: c.accent.withAlpha(100)),
      ),
      child: Text(
        '我的排名：第 ${me['rank'] ?? '—'} 名 · ${me['score'] ?? 0} 分',
        textAlign: TextAlign.center,
        style: context.body(
          size: CitroType.small,
          weight: CitroType.strong,
          color: c.accentInk,
        ),
      ),
    );
  }
}

/// 榜单列表体：表头固定，列表区在「加载 / 失败 / 空 / 有数据」之间切换。
///
/// 刷新时保留旧榜单，只在列表顶挂一条细进度；整页换成转圈会让切换难度
/// 看起来像「闪了一下」，还会把滚动位置弄丢。
class _RankBoard extends StatelessWidget {
  const _RankBoard({
    required this.loading,
    required this.error,
    required this.rows,
    required this.emptyTitle,
    this.onRetry,
    this.padH = _rankRowPadH,
  });

  final bool loading;
  final String? error;
  final List<BoardEntry> rows;
  final String emptyTitle;
  final VoidCallback? onRetry;
  final double padH;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Stack(
      children: [
        Positioned.fill(
          child: loading && rows.isEmpty
              ? const Center(child: _RankSpinner())
              : error != null && rows.isEmpty
                  ? _RankPlaceholder(
                      icon: AppIcons.trophy,
                      title: '排行榜暂时无法加载',
                      hint: '网络异常，请稍后重试',
                      onRetry: onRetry,
                    )
                  : rows.isEmpty
                      ? _RankPlaceholder(icon: AppIcons.trophy, title: emptyTitle)
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.x1,
                            bottom: AppSpacing.x1,
                          ),
                          itemCount: rows.length,
                          itemBuilder: (_, i) => _RankRow(row: rows[i], padH: padH),
                        ),
        ),
        if (loading && rows.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: c.accent,
              backgroundColor: c.line,
            ),
          ),
      ],
    );
  }
}

/// 排行榜分榜切换（手机弹窗 / 平板侧栏共用）。
///
/// 重叠数独有 6 个分榜，单行放不下；这里用 [Wrap] 自动换行，
/// 避免最右侧的档位被屏幕裁掉、又没有横向滑动的入口。
class GameDiffTabs extends StatelessWidget {
  const GameDiffTabs({
    super.key,
    required this.difficulties,
    required this.selected,
    required this.onSelect,
  });

  final List<(String, String)> difficulties;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => _GameChipTabs(
        items: difficulties,
        selected: selected,
        onSelect: onSelect,
      );
}

/// 榜单胶囊：手机 AI 榜 / 难度与平板 AI 榜 / 难度四处共用同一套选中态，
/// 避免同一个功能在弹层和侧栏里是两种选中色、两种按压手感。
class _GameChipTabs extends StatelessWidget {
  const _GameChipTabs({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<(String, String)> items;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Wrap(
      spacing: AppSpacing.x1,
      runSpacing: AppSpacing.x1,
      children: [
        for (final item in items)
          Pressable(
            onTap: () => onSelect(item.$1),
            scale: .97,
            hoverLift: 0,
            borderRadius: BorderRadius.circular(CitroColors.radii.chip),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected == item.$1 ? c.accentLt : c.surface2,
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                border: Border.all(
                  color: selected == item.$1 ? c.accent : c.line,
                ),
              ),
              child: Text(
                item.$2,
                style: context.body(
                  size: CitroType.caption,
                  weight: CitroType.strong,
                  color: selected == item.$1 ? c.accentText : c.inkSoft,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LeaderboardSheet extends StatefulWidget {
  final String game;
  final String title;
  final List<(String, String)> difficulties;
  final String initial;
  final bool aiSplit;
  const _LeaderboardSheet({
    required this.game,
    required this.title,
    this.difficulties = const [],
    this.initial = '',
    this.aiSplit = false,
  });

  @override
  State<_LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<_LeaderboardSheet> {
  late String diff = widget.initial.isEmpty
      ? (widget.difficulties.isNotEmpty ? widget.difficulties.first.$1 : '')
      : widget.initial;

  /// AI 榜 / 玩家榜（仅 2048 等双分区榜用）。
  late String boardTab = 'player';
  List<BoardEntry> rows = [];
  bool loading = true;
  String? error;
  Map<String, dynamic>? me;

  String get gameKey =>
      widget.difficulties.isEmpty ? widget.game : '${widget.game}:$diff';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// web gamesLoadBoard：拉到全量榜后按当前分榜前端过滤并重排名次。
  List<BoardEntry> get _shownRows {
    if (!widget.aiSplit) return rows;
    final filtered = rows.where((r) {
      final isAi = g2048IsAiRecord(r.name, r.score);
      return boardTab == 'ai' ? isAi : !isAi;
    }).toList();
    return [
      for (var i = 0; i < filtered.length; i++)
        BoardEntry(
          rank: i + 1,
          name: filtered[i].name,
          av: filtered[i].av,
          score: filtered[i].score,
          ts: filtered[i].ts,
          you: filtered[i].you,
        ),
    ];
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final state = AppState.instance;
    try {
      final j = await Api.gameBoard(
        gameKey,
        name: state.loggedIn ? null : state.guestName,
        gid: state.loggedIn ? null : state.gid,
      );
      if (!mounted) return;
      setState(() {
        rows = ((j['board'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => BoardEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        me = j['me'] is Map ? Map<String, dynamic>.from(j['me'] as Map) : null;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      // 榜上已有内容时保留旧榜单：整页换成错误态会让人以为榜单没了。
      if (rows.isEmpty) {
        setState(() => error = e.toString());
      } else {
        AppToast.show(context, '排行榜刷新失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final height = MediaQuery.sizeOf(context).height * .68;
    final emptyTitle = widget.aiSplit && boardTab == 'ai'
        ? 'AI 榜还没有成绩 · 十万分以上自动归入'
        : '还没有人上榜，快来抢第一';
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CitroColors.radii.modal),
        ),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.lg(c),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: c.line2,
                  borderRadius: BorderRadius.circular(CitroColors.radii.xs / 2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  AppIcon(
                    strokeSvg(AppIcons.trophy, width: 2),
                    size: 18,
                    color: c.accentInk,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${widget.title} · 全站排行',
                      style: context.heading(size: 18),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.close, width: 2.4),
                          size: 18,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.aiSplit) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _GameChipTabs(
                  items: const [('player', '玩家榜'), ('ai', 'AI 榜')],
                  selected: boardTab,
                  onSelect: (key) {
                    if (key == boardTab) return;
                    setState(() => boardTab = key);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
            ],
            if (widget.difficulties.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GameDiffTabs(
                  difficulties: widget.difficulties,
                  selected: diff,
                  onSelect: (key) {
                    if (key == diff) return;
                    setState(() => diff = key);
                    _load();
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _RankHeader(padH: 16),
                  Expanded(
                    child: _RankBoard(
                      loading: loading,
                      error: error,
                      rows: _shownRows,
                      emptyTitle: emptyTitle,
                      onRetry: _load,
                      padH: 16,
                    ),
                  ),
                ],
              ),
            ),
            if (me != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: _RankMeFooter(me: me!),
              ),
          ],
        ),
      ),
    );
  }
}

class GameTabletRankRail extends StatefulWidget {
  final String game;
  final String title;
  final List<(String, String)> difficulties;
  final String initial;
  final bool aiSplit;
  final bool enabled;

  /// 左侧栏已在返回按钮旁显示「排行榜」时可以关掉内部标题，避免重复。
  final bool showTitle;

  const GameTabletRankRail({
    super.key,
    required this.game,
    required this.title,
    this.difficulties = const [],
    this.initial = '',
    this.aiSplit = false,
    this.enabled = true,
    this.showTitle = true,
  });

  @override
  State<GameTabletRankRail> createState() => _GameTabletRankRailState();
}

class _GameTabletRankRailState extends State<GameTabletRankRail> {
  late String diff = widget.initial.isEmpty
      ? (widget.difficulties.isNotEmpty ? widget.difficulties.first.$1 : '')
      : widget.initial;
  String boardTab = 'player';
  List<BoardEntry> rows = [];
  Map<String, dynamic>? me;
  bool loading = true;
  String? error;

  String get _gameKey =>
      widget.difficulties.isEmpty ? widget.game : '${widget.game}:$diff';

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _load();
    } else {
      loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant GameTabletRankRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initial.isEmpty
        ? (widget.difficulties.isNotEmpty ? widget.difficulties.first.$1 : '')
        : widget.initial;
    // 只在「游戏变了 / 游戏内难度真的变了」时跟随；父级每 4s 的 live 心跳
    // 也会重建本组件，绝不能借此把用户手选的榜单分段重置回去。
    if (widget.game != oldWidget.game || widget.initial != oldWidget.initial) {
      diff = next;
      if (widget.enabled) _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final app = AppState.instance;
    try {
      final json = await Api.gameBoard(
        _gameKey,
        name: app.loggedIn ? null : app.guestName,
        gid: app.loggedIn ? null : app.gid,
      );
      if (!mounted) return;
      setState(() {
        rows = ((json['board'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => BoardEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        me = json['me'] is Map
            ? Map<String, dynamic>.from(json['me'] as Map)
            : null;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      // 榜上已有内容时保留旧榜单，只给一条轻提示（同手机弹层）。
      if (rows.isEmpty) {
        setState(() => error = e.toString());
      } else {
        AppToast.show(context, '排行榜刷新失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<BoardEntry> get _shownRows {
    if (!widget.aiSplit) return rows;
    final filtered = rows.where((row) {
      final isAi = g2048IsAiRecord(row.name, row.score);
      return boardTab == 'ai' ? isAi : !isAi;
    }).toList();
    return [
      for (var i = 0; i < filtered.length; i++)
        BoardEntry(
          rank: i + 1,
          name: filtered[i].name,
          av: filtered[i].av,
          score: filtered[i].score,
          ts: filtered[i].ts,
          you: filtered[i].you,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final emptyTitle = widget.aiSplit && boardTab == 'ai'
        ? 'AI 榜还没有成绩 · 十万分以上自动归入'
        : '还没有人上榜，快来抢第一';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle)
          Row(
            children: [
              AppIcon(
                strokeSvg(AppIcons.trophy, width: 2),
                size: 18,
                color: c.accentInk,
              ),
              const SizedBox(width: 6),
              Text(
                '排行榜',
                style: context.heading(size: 18, color: c.ink),
              ),
              const SizedBox(width: AppSpacing.x1),
              Flexible(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.body(size: 11, color: c.inkSoft),
                ),
              ),
            ],
          ),
        if (widget.showTitle) const SizedBox(height: 10),
        if (widget.difficulties.isNotEmpty) ...[
          _GameChipTabs(
            items: widget.difficulties,
            selected: diff,
            onSelect: (key) {
              if (diff == key) return;
              setState(() => diff = key);
              _load();
            },
          ),
          const SizedBox(height: AppSpacing.x1),
        ],
        if (widget.aiSplit) ...[
          _GameChipTabs(
            items: const [('player', '玩家榜'), ('ai', 'AI 榜')],
            selected: boardTab,
            onSelect: (key) {
              if (boardTab == key) return;
              setState(() => boardTab = key);
            },
          ),
          const SizedBox(height: AppSpacing.x1),
        ],
        const _RankHeader(padH: 0),
        Expanded(
          child: _RankBoard(
            loading: loading,
            error: error,
            rows: _shownRows,
            emptyTitle: emptyTitle,
            onRetry: _load,
            padH: 0,
          ),
        ),
        if (me != null) ...[
          const SizedBox(height: AppSpacing.x1),
          _RankMeFooter(me: me!),
        ],
      ],
    );
  }
}

String fmtDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
