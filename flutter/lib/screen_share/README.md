# screen_share（一起看）

Citro 的「一起看」模块。共享端在 Flutter 里（采集 + 发布）；观众端可以在网页里，
也可以留在 App 里。语音（开麦）在两端都支持，且和「是否在放映画面」无关。

> 2026-11-14 起，用户可见名称统一为 **一起看**；代码目录 / Worker 名 /
> 数据库键仍叫 `screen_share` / `screen-share`，不要跟着改，否则会丢历史
> 房间和已部署资源。视觉是暖黑剧场（`screen_share_theme.dart`），App 其余
> 页面保持浅色。

## 平台分工

| 平台 | 入口 | 说明 |
| --- | --- | --- |
| Android / iOS / Windows / macOS / Linux | `share_entry_native.dart` | 完整能力：共享自己的屏幕，或作为观众观看 |
| Web | `share_entry_web.dart` | 只跳转 `https://share.mint1017.cn/`，因为 `flutter_webrtc` 1.6.3 的 pubspec 没有声明 web 平台 |

邀请链接统一是 `https://share.mint1017.cn/?room=<6 位房间码>`，两端都从这个格式里取 `room`。

## 架构

信令和房间状态在 Cloudflare Worker + Durable Object 上（见 `../../screen-share/`，
其中 `docs/` 下有方案 / 测试计划 / 运维手册）。媒体不过 Worker，走 Cloudflare Realtime SFU：

```
Flutter 共享端 ──采集──> RTCPeerConnection ──publish──> SFU ──subscribe──> 观众
     │                                                                  │
     └──────────── WS（聊天 / 成员 / 上下线 / 画质）──────────────────────┘
                              Room Durable Object
```

- `sfu_client.dart` — 媒体引擎：一个房间成员一个 `SfuClient`，对应 Worker 侧一个 SFU session（发布 / 订阅 / renegotiate）
- `room_api.dart` — 房间 REST：创建 / 加入 / 结束
- `room_ws.dart` — 房间 WS 事件通道，断线指数退避重连（1s→2s→4s→8s，上限 30s）
- `screen_share_controller.dart` — 把 REST / WS / SFU 三条链路收成一个 `ChangeNotifier` 状态机
- `screen_capture.dart` — 平台相关的采集封装；调用顺序有硬性要求（Android 14+ 尤其严格）。

### 语音与画面的关系

- 同一条 `RTCPeerConnection` 既发布也订阅。开麦就是给它加一路 `mic` 音轨，
  **不要求**正在共享画面（观众之间也能连麦）。
- 关麦只把本地音轨 `enabled = false`，不重建 SDP、不 `stop()` 视频轨。
- 停止共享时如果麦克风还开着，`stopSharing()` 会补发一路 mic-only，声音不断。
- 桌面端共享画面时同时请求系统声音（`getDisplayMedia` 的 `audio: true`）。
  Windows 走 WASAPI loopback（整屏）或应用级 loopback（单个窗口），作为
  `system` 轨发布；观众按 trackName 区分 `screen` / `system` / `mic`。
  旧版 Worker 不认 `system` 时客户端会摘掉音轨重发一次，画面不受影响。
- 桌面端开始共享前先 `desktopCapturer.getSources()` 选源（整屏 / 单个窗口），
  源 id 同时用于填 flutter_webrtc 的原生缓存，否则 Windows 上会
  `source not found!`（见测试计划 §12）。Windows 的枚举结果不带缩略图，
  选择器用 `getDesktopSourceThumbnail` 按 id 逐项补预览。
- 设置弹层有两路滑杆：`mic` 音量（朋友听到的你）和 `system` 音量（共享
  内容里的声音）。拖动只改本地数值，松手才落到底层音轨，避免拖动发涩。

## 画质档位

| 档位 | 分辨率 | 帧率 | 目标码率 |
| --- | --- | --- | --- |
| 720p · 30fps | 1280×720 | 30 | 2.5 Mbps |
| 720p · 60fps | 1280×720 | 60 | 4 Mbps |
| 1080p · 30fps | 1920×1080 | 30 | 4 Mbps |
| 1080p · 60fps | 1920×1080 | 60 | 6.4 Mbps |
| 2K · 30fps | 2560×1440 | 30 | 8 Mbps |
| 2K · 60fps | 2560×1440 | 60 | 12.8 Mbps |

见 `share_quality.dart`；非法输入回落到 720p30。

## Widgets

- `screen_share_page.dart` — 入口页（发起 / 加入）。返回固定在安全区左上角，
  不跟 480 宽的正文列走；窄屏（< 600，Android / iPhone）整页收紧一档，
  iPad 与桌面保留原来的留白。
- `screen_share_theme.dart` — 暖黑剧场配色 + 弹层用的主题包装
- `share_quality_picker.dart` — 设置弹层里的画质选择
- `share_source_picker.dart` — 桌面端「整屏 / 应用窗口」选择器：缩略图预览 +
  画质 / 帧率两个下拉框
- `members_panel.dart` — 在线成员（踢人前二次确认）
- `chat_panel.dart` — 文字聊天
- `danmaku_layer.dart` — 舞台弹幕：新聊天从右向左飘过，历史记录不补播
- `mini_window.dart` — 应用内小窗（非系统 PiP）
- `remote_view.dart` — 远端视频渲染

邀请（房间号 / 链接）在房间页右栏的「复制邀请链接」和「一起看设置」里；
顶栏不再重复放复制键。旧的 `invite_sheet.dart` 已删除。
