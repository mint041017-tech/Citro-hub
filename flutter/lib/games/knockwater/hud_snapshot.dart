import 'engine.dart';

/// UI 层使用的只读快照：只包含 HUD / 结算浮层可见的值。
///
/// 该类型不依赖 Flutter，可在纯 Dart 测试中构造与比较。
/// 逐帧的引擎时间、蓄力比例、波前、粒子等不进入快照，避免 HUD
/// 因为水面动画而每帧重建。
class GameHudSnapshot {
  final int levelIndex;
  final String levelName;
  final int charges;
  final int maxCharges;
  final int petalsInBay;
  final int petalCount;
  final bool canUndo;
  final bool charging;
  final int stars;
  final GameStatus status;
  final LoseReason loseReason;

  const GameHudSnapshot({
    required this.levelIndex,
    required this.levelName,
    required this.charges,
    required this.maxCharges,
    required this.petalsInBay,
    required this.petalCount,
    required this.canUndo,
    required this.charging,
    required this.stars,
    required this.status,
    required this.loseReason,
  });

  factory GameHudSnapshot.of(Engine engine) {
    return GameHudSnapshot(
      levelIndex: engine.levelIndex,
      levelName: engine.level.name,
      charges: engine.charges,
      maxCharges: engine.maxCharges,
      petalsInBay: engine.petalsInBay,
      petalCount: engine.petals.length,
      canUndo: engine.canUndo,
      charging: engine.charging,
      stars: engine.stars,
      status: engine.status,
      loseReason: engine.loseReason,
    );
  }

  bool get knockAvailable => charges >= 3;

  @override
  bool operator ==(Object other) {
    return other is GameHudSnapshot &&
        other.levelIndex == levelIndex &&
        other.levelName == levelName &&
        other.charges == charges &&
        other.maxCharges == maxCharges &&
        other.petalsInBay == petalsInBay &&
        other.petalCount == petalCount &&
        other.canUndo == canUndo &&
        other.charging == charging &&
        other.stars == stars &&
        other.status == status &&
        other.loseReason == loseReason;
  }

  @override
  int get hashCode => Object.hash(
    levelIndex,
    levelName,
    charges,
    maxCharges,
    petalsInBay,
    petalCount,
    canUndo,
    charging,
    stars,
    status,
    loseReason,
  );
}
