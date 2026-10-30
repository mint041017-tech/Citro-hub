# App Store 截图清单与拍摄方法

> 截图必须在 Mac + iOS 模拟器/真机上拍，Windows 不能拍 iOS 素材。
> App Store Connect 每个尺寸 1–10 张；先做 6 张。以后台当前 Required 槽位为准。

## 1. 尺寸

| 设备 | 建议尺寸 | 方向 | 必填 |
| --- | --- | --- | --- |
| iPhone 6.9" | 1320×2868 或 2868×1320 | 竖屏 | 是（iPhone 运行） |
| iPad 13" | 2064×2752 或 2752×2064 | 横屏优先 | 是（iPad 运行） |
| iPhone 6.5" | 1284×2778 / 1242×2688 | 竖屏 | 如后台仍要求则补 |

- Citro 的 iPhone 运行时锁竖屏，iPad 支持全方向；iPad 建议横屏拍摄，展示宽屏手账/游戏布局。
- 图片格式 PNG/JPG，RGB，无透明通道；不要带设备边框外的白边；不要加 TestFlight/Beta/QA 字样。
- 可加简短中文标题，但不能遮挡核心 UI，不能展示未提供的功能。

## 2. 六张截图顺序与文案

| # | 页面 | 建议标题 | 拍摄要点 |
| --- | --- | --- | --- |
| 1 | 首页手账 | 把一天，收进一本手账 | 打卡、天气、今日小猫、壁纸/一言同屏；游客或演示账号都可 |
| 2 | 游戏页 | 15 款小游戏，随缘开黑 | 游戏网格 + 排行榜入口；不要出现 QA 成绩 |
| 3 | 数独/液体 2048 游戏内 | 一局就上头的轻游戏 | 选完成度高的棋盘；数独或咕噜果冻均可 |
| 4 | 社区 | 同频的人，在这里相遇 | 演示动态、评论、抱一抱；不出现真实手机号/私密内容 |
| 5 | 食谱/冰箱 | 今天吃什么，交给 Citro | 食谱步骤图 + 冰箱/购物清单 |
| 6 | 听隅/抽签/卡面 | 听一会儿，抽一支好签 | 听隅播放胶囊、卡面收藏或每日抽签；不要暗示付费/中奖 |

> 如果只能拍 3 张：首页、游戏页、社区。截图要覆盖产品核心，不要六张都是同一个页面。

## 3. 拍摄前准备

- [ ] 用演示账号登录（社区/食谱/卡面/排行榜才能展示）
- [ ] 社区、食谱、游戏成绩准备可公开展示的演示数据
- [ ] 关闭系统弹窗、通知横幅、低电量提示、录屏红点
- [ ] 状态栏设为 9:41、满电、WiFi/信号满格
- [ ] 深色/浅色模式选一种统一；建议浅色，符合手账纸张质感
- [ ] 确认没有 debug banner、TestFlight 水印、测试版标记
- [ ] 确认没有真实用户昵称、手机号、微信、地址、照片
- [ ] 截图内容与 build 1909 一致；如果之后改 UI，重拍

## 4. Mac 拍摄命令

```bash
# 1. 查看可用模拟器
xcrun simctl list devices available
flutter devices

# 2. 启动模拟器（示例：iPhone 16 Pro Max / 6.9 英寸）
open -a Simulator
xcrun simctl boot "iPhone 16 Pro Max" 2>/dev/null || true
xcrun simctl bootstatus "iPhone 16 Pro Max" -b

# 3. 运行 App（在 flutter 目录）
cd flutter
flutter run -d "iPhone 16 Pro Max" \
  --dart-define=API_BASE=https://chimu-claw.xyz/trashapi \
  --dart-define=APP_VERSION=1.9.9

# 4. 状态栏统一（另开终端）
xcrun simctl status_bar "iPhone 16 Pro Max" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4

# 5. 手动导航到目标页面，然后截屏
mkdir -p "app dist/screenshots/raw"
xcrun simctl io "iPhone 16 Pro Max" screenshot \
  "app dist/screenshots/raw/iphone-6.9-01-home.png"
```

iPad 13"：

```bash
xcrun simctl boot "iPad Pro 13-inch (M4)" 2>/dev/null || true
xcrun simctl bootstatus "iPad Pro 13-inch (M4)" -b
cd flutter
flutter run -d "iPad Pro 13-inch (M4)" \
  --dart-define=API_BASE=https://chimu-claw.xyz/trashapi \
  --dart-define=APP_VERSION=1.9.9
# 在 Simulator 菜单 Device → Rotate Left/Right 切横屏，再截屏
xcrun simctl io "iPad Pro 13-inch (M4)" screenshot \
  "app dist/screenshots/raw/ipad-13-01-home.png"
```

- 模拟器名称以 `xcrun simctl list devices available` 实际输出为准；Xcode 版本不同，设备名会变。
- `flutter run` 为 debug 运行，App 已关闭 debug banner；不要用带 banner 的截图。
- 如果模拟器无法登录后端，检查网络、`API_BASE` 和演示账号；不要用本地 QA 地址。
- 也可以用真机截图；真机截图同样要满足尺寸和状态栏要求。

## 5. 可选：自动逐张截屏

Mac 上使用：

```bash
bash "app dist/scripts/capture-ios-screenshots.sh" "iPhone 16 Pro Max"
```

脚本会启动模拟器、设置状态栏，然后每按一次回车截一张图；页面切换仍需手动完成，避免把密码写进脚本。

## 6. 后期与上传

- 用图片工具裁切/缩放，但不要拉伸变形；保持原始 UI 比例。
- 可加标题文字，建议 1 行、字号足够、放在顶部或底部留白区。
- 不要伪造功能、评分、媒体 logo、奖项或“App Store 编辑推荐”等标识。
- 上传前逐张放大检查：手机号、昵称、社区内容、AI 回复、错误弹窗都不能泄露隐私或显得未完成。
- 截图成品建议放 `app dist/screenshots/final/`；本目录的 `.gitignore` 已忽略 raw/final，避免把大图提交进仓库。
