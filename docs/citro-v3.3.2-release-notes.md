# Citro 3.3.2 发版记录（Web）

> 版本号：`3.3.2+3302` · 2026-11-23
> 汇总区间：3.3.1 → 3.3.2 · 本轮为 Web 端专项，Android / Windows 产物另行打包

## Web 横屏沿用 Windows 桌面版

- 浏览器窗口横向（宽 > 高，宽 ≥ 900、短边 ≥ 600）时进入与 Windows / iPad 横屏同一套桌面壳：
  208pt 左侧栏 + 分栏首页（左栏背景、右栏卡片）。
- 计划页改为 Windows 排版：待办与记账并排同高；社区保持双列信息流；「我的」改用浮窗。
- 网页端侧栏不再出现「资源库」（Web 产物的 mods 已移除，避免空页与路由错配）。
- 竖屏宽窗口仍用原 `WebHomePage`，手机横屏仍是移动壳。

## 字体

- `RoundedCN` 去掉 500 字重，只保留 400 / 700：字体文件从 6.88 MB 降到 4.56 MB。
- `index.html` 为 400 / 700 增加 `preload`，字体与主包并行下载，不再等 `FontManifest` 返回。
- `nook.ttf` 仍为运行时 `FontLoader` 加载，`NookUI` 子集留在 FontManifest 供听隅/番茄钟兜底。

## 首屏与包体

| 指标 | 3.3.1 | 3.3.2 |
| --- | --- | --- |
| Web 产物 | 66.9 MB | 62.7 MB |
| `Citro-web-*.zip` | 46.9 MiB（49,154,056 B） | **43.7 MiB（45,807,460 B）** |
| `main.dart.js` | 6.04 MB（gz 1.74） | 5.54 MB（gz 1.59） |
| 首帧前下载（gzip） | ≈8.2 MB | ≈5.6 MB |

- 非首屏页面（食谱、日历、待办、专注、记账、MBTI、听隅、搜索、播放、签到卷）改为 deferred，
  首页卡片的直达入口同步走 `CitroLazyPage`；deferred 分片 1.51 MB / 60 个。
- 移除 Dart 侧零引用的 `splash_image.jpg` / `splash_landscape.jpg`（−0.78 MB）。
- `tool/build_web.sh` 增加可选 brotli（`WEB_BROTLI=1`），默认关；需线上 nginx 有 `ngx_brotli`。

## 产物

| 平台 | 文件 |
| --- | --- |
| Web | `web/Citro-web-3.3.2.zip`、`web/latest.json` |
| 说明 | `docs/perf-web-首屏-20261123.md`（本轮改造明细与复核项） |

## 校验

| 文件 | 字节 | SHA-256 |
| --- | --- | --- |
| Citro-web-3.3.2.zip | 45,807,460 | `14c84fa55c0b48be375b03d99f71173fbb1daf9c3620c79678a8286f6845b027` |

- `flutter analyze lib`：0 error / 0 warning。
- `flutter build web --release --no-web-resources-cdn` 与 `tool/build_web.sh` 均通过。
- `test/windows_layout_test.dart`、`test/home_layout_smoke_test.dart` 全通过。

## 部署注意

- 用整包覆盖站点根（保留服务端 `/trashapi`、`/api` 反代与 `gzip_static`）。
- `latest.json` 随包上传 OBS，`url` 指向 `https://obs.chimu-claw.xyz/web/Citro-web-3.3.2.zip`。
- 首次打开 deferred 页面会多一次分片下载，属预期行为；发布后清一次 CDN 缓存更稳。
