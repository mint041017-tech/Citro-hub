import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CitroTimerWidgetBundle: WidgetBundle {
  var body: some Widget {
    CitroTimerLiveActivity()
  }
}

struct CitroTimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CitroTimerAttributes.self) { context in
      CitroTimerLockScreenView(context: context)
        .activityBackgroundTint(Color(red: 0.984, green: 0.969, blue: 0.925))
        .activitySystemActionForegroundColor(Color(red: 0.604, green: 0.337, blue: 0.024))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 7) {
            Image(systemName: "timer")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(Color(red: 0.604, green: 0.337, blue: 0.024))
              .frame(width: 30, height: 30)
              .background(Color(red: 0.996, green: 0.808, blue: 0.475))
              .clipShape(Circle())
            Text("Citro 计时")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(Color(red: 0.18, green: 0.17, blue: 0.13))
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          CitroTimerCountdown(context: context)
            .font(.system(size: 25, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color(red: 0.604, green: 0.337, blue: 0.024))
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(red: 0.34, green: 0.33, blue: 0.27))
            .lineLimit(1)
        }
      } compactLeading: {
        Image(systemName: "timer")
          .foregroundStyle(Color(red: 0.604, green: 0.337, blue: 0.024))
      } compactTrailing: {
        CitroTimerCountdown(context: context)
          .font(.system(size: 12, weight: .bold, design: .rounded))
          .monospacedDigit()
          .frame(width: 48)
          .foregroundStyle(Color(red: 0.604, green: 0.337, blue: 0.024))
      } minimal: {
        Image(systemName: "timer")
          .foregroundStyle(Color(red: 0.604, green: 0.337, blue: 0.024))
      }
      .keylineTint(Color(red: 0.949, green: 0.643, blue: 0.235))
    }
  }
}

private struct CitroTimerLockScreenView: View {
  let context: ActivityViewContext<CitroTimerAttributes>

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Circle()
            .fill(Color(red: 0.949, green: 0.643, blue: 0.235))
            .frame(width: 7, height: 7)
          Text("CITRO · 计时中")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(red: 0.34, green: 0.33, blue: 0.27))
        }
        Text(context.state.label)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Color(red: 0.18, green: 0.17, blue: 0.13))
          .lineLimit(1)
        Text(
          "预计 \(context.state.endAt, style: .time) 结束"
        )
        .font(.system(size: 10))
        .foregroundStyle(Color(red: 0.42, green: 0.41, blue: 0.35))
      }
      Spacer(minLength: 8)
      CitroTimerCountdown(context: context)
        .font(.system(size: 34, weight: .heavy, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(Color(red: 0.604, green: 0.337, blue: 0.024))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

private struct CitroTimerCountdown: View {
  let context: ActivityViewContext<CitroTimerAttributes>

  var body: some View {
    Text(
      timerInterval: context.state.startedAt...context.state.endAt,
      countsDown: true
    )
  }
}
