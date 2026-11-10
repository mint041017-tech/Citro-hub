import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if #available(iOS 10.0, *) {
      // flutter_local_notifications 需要 AppDelegate 接管前台展示；
      // 未设置时，App 在前台收到本地通知不会显示横幅。
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    UIApplication.shared.registerForRemoteNotifications()
    return launched
  }

  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    if UIDevice.current.userInterfaceIdiom == .pad { return .all }
    // Duo 外屏保持竖屏；内屏（约 669×951 / 951×669）允许横竖屏。
    // 普通 iPhone 也走 portrait，和原产品行为一致。
    guard let size = window?.bounds.size else { return .allButUpsideDown }
    let short = min(size.width, size.height)
    let long = max(size.width, size.height)
    let duoInner = short >= 600 && short <= 700 && long / short < 1.47
    return duoInner ? .allButUpsideDown : .portrait
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if LedgerIntakeBridge.shared.handle(url: url) { return true }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    CitroTimerChannel.shared.register(messenger: messenger)
    LedgerIntakeBridge.shared.register(messenger: messenger)
    PushTokenBridge.shared.register(messenger: messenger)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CitroLedgerIntake") {
      registrar.addSceneDelegate(LedgerIntakeBridge.shared)
    }
    // Duo 内屏横握需要横屏；普通 iPhone 仍由 Dart 侧锁竖屏，
    // 因此这里只提供设备形态，不直接改全局方向。
    FlutterMethodChannel(
      name: "com.chimu.crew/device",
      binaryMessenger: messenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "idiom":
        result(UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone")
      case "isDuo":
        let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
          $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let model = simulated.isEmpty ? machine : simulated
        result(model == "iPhone19,4")
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    PushTokenBridge.shared.deviceToken = deviceToken
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    PushTokenBridge.shared.deviceToken = nil
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // 前台由现有轮询发一条本地通知，APNs 只负责后台/锁屏提醒，避免双重横幅。
    if notification.request.trigger is UNPushNotificationTrigger {
      completionHandler([])
    } else {
      super.userNotificationCenter(
        center,
        willPresent: notification,
        withCompletionHandler: completionHandler
      )
    }
  }
}

final class PushTokenBridge {
  static let shared = PushTokenBridge()
  private var channel: FlutterMethodChannel?
  private var lastToken: String?

  var deviceToken: Data? {
    didSet {
      let value = deviceToken.map { data in
        data.map { String(format: "%02x", $0) }.joined()
      }
      lastToken = value
      guard let value, let channel else { return }
      channel.invokeMethod("token", arguments: ["token": value, "environment": "production"])
    }
  }

  func register(messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let channel = FlutterMethodChannel(name: "com.chimu.crew/push", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "getToken":
        result(lastToken.map { ["token": $0, "environment": "production"] })
      case "register":
        UIApplication.shared.registerForRemoteNotifications()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    if let lastToken {
      channel.invokeMethod("token", arguments: ["token": lastToken, "environment": "production"])
    }
  }
}

/// iOS 系统分享入口。
///
/// ShareExtension 把 JPG 写入 App Group，然后尝试打开 `citro://ledger/scan`。
/// 主 App 通过 `com.chimu.crew/ledger_intake` 读取并删除共享图片，交给 Dart
/// 进入与 Android 相同的识别草稿确认流程。
final class LedgerIntakeBridge: NSObject, FlutterSceneLifeCycleDelegate {
  static let shared = LedgerIntakeBridge()
  static let appGroup = "group.com.chimu.crew"

  private var channel: FlutterMethodChannel?
  private var dartAttached = false
  private var pendingPayload: [String: Any]?
  private var resolving = false

  func register(messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "com.chimu.crew/ledger_intake",
      binaryMessenger: messenger
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "attach":
        self.dartAttached = true
        if let payload = self.pendingPayload {
          self.pendingPayload = nil
          result(payload)
          return
        }
        self.deliverPending(result: result)
      case "consume":
        self.dartAttached = true
        self.deliverPending(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 返回 true 表示这个 URL 是记账分享入口，已由本类消费。
  @discardableResult
  func handle(url: URL) -> Bool {
    guard url.scheme?.lowercased() == "citro" else { return false }
    let host = url.host?.lowercased()
    let path = url.path.lowercased()
    guard host == "ledger" || path == "/ledger" || path == "/ledger/scan" else {
      return false
    }
    // URL 可能早于 Flutter 通道就绪；attach 时还会再检查一次共享目录。
    guard dartAttached, channel != nil else { return true }
    deliverPending()
    return true
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let url = connectionOptions?.urlContexts.first?.url else { return false }
    return handle(url: url)
  }

  func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) -> Bool {
    var handled = false
    for context in URLContexts {
      if handle(url: context.url) { handled = true }
    }
    return handled
  }

  private func deliverPending(result: FlutterResult? = nil) {
    guard !resolving else {
      result?(nil)
      return
    }
    resolving = true
    let payload = consumeSharedFile()
    resolving = false

    guard let payload = payload else {
      result?(nil)
      return
    }
    if let result = result {
      result(payload)
      return
    }
    if dartAttached, let channel = channel {
      channel.invokeMethod("ledgerImage", arguments: payload)
    } else {
      pendingPayload = payload
    }
  }

  /// ShareExtension 写入 `ledger-intake-<毫秒>.jpg`；读取最新一张并清理全部旧图。
  private func consumeSharedFile() -> [String: Any]? {
    let fm = FileManager.default
    guard
      let container = fm.containerURL(
        forSecurityApplicationGroupIdentifier: LedgerIntakeBridge.appGroup
      ),
      let files = try? fm.contentsOfDirectory(
        at: container,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else { return nil }

    let allowed = ["jpg", "jpeg", "png"]
    let candidates = files
      .filter {
        $0.lastPathComponent.lowercased().hasPrefix("ledger-intake") &&
          allowed.contains($0.pathExtension.lowercased())
      }
      .sorted {
        let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
          .contentModificationDate ?? .distantPast
        let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
          .contentModificationDate ?? .distantPast
        return left > right
      }

    guard let newest = candidates.first else { return nil }
    guard let data = try? Data(contentsOf: newest), !data.isEmpty else {
      for file in candidates { try? fm.removeItem(at: file) }
      return nil
    }
    for file in candidates { try? fm.removeItem(at: file) }
    return [
      "bytes": FlutterStandardTypedData(bytes: data),
      "origin": "iosShare",
    ]
  }
}
