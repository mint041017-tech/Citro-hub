# 迟暮·Crew 1.8 — 系统推送与构建约定

> 生成时间：2026-10-16
> 版本：`versionCode 180` · `versionName 1.8`（仅 stable 渠道）
> 产物：`APK/迟暮Crew-Kotlin-v1.8-release.apk`

---

## 一、这两条是硬约定

### 1. 构建 APK 绝不修改根目录的 HTML

`index.html`（以及 `beian.html`）是**网站与 App 共用的同一份源码**。
构建只允许改写 `kotlin/app/src/main/assets/www/` 下的副本：

| 脚本 | 行为 |
| --- | --- |
| `kotlin/sync-www.js` | 把根目录资源复制到 `assets/www`，再对**副本**做补丁（去「下载 App」入口、16 条 App 兼容补丁） |
| `kotlin/build.js` | 先跑 sync，再 gradle 打包，最后复制 APK 到 `APK/` |

两个脚本都在开工前记录根目录 HTML 的 SHA-256、收尾时校验；一旦发现被改动就
**直接报错退出**（`❌ 构建中止：根目录 HTML 被改动了`），杜绝"打包顺手改了网页"。

### 2. 默认只打 stable，不再随版本打 beta

```powershell
cd C:\迟暮\迟暮Crew\kotlin
node build.js release            # 默认 = release + stable
node build.js release beta       # 单独要 beta 时才这么写
node build.js release both       # 两个渠道都要
```

---

## 二、四项系统推送能力（1.8 新增）

### 关键设计：运行时注入，不改任何 HTML

`index.html` 的整段业务脚本包在一个 IIFE 里，`cookTimers` / `gamesSubmit` / `me`
都**不是 window 全局变量**，外部脚本读不到；而用户又要求构建不许改根目录 HTML。

于是桥接方式定为：**外壳在网页加载完成后把 `assets/chimu-bridge.js` 注入页面**
（`MainActivity.injectBridge()` → `evaluateJavascript`）。脚本只依赖三个不需要作用域的口子：

1. **DOM 镜像** —— 读 `#cookTimers` 里的 `.cook-timer` 节点（名字 / 剩余时间 / `data-del` id）
2. **`window.fetch` 拦截** —— 观察 `/api/games/score`、`/api/games/board`、`/api/notifications/read`
3. **localStorage** —— 登录 token、游客设备号、计时器镜像

配合 `addJavascriptInterface` 暴露的 `window.ChimuNative`，网页与原生双向通信。

### 四项能力分别怎么实现的

| 需求 | 实现 |
| --- | --- |
| ① 社区收件箱系统推送 | 原生 `PushChecker` 后台轮询 `GET /trashapi/api/notifications`，比对水位线 `lastNotifTs`，新的未读消息发系统通知（回复 / 评论 / 点赞分别措辞）。鉴权只用 **`X-Trash-Token` 头**（HttpURLConnection 没有 cookie jar，原生不带 cookie） |
| ② 食谱计时到点推送 + 常驻倒计时 | `chimu-bridge.js` 每秒镜像计时器 → `CookTimerService`（**前台服务**）在通知栏常驻倒计时（系统 chronometer，每秒自己走），到点直接发系统通知。App 切后台 / 锁屏也不会漏；通知栏带一个「取消计时」按钮，页面刷新后也能撤掉 |
| ③ 排行榜被超越推送 | 玩家提交成绩时（fetch 拦截 `/api/games/score`）记住该榜单；看榜时把"我的名次"作为基准。原生轮询 `GET /api/games/board?game=…`，名次变大即"被超越"，通知里带上超越者的昵称。每轮最多查 6 个榜、带 45 秒时间预算（避免顶穿广播接收器的 ANR 预算） |
| ④ 打开先要通知权限 | `MainActivity.onCreate()` → `requestNotificationPermission()`（Android 13+ 的 `POST_NOTIFICATIONS`）；网页点「开始计时」时也会再要一次 |

### 去重：网页与原生不能各弹一条

网页里原本就有 `cookNotify()`（找 Capacitor 的 LocalNotifications）。桥接脚本
垫了一个 **Capacitor 兼容 shim**，让它直接落到原生通知；同时 `CookTimerService`
记录"正在倒计时"和"刚刚响过"的名字，`ChimuBridge.notify()` 命中就丢弃。
去重窗口给到 **5 分钟** —— App 切后台后 WebView 的定时器会被节流到一分钟甚至更久
才跑一次，网页那条 `cookNotify` 可能比原生晚很多才到，窗口太小就会弹两条。

### 收件箱水位线只用服务端时间

`/api/notifications/read` 只让服务端把消息标成已读，**本地不动水位线**：
水位线是拿来和服务端 `ts` 比大小的，若写入本机当前时间，手机时钟快于服务器
就会把之后所有新消息永久跳过。

### 通知渠道

| 渠道 | 用途 | 重要性 |
| --- | --- | --- |
| `chimu_messages` | 社区消息、排行榜被超越 | HIGH（有声 + 震动） |
| `chimu_cook_done` | 计时到点 | HIGH（有声 + 震动） |
| `chimu_cook_run` | 通知栏常驻倒计时 | LOW（静音，前台服务通知） |

### 已知边界（没有服务端推送通道）

- 没有 FCM / 厂商推送，收件箱与排行榜靠 **AlarmManager 每 15 分钟拉一次**
  （`setInexactRepeating`，不精确；Doze 下可能更晚）+ **每次回到前台立即拉一次**。
  也就是"推送"延迟最坏可达十几分钟，不是秒级。
- 强制停止 App 后闹钟失效（安卓规则），重新打开会重新注册；重启手机由
  `BootReceiver` 重新注册。
- 计时器镜像会写进 localStorage，网页刷新 / WebView 重建也不会丢倒计时。

---

## 三、重新构建

```powershell
$env:JAVA_HOME = "C:\Android\jdk-21.0.12.1+1"
cd "C:\迟暮\迟暮Crew\kotlin"
node chimu-bridge.selftest.js     # 可选：桥接脚本离线自测（17 项断言）
node build.js release             # 产物：..\APK\迟暮Crew-Kotlin-v1.8-release.apk
```

## 四、新增文件

| 文件 | 作用 |
| --- | --- |
| `kotlin/app/src/main/assets/chimu-bridge.js` | 运行时注入的网页↔原生桥（**不是** HTML 的一部分） |
| `kotlin/app/src/main/java/com/chimu/crew/ChimuBridge.kt` | `window.ChimuNative` 的 Kotlin 实现 |
| `…/CookTimerService.kt` | 计时器前台服务（常驻倒计时 + 到点通知） |
| `…/PushChecker.kt` | 收件箱 / 排行榜轮询与通知 |
| `…/PushScheduler.kt` | 定时闹钟 + 开机重注册（含 `PushAlarmReceiver`、`BootReceiver`） |
| `…/PushStore.kt` | token / 水位线 / 名次快照 / 玩过的游戏 |
| `…/Notify.kt` | 通知渠道与发通知统一入口 |
| `kotlin/chimu-bridge.selftest.js` | 桥接脚本的 Node 离线自测 |
