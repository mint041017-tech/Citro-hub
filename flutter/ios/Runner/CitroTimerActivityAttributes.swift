import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct CitroTimerAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var label: String
    var startedAt: Date
    var endAt: Date
  }

  var createdAt: Date
}
