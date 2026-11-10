import 'package:flutter/foundation.dart';

/// 首页负一屏的展开信号。
///
/// 「资源库」现在只有一个落点：首页下拉负一屏。其它页面（我的、游戏页）
/// 想打开资源库时，不再 push 独立路由，而是发这个信号——
/// [RootShellState] 收到后切回首页 Tab，HomePage 收到后把负一屏展开。
final ValueNotifier<int> negativeScreenSignal = ValueNotifier<int>(0);

/// 从任意页面打开首页负一屏。
void openNegativeScreen() => negativeScreenSignal.value++;
