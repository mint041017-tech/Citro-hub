# Citro iOS 预打包清单（合并版）

> 从 2.0.15 起，原先按版本拆分的 `docs/ios-vX-预打包.md` 全部合并到本文件。
> 后续发版只维护这一份：更新第 1 节的版本号，在第 2 / 5 节补充当次改动，
> 并在第 7 节历史表追加一行即可。
>
> 当前版本：`3.5.1+3501` · 更新日期：2026-11-28

## 1. 当前版本与工程状态

> 当前发布环境为 Windows，Xcode 工具链不可用，因此只完成「预打包」：
> 版本、工程配置、权限文档与构建脚本已核对就绪，IPA 需在 macOS 上生成。

| 项目 | 值 | 位置 |
| --- | --- | --- |
| Flutter 版本号 | `3.5.1+3501` | `flutter/pubspec.yaml` |
| Bundle ID | `com.chimu.crew` | `flutter/ios/Runner.xcodeproj/project.pbxproj` |
| 短版本号 | `$(FLUTTER_BUILD_NAME)` → 3.5.1 | `flutter/ios/Runner/Info.plist` |
| Build 号 | `$(FLUTTER_BUILD_NUMBER)` → 3501 | `flutter/ios/Runner/Info.plist` |
| 最低系统 | iOS 15.0 | `flutter/ios/Podfile` |
| 高刷开关 | `CADisableMinimumFrameDurationOnPhone = true` | `flutter/ios/Runner/Info.plist` |
| 出口合规 | `ITSAppUsesNonExemptEncryption = false` | `flutter/ios/Runner/Info.plist` |
| 计时 Live Activity | `CitroTimerWidget` | `flutter/ios/CitroTimerWidget` |

已同步 `ios/Flutter/Generated.xcconfig` 与 `ios/Flutter/flutter_export_environment.sh` 的
`FLUTTER_BUILD_NAME=3.5.1`、`FLUTTER_BUILD_NUMBER=3501`。

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

### 2.5 启动页与 iPad 侧栏

- iOS 原生启动页（`LaunchScreen.storyboard`）与 Flutter 启动页同一套设计：奶米底、
  logo 柔光、`Citro · 今天也要开心` 与底部胶囊；不再使用 1.8.0 时期的猫咪插画，
  冷启动不再出现旧图到 logo 页的跳变。
- 原生页只放一块 **240×352pt 的透明品牌块**（`LaunchBrand.imageset`）：居中、
  `scaleAspectFit`、宽高由约束钉死，所以任何机型、任何横竖屏都不会被裁切或拉伸，
  也不会随屏幕比例改尺寸；版面尺寸与 Flutter 端 176pt logo 区 / 148pt 图一致。
- 背景用命名色 `LaunchBackground`（`LaunchBackground.colorset`）：浅色 `#F9EDD7`、
  深色 `#1E1A18`；品牌块另有 `LaunchBrandDark` 深色变体（墨色文字、深底胶囊）。
  两套资源都由 `flutter/tool/make_launch_images.py` 生成（logo 与圆体字取自 App
  资源），改配色 / 字号后重跑脚本即可，不要手工改 PNG。
- iPad 侧栏与 Windows 完全对齐：首页、计划、游戏、社区、资源库、全站搜索、CiCi；
  「我的」只由底部头像卡打开，不再单独占一项。
- iPad 的资源库 Tab 仍隐藏外设驱动板块（`ResPage.hideDrivers`）。

### 2.6 游戏页手机竖屏顶栏

- 手机竖屏（宽 ≤ 600 且高 > 宽）所有 `GameScaffold` 游戏启用紧凑顶栏：游戏名靠左，
  错误 / 用时 / 最佳等只读读数缩小收进顶栏右侧；平板、桌面与横屏保持居中标题 + 读数卡。
- 读数按真实文本宽度排布，放不下时自动折到标题下方一行；难度条与棋盘之间留 24dp 间距。
- 淘气小球、跳一跳这类自定义 `hud:` 页面显式提供 `hudStats`，其余游戏从 `pills` 自动提取。

### 2.7 3.5.1 预打包检查

- 天气详情、心情详情弹窗提高玻璃模糊并加深深色模式填充，次级文字更清晰。
- 首页天气卡标签、城市、描述与体感/湿度字号整体放大，窄卡自适应不溢出。
- Android 滚动与切 Tab 时底栏玻璃临时降低实时模糊，静止后恢复完整模糊，减少动画掉帧。
- 沿用 3.3.5 的测试中心 / 十二系测评、MBTI 测试档案、登录注册改版与全局玻璃/游戏卡片视觉。
- 版本号、Info.plist 变量、Generated.xcconfig 与构建脚本已同步到 `3.5.1 / 3501`。

### 2.8 3.3.5 预打包检查

- 新增「测试中心」：十二系亲密关系测评（40 题 / 5 维 / 12 原型，600 次蒙特卡洛稳定率），结果页含五维雷达、成人依恋平面、Curran 效度审计与关系动力学。
- MBTI 图鉴入口移除，历史结果改为「测试档案」内联回顾；档案随账号云端同步。
- 登录注册重做：自动识别手机号或邮箱，注册免昵称、增加确认密码，首次进入补全资料。
- 全局玻璃材质与深色模式通透度重新调校，底部标签栏磨砂更清晰。
- 游戏卡片与游戏页视觉优化，桌面、平板与手机布局更统一。
- 版本号、Info.plist 变量、Generated.xcconfig 与构建脚本已同步到 `3.3.5 / 3305`。

### 2.9 3.3.1 预打包检查

- 每日一签取消同级签按日期轮换，等级与具体签位独立随机；旧三段缓存会在首次读取时补随机签位并升级。
- 签文改为七段文本流式协议，签题、诗、读签、关键词、今日一小步、忌与便签逐段返回。
- 今日一小步新增生成后校验与手边动作兜底，过滤依赖他人、外出、购买、预约和等待回复的任务。
- 社区取消 200 字限制，长文按真实渲染宽度超过五行折叠，可展开 / 收起。
- 版本号、Info.plist 变量、Generated.xcconfig 与构建脚本已同步到 `3.3.1 / 3301`。

### 2.10 3.3.0 预打包检查

- MBTI 96 题测试、结果人格切片与二维码分享卡已进入 iOS 共用 Flutter 页面。
- 每日打卡升级：趣签筒、今日一签、晚间回签与七日成卷；手机签印改为独立朱砂色文字印记。
- 图鉴、历史记录与类型详情的返回转场缩短，不影响 iOS 系统 Cupertino 手势。
- 版本号、Info.plist 变量、Generated.xcconfig 与构建脚本已同步到 `3.3.0 / 3300`。

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
  --dart-define=APP_VERSION=3.5.1
```

产物：`flutter/build/ios/ipa/*.ipa`。

## 4. 产物归档与上传

```bash
cp build/ios/ipa/*.ipa "../IPA/Citro-v3.5.1-unsigned.ipa"
shasum -a 256 "../IPA/Citro-v3.5.1-unsigned.ipa"

curl -X PUT -T "IPA/Citro-v3.5.1-unsigned.ipa" \
  -H "Content-Type: application/octet-stream" \
  "https://obs.chimu-claw.xyz/IPA/Citro-v3.5.1-unsigned.ipa"
```

## 5. 发版前验证

1. `CFBundleShortVersionString` 为 `3.5.1`，`CFBundleVersion` 为 `3501`（CI 上传时会按 TestFlight 已有构建号自增，以收据为准）。
2. 真机走查：
   - 冷启动首屏是奶米底 logo 启动页（与 Flutter 启动页同款），不再出现旧猫咪插画；
   - 系统深色模式下冷启动是深底变体，浅色模式下是奶米底，两套都不会裁切 logo；
   - iPad 侧栏包含首页、计划、游戏、社区、资源库、全站搜索、CiCi，且没有「我的」项；
   - iPad 的资源库 Tab 不显示外设驱动板块；
   - 我的页快捷区不再出现「编辑资料」，点击顶部头像仍可编辑资料；
   - 主题胶囊更短，下拉菜单选项完整显示；
   - 侧栏底部头像能显示真实头像，加载时先显示昵称首字；
   - iPad 登录弹窗显示「扫码登录」，二维码可刷新、有倒计时；
   - 手机「我的 → 扫一扫」可识别二维码并提示「已确认登录」；
   - 手机号 / 邮箱切换文字在胶囊内居中；
   - 后台运行设置行与其它设置项左对齐；
   - 切页动效与 2.0.14 一致；
   - 游戏页手机竖屏：顶栏读数不挤压标题，HUD 卡收起，难度条与棋盘间距 24dp，长标题与大字体自动折行。
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
| 2.0.16–2.0.40 | 新增记账 / 待办 / 日历详情 / 倒数日与纪念日 / 首页卡片编排与迷你卡；评论时间右上角；CiCi 自定义性格；后台轮询门控与低内存清理；CORS、限流、WebView 外链与备份安全加固。 |
| 2.1.0 | 版本号与 iOS 构建配置同步到 `2.1.0+2100`；日历/待办/记账卡与评论时间定稿；性能与安全修复合并；四端重新打包，IPA 待 macOS 生成。 |
| 3.1.67 | 版本号与 iOS 构建配置同步到 `3.1.67+3167`；「一起看」声网主链路 + CF 兜底架构、网页观看端链路角标与全屏聊天按钮、App 全屏退出画面压条修复、抽签记录与圆形角标优化；IPA 待 macOS 生成。 |
| 3.1.68 | 版本号与 iOS 构建配置同步到 `3.1.68+3168`；首页 CiCi 新增直接记账、倒数日与纪念日（指令解析、写入与回执），修复连续入账 id 重复；iOS 原生启动页换成与 Flutter 启动页一致的 logo 版；iPad 侧栏与 Windows 对齐（资源库 / CiCi 进栏、移除我的，资源库隐藏驱动）；IPA 待 macOS 生成。 |
| 3.2.0 | 版本号与 iOS 构建配置同步到 `3.2.0+3200`；游戏页手机竖屏顶栏改版（游戏名靠左、错误/用时/最佳读数收进顶栏、放不下时折到标题下方），平板 / 桌面 / 横屏版式不变；IPA 待 macOS 生成，推送 main 后由 TestFlight CI 构建上传。 |
| 3.2.1 | 版本号与 iOS 构建配置同步到 `3.2.1+3201`；手机数独操作行随棋盘滚动，四个工具页返回完整淡出；IPA 由 TestFlight CI 构建上传。 |
| 3.3.0 | 版本号与 iOS 构建配置同步到 `3.3.0+3300`；MBTI 96 题测试与二维码分享、每日打卡回签与七日成卷、独立朱砂色今日签上线；IPA 待 macOS 生成，推送 main 后由 TestFlight CI 构建上传。 |
| 3.3.1 | 版本号与 iOS 构建配置同步到 `3.3.1+3301`；每日一签改为完全随机并移除同级日期轮换，签文七段流式输出，今日一小步增加动作校验与兜底，社区长文五行折叠；IPA 待 macOS 生成，推送 main 后由 TestFlight CI 构建上传。 |
| 3.3.5 | 版本号与 iOS 构建配置同步到 `3.3.5+3305`；新增测试中心与十二系亲密关系测评、MBTI 测试档案内联回顾；登录注册自动识别账号与免昵称注册；全局玻璃与深色模式通透度调校；游戏卡片视觉改版；IPA 待 macOS 生成，推送 main 后由 TestFlight CI 构建上传。 |
| 3.5.1 | 版本号与 iOS 构建配置同步到 `3.5.1+3501`；天气/心情详情弹窗加强模糊与深色填充，首页天气卡字号放大；Android 滚动/切页期间底栏玻璃自适应降模糊；IPA 待 macOS 生成，推送 main 后由 TestFlight CI 构建上传。 |