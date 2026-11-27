import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../checkin/checkin_store.dart';
import '../overlays/auth_modal.dart';
import '../overlays/composer_sheet.dart';
import '../overlays/report_sheet.dart';
import '../services/api.dart';
import '../services/media.dart';
import '../services/models.dart';
import '../services/orientation.dart';
import '../services/platform.dart' as platform;
import '../services/voice.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/app_image.dart';
import '../widgets/foldable_text.dart';
import '../widgets/image_viewer.dart';
import '../widgets/modal.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/paper.dart';
import '../widgets/feedback.dart';
import '../widgets/shared_element.dart';
import '../widgets/tablet_shell.dart';
import '../widgets/voice_bubble.dart';
import 'web_scrapbook.dart';

const _moreIcon =
    '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>';

Future<void> _reportPost(BuildContext context, Post p) async {
  if (!AppState.instance.loggedIn) {
    await showAuthModal(context);
    return;
  }
  final preview = p.text.trim().isNotEmpty
      ? p.text
      : (p.voice != null ? '[语音动态]' : (p.imgs.isNotEmpty ? '[图片动态]' : ''));
  await showReportSheet(
    context,
    type: 'post',
    postId: p.id,
    targetNick: p.nick,
    preview: preview,
  );
}

Future<void> _reportComment(
  BuildContext context,
  Post p,
  PostComment cm,
) async {
  if (!AppState.instance.loggedIn) {
    await showAuthModal(context);
    return;
  }
  await showReportSheet(
    context,
    type: 'comment',
    postId: p.id,
    commentId: cm.id,
    targetNick: cm.nick,
    preview: cm.text,
  );
}

Future<void> _blockNick(BuildContext context, String nick) async {
  final app = AppState.instance;
  if (!app.loggedIn) {
    await showAuthModal(context);
    return;
  }
  if (!app.canBlock(nick)) return;
  final ok = await showCitroDialog<bool>(
    context,
    builder: (ctx) => PaperDialog(
      showClose: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('拉黑 $nick？', style: ctx.heading(size: 20)),
          const SizedBox(height: 8),
          Text(
            '拉黑后，这个昵称的动态、评论与消息会从当前设备隐藏。匿名昵称每次随机，匿名内容建议直接举报。',
            textAlign: TextAlign.center,
            style: ctx.body(size: 12, color: ctx.c.inkSoft, height: 1.6),
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
                  text: '拉黑',
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
  await app.blockUser(nick);
  if (context.mounted) AppToast.show(context, '已拉黑 $nick');
}

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});
  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with WidgetsBindingObserver {
  List<Post> posts = [];
  List<InboxItem> inbox = [];
  int unread = 0;
  bool loading = false;
  bool loaded = false;

  /// 已经在列表里出现过的帖子。首次加载完成后一次性记下全部，
  /// 之后新插入的（刚发布 / 刷新出来的）才播一次淡入上浮。
  final Set<String> _seenPosts = {};
  String search = '';
  bool showSearch = false;
  final searchCtrl = TextEditingController();
  final searchFocus = FocusNode();
  Timer? poll;
  bool _active = true;
  bool _tickerActive = true;
  bool _resumed = true;
  AppState? _app;
  String? _lastUser;
  // 请求代次：下拉刷新/登录态变化/轮询可能并发，只有最后一次的结果才生效。
  int _reloadGen = 0;
  int _inboxSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    searchFocus.addListener(_onSearchFocus);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _resumed) return;
    _resumed = resumed;
    _syncActive();
  }

  // 搜索框失焦即整体收起并清空条件，避免留下看不见的过滤状态。
  void _onSearchFocus() {
    if (mounted && showSearch && !searchFocus.hasFocus) {
      setState(() {
        showSearch = false;
        search = '';
        searchCtrl.clear();
      });
    }
  }

  void _toggleSearch() {
    if (showSearch) {
      searchFocus.unfocus();
      return;
    }
    setState(() => showSearch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) searchFocus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerActive = TickerMode.valuesOf(context).enabled;
    _syncActive();
    final app = context.app;
    if (_app != app) {
      _app?.removeListener(_onApp);
      _app = app;
      app.addListener(_onApp);
      _lastUser = app.user?.name;
      if (app.loggedIn) _reload();
    }
  }

  void _syncActive() {
    final active = _tickerActive && _resumed;
    if (active == _active) return;
    _active = active;
    if (!_active) {
      poll?.cancel();
      poll = null;
    } else if (loaded) {
      _startPoll();
    }
  }

  void _onApp() {
    final name = _app?.user?.name;
    if (name != _lastUser) {
      _lastUser = name;
      if (name != null) {
        _reload();
      } else {
        setState(() {
          posts = [];
          inbox = [];
          unread = 0;
          loaded = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app?.removeListener(_onApp);
    poll?.cancel();
    searchFocus.removeListener(_onSearchFocus);
    searchCtrl.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final gen = ++_reloadGen;
    setState(() => loading = true);
    try {
      final list = await Api.posts();
      if (!mounted || gen != _reloadGen) return;
      setState(() {
        posts = list;
        loaded = true;
      });
      _loadInbox();
      _startPoll();
      _precacheFeed(list);
    } catch (e) {
      if (!mounted || gen != _reloadGen) return;
      setState(() => loaded = true);
      AppToast.show(context, '动态加载失败，请稍后重试');
    } finally {
      if (mounted && gen == _reloadGen) setState(() => loading = false);
    }
  }

  /// 首屏前几条动态的图片先落盘并解码，滚动时不至于逐张等网络。
  void _precacheFeed(List<Post> list) {
    final urls = <String>[];
    for (final p in list.take(4)) {
      for (final path in p.imgs.take(1)) {
        final url = Api.imageUrl(path);
        if (url.isNotEmpty) urls.add(url);
      }
    }
    if (urls.isEmpty) return;
    AppImage.precache(context, urls, width: 900);
  }

  void _startPoll() {
    if (!_active) return;
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 60), (_) => _loadInbox());
  }

  Future<void> _loadInbox() async {
    if (!context.mounted || !context.app.loggedIn) return;
    final seq = ++_inboxSeq;
    try {
      final j = await Api.notifications();
      if (!mounted || seq != _inboxSeq) return;
      setState(() {
        inbox = ((j['notifications'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => InboxItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        unread = int.tryParse('${j['unread'] ?? 0}') ?? 0;
      });
      AppState.instance.setUnread(unread);
    } catch (_) {}
  }

  Future<void> _openInbox() async {
    if (inbox.isEmpty) {
      await _loadInbox();
    }
    if (!mounted) return;
    var readOk = true;
    try {
      await Api.readNotifications();
    } catch (_) {
      readOk = false;
    }
    if (!mounted) return;
    if (readOk) {
      // 标记已读失败时不清本地未读，避免「已读又变未读」。
      setState(() {
        unread = 0;
        inbox = [for (final n in inbox) n.unread ? n.asRead() : n];
      });
      AppState.instance.setUnread(0);
    }
    final items = inbox
        .where((n) => !AppState.instance.isBlocked(n.nick))
        .toList();
    await showCitroSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _InboxSheet(items: items),
    );
    if (mounted) _loadInbox();
  }

  Future<void> _openUserPosts({
    String? nick,
    bool mine = false,
    String? avatar,
  }) async {
    final list = mine
        ? posts.where((p) => p.mine).toList()
        : posts
              .where(
                (p) =>
                    !p.anon &&
                    p.nick == nick &&
                    !AppState.instance.isBlocked(p.nick),
              )
              .toList();
    var changed = false;
    await showCitroSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserPostsSheet(
        posts: list,
        mine: mine,
        nick: mine ? (context.app.user?.name ?? '我') : (nick ?? ''),
        avatar: mine ? context.app.user?.av : avatar,
        onChanged: () => changed = true,
      ),
    );
    if (changed && mounted) _reload();
  }

  Future<void> _compose() async {
    final post = await showComposerSheet(context);
    if (post != null && mounted) {
      setState(() => posts.insert(0, post));
    }
  }

  Future<void> _like(Post post) async {
    if (!context.app.loggedIn) {
      showAuthModal(context, onDone: _reload);
      return;
    }
    final idx = posts.indexWhere((p) => p.id == post.id);
    if (idx < 0) return;
    final p = posts[idx];
    setState(() {
      posts[idx] = p.copyWith(
        liked: !p.liked,
        likes: p.likes + (p.liked ? -1 : 1),
      );
    });
    try {
      final j = await Api.toggleLike(p.id);
      if (!mounted) return;
      // 请求期间 feed 可能被刷新/插入新帖，按 id 重新定位，避免写错下标。
      final i = posts.indexWhere((e) => e.id == p.id);
      if (i < 0) return;
      setState(() {
        posts[i] = posts[i].copyWith(
          liked: j['liked'] == true,
          likes: int.tryParse('${j['likes']}') ?? posts[i].likes,
        );
      });
    } catch (e) {
      if (mounted) {
        final i = posts.indexWhere((x) => x.id == p.id);
        if (i >= 0) {
          setState(() => posts[i] = p);
          AppToast.show(context, e.toString());
        }
      }
    }
  }

  Future<void> _deletePost(Post post) async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('删除这条动态？', style: context.heading(size: 20)),
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
      await Api.deletePost(post.id);
      if (mounted) setState(() => posts.removeWhere((p) => p.id == post.id));
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
    }
  }

  Future<bool> _sendComment(
    Post post,
    String text, {
    String? replyId,
    String? image,
    String? voice,
    int voiceDur = 0,
  }) async {
    if (!context.app.loggedIn) {
      showAuthModal(context, onDone: _reload);
      return false;
    }
    try {
      final j = await Api.comment(
        post.id,
        text: text,
        replyId: replyId,
        imgs: image == null ? const [] : [image],
        voice: voice,
        voiceDur: voiceDur,
      );
      if (!mounted) return false;
      final c = PostComment.fromJson(Map<String, dynamic>.from(j['comment']));
      final idx = posts.indexWhere((p) => p.id == post.id);
      if (idx >= 0) {
        setState(() {
          posts[idx] = posts[idx].copyWith(
            comments: [...posts[idx].comments, c],
            nComments:
                int.tryParse('${j['nComments']}') ?? posts[idx].nComments + 1,
          );
        });
      }
      CheckinStore.instance.commentCreated(c.id);
      return true;
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
      return false;
    }
  }

  Future<void> _deleteComment(Post post, PostComment c) async {
    try {
      await Api.deleteComment(post.id, c.id);
      if (!mounted) return;
      final idx = posts.indexWhere((p) => p.id == post.id);
      if (idx >= 0) {
        setState(() {
          posts[idx] = posts[idx].copyWith(
            comments: posts[idx].comments.where((e) => e.id != c.id).toList(),
            nComments: math.max(0, posts[idx].nComments - 1),
          );
        });
      }
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
    }
  }

  /// 全屏查看同一条内容里的多张图：翻页、缩放、Hero 都交给 CitroImageViewer，
  /// 列表与评论只提供图片数组和起始索引。
  void _viewImages(
    List<String> paths,
    int index,
    Object Function(int index) tagOf,
    int cacheWidth,
  ) {
    if (paths.isEmpty) return;
    // 用透明 PageRoute 而不是 DialogRoute：Hero 只在 PageRoute 之间才会飞。
    Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: context.c.scrim,
        barrierDismissible: true,
        transitionDuration: CitroMotion.modal,
        reverseTransitionDuration: CitroMotion.modalReverse,
        pageBuilder: (ctx, animation, secondary) => CitroImageViewer(
          urls: paths.map(Api.imageUrl).toList(),
          initialIndex: index.clamp(0, paths.length - 1),
          tagOf: tagOf,
          cacheWidth: cacheWidth,
        ),
        transitionsBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: CitroMotion.easeOut,
            reverseCurve: CitroMotion.exit,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = context.c;
    final layout = CitroLayoutScope.maybeOf(context);
    final width = layout?.contentWidth ?? MediaQuery.sizeOf(context).width;
    final tabletNav = layout?.tabletNav ?? false;
    final duo = layout?.duo ?? false;
    // 宽屏网页沿用桌面端的信息流：居中标题 + 资料封面 + 多列瀑布流，
    // 不再使用网页专用的三栏仪表盘。
    final webWide = kIsWeb && width >= 760;
    final pad = !kIsWeb && CitroOrientation.padSize(MediaQuery.sizeOf(context));
    // 窄窗口（含测试里模拟的手机宽度）走手机信息流，别让 Windows 桌面布局
    // 覆盖掉 Duo 外屏/小窗口的判断。
    final windows = !kIsWeb && platform.isWindows && width >= 600;
    final masonry = tabletNav || duo || webWide || pad || windows;
    final maxFeed = (tabletNav || webWide || pad || windows) ? 1180.0 : 760.0;
    final side = AppSpacing.pageSide(width, maxFeed);
    // iPad 横竖屏都固定双列；Windows 最多双列；网页宽屏双列；
    // Android 平板保留原来的 2/3 列规则。
    final columns = (pad || windows || kIsWeb)
        ? (width >= 560 ? 2 : 1)
        : width >= 900
        ? (MediaQuery.orientationOf(context) == Orientation.landscape ? 3 : 2)
        : (width >= 560 ? 2 : 1);
    final q = search.trim().toLowerCase();
    final filtered = posts.where((p) {
      if (app.isBlocked(p.nick)) return false;
      if (q.isNotEmpty && !'${p.text}${p.nick}'.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    // 首批帖子直接记为「已见」，不播入场；之后新出现的才播。
    if (loaded && _seenPosts.isEmpty) {
      _seenPosts.addAll(posts.map((p) => p.id));
    }
    final showPosts =
        app.loggedIn && !(loading && !loaded) && filtered.isNotEmpty;
    final prelude = <Widget>[
      const CitroReveal(
        rise: 8,
        child: Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.block),
          child: CitroPageTitle('社区', ''),
        ),
      ),
      if (!app.loggedIn)
        CitroReveal(
          rise: 8,
          delay: CitroMotion.staggerStep,
          child: _gate(context),
        )
      else ...[
        CitroReveal(
          rise: 8,
          delay: CitroMotion.staggerStep,
          child: CitroFieldScope(tone: FieldTone.primary, child: Builder(builder: (context) => _cover(context, app))),
        ),
        if (showSearch) ...[const SizedBox(height: 12), _searchBox(context)],
        const SizedBox(height: AppSpacing.block - 4),
        if (loading && !loaded)
          CitroSkeleton.feed()
        else if (filtered.isEmpty)
          _empty(context),
      ],
    ];
    final itemCount =
        prelude.length +
        (showPosts ? filtered.length : 0) +
        (app.loggedIn ? 1 : 0);
    final footer = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '文明发言，友善互动 · 可举报或拉黑 · 发布者可删除自己的内容',
        textAlign: TextAlign.center,
        style: context.body(size: CitroType.micro, color: c.inkSoft),
      ),
    );
    return Stack(
      children: [
        // 沉浸式：背景由壳层统一提供，这里不再铺纯色底。
        CitroBackground(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RefreshIndicator(
                    color: c.accent,
                    onRefresh: loaded ? _reload : () async {},
                    child: masonry
                        ? CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            slivers: [
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  side,
                                  AppSpacing.pageTopRoomy(width),
                                  side,
                                  0,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildListDelegate(prelude),
                                ),
                              ),
                              if (showPosts)
                                SliverPadding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: side,
                                  ),
                                  sliver: SliverMasonryGrid.count(
                                    crossAxisCount: columns,
                                    mainAxisSpacing: AppSpacing.grid,
                                    crossAxisSpacing: AppSpacing.grid,
                                    childCount: filtered.length,
                                    itemBuilder: (context, index) =>
                                        _feedTile(context, filtered[index]),
                                  ),
                                ),
                              if (app.loggedIn)
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    side,
                                    AppSpacing.block,
                                    side,
                                    AppSpacing.pageBottom(floatingNav: false),
                                  ),
                                  sliver: SliverToBoxAdapter(child: footer),
                                )
                              else
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 56),
                                ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              side,
                              AppSpacing.pageTopRoomy(width),
                              side,
                              AppSpacing.pageBottom(floatingNav: true),
                            ),
                            itemCount: itemCount,
                            itemBuilder: (context, index) {
                              if (index < prelude.length) return prelude[index];
                              final feedIndex = index - prelude.length;
                              if (showPosts && feedIndex < filtered.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.grid,
                                  ),
                                  child: _feedTile(
                                    context,
                                    filtered[feedIndex],
                                  ),
                                );
                              }
                              return footer;
                            },
                          ),
                  ),
                ),
                if (kIsWeb && !tabletNav && width >= 1025)
                  Positioned(
                    left: 18,
                    bottom: MediaQuery.paddingOf(context).bottom + 24,
                    child: const WebHomeBackPill(),
                  ),
                if (app.loggedIn &&
                    MediaQuery.viewInsetsOf(context).bottom == 0)
                  Positioned(
                    right: math.max(18.0, (width - maxFeed) / 2 + 18),
                    bottom:
                        MediaQuery.paddingOf(context).bottom +
                        (tabletNav || (kIsWeb && width >= 1025) ? 24 : 96),
                    child: GestureDetector(
                      onTap: _compose,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: c.accent2,
                          shape: BoxShape.circle,
                          boxShadow: CitroColors.shadows.glow(c),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.plus, width: 2.4),
                            size: 24,
                            color: c.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _feedTile(BuildContext context, Post p) {
    final fresh = _seenPosts.isNotEmpty && _seenPosts.add(p.id);
    return CitroReveal(
      key: ValueKey('reveal-${p.id}'),
      enabled: fresh && !CitroMotion.lite(context),
      rise: 14,
      child: RepaintBoundary(
        // 色场：动态卡是白玻璃块（字多，保证可读）。
        child: CitroFieldScope(
        tone: FieldTone.glass,
        child: _PostCard(
        key: ValueKey('post-${p.id}'),
        post: p,
        onAvatar: p.mine
            ? () => _openUserPosts(mine: true)
            : (p.anon
                  ? null
                  : () => _openUserPosts(nick: p.nick, avatar: p.av)),
        onLike: () => _like(p),
        onDelete: () => _deletePost(p),
        onComment: (text, {replyId, image, voice, voiceDur = 0}) =>
            _sendComment(
              p,
              text,
              replyId: replyId,
              image: image,
              voice: voice,
              voiceDur: voiceDur,
            ),
        onDeleteComment: (comment) => _deleteComment(p, comment),
        onViewImage: _viewImages,
        onReportPost: () => _reportPost(context, p),
        onReportComment: (comment) => _reportComment(context, p, comment),
        onBlockUser: (nick) => _blockNick(context, nick),
      ),
      ),
      ),
    );
  }

  Widget _gate(BuildContext context) {
    final c = context.c;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: CitroCard(
          radius: CitroColors.radii.page,
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  // logo 图形是深色的：深色主题下固定垫一块浅色底，避免融进暗色背景。
                  color: c.dark ? c.ink : c.surface2,
                  borderRadius: BorderRadius.circular(CitroColors.radii.inner),
                  boxShadow: CitroColors.shadows.sm(c),
                ),
                padding: const EdgeInsets.all(12),
                child: Image.asset(
                  'assets/images/logo.webp',
                  fit: BoxFit.contain,
                  cacheWidth: 300,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '登录后加入 Citro 社区',
                textAlign: TextAlign.center,
                style: context.heading(size: CitroType.subtitle, color: c.ink),
              ),
              const SizedBox(height: 8),
              Text(
                '登录账号即可发帖、点赞和评论；热榜按点赞量实时排行，精彩内容永久留档。',
                textAlign: TextAlign.center,
                style: context.body(
                  size: CitroType.meta,
                  color: c.ink2,
                  height: 1.8,
                ),
              ),
              const SizedBox(height: 20),
              CitroButton(
                label: '登录 / 注册',
                style: CitroButtonStyle.primary,
                expanded: true,
                onPressed: () => showAuthModal(context, onDone: _reload),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, AppState app) {
    final c = context.c;
    final user = app.user!;
    final minePosts = posts.where((p) => p.mine).toList();
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openUserPosts(mine: true),
            child: _CommunityAvatar(
              url: Api.imageUrl(user.av),
              size: 50,
              cacheWidth: 150,
              initial: user.name.isEmpty ? '·' : user.name[0],
              textStyle: context.heading(size: 20, color: c.ink2),
              color: c.surface2,
              border: Border.all(color: c.line),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.heading(size: CitroType.title, color: c.ink),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(
                        '${minePosts.length}',
                        style: context.hand(
                          size: CitroType.meta,
                          color: c.accentInk,
                        ),
                      ),
                      Text(
                        ' 动态',
                        style: context.body(
                          size: CitroType.small,
                          color: c.inkSoft,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${minePosts.fold<int>(0, (s, p) => s + p.likes)}',
                        style: context.hand(
                          size: CitroType.meta,
                          color: c.accentInk,
                        ),
                      ),
                      Text(
                        ' 获赞',
                        style: context.body(
                          size: CitroType.small,
                          color: c.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _openInbox,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        strokeSvg(AppIcons.inbox, width: 2),
                        size: 18,
                        color: c.ink2,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '收件箱',
                        style: context.body(
                          size: CitroType.caption,
                          weight: CitroType.strong,
                          color: c.ink2,
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          // 圆形角标：直径随字数长，保证正圆。
                          width: unread > 99
                              ? 24.0
                              : (unread > 9 ? 20.0 : 16.0),
                          height: 16,
                          decoration: BoxDecoration(
                            color: c.ink,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: context.body(
                              size: CitroType.micro,
                              weight: CitroType.strong,
                              color: c.bg,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleSearch,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: showSearch ? c.ink : c.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: showSearch ? c.ink : c.line2),
                  ),
                  child: Center(
                    child: AppIcon(
                      strokeSvg(AppIcons.search, width: 2),
                      size: 20,
                      color: showSearch ? c.bg : c.ink2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchBox(BuildContext context) {
    final c = context.c;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(color: c.line2),
      ),
      child: Row(
        children: [
          AppIcon(
            strokeSvg(AppIcons.search, width: 2),
            size: 16,
            color: c.inkSoft,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: searchCtrl,
              focusNode: searchFocus,
              onChanged: (v) => setState(() => search = v),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              style: context.body(size: CitroType.meta),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: '搜索动态…',
                hintStyle: context.body(size: CitroType.meta, color: c.inkSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.c;
    return CitroCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: CitroEmptyState(
        icon: AppIcon(
          strokeSvg(AppIcons.community, width: 1.8),
          size: 26,
          color: c.accentInk,
        ),
        title: '还没有动态',
        hint: '来发第一条吧，分享此刻在做的事',
      ),
    );
  }
}

class _PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback? onAvatar;
  final VoidCallback onLike;
  final VoidCallback onDelete;
  final Future<bool> Function(
    String text, {
    String? replyId,
    String? image,
    String? voice,
    int voiceDur,
  })
  onComment;
  final ValueChanged<PostComment> onDeleteComment;
  final void Function(
    List<String> paths,
    int index,
    Object Function(int index) tagOf,
    int cacheWidth,
  )
  onViewImage;
  final VoidCallback? onReportPost;
  final ValueChanged<PostComment>? onReportComment;
  final ValueChanged<String>? onBlockUser;

  const _PostCard({
    super.key,
    required this.post,
    this.onAvatar,
    required this.onLike,
    required this.onDelete,
    required this.onComment,
    required this.onDeleteComment,
    required this.onViewImage,
    this.onReportPost,
    this.onReportComment,
    this.onBlockUser,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  final comment = TextEditingController();
  final commentFocus = FocusNode();
  PostComment? replyTo;
  bool showCommentInput = false;
  bool sending = false;
  String? image;
  VoiceResult? voice;
  bool recording = false;
  int recordSeconds = 0;
  Timer? recordTimer;
  // 点输入框内按钮（图片/录音/发送）时的保护窗：
  // TapRegion 的分组在部分机型上仍会先派发 onTapOutside 导致失焦收起，
  // 记录最近一次输入框内的按下时间，窗口期内不收起输入框。
  DateTime _lastComposerDown = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    commentFocus.addListener(_onCommentFocus);
  }

  void _onCommentFocus() {
    final held =
        DateTime.now().difference(_lastComposerDown) <
        const Duration(milliseconds: 150);
    if (mounted &&
        !commentFocus.hasFocus &&
        showCommentInput &&
        !sending &&
        !recording &&
        !held) {
      setState(() {
        showCommentInput = false;
        replyTo = null;
      });
    }
  }

  @override
  void dispose() {
    commentFocus.removeListener(_onCommentFocus);
    comment.dispose();
    commentFocus.dispose();
    recordTimer?.cancel();
    if (recording) VoiceRecorder.cancel();
    super.dispose();
  }

  void _openComment({PostComment? replyTo}) {
    setState(() {
      showCommentInput = true;
      // 无条件赋值：点「评论」重新打开输入框时要清掉上一次的回复对象，
      // 否则回复会发给错误的人。
      this.replyTo = replyTo;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) commentFocus.requestFocus();
    });
  }

  Future<void> _confirmDeleteComment(PostComment cm) async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('删除这条评论？', style: context.heading(size: 20)),
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
    if (ok == true && mounted) {
      if (replyTo?.id == cm.id) setState(() => replyTo = null);
      widget.onDeleteComment(cm);
    }
  }

  void _refocusComment() {
    if (!mounted || !showCommentInput) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && showCommentInput) commentFocus.requestFocus();
    });
  }

  Future<void> _pickImage() async {
    try {
      final data = await MediaService.pickImageData(
        maxWidth: 1200,
        quality: 80,
      );
      if (data != null && mounted) {
        setState(() => image = data);
        _refocusComment();
      }
    } catch (_) {}
  }

  Future<void> _toggleRecord() async {
    if (recording) {
      recordTimer?.cancel();
      final r = await VoiceRecorder.stop();
      if (!mounted) return;
      setState(() {
        recording = false;
        voice = r;
      });
      _refocusComment();
      return;
    }
    final ok = await VoiceRecorder.start(onAutoStop: _stopLimit);
    if (!mounted) return;
    if (!ok) {
      AppToast.show(context, '无法录音，请检查麦克风权限');
      return;
    }
    setState(() {
      recording = true;
      recordSeconds = 0;
    });
    recordTimer?.cancel();
    recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => recordSeconds++);
      if (recordSeconds >= 60) _stopLimit();
    });
  }

  void _stopLimit() {
    if (!recording) return;
    recordTimer?.cancel();
    () async {
      final r = await VoiceRecorder.stop();
      if (!mounted) return;
      setState(() {
        recording = false;
        voice = r;
      });
      _refocusComment();
    }();
  }

  Future<void> _send() async {
    if (sending) return;
    if (recording) {
      AppToast.show(context, '请先结束录音');
      return;
    }
    if (comment.text.trim().isEmpty && image == null && voice == null) return;
    setState(() => sending = true);
    final ok = await widget.onComment(
      comment.text.trim(),
      replyId: replyTo?.id,
      image: image,
      voice: voice?.dataUrl,
      voiceDur: voice?.seconds ?? 0,
    );
    if (!mounted) return;
    setState(() => sending = false);
    if (!ok) {
      // 发送失败保留文字、图片和语音，用户可以直接重试。
      AppToast.show(context, '评论发送失败，内容已保留');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      showCommentInput = false;
      comment.clear();
      image = null;
      voice = null;
      replyTo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = widget.post;
    final visibleComments = p.comments
        .where((cm) => !context.app.isBlocked(cm.nick))
        .toList();
    return CitroCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onAvatar,
                child: _CommunityAvatar(
                  url: Api.imageUrl(p.av),
                  size: 44,
                  cacheWidth: 132,
                  initial: p.nick.isEmpty ? '?' : p.nick[0],
                  textStyle: context.heading(size: 18, color: c.ink2),
                  color: c.surface2,
                  border: Border.all(color: c.line),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.nick,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(
                          size: CitroType.body,
                          weight: CitroType.strong,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (p.anon) ...[
                      const SizedBox(width: 6),
                      CitroChip(
                        '匿',
                        size: CitroType.micro,
                        color: c.inkSoft,
                        background: c.surface2,
                        borderColor: c.line2,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (p.mine)
                GestureDetector(
                  onTap: widget.onDelete,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AppIcon(
                      strokeSvg(AppIcons.trash, width: 2),
                      size: 18,
                      color: c.inkSoft,
                    ),
                  ),
                )
              else
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      _showActions(onReport: widget.onReportPost, nick: widget.post.nick),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AppIcon(
                      strokeSvg(_moreIcon, width: 2),
                      size: 18,
                      color: c.inkSoft,
                    ),
                  ),
                ),
            ],
          ),
          if (p.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            FoldableText(
              text: p.text,
              style: context.body(
                size: CitroType.body,
                color: c.ink,
                height: 1.75,
              ),
            ),
          ],
          if (p.imgs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _images(context),
          ],
          if (p.voice != null) ...[
            const SizedBox(height: 10),
            VoiceBubble(url: p.voice!, seconds: p.voiceDur),
          ],
          const SizedBox(height: 10),
          CitroDivider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                timeAgo(p.ts),
                style: context.body(size: CitroType.caption, color: c.inkSoft),
              ),
              const Spacer(),
              _action(
                context,
                p.liked
                    ? '点赞 ${p.likes}'
                    : '点赞${p.likes > 0 ? ' ${p.likes}' : ''}',
                AppIcons.heart,
                widget.onLike,
                active: p.liked,
              ),
              const SizedBox(width: 14),
              _action(
                context,
                '评论 ${visibleComments.length}',
                AppIcons.comment,
                () => _openComment(),
              ),
            ],
          ),
          if (visibleComments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(CitroColors.radii.inner),
              ),
              child: Column(
                children: [
                  for (final cm in visibleComments) _commentTile(context, cm),
                ],
              ),
            ),
          ],
          if (showCommentInput)
            TextFieldTapRegion(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _lastComposerDown = DateTime.now(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    if (replyTo != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '回复 @${replyTo!.nick}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.body(
                                  size: CitroType.small,
                                  color: c.accentInk,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => setState(() => replyTo = null),
                              child: Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.surface2,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: c.line2),
                                ),
                                child: Text(
                                  '取消回复',
                                  style: context.body(
                                    size: CitroType.small,
                                    weight: CitroType.strong,
                                    color: c.ink2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (recording)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: c.dangerSoft,
                          borderRadius: BorderRadius.circular(
                            CitroColors.radii.small,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: c.danger,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '录音中 ${recordSeconds}s',
                              style: context.body(
                                size: CitroType.small,
                                color: c.danger,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: _toggleRecord,
                              child: Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: c.danger),
                                ),
                                child: Text(
                                  '结束',
                                  style: context.body(
                                    size: CitroType.small,
                                    weight: CitroType.strong,
                                    color: c.danger,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (image != null || voice != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            if (image != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  CitroColors.radii.small,
                                ),
                                child: _LocalCommentImage(data: image!),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (voice != null)
                              VoiceBubble(
                                url: voice!.dataUrl,
                                seconds: voice!.seconds,
                                local: true,
                                width: 148,
                              ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => setState(() {
                                image = null;
                                voice = null;
                              }),
                              child: Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.surface2,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: c.line2),
                                ),
                                child: Text(
                                  '清除',
                                  style: context.body(
                                    size: CitroType.small,
                                    weight: CitroType.strong,
                                    color: c.ink2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(
                                CitroColors.radii.chip,
                              ),
                              border: Border.all(color: c.line2),
                            ),
                            child: TextField(
                              controller: comment,
                              focusNode: commentFocus,
                              onSubmitted: (_) => _send(),
                              onTapOutside: (_) =>
                                  FocusScope.of(context).unfocus(),
                              textInputAction: TextInputAction.send,
                              style: context.body(size: CitroType.meta),
                              // InputBorder.none + isDense 的默认 contentPadding 只有
                              // 上下 4，输入框容器约 28 高；而 InputDecorator 总是把容器
                              // 顶对齐（_RenderDecoration 里 offset = Offset(x, 0)），
                              // 于是 40 高的外框里文字偏上 6px。这里把上下留白补到 10，
                              // 让容器撑满外框，文字才真正居中。
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                hintText: replyTo == null
                                    ? '说点什么…'
                                    : '回复 ${replyTo!.nick}…',
                                hintStyle: context.body(
                                  size: CitroType.caption,
                                  color: c.inkSoft,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _commentAction(c, AppIcons.image, _pickImage, size: 20),
                        const SizedBox(width: 2),
                        _commentAction(
                          c,
                          AppIcons.mic,
                          _toggleRecord,
                          size: 20,
                          active: recording,
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: _send,
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.ink,
                              borderRadius: BorderRadius.circular(
                                CitroColors.radii.chip,
                              ),
                            ),
                            child: sending
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.6,
                                      color: c.bg,
                                    ),
                                  )
                                : Text(
                                    '发送',
                                    style: context.body(
                                      size: CitroType.small,
                                      weight: CitroType.strong,
                                      color: c.bg,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _images(BuildContext context) {
    final imgs = widget.post.imgs.take(3).toList();
    if (imgs.length == 1) {
      final tag = CitroHero.tagOf('post', '${widget.post.id}:0');
      return GestureDetector(
        onTap: () => widget.onViewImage(
          widget.post.imgs,
          0,
          (k) => CitroHero.tagOf('post', '${widget.post.id}:$k'),
          900,
        ),
        child: CitroHero(
          tag: tag,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CitroColors.radii.small),
            child: AspectRatio(
              aspectRatio: 1.45,
              child: AppImage(
                Api.imageUrl(imgs.first),
                fit: BoxFit.cover,
                cacheWidth: 900,
                placeholder: Container(color: context.c.tintPink),
                errorBuilder: (_, _, _) => Container(color: context.c.tintPink),
              ),
            ),
          ),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < imgs.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Builder(
              builder: (context) {
                final tag = CitroHero.tagOf('post', '${widget.post.id}:$i');
                return GestureDetector(
                  onTap: () => widget.onViewImage(
                    widget.post.imgs,
                    i,
                    (k) => CitroHero.tagOf('post', '${widget.post.id}:$k'),
                    900,
                  ),
                  child: CitroHero(
                    tag: tag,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        CitroColors.radii.small,
                      ),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: AppImage(
                          Api.imageUrl(imgs[i]),
                          fit: BoxFit.cover,
                          cacheWidth: 720,
                          placeholder: Container(color: context.c.tintPink),
                          errorBuilder: (_, _, _) =>
                              Container(color: context.c.tintPink),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _action(
    BuildContext context,
    String label,
    String icon,
    VoidCallback onTap, {
    bool active = false,
  }) {
    final c = context.c;
    final layout = CitroLayoutScope.maybeOf(context);
    final tablet = (layout?.tabletNav ?? false) || (layout?.duo ?? false);
    // 点赞后换成实心小红心，和「已喜欢」的语义保持一致。
    final liked = active && icon == AppIcons.heart;
    final fg = liked ? c.stamp : (active ? c.accentInk : c.inkSoft);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: tablet ? 40 : 0),
        padding: EdgeInsets.symmetric(
          horizontal: active ? (tablet ? 12 : 10) : (tablet ? 8 : 2),
          vertical: tablet ? 8 : 4,
        ),
        decoration: active
            ? BoxDecoration(
                color: liked ? c.stamp.withAlpha(24) : c.accent.withAlpha(28),
                borderRadius: BorderRadius.circular(CitroColors.radii.chip),
                border: Border.all(
                  color: (liked ? c.stamp : c.accent).withAlpha(90),
                ),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              liked ? fillSvg(AppIcons.heartFilled) : strokeSvg(icon, width: 2),
              size: tablet ? 19 : 16,
              color: fg,
            ),
            SizedBox(width: tablet ? 6 : 4),
            Text(
              label,
              style: context.body(
                size: tablet ? CitroType.caption : CitroType.small,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _commentAction(
    CitroColors c,
    String icon,
    VoidCallback onTap, {
    double size = 18,
    bool active = false,
  }) {
    final layout = CitroLayoutScope.maybeOf(context);
    final tablet = (layout?.tabletNav ?? false) || (layout?.duo ?? false);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: tablet ? 42 : 36,
        height: tablet ? 42 : 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.dangerSoft : c.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: active ? c.danger : c.line2),
        ),
        child: AppIcon(
          strokeSvg(icon, width: 2),
          size: tablet ? size + 2 : size,
          color: active ? c.danger : c.ink2,
        ),
      ),
    );
  }

  Future<void> _showActions({
    required VoidCallback? onReport,
    required String nick,
  }) async {
    final c = context.c;
    final canBlock =
        widget.onBlockUser != null &&
        AppState.instance.canBlock(nick) &&
        !AppState.instance.isBlocked(nick);
    final action = await showCitroSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(CitroColors.radii.modal),
            boxShadow: CitroColors.shadows.lg(c),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onReport != null)
                _sheetAction(
                  context,
                  label: '举报内容',
                  icon: AppIcons.bell,
                  value: 'report',
                ),
              if (canBlock)
                _sheetAction(
                  context,
                  label: '拉黑 / 隐藏此昵称',
                  icon: AppIcons.lock,
                  value: 'block',
                  danger: true,
                ),
              CitroDivider(color: c.line),
              _sheetAction(
                context,
                label: '取消',
                icon: AppIcons.close,
                value: '',
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'report') onReport?.call();
    if (action == 'block') widget.onBlockUser?.call(nick);
  }

  Widget _sheetAction(
    BuildContext context, {
    required String label,
    required String icon,
    required String value,
    bool danger = false,
  }) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AppIcon(
              strokeSvg(icon, width: 2),
              size: 18,
              color: danger ? c.danger : c.accentInk,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: context.body(
                  size: CitroType.body,
                  weight: CitroType.strong,
                  color: danger ? c.danger : c.ink,
                ),
              ),
            ),
            AppIcon(
              strokeSvg(AppIcons.chevronRight, width: 2),
              size: 15,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }

  Widget _commentTile(BuildContext context, PostComment cm) {
    final c = context.c;
    return GestureDetector(
      onTap: () => _openComment(replyTo: cm),
      onLongPress: cm.mine
          ? () => _confirmDeleteComment(cm)
          : () => _showActions(
              onReport: widget.onReportComment == null
                  ? null
                  : () => widget.onReportComment!(cm),
              nick: cm.nick,
            ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CommunityAvatar(
              url: Api.imageUrl(cm.av),
              size: 30,
              cacheWidth: 90,
              initial: cm.nick.isEmpty ? '?' : cm.nick[0],
              textStyle: context.body(size: CitroType.caption, color: c.ink2),
              asset: cm.bot && Api.imageUrl(cm.av).isEmpty
                  ? 'assets/images/cici_avatar.webp'
                  : null,
              color: c.surface2,
              border: Border.all(color: c.line),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 48),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                cm.nick,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.body(
                                  size: CitroType.caption,
                                  weight: CitroType.strong,
                                  color: c.ink,
                                ),
                              ),
                            ),
                            if (cm.replyTo != null) ...[
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  '回复 @${cm.replyTo}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.body(
                                    size: CitroType.small,
                                    color: c.inkSoft,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Text(
                          timeAgo(cm.ts),
                          style: context.body(
                            size: CitroType.small,
                            color: c.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (cm.text.isNotEmpty)
                    Text(
                      cm.text,
                      style: context.body(
                        size: CitroType.body,
                        color: c.ink2,
                        height: 1.6,
                      ),
                    ),
                  if (cm.imgs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Builder(
                        builder: (context) {
                          final tag = CitroHero.tagOf('comment', '${cm.id}:0');
                          return GestureDetector(
                            onTap: () => widget.onViewImage(
                              cm.imgs,
                              0,
                              (k) => CitroHero.tagOf('comment', '${cm.id}:$k'),
                              720,
                            ),
                            child: CitroHero(
                              tag: tag,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  CitroColors.radii.small,
                                ),
                                child: SizedBox(
                                  width: 72,
                                  height: 72,
                                  child: AppImage(
                                    Api.imageUrl(cm.imgs.first),
                                    fit: BoxFit.cover,
                                    cacheWidth: 216,
                                    placeholder: Container(
                                      color: context.c.tintPink,
                                    ),
                                    errorBuilder: (_, _, _) =>
                                        Container(color: context.c.tintPink),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (cm.voice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: VoiceBubble(url: cm.voice!, seconds: cm.voiceDur),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本地评论图：base64 只解码一次。
/// 旧实现在 build 里 base64Decode + Uint8List.fromList，每次父级重建都会产生
/// 新的 MemoryImage（字节对象不同 → 命中不了图片缓存），滚动时反复解码。
class _LocalCommentImage extends StatefulWidget {
  const _LocalCommentImage({required this.data});

  final String data;

  @override
  State<_LocalCommentImage> createState() => _LocalCommentImageState();
}

class _LocalCommentImageState extends State<_LocalCommentImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant _LocalCommentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _decode();
  }

  void _decode() {
    try {
      final comma = widget.data.indexOf(',');
      _bytes = base64Decode(
        comma >= 0 ? widget.data.substring(comma + 1) : widget.data,
      );
    } catch (_) {
      _bytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return const SizedBox(width: 44, height: 44);
    }
    return Image.memory(
      bytes,
      width: 44,
      height: 44,
      fit: BoxFit.cover,
      cacheWidth: 132,
      gaplessPlayback: true,
    );
  }
}

/// 社区头像：原生端走 AppImage 的磁盘缓存，避免每次打开都重新下载。
class _CommunityAvatar extends StatelessWidget {
  const _CommunityAvatar({
    required this.url,
    required this.size,
    required this.cacheWidth,
    required this.initial,
    required this.textStyle,
    this.asset,
    this.color,
    this.border,
  });

  final String url;
  final double size;
  final int cacheWidth;
  final String initial;
  final TextStyle textStyle;

  /// 本地图片资源（CiCi 头像）；不为空时优先于网络头像。
  final String? asset;
  final Color? color;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(child: Text(initial, style: textStyle));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      foregroundDecoration: border == null
          ? null
          : BoxDecoration(shape: BoxShape.circle, border: border),
      child: asset != null
          ? ClipOval(
              child: Image.asset(
                asset!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            )
          : url.isEmpty
          ? fallback
          : ClipOval(
              child: AppImage(
                url,
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                placeholder: fallback,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

class _UserPostsSheet extends StatefulWidget {
  final List<Post> posts;
  final bool mine;
  final String nick;
  final String? avatar;
  final VoidCallback onChanged;

  const _UserPostsSheet({
    required this.posts,
    required this.mine,
    required this.nick,
    this.avatar,
    required this.onChanged,
  });

  @override
  State<_UserPostsSheet> createState() => _UserPostsSheetState();
}

class _UserPostsSheetState extends State<_UserPostsSheet> {
  late final List<Post> posts;

  @override
  void initState() {
    super.initState();
    posts = List.of(widget.posts);
    AppState.instance.addListener(_onAppState);
  }

  void _onAppState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAppState);
    super.dispose();
  }

  Future<void> _like(Post post) async {
    final idx = posts.indexWhere((p) => p.id == post.id);
    if (idx < 0) return;
    final p = posts[idx];
    setState(() {
      posts[idx] = p.copyWith(
        liked: !p.liked,
        likes: p.likes + (p.liked ? -1 : 1),
      );
    });
    try {
      final j = await Api.toggleLike(p.id);
      if (!mounted) return;
      final i = posts.indexWhere((e) => e.id == p.id);
      if (i < 0) return;
      setState(() {
        posts[i] = posts[i].copyWith(
          liked: j['liked'] == true,
          likes: int.tryParse('${j['likes']}') ?? posts[i].likes,
        );
      });
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        final i = posts.indexWhere((x) => x.id == p.id);
        if (i >= 0) {
          setState(() => posts[i] = p);
          AppToast.show(context, e.toString());
        }
      }
    }
  }

  Future<void> _deletePost(Post post) async {
    final ok = await showCitroDialog<bool>(
      context,
      builder: (ctx) => PaperDialog(
        showClose: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('删除这条动态？', style: context.heading(size: 20)),
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
      await Api.deletePost(post.id);
      if (!mounted) return;
      setState(() => posts.removeWhere((p) => p.id == post.id));
      widget.onChanged();
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
    }
  }

  Future<bool> _sendComment(
    Post post,
    String text, {
    String? replyId,
    String? image,
    String? voice,
    int voiceDur = 0,
  }) async {
    try {
      final j = await Api.comment(
        post.id,
        text: text,
        replyId: replyId,
        imgs: image == null ? const [] : [image],
        voice: voice,
        voiceDur: voiceDur,
      );
      if (!mounted) return false;
      final c = PostComment.fromJson(Map<String, dynamic>.from(j['comment']));
      final idx = posts.indexWhere((p) => p.id == post.id);
      if (idx >= 0) {
        setState(() {
          posts[idx] = posts[idx].copyWith(
            comments: [...posts[idx].comments, c],
            nComments:
                int.tryParse('${j['nComments']}') ?? posts[idx].nComments + 1,
          );
        });
      }
      widget.onChanged();
      CheckinStore.instance.commentCreated(c.id);
      return true;
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
      return false;
    }
  }

  Future<void> _deleteComment(Post post, PostComment c) async {
    try {
      await Api.deleteComment(post.id, c.id);
      if (!mounted) return;
      final idx = posts.indexWhere((p) => p.id == post.id);
      if (idx >= 0) {
        setState(() {
          posts[idx] = posts[idx].copyWith(
            comments: posts[idx].comments.where((e) => e.id != c.id).toList(),
            nComments: math.max(0, posts[idx].nComments - 1),
          );
        });
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
    }
  }

  /// 全屏查看同一条内容里的多张图：翻页、缩放、Hero 都交给 CitroImageViewer，
  /// 列表与评论只提供图片数组和起始索引。
  void _viewImages(
    List<String> paths,
    int index,
    Object Function(int index) tagOf,
    int cacheWidth,
  ) {
    if (paths.isEmpty) return;
    // 用透明 PageRoute 而不是 DialogRoute：Hero 只在 PageRoute 之间才会飞。
    Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: context.c.scrim,
        barrierDismissible: true,
        transitionDuration: CitroMotion.modal,
        reverseTransitionDuration: CitroMotion.modalReverse,
        pageBuilder: (ctx, animation, secondary) => CitroImageViewer(
          urls: paths.map(Api.imageUrl).toList(),
          initialIndex: index.clamp(0, paths.length - 1),
          tagOf: tagOf,
          cacheWidth: cacheWidth,
        ),
        transitionsBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: CitroMotion.easeOut,
            reverseCurve: CitroMotion.exit,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;
    final sheetH = math.max(320.0, screenH * .92 - insets);
    final visiblePosts = posts
        .where((p) => !AppState.instance.isBlocked(p.nick))
        .toList();
    final likes = visiblePosts.fold<int>(0, (s, p) => s + p.likes);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        height: sheetH,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CitroColors.radii.modal),
          ),
        ),
        child: SafeArea(
          top: false,
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
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                child: Row(
                  children: [
                    _CommunityAvatar(
                      url: Api.imageUrl(widget.avatar),
                      size: 46,
                      cacheWidth: 138,
                      initial: widget.nick.isEmpty ? '?' : widget.nick[0],
                      textStyle: context.heading(size: 20, color: c.ink2),
                      color: c.surface2,
                      border: Border.all(color: c.line),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.mine ? '我的发布' : '${widget.nick} 的发布',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.heading(size: CitroType.titleLg),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${visiblePosts.length} 条动态 · $likes 获赞',
                            style: context.body(
                              size: CitroType.small,
                              color: c.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.surface2,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.line2),
                        ),
                        child: Center(
                          child: AppIcon(
                            strokeSvg(AppIcons.close, width: 2.2),
                            size: 18,
                            color: c.inkSoft,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              CitroDivider(),
              Expanded(
                child: visiblePosts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CitroEmptyState(
                              icon: AppIcon(
                                strokeSvg(AppIcons.community, width: 1.8),
                                size: 26,
                                color: c.accentInk,
                              ),
                              title: widget.mine ? '你还没有发布过动态' : 'TA 还没有发布过动态',
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 20),
                        itemCount: visiblePosts.length + 1,
                        itemBuilder: (context, index) {
                          if (index == visiblePosts.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '文明发言，友善互动 · 可举报或拉黑 · 发布者可删除自己的内容',
                                textAlign: TextAlign.center,
                                style: context.body(
                                  size: CitroType.micro,
                                  color: c.inkSoft,
                                ),
                              ),
                            );
                          }
                          final p = visiblePosts[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _PostCard(
                              post: p,
                              onLike: () => _like(p),
                              onDelete: () => _deletePost(p),
                              onComment:
                                  (
                                    text, {
                                    replyId,
                                    image,
                                    voice,
                                    voiceDur = 0,
                                  }) => _sendComment(
                                    p,
                                    text,
                                    replyId: replyId,
                                    image: image,
                                    voice: voice,
                                    voiceDur: voiceDur,
                                  ),
                              onDeleteComment: (cm) => _deleteComment(p, cm),
                              onViewImage: _viewImages,
                              onReportPost: () => _reportPost(context, p),
                              onReportComment: (cm) =>
                                  _reportComment(context, p, cm),
                              onBlockUser: (nick) => _blockNick(context, nick),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxSheet extends StatefulWidget {
  final List<InboxItem> items;
  const _InboxSheet({required this.items});

  @override
  State<_InboxSheet> createState() => _InboxSheetState();
}

class _InboxSheetState extends State<_InboxSheet> {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: MediaQuery.sizeOf(context).height * .64,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CitroColors.radii.modal),
        ),
      ),
      child: SafeArea(
        top: false,
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
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
              child: Row(
                children: [
                  Text('收件箱', style: context.heading(size: CitroType.title)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.line2),
                      ),
                      child: Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.close, width: 2.2),
                          size: 18,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.items.isEmpty
                  ? const Center(
                      child: CitroEmptyState(
                        icon: Icon(Icons.notifications_none_rounded),
                        title: '暂无消息',
                        hint: '别人评论或回复你时会在这里提醒',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: widget.items.length,
                      separatorBuilder: (_, __) => CitroDivider(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                      ),
                      itemBuilder: (_, i) {
                        final n = widget.items[i];
                        final icon = n.type == 'like'
                            ? AppIcons.heart
                            : (n.type == 'reply'
                                  ? AppIcons.repeat
                                  : AppIcons.comment);
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: n.unread
                              ? BoxDecoration(
                                  color: c.accent.withAlpha(24),
                                  borderRadius: BorderRadius.circular(
                                    CitroColors.radii.small,
                                  ),
                                )
                              : null,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(width: 4),
                              AppIcon(
                                strokeSvg(icon, width: 2),
                                size: 16,
                                color: n.unread ? c.accentInk : c.inkSoft,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: n.nick,
                                            style: context.body(
                                              size: CitroType.caption,
                                              weight: CitroType.strong,
                                              color: c.ink,
                                            ),
                                          ),
                                          TextSpan(
                                            text: n.type == 'like'
                                                ? ' 赞了你的动态'
                                                : (n.type == 'reply'
                                                      ? ' 回复了你的评论'
                                                      : ' 评论了你的动态'),
                                            style: context.body(
                                              size: CitroType.small,
                                              color: c.inkSoft,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (n.text.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          n.text,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.body(
                                            size: CitroType.small,
                                            color: c.ink2,
                                          ),
                                        ),
                                      ),
                                    if (n.postText.isNotEmpty)
                                      Text(
                                        '「${n.postText}」',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.body(
                                          size: CitroType.micro,
                                          color: c.inkSoft,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                timeAgo(n.ts),
                                style: context.body(
                                  size: CitroType.micro,
                                  color: c.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String timeAgo(int ts) {
  final diff = DateTime.now().millisecondsSinceEpoch - ts;
  if (diff < 60000) return '刚刚';
  if (diff < 3600000) return '${diff ~/ 60000}分钟前';
  if (diff < 86400000) return '${diff ~/ 3600000}小时前';
  if (diff < 86400000 * 7) return '${diff ~/ 86400000}天前';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.year}.${d.month}.${d.day}';
}
