# Mac 交接清单与提示词

> 目标：在 Mac 上完成 Citro 1.9.9(1909) 的构建、TestFlight/真机验收、App Store 截图和提交审核。
> 本文件是交接单；商店文案、隐私标签等材料见同目录其他文件。

## 0. 当前基线

- 仓库：`https://github.com/mint041017-tech/Citro-hub`
- 分支：`main`（当前 `cd6d70a`，包含 `app dist/` 文档）；tag `v1.9.9`（`94c1eb4`）只含 iOS 代码，不含本目录文档
- Mac 构建请用 `main`，不要只 checkout tag；功能仍是 1.9.9+1909，二者 iOS 代码一致
- 版本：`1.9.9+1909`（`flutter/pubspec.yaml` 为唯一版本源）
- Bundle ID：Runner `com.chimu.crew`；TimerWidget `com.chimu.crew.TimerWidget`
- 部署目标：Runner iOS 15.0；Widget iOS 16.1
- 设备：iPhone 竖屏；iPad 全方向/分屏
- 当前无 IPA；`IPA/` 里的 1.8.0/1.9.0/1.9.1 都是 unsigned，不能上架
- 上架材料：`app dist/README.md`、`metadata.md`、`app-privacy.md`、`age-rating.md`、`review-notes.md`、`screenshots.md`

## 1. 上 Mac 前先确认的阻塞（非 Mac，但会卡审核）

- [ ] 生产 `trash/trash.js` 已部署；`/api/auth/delete`、`/api/report`、`/api/cards/*`、`/api/ai` 可用
- [ ] `GLM_API_KEY`、`SHOWAPI_KEY`、`INVITE_CODE` 已在服务端配置，未进 App/仓库
- [ ] 线上 `trash/data/` 已备份；没有用本地 data 覆盖线上
- [ ] QA 测试数据已清理/恢复，社区/食谱/排行榜没有测试垃圾
- [ ] `privacy.html`、`terms.html`、`account-deletion.html`、`support.html` 已部署并可公网访问
- [ ] 演示账号已创建，能登录全部功能，审核期间不会失效
- [ ] 已决定 UGC 发布前过滤方案（当前只有举报/拉黑，Apple 1.2 可能要求）
- [ ] 已决定 iOS「资源库」PC 工具入口是否隐藏/移动（审核可能认为与 App 功能不符）
- [ ] 已决定是否上架中国大陆（备案、版号、生成式 AI 合规）
- [ ] App Store 名称 `Citro` 已查重；备选名和商标风险已知

## 2. Mac 必做清单

### A. 环境与代码

- [ ] macOS 14+（建议 15）
- [ ] Xcode 16+，`sudo xcodebuild -license accept`
- [ ] CocoaPods、Flutter 3.47.7
- [ ] 付费 Apple Developer Program；App Store Connect 可登录；Free Apps 协议已生效
- [ ] 克隆/更新仓库，checkout `main`（当前 `cd6d70a`）；`git status` 干净
- [ ] `cd flutter && flutter pub get`
- [ ] `cd ios && pod install --repo-update`
- [ ] 打开 `ios/Runner.xcworkspace`（不是 `.xcodeproj`）
- [ ] Runner、CitroTimerWidget、RunnerTests 选择同一 Team；自动签名开启
- [ ] 确认 Bundle ID、版本 1.9.9、build 1909
- [ ] 确认 `Info.plist` 的 `ITSAppUsesNonExemptEncryption=false`
- [ ] `flutter analyze` 无 error/warning
- [ ] `flutter test` 通过；有失败要记录原因，不要静默忽略
- [ ] `bash ios/build_ipa.sh` 成功，产物在 `flutter/build/ios/ipa/`
- [ ] 检查 IPA：Runner/Widget 的版本、build、Bundle ID 正确
- [ ] 用 Xcode Organizer 或 Transporter 上传 App Store Connect
- [ ] 构建处理完成，出口合规自动回答

### B. TestFlight 与真机验收

- [ ] 内部 TestFlight（最多 100 人，无需审核）安装到 iPhone + iPad
- [ ] 演示账号登录；社区发文字/图片/语音、评论、点赞/抱一抱、删除自己的内容
- [ ] 举报动态/评论；拉黑昵称；确认举报不是 404
- [ ] AI 文字/图片对话；好事记录；星象；抽签；卡面；排行榜
- [ ] 相机、麦克风、相册、定位、通知权限；拒绝后仍有降级路径
- [ ] 番茄钟/Live Activity（iPhone，iOS 16.1+）
- [ ] iPhone 竖屏锁定；返回手势；键盘弹起；深色模式
- [ ] iPad 13" 竖屏、横屏、1/2 与 1/3 分屏；无溢出/横向滚动
- [ ] 极限刹车、咕噜果冻等 WebView 游戏加载；120Hz 接近满帧
- [ ] 用一次性账号测试「我的 → 注销账号」；不要注销演示账号
- [ ] 卡面收藏/今日卡/抽卡次数在 iPhone、iPad、Web 同账号一致
- [ ] 需要公开 TestFlight：External Testing → Test Information → Beta App Review → Public Link（最多 10,000 人，build 90 天过期）
- [ ] 记录每个失败的复现步骤、设备、系统版本、build

### C. 截图与 App Store Connect

- [ ] iPhone 6.9" 截图：1320×2868 竖屏，至少 1 张（建议 6 张）
- [ ] iPad 13" 截图：2064×2752 或 2752×2064，横屏优先，至少 1 张（建议 6 张）
- [ ] 截图不含 beta/TestFlight/QA/真实用户隐私；状态栏 9:41、满电
- [ ] App 图标 1024×1024，无透明通道
- [ ] App 记录已创建（名称、Bundle ID、SKU、主语言）
- [ ] 填 `app dist/metadata.md`：名称/副标题/描述/关键词/分类/版权/价格/销售范围
- [ ] 支持 URL `https://chimu-claw.xyz/support.html`
- [ ] 隐私政策 URL `https://chimu-claw.xyz/privacy.html`
- [ ] App Privacy 按 `app dist/app-privacy.md` 填；Tracking = No
- [ ] 年龄分级按 `app dist/age-rating.md` 填
- [ ] 内容版权按第三方游戏/素材实际授权填写
- [ ] App Review Information：联系人、演示账号、中英备注
- [ ] 选择 build 1909；如已上传过同号 build，改用 1910
- [ ] 提交审核；建议手动发布，通过后可开分阶段发布

### D. 提交后

- [ ] 记录提交时间、build、审核状态
- [ ] 被拒后按 `app dist/rejection-playbook.md` 修复；递增 build 重新上传
- [ ] 通过后手动发布；监控崩溃、登录、社区、AI、注销
- [ ] 上架后每次更新复核隐私标签、法务页和截图

## 3. 可直接粘贴的提示词

### Prompt 1：Mac 构建与上传

```text
你在一台 Mac 上处理 Citro iOS 1.9.9 的出包与上传。

项目：https://github.com/mint041017-tech/Citro-hub
分支：main（当前 commit cd6d70a；版本仍是 1.9.9+1909）
Flutter 工程：仓库根目录下的 flutter/

先读：
- app dist/mac-build-upload.md
- app dist/README.md
- docs/ios-mac-checklist.md

目标：产出可上架 App Store 的 1.9.9(1909) IPA，并上传到 App Store Connect。
不要部署后端，不要改业务功能，不要提交 IPA/密钥/证书到 Git。

执行步骤：
1. 检查 macOS、Xcode、CocoaPods、Flutter 版本，输出实际版本号。
2. 克隆或更新仓库，checkout main；确认 git status 干净且 HEAD 为 cd6d70a（或更新的 main）。
3. cd flutter && flutter pub get；cd ios && pod install --repo-update。
4. 打开 ios/Runner.xcworkspace，确认 Runner、CitroTimerWidget、RunnerTests 使用同一 Team 并开启自动签名。如果 Team 未配置，停下来让我在 Xcode 里选择，不要猜 Team ID。
5. 确认 pubspec.yaml 版本为 1.9.9+1909；Runner Bundle ID 为 com.chimu.crew；Widget 为 com.chimu.crew.TimerWidget。
6. 运行 flutter analyze；再运行 flutter test，记录所有失败，不要静默忽略。
7. 运行 bash ios/build_ipa.sh。失败时只修构建/签名/CocoaPods 问题；需要改业务代码先停下来问我。
8. 检查 IPA：版本 1.9.9、build 1909、Bundle ID 正确、Info.plist 的 ITSAppUsesNonExemptEncryption=false。
9. 用 Xcode Organizer 或 Transporter 上传 App Store Connect，等待处理完成。
10. 输出：命令与结果、IPA 路径、版本/build、Bundle ID、上传状态、所有警告和阻塞项。

禁止：--no-verify、改 git 历史、写入真实密码/API Key、覆盖 IPA/ 里的旧包。
```

### Prompt 2：TestFlight 与真机验收

```text
你在 Mac + iPhone/iPad 上做 Citro 1.9.9 的 TestFlight 真机验收。

先读：
- app dist/checklist.md
- app dist/demo-account.md
- docs/ios-mac-checklist.md

使用内部 TestFlight 安装 build 1909，用演示账号登录。不要污染生产数据，不要删除演示账号；测试注销时使用单独的一次性账号。

逐项测试并输出表格（项目/设备/系统版本/build/结果/证据/问题）：
1. iPhone 竖屏锁定；iPad 13" 竖屏、横屏、1/2 和 1/3 分屏。
2. 登录、社区发文字/图片/语音、评论、点赞/抱一抱、删除自己的内容。
3. 举报动态/评论、拉黑昵称；确认不是 404。
4. AI 文字/图片对话、好事记录、星象、抽签、卡面、排行榜。
5. 相机、麦克风、相册、定位、通知；拒绝权限后的降级。
6. 番茄钟/Live Activity（iPhone，iOS 16.1+）。
7. 极限刹车、咕噜果冻等 WebView 游戏；120Hz/流畅度。
8. 用一次性账号走「我的 → 注销账号」，确认数据删除。
9. 同账号在 iPhone/iPad/Web 的卡面收藏、今日卡、抽卡次数一致。
10. 需要公开 TestFlight 时，检查 External Testing 的 Test Information、Beta App Review 和 Public Link。

需要输入密码时停下来让我手动输入，不要写进日志或文件。发现 bug 先给复现步骤、预期/实际、设备、系统、build，不要擅自改业务代码。
```

### Prompt 3：截图与 App Store Connect

```text
你在 Mac 上帮 Citro 准备 App Store 截图并填写 App Store Connect。

先读：
- app dist/metadata.md
- app dist/app-privacy.md
- app dist/age-rating.md
- app dist/review-notes.md
- app dist/screenshots.md

任务：
1. 用 iPhone 6.9" 和 iPad 13" 模拟器拍 6 张截图（首页、游戏、游戏内、社区、食谱、听隅/卡面）。状态栏 9:41、满电；不要出现 beta/TestFlight/QA、真实用户隐私、debug banner。截图成品放 app dist/screenshots/final/。
2. 部署/核验公网 URL：support.html、privacy.html、terms.html、account-deletion.html。可以运行 app dist/scripts/verify-public-urls.sh；只做匿名 GET，不写数据。
3. 如果 App Store Connect 还没有 App 记录，按 metadata.md 创建：名称、Bundle ID com.chimu.crew、SKU、主语言、分类、价格与销售范围。
4. 填 metadata.md、app-privacy.md、age-rating.md 的所有字段；上传截图；填内容版权、支持 URL、隐私政策 URL。
5. 填 App Review Information：联系人、演示账号、review-notes.md 中英备注。密码只填 App Store Connect，不要写进仓库或聊天记录。
6. 选择 build 1909；输出提交前检查表，等我明确说「提交」后再点 Submit for Review。不要绕过 2FA，不要自动提交。

如果 App 名称 Citro 被占用，停下来列出可用备选名；如果中国大陆销售范围未决定，停下来问我。不要编造演示账号、联系方式或备案号。
```

### Prompt 4：被拒后的处理

```text
你在 Mac 上处理 Citro 的 App Store 拒审。

先读拒审信和 app dist/rejection-playbook.md，逐条映射到 Guideline。输出：
1. 拒审原因（引用原文）；
2. 需要改的代码/后端/文案/截图；
3. 是否影响 1.9.9 版本号；
4. 验证步骤和证据。

修复后：
- build number 递增（例如 1909 → 1910），不要重复上传 1909；
- 更新 review-notes.md 里的 build 号和备注；
- 重新构建、上传、填写审核信息；
- 提交前给我变更清单和证据，等我确认后再提交。
不要删除举报/拉黑/注销入口，不要把真实用户数据放进截图或备注。
```

## 4. 交付标准

- [ ] Mac 能产出并上传 `1.9.9(1909)` 或递增 build 的 IPA
- [ ] TestFlight 内部验收通过，关键路径有证据
- [ ] iPhone 6.9" 与 iPad 13" 截图各至少 1 张，推荐 6 张
- [ ] App Store Connect 元数据、隐私标签、年龄分级、审核备注完整
- [ ] 演示账号可用，后端/法务页在线
- [ ] 明确记录哪些项未验证，不用“应该可以”代替证据
