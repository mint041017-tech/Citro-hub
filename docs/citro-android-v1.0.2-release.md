# Citro Android APK · v1.0.2 更新说明（2026-10-19）

> ⚠️ 后续：v1.0.2 在部分机型上仍只显示 logo、启动动画不出现。
> 根因与修复见 **v1.0.3**：`docs/citro-android-v1.0.3-release.md`
> （改用 TextureView + MediaPlayer、启动视频转码为 H.264 Baseline/720p、Android 12+ 等系统启动页退场再起播）。

> v1.0.1 的安装包在部分机型上「开屏动画不显示」：Android 12+ 的系统启动画面会盖在
> 应用窗口上，如果 `onCreate` 里立刻播放，冷启动较慢的机器会把 3s 视频在系统启动页背后
> 播完，用户一进来只剩首页。**v1.0.2 修复了这个问题**，并保留 v1.0.1 的其他更新。

## 1. 本次更新内容

| 项 | 说明 |
| --- | --- |
| 版本 | `versionName 1.0.2` / `versionCode 1002`（可直接覆盖 v1.0.1 升级，签名相同） |
| 应用名 | **Citro**（`strings.xml` 的 `app_name`；APK 实测 `application-label: Citro`） |
| 图标 | 新 logo（`素材/citro-logo.png` 透明字标 + 方图背景），全密度 + Android 8+ 自适应图标 |
| 启动动画（修复） | 竖屏 `res/raw/splash_portrait.mp4`（1080×1920、3.04s）。**等窗口获得焦点后才 `start()`**，避开 Android 12+ 系统启动页遮挡；静态字标先铺第一帧（带淡入上浮），视频真正开始后再淡出；视频播完 + 页面首帧 + **至少展示 2.4s** 才淡出；视频解码失败回退静态字标；6.5s 总兜底；`onDestroy` 停止播放 |
| 调试日志 | 启动动画相关日志 tag `CitroSplash`：`adb logcat -s CitroSplash` 可看到 prepared/start/complete/error/dismiss 全过程 |
| 网页资源 | 最新站点（毛玻璃、弹窗主题色、「我的」页玻璃等）已同步进 `assets/www`，App 内删「下载 App」入口 |
| 网站下载入口 | `index.html` 两处 APK 链接：`/APK/Citro-v1.0.2-release.apk`，文案 `Android · v1.0.2 · 14.7MB` |
| 签名 | 与 v1.0.1 **同一把新密钥**（`CN=Citro`，SHA-256 `22c7da41…ad1e6aa`），v1.0.1 可直接覆盖升级 |

## 2. 产物

| 文件 | 说明 |
| --- | --- |
| **`APK/Citro-v1.0.2-release.apk`** | **正式发布包**，15,393,234 字节（14.68 MiB），新密钥签名 |
| `kotlin/app/build/outputs/apk/stable/release/app-stable-release.apk` | Gradle 原始签名产物 |

- APK SHA-256：`272529168EBDFABDB1460C610DA460C93A46CA041763398AC55C9BCEC865BEDA`
- 证书：`CN=Citro, OU=Mobile, O=Citro, L=Beijing, ST=Beijing, C=CN`
  SHA-256：`22:C7:DA:41:89:F6:46:33:2A:5A:AF:ED:53:6C:FB:85:EA:C6:B2:4F:C0:22:EC:7E:69:67:56:37:9A:D1:E6:AA`

## 3. 签名与密钥（重要）

旧正式密钥（CN=Chimu Crew）已丢失，按用户确认从 v1.0.1 起使用新密钥：

| 项 | 值 |
| --- | --- |
| keystore | `密钥/citro-release.jks`（PKCS12，alias `citro-release`） |
| 密码 | 见 `密钥/签名说明.txt`（本地文件，已 gitignore） |
| 构建配置 | `capacitor/android/keystore.properties`（已 gitignore） |
| `.gitignore` | 已忽略 `密钥/`、`*.jks`、`*.keystore` |

⚠️ 已安装旧版（v1.9 / v1.0.0）的用户无法覆盖升级，需**卸载重装**；
v1.0.1 与 v1.0.2 签名相同，可直接覆盖升级。
⚠️ **请把 `密钥/` 目录和 `keystore.properties` 离线备份**；再丢一次只能再次换代。
> 2026-10-19 构建时发现 `密钥/` 被误移动到 `APK/密钥/`，已在 `build.gradle.kts` 加兜底查找路径
> （`../密钥/` → `../APK/密钥/`），并把目录移回 `密钥/`。

## 4. 验证记录

- `aapt2 dump badging`：`package name=com.chimu.crew versionCode=1002 versionName=1.0.2`，`application-label:Citro`；
- `apksigner verify --print-certs`：签名有效，证书 = 上面的 `CN=Citro`（与 v1.0.1 同一个）；
- APK 内 `res/` 的 `splash_portrait.mp4` SHA-256 与 `素材/启动动画（竖屏）.mp4` 一致
  （`900D4AB9…92F3FB`，5,235,936 字节）；
- APK 内 `assets/www/index.html` 与 `kotlin/app/src/main/assets/www/index.html` 一致；
- `node build.js release stable` 退出码 0，根目录 HTML 未被构建过程改动；
- **仍无真机/模拟器可用（本机 adb 不可用、SDK 未装 emulator）**，请安装后按下面方式确认。

## 5. 真机确认清单

1. 覆盖安装 v1.0.2（若之前装过 debug 测试包，需先卸载，签名不同）；
2. 冷启动 App：应先看到 Citro 字标，然后竖屏启动动画完整播放，再进首页；
3. 如果仍然看不到动画，连电脑执行：
   ```powershell
   adb logcat -s CitroSplash
   ```
   把输出发我（能看到 prepared / start / complete / error 卡在哪一步）；
4. 同时告诉我手机型号 + Android 版本，我可以按机型再兜底（例如换解码路径/降级视频规格）。

## 6. 打包方式（不变）

```powershell
cd kotlin
node build.js release stable
```

手动给未签名包签名（备用）：`devtools/sign-citro-apk.ps1`。
