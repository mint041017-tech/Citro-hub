# Citro 字体清晰度修复说明（2026-11-01）

## 结论先行

「有些字发虚」的根因不是字号或抗锯齿参数，而是**打包字体只覆盖了旧文案的字**：

- `noto-sc-400-app.otf` / `noto-sc-700-app.otf` 子集只有 **1964 个字符**，而 `flutter/lib`
  当前文案有 **2127 个不同汉字**；
- 缺的 **296 个字**（很 / 因 / 告 / 议 / 导 / 帮 / 环 / 替 / 糖 / 茶 / 桌 / 集 / 均 / 医 …）
  在各端会掉到 fallback 字体：Windows 用微软雅黑、iOS 用苹方、Android 用系统 Noto、
  Web 交给浏览器默认中文字体；
- fallback 字体与 Noto Sans SC 的笔画、字重都不一致，请求 w700 时系统字体还会被
  引擎合成加粗，所以同一行里"有的字实、有的字糊"；
- 旧子集还用 `--no-hinting` 裁掉了 `prep` / `gasp`，小字号缺少指令对齐，进一步显糊。

在渲染验证里可以直观看到：旧字体对「因为很重要」「障碍物与咕噜铺」等文本直接是空白
（`.notdef`），新字体完整成句。

## 这次改了什么

1. **重建字体子集**（`devtools/build-app-fonts.py`）
   - 字符集 = `flutter/lib` 全部 Dart 源码字符 ∪ **GB2312 一级 + 二级**（6763 字）
     ∪ ASCII ∪ 中英文标点；
   - 正文 400 覆盖一级 + 二级；粗体 700 与标题 ZCOOL 覆盖一级 + 项目文案；
   - 源字体换成 @fontsource 的 **Noto Sans SC 静态 woff2**（无 wght 可变轴，不需要合并切片）；
   - **保留 hinting**；
   - 输出统一为真正的 SFNT（`.ttf`），并断言文件头不是 `wOF2`
     —— woff2 容器 Flutter 引擎无法加载，会把整行渲染成 `.notdef` 方块。
2. **字体文件改名 `.otf` → `.ttf`**，同步 `pubspec.yaml`、`test/**`、`tool/make_installer_art.py`。
3. **顺带修掉暴露出来的布局溢出**：`tingyu_page.dart` 顶栏品牌 `Row` 在补字后变宽，
   390 宽手机上挤出 17px；已给文本列加 `Flexible` + 单行 ellipsis 兜底。

## 覆盖率

| 字体 | 字符集目标 | 实际 cmap | 缺失 |
| --- | --- | --- | --- |
| NotoSC 400 | 7031 | 5883 | GB2312 二级生僻字 1042 + 一级 4（耪锨谰毖） |
| NotoSC 700 | 4142 | 4035 | 符号类 107 |
| ZCOOL | 4142 | 4029 | 符号类 113 |

**项目文案 2222 个汉字只缺 5 个诗用生僻字**（朓 浥 窅 葸 龥），其余全部由打包字体渲染。

## 体积

| 文件 | 旧 | 新 |
| --- | --- | --- |
| noto-sc-400-app | 392 KB (otf) | 1757 KB (ttf) |
| noto-sc-700-app | 396 KB (otf) | 1157 KB (ttf) |
| zcool-app | 362 KB | 768 KB |

字体总量 1.15 MB → 3.68 MB（四端安装包 +2.5 MB 左右）。如果 Web 首屏体积敏感，可以把
`build-app-fonts.py` 里 400 的字符集从「一级 + 二级」收回到「一级」，体积约 1.15 MB。

## 重建方式

```powershell
python devtools\build-app-fonts.py            # 重建 400 / 700 / ZCOOL
python devtools\build-app-fonts.py --check    # 只核对覆盖率
python devtools\font_coverage_check.py        # 项目文案逐一核对
```

切片与静态源字体会缓存在 `devtools/.fontcache/`（已加入 `.gitignore`）。

## 注意事项

- `flutter/test/preview/**` 与 `test/duo_*_preview.dart` 的 golden 基线基于旧字体，
  字体变更后会失配；等当前视觉改动定稿后统一执行
  `flutter test --update-goldens test/preview test/duo_cook_preview.dart …` 刷新一次即可。
- 新增字体文件是 TTF，不要再改回 `--no-hinting` 或 woff2 输出，否则小字清晰度会退回去。
- 已核对 `runner.exe.manifest` 为 `PerMonitorV2`，Windows 高 DPI 不是这次的诱因。