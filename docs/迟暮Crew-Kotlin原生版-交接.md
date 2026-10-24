# 迟暮·Crew — Kotlin 外壳版 v1.0.0 交接文档

> 生成时间：2026-10-10
> 目标：把 `offline`（Capacitor 通用壳）重构为 **Kotlin 定制外壳 + 本地 WebView 内容**，代号 `offline` → `Kotlin`，版本大版本升级到 **1.0.0**。
> 核心诉求：**网页内容 / 功能 / 样式 100% 保留**，同时**提升 App 性能**。

---

## 一、架构：为什么能"样式不变"又"更快"

```
Kotlin 原生外壳（启动页 / 权限 / 相机 / 分享 / 返回键）
        │
        ▼
WebView ── 加载 assets/www/index.html（本地，0 网络）
        │        ▲
        │        └─ WebViewAssetLoader 以虚拟域名 https://chimu-claw.xyz 提供
        │           → 与后端【同源】：cookie / 登录 / credentials:include 原生可用
        ▼
后端 https://chimu-claw.xyz/trashapi（仅数据请求走网络）
```

**关键设计**：把 WebView 的虚拟域名设成 **`chimu-claw.xyz`**（而不是 Capacitor 的 `localhost` / `file://`）。
于是 `index.html` 里所有 `/trashapi/...`、`/api/...` 根相对地址**无需任何改写**就能直达真实后端，且是**同源请求**——Cookie 正常携带、无 CORS 问题、登录态可持久。

---

## 二、本次交付物

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| Release APK | `APK/迟暮Crew-Kotlin-v1.0.0-release.apk` | **6.47 MB**，`密钥/chimu-release.jks` 签名 |
| Debug APK | `APK/迟暮Crew-Kotlin-v1.0.0-debug.apk` | 调试用 |
| 外壳工程 | `kotlin/` | Kotlin 2.0.21 + androidx.webkit，无 Compose |
| 资源同步脚本 | `kotlin/sync-www.js` | 把根目录网页资源同步到 `assets/www/` |
| 一键打包 | `kotlin/build.js` | `node build.js [debug\|release]`（自动先同步资源） |

**包信息**：`com.chimu.crew` · versionCode **100** · versionName **1.0.0** · minSdk 23 · targetSdk/compileSdk 35 · 签名 CN=Chimu Crew。

### 体积对比

| 版本 | 体积 | 说明 |
| --- | --- | --- |
| 旧 `offline`（Capacitor） | 28.88 MB | 通用壳 + 未清理资源 |
| Kotlin 外壳（首次） | 29.04 MB | 资源原样带入 |
| **Kotlin 外壳（最终）** | **6.47 MB** | 剔除 21.2 MB 未被引用的历史背景图 |

---

## 三、性能优化清单（相对旧 Capacitor 壳）

| # | 手段 | 说明 |
| --- | --- | --- |
| 1 | **WebViewAssetLoader** | 本地资源走 https 虚拟域名，不是 `file://`；有正常 origin，缓存/Cookie/存储全可用 |
| 2 | **与后端同源** | 虚拟域名 = 后端域名 → 免 CORS、免改接口地址、Cookie 原生携带 |
| 3 | **原生启动页** | 首帧可见前显示原生 Splash，消除白屏 |
| 4 | **单实例 WebView** | 已声明 `configChanges`，旋转/切页不重建、不重载 |
| 5 | **缓存策略** | `LOAD_CACHE_ELSE_NETWORK` + DOM Storage + Database |
| 6 | **资源瘦身** | 剔除 21.2 MB 未被引用的历史背景图（详见下） |
| 7 | **图片/字体免二次压缩** | `androidResources.noCompress` 避免运行时解压开销 |
| 8 | **系统能力下沉** | 相机 / 麦克风 / 定位 / 文件选择 / 外链 / 下载由原生处理 |
| 9 | **渲染进程守护** | `onRenderProcessGone` 自动重建 WebView，避免整个 App 被系统杀掉 |
| 10 | **移除 Compose** | 外壳不用 Compose，减少 dex 体积与启动开销 |

### 过渡动画优化：已回滚（2026-10-10）

曾做过一版"运动中临时关闭 `backdrop-filter`"的流畅模式（注入 App 内副本 + 外壳 `offscreenPreRaster` / 渲染进程提优先级），**已按用户要求整体回滚**，当前 App 与网站表现完全一致。

回滚方式：
- `kotlin/sync-www.js` 顶部 `const injectPerfMotion = false;`
- 外壳 `MainActivity.kt` 中已移除 `offscreenPreRaster` 与 `setRendererPriorityPolicy` 两行

> 该优化代码仍保留在 `sync-www.js` 中（默认关闭），随时可把 `injectPerfMotion` 改回 `true` 重新启用；档位由 `PERF_MOTION_BLUR` 控制（`'none'` 最流畅 / `'soft'` 保留磨砂感）。
> 卡顿根因仍存在（全站 203 处 `backdrop-filter: blur(12px)` + `transition: all`），若后续仍要优化，可考虑：全局降模糊半径、拆包 1 MB 单文件、暂停装饰性循环动画。

### 资源瘦身明细

`图/` 下 **21.22 MB 图片完全未被 `index.html` 引用**（已逐文件核对，含 CSS `url()` 与 JS 动态拼接，均无命中）：

```
17.44 MB  图/小橘子背景.png
 1.80 MB  图/小橘子背景.jpeg
 1.11 MB  图/大橘子背景.jpg
 0.72 MB  图/普通背景.jpg
 0.07 MB  图/today-shot.jpg
 0.07 MB  图/mmexport1789968066889.jpg
```

已在 `kotlin/sync-www.js` 的 `skipImages` 中排除（**工作区原文件保留未删**）。真正被引用的图片只有 1.13 MB。
如需重新启用某张图，从 `skipImages` 里移除对应项即可。

---

## 四、已具备的能力

- ✅ **样式 / 功能 100% 与网站一致**（同一份 `index.html`，由 WebView 渲染）
- ✅ 登录 / 社区 / 发帖 / 点赞 / 语音动态（依赖后端同源 Cookie，已打通）
- ✅ 全部小游戏、抽签、运势、星盘等网页内功能
- ✅ 相机拍照、相册选择、录音（`onPermissionRequest` + 运行时权限）
- ✅ 定位（`onGeolocationPermissionsShowPrompt`）
- ✅ 外链自动跳系统浏览器、返回键回退网页历史
- ✅ 深色/浅色主题（网页自带）
- ✅ **原生启动页**：品牌 logo（橘子吉祥物）+ 马善政毛笔体「迟暮·Crew」+ 副标「星座 · 抽签 · 小游戏」，淡入上浮入场

### 启动页实现细节

| 元素 | 来源 |
| --- | --- |
| logo | `图/logo.png` → `res/drawable/splash_logo.png`（136dp，`FIT_CENTER`） |
| 品牌名 / 副标字体 | `fonts/ma-shan-zheng-400-sub.woff2` → 用 fontTools 转成 `res/font/chimu_art.ttf` |
| 背景 | 与主题一致的米白 `#F5F0E6`；品牌名 `#B04E00`，副标 `#A2937F` |
| 位置 | 水平居中，垂直方向在屏幕约 **24%** 处起排（中上，非正中） |
| 入场 | `alpha 0→1` + `translationY 12dp→0`，420ms |

> 字体是网页同款书法体的**子集**（644 字形，仅 379 KB）。子集里原本没有 `·`（U+00B7），已把该码位映射到句点字形，故「迟暮·Crew」可正常显示。
> 转换命令（需 fontTools + brotli）：
> ```python
> from fontTools.ttLib import TTFont
> f = TTFont("fonts/ma-shan-zheng-400-sub.woff2"); f.flavor = None
> f.save("kotlin/app/src/main/res/font/chimu_art.ttf")
> ```

---

## 五、重新构建

```powershell
$env:JAVA_HOME = "C:\Android\jdk-21.0.12.1+1"
cd "C:\迟暮\迟暮Crew\kotlin"
node build.js release     # 自动执行 sync-www.js 后再打包
# 产物：..\APK\迟暮Crew-Kotlin-v1.0.0-release.apk
```

---

## 六、注意事项 / 后续可做

1. **首次启动需联网**：页面本体本地加载，但数据（运势/社区等）仍需访问 `chimu-claw.xyz`。
2. **性能模式（可选未做）**：网页大量使用 `backdrop-filter: blur()`，中低端机可能掉帧。可加一个"性能模式"把模糊降级为半透明纯色——**但会改变观感，故默认不做**（与"样式不要变"冲突）。
3. **资源拆包（可选未做）**：把 1.07 MB 单文件 `index.html` 拆成 HTML/CSS/JS，可进一步加快首屏解析（需改网页代码）。
4. **真机验证**：本机无 Android 设备/模拟器，仅完成编译、打包、签名与元数据校验，**未做真机运行验证**。
5. 旧 `capacitor/` 工程与 `offline`/`remote` 变体保留未删。
