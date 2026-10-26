import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/resources.dart';
import '../games/game_registry.dart';
import '../overlays/ai_chat.dart';
import '../overlays/appreciation_sheet.dart';
import '../overlays/coin_sheet.dart';
import '../overlays/extra_sheets.dart';
import '../overlays/lantern_sheet.dart';
import '../overlays/pomodoro_sheet.dart';
import '../overlays/zodiac_modal.dart';
import '../pages/in_app_web.dart';
import '../pages/web_resource_actions.dart';
import '../services/lantern_api.dart';
import '../services/prefs.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'paper.dart';

const _searchHistoryKey = 'chimu_search_hist';

enum _SearchAction {
  route,
  checkin,
  zodiac,
  weather,
  fish,
  pomodoro,
  ai,
  coin,
  lantern,
  appreciate,
  tool,
  url,
}

class _SearchEntry {
  final String type;
  final String name;
  final String desc;
  final String keys;
  final _SearchAction action;
  final String? target;
  final ToolItem? tool;

  const _SearchEntry({
    required this.type,
    required this.name,
    required this.desc,
    required this.keys,
    required this.action,
    this.target,
    this.tool,
  });
}

class _SearchRow {
  final _SearchEntry? entry;
  final String? bing;
  final String? history;

  const _SearchRow.entry(this.entry) : bing = null, history = null;
  const _SearchRow.bing(this.bing) : entry = null, history = null;
  const _SearchRow.history(this.history) : entry = null, bing = null;
}

List<_SearchEntry> _buildSearchIndex() {
  final entries = <_SearchEntry>[
    const _SearchEntry(
      type: '页面',
      name: '首页',
      desc: '天气、月历、摸鱼、星象与每日一言',
      keys: 'home shouye 首页 手账 天气 日历 月历 摸鱼',
      action: _SearchAction.route,
      target: '/home',
    ),
    _SearchEntry(
      type: '页面',
      name: '小游戏',
      desc: '${kGameCards.length} 款小游戏 · 账号同步 · 全站排行',
      keys: 'games game 游戏 小游戏 排行',
      action: _SearchAction.route,
      target: '/games',
    ),
    const _SearchEntry(
      type: '页面',
      name: 'Citro 社区',
      desc: '动态、评论、点赞与消息中心',
      keys: 'community trash shequ 社区 动态 消息 发帖',
      action: _SearchAction.route,
      target: '/trash',
    ),
    const _SearchEntry(
      type: '页面',
      name: '我的',
      desc: '账号资料与我的笔记',
      keys: 'me account 我的 账号 登录 资料 笔记',
      action: _SearchAction.route,
      target: '/me',
    ),
    const _SearchEntry(
      type: '页面',
      name: '灵敏度',
      desc: '跨游戏灵敏度精确换算',
      keys: 'lingmindu lingmin sensitivity sens dpi 灵敏度 转换 换算',
      action: _SearchAction.route,
      target: '/sens',
    ),
    const _SearchEntry(
      type: '页面',
      name: '玩法抽签',
      desc: '无畏契约整活玩法抽签',
      keys: 'chouqian play 抽签 玩法 整活 无畏契约 瓦罗兰特',
      action: _SearchAction.route,
      target: '/play',
    ),
    const _SearchEntry(
      type: '功能',
      name: '每日打卡',
      desc: '翻开今日一签 · 节气农历 · 连续打卡',
      keys: 'daka checkin 打卡 签到 连续 每日 节气 农历 幸运签 运势',
      action: _SearchAction.checkin,
    ),
    const _SearchEntry(
      type: '功能',
      name: '食谱日记',
      desc: '收藏菜谱 · 记每次下厨 · 购物清单 · 食谱广场',
      keys: 'cook recipe shipu 食谱 日记 菜谱 做饭 下厨 烹饪 购物清单 食材',
      action: _SearchAction.route,
      target: '/cook',
    ),
    const _SearchEntry(
      type: '功能',
      name: '星象',
      desc: '每日运势 · 星座选择 · 幸运指数',
      keys: 'xingzuo zodiac 星座 运势 星象',
      action: _SearchAction.zodiac,
    ),
    const _SearchEntry(
      type: '功能',
      name: '天气详情',
      desc: '当前天气、体感温度与未来预报',
      keys: 'weather tianqi 天气 气温 湿度 预报',
      action: _SearchAction.weather,
    ),
    const _SearchEntry(
      type: '功能',
      name: '摸鱼日历',
      desc: '工作状态、休息日与上下班时间',
      keys: 'fish moyu 摸鱼 下班 上班 休息日 工作日',
      action: _SearchAction.fish,
    ),
    const _SearchEntry(
      type: '功能',
      name: '番茄钟',
      desc: '专注计时与休息提醒',
      keys: 'pomodoro timer fanqie 番茄钟 专注 计时 时钟',
      action: _SearchAction.pomodoro,
    ),
    const _SearchEntry(
      type: '功能',
      name: 'Citro AI',
      desc: '和橘子助手聊聊天',
      keys: 'ai chat 聊天 助手 橘子 人工智能',
      action: _SearchAction.ai,
    ),
    const _SearchEntry(
      type: '功能',
      name: '抛硬币',
      desc: '正面、反面，还有 2% 的概率立起来',
      keys: 'coin toss 硬币 抛硬币 正面 反面 立起',
      action: _SearchAction.coin,
    ),
    const _SearchEntry(
      type: '功能',
      name: '赞赏码',
      desc: '给广告费！！！',
      keys: 'appreciate sponsor 赞赏 广告费 支持',
      action: _SearchAction.appreciate,
    ),
    if (LanternApi.currentWindow() != null)
      const _SearchEntry(
        type: '活动',
        name: '中秋灯谜',
        desc: '三十道灯谜与 emoji 成语附加题',
        keys: 'lantern 中秋 灯谜 猜谜 emoji 成语',
        action: _SearchAction.lantern,
      ),
  ];
  for (final game in kGameCards) {
    entries.add(
      _SearchEntry(
        type: '游戏',
        name: game.title,
        desc: 'Citro 小游戏 · 账号同步 · 全站排行',
        keys:
            '${game.key} ${game.title} game 游戏 小游戏 排行 '
            '${_gameKeywords(game.key)}',
        action: _SearchAction.route,
        target: '/${game.key}',
      ),
    );
  }
  if (!kIsWeb) {
    // 网页端不再提供 Mod / 工具 / 驱动资源库，搜索索引也同步移除。
    for (final mod in kMods) {
      entries.add(
        _SearchEntry(
          type: 'Mod',
          name: mod.name,
          desc: mod.desc,
          keys: '${mod.name} ${mod.desc} ${mod.tag} mod 模组 整合包 下载',
          action: _SearchAction.url,
          target: mod.url,
        ),
      );
    }
    for (final tool in kTools) {
      entries.add(
        _SearchEntry(
          type: '工具',
          name: tool.name,
          desc: tool.desc,
          keys: '${tool.name} ${tool.desc} ${tool.section} 工具 软件 下载',
          action: _SearchAction.tool,
          tool: tool,
        ),
      );
    }
    for (final driver in [...kDriversWeb, ...kDriversClient]) {
      entries.add(
        _SearchEntry(
          type: '驱动',
          name: driver.name,
          desc: driver.client ? '外设驱动 · 客户端' : '外设驱动 · 网页配置',
          keys:
              '${driver.name} 驱动 外设 键盘 鼠标 耳机 网页驱动 客户端 '
              'driver qudong ${driver.client ? 'client 客户端' : 'web 网页'}',
          action: _SearchAction.url,
          target: driver.url,
        ),
      );
    }
  }
  return entries;
}

String _gameKeywords(String key) => switch (key) {
  'g2048' => '2048 数字 合成',
  'gmem' => 'memory jiyi 记忆 翻牌 配对 卡牌',
  'gsudoku' => 'sudoku 数独 九宫格 逻辑',
  'gnono' => 'nonogram nono 数织 填涂',
  'gslide' => 'slide huarongdao 华容道 拼图 滑动',
  'gsnake' => 'snake 贪吃蛇 蛇',
  'gsheep' => 'sheep 羊了个羊 消除 三消',
  'gjump' => 'jump 跳一跳 跳跃',
  'gpeng' => 'peng 淘气小球 圆环 旋转',
  'gbrake' => 'brake 极限刹车 刹车 汽车 3d',
  'gidiom' => 'idiom 成语接龙 成语 接龙',
  'gfeihua' => 'feihua 飞花令 诗词 诗句',
  _ => '',
};

/// Original site-wide search: suggestions, six persistent history entries,
/// arrow-key selection, named-route navigation and Bing fallback.
class GlobalSearch extends StatefulWidget {
  final bool preferBelow;
  final String hint;

  const GlobalSearch({
    super.key,
    this.preferBelow = false,
    this.hint = '搜索功能 / Mod / 工具，回车必应',
  });

  @override
  State<GlobalSearch> createState() => _GlobalSearchState();
}

class _GlobalSearchState extends State<GlobalSearch> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  final _tapGroup = Object();
  final _index = _buildSearchIndex();
  OverlayEntry? _panel;
  List<_SearchRow> _rows = [];
  int _active = -1;
  double _targetWidth = 400;
  bool _panelBelow = true;
  double _panelMaxHeight = 410;

  List<String> get _history => Prefs.getStringList(_searchHistoryKey);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
      if (_focus.hasFocus) {
        _showPanel();
      } else {
        _closePanel();
      }
    });
  }

  @override
  void dispose() {
    _closePanel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<_SearchEntry> _match(String query) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) {
      return _index.where((e) => e.type == '功能').take(4).toList();
    }
    final matches = _index.where((entry) {
      final haystack = '${entry.name} ${entry.desc} ${entry.keys}'
          .toLowerCase();
      return terms.every(haystack.contains);
    }).toList();
    matches.sort((a, b) {
      final ai = a.name.toLowerCase().indexOf(terms.first);
      final bi = b.name.toLowerCase().indexOf(terms.first);
      final ap = ai < 0 ? 99 : ai;
      final bp = bi < 0 ? 99 : bi;
      if (ap != bp) return ap.compareTo(bp);
      final aPriority = a.type == '页面' || a.type == '功能' ? 0 : 1;
      final bPriority = b.type == '页面' || b.type == '功能' ? 0 : 1;
      return aPriority.compareTo(bPriority);
    });
    return matches;
  }

  void _rebuildRows() {
    final query = _controller.text.trim();
    final rows = <_SearchRow>[];
    var localCount = 0;
    if (query.isEmpty) {
      rows.addAll(_history.map(_SearchRow.history));
      rows.addAll(_match('').map(_SearchRow.entry));
    } else {
      rows.add(_SearchRow.bing(query));
      rows.addAll(
        _history
            .where((word) => word.toLowerCase().contains(query.toLowerCase()))
            .take(3)
            .map(_SearchRow.history),
      );
      final matches = _match(query).take(7).toList();
      localCount = matches.length;
      rows.addAll(matches.map(_SearchRow.entry));
    }
    _rows = rows;
    _active = query.isEmpty ? -1 : 0;
    _emptyLocalQuery = query.isNotEmpty && localCount == 0;
  }

  bool _emptyLocalQuery = false;

  void _measurePanel() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _targetWidth = box.size.width;
    final origin = box.localToGlobal(Offset.zero);
    final viewHeight = MediaQuery.sizeOf(context).height;
    final belowSpace = viewHeight - origin.dy - box.size.height - 14;
    final aboveSpace = origin.dy - 14;
    _panelBelow = widget.preferBelow
        ? (belowSpace >= 180 || belowSpace >= aboveSpace)
        : (belowSpace >= 240 || belowSpace >= aboveSpace);
    final available = _panelBelow ? belowSpace : aboveSpace;
    _panelMaxHeight = available.clamp(140.0, 410.0);
  }

  void _showPanel() {
    _rebuildRows();
    _measurePanel();
    if (_panel != null) {
      _panel!.markNeedsBuild();
      return;
    }
    _panel = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: 0,
        top: 0,
        width: _targetWidth,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: _panelBelow ? Alignment.bottomLeft : Alignment.topLeft,
          followerAnchor: _panelBelow
              ? Alignment.topLeft
              : Alignment.bottomLeft,
          offset: Offset(0, _panelBelow ? 8 : -8),
          child: TextFieldTapRegion(
            groupId: _tapGroup,
            child: Material(
              color: Colors.transparent,
              child: _buildPanel(overlayContext),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_panel!);
  }

  void _closePanel() {
    _panel?.remove();
    _panel = null;
    _rows = [];
    _active = -1;
  }

  void _saveHistory(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    final next = _history.where((word) => word != query).toList()
      ..insert(0, query);
    Prefs.setStringList(_searchHistoryKey, next.take(6).toList());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_rows.isNotEmpty) {
        _active = (_active + 1) % _rows.length;
        _panel?.markNeedsBuild();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_rows.isNotEmpty) {
        _active = _active <= 0 ? _rows.length - 1 : _active - 1;
        _panel?.markNeedsBuild();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _closePanel();
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submit() {
    final query = _controller.text.trim();
    if (_active >= 0 && _active < _rows.length) {
      _run(_rows[_active]);
    } else if (query.isNotEmpty) {
      _run(_SearchRow.bing(query));
    }
  }

  void _run(_SearchRow row) {
    final query = _controller.text.trim();
    _saveHistory(row.history ?? row.bing ?? query);
    _closePanel();
    _focus.unfocus();
    if (row.bing != null || row.history != null) {
      final word = row.bing ?? row.history!;
      openCitroPage(
        context,
        'https://www.bing.com/search?q=${Uri.encodeQueryComponent(word)}',
        title: '必应 · $word',
      );
      return;
    }
    final entry = row.entry;
    if (entry == null || !mounted) return;
    switch (entry.action) {
      case _SearchAction.route:
        Navigator.of(context).pushNamed(entry.target!);
      case _SearchAction.checkin:
        showCheckinOverlay(context);
      case _SearchAction.zodiac:
        showZodiacModal(context);
      case _SearchAction.weather:
        showWeatherSheet(context);
      case _SearchAction.fish:
        showFishSheet(context);
      case _SearchAction.pomodoro:
        showPomodoroOverlay(context);
      case _SearchAction.ai:
        showAiChat(context);
      case _SearchAction.coin:
        showCoinSheet(context);
      case _SearchAction.lantern:
        showLanternSheet(context);
      case _SearchAction.appreciate:
        showAppreciationSheet(context);
      case _SearchAction.tool:
        openCitroTool(context, entry.tool!);
      case _SearchAction.url:
        openCitroResource(context, entry.name, entry.target!);
    }
  }

  Widget _buildPanel(BuildContext context) {
    final c = context.c;
    return Container(
      key: const ValueKey('globalSearchPanel'),
      constraints: BoxConstraints(maxHeight: _panelMaxHeight),
      decoration: BoxDecoration(
        color: c.dark ? const Color(0xFF211E19) : const Color(0xFFFFFCF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
        boxShadow: CitroColors.shadows.lg(c),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 7),
        children: [
          if (_controller.text.trim().isEmpty && _history.isNotEmpty)
            _panelHeader(context, '最近搜索', clear: true),
          for (var i = 0; i < _rows.length; i++) _resultRow(context, i),
          if (_rows.isEmpty || _emptyLocalQuery)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Text(
                _rows.isEmpty ? '输入关键词搜索站内功能，回车必应' : '站内无匹配，回车直接必应搜索',
                style: context.body(size: 11.5, color: c.inkSoft),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelHeader(BuildContext context, String text, {bool clear = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 8, 5),
      child: Row(
        children: [
          Text(text, style: context.body(size: 10.5, color: context.c.inkSoft)),
          const Spacer(),
          if (clear)
            TextButton(
              onPressed: () {
                Prefs.setString(_searchHistoryKey, null);
                _rebuildRows();
                _panel?.markNeedsBuild();
              },
              child: Text(
                '清空',
                style: context.body(size: 10.5, color: context.c.accentInk),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultRow(BuildContext context, int index) {
    final row = _rows[index];
    final c = context.c;
    final tag = row.bing != null
        ? '必应'
        : row.history != null
        ? '历史'
        : row.entry!.type;
    final name = row.bing != null
        ? '必应搜索：${row.bing}'
        : row.history ?? row.entry!.name;
    final desc = row.bing != null
        ? '在应用内打开 Bing 搜索结果'
        : row.history != null
        ? '使用这条历史记录进行必应搜索'
        : row.entry!.desc;
    return InkWell(
      onTap: () => _run(row),
      onHover: (hover) {
        if (hover && _active != index) {
          _active = index;
          _panel?.markNeedsBuild();
        }
      },
      child: Container(
        color: _active == index ? c.hl.withAlpha(170) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 43,
              padding: const EdgeInsets.symmetric(vertical: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.hl.withAlpha(150),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tag,
                style: context.body(size: 9.5, color: c.accentInk),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.body(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  if (desc.isNotEmpty)
                    Text(
                      desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(size: 10.5, color: c.inkSoft),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final focused = _focus.hasFocus;
    return CompositedTransformTarget(
      link: _link,
      child: Focus(
        onKeyEvent: _onKey,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: c.surface2.withAlpha(c.dark ? 225 : 245),
            borderRadius: BorderRadius.circular(14),
            boxShadow: CitroColors.shadows.paper(c),
          ),
          child: CustomPaint(
            foregroundPainter: _SearchBorderPainter(
              color: focused ? c.accent : c.line2,
            ),
            child: Center(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                groupId: _tapGroup,
                textAlign: TextAlign.left,
                textAlignVertical: TextAlignVertical.center,
                onChanged: (_) {
                  setState(() {});
                  _showPanel();
                },
                onSubmitted: (_) => _submit(),
                onTap: _showPanel,
                textInputAction: TextInputAction.search,
                style: context.body(
                  size: 14.5,
                  weight: FontWeight.w600,
                  color: c.ink,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.hint,
                  hintStyle: context.body(size: 13.5, color: c.inkSoft),
                  contentPadding: const EdgeInsets.fromLTRB(18, 0, 44, 1),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _controller.clear();
                            _showPanel();
                            _focus.requestFocus();
                          },
                          icon: AppIcon(
                            strokeSvg(AppIcons.close),
                            size: 14,
                            color: c.inkSoft,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBorderPainter extends CustomPainter {
  final Color color;

  const _SearchBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          const Radius.circular(14),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + 7 < metric.length ? distance + 7 : metric.length;
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SearchBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
