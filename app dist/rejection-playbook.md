# Citro 高概率拒审项与处理

> 先按拒审信原文对应 Guideline，不要只改文案；能补证据的补证据（录屏、截图、接口日志、演示账号）。

## 逐项处理

| Guideline / 场景 | Citro 可能触发点 | 处理 |
| --- | --- | --- |
| 2.1 App Completeness | 后端未部署、演示账号失效、AI/天气白屏、iPad 布局溢出 | 部署 `trash.js`；用演示账号在 iPhone/iPad 全流程走一遍；补错误降级；审核期间保持在线 |
| 1.2 User-Generated Content | 社区图文/语音/匿名发帖；当前代码可见举报/拉黑，但未看到发布前敏感词过滤 | 每条内容举报入口可见；拉黑可用；**补发布前敏感词/违规内容过滤或先审后发**；运营者能及时处理举报；提供联系渠道；清理违规测试内容 |
| 5.1.1 Account Deletion | 注销 404、只能网页/邮件注销、注销后数据未删 | App 内「我的 → 注销账号」可用；用一次性账号实测；隐私政策写明删除范围；后端日志留证 |
| 5.1.1 Privacy | App 隐私标签与真实收集不一致；隐私政策打不开；AI 数据未披露 | 按 `app-privacy.md` 填；三个 URL 200；隐私政策补 AI 图片/卡面/抽签/好事记录；权限文案与用途一致 |
| 2.3 Accurate Metadata | 截图含未提供功能、含 Beta/TestFlight/QA、描述夸大 | 重拍截图；删除 beta/测试字样；描述只写现有功能；演示数据干净 |
| 2.3.1 Hidden Features | 资源库藏有 PC 工具/驱动/Mod 下载，审核员认为与 App 功能不符 | 在审核备注解释；更稳妥是 iOS 隐藏资源库入口，或至少把入口放在「我的 → 关于」并加说明 |
| 4.2 Minimum Functionality | 被当成“网页壳”或“下载目录” | 强调原生手账、游戏、社区、食谱、AI；提供完整演示路径；资源库不是主功能 |
| 4.7 Mini Apps / HTML5 Games | 极限刹车、liquid2048 是内嵌 WebView 游戏 | 说明游戏资源随包内置/本地加载、无外部商店、无绕过分发；内容适龄；不提供第三方小程序商店 |
| 3.1.1 In-App Purchase | 以后若加会员/付费卡面/付费抽卡 | 数字内容必须走 IAP；不要外链支付；当前免费无 IAP，备注写明 |
| 4.8 Sign in with Apple | 当前只有手机号登录 | 不适用；如果以后加微信/QQ 等第三方登录，需评估 Sign in with Apple |
| 5.1.2 Data Use and Sharing | AI 把用户文字/图片发给第三方模型；UGC 数据用于审核 | 隐私政策披露；App 隐私标签申报；不把数据用于广告/追踪；AI 仅娱乐 |
| 5.2.3 Third-Party Content | 游戏 Mod、PC 工具、第三方游戏素材版权 | 确认授权/开源许可；无法证明的下架或隐藏；Content Rights 如实填 |
| 2.5.2 / WebView | 用 WebView 加载外部页面；可能被要求使用 Safari | 固定域名/白名单；外部链接交系统 Safari；资源库不作为核心体验 |
| 2.1 演示账号 | 邀请码导致审核员无法注册 | 预创建演示账号；备注写清无需注册；提供一次性注销测试账号 |
| 5.1.1 数据最小化 | 定位权限文案说“城市天气”，实际请求经纬度 | 保持低精度；隐私政策写“大致位置”；如改高精度，更新标签与文案 |
| 2.3 名称/商标 | `Citro` 与汽车品牌接近，或名称被占用 | 提前查重；准备备选名；被拒时改展示名，不改 Bundle ID |
| 4.2 iPad | 只测了 iPhone，iPad 分屏/横屏溢出 | 按 `docs/ios-mac-checklist.md` 测 13" 竖/横/1/2/1/3 分屏；修最大宽度与安全区 |

## Citro 最该先做的三件事

1. **生产后端**：`trash.js` 部署，注销/举报/卡面同步不是 404；真实数据替换 QA。
2. **演示账号**：预创建、能登录、有干净演示内容、审核期间不失效；备注写清邀请码机制。
3. **截图与隐私标签**：截图只展示真实功能；隐私标签覆盖手机号、UGC 图文语音、位置、AI 文本/图片、游戏/卡面/抽签。

## 被拒后的回复模板

```text
Hello App Review,

Thank you for the review. We have addressed the issue under Guideline [X.X]:

- What changed: [具体修改，例如“deployed the production backend so account deletion and reporting no longer return 404”]
- Where to verify: [路径/URL/演示账号]
- Evidence: [录屏/截图/接口返回]

The demo account remains active during review: [账号，密码另填或说明已更新].
Please let us know if you need anything else.

Best regards,
[开发者/运营者]
[联系邮箱]
```

## 不要做

- 不要为了过审删掉举报/拉黑/注销入口；这些是 UGC 与账号类 App 的硬要求。
- 不要把真实用户内容放进截图或审核备注。
- 不要在截图/描述里写“即将上线”“Beta”“内测”。
- 不要用同一个 build number 反复上传；被拒修复后递增 build。
- 不要用企业签名/Ad Hoc 替代 App Store 公开分发。
