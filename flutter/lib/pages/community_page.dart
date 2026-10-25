import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../overlays/auth_modal.dart';
import '../overlays/composer_sheet.dart';
import '../overlays/report_sheet.dart';
import '../services/api.dart';
import '../services/media.dart';
import '../services/models.dart';
import '../services/voice.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';
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
            style: ctx.body(size: 11.5, color: ctx.c.inkSoft, height: 1.6),
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

class _CommunityPageState extends State<CommunityPage> {
  List<Post> posts = [];
  List<InboxItem> inbox = [];
  int unread = 0;
  bool loading = false;
  bool loaded = false;
  String search = '';
  bool showSearch = false;
  final searchCtrl = TextEditingController();
  final searchFocus = FocusNode();
  Timer? poll;
  bool _active = true;
  AppState? _app;
  String? _lastUser;

  @override
  void initState() {
    super.initState();
    searchFocus.addListener(_onSearchFocus);
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
    final active = TickerMode.of(context);
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
    _app?.removeListener(_onApp);
    poll?.cancel();
    searchFocus.removeListener(_onSearchFocus);
    searchCtrl.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final list = await Api.posts();
      if (!mounted) return;
      setState(() {
        posts = list;
        loaded = true;
      });
      _loadInbox();
      _startPoll();
    } catch (e) {
      if (mounted) {
        setState(() => loaded = true);
        AppToast.show(context, '动态加载失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _startPoll() {
    if (!_active) return;
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 60), (_) => _loadInbox());
  }

  Future<void> _loadInbox() async {
    if (!context.mounted || !context.app.loggedIn) return;
    try {
      final j = await Api.notifications();
      if (!mounted) return;
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
    try {
      await Api.readNotifications();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      unread = 0;
      inbox = [for (final n in inbox) n.unread ? n.asRead() : n];
    });
    AppState.instance.setUnread(0);
    final items = inbox
        .where((n) => !AppState.instance.isBlocked(n.nick))
        .toList();
    await showModalBottomSheet<void>(
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
    await showModalBottomSheet<void>(
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
      setState(() {
        posts[idx] = posts[idx].copyWith(
          liked: j['liked'] == true,
          likes: int.tryParse('${j['likes']}') ?? posts[idx].likes,
        );
      });
    } catch (e) {
      if (mounted) {
        setState(() => posts[idx] = p);
        AppToast.show(context, e.toString());
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
            Text('删除这条动态？', style: context.heading(size: 21)),
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

  Future<void> _sendComment(
    Post post,
    String text, {
    String? replyId,
    String? image,
    String? voice,
    int voiceDur = 0,
  }) async {
    if (!context.app.loggedIn) {
      showAuthModal(context, onDone: _reload);
      return;
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
      if (!mounted) return;
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
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
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

  void _viewImage(String path) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          child: Center(
            child: Image.network(
              Api.imageUrl(path),
              fit: BoxFit.contain,
              cacheWidth: 1280,
            ),
          ),
        ),
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
    final masonry = tabletNav || duo || webWide;
    final maxFeed = (tabletNav || webWide) ? 1180.0 : 760.0;
    final side = math.max(8.0, (width - maxFeed) / 2);
    final q = search.trim().toLowerCase();
    final filtered = posts.where((p) {
      if (app.isBlocked(p.nick)) return false;
      if (q.isNotEmpty && !'${p.text}${p.nick}'.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    final showPosts =
        app.loggedIn && !(loading && !loaded) && filtered.isNotEmpty;
    final prelude = <Widget>[
      _header(context),
      if (!app.loggedIn)
        _gate(context)
      else ...[
        _cover(context, app),
        if (showSearch) ...[const SizedBox(height: 8), _searchBox(context)],
        const SizedBox(height: 10),
        if (loading && !loaded)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
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
        style: context.body(size: 10, color: c.inkSoft),
      ),
    );
    return PaperBackground(
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
                            padding: EdgeInsets.fromLTRB(side, 8, side, 0),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate(prelude),
                            ),
                          ),
                          if (showPosts)
                            SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: side),
                              sliver: SliverMasonryGrid.count(
                                crossAxisCount: kIsWeb
                                    ? (width >= 560 ? 2 : 1)
                                    : width >= 900
                                    ? (MediaQuery.orientationOf(context) ==
                                              Orientation.landscape
                                          ? 3
                                          : 2)
                                    : (width >= 560 ? 2 : 1),
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childCount: filtered.length,
                                itemBuilder: (context, index) =>
                                    _feedTile(context, filtered[index]),
                              ),
                            ),
                          if (app.loggedIn)
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(side, 16, side, 36),
                              sliver: SliverToBoxAdapter(child: footer),
                            )
                          else
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 36),
                            ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: EdgeInsets.fromLTRB(side, 8, side, 110),
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          if (index < prelude.length) return prelude[index];
                          final feedIndex = index - prelude.length;
                          if (showPosts && feedIndex < filtered.length) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _feedTile(context, filtered[feedIndex]),
                            );
                          }
                          return footer;
                        },
                      ),
              ),
            ),
            if (kIsWeb && width >= 1025)
              Positioned(
                left: 18,
                bottom: MediaQuery.paddingOf(context).bottom + 24,
                child: const WebHomeBackPill(),
              ),
            if (app.loggedIn)
              Positioned(
                right: math.max(18.0, (width - maxFeed) / 2 + 18),
                bottom:
                    MediaQuery.paddingOf(context).bottom +
                    (tabletNav || (kIsWeb && width >= 1025) ? 24 : 96),
                child: GestureDetector(
                  onTap: _compose,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                      boxShadow: CitroColors.shadows.lg(c),
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(AppIcons.plus, width: 2.4),
                        size: 22,
                        color: const Color(0xFF2E2C22),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _feedTile(BuildContext context, Post p) {
    return RepaintBoundary(
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
        onViewImage: _viewImage,
        onReportPost: () => _reportPost(context, p),
        onReportComment: (comment) => _reportComment(context, p, comment),
        onBlockUser: (nick) => _blockNick(context, nick),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Column(
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Citro ',
                  style: context.display(
                    size: 30,
                    weight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                TextSpan(
                  text: '社区',
                  style: context
                      .heading(size: 28, color: c.ink)
                      .copyWith(backgroundColor: c.hl, height: 1.2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                strokeSvg(
                  '<path d="M12 3l1.9 5.8a2 2 0 0 0 1.3 1.3L21 12l-5.8 1.9a2 2 0 0 0-1.3 1.3L12 21l-1.9-5.8a2 2 0 0 0-1.3-1.3L3 12l5.8-1.9a2 2 0 0 0 1.3-1.3L12 3z"/>',
                  width: 2,
                ),
                size: 12,
                color: c.accentInk,
              ),
              const SizedBox(width: 4),
              Text(
                '“ 在清爽的汽水里，与同频的灵魂相遇 ”',
                style: context.hand(size: 15, color: c.ink2, height: 1.4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gate(BuildContext context) {
    final c = context.c;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: PaperCard(
          rotate: -1,
          tapeColor: c.tape,
          tapeAngle: -2.4,
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 42),
          child: Column(
            children: [
              Transform.rotate(
                angle: -1.5 * math.pi / 180,
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: c.paperLine),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x145A4A2C),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Image.asset(
                    'assets/images/logo.webp',
                    fit: BoxFit.contain,
                    cacheWidth: 300,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '登录后加入 Citro 社区',
                textAlign: TextAlign.center,
                style: context.heading(size: 22, color: c.ink),
              ),
              const SizedBox(height: 8),
              Text(
                '登录账号即可发帖、点赞、抱一抱和评论；热榜按点赞量实时排行，精彩内容永久留档。',
                textAlign: TextAlign.center,
                style: context.body(size: 12.5, color: c.ink2, height: 1.8),
              ),
              const SizedBox(height: 18),
              Pressable(
                onTap: () => showAuthModal(context, onDone: _reload),
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
              const SizedBox(height: 24),
              Text(
                'CITRO · COMMUNITY',
                style: context.hand(size: 17, color: c.inkSoft),
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PaperCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _openUserPosts(mine: true),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [c.accentLt, c.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: c.surface2, width: 2),
                    image: user.av != null
                        ? DecorationImage(
                            image: ResizeImage(
                              NetworkImage(Api.imageUrl(user.av)),
                              width: 150,
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: user.av != null
                      ? null
                      : Center(
                          child: Text(
                            user.name.isEmpty ? '·' : user.name[0],
                            style: context.display(
                              size: 21,
                              color: const Color(0xFF2E2C22),
                            ),
                          ),
                        ),
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
                      style: context.heading(size: 17, color: c.ink),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Text(
                            '${posts.where((p) => p.mine).length}',
                            style: context.display(
                              size: 13,
                              weight: FontWeight.w700,
                              color: c.accentInk,
                            ),
                          ),
                          Text(
                            ' 动态',
                            style: context.body(size: 11, color: c.inkSoft),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${posts.where((p) => p.mine).fold<int>(0, (s, p) => s + p.likes)}',
                            style: context.display(
                              size: 13,
                              weight: FontWeight.w700,
                              color: c.accentInk,
                            ),
                          ),
                          Text(
                            ' 获赞',
                            style: context.body(size: 11, color: c.inkSoft),
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
                      padding: const EdgeInsets.fromLTRB(14, 0, 15, 0),
                      decoration: BoxDecoration(
                        color: c.dark ? c.mintSoft : const Color(0xFFF5F0DE),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.mintLine),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('📬', style: TextStyle(fontSize: 17)),
                          const SizedBox(width: 6),
                          Text(
                            '收件箱',
                            style: context.body(
                              size: 12,
                              weight: FontWeight.w600,
                              color: c.ink2,
                            ),
                          ),
                          if (unread > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: c.accent,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '$unread',
                                style: context.body(
                                  size: 9.5,
                                  weight: FontWeight.w800,
                                  color: const Color(0xFF2E2C22),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  GestureDetector(
                    onTap: _toggleSearch,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: showSearch ? c.hl : c.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: showSearch ? c.accent : c.line2,
                        ),
                      ),
                      child: Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.search, width: 2),
                          size: 20,
                          color: c.accentInk,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: -9,
          left: 22,
          child: Transform.rotate(
            angle: -3.5 * math.pi / 180,
            child: ClipPath(
              clipper: _TapeClip(),
              child: Container(width: 64, height: 20, color: c.tape3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchBox(BuildContext context) {
    final c = context.c;
    return Container(
      height: 42,
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
              controller: searchCtrl,
              focusNode: searchFocus,
              onChanged: (v) => setState(() => search = v),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              style: context.body(size: 12.5),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: '搜索动态…',
                hintStyle: context.body(size: 12, color: c.inkSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 50),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Text('🍊', style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          Text(
            '还没有动态，来发第一条吧',
            style: context.body(size: 12.5, color: c.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _TapeClip extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .02, 0)
    ..lineTo(size.width * .98, size.height * .03)
    ..lineTo(size.width, size.height * .95)
    ..lineTo(size.width * .04, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

class _PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback? onAvatar;
  final VoidCallback onLike;
  final VoidCallback onDelete;
  final Future<void> Function(
    String text, {
    String? replyId,
    String? image,
    String? voice,
    int voiceDur,
  })
  onComment;
  final ValueChanged<PostComment> onDeleteComment;
  final ValueChanged<String> onViewImage;
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
  bool showAllComments = false;
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
      if (replyTo != null) this.replyTo = replyTo;
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
    await widget.onComment(
      comment.text.trim(),
      replyId: replyTo?.id,
      image: image,
      voice: voice?.dataUrl,
      voiceDur: voice?.seconds ?? 0,
    );
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      sending = false;
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
    final shown = showAllComments
        ? visibleComments
        : visibleComments.take(2).toList();
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onAvatar,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.hl,
                    border: Border.all(color: c.line2),
                    image: p.av != null
                        ? DecorationImage(
                            image: ResizeImage(
                              NetworkImage(Api.imageUrl(p.av)),
                              width: 132,
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: p.av != null
                      ? null
                      : Center(
                          child: Text(
                            p.nick.isEmpty ? '?' : p.nick[0],
                            style: context.display(
                              size: 19,
                              weight: FontWeight.w700,
                              color: c.accentInk,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.nick,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.body(
                          size: 15.5,
                          weight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (p.anon) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: c.hl,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '匿',
                          style: context.body(size: 8, color: c.accentInk),
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
                  onTap: _showMoreMenu,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AppIcon(
                      strokeSvg(_moreIcon, width: 2),
                      size: 17,
                      color: c.inkSoft,
                    ),
                  ),
                ),
            ],
          ),
          if (p.text.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              p.text,
              style: context.body(size: 15.5, color: c.ink, height: 1.75),
            ),
          ],
          if (p.imgs.isNotEmpty) ...[
            const SizedBox(height: 9),
            _images(context),
          ],
          if (p.voice != null) ...[
            const SizedBox(height: 9),
            VoiceBubble(url: p.voice!, seconds: p.voiceDur),
          ],
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line.withAlpha(180))),
            ),
            child: Row(
              children: [
                Text(
                  timeAgo(p.ts),
                  style: context.body(size: 11.5, color: c.inkSoft),
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
          ),
          if (visibleComments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: c.dark ? c.mintSoft : const Color(0x2EFBF1C4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.line.withAlpha(150)),
              ),
              child: Column(
                children: [
                  for (final cm in shown) _commentTile(context, cm),
                  if (!showAllComments && visibleComments.length > shown.length)
                    GestureDetector(
                      onTap: () => setState(() => showAllComments = true),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          '查看全部 ${visibleComments.length} 条评论',
                          style: context.body(size: 10.5, color: c.accentInk),
                        ),
                      ),
                    ),
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
                                  size: 10.5,
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
                                  border: Border.all(color: c.line),
                                ),
                                child: Text(
                                  '取消回复',
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
                      ),
                    if (recording)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: c.hl.withAlpha(120),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: c.stamp,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '录音中 ${recordSeconds}s',
                              style: context.body(size: 10.5, color: c.stamp),
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
                                  color: c.surface2,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: c.stamp.withAlpha(90),
                                  ),
                                ),
                                child: Text(
                                  '结束',
                                  style: context.body(
                                    size: 10.5,
                                    weight: FontWeight.w700,
                                    color: c.stamp,
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
                                borderRadius: BorderRadius.circular(6),
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
                                  border: Border.all(color: c.line),
                                ),
                                child: Text(
                                  '清除',
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
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: c.line2),
                            ),
                            child: TextField(
                              controller: comment,
                              focusNode: commentFocus,
                              onSubmitted: (_) => _send(),
                              onTapOutside: (_) =>
                                  FocusScope.of(context).unfocus(),
                              textInputAction: TextInputAction.send,
                              style: context.body(size: 11.5),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: replyTo == null
                                    ? '说点什么…'
                                    : '回复 ${replyTo!.nick}…',
                                hintStyle: context.body(
                                  size: 11,
                                  color: c.inkSoft,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _commentAction(c, AppIcons.image, _pickImage, size: 19),
                        const SizedBox(width: 2),
                        _commentAction(
                          c,
                          AppIcons.mic,
                          _toggleRecord,
                          size: 19,
                          active: recording,
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: _send,
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: sending
                                ? SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: c.ink,
                                    ),
                                  )
                                : Text(
                                    '发送',
                                    style: context.body(
                                      size: 11,
                                      weight: FontWeight.w700,
                                      color: const Color(0xFF2E2C22),
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
      return GestureDetector(
        onTap: () => widget.onViewImage(imgs.first),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: AspectRatio(
            aspectRatio: 1.45,
            child: Image.network(
              Api.imageUrl(imgs.first),
              fit: BoxFit.cover,
              cacheWidth: 900,
              errorBuilder: (_, __, ___) => Container(color: context.c.noteP),
            ),
          ),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < imgs.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onViewImage(imgs[i]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Image.network(
                    Api.imageUrl(imgs[i]),
                    fit: BoxFit.cover,
                    cacheWidth: 720,
                    errorBuilder: (_, __, ___) =>
                        Container(color: context.c.noteP),
                  ),
                ),
              ),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: tablet ? 40 : 0),
        padding: EdgeInsets.symmetric(
          horizontal: active ? (tablet ? 12 : 8) : (tablet ? 8 : 2),
          vertical: tablet ? 8 : 4,
        ),
        decoration: active
            ? BoxDecoration(
                color: c.hl,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.accent.withAlpha(100)),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              strokeSvg(icon, width: 2),
              size: tablet ? 19 : 15,
              color: active ? c.accentInk : c.inkSoft,
            ),
            SizedBox(width: tablet ? 6 : 4),
            Text(
              label,
              style: context.body(
                size: tablet ? 13 : 11.5,
                color: active ? c.accentInk : c.inkSoft,
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
          color: active ? c.hl : c.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: active ? c.accent.withAlpha(120) : c.line),
        ),
        child: AppIcon(
          strokeSvg(icon, width: 2),
          size: tablet ? size + 2 : size,
          color: active ? c.stamp : c.accentInk,
        ),
      ),
    );
  }

  Future<void> _showMoreMenu() {
    return _showActions(onReport: widget.onReportPost, nick: widget.post.nick);
  }

  Future<void> _showCommentMenu(PostComment cm) {
    return _showActions(
      onReport: widget.onReportComment == null
          ? null
          : () => widget.onReportComment!(cm),
      nick: cm.nick,
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
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DashedLine(color: c.line2.withAlpha(120)),
              ),
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
              color: danger ? c.stamp : c.accentInk,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: context.body(
                  size: 13.5,
                  weight: FontWeight.w600,
                  color: danger ? c.stamp : c.ink,
                ),
              ),
            ),
            AppIcon(
              strokeSvg(AppIcons.chevronRight, width: 2),
              size: 15,
              color: c.inkSoft.withAlpha(140),
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
          : () => _showCommentMenu(cm),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.surface2,
                border: Border.all(color: c.line),
                image: cm.av != null
                    ? DecorationImage(
                        image: ResizeImage(
                          NetworkImage(Api.imageUrl(cm.av)),
                          width: 90,
                        ),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: cm.av != null
                  ? null
                  : Center(
                      child: Text(
                        cm.nick.isEmpty ? '?' : cm.nick[0],
                        style: context.body(size: 12, color: c.accentInk),
                      ),
                    ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          cm.nick,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.body(
                            size: 12,
                            weight: FontWeight.w700,
                            color: c.accentInk,
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
                            style: context.body(size: 10.5, color: c.inkSoft),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        timeAgo(cm.ts),
                        style: context.body(size: 10.5, color: c.inkSoft),
                      ),
                    ],
                  ),
                  if (cm.text.isNotEmpty)
                    Text(
                      cm.text,
                      style: context.body(
                        size: 13.5,
                        color: c.ink2,
                        height: 1.6,
                      ),
                    ),
                  if (cm.imgs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: GestureDetector(
                        onTap: () => widget.onViewImage(cm.imgs.first),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Image.network(
                            Api.imageUrl(cm.imgs.first),
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            cacheWidth: 216,
                          ),
                        ),
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
      setState(() {
        posts[idx] = posts[idx].copyWith(
          liked: j['liked'] == true,
          likes: int.tryParse('${j['likes']}') ?? posts[idx].likes,
        );
      });
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() => posts[idx] = p);
        AppToast.show(context, e.toString());
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
            Text('删除这条动态？', style: context.heading(size: 21)),
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

  Future<void> _sendComment(
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
      if (!mounted) return;
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
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
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

  void _viewImage(String path) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          child: Center(
            child: Image.network(
              Api.imageUrl(path),
              fit: BoxFit.contain,
              cacheWidth: 1280,
            ),
          ),
        ),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: c.line),
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
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.hl,
                        border: Border.all(color: c.line2),
                        image: widget.avatar != null
                            ? DecorationImage(
                                image: ResizeImage(
                                  NetworkImage(Api.imageUrl(widget.avatar)),
                                  width: 138,
                                ),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: widget.avatar != null
                          ? null
                          : Center(
                              child: Text(
                                widget.nick.isEmpty ? '?' : widget.nick[0],
                                style: context.display(
                                  size: 19,
                                  weight: FontWeight.w700,
                                  color: c.accentInk,
                                ),
                              ),
                            ),
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
                            style: context.heading(size: 19),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${visiblePosts.length} 条动态 · $likes 获赞',
                            style: context.body(size: 10.5, color: c.inkSoft),
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
              Divider(height: 1, color: c.line.withAlpha(150)),
              Expanded(
                child: visiblePosts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🍊', style: TextStyle(fontSize: 36)),
                            const SizedBox(height: 8),
                            Text(
                              widget.mine ? '你还没有发布过动态' : 'TA 还没有发布过动态',
                              style: context.body(size: 12.5, color: c.inkSoft),
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
                                style: context.body(size: 10, color: c.inkSoft),
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
                              onViewImage: _viewImage,
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: c.line),
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
                  Text('📬 收件箱', style: context.heading(size: 18)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AppIcon(
                        strokeSvg(AppIcons.close, width: 2.2),
                        size: 17,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.items.isEmpty
                  ? Center(
                      child: Text(
                        '暂无消息\n别人评论或回复你时会在这里提醒',
                        textAlign: TextAlign.center,
                        style: context.body(
                          size: 12,
                          color: c.inkSoft,
                          height: 1.7,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: widget.items.length,
                      separatorBuilder: (_, __) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: DashedLine(color: c.line2.withAlpha(120)),
                      ),
                      itemBuilder: (_, i) {
                        final n = widget.items[i];
                        final icon = n.type == 'like'
                            ? '♥'
                            : (n.type == 'reply' ? '↩' : '💬');
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          color: n.unread ? c.hl.withAlpha(80) : null,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                icon,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: c.accentInk,
                                ),
                              ),
                              const SizedBox(width: 8),
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
                                              size: 11.5,
                                              weight: FontWeight.w700,
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
                                              size: 11,
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
                                            size: 11,
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
                                          size: 10,
                                          color: c.inkSoft,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                timeAgo(n.ts),
                                style: context.body(size: 9, color: c.inkSoft),
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
