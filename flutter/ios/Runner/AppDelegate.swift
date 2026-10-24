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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    CitroTimerChannel.shared.register(messenger: messenger)
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
}
