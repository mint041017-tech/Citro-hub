import ActivityKit
import AudioToolbox
import Flutter
import Foundation
import UIKit

final class CitroTimerChannel {
  static let shared = CitroTimerChannel()

  private var channel: FlutterMethodChannel?

  private init() {}

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.chimu.crew/timer",
      binaryMessenger: messenger
    )
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "show":
        guard #available(iOS 16.1, *) else {
          result(false)
          return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        let label = args["label"] as? String ?? "计时"
        let endMillis = (args["end"] as? NSNumber)?.doubleValue ?? 0
        let endAt = Date(timeIntervalSince1970: endMillis / 1000)
        Task { @MainActor in
          let started = await CitroTimerLiveActivityManager.shared.show(
            label: label,
            endAt: endAt
          )
          result(started)
        }
      case "cancel", "cancelAll":
        guard #available(iOS 16.1, *) else {
          result(false)
          return
        }
        Task { @MainActor in
          await CitroTimerLiveActivityManager.shared.cancel()
          result(true)
        }
      case "vibrate":
        let args = call.arguments as? [String: Any] ?? [:]
        let kind = args["kind"] as? String ?? "breath"
        DispatchQueue.main.async {
          if kind == "done" {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
          } else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
          }
          result(true)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

@available(iOS 16.1, *)
@MainActor
private final class CitroTimerLiveActivityManager {
  static let shared = CitroTimerLiveActivityManager()

  private init() {}

  func show(label: String, endAt: Date) async -> Bool {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return false
    }
    let startedAt = Date()
    let state = CitroTimerAttributes.ContentState(
      label: label,
      startedAt: startedAt,
      endAt: endAt
    )

    if let existing = Activity<CitroTimerAttributes>.activities.first {
      await update(existing, state: state, endAt: endAt)
      return true
    }

    let attributes = CitroTimerAttributes(createdAt: startedAt)
    do {
      if #available(iOS 16.2, *) {
        _ = try Activity.request(
          attributes: attributes,
          content: ActivityContent(state: state, staleDate: endAt),
          pushType: nil
        )
      } else {
        _ = try Activity.request(
          attributes: attributes,
          contentState: state,
          pushType: nil
        )
      }
      return true
    } catch {
      return false
    }
  }

  private func update(
    _ activity: Activity<CitroTimerAttributes>,
    state: CitroTimerAttributes.ContentState,
    endAt: Date
  ) async {
    if #available(iOS 16.2, *) {
      await activity.update(
        ActivityContent(state: state, staleDate: endAt)
      )
    } else {
      await activity.update(using: state)
    }
  }

  func cancel() async {
    for activity in Activity<CitroTimerAttributes>.activities {
      if #available(iOS 16.2, *) {
        await activity.end(nil, dismissalPolicy: .immediate)
      } else {
        await activity.end(using: nil, dismissalPolicy: .immediate)
      }
    }
  }
}
