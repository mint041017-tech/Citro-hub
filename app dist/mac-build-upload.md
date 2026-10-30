# Mac 构建与上传

> Windows 不能产出可上架的 iOS IPA；本机 `IPA/` 里的 1.8.0/1.9.0/1.9.1 都是 unsigned，不能用于 TestFlight/App Store。

## 1. 前置

- macOS 14+（建议 15）
- Xcode 16+，已同意 license：`sudo xcodebuild -license accept`
- CocoaPods：`brew install cocoapods` 或 `sudo gem install cocoapods`
- Flutter 3.47.7
- 付费 Apple Developer Program，Account Holder/Admin 权限
- App Store Connect 已签 Free Apps 协议

```bash
cd <项目>/flutter
flutter doctor -v
flutter precache --ios
flutter pub get
```

## 2. Xcode 签名（首次一次）

1. 打开 `ios/Runner.xcworkspace`（不是 `.xcodeproj`）。
2. Runner target → Signing & Capabilities：
   - Team：选 Apple Developer Team；
   - Bundle Identifier：`com.chimu.crew`（与 App Store Connect App ID 一致）；
   - 勾选 Automatically manage signing。
3. CitroTimerWidget target 选同一 Team；Bundle ID `com.chimu.crew.TimerWidget`。
4. RunnerTests target 选同一 Team。
5. 首次构建前如需要：

```bash
cd ios
pod install --repo-update
cd ..
```

## 3. 出包

```bash
cd flutter
bash ios/build_ipa.sh
```

脚本会读取 `pubspec.yaml` 的版本，执行 `pod install` 和：

```text
flutter build ipa --release --export-method app-store --dart-define=APP_VERSION=1.9.9
```

产物：`build/ios/ipa/`。

手动等价命令：

```bash
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter build ipa --release --export-method app-store \
  --dart-define=APP_VERSION=1.9.9
```

## 4. 上传

- **Xcode Organizer**：Window → Organizer → Archives → Distribute App → App Store Connect → Upload。
- **Transporter**：把 `build/ios/ipa/*.ipa` 拖进 Transporter，登录后交付。
- 上传后等待处理（通常 10–60 分钟）；出口合规已由 Info.plist 的 `ITSAppUsesNonExemptEncryption=false` 自动回答。

## 5. TestFlight（建议先做）

1. App Store Connect → TestFlight → Internal Testing，加自己/团队成员（最多 100，不需审核）。
2. 安装 TestFlight，逐项验证：登录、社区、AI、相机/麦克风/相册、定位、通知、iPad 布局、深色模式、返回手势。
3. 需要外部公开链接时，再建 External Testing 组，填 Test Information，提交 Beta App Review；通过后开 Public Link（最多 10,000 人，build 90 天过期）。

## 6. 提交 App Store

### 6.1 如还没有 App 记录

1. App Store Connect → Apps → `+` → New App。
2. 平台选 iOS；名称填 `metadata.md` 中的名称；主语言简体中文；Bundle ID 选 `com.chimu.crew`；SKU 填 `citro-ios-1`。
3. 填 App Information：主/副分类、内容版权、年龄分级。
4. Pricing and Availability：免费；选择销售范围（中国区先看 `china-compliance.md`）。
5. App Privacy：按 `app-privacy.md` 填写。
6. 创建后进入 App Store 版本页；上传的 build 会出现在 TestFlight/构建列表。

### 6.2 创建版本并提交

1. App Store Connect → App Store → 创建 1.9.9 版本。
2. 选择已处理的 build 1909（TestFlight 用过的同一个 build 可以直接选，不需要重新打包）。
3. 填 `metadata.md`、`app-privacy.md`、`age-rating.md` 的内容。
4. 上传截图（`screenshots.md`）。
5. 填 App Review Information（`review-notes.md` + `demo-account.md`）。
6. 提交审核；建议手动发布，不选自动发布。
7. 通过后可开启分阶段发布（7 天）。

## 7. 被拒后重新上传

- 修代码/后端/文案后，递增 build number：`1.9.9+1910`、`1.9.9+1911`……
- `pubspec.yaml` 是唯一版本源；Runner/TimerWidget 会读 `FLUTTER_BUILD_NAME`/`FLUTTER_BUILD_NUMBER`。
- 重新 `flutter pub get` + `bash ios/build_ipa.sh` + 上传。
- 营销版本号 1.9.9 在首次上架前不用改；App Store 已发布后再更新才升 1.9.10/2.0.0。
- 不要用同一个 build number 重复上传，App Store Connect 会拒绝。

## 8. 常见问题

| 问题 | 处理 |
| --- | --- |
| `No profiles for 'com.chimu.crew'` | Xcode 选 Team，开自动签名；确认 App ID 已注册 |
| CocoaPods 报错 | `pod repo update`、`pod install --repo-update`；确认 Xcode 版本 |
| 上传后一直“处理中” | 等待；检查邮箱是否有 Apple 的合规/版权问题 |
| 构建缺少合规回答 | Info.plist 已设置 `ITSAppUsesNonExemptEncryption=false`；确认打包用的是当前 Info.plist |
| iPad 截图缺失 | App 支持 iPad，App Store Connect 会要求 iPad 13" 截图 |
| TestFlight 外部审核慢 | Beta App Review 通常 1–2 个工作日；内部测试不需要审核 |
