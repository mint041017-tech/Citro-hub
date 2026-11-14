# iPhone / iPad 自动发布到 TestFlight

Workflow：`.github/workflows/ios-testflight.yml`。

## 日常发布

直接把本地代码 push 到 `main` 就会触发，无需先创建分支或 pull request：

```bash
git push origin main
```

版本仍取自 `flutter/pubspec.yaml`，例如 `2.1.0+2100`。流水线读取 TestFlight 中该版本最新 build 号并加一；没有该版本的历史 build 时，从 pubspec 的 build 号加一开始。三个 target 使用相同版本和 build 号。

也支持推送 `v<版本号>` tag。tag 必须与该提交的 pubspec 版本一致，且提交必须已包含在远端 main 中：

```bash
git tag v2.1.1
git push origin main --tags
```

main 和 tag 同时推送时，两次事件共用发布队列（最多等待 100 次发布）。自动触发会查询该提交的 GitHub `testflight` deployment 成功记录，已上传的提交跳过重复上传。

上传前先记录持久的 upload attempt。若任务在上传期间中断，结果可能已被 Apple 接收，自动触发会停止重复上传，并要求先核对 App Store Connect；确认需要重传后再手动触发。这样避免把跨 Apple / GitHub 的状态写入中断误当成未上传。

需要重试时，在 Actions → iOS and iPadOS TestFlight → Run workflow，选择 main。手动运行允许重新发布同一提交，并分配新的 build 号。

## 首次配置 Secrets

在仓库 Settings → Secrets and variables → Actions 添加以下六项；也可以配置到 `testflight` Environment：

| Secret | 内容 |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | 包含 Apple Distribution 证书及其私钥的 `.p12` 文件的 Base64 |
| `IOS_DISTRIBUTION_P12_PASSWORD` | 上述 `.p12` 的导出密码，必须非空 |
| `IOS_PROVISIONING_PROFILES_BASE64` | 三份 App Store Connect 分发 `.mobileprovision` 打成 ZIP 后的 Base64 |
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | App Store Connect API Issuer ID |
| `ASC_PRIVATE_KEY_BASE64` | 对应 App Store Connect API `.p8` 文件的 Base64 |

App Store Connect API Key 需具备访问此 App、查询 build 和上传 build 的权限（例如 App Manager）。它与后端 APNs Key 是两种不同用途的密钥；不要填入 APNs 私钥。

三份分发描述文件分别覆盖：

- `com.chimu.crew`：Production Push Notifications，以及 `group.com.chimu.crew`。
- `com.chimu.crew.TimerWidget`。
- `com.chimu.crew.ShareExtension`：`group.com.chimu.crew`。

描述文件必须属于 Team `3F78UC4868`，未过期，并包含 `.p12` 对应的分发证书。从已验证的 App Store 分发包提取的三份 `embedded.mobileprovision` 也可使用，但压缩前需改成不同文件名，防止覆盖。证书或描述文件到期后需替换相应 Secrets。

签名资料只写入临时 keychain / 临时目录，结束时清理；不会成为构建产物。不要把证书、私钥、导出密码提交到 Git。

上传文件类 Secrets 时请使用不换行的 Base64，例如 `base64 -i AppleDistribution.p12 | tr -d '\n' | gh secret set IOS_DISTRIBUTION_P12_BASE64`。密码和 API ID 使用各自原值，不做 Base64 编码。

## 构建与检查

使用官方 `xcode-27` ARM64 runner，固定 Xcode 27.1（27A9275）、Flutter 3.47.7、CocoaPods 1.16.2 和 Fastlane 2.241.2。Bundler 在 runner 上解析并缓存 Ruby 依赖；直接依赖版本由 Gemfile 固定。

上传前检查三个 target 的版本、App Store 签名、iPhone/iPad 支持、Production APNs entitlement、App Groups、隐私清单，并拒绝 IPA 中出现 `.p8` 或 `.p12` 文件。IPA 和脱敏上传回执保留 14 天。

成功表示 Apple 已接收上传。Apple 后续处理、测试组分配、外部审核和真机测试不属于此 workflow。

本地可运行的轻量检查：

```bash
python3 -m unittest discover -s flutter/tool -p 'test_ci_release_metadata.py'
ruby -c flutter/fastlane/Fastfile
```
