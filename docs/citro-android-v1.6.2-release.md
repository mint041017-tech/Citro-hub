# Citro Android v1.6.2 发版记录

- 日期：2026-10-23
- 版本：`1.6.2` / versionCode `1602`
- APK：`APK/Citro-v1.6.2-release.apk`（70.7 MB）
- SHA-256：`6C473C6320AEF6BC4BE3E755BE749D5A7E369FE73D35D15924BD7B9B54EDDC41`
- 签名：同 release key，可覆盖升级

## 1. 轻提示统一到上方、去掉重复

- 全局 `AppToast` 从「底部 +110」改为「顶部 safeArea + 88」——站内所有轻提示
  （复制成功、换令字、兑换等）统一显示在屏幕上方。
- 成语接龙 / 飞花令的 `_feedback` 不再同时弹 AppToast：只保留链表区顶部的
  fb 浮层胶囊，消除「上下各一条」的重复。

## 2. 文字游戏键盘适配

- 舞台高度随键盘收缩：`min(506.39, 屏高 - 键盘高 - 240)`（240 = 顶栏 56.7 +
  标题/HUD 约 150 + 边距 36），键盘弹出后整个游戏区（含底部输入行、需接拼音 /
  令字徽章）无需手动滚动即可见；键盘收起时恢复 506.39，不影响原版版式。
- 键盘弹出时「正在玩」条自动隐藏（GameScaffold 读 viewInsets）。

## 3. 极限刹车：全面回退到 web 原版参数（1:1）

v1.6.1 为提高可读性自行调过一批参数，本版按用户「像素级还原」要求逐项回退：

| 项目 | v1.6.1 改动 | v1.6.2（= web） |
| --- | --- | --- |
| 追逐相机 | camY 3.0 / dist 10.8 / fov+18 | camY 2.2-sp·0.5 / dist 8.2-sp·1.4 / fov+sp·22 |
| 刹车相机 | 2.0 / 9.6-sp | 1.55 / 7.6-sp |
| 菜单相机 | R 10.5 / ty 1.9 | R 9.5 / ty 2.4（pitch=atan(0.65/R)） |
| 草地色 | #4E4B3C | #575046 |
| 地平线暖光 | .66/.35/.11 | .92/.48/.16 |
| 夕阳反光带 | .18 / ±W·0.3 | .55/.20/0 + ±W·0.17 |
| 路灯灯杆/灯头 | 0.30 宽 / 1.1 宽 | 0.22 / 0.9 |
| 灯头光晕 / 路面光池 | 上限 15px、只画 130m/120m | rr·4 无上限、420m/340m |
| 护栏梁 | 0.42-1.00 | 0.50-0.82（近处 0.66 分界） |
| 树木剪影 | 新增 | 删除（web 无此元素） |
| 路障可见距离 | 3400m | 1600m |

另：结算卡改为场景内水平+垂直居中（用户上一轮点名要求，保留）。

**1:1 校验**：用无头 Chrome 在 390×844 下重抓 web 版页面，与 native golden
做像素差分（_tmp/brake_ref/cmp_menu.png）：布局、字号、卡片、按钮完全对位，
均差 5.24 / >24 灰阶差异像素 7%（残差为字体栅格化、云/环绕相机的时间相位差、
以及 headless 桌面指针下 web 顶栏显示「返回首页」文字而真机显示圆钮——真机
与 App 一致）。场景渲染器与 web 的 `gbDrawSky / gbDrawGround / gbDrawBarrier /
gbDrawRoadside / gbDrawCar / gbRender` 逐函数对齐。

## 4. 贪吃蛇「正在玩」

恢复 `showLive`（v1.5.8 误关），并新增进度 `ValueNotifier`：`得分 N · 长度 M`，
对局结束显示「得分 N · 已结束」，与 web `gamesLiveHeartbeat('gsnake')` 语义一致。

## 验证

- `dart analyze lib test`：0 error / 0 warning。
- `flutter test --concurrency=1`：13 张 golden 全通过（gsnake 增加 live 条基线）。
- aapt2：versionCode 1602 / versionName 1.6.2。
- 参考帧工具留存：`_tmp/brake_ref/harness.html` + `cmp.py`（对比 web 与
  native 的像素差，后续改场景可直接复用）。
