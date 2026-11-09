# 截图一键记账：系统入口说明

账单截图不会直接入账：无论 Android 还是 iOS，都会先进入「账单 → 记一笔」，
由 AI 生成可编辑草稿，用户确认后才写入账本。

## Android：系统分享

已注册 `ACTION_SEND` / `ACTION_SEND_MULTIPLE` + `image/*`，Citro 会出现在微信、
支付宝、相册等应用的系统分享面板里。

1. 在微信 / 支付宝账单页截屏；
2. 打开截图，点「分享」→ 选择 Citro；
3. Citro 自动打开「账单 → 记一笔」并开始识别；
4. 核对金额、分类、时间后确认入账。

实现位置：

- `flutter/android/app/src/main/AndroidManifest.xml`：分享 intent-filter；
- `MainActivity.kt`：读取分享 URI、缩到 1800px 内、JPEG 压缩后通过
  `com.chimu.crew/ledger_intake` 通道交给 Dart；
- `lib/ledger/ledger_intake.dart`：图片队列、跳转账单页、通知记一笔；
- `lib/ledger/ledger_add_tab.dart`：复用原有截图识别与草稿确认流程。

## iOS：系统分享

使用 Share Extension，与 Android 走同样的系统分享路径。

1. 在账单页截屏；
2. 打开截图分享面板，选择「Citro 记账」；
3. 扩展会把截图压缩写入 App Group，并尝试打开 Citro；
4. 如果系统不允许扩展直接拉起 App，按扩展提示打开 Citro，回到前台后会继续识别。

实现位置：

- `flutter/ios/ShareExtension/ShareViewController.swift`：接收图片、压缩、
  写入 App Group、打开 `citro://ledger/scan`；
- `flutter/ios/ShareExtension/Info.plist`：`com.apple.share-services` 扩展声明；
- `flutter/ios/ShareExtension/ShareExtension.entitlements` 和
  `Runner/Runner.entitlements`：`group.com.chimu.crew` App Group；
- `Runner.xcodeproj`：新增 `ShareExtension` target，并嵌入 Runner；
- `Runner/AppDelegate.swift` 的 `LedgerIntakeBridge`：读取并清理共享图片，
  `lib/ledger/ledger_intake.dart` 负责进入识别流程。

### iOS 构建注意事项

- 需要在 Apple Developer 后台为 App 和 ShareExtension 同时启用
  **App Groups**，组名 `group.com.chimu.crew`；
- Xcode 自动签名需要覆盖 `com.chimu.crew` 和
  `com.chimu.crew.ShareExtension`；
- iOS 原生改动必须在 macOS + Xcode 上重新构建 IPA；Windows 环境只能验证 Android。

## 失败与排查

- **Android 分享面板找不到 Citro**：确认安装的是包含本次改动的包；部分系统需要
  分享图片（而不是文字/链接）才会显示图片类目标。
- **iOS 分享面板找不到「Citro 记账」**：确认新 IPA 已安装，且
  `ShareExtension.appex` 已嵌入 App；必要时删除旧 App 后重装。
- **iOS 提示无法写入共享目录**：检查 App Group `group.com.chimu.crew` 是否在
  Apple Developer 后台为两个 Bundle ID 启用。
- **识别不到账单**：换更清晰、包含金额和商户的截图；识别结果始终可以在草稿层
  手动修改后再入账。