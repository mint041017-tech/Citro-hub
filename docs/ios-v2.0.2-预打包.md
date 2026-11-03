# Citro iOS 2.0.2 预打包清单

> 当前发布环境为 Windows，Xcode 工具链不可用，因此本次只完成「预打包」：
> 版本、工程配置、权限文档、依赖与构建脚本已核对就绪，IPA 产物需在 macOS 上执行本清单生成。

## 1. 版本与工程状态（已在 Windows 侧完成）

| 项目 | 值 | 位置 |
| --- | --- | --- |
| Flutter 版本号 | `2.0.2+2002` | `flutter/pubspec.yaml` |
| Bundle ID | `com.chimu.crew` | `flutter/ios/Runner.xcodeproj/project.pbxproj` |
| 短版本号 | `$(FLUTTER_BUILD_NAME)` → 2.0.2 | `flutter/ios/Runner/Info.plist:23` |
| Build 号 | `$(FLUTTER_BUILD_NUMBER)` → 2002 | `flutter/ios/Runner/Info.plist:27` |
| 最低系统 | iOS 15.0 | `flutter/ios/Podfile` |
| 计时 Live Activity | `CitroTimerWidget` | `flutter/ios/CitroTimerWidget` |

已同步 `ios/Flutter/Generated.xcconfig` 与 `ios/Flutter/flutter_export_environment.sh` 的
`FLUTTER_BUILD_NAME=2.0.2`、`FLUTTER_BUILD_NUMBER=2002`，保证在 Mac 上打开工程时先显示正确版本。

## 2. 权限文案（Info.plist 已配置）

- 相机：拍摄头像、帖子配图与食谱照片
- 麦克风：录制社区语音消息和语音输入
- 语音识别：把说的话转成文字填入与 CiCi 的对话
- 相册读取 / 写入：选择与保存头像、配图、食谱照片
- 定位（使用期间）：天气与本地化信息

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

# 3. 一步构建 IPA（脚本会自动读取 pubspec 的 2.0.2）
bash ios/build_ipa.sh
```

脚本等价于：

```bash
flutter build ipa --release \
  --export-method app-store \
  --dart-define=APP_VERSION=2.0.2
```

产物：`flutter/build/ios/ipa/*.ipa`。

## 4. 产物归档与命名

```bash
cp build/ios/ipa/*.ipa "../IPA/Citro-v2.0.2-unsigned.ipa"
shasum -a 256 "../IPA/Citro-v2.0.2-unsigned.ipa"
```

- 若使用开发签名导出，文件名后缀改为 `-dev.ipa`
- 未配置证书时可先 `flutter build ios --release --no-codesign` 做编译验证（不产出可安装 IPA）

## 5. 上传 OBS（公开读写桶）

```bash
curl -X PUT -T "IPA/Citro-v2.0.2-unsigned.ipa" \
  -H "Content-Type: application/octet-stream" \
  "https://obs.chimu-claw.xyz/IPA/Citro-v2.0.2-unsigned.ipa"
```

上传后校验：

```bash
curl -sI "https://obs.chimu-claw.xyz/IPA/Citro-v2.0.2-unsigned.ipa"
```

## 6. 发版前验证

1. `CFBundleShortVersionString` 为 `2.0.2`，`CFBundleVersion` 为 `2002`
   （`unzip -p ...ipa Payload/Runner.app/Info.plist` 或 Xcode Organizer 查看）
2. 真机走查：听隅手机端顶栏时钟与呼吸按钮贴齐最右侧；首页小游戏卡和游戏页游戏卡打开/关闭均为纸页软转场，退出回到原卡片位置；减弱动态效果开关下直接切换。
3. 冷启动与后台恢复：专注计时胶囊、Live Activity 正常。
4. App Store Connect 上传后等待处理完成，再补 TestFlight 测试。

## 7. 本机限制

- Windows 无法执行 `flutter build ipa` 或 `xcodebuild archive`，`ios/build_ipa.sh` 会在非 Darwin 环境直接退出。
- 因此 `IPA/` 目录本次不新增二进制；Android / Windows / Web 三端已完成构建与 OBS 同步。