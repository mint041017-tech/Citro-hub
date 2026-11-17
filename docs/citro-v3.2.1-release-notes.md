# Citro 3.2.1 发版记录

> 版本号：`3.2.1+3201` · 2026-11-18
> 汇总区间：3.2.0 → 3.2.1（体验优化补丁）

## 数独页（手机竖屏）

- 手机竖屏数独页的「新游戏 / 暂停」操作行不再钉在视口底部，改为跟着棋盘一起滚动
  （方案 A）。棋盘、操作行同处一个滚动区，底部只保留「正在玩」和局数提示。
- 仅数独页启用，其余游戏的操作行仍固定在底部；横屏、平板与桌面版式不变。
- `GameScaffold` 新增 `actionsInScroll` 开关，默认关闭，数独显式打开。

## 页面退场动画（Android / Windows / Web）

- 灵敏度、视野 live、玩法抽签、一起看四个页面的返回动画改为完整淡出：
  触屏 150ms、桌面 120ms，`easeInCubic` 收尾，退场时不再缩放。
- 此前全局路由在返回时只淡出约 18% 并轻微位移就被移除，观感是「抖一下消失」；
  现在四个工具页走独立的 `CitroCrispPageRoute`，其余页面保持原有转场。
- iOS / macOS 继续使用系统 Cupertino 转场：它本身就是整页滑出，
  并且只有它会在路由层安装左缘滑动返回手势，不能替换成自定义淡出。
  转场改用 `MaterialPageRoute` 子类，在 iOS / macOS 上回落到系统转场。
- 一起看的内置网页只在合作工具站（`shijiao.xingpaste.com`）启用干净退场，
  普通外链页面不受影响。

## Android 端

- 手机竖屏数独页操作行随内容滚动，小屏不再挤压棋盘高度。
- 仅发 arm64-v8a 包，Impeller 保持开启，Citro 签名与旧版一致，可直接覆盖升级。
- 应用内更新清单 `APK/update.json` 同步到 3.2.1。

## iPad / iOS

- iPad 与横屏版式不变；iOS 保留系统 Cupertino 转场与左缘滑动返回手势。
- iOS 预打包完成：版本号与构建配置已同步到 3.2.1；
  推送 main 后由 TestFlight CI 在 macOS 上签名构建并上传。

## Windows 端

- 桌面端数独页版式不变，操作行仍固定在棋盘下方；四个工具页返回时完整淡出。
- 延续 3.2.0 的一起看修复：Windows 端发布系统声时，Cloudflare 链路只发画面，
  系统声统一由声网发送，避免系统音量被压低。
- 桌面端随 3.2.1 重新打包，安装包更新清单带 SHA-256 校验，静默更新与便携版同时可用。

## Web 端

- Flutter Web 与桌面端同源更新；构建产物预压缩、CanvasKit 本地分发照旧，
  `latest.json` 同步到 3.2.1。
- downloads 静态站更新三端 3.2.1 更新日志，Android 与 Windows 入口指向 3.2.1。

## 下载

- Android APK：`Citro-v3.2.1-release.apk`（arm64-v8a，Citro 签名，应用内更新可用）
- Windows 安装包：`Citro-v3.2.1-win64-setup.exe`（用户级安装，无需管理员，静默更新）
- Web 压缩包：`Citro-web-3.2.1.zip`（部署到站点根，清单 latest.json 已同步）
- downloads 站：`Citro-downloads-3.2.1.zip`（清单 downloads.json 已同步）
- iOS：预打包完成，IPA 由 TestFlight CI 生成，渠道不变

## 校验

| 文件 | SHA-256 |
| --- | --- |
| Citro-v3.2.1-release.apk | `dcfcf4a78aeef42946c5085f60e7858be4d9911e7156b30514a4f8dd4d3b36a3` |
| Citro-v3.2.1-win64-setup.exe | `6b000b745dacc6263ed06f75b09284312ee3b0a38af091d0adf0590cd474e96e` |
| Citro-web-3.2.1.zip | `ee5d5c1efa4b47763c69da87a6a51fdfb9f8ba2302251d2bfdaff46a79994859` |
| Citro-downloads-3.2.1.zip | `c25dc55639671b6246827f489f32b1ddb22dbb7d8a260a88f8ef0a605bd63977` |
