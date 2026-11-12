# Citro 打包规范

> 适用范围：Android / Windows / Web / iOS 的发版打包。
> 最后更新：2026-11-09（v2.1.1）
> 本文件与 `flutter/build.js`、`flutter/android/app/build.gradle.kts`、`flutter/android/app/src/main/AndroidManifest.xml` 同步维护；改规则必须一起改代码与本文件。

---

## 0. 一句话

**Android release 只打 `arm64-v8a`，并且必须启用 Impeller。**

---

## 1. Android 硬性规则

### 1.1 只打 arm64

自 **v2.1.1（versionCode 2101）** 起，Android 正式包只包含 `arm64-v8a`：

| 环节 | 做法 |
|---|---|
| 打包命令 | `flutter/build.js release` 固定追加 `--target-platform android-arm64` |
| Gradle 兜底 | `android/app/build.gradle.kts` 在 `target-platform=android-arm64` 时用 `packaging.jniLibs.excludes` 排除 `lib/armeabi-v7a/**`、`lib/x86_64/**` |
| debug / 模拟器 | 不传 `--target-platform`，仍保留多 ABI，不影响本地调试 |
| 为什么 | 目标机型均为 arm64；v7a 已无真实用户，x86_64 只用于模拟器。插件 AAR（MLKit、dartjni 等）会把其他 ABI 的 `.so` 带进来，必须在 Gradle 层排除 |

**发布前必须校验：**

```powershell
aapt dump badging APK\Citro-v<version>-release.apk | findstr "native-code"
# 期望：native-code: 'arm64-v8a'（且只有这一项）

7z l APK\Citro-v<version>-release.apk | findstr "lib\"
# 期望：lib\ 下只有 lib\arm64-v8a\
```

禁止为了"兼容老设备"私自加回 `armeabi-v7a` / `x86_64`。确需多 ABI 时，必须作为单独变体发布，并在本规范与发版记录中写明原因。

### 1.2 启用 Impeller

Android 正式包必须保持 Impeller：

```xml
<meta-data
    android:name="io.flutter.embedding.android.EnableImpeller"
    android:value="true" />
```

- Manifest 中**只能有一条** `EnableImpeller` 声明，禁止再出现 `false` 的重复项（重复声明会导致合并结果不可预期）。
- 禁止用 `--no-enable-impeller`、Skia 作为默认渲染后端。
- 仅当确认某机型在 Impeller 下黑屏/崩溃时，才允许出临时 Skia 兜底包；必须在发版记录中注明机型与原因，并尽快回归 Impeller。

**发布前必须校验：**

```powershell
aapt dump xmltree APK\Citro-v<version>-release.apk AndroidManifest.xml | findstr "EnableImpeller"
# 期望：android:value = true（0xffffffff）
```

> 背景：本 ROM（HyperOS 4 移植包）存在 `persist.sys.force_sw_gles=1`，只影响 GLES；Impeller 走 Vulkan，可绕开软件 GLES。

---

## 2. 版本与产物

1. **版本号**写在 `flutter/pubspec.yaml`：`version: x.y.z+code`，`code = major*1000 + minor*100 + patch`（例：2.1.1 → 2101）。
2. **更新说明**写在 `flutter/update_notes.txt`，每行一条，`build.js` 会写进 `APK/update.json`。
3. 产物固定为：
   - `APK/Citro-v<version>-release.apk`
   - `APK/update.json`
4. 签名依赖 `flutter/android/app/key.properties` 与本地 `密钥/citro-release.jks`；两者**绝不入库**。缺失时 `build.js` 拒绝 release 构建。
5. 打包完成后用 `apksigner verify --print-certs` 确认签名 DN 为 `CN=Citro`。

---

## 3. 打包流程

```powershell
cd flutter
node build.js release
```

`build.js` 会依次完成：读版本号 → 校验签名配置 → `flutter build apk --release --target-platform android-arm64` → 复制 APK 到 `APK/` → 生成 `APK/update.json`。

可选校验（建议每次都做）：

```powershell
$apk = "..\APK\Citro-v2.1.1-release.apk"
aapt dump badging $apk | findstr "package:"
# versionCode / versionName 与 pubspec 一致
aapt dump badging $apk | findstr "native-code"
# 只有 arm64-v8a
aapt dump xmltree $apk AndroidManifest.xml | findstr "EnableImpeller"
# true
```

---

## 4. 上传约定

1. **先传 APK，再传 `update.json`**，避免用户在这一分钟内读到"新清单 + 旧/缺失 APK"。
2. 两个文件都放 OBS 的 `APK/` 目录：
   - `https://obs.chimu-claw.xyz/APK/Citro-v<version>-release.apk`
   - `https://obs.chimu-claw.xyz/APK/update.json`
3. 上传后校验：
   - APK 的 `Content-Length` 与本地字节数一致；
   - `ETag`（单次 PUT 即 MD5）与本地 MD5 一致；
   - `update.json` GET 返回新 `version` / `versionCode`。
4. 上传使用维护者账号，AK/SK 只在本机临时使用，不写入仓库、不写进脚本。桶 ACL 应保持“公共读、仅账号可写”；若发版时临时开启过匿名写入，上传完成后立即收回，防止安装包被替换。
5. 旧版本 APK 可保留也可清理；`update.json` 只指向最新版本。

---

## 5. 其他平台

- **Windows**：`node tool/build_windows.js`，产物在 `WIN/` 与 `exe/`，不影响 Android 规则。
- **Web**：`bash tool/build_web.sh`，产物 `build/web/`。
- **iOS**：必须在 macOS + Xcode 上按 `docs/ios-预打包清单.md` 构建；Impeller / ABI 规则仅适用于 Android。

---

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-11-09 | v2.1.1 | 新增本规范；Android release 固定 arm64 单 ABI；恢复并锁定 Impeller |