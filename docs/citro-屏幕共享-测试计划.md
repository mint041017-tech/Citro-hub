# Citro 一起看（屏幕共享）· 测试计划

配套方案：`citro-屏幕共享-cloudflare升级方案.md`
运维手册：`citro-屏幕共享-运维手册.md`

---

## 1. 测试范围

| 层次 | 对象 | 方式 |
|---|---|---|
| 信令 | Worker + Durable Object（REST / WebSocket） | 自动化（vitest-pool-workers） |
| 客户端 | Flutter 模型 / 事件解析 / 入口页 | 自动化（flutter_test） |
| 媒体 | Cloudflare Realtime SFU 采集与转发 | **手动**（需要真实密钥与真机） |
| 网络 | 中国大陆三大运营商 | **手动**（方案 §7.2 矩阵） |
| 平台 | Android 前台服务 / iOS 广播扩展 | **手动**（需要真机） |

---

## 2. 已有的自动化测试

### 2.1 Worker：23 个用例（`screen-share/test/`，17 + 6）

```
cd screen-share
npm test
```

覆盖（`test/api.test.ts`，15 个）：

- 房间创建 / 加入 / 查询 / 结束
- **只用 6 位房间码也能找到同一个房间**（回归 `doKey`）
- 错误房间码被拒
- 发布 / 订阅 / answer 的 SDP 交换与 `mid` 透传
- **观众满 50 人拒绝**（回归：房主不占名额，50 个观众都能进，第 51 个被拒）
- 主持人结束房间；结束后旧 token 不能再加入
- **房主断线宽限**（F-09）：房主最后一个连接断开后 DO 闹钟改成 `now + HOST_GRACE_MINUTES`，
  到点回收房间；宽限内重连（重连 WS 或重新 `join`）则恢复成房间的到期时间
- WebSocket：hello 快照（自己 / 成员 / 聊天记录）、缺少凭证不能建连
- **语音权限**：观众可以发布 mic-only；只开麦的观众仍不能发布画面
  （回归旧实现 `tracks.length > 0` 的提权口子）；开麦不改变角色、不涨 `publisherCount`

覆盖（`test/token.test.ts`，6 个）：token 签发 / 验回、密钥错误拒绝、过期拒绝、篡改拦截、`extractBearer` 解析、错误码形状（`status + code + message`）。

暂未自动化，需手动或暂未覆盖：

- 主持人踢人（`POST /kick`）
- 按 `expiresAt` 的自然回收（上面的宽限用例触发的是宽限闹钟，不是到期闹钟）
- SFU 的真实媒体收发（测试里 `rtc.live.cloudflare.com` 是 mock）

### 2.2 Flutter：30 个用例（`flutter/test/screen_share_test.dart`）

```
cd flutter
flutter test test/screen_share_test.dart
```

覆盖：

- 6 个画质档位、码率、采集约束、非法值回落
- `RoomTrack.mid` 往返（发布/订阅匹配的关键）
- `RoomMember` 角色与能力推导
- `RoomInfo` 邀请链接、`copyWithLive`、状态判定
- `WsEvent` 对 hello / chat / publisher_joined / viewer_count / quality_changed 的解析
- `SfuSessionResult` 的 mid 语义
- **邀请链接解析**：纯数字、完整链接、自由文本、非法输入
- 入口页渲染、房间码预填、画质弹层交互

> 写这个测试时抓到并修掉了一个真实 bug：`_QualitySheet` 的 `Column` 在
> 小屏（或系统字体放大）下会溢出 178px，最后两档被裁掉。已改为可滚动。

---

## 3. POC 测试矩阵（方案 §7.2）

> ⚠️ **入口域名**：`*.workers.dev` 在大陆被 DNS + SNI 双重阻断（见运维手册 §4.1），
> POC 必须使用 `share.mint1017.cn`。在这一步完成之前，POC 无法在大陆发起。
>
> **partial（CNAME）setup 已被否掉**：官方文档要求 Business/Enterprise 套餐，
> 且 `cdn.cloudflare.net` 实测不解析。可行路径是把域整域迁到 Cloudflare
> （Free 即可）——代理记录会被 CNAME 展平成 Cloudflare 边缘 IP，客户端不会去
> 解析 `workers.dev`。详见运维手册 §4.2。
>
> 注：`share.chimu-claw.xyz` 的 zone 也曾建好，但其注册局委派又回到了华为云
> DNS，公网不可解析，故当前入口域名是 `share.mint1017.cn`（见运维手册 §4.4）。

**这一步是决定项目能不能继续的关键**，必须在 MVP 之前完成。

| 维度 | 要求 |
|---|---|
| 运营商 | 中国电信、中国联通、中国移动各至少 2 条线路 |
| 时段 | 工作日下午、晚高峰 20:00–22:00 各一轮 |
| 规模 | 1 个共享端 + 50 个观众端 |
| 时长 | 每轮至少 30 分钟 |
| 网络 | 家庭宽带、公司网络、4G/5G 各覆盖 |

### 通过标准

| 指标 | 阈值 |
|---|---|
| 加入成功率 | ≥ 98% |
| 30 分钟卡顿次数 | < 3 次 |
| 端到端延迟 | < 1.2 s |
| 花屏 / 黑屏 | 0 次 |

### 记录表（每轮填一份）

| 字段 | 示例 |
|---|---|
| 日期 / 时段 | 2026-11-20 20:15 |
| 运营商 / 网络类型 | 中国电信 / 家庭宽带 500M |
| 共享端平台 | Windows 11 / Android 14 |
| 观众人数 | 50 |
| 画质档位 | 720p30 |
| 加入成功 / 总数 | 49 / 50 |
| 卡顿次数 | 1 |
| 实测延迟 | 800 ms |
| 花屏 / 黑屏 | 无 |
| 备注 | 晚高峰偶发丢包 |

### 不达标时的处理顺序（方案 §7.3）

1. 降码率：720p → 1.2~1.5 Mbps，优先保证流畅；
2. 确认 TURN 生效（大陆无 Cloudflare 节点，中继大概率必需）；
3. 切换国内云：腾讯云 TRTC / 声网 Agora 做媒体层，Cloudflare 只保留
   静态页与房间 API；
4. 分区部署：海外走 Cloudflare，大陆走国内云。

---

## 4. 功能用例

### 4.1 房间生命周期

| 编号 | 用例 | 预期 |
|---|---|---|
| F-01 | 未登录创建房间 | 被拒（生产配了 `TRASH_API_BASE` 后） |
| F-02 | 登录后创建房间 | 返回 6 位房间码 + 房间 token |
| F-03 | 用房间码加入 | 成为 viewer，成员列表 +1 |
| F-04 | 房间码错误 | 提示「请输入正确的房间码」 |
| F-05 | 房间已结束 | 加入被拒 |
| F-06 | 满 50 人再加入 | 被拒（房主重连不受限）。已自动化，见 §2.1 |
| F-07 | 主持人结束房间 | 所有人的 WS 收到 `room_ended`，客户端弹提示并退出 |
| F-08 | 观众离开 | 成员列表 -1，观看人数更新 |
| F-09 | 主持人断线后重连 | 5 分钟内可重连，房间不被回收。已自动化，见 §2.1 |

### 4.2 共享与观看

| 编号 | 用例 | 预期 |
|---|---|---|
| F-10 | 主持人开始共享 | 观众端 3 s 内出现画面 |
| F-11 | 打开麦克风 | 观众能听到声音（需订阅 `mic` 那一路） |
| F-12 | 切换画质 | 观众端画质变化，`quality_changed` 事件到达 |
| F-13 | 停止共享 | 观众端回到「等待主持人开始共享」 |
| F-14 | 多路共享（多对多） | 观众端同时显示多路，可切换主画面 |
| F-15 | 共享中红色边框 / 「正在共享」提示 | 防止误共享 |
| F-26 | 观众（不共享画面）开麦 | 其他端能听到；角色仍是 viewer |
| F-27 | 共享中关麦 → 再开麦 | 画面不中断（只切 `track.enabled`，不重发整路） |
| F-28 | 停止共享但麦克风开着 | 画面消失，声音继续；再开共享声音不中断 |
| F-29 | Windows 点「开始共享」 | 先出现屏幕 / 应用窗口选择器，选中后只共享该项 |

### 4.3 邀请

| 编号 | 用例 | 预期 |
|---|---|---|
| F-16 | 复制房间码 | 复制 6 位数字 |
| F-17 | 复制邀请链接 | 复制 `https://share.mint1017.cn/?room=xxxxxx` |
| F-18 | App 内点链接 | 打开原生房间页，房间码自动填好 |
| F-19 | 浏览器点链接（未装 App） | 打开网页观众页，可观看 |
| F-20 | 粘贴链接到输入框 | 自动解析出 6 位房间码 |

### 4.4 沟通

| 编号 | 用例 | 预期 |
|---|---|---|
| F-21 | 文字聊天 | 收发即时，重进能看到历史（最近 50 条） |
| F-22 | 语音 | 任何人开麦后其它端都能听到（不再要求先共享画面） |
| F-23 | 空消息 | 被服务端拒（「消息不能为空」） |

### 4.5 小窗

| 编号 | 用例 | 预期 |
|---|---|---|
| F-24 | 应用内小窗 | 可拖动，不阻断其他操作 |
| F-25 | 系统画中画（Android） | 切到后台后继续显示 |

> F-25 目前只声明了 `android:supportsPictureInPicture="true"`，
> **尚未实现进入 PiP 的逻辑**，需要补一个插件或平台通道。

---

## 5. 弱网与稳定性

| 编号 | 场景 | 预期 |
|---|---|---|
| S-01 | 共享中切 Wi-Fi → 4G | 5 s 内恢复 |
| S-02 | 观众断网 10 s 后恢复 | 自动重连，画面恢复 |
| S-03 | 主持人断网 10 s 后恢复 | 自动重连，观众仍在 |
| S-04 | 30 分钟连续共享 | 无崩溃、无内存暴涨 |
| S-05 | 50 人同时观看 60 分钟 | 不崩溃 |
| S-06 | 服务端 500 | 客户端提示错误，不白屏 |
| S-07 | 房间 token 过期 | 提示并引导重新加入 |

**弱网模拟**：Android 上用 `adb shell svc data disable` / 模拟器网络限速；
Windows 上用 Clumsy 或 Network Emulator。

---

## 6. 安全用例

| 编号 | 用例 | 预期 |
|---|---|---|
| A-01 | 客户端抓包 | 能看到房间 token（2 h 有效）与主站会话 token `X-Trash-Token`（30 天有效），**看不到 App Secret** |
| A-02 | 伪造房间 token | 被拒 |
| A-03 | 过期房间 token | 被拒 |
| A-04 | 观众尝试发布 `screen` | 被拒（1 对多模式下）；只发 `mic` 是允许的 |
| A-05 | 观众尝试调 `/kick` `/end` | 被拒 |
| A-06 | 订阅自己的画面 | 被拒 |
| A-07 | 生产未配 `TRASH_API_BASE` | **任意 token 都能建房 —— 上线前必须确认已配置** |
| A-08 | 房间码暴力尝试 | 同一 IP 每分钟 20 次后限流 |

---

## 7. 性能基线

| 指标 | 目标 | 测法 |
|---|---|---|
| 加入房间 | < 3 s | 从点击「加入」到看到画面 |
| 端到端延迟 | < 1.2 s | 共享端操作 → 观众端可见 |
| 720p30 码率 | ≈ 2.5 Mbps | Cloudflare Dashboard |
| 1080p30 码率 | ≈ 4 Mbps | 同上 |
| 2K30 码率 | ≈ 8 Mbps | 同上 |

码率与画质档位一一对应（`flutter/lib/screen_share/share_quality.dart`）：

| 档位 | 分辨率 | 帧率 | 目标码率 |
|---|---|---|---|
| 720p · 30fps | 1280×720 | 30 | 2.5 Mbps |
| 720p · 60fps | 1280×720 | 60 | 4 Mbps |
| 1080p · 30fps | 1920×1080 | 30 | 4 Mbps |
| 1080p · 60fps | 1920×1080 | 60 | 6.4 Mbps |
| 2K · 30fps | 2560×1440 | 30 | 8 Mbps |
| 2K · 60fps | 2560×1440 | 60 | 12.8 Mbps |
| 内存（共享端） | 30 分钟不持续增长 | Android Profiler / Windows 任务管理器 |
| 崩溃率 | 0 | Firebase Crashlytics（若已接入） |

---

## 8. 兼容性

| 平台 | 版本 | 共享端 | 观看端 |
|---|---|---|---|
| Windows | 10 / 11 | ✅ | ✅ |
| Android | 7.0+（API 24+） | ✅ | ✅ |
| iOS | 15.0+ | ❌（第二阶段） | ✅ |
| Chrome / Edge | 最新版 | — | ✅ |
| Safari | 最新版 | — | 部分（`transceiver.mid` 匹配会走兜底逻辑） |

> Android 共享需要 Android 14+ 的 `mediaProjection` 前台服务；
> 低版本上没有这条硬性要求，代码会自动跳过。

---

## 9. 当前未覆盖的部分

写下来是为了不假装已经测过：

1. **真实媒体链路**：采集 → SFU → 播放，需要真实的
   `CF_REALTIME_APP_ID/SECRET`，本地无法验证。
2. **中国大陆网络质量**：Cloudflare 无大陆节点，必须实测。
3. **iOS**：`Info.plist` 的 `RTCAppGroupIdentifier` /
   `RTCScreenSharingExtension` 与 Broadcast Upload Extension 未配置，
   需要 macOS + Xcode。
4. **系统画中画**：未实现。
5. **50 人压测**：未执行。
6. **流量告警**：方案要求的 800 GB 预警未实现，目前是人工看 Dashboard。
7. **Windows 构建**：本机装有 cmake 3.31.6-msvc6，也产出过 Windows Release 构建；
   但该构建早于 `flutter/lib/screen_share`（11-14 02:01 起），屏幕共享未在 Windows 上验证（Android 已验证）。

---

## 12. Windows 采集缺陷修复（2026-11-14）

**现象**：Windows 端创建房间成功后点「开始共享」，toast 报
`开始共享失败：Unable to getDisplayMedia: source not found!`。Android 无此问题。

**根因**（读 `flutter_webrtc-1.6.3` 的 `common/cpp/src/flutter_screen_capture.cc` 确认）：
桌面端 `getDisplayMedia` 只从「已枚举源缓存」（`sources_`）里按 id 找源；缓存只有
`desktopCapturer.getSources()` 会填。不带 `deviceId` 时 native 侧按 `source_id="0"`
查找，而没有任何源 id 是 `"0"`。「缓存为空时取第一块屏」的兜底只存在于
`#ifdef __linux__` 分支，Windows / macOS 没有 → 必然 `source not found!`。
我们的 UI 从不做源选择，`startSharing` 也从不传 `sourceId`，三个条件全占，100% 复现。

**修复**：`screen_capture.dart` 桌面分支先 `listSources()`（内部走 `getSources()`）
填缓存，取第一块屏幕（无屏幕则第一个窗口）的 id 塞进 `deviceId.exact` 再采集。
`screen_share_test.dart` 30/30 通过。

**连带**：本机系统区域中文（代码页 936），MSVC 按 GBK 解码 `flutter_webrtc`
无 BOM UTF-8 源文件触发 C4819，叠加应用模板的 `/W4 /WX` 直接断编译。
已在 `flutter/windows/CMakeLists.txt` 的 `apply_standard_settings` 加 `/utf-8`
（保住「警告即错误」对真实问题的保护，同时治好解码）。

**服务端复验（同日）**：注册真实账号 → 创建房间 200 → 房间凭证拉 ICE 200（含
TURN）→ 带 SDP 发布穿透到 SFU（收到 SFU 协议级应答）→ 结束房间 200。
Windows 端到端采集→观看仍待真实桌面跑一轮。

**同日第二个缺陷（图标空白 / 看不到返回按钮）**：`AppIcons.*` 常量是裸 SVG
片段（多个 `<path>` 并列），`AppIcon` 直接把它们交给 `SvgPicture.string`，
缺 `<svg>` 根节点解析失败 → 所有漏包 `strokeSvg(...)` 的调用点静默渲染空白。
`lib/screen_share/` 全部十来处都漏了，房间页顶栏的返回箭头也是空白，看起来
像「没有返回按钮」。修复：`AppIcon.build` 内统一兜底（非完整文档自动按描边
图标包一层），并给 `ScreenSharePage` 补了自带的「返回」胶囊按钮（桌面端没有
系统返回键，被 push 的页面必须自带出口）。连带修好 `auth_modal` /
`login_page` 里一直空白的登录方式图标与勾选标记。

---

## 10. 网页观众端手工验收（2026-11-14 已执行）

网页观众端（`screen-share/public/index.html`）没有 DOM 测试环境，
它的验收只能靠真实浏览器。下面是 2026-11-14 实际跑过的步骤，
**建议每次改动这个页面后重跑一遍**。

### 怎么起

```bash
cd screen-share
npx wrangler dev --port 8787
```

浏览器打开 `http://localhost:8787/`。

### 用例

| 编号 | 步骤 | 预期 |
|---|---|---|
| W-01 | 直接打开 `/` | 只有落地页；**不能**出现「房间已结束」遮罩 |
| W-02 | 打开 `/?room=<6位码>` | 房间码自动填好 |
| W-03 | 点「加入房间」 | 进入房间页，标题 / 房间码 / 在线人数 / 画质正确，无报错 |
| W-04 | 输入 5 位数字加入 | 客户端提示「请输入 6 位数字房间码」 |
| W-05 | 输入不存在的 6 位码加入 | 服务端提示「请输入正确的房间码」 |
| W-06 | 打开聊天，发一条消息 | 消息出现在列表里，且标记为自己发的 |
| W-07 | 另一个客户端加入同一房间 | 在线人数实时 +1（走 WebSocket） |
| W-08 | 主持人结束房间 | 遮罩出现：「房间已结束 / 主持人已结束共享」 |
| W-09 | 点「返回首页」 | 回到落地页，**加入按钮可点**，遮罩消失 |
| W-10 | 再进入另一间房 | 房间页正常，**没有**上一间留下的遮罩 |

### 这一次跑出来的三个真实 bug（已修）

1. **`[hidden]` 被作者样式盖掉** —— `.overlay{display:grid}` 与
   `#room{display:flex}` 的优先级高于 UA 的 `[hidden]{display:none}`，
   导致落地页一打开就被「房间已结束」遮罩糊住，网页端完全不可用。
   已加 `[hidden]{display:none!important}`。
2. **`showError(box, null)` 把清空写成「出错了」** —— 每次点加入前都先误报一次。
   已改为 `err == null` 时清空。
3. **`backHome()` 不清上一间房的状态** —— 加入按钮卡在 `disabled`，
   且 `endedOverlay` 还开着，下一间房一进来就被糊住。
   已在 `backHome()` / `showRoom()` 里复位。

> 这三个都是「看源码看不出、跑起来才暴露」的类型，
> 所以 W-01 / W-09 / W-10 这三条每次都不要跳过。

---

## 11. 媒体链路端到端验收（2026-11-14 已执行）

用真实 Cloudflare Realtime 凭据，在 `wrangler dev` 起来的本地 Worker 上
跑了一次完整的「发布 → SFU → 订阅」：

| 步骤 | 结果 |
|---|---|
| 建房间 | `iceServers` 返回 2 条：STUN + `turn:turn.cloudflare.com:...`（带 username / credential） |
| 发布（canvas 1280×720@30） | SFU 返回 answer，session 建立 |
| 订阅 | `ontrack` 触发，`readyState = live` |
| 媒体统计 | 发送 1280×720 / 4659 帧；接收 1280×720 / 4378 帧 / 30fps |
| ICE | `connected` |

> **排查提示**：如果 `/api/ice` 只返回一条 `stun:`，先别怀疑密钥 ——
> 先确认端口上有没有**旧的 `wrangler dev` 进程**
> （`netstat -ano | findstr 8787`）。旧进程加载的是旧 `.dev.vars`，
> 会静默走 STUN 回落，表现和「密钥没配」一模一样。

---

## 12. 部署校验的两个坑

1. **Cloudflare 会往 `GET /` 注入 Web Analytics beacon**：在生产域名上，
   带浏览器 `Accept: text/html` 的请求会在 `</body>` 前插一段 366 字节的
   `static.cloudflareinsights.com/beacon.min.js` 脚本，正文从 31766B 变成
   32133B。所以「远端页面与本地逐字节一致」只在非 HTML Accept
   （如 `curl` 默认的 `*/*`）下成立，不要把它当成部署出了问题。
2. **静态资源不过 Worker**：`wrangler.toml` 没设 `run_worker_first`（默认
   false），命中静态资源的请求由边缘 Asset Worker 直接返回，不会带上
   `index.ts` 里那套 CORS 头。要让静态资源也走 Worker，得显式设置
   `run_worker_first = true`。

---

## 13. 六项反馈的修复（2026-11-14 第二轮）

| # | 反馈 | 修法 |
|---|---|---|
| 1 | 网页观看端 UI 和 App 差太远 | `public/index.html` 从深色独立风格整体换成 App 的浅色纸面体系：暖米底 / 青瓷点缀 / 胶囊按钮 / 24px 卡片圆角，色值抄 `flutter/lib/theme/tokens.dart`。顺带把说明文字的对比度压深过 WCAG AA（App 的 inkSoft / danger 原色在网页上只有 3.2–3.8:1） |
| 2 | Windows 顶栏没避开最小化 / 最大化 / 关闭 | 房间页 `_TopBar` 右内边距 `+ CitroDesktopShell.windowControlsInset`（118）。与首页 / 资源库的约定一致 |
| 3 | 退出按钮重复 | 删掉底部右侧 logout。它还绕过确认框直接 pop —— 主持人会「无声结束」房间。现在唯一入口是左上返回 → 结束 / 只离开 / 再待一会儿 |
| 4 | Windows 预览框和操作区左右排列 | 宽度 ≥ 900 时 `Row[画面, 320 宽控制栏]`；窄屏保持「画面 + 底部控制条」。两处共用同一个 `_Controls` |
| 5 | Windows 不能指定某个应用共享 | 桌面端开始共享前枚举 `desktopCapturer.getSources()`，弹「屏幕 / 应用窗口」选择器（带 320×180 缩略图），选中项的 id 作为 `deviceId.exact` 传给 `getDisplayMedia`。枚举还顺带填了 flutter_webrtc 的原生源缓存（见 §12） |
| 6 | 没有多人实时语音 | 麦克风与画面解耦，见下 |

### 6 的具体改动（服务端 + 客户端 + 网页端）

**服务端**

- `publish` 权限：`mic` 任何成员可发；`screen` 仍按房间模式判定。判定从
  `member.tracks.length > 0` 改成「**已有一条 screen 轨**」——旧写法里观众先开麦
  就满足了条件，随后能补发画面（提权）。
- `publish_state` 现在广播 track diff（`publisher_joined` / `track_added` /
  `track_removed` / `publisher_left`）。之前只写 DO 不广播，停止共享时观众端
  一直挂着最后一帧。
- 角色提升与 `publisherCount` 只认 `screen` 轨：开麦的人不再被标成「共享者」。

**Flutter**

- `toggleMic` 不再要求 `publishing`；观众也能开麦。
- 开麦走 `SfuClient.publishMic()`（mic-only session）；关麦只把本地音轨
  `enabled = false`。旧实现「unpublish → 重发屏幕」会把视频采集流 stop 掉，
  重发的是一路死轨，观众冻帧。
- `stopSharing` 保留麦克风：unpublish 后若仍在开麦，补发一路 mic-only。
- `remotePublishers` 只列有 `screen` 轨的人，主画面 / 发布者切换条不会被
  「只开麦」的成员占位。
- 麦克风关闭态改用专门的 `micOff` 图标（斜杠麦克风）。之前借 `close` 的
  「×」会跟共享按钮并排，看起来像第二个「退出房间」。

**网页观众端**

- 网页也能发言：页脚「开麦」往同一条 pc 加一路 sendonly 音轨，走
  `POST /publish`（mic-only）→ answer；关麦只切 `track.enabled`。
- 自己的事件（DO 会广播回自己）直接忽略，否则会去订阅自己被拒。
- 只开麦的发布者不建画面格子，挂隐藏 `<audio>` 播放。
- 订阅按 `(sessionId, trackName)` 去重（track_added 与 hello 快照会指向同一路）。
- `mid` / `pending` 在 `setRemoteDescription` **之前**登记，修 ontrack 竞态。
- 自动播放被拦时页脚出现「开启声音」按钮。

### 验证

- Worker：`npm test` 23/23（新增语音权限回归，覆盖提权口子）。
- Flutter：`flutter analyze` 只剩 `test/refresh_rate_test.dart` 既有的红；
  `flutter test test/screen_share_test.dart` 30/30。
- 网页：`wrangler dev` + 浏览器实测落地页 / 房间页（含窄屏换行、宽屏 1280 布局、
  加入失败提示、`[hidden]` 遮罩不复现）。真实双端语音链路仍需真机跑一轮 —— 见 §9。
- Windows 便携版实机（2.8.0 构建）：房间页最大化到 1920 宽确认预览在左、控制栏
  在右，顶栏的复制 / 成员 / 窗口按钮互不重叠；点「开始共享」弹出「选择共享
  内容」，屏幕段列出 `Screen 1 · 整个桌面`，应用窗口段列出 Citro、Realtime |
  TURN 等真实窗口并带缩略图。退出入口只剩左上返回。
- 线上（2026-11-14）：`npx wrangler deploy` 发布版本 `0a6b3aae-9bc3-49d4-b8e8-
  eb3905a93741`。`https://share.mint1017.cn/` 返回的 HTML 与
  `public/index.html` 字节一致（sha256 `8259a1be…`）；`/api/health` 正常，
  `/api/ice` 无房间凭证返回 401 属预期。

---

## 14. 参照 KOOK 重做为「一起看」（2026-11-14 第三轮）

用户反馈「做的乱七八糟的，参照 KOOK 重做，改名一起看，网页要用 logo」。
这一轮是**整体重做**，不是打补丁。

### 14.1 视觉与命名

- 用户可见名称统一改为 **一起看**：入口卡片、资源库快捷工具、首页工具行、
  发起页、房间页、结束文案、网页 `<title>` / 落地页 / 房间页。
  代码目录、Worker、KV / DO 键保持 `screen_share` / `screen-share` 不变。
- 新的暖黑剧场配色（`screen_share_theme.dart`，与 `public/index.html` 同步）：
  底 `#221C19`、舞台 `#17120F`、卡面 `#2C2521`、奶油字 `#FFF6EA`、
  logo 橙 `#E8703A`、在线薄荷 `#8FD3C7`。App 其他页面仍是浅色。
- 网页观看端顶部品牌、落地页 hero、等待态、结束遮罩全部改用
  `assets/images/logo.webp` 同款 logo，不再用字母「C」占位。

### 14.2 布局（对齐 KOOK）

- **发起页**：logo + 「一起看」大字 + 一句话副标题；一张发起卡
  （房间名可留空 → 「发起一起看」），一张房间号加入卡，最近房间 chips。
  模式 / 画质从入口页移走，减少首屏设置项。
- **房间页**（窄屏）：顶栏（返回 / 标题 + 在线人数 + 画质 + 房间码 / 复制邀请），
  大舞台，底部悬浮控制条（一起看 / 麦克风 / 聊天 / 成员 / 设置）。
- **房间页**（≥ 920 宽）：舞台 + 右侧 300 宽信息栏（房间号、复制邀请链接、
  画质、小窗开关、在线成员）。控制条仍在底部，宽屏居中。
- **设置弹层**：画质（仅主持人）、共享内容说明、小窗、复制房间号 / 邀请链接。
- **源选择器**：先选屏幕 / 应用窗口，再选分辨率与帧率，底部橙色
  「开始一起看」；默认选中第一块屏幕。
- **聊天 / 成员**：暖黑弹层；自己的消息靠右、橙色调；成员行显示
  主持人 / 放映中 / 开麦；踢人前二次确认。

### 14.3 顺手修掉的旧问题

| 旧问题 | 处理 |
|---|---|
| 非主持人也看到画质设置，服务端却拒绝 | 画质入口只给主持人；观众只读显示当前档位 |
| 主持人无法切回自己的画面 | 切换条加入「我的画面」（self uid），别人开共享后也能切回 |
| 小窗压住底部控制条 | 初始底距 96 → 108，停在悬浮条上方 |
| 邀请与成员入口重复、复制键不复制 | 顶栏复制键直接复制邀请链接；邀请两个入口收进设置弹层；成员只在底栏 |
| 空状态文案「点下面」在宽屏没有下面的按钮 | 宽屏控制条仍固定在底部；文案改为「点下面的「一起看」」 |
| 聊天自己的消息靠左 | 用 `selfUid` 判断，右对齐 + 橙色气泡 |
| 退出入口重复 / 绕过确认 | 只保留左上返回，走「结束 / 只离开 / 再待一会儿」 |

### 14.4 本轮验收（待执行）

- [ ] `flutter test test/screen_share_test.dart`（30 用例）
- [ ] `flutter test test/web_desktop_test.dart`（工具行改名）
- [ ] `npm test`（Worker，默认标题 / 结束原因文案变更）
- [ ] 网页：`wrangler dev` 打开 `/` 与 `?room=`，核对 logo、暖黑配色、
      成员抽屉、聊天、结束遮罩；390 / 1440 两档宽度无横向滚动
- [ ] Windows 实机：发起页 / 房间页 / 源选择器 / 设置弹层截图核对
- [ ] Android 实机：发起 → 系统授权 → 房间页 → 停止
- [ ] 部署 Worker 后线上 `public/index.html` 与本地字节一致

---

## 15. 第二轮反馈修正（2026-11-14 第四轮）

用户看过房间页后提出 5 点，§14.2 中与本节冲突的布局描述以本节为准：

| # | 反馈 | 处理 |
|---|---|---|
| 1 | 删掉右上角的复制链接按钮 | 顶栏只留返回、标题、状态；复制入口收在右栏「复制邀请链接」和设置弹层里 |
| 2 | 删掉侧栏的一起看设置部分 | 右栏只保留房间号 / 邀请 / 在线成员；画质和小窗仍在齿轮设置弹层里 |
| 3 | 侧栏没有圆角 | 右栏改成留边距的悬浮圆角面板（`radii.card` + 描边） |
| 4 | 选屏幕 / 应用没有预览；画质帧率要下拉框 | 源选择器改成「屏幕 / 应用窗口」分页 + 缩略图网格；分辨率、帧率各一个下拉框 |
| 5 | 文字聊天要能弹幕滚动 | App 舞台加 `danmaku_layer.dart`（新消息从右向左，历史不补播）；网页舞台加同款弹幕层，新消息不再自动掀开聊天侧栏 |

### 15.1 实现要点

- Flutter 选源器：枚举时请求 `thumbnailSize: 320×180`，macOS 会直接带回
  预览；**Windows 的 `getDesktopSources` 返回值里没有 thumbnail**（插件
  的 common/cpp 侧只填 id / name / type），所以 Windows 改为进弹窗后对
  每个源调 `getDesktopSourceThumbnail` 现取一张 JPEG，逐项刷新网格。
  取不到时显示「暂无预览」而不是空白。
- 弹幕层 `IgnorePointer` + `ClipRect`，只在舞台内飘，不挡控制条；
  泳道按舞台高度取 2–6 条，9 秒走完全程，最多保留 24 条。
- 网页弹幕：`#danmakuLayer` 在 `main.stage` 内，`z-index:4`，
  `pointer-events:none`；`--travel` 按实际舞台宽度 + 气泡宽度计算，
  窄屏不会只飘一半。
- 聊天面板仍在，完整记录和发送入口不变；弹幕只是新增的展示方式。

### 15.2 验证

- [x] `flutter analyze lib/screen_share lib/widgets/paper.dart` 无问题
- [x] `flutter test test/screen_share_test.dart` 31/31（新增选源器分页 / 下拉用例）
- [x] 网页（390 宽）：弹幕层在舞台内、三行泳道、1.2s 左移约 78px、
      `pointer-events:none`、`z-index:4`
- [ ] 网页 1440 宽与真实房间聊天复测（需部署后线上）
- [ ] Windows 实机复看：右栏圆角、顶栏无复制键、源选择器预览与下拉
- [ ] Android 实机复看：发起 → 授权 → 弹幕

---

## 16. 第三轮反馈修正（2026-11-14 第五轮）

| # | 反馈 | 处理 |
|---|---|---|
| 1 | 选源器还是没有预览 | 根因：Windows 的 `getDesktopSources` 不返回 thumbnail（common/cpp 的 `thumbnailSize` 是 TODO）。选源器改为对每个源调 `getDesktopSourceThumbnail`，拿到 JPEG 后逐项刷新；单屏时格子铺满一行，预览更大 |
| 2 | 发起页返回按钮要在左上角 | 返回从 480 宽的正文列里拿出来，固定在页面左上角（`side` 边距 + `SafeArea`），正文单独滚动 |
| 3 | 麦克风音量与系统音量可调 | 设置弹层新增两路滑杆；桌面共享改为同时采系统声音（`audio:true` → WASAPI / 应用 loopback），作为 `system` 轨发布；麦克风与系统音量分别作用于两路本地音轨 |

### 16.1 系统声音链路

```
桌面共享 getDisplayMedia(video+audio)
  ├─ video  → track `screen`
  └─ audio  → track `system`（WASAPI loopback / 单窗口应用 loopback）
麦克风 getUserMedia(audio)
  └─ track `mic`
订阅端按 trackName 分开渲染；网页把 screen 塞进 <video>，system / mic
都进发布者的 MediaStream，由同一个 <video> 或隐藏 <audio> 播放。
```

- Worker 的 `/publish` 白名单从 `screen / mic` 扩到 `screen / mic / system`。
- **兼容旧 Worker**：如果 `/publish` 仍回「不支持的 track」，客户端摘掉
  `system` 轨重新协商一次，画面优先。部署新 Worker 后自动带声音。
- 系统声音音量滑杆只在 `hasSystemAudio` 为真时启用；未共享或本次共享
  没有声音时明确置灰并说明原因，不做无效滑杆。
- 拖动时只改本地数值，`onChangeEnd` 才调 `Helper.setVolume`，避免每帧
  过 platform channel。

### 16.2 顺手修掉的问题

| 问题 | 处理 |
|---|---|
| 弹幕监听用 `addPostFrameCallback`，但聊天不会主动排帧 | 改为 `scheduleMicrotask` + `setState`；否则该帧没有别的状态变化时弹幕永远不出现（测试里直接卡死） |
| 橙底按钮图标用 `ink2`（奶油色），对比度 1.9:1 | 选源器 / 发起页的主按钮图标显式用 `onAccent` 深棕 |
| 选源弹窗单屏时只占左半列 | 只有一项时单列铺满，预览格 620×190 左右 |
| 网页撤销 `mic` 会连带删掉同发布者的 `system` 音轨 | 网页按 trackName 记录音轨，`mic` / `system` 各撤各的；只剩一路时仍能继续播放 |

### 16.3 验证

- [x] `flutter analyze lib/screen_share test/screen_share_test.dart` 无问题
- [x] `flutter test test/screen_share_test.dart` 34/34
- [x] `npm run typecheck`、`npm test`（23/23，publish 用例覆盖 `system` 轨）
- [x] 网页内联脚本 `node --check` 通过
- [ ] Windows 实机：选源器缩略图真实出图、发起页左上返回、设置两路滑杆
- [ ] 部署 Worker 后：分享视频时观众能听到系统声音，滑杆生效

---

## 17. 第四轮反馈修正（2026-11-14 第六轮）

| # | 反馈 | 处理 |
|---|---|---|
| 1 | 返回按钮要在整个页面左上角 | 页面顶栏再收紧：左上各 8px，宽屏也不再跟 48px 的正文留白；正文列仍用 `side` 居中，两者互不影响 |
| 2 | Android 刚打开一段时间内怎么滑都被拉回原位 | 根因在 RootShell 页面层：`Positioned.fill` 没有稳定 key。启动后 1.2s / 2.0s / 2.8s 依次预热计划 / 游戏 / 社区页，新页插到首页前面，Flutter 会按位置复用同类型 Element，首页被整棵重建、`ScrollController` 一并重建，offset 归零。给每层加 `ValueKey('citro-page-$i')` 后按 key 搬运。新增 `test/root_shell_scroll_test.dart` 复现：去掉 key 时 300→0，有 key 时保持 300 |
| 3 | Android / iOS 一起看卡片太大 | 窄屏（< 600，Android / iPhone 同一套宽度）统一收紧一档：入口页 logo 96→68、标题 40→32、卡片内边距 20→16、按钮 52→46，品牌区与页尾留白同步压缩；负一屏的「一起看」整行长卡图标 54→44、内边距 24→16、标题 18→16（高 102→76），抽屉高度按 349→323 重新校准。iPad 与桌面保持原样 |

### 17.1 验证

- [x] `flutter test test/screen_share_test.dart` 37/37（新增窄屏品牌区 / 返回位置 / 320 宽不溢出断言）
- [x] `flutter test test/root_shell_scroll_test.dart` 1/1（启动预热不重建首页）
- [x] `flutter test test/home_layout_smoke_test.dart` 10/10
- [ ] Android / iOS 实机复看窄屏入口，并在启动后立刻滑动确认不再回顶
