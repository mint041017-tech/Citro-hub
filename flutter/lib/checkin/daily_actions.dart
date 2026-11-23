/// 十类签到通用行动的映射（执行方案 6.2）。
///
/// 这里只描述「该做什么、主按钮叫什么、怎么自动验证」，不直接跳页面；
/// 页面跳转与验证器在 `checkin_store.dart` / `fortune_sheet.dart` 里。
library;

import 'checkin_models.dart';

class CheckinActionPlan {
  /// 通用行动类型，见 [CheckinActionType]。
  final String type;

  /// 主按钮文案。
  final String primaryLabel;

  /// 主按钮没有可跳转页面时（manual）为 null。
  final String? route;

  /// 点主按钮后直接打开回签弹层。
  final bool opensReflection;

  /// 点主按钮后打开笔记弹层。
  final bool opensNotes;

  /// 专注 / 听隅的自动完成阈值（分钟）。其他类型为 0。
  final int thresholdMinutes;

  /// 行动说明，给弹层里一行小字用。
  final String hint;

  const CheckinActionPlan({
    required this.type,
    required this.primaryLabel,
    this.route,
    this.opensReflection = false,
    this.opensNotes = false,
    this.thresholdMinutes = 0,
    required this.hint,
  });

  bool get hasPrimary => route != null || opensReflection || opensNotes;

  bool get isAuto => type != CheckinActionType.manual;

  /// 次按钮永远可用。
  String get manualLabel => '我自己完成了';
}

/// 按签类取行动方案。
CheckinActionPlan checkinPlanForKind(
  String? kind, {
  String? actionText,
  String? stepText,
}) {
  switch (kind) {
    case 'career':
      return const CheckinActionPlan(
        type: CheckinActionType.task,
        primaryLabel: '去计划',
        route: '/todo',
        hint: '选一条今天的任务推进；它完成时自动盖章',
      );
    case 'study':
      return const CheckinActionPlan(
        type: CheckinActionType.focus,
        primaryLabel: '专注十分钟',
        route: '/todo/focus',
        thresholdMinutes: 10,
        hint: '专注满十分钟自动盖章',
      );
    case 'action':
      return const CheckinActionPlan(
        type: CheckinActionType.focus,
        primaryLabel: '开始五分钟',
        route: '/todo/focus',
        thresholdMinutes: 5,
        hint: '先做五分钟，专注满五分钟自动盖章',
      );
    case 'rest':
      return const CheckinActionPlan(
        type: CheckinActionType.listen,
        primaryLabel: '去听隅',
        route: '/tingyu',
        thresholdMinutes: 10,
        hint: '前台有效播放满十分钟自动盖章',
      );
    case 'body':
      return const CheckinActionPlan(
        type: CheckinActionType.listen,
        primaryLabel: '去听隅',
        route: '/tingyu',
        thresholdMinutes: 5,
        hint: '听一会儿声音，满五分钟自动盖章',
      );
    case 'money':
      return const CheckinActionPlan(
        type: CheckinActionType.ledger,
        primaryLabel: '记一笔',
        route: '/ledger',
        hint: '新增一条账本记录后自动盖章',
      );
    case 'social':
      return const CheckinActionPlan(
        type: CheckinActionType.community,
        primaryLabel: '去回应',
        route: '/trash',
        hint: '发出一句回应后自动盖章',
      );
    case 'heart':
      return const CheckinActionPlan(
        type: CheckinActionType.note,
        primaryLabel: '写下来',
        opensReflection: true,
        hint: '写一句心情，保存回签即盖章',
      );
    case 'idea':
      return const CheckinActionPlan(
        type: CheckinActionType.note,
        primaryLabel: '写下来',
        opensNotes: true,
        hint: '记一条笔记，或保存一句回签，都会盖章',
      );
    default:
      return const CheckinActionPlan(
        type: CheckinActionType.manual,
        primaryLabel: '我自己完成了',
        hint: '这一签没有固定入口，做完就点一下',
      );
  }
}

/// 是否允许在行动开始前更新行动文案（AI 回来后可以改）。
bool checkinActionTextEditable(CheckinDayEntry? entry) {
  if (entry == null) return true;
  // 已完成 / 已回签就冻结，其他情况下转运可以换签换行动。
  return !entry.actionDone && !entry.hasReflection;
}
