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
  final VoidCallback? onNew;

  const GamePageShell({
    super.key,
    required this.gameKey,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.note,
    this.liveProgress,
    this.extraHud = const [],
    this.onNew,
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
      body: PaperBackground(
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: c.line),
                            boxShadow: CitroColors.shadows.paper(c),
                          ),
                          child: Row(
                            children: [
                              AppIcon(
                                strokeSvg(AppIcons.arrowLeft, width: 2.2),
                                size: 15,
                                color: c.ink2,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '返回',
                                style: context.body(
                                  size: 11.5,
                                  weight: FontWeight.w600,
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
                          style: context.heading(size: 15, color: c.ink),
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
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(999),
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
                                          color: c.accentInk,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              state.loggedIn ? state.displayName : '游客',
                              style: context.body(size: 10.5, color: c.ink2),
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
                        style: context.heading(size: 28, color: c.ink),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: context.body(
                          size: 12.5,
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
                          size: 10.5,
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
            style: context.body(size: 14),
            decoration: InputDecoration(
              counterText: '',
              prefixText: '游客·',
              filled: true,
              fillColor: ctx.c.surface2,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: ctx.c.line2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
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

class GamePill extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const GamePill({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.paper(c),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.body(size: 9.5, color: c.inkSoft)),
          const SizedBox(height: 1),
          Text(
            value,
            style: context.display(
              size: 18,
              weight: FontWeight.w700,
              color: color ?? c.ink,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class GameButton extends StatelessWidget {
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool small;

  const GameButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.primary = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: small ? 10 : 12,
          vertical: small ? 7 : 9,
        ),
        decoration: BoxDecoration(
          color: primary ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: primary ? c.accent : c.line),
          boxShadow: primary
              ? CitroColors.shadows.note(c)
              : CitroColors.shadows.paper(c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AppIcon(
                strokeSvg(icon!, width: 2.2),
                size: small ? 12 : 14,
                color: primary ? const Color(0xFF2E2C22) : c.accentInk,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: context.body(
                size: small ? 11 : 12,
                weight: FontWeight.w700,
                color: primary ? const Color(0xFF2E2C22) : c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LivePanel extends StatelessWidget {
  final List<dynamic> list;
  const LivePanel({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '正在玩 · ${list.length} 人',
                style: context.body(
                  size: 11,
                  weight: FontWeight.w700,
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
                        size: 10.5,
                        color: (raw['you'] == true) ? c.accentInk : c.inkSoft,
                      ),
                    ),
                  ),
                  Text(
                    '${raw['progress'] ?? ''}',
                    style: context.body(size: 10, color: c.inkSoft),
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
  await showModalBottomSheet(
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

  Widget _aiTab(String key, String label) {
    final c = context.c;
    final on = boardTab == key;
    return GestureDetector(
      onTap: () {
        if (boardTab == key) return;
        setState(() => boardTab = key);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: on ? c.hl : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? c.accent : c.line2),
        ),
        child: Text(
          label,
          style: context.body(
            size: 11.5,
            weight: FontWeight.w600,
            color: on ? c.accentInk : c.inkSoft,
          ),
        ),
      ),
    );
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
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final height = MediaQuery.sizeOf(context).height * .68;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 6),
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
                      style: context.heading(size: 17),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: AppIcon(
                        strokeSvg(AppIcons.close, width: 2.4),
                        size: 18,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.aiSplit) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _aiTab('player', '玩家榜'),
                    const SizedBox(width: 7),
                    _aiTab('ai', 'AI 榜'),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (widget.difficulties.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final d in widget.difficulties)
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => diff = d.$1);
                            _load();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: diff == d.$1 ? c.hl : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: diff == d.$1 ? c.accent : c.line2,
                              ),
                            ),
                            child: Text(
                              d.$2,
                              style: context.body(
                                size: 11,
                                weight: FontWeight.w600,
                                color: diff == d.$1 ? c.accentInk : c.inkSoft,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : error != null
                  ? Center(
                      child: Text(
                        error!,
                        style: context.body(size: 12, color: c.stamp),
                      ),
                    )
                  : _shownRows.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🏆', style: const TextStyle(fontSize: 40)),
                          const SizedBox(height: 8),
                          Text(
                            widget.aiSplit && boardTab == 'ai'
                                ? 'AI 榜还没有成绩 · 十万分以上自动归入'
                                : '还没有人上榜，快来抢第一',
                            style: context.body(size: 12, color: c.inkSoft),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      itemCount: _shownRows.length,
                      separatorBuilder: (_, __) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: DashedLine(color: c.line2.withAlpha(120)),
                      ),
                      itemBuilder: (_, i) {
                        final r = _shownRows[i];
                        final medal = r.rank == 1
                            ? '🥇'
                            : r.rank == 2
                            ? '🥈'
                            : r.rank == 3
                            ? '🥉'
                            : '${r.rank}';
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: r.you
                              ? BoxDecoration(
                                  color: c.hl.withAlpha(110),
                                  borderRadius: BorderRadius.circular(8),
                                )
                              : null,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 30,
                                child: Text(
                                  medal,
                                  textAlign: TextAlign.center,
                                  style: context.display(
                                    size: 15,
                                    color: c.inkSoft,
                                  ),
                                ),
                              ),
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c.hl,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: r.av != null
                                    ? Image.network(
                                        Api.imageUrl(r.av),
                                        fit: BoxFit.cover,
                                        cacheWidth: 90,
                                      )
                                    : Center(
                                        child: Text(
                                          r.name.isEmpty ? '?' : r.name[0],
                                          style: context.body(
                                            size: 12,
                                            color: c.accentInk,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.body(
                                    size: 12.5,
                                    weight: FontWeight.w600,
                                    color: c.ink,
                                  ),
                                ),
                              ),
                              Text(
                                '${r.score}',
                                style: context.display(
                                  size: 17,
                                  weight: FontWeight.w700,
                                  color: c.accentInk,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (me != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: Text(
                  '我的排名：第 ${me!['rank'] ?? '—'} 名 · ${me!['score'] ?? 0} 分',
                  textAlign: TextAlign.center,
                  style: context.body(size: 11.5, color: c.accentInk),
                ),
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

  const GameTabletRankRail({
    super.key,
    required this.game,
    required this.title,
    this.difficulties = const [],
    this.initial = '',
    this.aiSplit = false,
    this.enabled = true,
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
      if (mounted) setState(() => error = e.toString());
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIcon(
              strokeSvg(AppIcons.trophy, width: 2),
              size: 17,
              color: c.accentInk,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '排行榜',
                style: context.heading(size: 18, color: c.ink),
              ),
            ),
            Flexible(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.body(size: 10.5, color: c.inkSoft),
              ),
            ),
          ],
        ),
        if (widget.difficulties.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final item in widget.difficulties)
                GestureDetector(
                  onTap: () {
                    if (diff == item.$1) return;
                    setState(() => diff = item.$1);
                    _load();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: diff == item.$1 ? c.accent : c.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: diff == item.$1 ? c.accent : c.line,
                      ),
                    ),
                    child: Text(
                      item.$2,
                      style: context.body(
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: diff == item.$1
                            ? const Color(0xFF2E2C22)
                            : c.inkSoft,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (widget.aiSplit) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              for (final item in const [('player', '玩家榜'), ('ai', 'AI 榜')])
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: GestureDetector(
                    onTap: () => setState(() => boardTab = item.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: boardTab == item.$1 ? c.hl : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: boardTab == item.$1 ? c.accent : c.line,
                        ),
                      ),
                      child: Text(
                        item.$2,
                        style: context.body(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: boardTab == item.$1 ? c.accentInk : c.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        DashedLine(color: c.line2.withAlpha(150)),
        const SizedBox(height: 4),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : error != null
              ? Center(
                  child: Text(
                    '排行榜暂时无法加载',
                    textAlign: TextAlign.center,
                    style: context.body(size: 11, color: c.inkSoft),
                  ),
                )
              : _shownRows.isEmpty
              ? Center(
                  child: Text(
                    '还没有人上榜',
                    style: context.body(size: 11, color: c.inkSoft),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4),
                  itemCount: _shownRows.length,
                  itemBuilder: (_, i) => _rankRow(context, _shownRows[i]),
                ),
        ),
        if (me != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            decoration: BoxDecoration(
              color: c.hl,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: c.accent.withAlpha(100)),
            ),
            child: Text(
              '我的排名：第 ${me!['rank'] ?? '—'} 名 · ${me!['score'] ?? 0} 分',
              textAlign: TextAlign.center,
              style: context.body(
                size: 10.5,
                weight: FontWeight.w700,
                color: c.accentInk,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _rankRow(BuildContext context, BoardEntry row) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: row.you ? c.hl.withAlpha(120) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${row.rank}',
              textAlign: TextAlign.center,
              style: context.display(
                size: 14,
                weight: FontWeight.w700,
                color: row.rank <= 3 ? c.accentInk : c.inkSoft,
              ),
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.hl),
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
                      style: context.body(size: 11, color: c.accentInk),
                    ),
                  ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(
                size: 11.5,
                weight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${row.score}',
            style: context.display(
              size: 15,
              weight: FontWeight.w700,
              color: c.accentInk,
            ),
          ),
        ],
      ),
    );
  }
}

String fmtDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
