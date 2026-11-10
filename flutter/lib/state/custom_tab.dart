import '../widgets/paper.dart';

/// Tab 栏第 4 格「自定义」可切换的模块。
///
/// 默认待办；长按 Tab 可在 待办 / 听隅 / 记账 / 食谱 之间切换，选择会持久化。
enum CustomTabModule { todo, tingyu, ledger, cook }

extension CustomTabModuleX on CustomTabModule {
  String get label => switch (this) {
    CustomTabModule.todo => '待办',
    CustomTabModule.tingyu => '听隅',
    CustomTabModule.ledger => '记账',
    CustomTabModule.cook => '食谱',
  };

  /// AppIcons 里的 SVG 路径。
  String get icon => switch (this) {
    CustomTabModule.todo => AppIcons.list,
    CustomTabModule.tingyu => AppIcons.wave,
    CustomTabModule.ledger => AppIcons.wallet,
    CustomTabModule.cook => AppIcons.fork,
  };

  /// 该模块原有的独立路由，用于「进入详情」类跳转。
  String get route => switch (this) {
    CustomTabModule.todo => '/todo',
    CustomTabModule.tingyu => '/tingyu',
    CustomTabModule.ledger => '/ledger',
    CustomTabModule.cook => '/cook',
  };
}
