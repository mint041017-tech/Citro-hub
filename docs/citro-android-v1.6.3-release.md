# Citro Android v1.6.3 发版记录

- 日期：2026-10-23
- 版本：`1.6.3` / versionCode `1603`
- APK：`APK/Citro-v1.6.3-release.apk`（70.8 MB）
- SHA-256：`5A3831E0327ECE823C31A9DA5C1033D11D68246015BF894744FB9791767FABDE`
- 签名：同 release key，可覆盖升级

## 1. 极限刹车：改按原始版 shache.org 复刻

之前的实现基于站内 web 版（浅色纸张风 + 2.5D 假透视）。本次直接以 **https://shache.org/**
（three.js r186 原始版）为基准：

**从原版 bundle 中提取到的硬参数**（`_tmp/shache/` 保留反编译产物与参考截图）：

- 配置：`car{maxSpeedKmh:260, launchAccel:7.4, accelFalloffExp:1.55, wheelRadius:.4}`、
  `brake{minSpeedKmh:100, breakForceN:1612, rampBase:200, rampGrowth:400,
  releaseRate:900, decelPerNewton:10.8/1612, rollingDecel:.15, dragCoeff:22e-5,
  stopSpeed:.08}`、`track{barrierDistance:2600, roadWidth:14, laneWidth:3.6}`、
  `crash{slowMoScale:.28, slowMoSeconds:1.6, resultDelaySeconds:5.5}`、
  `score = round(v0² / t)`。
- 相机：`PerspectiveCamera(42, aspect, .1, 12000)`，竖屏 fov 58；
  `camera.position = anchor + offset`，`lookAt(anchor + lookOffset)`：
  showcase offset(R 9.5/7.8, y 2.4/1.5) look(0,-1.6/0.85,0)；
  chase offset(1.6-1.2e, 2.2-.5e, 8.2-1.4e) **look(0,1,-6)**；
  brake offset(2, 1.55, 7.6-e) look(.3,.9,-4)；crash(9,4.5,13)；
  finish(R 8.5/6.8, y1.4) look(0,.8,0)；平滑 `1-exp(-dt·rate)`，rate 2/2.5/1.8/2.2/1.6。
- 光照/大气：FogExp2(0xB07766, 0.00038)；Hemisphere(#FFD2B0, #2A2430, .55)；
  Directional(#FFB27A, 3.2) 沿太阳方向（球坐标 87.5°/215°）；天空 shader
  天顶 #1D2140 / 中层 #7A4A63 / 地平线 #F09060×1.15 / 地表 #2A1D22 / 太阳 #FFA055。
- 场景：路面 14m 宽（贴图 #2A2A2D）、路缘石 ±7.2（0.4×0.14）、护栏梁
  ±8.1（0.06×0.32 @y.66）+ 4m 立柱、路灯 ±9.2（45m 间隔、臂 2.4、灯头 .9 @y8.85、
  自发光 #FFC28A）、指路牌 4×2 @±10.2 y4.2（1500/1000/500 绿、300/200/100 黄、
  80m 蓝）、路障 7×水马(1.9×1×.7)@2600 + 9×2.2 红板 + 4 颗呼吸警示灯、
  两圈山裙（2600/260、2200/170）。

**渲染器改造**：

- 相机由「俯仰角近似」改为**真正的 lookAt 三维相机**（forward/right/up 基 +
  锚点跟随），追尾视线朝前 6m —— 这是与旧版构图差异最大的地方：车尾压在画面
  左下、长路面向前延伸，与原版一致。
- 新增**近平面多边形裁剪**（Sutherland–Hodgman）：地面等超大四边形不再因角点
  落到相机后方而整面丢失；路面/标线改为 24m 近段细分 + 折线描边，保证透视下
  不丢面。
- 地面改为屏幕空间渐变铺满（原版地面是一整块纯色贴图，无结构）。
- 天空按原版 shader 的实测输出色重建（含地平线以下 uGround 的过渡），
  太阳按原版方向投影并带 glow + 亮核。
- 光照方向换成原版太阳方向；车漆按原版黑金 + 红尾灯。

**界面同步改为原版暗玻璃风**：面板 `#100c0e` 89% + 金色描边、标题与 HUD 数值
`#F1DCAE`、主按钮 `#F6E5BF→#C9A86C` 渐变、速度表金/绿、踏板红脉冲。

**尚未 1:1 的部分（如实说明）**：原版车模是 ~200 个圆角盒/挤出体拼的精细 SUV
（带镀铬窗框、真皮缝线、轮毂辐条、PBR 反射与实时阴影、Bloom 后期），Flutter
侧的 Canvas 渲染器仍是「低多边形近似车 + 无阴影/无反射」，这部分需要引入真正的
三维管线（如 flutter_gl / 自写光栅器）才能逐像素对齐；本轮已把相机、配色、光照
方向、赛道构件与 HUD 全部对齐到原版参数。

## 2. 成语接龙 / 飞花令 AI 判定提示

根因：`_verifyAndAccept` 里 `_feedback(...)` 之后紧跟 `setState(() => fb = '')`，
提示在同一帧被清空，看起来「没有 toast」；成功时也从未提示。

- 失败：`AI 判定：「xx」不是成语` / `AI 判定：这不是含「x」的真实诗句`。
- 成功：`AI 判定：「xx」通过 ✓`（随后正常接龙/对句）。
- `_feedback` 改为 2.2s 自动消失的 toast 行为（定时器在 dispose 清理）。

## 验证

- `dart analyze lib test`：0 error / 0 warning。
- `flutter test --concurrency=1`：13 张 golden 通过（刹车基线随新场景/暗色面板重建）。
- 原版参考工具：`_tmp/shache/shot.js`（CDP 抓帧）、`_tmp/brake_ref/cmp.py`（像素差分）。
- aapt2：versionCode 1603 / versionName 1.6.3。
