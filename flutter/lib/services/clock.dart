/// 统一时钟入口。
///
/// 正式运行时 [debugNow] 为 null，[now] 直接返回 `DateTime.now()`，与改动前
/// 的分支逻辑逐一等价；视觉 / golden 测试可在 setUpAll 注入固定时间、
/// tearDownAll 复位 null，让问候语分档、日期戳、按日轮换的文案 / 倒计时等
/// 内容确定性复现，避免基线跨小时 / 跨天漂移。思路同 `GameRandom.debugSeed`。
class CitroClock {
  /// 测试注入的固定时间；null = 生产行为，取真实当前时间。
  static DateTime? debugNow;

  /// 当前时间：注入值优先；都为空时与 `DateTime.now()` 等价。
  static DateTime now() => debugNow ?? DateTime.now();
}
