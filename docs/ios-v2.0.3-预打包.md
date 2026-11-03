# Citro iOS 2.0.3 预打包清单

> 当前发布环境为 Windows，Xcode 工具链不可用，因此本次只完成「预打包」：
> 版本、工程配置、权限文档、依赖与构建脚本已核对就绪，IPA 产物需在 macOS 上执行本清单生成。

## 1. 版本与工程状态（已在 Windows 侧完成）

| 项目 | 值 | 位置 |
| --- | --- | --- |
| Flutter 版本号 | `2.0.3+2003` | `flutter/pubspec.yaml` |
| Bundle ID | `com.chimu.crew` | `flutter/ios/Runner.xcodeproj/project.pbxproj` |
| 短版本号 | `$(FLUTTER_BUILD_NAME)` → 2.0.3 | `flutter/ios/Runner/Info.plist` |
| Build 号 | `$(FLUTTER_BUILD_NUMBER)` → 2003 | `flutter/ios/Runner/Info.plist` |
| 最低系统 | iOS 15.0 | `flutter/ios/Podfile` |
| 高刷开关 | `CADisableMinimumFrameDurationOnPhone = true` | `flutter/ios/Runner/Info.plist` |
| 计时 Live Activity | `CitroTimerWidget` | `flutter/ios/CitroTimerWidget` |

已同步 `ios/Flutter/Generated.xcconfig` 与 `ios/Flutter/flutter_export_environment.sh` 的
`FLUTTER_BUILD_NAME=2.0.3`、`FLUTTER_BUILD_NUMBER=2003`，保证在 Mac 上打开工程时先显示正确版本。

## 2. 本次版本包含的端侧改动

- Web/移动/桌面通用的性能改动：图片解码尺寸收敛、食材库/成语链/诗句链懒构建、
  图片磁盘缓存 LRU、Android 低内存回调。
- 数独计分明细、对局续玩与最佳用时。
- iOS 侧沿用 2.0.2 的权限文案与 120Hz ProMotion 开关，无需新增权限。

## 3. Mac 构建步骤

```bash
# 1. 环境
xcodebuild -version          # 需要 Xcode 15+（建议 16.x）
pod --version                # 需要 CocoaPods 1.13+
flutter --version

# 2. 取代码并安装依赖
cd flutter
flutter pub get
(cd ios && pod install --repo-update)

# 3. 一步构建 IPA（脚本会自动读取 pubspec 的 2.0.3）
bash ios/build_ipa.sh
```

脚本等价于：

```bash
flutter build ipa --release \
  --export-method app-store \
  --dart-define=APP_VERSION=2.0.3
```

产物：`flutter/build/ios/ipa/*.ipa`。

## 4. 产物归档与命名

```bash
cp build/ios/ipa/*.ipa "../IPA/Citro-v2.0.3-unsigned.ipa"
shasum -a 256 "../IPA/Citro-v2.0.3-unsigned.ipa"
```

- 若使用开发签名导出，文件名后缀改为 `-dev.ipa`
- 未配置证书时可先 `flutter build ios --release --no-codesign` 做编译验证（不产出可安装 IPA）

## 5. 上传 OBS（公开读写桶）

```bash
curl -X PUT -T "IPA/Citro-v2.0.3-unsigned.ipa" \
  -H "Content-Type: application/octet-stream" \
  "https://obs.chimu-claw.xyz/IPA/Citro-v2.0.3-unsigned.ipa"
```

上传后校验：

```bash
curl -sI "https://obs.chimu-claw.xyz/IPA/Citro-v2.0.3-unsigned.ipa"
```

## 6. 发版前验证

1. `CFBundleShortVersionString` 为 `2.0.3`，`CFBundleVersion` 为 `2003`
   （`unzip -p ...ipa Payload/Runner.app/Info.plist` 或 Xcode Organizer 查看）。
2. 真机走查：
   - 首屏、听隅、食谱、社区、小游戏滚动无掉帧；
   - 数独进入对局后计分明细、暂停退出再进入可续玩，最佳用时写入本地；
   - 减弱动态效果开关下页面切换直接呈现终态。
3. 冷启动与后台恢复：专注计时胶囊、Live Activity 正常。
4. App Store Connect 上传后等待处理完成，再补 TestFlight 测试。

## 7. 本机限制

- Windows 无法执行 `flutter build ipa` 或 `xcodebuild archive`，`ios/build_ipa.sh` 会在非 Darwin 环境直接退出。
- 因此 `IPA/` 目录本次不新增二进制；Android / Windows / Web 三端已完成构建与 OBS 同步。