# Citro iOS / IPA 构建清单（必须在 Mac 完成的部分）

> 代码、工程文件、权限文案、图标、启动屏、隐私清单、通知/定位 Dart 适配已经完成。
> 下面这些步骤依赖 macOS、Xcode、Apple 签名与真机，Windows 无法代替。
>
> 截至 2026-10-28：版本已升到 **1.9.3+1903**（pubspec 为唯一版本源，Runner/TimerWidget 均用
> `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER`）；1.9.2 的共享 Flutter 层、资源与权限文案已完成，
> `flutter analyze` 改动文件无 error/warning，Android release / Windows / Web 构建通过。
> **iOS 的 Xcode 编译、签名和真机运行仍未在 Mac 上验证**，第一次 Mac 构建可能还需要处理 Xcode/CocoaPods 版本差异。

## 0. 前置

- macOS 14+（建议 macOS 15）
- Xcode 16+（同意 license：`sudo xcodebuild -license accept`）
- CocoaPods（`brew install cocoapods` 或 `sudo gem install cocoapods`）
- Flutter SDK（与项目一致：3.47.7）
- Apple Developer Program（App Store / TestFlight 需要付费账号）
- 一台 iPhone（iOS 15+），用于权限、通知、相机/麦克风、WebView、120Hz 真机验证

```bash
cd <项目>/flutter
flutter doctor -v
flutter precache --ios
flutter pub get
```

## 1. Xcode 签名（只需做一次）

1. 打开 `ios/Runner.xcworkspace`（不是 `.xcodeproj`）。
2. 选择 Runner target → Signing & Capabilities：
   - Team：选择你的 Apple Developer Team；
   - Bundle Identifier：`com.chimu.crew`（与 Apple Developer App ID 一致；如被占用可改成你自己的反向域名，同时修改 `project.pbxproj` 的 3 处 Runner 配置和 RunnerTests）；
   - 勾选“Automatically manage signing”。
3. RunnerTests target 也选择同一个 Team（单元测试用）。
4. 首次构建前如果需要，执行：

```bash
cd ios
pod install --repo-update
cd ..
```

> 工程默认**通用设备族（iPhone + iPad）**：iPhone 竖屏；iPad 支持横竖屏与分屏；
> 首页 / 游戏 / 社区 / 我的 / 游戏页已加宽屏最大宽度与居中约束，iPad 上不会被拉成整屏巨卡。
> 如果在 iPad 模拟器发现 Cook / Res / Play / Sens 等二级页仍过宽，可按同样方式补 `maxWidth` 约束，
> 但不要改变功能与手机版视觉。

## 2. 构建 IPA

推荐：

```bash
cd flutter
bash ios/build_ipa.sh
```

脚本会读取 `pubspec.yaml` 的版本并通过 `APP_VERSION` 传给 Flutter，然后执行
`flutter build ipa --release --export-method app-store`。客户端 AI 请求经自有服务
`/trashapi/api/ai` 转发；provider `GLM_API_KEY` 只配置在 Node 服务端环境/配置中，IPA 构建不需要该密钥。产物在：

```text
build/ios/ipa/
```

如果不使用脚本：

```bash
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter build ipa --release --export-method app-store \
  --dart-define=APP_VERSION=1.9.3
```

手动构建时将 `APP_VERSION` 与 `pubspec.yaml` 的版本号保持一致。

第一次构建必须打开 Xcode 设置 Team；否则会报 `No profiles for 'com.chimu.crew' were found`。

## 3. 真机验收（不可跳过）

在 iPhone 上安装并逐项确认：

- 支持 iPhone 与 iPad；iPhone 只允许竖屏，iPad 允许横竖屏和分屏；
- 首页 / 游戏 / 社区 / 我的 / 游戏页的最大内容宽度：首页 760、游戏 840、社区 760、我的 640、游戏页 760、底部导航 520；
- 检查 iPad 模拟器（13 英寸）竖屏、横屏、1/2 与 1/3 分屏，以及 iPhone 小屏；
- 所有弹层/底部面板在 iPad 上居中且不超过 760 宽，键盘弹起不遮挡输入框；
- 旋转屏幕后内容不溢出、不出现横向滚动；
- 每个 iPad 方向都留出安全区，底部导航不被 Home Indicator 遮挡；
- App Store Connect 需要单独上传 iPad 13 英寸截图；
- 启动屏在 iPad 横屏下使用 aspectFill，不能出现白边或拉伸变形；- 定位权限：允许后天气城市正确；拒绝后 App 仍可使用默认城市；
- 通知权限：在「我的 → 通知提醒」打开后能收到测试通知；
- 语音：发帖录音、语音消息播放、AI 页录音是否有声音；
- 相机/相册：头像、帖子配图、食谱图片；
- 分享：截图分享是否正常（iPhone-only 不存在 iPad popover 问题）；
- 极限刹车内嵌 WebView：WebGL 场景是否能加载、是否流畅；
- ProMotion：游戏页应接近 120Hz（Info.plist 已设置 `CADisableMinimumFrameDurationOnPhone`）；
- 深色模式、键盘弹起后底部导航隐藏、返回手势；
- 账号注销与举报：**依赖线上 `trash/trash.js` 已更新并部署**，否则会返回 404；
- App 内隐私政策/用户协议/黑名单入口。

## 4. App Store Connect

1. 创建 App（Bundle ID `com.chimu.crew`，名称 Citro，主语言中文）。
2. 填写：
   - 隐私政策 URL：部署后的 `/privacy.html`；
   - 用户协议 URL：部署后的 `/terms.html`；
   - 账号删除 URL：部署后的 `/account-deletion.html`；
   - 支持 URL 与联系邮箱；
   - App 隐私标签（手机号、昵称、照片/视频、音频、用户内容、用户 ID、精确位置、本地偏好；用途为 App 功能；不用于追踪）；
   - 年龄分级（UGC 社区一般 12+ / 17+，按问卷实际选择）；
   - 出口合规：已设置 `ITSAppUsesNonExemptEncryption=false`（仅标准 HTTPS）。
3. 审核备注：
   - **必须提供可用的测试账号**（当前注册需要邀请码，审核员无法自助注册）；
   - 说明 AI 内容仅供参考、社区举报/拉黑位置、账号注销路径；
   - 保证审核期间后端和服务器持续在线。
4. 上传构建：Xcode Organizer → Distribute App → App Store Connect，或使用 Transporter 上传 `build/ios/ipa/*.ipa`。
5. TestFlight 内部测试通过后再提交审核。

## 5. 上线前仍未完成的外部事项

- 部署 `trash/trash.js`（账号注销/举报接口；1.9.2 食谱收藏保留原作者依赖新版 `cookPubMine` 的 `owner`/`ownerAv`/`fromOwner` 字段）；
- 恢复真实 `trash/data`（当前线上是 QA 测试数据，详见 `docs/citro-android-v1.7.10-release.md` 与账号恢复记录）；
- 部署 `privacy.html`、`terms.html`、`account-deletion.html`；
- 中国大陆区若上架：准备 ICP 备案、游戏版号/软著（如被按游戏类审核）、生成式 AI 相关备案/安全评估；
- App Store 截图、预览、宣传文案与客服渠道；
- 1.9.2 起 iOS / Android 构建不再注入 GLM Key，AI 统一走服务端代理（密钥不入库）。

## 6. 版本号规则

- `pubspec.yaml` 的 `version: 1.9.3+1903` 决定 iOS `CFBundleShortVersionString` / `CFBundleVersion`。
- 每次上传 App Store Connect 必须递增 build number（+ 后面的数字）；仅改代码不升 build number 会被拒绝。
