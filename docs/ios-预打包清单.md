# Citro iOS 预打包清单（合并版）

> 从 2.0.15 起，原先按版本拆分的 `docs/ios-vX-预打包.md` 全部合并到本文件。
> 后续发版只维护这一份：更新第 1 节的版本号，在第 2 / 5 节补充当次改动，
> 并在第 7 节历史表追加一行即可。
>
> 当前版本：`2.0.15+2015` · 更新日期：2026-11-05

## 1. 当前版本与工程状态

> 当前发布环境为 Windows，Xcode 工具链不可用，因此只完成「预打包」：
> 版本、工程配置、权限文档与构建脚本已核对就绪，IPA 需在 macOS 上生成。

| 项目 | 值 | 位置 |
| --- | --- | --- |
| Flutter 版本号 | `2.0.15+2015` | `flutter/pubspec.yaml` |
| Bundle ID | `com.chimu.crew` | `flutter/ios/Runner.xcodeproj/project.pbxproj` |
| 短版本号 | `$(FLUTTER_BUILD_NAME)` → 2.0.15 | `flutter/ios/Runner/Info.plist` |
| Build 号 | `$(FLUTTER_BUILD_NUMBER)` → 2015 | `flutter/ios/Runner/Info.plist` |
| 最低系统 | iOS 15.0 | `flutter/ios/Podfile` |
| 高刷开关 | `CADisableMinimumFrameDurationOnPhone = true` | `flutter/ios/Runner/Info.plist` |
| 出口合规 | `ITSAppUsesNonExemptEncryption = false` | `flutter/ios/Runner/Info.plist` |
| 计时 Live Activity | `CitroTimerWidget` | `flutter/ios/CitroTimerWidget` |

已同步 `ios/Flutter/Generated.xcconfig` 与 `ios/Flutter/flutter_export_environment.sh` 的
`FLUTTER_BUILD_NAME=2.0.15`、`FLUTTER_BUILD_NUMBER=2015`。

## 2. 当前功能面与端侧能力

### 2.1 权限文案

| 权限 | 用途 |
| --- | --- |
| 相机 | 拍摄头像、帖子配图、食谱照片，以及扫描登录二维码 |
| 麦克风 | 录制社区语音消息和语音输入 |
| 语音识别 | 把说的话转成文字填入与 CiCi 的对话 |
| 相册读取 / 写入 | 选择与保存头像、配图、食谱照片 |
| 定位（使用期间） | 天气与本地化信息 |

### 2.2 账号与登录

- 登录 / 注册支持手机号或邮箱，注册无需邀请码。
- 手机号 / 邮箱切换文字严格居中。
- **扫码登录（iPad）**：登录弹窗显示 5 分钟有效的一次性二维码，手机 App 扫码确认后
  iPad 立即登录；iPad 判断使用 `CitroOrientation.padSize`（iOS 且最短边 ≥ 600pt）。
- **手机端扫一扫**：「我的」快捷工具可扫描 `citro://qr?id=...`，调用
  `POST /api/auth/qr/confirm` 确认电脑端登录。
- 依赖：`qr_flutter 4.1.0`、`mobile_scanner 5.2.3`（iOS 12+，项目 iOS 15.0 兼容）。

### 2.3 我的页与设置

- 我的页滚动使用 `BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())`，与首页一致。
- 快捷工具区：我的笔记、黑名单、扫一扫；不再显示「编辑资料」卡片，
  资料编辑入口保留在顶部头像卡片。
- 「主题」下拉：触发胶囊宽 118（Web）/ 110（移动端），下拉菜单 152/144；
  支持浅色、深色、跟随系统。
- 「后台运行设置」行与其它设置项左对齐，右侧 trailing 右对齐。
- 侧栏底部头像与 Duo 右侧栏头像使用 `AppImage`：磁盘缓存优先，
  加载中显示昵称首字，失败回落首字母。

### 2.4 性能与高刷

- 全局 120Hz：`main()` 启动即 `RefreshRate.acquire()` 常驻；iOS 保持 ProMotion
  （`CADisableMinimumFrameDurationOnPhone=true`），无需新增权限。
- 页面实例缓存：`RootShell` 只创建一次页面 Widget，切 Tab 不重挂 Element。
- 空闲预热：启动后错开预挂载游戏 / 我的 / 社区。
- 切页动画：280ms（移动端）/ 220ms（桌面端），
  `Opacity .82→1` + `scale .992→1` + 8/6px 位移（与 2.0.12 恢复后的版本一致）。
- 后台轮询门控：退后台暂停未读 / 社区动态轮询，回前台补一次。
- 图片 / 音效缓存上限：`ImageStore` 24MB、`GameSfx` 12MB；系统低内存时一并释放。
- 其它：const 补齐、铃渡选关 `ListView.builder` 懒加载、我的页 `RepaintBoundary`。

## 3. Mac 构建步骤

```bash
xcodebuild -version
pod --version
flutter --version

cd flutter
flutter pub get
(cd ios && pod install --repo-update)
bash ios/build_ipa.sh
```

脚本等价于：

```bash
flutter build ipa --release \
  --export-method app-store \
  --dart-define=APP_VERSION=2.0.15
```

产物：`flutter/build/ios/ipa/*.ipa`。

## 4. 产物归档与上传

```bash
cp build/ios/ipa/*.ipa "../IPA/Citro-v2.0.15-unsigned.ipa"
shasum -a 256 "../IPA/Citro-v2.0.15-unsigned.ipa"

curl -X PUT -T "IPA/Citro-v2.0.15-unsigned.ipa" \
  -H "Content-Type: application/octet-stream" \
  "https://obs.chimu-claw.xyz/IPA/Citro-v2.0.15-unsigned.ipa"
```

## 5. 发版前验证

1. `CFBundleShortVersionString` 为 `2.0.15`，`CFBundleVersion` 为 `2015`。
2. 真机走查：
   - 我的页快捷区不再出现「编辑资料」，点击顶部头像仍可编辑资料；
   - 主题胶囊更短，下拉菜单选项完整显示；
   - 侧栏底部头像能显示真实头像，加载时先显示昵称首字；
   - iPad 登录弹窗显示「扫码登录」，二维码可刷新、有倒计时；
   - 手机「我的 → 扫一扫」可识别二维码并提示「已确认登录」；
   - 手机号 / 邮箱切换文字在胶囊内居中；
   - 后台运行设置行与其它设置项左对齐；
   - 切页动效与 2.0.14 一致。
3. 服务端已部署新版 `trash/trash.js`（`pm2 restart trash`），扫码三个接口可用。

> ⚠️ 扫码登录依赖 2.0.14 引入的后端接口。若线上尚未部署 `trash/trash.js`，
> `/api/auth/qr/create`、`/api/auth/qr/confirm`、`/api/auth/qr/poll` 会返回 404。

## 6. 本机限制

- Windows 无法执行 `flutter build ipa` 或 `xcodebuild archive`，
  `ios/build_ipa.sh` 会在非 Darwin 环境直接退出。
- 因此 `IPA/` 目录不新增二进制；Android / Windows / Web 三端在 Windows 侧完成构建与 OBS 同步。

## 7. 历史版本记录

| 版本 | 主要端侧改动 |
| --- | --- |
| 2.0.0 | iOS 预打包基线：相机、麦克风、语音识别、相册读写、定位权限文案；ProMotion 与出口合规配置。 |
| 2.0.1 | 沿用 2.0.0 的权限与工程配置。 |
| 2.0.2 | 沿用 2.0.0 的权限与工程配置。 |
| 2.0.3 | 图片解码尺寸收敛、食材库 / 成语链 / 诗句链懒构建、图片磁盘缓存 LRU、Android 低内存回调；数独计分明细、续玩与最佳用时。 |
| 2.0.4 | 未单独出预打包文档（版本跳号）。 |
| 2.0.5 | Tab 切换只重建当前页；听隅后台 / 被遮挡时暂停刷新；清理多余 `Opacity` 合成层；性能探针支持 profile。 |
| 2.0.6 | 补齐 125 处 `const`、清理 32 处冗余 `const`；铃渡选关改 `ListView.builder`（78 关懒加载）。 |
| 2.0.7 | 前后台轮询门控；`ImageStore` 24MB / `GameSfx` 12MB 上限与低内存释放；Android 后台运行设置入口；预测性返回。 |
| 2.0.8 | 全局高刷 `RefreshRate.acquire()`；`preferredRefreshRate` + `preferredDisplayModeId`；生命周期重申请缓解 HyperOS 回 60Hz。 |
| 2.0.9 | 切 Tab 去掉整页 `Opacity`，只保留 8px 位移 + 0.992→1 缩放；我的页设置卡 / 资料卡 / 快捷入口加 `RepaintBoundary`。 |
| 2.0.10 | 页面实例缓存（`_pages` 只创建一次）；启动后空闲预热游戏 / 我的 / 社区。 |
| 2.0.11 | 导航图标 `child` 化；切页改为只做 8px 平移（此动画调整未获确认）。 |
| 2.0.12 | 切页动画恢复原样（淡入 + 缩放 + 位移），保留页面缓存、预热与 `RepaintBoundary`。 |
| 2.0.13 | 我的页回弹；登录注册页重设计；手机号 / 邮箱注册与登录；移除邀请码限制（后端同步）。 |
| 2.0.14 | Web / Windows / iPad 扫码登录；手机端扫一扫；登录子标签居中；主题下拉重设计；后台运行设置行对齐；引入 `qr_flutter` / `mobile_scanner`。 |
| 2.0.15 | 我的页移除「编辑资料」快捷卡片；主题胶囊缩短；Windows 左下角头像改用 `AppImage` 修复显示。 |