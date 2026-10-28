/// 数独统一入口的模式目录：经典、异形、高级阶数。
///
/// 这里只描述“有哪些模式、每档难度叫什么、排行榜用什么键”，
/// 出题与判定由纯 Dart 内核（sudoku_kernel.dart）负责。
enum SudokuVariant {
  classic,
  jigsaw,
  snowflake,
  overlap,
  evenOdd,
  diagonal,
  inequality,
  killer,
  cube3d,
}

enum SudokuDifficulty { easy, medium, hard, expert }

enum SudokuGroup { classic, jigsaw, advanced }

extension SudokuDifficultyX on SudokuDifficulty {
  String get key => switch (this) {
    SudokuDifficulty.easy => 'easy',
    SudokuDifficulty.medium => 'medium',
    SudokuDifficulty.hard => 'hard',
    SudokuDifficulty.expert => 'expert',
  };

  String get label => switch (this) {
    SudokuDifficulty.easy => '简单',
    SudokuDifficulty.medium => '中等',
    SudokuDifficulty.hard => '困难',
    SudokuDifficulty.expert => '专家',
  };

  int get tier => index;
}

class SudokuModeSpec {
  const SudokuModeSpec({
    required this.variant,
    required this.group,
    required this.key,
    required this.title,
    required this.blurb,
    required this.difficulties,
    this.overlapCount = 0,
    this.hidden = false,
  });

  final SudokuVariant variant;
  final SudokuGroup group;
  final String key;
  final String title;
  final String blurb;
  final List<SudokuDifficulty> difficulties;
  final int overlapCount;

  /// 仅保留给旧内核/测试的隐藏模式，不进入模式选择 UI。
  final bool hidden;

  bool get isOverlap => variant == SudokuVariant.overlap;

  /// 排行榜 / 本地最佳 / 提交分数使用的难度键。
  ///
  /// 经典数独沿用旧键 easy/med/hard/exp，历史成绩不丢；
  /// 其余模式统一加模式前缀，避免不同变体互相串榜。
  String rankKey(SudokuDifficulty difficulty) {
    if (key == 'windmill') return 'windmill-${difficulty.key}';
    if (isOverlap) return 'overlap-$overlapCount';
    return switch (variant) {
      SudokuVariant.classic => switch (difficulty) {
        SudokuDifficulty.easy => 'easy',
        SudokuDifficulty.medium => 'med',
        SudokuDifficulty.hard => 'hard',
        SudokuDifficulty.expert => 'exp',
      },
      SudokuVariant.jigsaw => 'jigsaw-${difficulty.key}',
      SudokuVariant.snowflake => 'snowflake-${difficulty.key}',
      SudokuVariant.evenOdd => 'evenodd-${difficulty.key}',
      SudokuVariant.diagonal => 'diag-${difficulty.key}',
      SudokuVariant.inequality => 'ineq-${difficulty.key}',
      SudokuVariant.killer => 'killer-${difficulty.key}',
      SudokuVariant.cube3d => 'cube3d-${difficulty.key}',
      SudokuVariant.overlap => 'overlap-$overlapCount',
    };
  }

  List<(String, String)> get rankDifficulties => [
    for (final d in difficulties) (rankKey(d), isOverlap ? title : d.label),
  ];

  SudokuDifficulty get defaultDifficulty => difficulties.first;
}

const List<SudokuModeSpec> kSudokuModes = [
  SudokuModeSpec(
    variant: SudokuVariant.classic,
    group: SudokuGroup.classic,
    key: 'classic',
    title: '经典九宫',
    blurb: '原本的四档难度，全部保留',
    difficulties: [
      SudokuDifficulty.easy,
      SudokuDifficulty.medium,
      SudokuDifficulty.hard,
      SudokuDifficulty.expert,
    ],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.jigsaw,
    group: SudokuGroup.jigsaw,
    key: 'jigsaw',
    title: '九宫异形',
    blurb: '宫形自由生长，每局都不一样',
    difficulties: [
      SudokuDifficulty.medium,
      SudokuDifficulty.hard,
      SudokuDifficulty.expert,
    ],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.overlap,
    group: SudokuGroup.jigsaw,
    key: 'windmill',
    title: '风车数独',
    blurb: '五盘风车式错位，共享 3×6 同数',
    difficulties: [SudokuDifficulty.expert],
    overlapCount: 5,
  ),
  SudokuModeSpec(
    variant: SudokuVariant.snowflake,
    group: SudokuGroup.jigsaw,
    key: 'snowflake',
    title: '雪花数独',
    blurb: '雪花形异形宫，难度高于九宫异形',
    difficulties: [SudokuDifficulty.hard, SudokuDifficulty.expert],
    hidden: true,
  ),
  SudokuModeSpec(
    variant: SudokuVariant.overlap,
    group: SudokuGroup.jigsaw,
    key: 'overlap-2',
    title: '双重叠',
    blurb: '两个九宫格重叠，共用区同数',
    overlapCount: 2,
    difficulties: [SudokuDifficulty.hard],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.overlap,
    group: SudokuGroup.jigsaw,
    key: 'overlap-3',
    title: '三重叠',
    blurb: '三个九宫格重叠',
    overlapCount: 3,
    difficulties: [SudokuDifficulty.hard],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.overlap,
    group: SudokuGroup.jigsaw,
    key: 'overlap-4',
    title: '四重叠',
    blurb: '风车样式四重叠',
    overlapCount: 4,
    difficulties: [SudokuDifficulty.expert],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.overlap,
    group: SudokuGroup.jigsaw,
    key: 'overlap-5',
    title: '五重叠',
    blurb: '五个九宫格重叠',
    overlapCount: 5,
    difficulties: [SudokuDifficulty.expert],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.overlap,
    group: SudokuGroup.jigsaw,
    key: 'overlap-8',
    title: '八重叠',
    blurb: '八个九宫格重叠',
    overlapCount: 8,
    difficulties: [SudokuDifficulty.expert],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.overlap,
    group: SudokuGroup.jigsaw,
    key: 'overlap-13',
    title: '十三重叠',
    blurb: '十三个九宫格重叠',
    overlapCount: 13,
    difficulties: [SudokuDifficulty.expert],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.evenOdd,
    group: SudokuGroup.advanced,
    key: 'evenodd',
    title: '奇偶数独',
    blurb: '部分格有圆/方标记，圆奇方偶',
    difficulties: [SudokuDifficulty.hard, SudokuDifficulty.expert],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.diagonal,
    group: SudokuGroup.advanced,
    key: 'diag',
    title: '对角线数独',
    blurb: '两条主对角线也必须是 1–9',
    difficulties: [SudokuDifficulty.hard, SudokuDifficulty.expert],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.inequality,
    group: SudokuGroup.advanced,
    key: 'ineq',
    title: '不等式数独',
    blurb: '相邻格之间给出大小关系',
    difficulties: [SudokuDifficulty.hard, SudokuDifficulty.expert],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.killer,
    group: SudokuGroup.advanced,
    key: 'killer',
    title: '杀手数独',
    blurb: '虚线笼内的数相加等于左上角',
    difficulties: [SudokuDifficulty.hard, SudokuDifficulty.expert],
  ),
  SudokuModeSpec(
    variant: SudokuVariant.cube3d,
    group: SudokuGroup.advanced,
    key: 'cube3d',
    title: '3D 数独',
    blurb: '三面立方，共享边同数；可拖动旋转查看',
    difficulties: [SudokuDifficulty.hard, SudokuDifficulty.expert],
  ),
];

SudokuModeSpec sudokuModeByKey(String key) => kSudokuModes.firstWhere(
  (m) => m.key == key,
  orElse: () => kSudokuModes.first,
);

List<SudokuModeSpec> sudokuModesInGroup(SudokuGroup group) => kSudokuModes
    .where((m) => m.group == group && !m.hidden)
    .toList(growable: false);
