import 'dart:math' as math;

import 'sudoku_puzzle.dart';

/// 九宫异形种子：每行一条宫形切分，0–8 为区域编号，用 / 分隔。
/// 这些种子与 [standardSolution] 配套；运行时再叠加旋转/镜像/宫行置换。
const List<String> kJigsawNineSeeds = [
  '555111177/555511177/355011877/300088887/300008887/333022867/332222666/344222666/444444466',
  '222222000/555222400/555544400/551444440/111177770/611117733/666777333/668888333/666888883',
  '055537777/005533777/000533776/008533666/408553666/488883626/448811222/448111222/444111122',
  '666666555/333666055/333300055/337000005/777777775/888811111/888881111/444222222/444444222',
  '006644444/000666444/000663477/505663777/555133377/555113337/511113227/888112222/888888222',
  '664457777/666455777/666455772/161455222/111445222/111435282/100433888/000333888/000033388',
  '444466666/044444666/000078688/007778888/007777858/111173355/111113555/222333355/222222335',
  '355577666/355557766/335577766/330007786/330000086/434401188/444111188/442211188/422222228',
  '222227666/442227366/442777366/447733336/547711336/544111300/551111000/558888000/555888880',
  '444448888/334444888/333300882/330000222/135000222/155555272/115566777/115666777/111666677',
  '888833344/788833334/788663304/766660004/776660004/777550504/722555554/222111154/222211111',
  '655555444/666555544/666333444/663333114/888330011/888800111/880000011/777222222/777777222',
  '877777333/822777733/822444433/822444553/882445513/882255511/800551111/000666611/000066666',
  '220000444/222000044/222701444/327711114/333771155/333771155/338776555/888666665/888886665',
  '887777444/888777744/888575444/185555554/111222500/111222000/112220000/333666666/333333666',
  '255000000/225666000/225666667/225564777/825544777/825344717/883334111/883334111/888334411',
  '211111188/223311188/223333588/223355548/627355548/627750548/667700044/667700044/666770044',
  '551116666/551111666/055113668/053333888/055333388/000777778/004477778/044222228/444442222',
  '444444888/555444788/555577788/552777608/222776608/222266600/211663300/111633300/111133330',
  '666777777/666666777/033335558/033335888/003555888/000544828/001544222/111444222/111114422',
  '666688888/166600888/166000822/110005222/110555422/111544442/555544442/777333333/777777333',
  '000002222/330001222/330111226/331114666/531144466/533844446/558884776/558887776/555887777',
  '888800055/188880005/118770055/117773035/117773335/611673335/666663445/222664444/222222444',
  '336666666/433000662/433000002/433101822/443111882/444111882/455177882/555777782/555577782',
];

/// 八臂雪花模板：中心 3×3 + 8 条臂，每区 9 格且连通。
const List<String> kSnowflakeSeeds = [
  '333355444/333555444/338555544/888000664/888000666/288000666/227777611/222777111/222771111',
  '888811155/888811155/444811155/444000555/444000222/777000222/773336222/773336666/773336666',
  // 上面两个基础形的 90° 版本，作为独立固定模板（仍只做固定变换，不搜索）。
  '222288333222888333227888833777000553777000555177000555116666544111666444111664444',
  '777744488777744488333744488333000888333000111666000111662225111662225555662225555',
];

/// 与 [kSnowflakeSeeds] 配套的满解（预计算，避免运行时反复重解宫形）。
const List<String> kSnowflakeSolutions = [
  '573419628918264375621375894352986741867542139249731586184697253796853412435128967',
  '573419628918625437469283715825371946137968254681542379352794861246857193794136582',
  '471283695398465217564972183186759324259348761837126549942517836615834972723691458',
  '723618495945832617462175983187593264359467821674281359518329746896754132231946578',
];

List<int> decodeRegionSeed(String seed) {
  final cells = <int>[];
  for (var i = 0; i < seed.length; i++) {
    final code = seed.codeUnitAt(i);
    if (code != 0x2F) cells.add(code - 0x30);
  }
  return cells;
}

List<int> standardSolution() => [
  for (var r = 0; r < 9; r++)
    for (var c = 0; c < 9; c++) (r * 3 + r ~/ 3 + c) % 9 + 1,
];

List<int> standardRegions() => [
  for (var r = 0; r < 9; r++)
    for (var c = 0; c < 9; c++) (r ~/ 3) * 3 + c ~/ 3,
];

/// 8 种旋转/镜像：0 原样，1 逆时针，2 180°，3 顺时针，4–7 镜像后再旋转。
List<int> transformGrid(List<int> grid, int n, int turn) {
  final out = List<int>.filled(n * n, 0);
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final src = switch (turn) {
        1 => (n - 1 - c) * n + r,
        2 => (n - 1 - r) * n + (n - 1 - c),
        3 => c * n + (n - 1 - r),
        4 => r * n + (n - 1 - c),
        5 => (n - 1 - r) * n + c,
        6 => c * n + r,
        7 => (n - 1 - c) * n + (n - 1 - r),
        _ => r * n + c,
      };
      out[r * n + c] = grid[src];
    }
  }
  return out;
}

List<int> permuteGrid(
  List<int> grid,
  int n,
  List<int> rowPerm,
  List<int> colPerm,
) => [
  for (final r in rowPerm)
    for (final c in colPerm) grid[r * n + c],
];

List<int> bandRows(math.Random rnd) {
  final bands = [0, 1, 2]..shuffle(rnd);
  return [
    for (final b in bands)
      for (final r in ([0, 1, 2]..shuffle(rnd))) b * 3 + r,
  ];
}

List<int> bandCols(math.Random rnd) {
  final stacks = [0, 1, 2]..shuffle(rnd);
  return [
    for (final s in stacks)
      for (final c in ([0, 1, 2]..shuffle(rnd))) s * 3 + c,
  ];
}

bool regionConnected(List<int> regions, int region) {
  final cells = <int>[];
  for (var i = 0; i < regions.length; i++) {
    if (regions[i] == region) cells.add(i);
  }
  if (cells.isEmpty) return false;
  final seen = <int>{cells.first};
  final queue = <int>[cells.first];
  while (queue.isNotEmpty) {
    final i = queue.removeLast();
    final r = i ~/ 9;
    final c = i % 9;
    for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nr = r + dr;
      final nc = c + dc;
      if (nr < 0 || nr >= 9 || nc < 0 || nc >= 9) continue;
      final ni = nr * 9 + nc;
      if (regions[ni] != region || !seen.add(ni)) continue;
      queue.add(ni);
    }
  }
  return seen.length == cells.length;
}

bool regionsConnected(List<int> regions) {
  for (var k = 0; k < 9; k++) {
    if (!regionConnected(regions, k)) return false;
  }
  return true;
}

bool regionsMatchSolution(List<int> regions, List<int> solution) {
  for (var k = 0; k < 9; k++) {
    final digits = <int>{};
    var count = 0;
    for (var i = 0; i < 81; i++) {
      if (regions[i] != k) continue;
      count++;
      if (!digits.add(solution[i])) return false;
    }
    if (count != 9 || digits.length != 9) return false;
  }
  return true;
}

List<List<int>> regionUnits(List<int> regions) => [
  for (var k = 0; k < 9; k++)
    [
      for (var i = 0; i < 81; i++)
        if (regions[i] == k) i,
    ],
];

List<List<int>> classicUnits({bool diagonal = false}) {
  final units = <List<int>>[
    for (var r = 0; r < 9; r++) [for (var c = 0; c < 9; c++) r * 9 + c],
    for (var c = 0; c < 9; c++) [for (var r = 0; r < 9; r++) r * 9 + c],
    for (var br = 0; br < 3; br++)
      for (var bc = 0; bc < 3; bc++)
        [
          for (var r = 0; r < 3; r++)
            for (var c = 0; c < 3; c++) (br * 3 + r) * 9 + bc * 3 + c,
        ],
  ];
  if (diagonal) {
    units.add([for (var i = 0; i < 9; i++) i * 9 + i]);
    units.add([for (var i = 0; i < 9; i++) i * 9 + (8 - i)]);
  }
  return units;
}

/// 三面立方的满解（217 位，按 [cubeFaceMaps] 的全局索引顺序）。
/// 运行时只做数字置换/挖洞，保证 3D 出题稳定且可复现。
const List<String> kCubeFaceSolutions = [
  '5237486914189365729671254383845627192763918451958742637412539868596173246324891574973158628152673499715346285648219733287965141869724357431582962596437816937481547521638316524975471892628963751731862499543718286249573',
  '2376819544815972369652438171268354797431695825987243618793126453549761286124587938392176547546392812683945174917658325738214699451763281275839463869421759135876225836497824195361397468567583214346259715914782378261349',
  '3624591781876329549548713268239475617915264835461837922153986474387652196792148351428537963586794128379251649647312582154689735831926474963875217215463899237854157149638659873123126549748721956234961857953286416854723',
  '1659724834386517299728341568574169326945238713217986452831675945463892177192453683856794212468137959235861475781249361649378526327915848974526134513682794857936227146839823956141578429364913785532689719185742676432158',
];

/// 3D 三面立方的几何：三个可见面共享边上的格只存一份。
///
/// 全局索引约定（UI 必须通过 [faces] 取，不要硬编码）：
/// - top: 0–80，`r*9+c`；
/// - frontLeft: 0–80 的面内坐标映射到 top 底边 + 新增 81–152；
/// - frontRight: 新增 153–216；
/// - 总物理格 217。
///
/// 共享边（与 UI 的等距投影一致）：
/// - top(8,c) ↔ frontLeft(0,c)；
/// - top(r,8) ↔ frontRight(0,r)；
/// - frontLeft(r,8) ↔ frontRight(r,8)。
class CubeFaceLayout {
  const CubeFaceLayout({
    required this.faces,
    required this.units,
    required this.regions,
    required this.cellCount,
  });

  final List<SudokuCubeFaceMap> faces;
  final List<List<int>> units;

  /// 每格的主面宫号 0–26（top 0–8，frontLeft 9–17，frontRight 18–26）。
  final List<int> regions;
  final int cellCount;
}

List<SudokuCubeFaceMap> cubeFaceMaps() {
  final top = <int>[for (var i = 0; i < 81; i++) i];
  final frontLeft = List<int>.filled(81, -1);
  final frontRight = List<int>.filled(81, -1);

  for (var c = 0; c < 9; c++) {
    frontLeft[c] = 8 * 9 + c; // top(8,c)
  }
  var next = 81;
  for (var r = 1; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      frontLeft[r * 9 + c] = next++;
    }
  }

  for (var c = 0; c < 9; c++) {
    frontRight[c] = c * 9 + 8; // top(c,8)
  }
  for (var r = 1; r < 9; r++) {
    frontRight[r * 9 + 8] = frontLeft[r * 9 + 8];
  }
  for (var r = 1; r < 9; r++) {
    for (var c = 0; c < 8; c++) {
      frontRight[r * 9 + c] = next++;
    }
  }

  return [
    SudokuCubeFaceMap(
      face: SudokuCubeFace.top,
      cells: top,
      sharedEdgeCells: {
        for (var i = 0; i < 9; i++) 8 * 9 + i,
        for (var i = 0; i < 9; i++) i * 9 + 8,
      },
    ),
    SudokuCubeFaceMap(
      face: SudokuCubeFace.frontLeft,
      cells: frontLeft,
      sharedEdgeCells: {
        for (var i = 0; i < 9; i++) i,
        for (var i = 0; i < 9; i++) i * 9 + 8,
      },
    ),
    SudokuCubeFaceMap(
      face: SudokuCubeFace.frontRight,
      cells: frontRight,
      sharedEdgeCells: {
        for (var i = 0; i < 9; i++) i * 9 + 8,
        for (var i = 0; i < 9; i++) i,
      },
    ),
  ];
}

CubeFaceLayout cubeFaceLayout() {
  final faces = cubeFaceMaps();
  final raw = <List<int>>[];
  for (final face in faces) {
    for (var r = 0; r < 9; r++) {
      raw.add([for (var c = 0; c < 9; c++) face.cells[r * 9 + c]]);
    }
    for (var c = 0; c < 9; c++) {
      raw.add([for (var r = 0; r < 9; r++) face.cells[r * 9 + c]]);
    }
    for (var br = 0; br < 3; br++) {
      for (var bc = 0; bc < 3; bc++) {
        raw.add([
          for (var r = 0; r < 3; r++)
            for (var c = 0; c < 3; c++)
              face.cells[(br * 3 + r) * 9 + bc * 3 + c],
        ]);
      }
    }
  }
  // 共享边上的行/列在两面是同一组格，排序后去重（81 → 78）。
  final seen = <String>{};
  final units = <List<int>>[];
  for (final unit in raw) {
    final sorted = [...unit]..sort();
    if (seen.add(sorted.join(','))) units.add(sorted);
  }

  final cellCount = faces.expand((f) => f.cells).toSet().length;
  final regions = List<int>.filled(cellCount, -1);
  for (var fi = 0; fi < faces.length; fi++) {
    final face = faces[fi];
    for (var br = 0; br < 3; br++) {
      for (var bc = 0; bc < 3; bc++) {
        final region = fi * 9 + br * 3 + bc;
        for (var r = 0; r < 3; r++) {
          for (var c = 0; c < 3; c++) {
            final index = face.cells[(br * 3 + r) * 9 + bc * 3 + c];
            if (regions[index] < 0) regions[index] = region;
          }
        }
      }
    }
  }

  return CubeFaceLayout(
    faces: faces,
    units: units,
    regions: regions,
    cellCount: cellCount,
  );
}

class OverlapLayout {
  const OverlapLayout({
    required this.rows,
    required this.cols,
    required this.grids,
  });

  final int rows;
  final int cols;
  final List<SudokuSubGrid> grids;
}

OverlapLayout overlapLayout(int count) {
  final origins = <(int, int)>[];
  var rows = 9;
  var cols = 9;
  switch (count) {
    case 2:
      // 斜向错位：两盘共享右下 3×3（rows 6–8 × cols 6–8）。
      origins.addAll([(0, 0), (6, 6)]);
      rows = 15;
      cols = 15;
      break;
    case 3:
      // 沿对角线级联：每次下移 6、右移 3；相邻实际共享 3 行 × 6 列
      // = 18 格（参考图三中高亮的 3×3 只是其中一个宫块）。
      origins.addAll([(0, 0), (6, 3), (12, 6)]);
      rows = 21;
      cols = 15;
      break;
    case 4:
      // 风车：四个子盘围绕中心空洞，各自只与相邻两盘共享 3×3 宫。
      origins.addAll([(0, 6), (6, 0), (6, 12), (12, 6)]);
      rows = 21;
      cols = 21;
      break;
    case 5:
      // Samurai：中心 + 四角，每个外盘与中心共享 3×3。
      origins.addAll([(0, 0), (12, 0), (0, 12), (12, 12), (6, 6)]);
      rows = 21;
      cols = 21;
      break;
    case 8:
      for (var br = 0; br < 3; br++) {
        for (var bc = 0; bc < 3; bc++) {
          if (br == 1 && bc == 1) continue;
          origins.add((br * 6, bc * 6));
        }
      }
      rows = 21;
      cols = 21;
      break;
    case 13:
      // 参考图四：5×5 棋盘格取 i+j 为偶数的 13 个位置，包围盒 33×33。
      // 相邻行/列错开 6，因此只有斜向相邻的子盘共享 3×3；
      // 共 16 个共享块、144 个共享格，active = 13*81 - 144 = 909。
      for (var i = 0; i < 5; i++) {
        for (var j = 0; j < 5; j++) {
          if ((i + j).isOdd) continue;
          origins.add((i * 6, j * 6));
        }
      }
      rows = 33;
      cols = 33;
      break;
    default:
      origins.addAll([(0, 0), (0, 6)]);
      cols = 15;
  }
  return OverlapLayout(
    rows: rows,
    cols: cols,
    grids: [
      for (final (top, left) in origins) SudokuSubGrid(top: top, left: left),
    ],
  );
}

/// 参考图一：五盘风车式堆叠，中心盘与四个外盘各共享 3 行 × 6 列（18 格），
/// 外盘之间互不重叠；active = 5×81 - 4×18 = 333。
/// 顺序按顺时针 TL → TR → BR → BL → 中心，配色与参考图的黄/粉交替一致。
OverlapLayout windmillLayout() => const OverlapLayout(
  rows: 21,
  cols: 21,
  grids: [
    SudokuSubGrid(top: 0, left: 3),
    SudokuSubGrid(top: 3, left: 12),
    SudokuSubGrid(top: 12, left: 9),
    SudokuSubGrid(top: 9, left: 0),
    SudokuSubGrid(top: 6, left: 6),
  ],
);

List<int> overlapSolution(int rows, int cols) => [
  for (var r = 0; r < rows; r++)
    for (var c = 0; c < cols; c++) (3 * (r % 3) + (r ~/ 3) + c) % 9 + 1,
];

List<bool> overlapActive(List<SudokuSubGrid> grids, int rows, int cols) {
  final active = List<bool>.filled(rows * cols, false);
  for (final g in grids) {
    for (var r = 0; r < g.size; r++) {
      for (var c = 0; c < g.size; c++) {
        final row = g.top + r;
        final col = g.left + c;
        if (row < 0 || row >= rows || col < 0 || col >= cols) continue;
        active[row * cols + col] = true;
      }
    }
  }
  return active;
}

List<List<int>> overlapUnits(List<SudokuSubGrid> grids, int rows, int cols) {
  final units = <List<int>>[];
  for (final g in grids) {
    int at(int r, int c) => (g.top + r) * cols + (g.left + c);
    for (var r = 0; r < 9; r++) {
      units.add([for (var c = 0; c < 9; c++) at(r, c)]);
    }
    for (var c = 0; c < 9; c++) {
      units.add([for (var r = 0; r < 9; r++) at(r, c)]);
    }
    for (var br = 0; br < 3; br++) {
      for (var bc = 0; bc < 3; bc++) {
        units.add([
          for (var r = 0; r < 3; r++)
            for (var c = 0; c < 3; c++) at(br * 3 + r, bc * 3 + c),
        ]);
      }
    }
  }
  return units;
}

class JigsawLayout {
  const JigsawLayout({required this.regions, required this.solution});

  final List<int> regions;
  final List<int> solution;
}

JigsawLayout randomJigsawLayout(math.Random rnd) {
  final seed = kJigsawNineSeeds[rnd.nextInt(kJigsawNineSeeds.length)];
  final turn = rnd.nextInt(8);
  var regions = transformGrid(decodeRegionSeed(seed), 9, turn);
  var solution = transformGrid(standardSolution(), 9, turn);

  // 宫行置换能在保持数独行的同时改变宫形；只接受仍然连通的置换。
  for (var attempt = 0; attempt < 12; attempt++) {
    final rows = bandRows(rnd);
    final cols = bandCols(rnd);
    final nextRegions = permuteGrid(regions, 9, rows, cols);
    final nextSolution = permuteGrid(solution, 9, rows, cols);
    if (regionsConnected(nextRegions) &&
        regionsMatchSolution(nextRegions, nextSolution)) {
      regions = nextRegions;
      solution = nextSolution;
      break;
    }
  }

  final digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(rnd);
  solution = [for (final v in solution) digits[v - 1]];
  return JigsawLayout(regions: regions, solution: solution);
}

List<int> decodeSolution(String seed) => [
  for (final code in seed.codeUnits) code - 0x30,
];

/// 雪花模板只做固定模板的旋转/镜像，运行时不做任何宫形搜索。
/// 当前为 4 个固定条目（两个基础形 + 各自 90° 版本），形状是
/// 中心 3×3 + 八花瓣（4 重对称）。正方形 9×9 网格不存在严格的 60°
/// 六重旋转；若产品必须视觉 6 臂，需要另做非对称近似模板。
/// 满解随模板一起旋转/镜像，再整体做数字置换。
JigsawLayout randomSnowflakeLayout(math.Random rnd) {
  final index = rnd.nextInt(kSnowflakeSeeds.length);
  final turn = rnd.nextInt(8);
  final regions = transformGrid(
    decodeRegionSeed(kSnowflakeSeeds[index]),
    9,
    turn,
  );
  final solution = digitsPermuted(
    transformGrid(decodeSolution(kSnowflakeSolutions[index]), 9, turn),
    rnd,
  );
  return JigsawLayout(regions: regions, solution: solution);
}

List<int> digitsPermuted(List<int> grid, math.Random rnd) {
  final digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(rnd);
  return [for (final v in grid) digits[v - 1]];
}
