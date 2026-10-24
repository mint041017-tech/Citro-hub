# Citro Android v1.7.8 发版记录

- 日期：2026-10-24
- 版本：`1.7.8` / versionCode `1708`
- APK：`APK/Citro-v1.7.8-release.apk`（72.8 MB / 76,380,398 bytes）
- SHA-256：`EB6B2153AD714F6CADE047EE8E935D79FAF543C5DDB8794E1B72469E7595F186`

## 我的冰箱

- 添加食材的圆形悬浮按钮从距底部 92 下移到 78，整体下移 14，离底部导航更近。

## 社区收件箱

- 顶栏收件箱胶囊加长并显示「收件箱」文字（📬 收件箱 + 未读数角标），左右内边距同步调整。
- 点开收件箱即视为已读：打开时调用已读接口，清空顶栏红点与 App 全局未读数，
  同时把列表项的高亮去掉。
- 移除收件箱内的「全部已读」按钮和头部未读角标，避免重复操作。

## 验证

- `flutter analyze lib`：0 error / 0 warning。
- APK：`unzip -t` 通过；`aapt2 dump badging` 显示 versionCode `1708` / versionName `1.7.8`；
  签名 `CN=Citro`，与 v1.1.1 相同，可直接覆盖升级。
- AOT 产物确认启动页为 `v1.7.8`，AI 密钥已打入。
- 按用户要求，未启动模拟器验证界面。
