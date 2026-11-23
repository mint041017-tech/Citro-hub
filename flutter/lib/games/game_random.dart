import 'dart:math';

/// 游戏随机源统一入口。
///
/// 正式运行时 [debugSeed] 为 null，行为与直接 `Random()` 等价；
/// 视觉 / golden 测试可在播种（赋值 [debugSeed]）后，让所有游戏的初始状态
/// 确定性复现，避免整页基线随随机种子漂移。
class GameRandom {
  /// 测试播种值；null = 不播种（生产行为，与 `Random()` 一致）。
  static int? debugSeed;

  /// 创建随机数生成器：显式传 [seed] 优先；否则取 [debugSeed]；都为空时与 `Random()` 等价。
  static Random create([int? seed]) => Random(seed ?? debugSeed);
}
