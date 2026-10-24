import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/game_sfx.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'game_ui.dart';

// ---------------------------------------------------------------------------
// 羊了个羊 —— 复刻 web 原版 #gsheepPage（index.html 内联脚本 gsheep* 系列）。
//
// 玩法（与原版完全一致）：
//   · 两关。第 1 关 12 张牌（3 种图案、2 层）；第 2 关 300 张牌（15 种图案、9 层重叠）。
//   · 点击「没有被画在上面的牌压住」的牌 → 放进底部 7 个槽位；同图案凑 3 张自动消除。
//   · 主牌堆清空 = 通关（第 1 关照例自动进第 2 关，只有全部通关才计分）。
//   · 7 个槽位全满 = 失败；可复活一次（把槽内 3 张移出）。
//   · 道具：洗牌 2 次 / 撤销 3 次 / 移出 1 次。
//   · 计分：score = max(1, 99999 - floor(用时秒))；本机最快用时存 "sheep" 的最好成绩。
//
// 版式取自 web 计算样式（390×844 light）：
//   内容顶 121.663 = HUD 107.641（pills 56.6406 + 9 + actions 42）
//   + 4 + 10 → 工具条 37 → 14 → 舞台 543 = 362 × 3/2（宽 362，上下留白 14/10）
//   舞台内：#gsheepBoard 340×453（flex:1）+ 14 + #gsheepSlots 340×50
// ---------------------------------------------------------------------------

/// 一张牌：牌堆网格坐标（gx/gy 允许半格）+ 所在层 + 图案编号。
class SheepTile {
  SheepTile({
    required this.id,
    required this.gx,
    required this.gy,
    required this.layer,
    this.type = 0,
    this.picked = false,
  });

  final int id;
  final double gx;
  final double gy;
  final int layer;
  int type;
  bool picked;
}

/// 牌桌几何：与 web `gsheepComputeGeom / gsheepLayout` 逐行对应。
class SheepGeom {
  const SheepGeom({
    required this.ts,
    required this.margin,
    required this.cw,
    required this.ch,
    required this.offX,
    required this.offY,
  });

  /// 单张牌边长（web `--gsheep-ts`）。
  final double ts;

  /// 牌堆四周留白 = ts × 0.16。
  final double margin;

  /// 网格步长（含缝）= ts × 1.1。
  final double cw;
  final double ch;

  /// 牌堆整体居中偏移。
  final double offX;
  final double offY;

  /// 同层缝隙比：0.10（web GSHEEP_GAP_RATIO）。
  static const double gapRatio = 0.10;

  /// 牌堆留白比：0.16。
  static const double marginRatio = 0.16;

  /// 遮挡阈值（格单位）= 1 / (1 + gapRatio)。
  static const double cover = 1 / (1 + gapRatio);

  static SheepGeom compute({
    required double boardW,
    required double boardH,
    required List<SheepTile> tiles,
  }) {
    var maxGx = 0.0;
    var maxGy = 0.0;
    for (final t in tiles) {
      if (t.gx > maxGx) maxGx = t.gx;
      if (t.gy > maxGy) maxGy = t.gy;
    }
    final denomW = maxGx * (1 + gapRatio) + 1 + 2 * marginRatio;
    final denomH = maxGy * (1 + gapRatio) + 1 + 2 * marginRatio;
    var ts = boardW / denomW;
    if (boardH >= 10) ts = math.min(ts, boardH / denomH);
    ts = ts.clamp(16.0, 200.0);
    final margin = ts * marginRatio;
    final cw = ts * (1 + gapRatio);
    final contentW = maxGx * cw + ts + 2 * margin;
    final contentH = maxGy * cw + ts + 2 * margin;
    return SheepGeom(
      ts: ts,
      margin: margin,
      cw: cw,
      ch: cw,
      offX: math.max(0.0, (boardW - contentW) / 2),
      offY: math.max(0.0, (boardH - contentH) / 2),
    );
  }

  double leftOf(SheepTile t) => t.gx * cw + margin + offX;

  double topOf(SheepTile t) => t.gy * ch + margin + offY;

  /// 是否被「画在上面」的牌压住（web `gsheepIsLocked`）。
  bool isLocked(List<SheepTile> tiles, SheepTile tile) {
    final px = tile.gx * cw;
    final py = tile.gy * ch;
    for (final o in tiles) {
      if (identical(o, tile) || o.picked) continue;
      if (o.layer < tile.layer) continue;
      if (o.layer == tile.layer && o.id <= tile.id) continue;
      if ((o.gx * cw - px).abs() < ts && (o.gy * ch - py).abs() < ts) {
        return true;
      }
    }
    return false;
  }
}

class _SheepLayerSpec {
  const _SheepLayerSpec(this.cols, this.rows);
  final int cols;
  final int rows;
}

class _SheepLevelSpec {
  const _SheepLevelSpec({
    required this.nTypes,
    required this.k,
    required this.layers,
    this.overlap,
  });

  final int nTypes;

  /// 每批交错的「三元组」数量（web K）。
  final int k;
  final List<_SheepLayerSpec> layers;
  final List<double>? overlap;
}

/// web `GSHEEP_LEVELS`。
const List<_SheepLevelSpec> _sheepLevels = <_SheepLevelSpec>[
  _SheepLevelSpec(
    nTypes: 3,
    k: 1,
    layers: <_SheepLayerSpec>[_SheepLayerSpec(3, 3), _SheepLayerSpec(3, 1)],
  ),
  _SheepLevelSpec(
    nTypes: 15,
    k: 3,
    layers: <_SheepLayerSpec>[
      _SheepLayerSpec(6, 6),
      _SheepLayerSpec(6, 6),
      _SheepLayerSpec(6, 6),
      _SheepLayerSpec(6, 6),
      _SheepLayerSpec(6, 6),
      _SheepLayerSpec(6, 6),
      _SheepLayerSpec(6, 6),
      _SheepLayerSpec(6, 6),
      _SheepLayerSpec(4, 3),
    ],
    overlap: <double>[0, 0.3, 0.5, 0.7, 1, 1, 1, 1, 1],
  ),
];

class _Cell {
  _Cell(this.gx, this.gy, this.layer);
  final double gx;
  final double gy;
  final int layer;
}

void _shuffleList<T>(List<T> a, math.Random rnd) {
  for (var i = a.length - 1; i > 0; i--) {
    final j = rnd.nextInt(i + 1);
    final t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
}

/// web `gsheepCovers`：a 是否「压住」b。
bool _covers(SheepTile a, SheepTile b) {
  if (identical(a, b)) return false;
  if (a.layer < b.layer) return false;
  if (a.layer == b.layer && a.id <= b.id) return false;
  return (a.gx - b.gx).abs() < SheepGeom.cover &&
      (a.gy - b.gy).abs() < SheepGeom.cover;
}

/// web `gsheepBuildPile`：生成单个「规则金字塔」牌堆坐标（局部坐标，从 0 起）。
List<_Cell> _buildPile(
  List<_SheepLayerSpec> layers,
  List<double>? overlap,
  math.Random rnd,
) {
  final out = <_Cell>[];
  var maxCols = 0;
  var maxRows = 0;
  for (final l in layers) {
    maxCols = math.max(maxCols, l.cols);
    maxRows = math.max(maxRows, l.rows);
  }
  var fx = -1e9;
  var fy = -1e9;
  for (var li = 0; li < layers.length; li++) {
    final l = layers[li];
    final sx = (maxCols - l.cols) / 2 + li * 0.5;
    final sy = (maxRows - l.rows) / 2 + li * 0.5;
    final p = (overlap != null && li < overlap.length) ? overlap[li] : 0.0;
    var cells = <_Cell>[];
    for (var r = 0; r < l.rows; r++) {
      for (var c = 0; c < l.cols; c++) {
        cells.add(_Cell(sx + c, sy + r, li));
      }
    }
    if (p > 0) {
      // 落点池 = 下一层「不同格位」：完全重叠后压到它正上方。
      final seen = <String>{};
      final pool = <_Cell>[];
      if (li > 0) {
        for (final t in out) {
          if (t.layer != li - 1) continue;
          final k = '${t.gx},${t.gy}';
          if (seen.add(k)) pool.add(t);
        }
      }
      final m = math.min((p * cells.length).round(), pool.length);
      if (m > 0) {
        final onGrid = <String>{for (final c in cells) '${c.gx},${c.gy}'};
        final off = pool
            .where((c) => !onGrid.contains('${c.gx},${c.gy}'))
            .toList();
        final on = pool
            .where((c) => onGrid.contains('${c.gx},${c.gy}'))
            .toList();
        _shuffleList(off, rnd);
        _shuffleList(on, rnd);
        final targets = <_Cell>[...off, ...on].take(m).toList();
        final tk = <String>{for (final c in targets) '${c.gx},${c.gy}'};
        final keep = cells
            .where((c) => !tk.contains('${c.gx},${c.gy}'))
            .toList();
        _shuffleList(keep, rnd);
        // 非重叠格优先收进「已有足迹」内（金字塔向内收边），放不下再落外侧。
        final inside = keep.where((c) => c.gx <= fx && c.gy <= fy).toList();
        final outside = keep.where((c) => c.gx > fx || c.gy > fy).toList();
        final total = cells.length;
        cells = <_Cell>[
          ...targets,
          ...<_Cell>[...inside, ...outside].take(total - m),
        ];
      }
    }
    for (final cell in cells) {
      out.add(_Cell(cell.gx, cell.gy, li));
      if (cell.gx > fx) fx = cell.gx;
      if (cell.gy > fy) fy = cell.gy;
    }
  }
  return out;
}

/// web `gsheepPeelOrder`：求一条合法剥离顺序（每步取「当前没被更高层压住」的牌）。
List<SheepTile> _peelOrder(List<SheepTile> tiles, math.Random rnd) {
  final n = tiles.length;
  final coverCnt = List<int>.filled(n, 0);
  final covers = List<List<int>>.generate(n, (_) => <int>[]);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (i != j && _covers(tiles[j], tiles[i])) {
        coverCnt[i]++;
        covers[j].add(i);
      }
    }
  }
  final gone = List<bool>.filled(n, false);
  final free = <int>[
    for (var i = 0; i < n; i++)
      if (coverCnt[i] == 0) i,
  ];
  final order = <SheepTile>[];
  while (free.isNotEmpty) {
    final pk = rnd.nextInt(free.length);
    final idx = free[pk];
    free[pk] = free.last;
    free.removeLast();
    order.add(tiles[idx]);
    gone[idx] = true;
    for (final t in covers[idx]) {
      if (!gone[t] && --coverCnt[t] == 0) free.add(t);
    }
  }
  return order;
}

/// web `gsheepAssignTypes`：按剥离顺序分组交错赋牌，保证「槽内不超过 2K 张必能三消」。
void _assignTypes(List<SheepTile> order, int nTypes, int k, math.Random rnd) {
  final total = order.length;
  final nTriples = total ~/ 3;
  final blocks = <int>[for (var i = 0; i < nTriples; i++) i % nTypes];
  _shuffleList(blocks, rnd);
  final seq = <int>[];
  for (var i = 0; i < blocks.length; i += k) {
    final group = blocks.sublist(i, math.min(i + k, blocks.length));
    for (var r = 0; r < 3; r++) {
      for (final g in group) {
        seq.add(g);
      }
    }
  }
  final len = math.min(total, seq.length);
  for (var p = 0; p < len; p++) {
    order[p].type = seq[p];
  }
}

/// web `gsheepGenLevel`（当前每关只有一个主牌堆）。
List<SheepTile> _genLevel(int idx, math.Random rnd) {
  final cfg = _sheepLevels[idx];
  final raw = _buildPile(cfg.layers, cfg.overlap, rnd);
  var minX = double.infinity;
  var minY = double.infinity;
  for (final c in raw) {
    if (c.gx < minX) minX = c.gx;
    if (c.gy < minY) minY = c.gy;
  }
  final tiles = <SheepTile>[];
  for (var i = 0; i < raw.length; i++) {
    tiles.add(
      SheepTile(
        id: i,
        gx: raw[i].gx - minX,
        gy: raw[i].gy - minY,
        layer: raw[i].layer,
      ),
    );
  }
  final order = _peelOrder(tiles, rnd);
  _assignTypes(order, cfg.nTypes, cfg.k, rnd);
  return tiles;
}

String _sheepFmtTime(double secs) {
  if (!secs.isFinite) return '--';
  final s = math.max(0, secs.floor());
  final m = s ~/ 60;
  final ss = s % 60;
  return m > 0 ? '$m:${ss.toString().padLeft(2, '0')}' : '${ss}s';
}

class _SheepSnap {
  _SheepSnap({
    required this.picked,
    required this.types,
    required this.slotIds,
    required this.removedIds,
    required this.over,
    required this.won,
    required this.revived,
  });

  final List<bool> picked;
  final List<int> types;
  final List<int> slotIds;
  final List<int> removedIds;
  final bool over;
  final bool won;
  final bool revived;
}

/// 游戏页：只负责状态与玩法，视觉全部交给 [GameSheepView]。
class GameSheepPage extends StatefulWidget {
  const GameSheepPage({super.key});

  @override
  State<GameSheepPage> createState() => _GameSheepPageState();
}

class _GameSheepPageState extends State<GameSheepPage> {
  static const int _slotCount = 7;
  static const int _base = 99999;

  final math.Random _rnd = math.Random();
  final ValueNotifier<String> _timeText = ValueNotifier<String>('0.0s');

  /// 「正在玩」心跳进度（web gamesLiveProgress：第 N 关 · 剩 X 张）。
  final ValueNotifier<String> _liveProgress = ValueNotifier<String>(
    '第 1 关 · 剩 12 张',
  );

  List<SheepTile> _tiles = const <SheepTile>[];
  List<SheepTile?> _slots = List<SheepTile?>.filled(_slotCount, null);
  final List<SheepTile> _removed = <SheepTile>[];

  /// 三消幽灵：(tileId, type, slotIndex)——用于消失动画。
  final List<(int, int, int)> _fading = <(int, int, int)>[];
  final List<_SheepSnap> _history = <_SheepSnap>[];

  int _level = 0;
  int _shuffleLeft = 2;
  int _undoLeft = 3;
  int _removeLeft = 1;
  bool _revived = false;
  bool _over = false;
  bool _won = false;
  bool _submitted = false;
  double? _bestSecs;
  bool _bestLoaded = false;

  String? _ovTitle;
  String? _ovDesc;
  bool _ovRevive = false;

  Timer? _ticker;
  Timer? _levelTimer;
  DateTime _start = DateTime.now();
  final List<double> _levelTimes = <double>[];

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bestLoaded) return;
    _bestLoaded = true;
    final best = context.app.localBest('sheep');
    _bestSecs = best > 0 ? (_base - best).toDouble() : null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _levelTimer?.cancel();
    _timeText.dispose();
    _liveProgress.dispose();
    super.dispose();
  }

  double _secs() => DateTime.now().difference(_start).inMilliseconds / 1000.0;

  void _startTicker() {
    _ticker?.cancel();
    _timeText.value = '0.0s';
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_over || _won) return;
      _timeText.value = '${_secs().toStringAsFixed(1)}s';
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // --- 开局 / 关卡 ---------------------------------------------------------

  void _newGame() {
    _ticker?.cancel();
    _levelTimer?.cancel();
    _level = 0;
    _shuffleLeft = 2;
    _undoLeft = 3;
    _removeLeft = 1;
    _revived = false;
    _over = false;
    _won = false;
    _submitted = false;
    _levelTimes.clear();
    _history.clear();
    _start = DateTime.now();
    _startLevel();
    _hideOverlay();
    _startTicker();
  }

  void _startLevel() {
    _tiles = _genLevel(_level, _rnd);
    _slots = List<SheepTile?>.filled(_slotCount, null);
    _removed.clear();
    _fading.clear();
    _history.clear();
    _over = false;
    _won = false;
  }

  void _hideOverlay() {
    _ovTitle = null;
    _ovDesc = null;
    _ovRevive = false;
  }

  // --- 取牌 / 三消 ---------------------------------------------------------

  void _pick(SheepTile tile, SheepGeom geom) {
    if (_over || tile.picked) return;
    if (geom.isLocked(_tiles, tile)) return;
    final si = _slots.indexWhere((s) => s == null);
    if (si < 0) return;
    _pushHistory();
    tile.picked = true;
    _slots[si] = tile;
    GameSfx.flip();
    _checkMatch();
    _sortSlots();
    _checkEnd();
  }

  /// 移出区的牌可以点回槽位（web `gsheepPickRemoved`）。
  void _pickRemoved(SheepTile tile) {
    if (_over) return;
    final si = _slots.indexWhere((s) => s == null);
    if (si < 0) return;
    _pushHistory();
    _removed.remove(tile);
    GameSfx.flip();
    _slots[si] = tile;
    _checkMatch();
    _sortSlots();
    _checkEnd();
  }

  void _checkMatch() {
    final counts = <int, int>{};
    for (final s in _slots) {
      if (s != null) counts[s.type] = (counts[s.type] ?? 0) + 1;
    }
    for (final ty in counts.keys.toList()) {
      if ((counts[ty] ?? 0) >= 3) {
        GameSfx.match();
        final batch = <(int, int, int)>[]; // (tileId, type, slot)
        var removed = 0;
        for (var i = 0; i < _slotCount && removed < 3; i++) {
          final s = _slots[i];
          if (s != null && s.type == ty) {
            // v1.6.0：三消不再瞬间消失，先记下幽灵做缩放淡出动画
            batch.add((s.id, s.type, i));
            _slots[i] = null;
            removed++;
          }
        }
        // 调用方（_pick / _pickRemoved）本就在 setState 回调里，无需再套
        _fading.addAll(batch);
        unawaited(
          Future.delayed(const Duration(milliseconds: 400), () {
            if (!mounted) return;
            final ids = batch.map((e) => e.$1).toSet();
            setState(() => _fading.removeWhere((e) => ids.contains(e.$1)));
          }),
        );
        final filled = _slots.where((s) => s != null).toList();
        _slots = List<SheepTile?>.filled(_slotCount, null);
        for (var k = 0; k < filled.length; k++) {
          _slots[k] = filled[k];
        }
        _checkMatch();
        return;
      }
    }
  }

  void _sortSlots() {
    final filled = _slots.where((s) => s != null).cast<SheepTile>().toList();
    filled.sort((a, b) => a.type - b.type);
    _slots = List<SheepTile?>.filled(_slotCount, null);
    for (var k = 0; k < filled.length; k++) {
      _slots[k] = filled[k];
    }
  }

  void _checkEnd() {
    final remaining = _tiles.where((t) => !t.picked).length;
    if (remaining == 0) {
      final secs = _secs();
      final prev = _levelTimes.fold<double>(0, (a, b) => a + b);
      _levelTimes.add(secs - prev);
      if (_level < _sheepLevels.length - 1) {
        _showWinOverlay(secs, lvSecs: _levelTimes.last);
        _levelTimer?.cancel();
        _levelTimer = Timer(const Duration(milliseconds: 1600), () {
          if (!mounted) return;
          setState(() {
            _hideOverlay();
            _level++;
            _startLevel();
          });
        });
      } else {
        _won = true;
        _over = true;
        _stopTicker();
        _submitScore(secs);
        GameSfx.win();
        _showWinOverlay(secs);
      }
      return;
    }
    if (_slots.every((s) => s != null)) {
      _over = true;
      _stopTicker();
      GameSfx.lose();
      _showFailOverlay();
    }
  }

  void _showWinOverlay(double secsTotal, {double? lvSecs}) {
    if (_level < _sheepLevels.length - 1) {
      _ovTitle = '第${_level + 1}关通过！';
      _ovDesc = '用时 ${_sheepFmtTime(lvSecs ?? secsTotal)} · 进入下一关';
    } else {
      _ovTitle = '全部通关！';
      _ovDesc = '总用时 ${_sheepFmtTime(secsTotal)} · 已同步全站排行';
    }
    _ovRevive = false;
  }

  void _showFailOverlay() {
    _ovTitle = '槽位已满';
    _ovDesc = _revived ? '复活已用完，再试一次吧' : '可复活一次：移出 3 张牌继续';
    _ovRevive = !_revived;
  }

  void _submitScore(double secs) {
    if (_submitted) return;
    _submitted = true;
    if (_bestSecs == null || secs < _bestSecs!) _bestSecs = secs;
    final score = math.max(1, _base - secs.floor());
    context.app.submitScore('sheep', score);
  }

  // --- 快照 / 撤销 ---------------------------------------------------------

  _SheepSnap _snapshot() => _SheepSnap(
    picked: _tiles.map((t) => t.picked).toList(),
    types: _tiles.map((t) => t.type).toList(),
    slotIds: _slots.map((s) => s?.id ?? -1).toList(),
    removedIds: _removed.map((t) => t.id).toList(),
    over: _over,
    won: _won,
    revived: _revived,
  );

  void _pushHistory() => _history.add(_snapshot());

  void _restore(_SheepSnap s) {
    final byId = <int, SheepTile>{for (final t in _tiles) t.id: t};
    for (var i = 0; i < _tiles.length; i++) {
      _tiles[i].picked = s.picked[i];
      _tiles[i].type = s.types[i];
    }
    _slots = List<SheepTile?>.filled(_slotCount, null);
    for (var i = 0; i < _slotCount && i < s.slotIds.length; i++) {
      final id = s.slotIds[i];
      _slots[i] = id < 0 ? null : byId[id];
    }
    _removed
      ..clear()
      ..addAll(s.removedIds.map((id) => byId[id]).whereType<SheepTile>());
    _over = s.over;
    _won = s.won;
    _revived = s.revived;
    if (_over && !_won) {
      _showFailOverlay();
      _stopTicker();
    } else {
      _hideOverlay();
      if (!_over && !_won) _startTicker();
    }
  }

  // --- 道具 ---------------------------------------------------------------

  void _shuffle() {
    if (_over || _shuffleLeft <= 0) return;
    _pushHistory();
    final rem = _tiles.where((t) => !t.picked).toList();
    final types = rem.map((t) => t.type).toList();
    _shuffleList(types, _rnd);
    for (var i = 0; i < rem.length; i++) {
      rem[i].type = types[i];
    }
    _shuffleLeft--;
  }

  /// 撤销：槽满（over）时同样可用；仅通关后（won）禁用。
  void _undo() {
    if (_won || _undoLeft <= 0 || _history.isEmpty) return;
    final snap = _history.removeLast();
    _undoLeft--;
    _restore(snap);
  }

  void _remove() {
    if (_over || _removeLeft <= 0) return;
    final filled = _slots.where((s) => s != null).length;
    if (filled < 3) return;
    _pushHistory();
    var taken = 0;
    for (var i = 0; i < _slotCount && taken < 3; i++) {
      final s = _slots[i];
      if (s != null) {
        _removed.add(s);
        _slots[i] = null;
        taken++;
      }
    }
    _removeLeft--;
    _sortSlots();
  }

  void _revive() {
    if (!_over || _won || _revived) return;
    _pushHistory();
    var taken = 0;
    for (var i = 0; i < _slotCount && taken < 3; i++) {
      final s = _slots[i];
      if (s != null) {
        _removed.add(s);
        _slots[i] = null;
        taken++;
      }
    }
    _sortSlots();
    _revived = true;
    _over = false;
    _hideOverlay();
    _startTicker();
  }

  // --- 构建 ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final filled = _slots.where((s) => s != null).length;
    // web gamesLiveProgress('gsheep')：「第 N 关 · 剩 X 张」
    final left = _tiles.where((t) => !t.picked).length;
    _liveProgress.value = '第 ${_level + 1} 关 · 剩 $left 张';
    return GameSheepView(
      tiles: _tiles,
      slots: _slots,
      removed: _removed,
      fading: List.of(_fading),
      levelText: '${_level + 1} / ${_sheepLevels.length}',
      timeText: _timeText.value,
      timeListenable: _timeText,
      liveProgress: _liveProgress,
      bestText: _bestSecs == null ? '--' : _sheepFmtTime(_bestSecs!),
      shuffleLeft: _shuffleLeft,
      undoLeft: _undoLeft,
      removeLeft: _removeLeft,
      shuffleEnabled: _shuffleLeft > 0 && !_over,
      undoEnabled: _undoLeft > 0 && _history.isNotEmpty && !_won,
      removeEnabled: _removeLeft > 0 && !_over && filled >= 3,
      overlayTitle: _ovTitle,
      overlayDesc: _ovDesc,
      showRevive: _ovRevive,
      onPick: (tile, geom) => setState(() => _pick(tile, geom)),
      onPickRemoved: (tile) => setState(() => _pickRemoved(tile)),
      onNewGame: () => setState(_newGame),
      onRetry: () => setState(_newGame),
      onRank: () => showGameRank(context, game: 'sheep', title: '羊了个羊'),
      onShuffle: () => setState(_shuffle),
      onUndo: () => setState(_undo),
      onRemove: () => setState(_remove),
      onRevive: () => setState(_revive),
    );
  }
}

/// web `GSHEEP_ICONS`：15 个 32×32 手绘 SVG 图案（索引 = 牌型）。
const List<String> _sheepIconBodies = <String>[
  '<g transform="translate(16 16) scale(1.13) translate(-16 -15.6)"><path d="M9 8.6c2 .6 3.8 2.5 4.8 5.6" fill="none" stroke="#5FB84A" stroke-width="2.6" stroke-linecap="round"/><path d="M16 3.6c-1 3-1.4 6.1-1 9.2" fill="none" stroke="#5FB84A" stroke-width="2.6" stroke-linecap="round"/><path d="M23 8.6c-2 .6-3.8 2.5-4.8 5.6" fill="none" stroke="#5FB84A" stroke-width="2.6" stroke-linecap="round"/><path d="M11.2 11.4h9.6L16.9 26.5c-.4 1.4-1.4 1.4-1.8 0z" fill="#F28C28" stroke="#4B3320" stroke-width="1.6" stroke-linejoin="round"/><path d="M12.8 15.4l-1 4.6M16 15.4v3.8M19.2 15.4l1 4.6" fill="none" stroke="#C96A16" stroke-width="1.1" stroke-linecap="round" opacity=".45"/></g>',
  '<g transform="translate(16 16) scale(1.4) translate(-16 -14.6)"><path d="M16 5.8C10.6 10 7 14.7 7 19c0 2.4 2 4.4 4.6 4.4h8.8C23 23.4 25 21.4 25 19c0-4.3-3.6-9-9-13.2z" fill="#EAC24A" stroke="#4B3320" stroke-width="1.6" stroke-linejoin="round"/><path d="M9.6 17.8h12.8" fill="none" stroke="#C79A2E" stroke-width="2" stroke-linecap="round" opacity=".65"/><path d="M12.8 12.6c1.2-1.3 2.6-2 4.2-2.2M10.6 15.6c1-1.2 2.3-1.9 3.6-2.2" fill="none" stroke="#C79A2E" stroke-width="1" stroke-linecap="round" opacity=".6"/></g>',
  '<g transform="translate(16 16) scale(1.063) translate(-15.9 -16)"><rect x="3.4" y="10" width="25.2" height="12" rx="6" fill="#B07A46" stroke="#4B3320" stroke-width="1.6"/><ellipse cx="9.2" cy="16" rx="6" ry="7.2" fill="#E6C293" stroke="#4B3320" stroke-width="1.4"/><ellipse cx="9.2" cy="16" rx="3.4" ry="4" fill="#C89B65"/><ellipse cx="9.2" cy="16" rx="1.4" ry="1.7" fill="#A87848"/><path d="M18 12.6h8.6M18 19.4h6" fill="none" stroke="#8A5C2C" stroke-width="1.2" stroke-linecap="round" opacity=".5"/></g>',
  '<g transform="translate(16 16) scale(1.179) translate(-16 -14.8)"><path d="M16 3.4c1 4-2.6 5.9-4.8 9.1-1.3 2-2 4-2 6 0 4.4 3 7.8 6.8 7.8s6.8-3.4 6.8-7.8c0-2.9-1.4-4.9-2.7-7.2-1 2-2.5 3.1-2.5 3.1S16.6 7.6 16 3.4z" fill="#EF5A2A" stroke="#4B3320" stroke-width="1.6" stroke-linejoin="round"/><path d="M16 13.8c-1.2 2.2-2.9 3.2-2.9 5.5 0 2.1 1.3 3.6 2.9 3.6s2.9-1.5 2.9-3.6c0-2.3-1.7-3.3-2.9-5.5z" fill="#FBD24E"/></g>',
  '<g transform="translate(16 16) scale(1.13) translate(-16 -15.3)"><path d="M16 3.4C12.3 9.2 7.8 13.4 7.8 19c0 4.6 3.7 8.3 8.2 8.3S24.2 23.6 24.2 19c0-5.6-4.5-9.8-8.2-15.6z" fill="#4DA3E0" stroke="#4B3320" stroke-width="1.6" stroke-linejoin="round"/><ellipse cx="12.4" cy="17.6" rx="1.6" ry="3" fill="#DCEFFB" opacity=".85"/><ellipse cx="19.6" cy="21" rx="1" ry="1.7" fill="#BFE0F5" opacity=".7"/></g>',
  '<g transform="translate(16 16) scale(1.098) translate(-16 -15.7)"><path d="M8.8 9.2c.5-3.5 3.4-5.8 7.2-5.8s6.7 2.3 7.2 5.8" fill="none" stroke="#4B3320" stroke-width="1.6" stroke-linecap="round"/><path d="M6.6 9.4h18.8l-1.7 15.2c-.2 1.9-1.8 3.4-3.7 3.4h-8c-1.9 0-3.5-1.5-3.7-3.4z" fill="#6E93AE" stroke="#4B3320" stroke-width="1.6" stroke-linejoin="round"/><ellipse cx="16" cy="9.4" rx="9.4" ry="2.5" fill="#A9C7DB" stroke="#4B3320" stroke-width="1.4"/><path d="M7.4 14.6h17.2" fill="none" stroke="#8DB1C8" stroke-width="2.6" opacity=".9"/><path d="M11.4 18c.3 2.7.6 5.3 1 8M20.6 18c-.3 2.7-.6 5.3-1 8" fill="none" stroke="#587B92" stroke-width="1" stroke-linecap="round" opacity=".4"/></g>',
  '<g transform="translate(16 16) scale(1.089) translate(-14.6 -16)"><path d="M14 15.2 24.6 5.4M14 16.8 24.6 26.6" fill="none" stroke="#98A6B4" stroke-width="3.4" stroke-linecap="round"/><path d="M14 15.2 24.6 5.4M14 16.8 24.6 26.6" fill="none" stroke="#CBD6E0" stroke-width="1.4" stroke-linecap="round"/><path d="M11.6 10 13.9 14.4M11.6 22 13.9 17.6" fill="none" stroke="#8A9AA8" stroke-width="2" stroke-linecap="round"/><circle cx="8.6" cy="7.6" r="4" fill="#F2E7CF" stroke="#4B3320" stroke-width="1.6"/><circle cx="8.6" cy="24.4" r="4" fill="#F2E7CF" stroke="#4B3320" stroke-width="1.6"/><circle cx="16.3" cy="16" r="1.6" fill="#7A8794"/></g>',
  '<g transform="translate(16 16) scale(1.392) translate(-13.7 -16.9)"><path d="M10 26.6V13.8c0-3.5 2.7-6.4 6-6.4s6 2.9 6 6.4v12.8z" fill="#F2E7CF" stroke="#4B3320" stroke-width="1.6" stroke-linejoin="round"/><path d="M8.2 15.6c-1.7-.3-2.9-1.5-2.9-3 0-1.2 1-2 2.2-1.8 1.3.2 2.6 1.3 3.6 2.8" fill="#F2E7CF" stroke="#4B3320" stroke-width="1.5" stroke-linejoin="round"/><path d="M12.8 7.6v4M16 7.2v4.6M19.2 7.6v4" fill="none" stroke="#D3C2A0" stroke-width="1" stroke-linecap="round"/><path d="M10 20.6h12v6H10z" fill="#D96A4A" stroke="#4B3320" stroke-width="1.5" stroke-linejoin="round"/></g>',
  '<g transform="translate(16 16) scale(1.179) translate(-16 -14.3)"><rect x="12.8" y="2.8" width="6.4" height="12.6" rx="3.2" fill="#B07A48" stroke="#4B3320" stroke-width="1.5"/><path d="M9.6 14.2h12.8v5c0 3.7-2.9 6.5-6.4 6.5s-6.4-2.8-6.4-6.5z" fill="#E4D2B0" stroke="#4B3320" stroke-width="1.6" stroke-linejoin="round"/><path d="M12.4 17v7.2M16 17v7.6M19.6 17v7.2" fill="none" stroke="#C3AE86" stroke-width="1.1" stroke-linecap="round"/><path d="M14.4 4.2h3.2" fill="none" stroke="#8E5C2E" stroke-width="1.1" stroke-linecap="round" opacity=".6"/></g>',
  '<g transform="translate(16 16) scale(1.184) translate(-16 -16)"><path d="M11.8 9.8C9.8 7.9 7 7.5 5.3 8.5c2.2 1.7 5 2.3 7.5 1.7z" fill="#6DA84E" stroke="#4B3320" stroke-width="1.4" stroke-linejoin="round"/><path d="M20.2 9.8c2-1.9 4.8-2.3 6.5-1.3-2.2 1.7-5 2.3-7.5 1.7z" fill="#6DA84E" stroke="#4B3320" stroke-width="1.4" stroke-linejoin="round"/><path d="M16 4.6c-3.5 0-6.1 5.1-6.1 11.3S12.5 27.4 16 27.4s6.1-5.3 6.1-11.5S19.5 4.6 16 4.6z" fill="#F0D95A" stroke="#4B3320" stroke-width="1.6" stroke-linejoin="round"/><path d="M10.6 11h10.8M10.1 15.1h11.8M10.6 19.2h10.8M11.4 23.1h9.2" fill="none" stroke="#CFB63F" stroke-width="1" opacity=".7"/></g>',
  '<g transform="translate(16 16) scale(1.205) translate(-16 -15.8)"><circle cx="16" cy="15.8" r="11.2" fill="#F0E9D6" stroke="#4B3320" stroke-width="1.6"/><path d="M8 10c4.7 2.4 8.6 6.9 10.6 14.4M24 10c-2.3 6.3-5.9 10.3-12.7 13.2M9.6 6.2c3.7 3.7 8 4.1 12.3 1.9" fill="none" stroke="#CFC6AC" stroke-width="2" stroke-linecap="round"/><path d="M7.6 20.6c-1.4.8-2.4 2-2.7 3.5" fill="none" stroke="#CFC6AC" stroke-width="2" stroke-linecap="round"/></g>',
  '<g transform="translate(16 16) scale(1.205) translate(-16 -16.2)"><path d="M16 27.4C16 17.6 12.4 9.6 6.4 5c6.6.9 10.9 7.5 9.8 22.4z" fill="#5FAE45" stroke="#4B3320" stroke-width="1.5" stroke-linejoin="round"/><path d="M16 27.4c0-8.7 3.6-15.4 9.6-20-6 .9-9.6 6.7-9.6 20z" fill="#7CC25C" stroke="#4B3320" stroke-width="1.5" stroke-linejoin="round"/><path d="M16 27V15" fill="none" stroke="#4A9034" stroke-width="1" stroke-linecap="round" opacity=".5"/></g>',
  '<g transform="translate(16 16) scale(1.12) translate(-16 -16.2)"><path d="M16 4.4C9 4.4 3.8 9.4 3.8 15.6c0 1.6 1.3 2.8 2.9 2.8h18.6c1.6 0 2.9-1.2 2.9-2.8C28.2 9.4 23 4.4 16 4.4z" fill="#D9534B" stroke="#4B3320" stroke-width="1.6" stroke-linejoin="round"/><ellipse cx="10.6" cy="11.8" rx="2" ry="1.8" fill="#FFF6E6"/><ellipse cx="17.6" cy="9" rx="2.3" ry="2" fill="#FFF6E6"/><ellipse cx="22.6" cy="13.4" rx="1.7" ry="1.5" fill="#FFF6E6"/><path d="M13.2 18.4c.2 3.8 1.1 6.9 2.2 9 .3.7 1 .7 1.3 0 1.1-2.1 2-5.2 2.2-9z" fill="#F2E6CC" stroke="#4B3320" stroke-width="1.6" stroke-linejoin="round"/><path d="M15 21.6h2" fill="none" stroke="#CFBE9C" stroke-width="1" stroke-linecap="round" opacity=".7"/></g>',
  '<g transform="translate(16 16) scale(1.12) translate(-16 -16.8)"><ellipse cx="16" cy="16.8" rx="8.6" ry="10.8" fill="#F7ECD6" stroke="#4B3320" stroke-width="1.6"/><path d="M11.4 12.4c.9-2.5 2.3-4 4-4.6" fill="none" stroke="#FFFDF6" stroke-width="2" stroke-linecap="round" opacity=".9"/><ellipse cx="19.6" cy="21" rx="2.2" ry="3.2" fill="#E8D9BB" opacity=".7"/><path d="M12 22c1.4 1.6 3 2.4 4.6 2.6" fill="none" stroke="#E1D1AF" stroke-width="1.2" stroke-linecap="round"/></g>',
  '<g><g fill="#F2C63C" stroke="#4B3320" stroke-width="1.5" stroke-linejoin="round"><ellipse cx="16" cy="5.6" rx="2.7" ry="4.3"/><ellipse cx="16" cy="5.6" rx="2.7" ry="4.3" transform="rotate(45 16 16)"/><ellipse cx="16" cy="5.6" rx="2.7" ry="4.3" transform="rotate(90 16 16)"/><ellipse cx="16" cy="5.6" rx="2.7" ry="4.3" transform="rotate(135 16 16)"/><ellipse cx="16" cy="5.6" rx="2.7" ry="4.3" transform="rotate(180 16 16)"/><ellipse cx="16" cy="5.6" rx="2.7" ry="4.3" transform="rotate(225 16 16)"/><ellipse cx="16" cy="5.6" rx="2.7" ry="4.3" transform="rotate(270 16 16)"/><ellipse cx="16" cy="5.6" rx="2.7" ry="4.3" transform="rotate(315 16 16)"/></g><circle cx="16" cy="16" r="6.6" fill="#9A6B3C" stroke="#4B3320" stroke-width="1.6"/><circle cx="16" cy="16" r="3.4" fill="#7C5228"/><path d="M14 14c.7-.8 1.6-1.3 2.6-1.4" fill="none" stroke="#B98B54" stroke-width="1.1" stroke-linecap="round" opacity=".75"/></g>',
];

/// 工具条图标（与 web 内联 SVG 一致，stroke 线条宽度 2）。
const String _iconShuffle =
    '<path d="M16 3h5v5"/><path d="M4 20 21 3"/><path d="M21 16v5h-5"/>'
    '<path d="M15 15l6 6"/><path d="M4 4l5 5"/>';
const String _iconUndo =
    '<path d="M3 7v6h6"/>'
    '<path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/>';
const String _iconTrash =
    '<path d="M4 7h16"/><path d="M9 7v-3h6v3"/>'
    '<path d="M6 7l1 13h10l1-13"/>';

/// 牌被上层压住时的滤镜：CSS `filter:brightness(.72) saturate(.55)` 的 sRGB 矩阵近似。
final ColorFilter _lockedFilter = ColorFilter.matrix(const <double>[
  0.4650, 0.2317, 0.0233, 0, 0, //
  0.0690, 0.6277, 0.0233, 0, 0, //
  0.0690, 0.2317, 0.4193, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// 羊了个羊的纯视觉层（golden 测试直接渲染它，状态由 [GameSheepPage] 提供）。
class GameSheepView extends StatelessWidget {
  const GameSheepView({
    super.key,
    this.tiles = const <SheepTile>[],
    this.slots = const <SheepTile?>[],
    this.removed = const <SheepTile>[],
    this.fading = const <(int, int, int)>[],
    this.levelText = '1 / 2',
    this.timeText = '0.0s',
    this.timeListenable,
    this.liveProgress,
    this.bestText = '--',
    this.shuffleLeft = 2,
    this.undoLeft = 3,
    this.removeLeft = 1,
    this.shuffleEnabled = true,
    this.undoEnabled = false,
    this.removeEnabled = false,
    this.overlayTitle,
    this.overlayDesc,
    this.showRevive = false,
    this.onPick,
    this.onPickRemoved,
    this.onNewGame,
    this.onRetry,
    this.onRank,
    this.onShuffle,
    this.onUndo,
    this.onRemove,
    this.onRevive,
  });

  final List<SheepTile> tiles;
  final List<SheepTile?> slots;
  final List<SheepTile> removed;

  /// 三消幽灵 (tileId, type, slot) —— 原位缩放淡出动画。
  final List<(int, int, int)> fading;
  final String levelText;
  final String timeText;
  final ValueListenable<String>? timeListenable;
  final ValueNotifier<String>? liveProgress;
  final String bestText;
  final int shuffleLeft;
  final int undoLeft;
  final int removeLeft;
  final bool shuffleEnabled;
  final bool undoEnabled;
  final bool removeEnabled;
  final String? overlayTitle;
  final String? overlayDesc;
  final bool showRevive;
  final void Function(SheepTile tile, SheepGeom geom)? onPick;
  final ValueChanged<SheepTile>? onPickRemoved;
  final VoidCallback? onNewGame;
  final VoidCallback? onRetry;
  final VoidCallback? onRank;
  final VoidCallback? onShuffle;
  final VoidCallback? onUndo;
  final VoidCallback? onRemove;
  final VoidCallback? onRevive;

  static const int _slotCount = 7;
  static const double _tapeW = 66;
  static const double _tapeH = 20;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      gameKey: 'gsheep',
      title: '羊了个羊',
      // 2026-10-23：恢复「正在玩」条（web gamesLiveMount 对全部 12 个游戏页
      // 统一挂载，v1.5.8 误关）；页面高度超过视口时按 web 行为进滚动流。
      showLive: true,
      liveInScroll: true,
      liveProgress: liveProgress,
      hud: _hud(context),
      boardGap: 14,
      board: LayoutBuilder(
        builder: (context, cons) {
          final availableW = cons.maxWidth.isFinite ? cons.maxWidth : 362.0;
          final tablet = MediaQuery.sizeOf(context).width >= 900;
          final bodyW = tablet ? math.min(480.0, availableW) : availableW;
          // 手机保持 2:3；平板以网页版桌面舞台 480×640 为上限，避免棋盘高过视口。
          final stageH = tablet ? math.min(640.0, bodyW * 1.5) : bodyW * 1.5;
          final boardW = bodyW - 22;
          final removedBlock = removed.isEmpty ? 0.0 : 56.0;
          final boardH = stageH - 2 - 24 - 14 - 50 - removedBlock;
          final geom = SheepGeom.compute(
            boardW: boardW,
            boardH: boardH,
            tiles: tiles,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tools(context),
              const SizedBox(height: 14),
              _stage(
                context,
                bodyW: bodyW,
                stageH: stageH,
                boardW: boardW,
                boardH: boardH,
                geom: geom,
              ),
            ],
          );
        },
      ),
    );
  }

  // --- HUD ------------------------------------------------------------

  Widget _hud(BuildContext context) {
    // kit 标题行盒被 SkParagraph 取整成 42.0（web 25.74*1.65 = 42.471），
    // 整条纵向链会偏高 0.471px；这里补回差值，让 HUD/牌桌/卡槽对齐参考图。
    return Padding(
      padding: const EdgeInsets.only(top: 0.471),
      child: Column(
        key: const ValueKey<String>('sheepHud'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pill(context, '关卡', levelText),
              const SizedBox(width: 9),
              _timePill(context),
              const SizedBox(width: 9),
              _pill(context, '最快', bestText),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GameActionButton(
                label: '新游戏',
                icon: GameIcons.reset,
                primary: true,
                onTap: onNewGame,
              ),
              const SizedBox(width: 8),
              GameActionButton(
                label: '排行榜',
                icon: GameIcons.trophySimple,
                onTap: onRank,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 复刻 web `.g-pill`。kit 的 GameScorePill 行盒会被 SkParagraph 取整成
  /// 20 / 22（web 是 19.8 / 21.85），造成 label 高 1px、value 低 1px；
  /// 这里自绘并用 ±1px 视觉补偿对齐参考图。
  Widget _pill(BuildContext context, String label, String value) {
    final c = context.c;
    return Container(
      width: 62,
      height: 56.64,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.accent),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: const Offset(-1, 1),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AppFonts.noto,
                  fontFamilyFallback: AppFonts.bodyFallback,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.65,
                  letterSpacing: 1.68,
                  color: c.accentInk,
                ),
              ),
            ),
            const SizedBox(height: 1),
            Transform.translate(
              offset: const Offset(0, -1),
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: AppFonts.kalam,
                  fontFamilyFallback: AppFonts.fallback,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: 0.38,
                  color: c.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timePill(BuildContext context) {
    final listenable = timeListenable;
    if (listenable == null) {
      return _pill(context, '用时', timeText);
    }
    return ValueListenableBuilder<String>(
      valueListenable: listenable,
      builder: (context, value, _) => _pill(context, '用时', value),
    );
  }

  // --- 道具条 ---------------------------------------------------------

  Widget _tools(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tool(
          context,
          label: '洗牌',
          count: shuffleLeft,
          icon: _iconShuffle,
          enabled: shuffleEnabled,
          onTap: onShuffle,
        ),
        const SizedBox(width: 10),
        _tool(
          context,
          label: '撤销',
          count: undoLeft,
          icon: _iconUndo,
          enabled: undoEnabled,
          onTap: onUndo,
        ),
        const SizedBox(width: 10),
        _tool(
          context,
          label: '移出',
          count: removeLeft,
          icon: _iconTrash,
          enabled: removeEnabled,
          onTap: onRemove,
        ),
      ],
    );
  }

  Widget _tool(
    BuildContext context, {
    required String label,
    required int count,
    required String icon,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    final c = context.c;
    final row = Container(
      height: 37,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // web：`.gsheep-tool svg{filter:drop-shadow(0 1px 0 rgba(90,55,20,.5))}`
          SizedBox(
            width: 16,
            height: 16,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 1,
                  child: gameIcon(
                    icon,
                    size: 16,
                    color: const Color(0x805A3714),
                  ),
                ),
                gameIcon(icon, size: 16, color: c.accentInk),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 19 / 13,
              color: c.ink2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: AppFonts.noto,
              fontFamilyFallback: AppFonts.bodyFallback,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 19 / 13,
              color: c.mintInk,
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Opacity(opacity: enabled ? 1 : .45, child: row),
    );
  }

  // --- 舞台（纸面 + 纸胶带 + 牌桌 + 卡槽） -----------------------------

  Widget _stage(
    BuildContext context, {
    required double bodyW,
    required double stageH,
    required double boardW,
    required double boardH,
    required SheepGeom geom,
  }) {
    final c = context.c;
    return SizedBox(
      key: const ValueKey<String>('sheepStage'),
      width: bodyW,
      height: stageH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CssShadowLayer(
              radius: 14,
              shadows: const <CssShadowSpec>[
                // CSS box-shadow 列表「先写的在上层」，kit 是后写覆盖先写 → 反序。
                CssShadowSpec(
                  color: Color(0x4D5A4A2C),
                  offset: Offset(0, 8),
                  blur: 20,
                  spread: -12,
                ),
                CssShadowSpec(
                  color: Color(0x0E5A4A2C),
                  offset: Offset(0, 1),
                  blur: 2,
                ),
              ],
              child: SizedBox.expand(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              // web 是 border-box：舞台 1px 边框 + padding(10,14,10,10) 都在盒内，
              // 所以 Flutter 里内容区的 padding 各加 1px 边框宽。
              padding: const EdgeInsets.fromLTRB(11, 15, 11, 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: boardW,
                    height: boardH,
                    child: _board(context, geom),
                  ),
                  const SizedBox(height: 14),
                  // web 卡槽盒顶 776.0（参考图边框整像素落在 776 行），
                  // 布局链给的是 776.3，故视觉上移 0.303。
                  Transform.translate(
                    offset: const Offset(0, -0.303),
                    child: _slotsRow(context, boardW),
                  ),
                  if (removed.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _removedRow(context, boardW),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            left: (bodyW - _tapeW) / 2,
            top: -9,
            child: const GameTape(
              width: _tapeW,
              height: _tapeH,
              angle: 1.6,
              color: Color(0x99F4D678),
            ),
          ),
          if (overlayTitle != null) Positioned.fill(child: _overlay(context)),
        ],
      ),
    );
  }

  Widget _board(BuildContext context, SheepGeom geom) {
    final lockedIds = <int>{};
    for (final t in tiles) {
      if (!t.picked && geom.isLocked(tiles, t)) lockedIds.add(t.id);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final t in tiles)
          if (!t.picked)
            Positioned(
              left: geom.leftOf(t),
              top: geom.topOf(t) - 0.3,
              width: geom.ts,
              height: geom.ts,
              child: GestureDetector(
                key: ValueKey<String>('sheepTile${t.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: onPick == null ? null : () => onPick!(t, geom),
                child: _tileCard(
                  context,
                  size: geom.ts,
                  type: t.type,
                  locked: lockedIds.contains(t.id),
                ),
              ),
            ),
      ],
    );
  }

  /// 一张贴纸牌：纸面 + 1px 边 + 双层投影（web `.gsheep-tile-inner`）。
  Widget _tileCard(
    BuildContext context, {
    required double size,
    required int type,
    bool locked = false,
  }) {
    final c = context.c;
    final radius = BorderRadius.circular(10);
    final iconSize = (size - 2) * 0.8;
    final card = Stack(
      children: [
        Positioned.fill(
          child: CssShadowLayer(
            radius: 10,
            // CSS box-shadow 列表里「先写的在上层」，kit 是按列表顺序后写覆盖先写，
            // 所以这里把模糊阴影放前面、2px 实色阴影放最后。
            shadows: locked
                ? const <CssShadowSpec>[
                    CssShadowSpec(
                      color: Color(0x24584A28),
                      offset: Offset(0, 3),
                      blur: 6,
                    ),
                    CssShadowSpec(
                      color: Color(0x59967E5C),
                      offset: Offset(0, 2),
                    ),
                  ]
                : const <CssShadowSpec>[
                    CssShadowSpec(
                      color: Color(0x805A4A2C),
                      offset: Offset(0, 6),
                      blur: 14,
                      spread: -8,
                    ),
                    CssShadowSpec(
                      color: Color(0xFFD2C8B0),
                      offset: Offset(0, 2),
                    ),
                  ],
            child: SizedBox.expand(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: radius,
                  border: Border.all(color: c.line2),
                ),
              ),
            ),
          ),
        ),
        if (locked)
          Positioned.fill(
            child: IgnorePointer(
              // web 的 `inset 0 0 0 999px rgba(46,44,34,.22)` 画在 padding box
              // （边框内侧），边框本身不受影响，所以这里内缩 1px、圆角 9。
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x382E2C22),
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ),
        Center(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
            child: SvgPicture.string(
              _sheepSvg(type),
              width: iconSize,
              height: iconSize,
            ),
          ),
        ),
      ],
    );
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: locked
            ? ColorFiltered(colorFilter: _lockedFilter, child: card)
            : card,
      ),
    );
  }

  // --- 底部 7 个卡槽 --------------------------------------------------

  Widget _slotsRow(BuildContext context, double width) {
    final c = context.c;
    const slotSize = 34.0;
    // web 是 border-box：50 = 1 边框 + 7 padding + 34 卡槽。Flutter 的边框不占布局，
    // 所以 padding 各加 1px，inset 阴影单独铺在整盒（边框内）上。
    return Container(
      key: const ValueKey<String>('sheepSlots'),
      width: width,
      height: 50,
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line2),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _InsetTopPainter(color: Color(0x155A4A2C)),
              ),
            ),
          ),
          Padding(
            // 边框已被 Container 当作内边距（1px），web 是 1 + 7；再补 0.303
            // 让卡槽虚线框落在参考图的 784.3。
            padding: const EdgeInsets.fromLTRB(7, 7.303, 7, 6.697),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slotCount; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  SizedBox(
                    width: slotSize,
                    height: slotSize,
                    child: _slot(context, i, slotSize),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slot(BuildContext context, int index, double size) {
    final c = context.c;
    final tile = index < slots.length ? slots[index] : null;
    final ghosts = fading.where((e) => e.$3 == index).toList();
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DashedRRectPainter(color: c.line2, radius: 10),
            ),
          ),
        ),
        if (tile != null)
          Positioned(
            left: 2,
            top: 2,
            child: _tileCard(context, size: size - 4, type: tile.type),
          ),
        // v1.6.0：三消幽灵——牌在原槽位放大 + 淡出（web 版的瞬时消失在
        // 手机上显得生硬，用户反馈要消失动画）。
        for (final g in ghosts)
          Positioned.fill(
            key: ValueKey<String>('fade-${g.$1}'),
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                builder: (ctx, t, child) => Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Transform.scale(scale: 1 + 0.45 * t, child: child),
                ),
                child: Center(
                  child: _tileCard(context, size: size - 4, type: g.$2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 移出区（web `#gsheepRemoved`，`--gsheep-removed-*`）：横向排列被移出的牌。
  Widget _removedRow(BuildContext context, double width) {
    final c = context.c;
    return Container(
      width: width,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < removed.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            SizedBox(
              width: 36,
              height: 36,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPickRemoved == null
                    ? null
                    : () => onPickRemoved!(removed[i]),
                child: Opacity(
                  opacity: .85,
                  child: _tileCard(context, size: 36, type: removed[i].type),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- 结算遮罩 -------------------------------------------------------

  Widget _overlay(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF6F6EFDF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xF2FFF8EA)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              overlayTitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.zcool,
                fontFamilyFallback: AppFonts.fallback,
                fontSize: 26,
                fontWeight: FontWeight.w400,
                letterSpacing: 26 * 0.02,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                overlayDesc ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFonts.noto,
                  fontFamilyFallback: AppFonts.bodyFallback,
                  fontSize: 14,
                  height: 1.6,
                  color: c.ink2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GameActionButton(label: '再来一局', primary: true, onTap: onRetry),
                if (showRevive) ...[
                  const SizedBox(width: 10),
                  GameActionButton(label: '复活（移出 3 张）', onTap: onRevive),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _sheepSvg(int type) {
  final i = type < 0
      ? 0
      : (type >= _sheepIconBodies.length ? _sheepIconBodies.length - 1 : type);
  // Chrome 的 SVG 描边比 Skia 细一点（AA 更亮），按参考图把 stroke-width 收 5%，
  // 使贴纸牌图标的墨色像素量和浏览器版对齐。
  final body = _sheepIconBodies[i].replaceAllMapped(
    RegExp(r'stroke-width="([0-9.]+)"'),
    (m) {
      final w = double.parse(m[1]!);
      return 'stroke-width="${(w * _iconStrokeScale).toStringAsFixed(2)}"';
    },
  );
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'
      '$body</svg>';
}

/// 图标描边收细系数（见 [_sheepSvg]）。
const double _iconStrokeScale = 1.0;

/// 虚线圆角边框（卡槽 `border:1px dashed`）：按 PathMetrics 等距切段。
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _dash = 3;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final next = math.min(d + _dash, metric.length);
        canvas.drawPath(metric.extractPath(d, next), paint);
        d = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// 卡槽容器顶部内阴影（web `box-shadow:inset 0 2px 6px rgba(90,74,44,.12)`）。
class _InsetTopPainter extends CustomPainter {
  const _InsetTopPainter({required this.color});

  final Color color;

  /// 逐行衰减比例（取自 web 截图的 inset 阴影剖面，深度 8px）。
  static const List<double> _fade = <double>[
    1,
    .82,
    .55,
    .45,
    .28,
    .18,
    .10,
    .05,
    0,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 4 || size.height <= 4) return;
    // 注意：Container 带 border 且未设 padding 时，边框会被当作 child 的内边距
    // （等价 border-box），所以这里的 (0,0) 已经是 border 内侧，阴影从边框下沿起算。
    final inner = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(inner, const Radius.circular(9)));
    final depth = math.min(8.0, inner.height);
    final span = depth / inner.height;
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        for (final f in _fade) color.withValues(alpha: color.a * f),
      ],
      stops: <double>[
        for (var i = 0; i < _fade.length; i++) (i * span / (_fade.length - 1)),
      ],
    ).createShader(inner);
    canvas.drawRect(inner, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InsetTopPainter old) => old.color != color;
}
