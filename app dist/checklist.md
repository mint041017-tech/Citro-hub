# Citro App Store 提交检查单

> 版本基线：1.9.9+1909；Bundle ID `com.chimu.crew`。
> 勾选前请附证据（链接、截图、日志或 App Store Connect 页面），不要凭记忆打勾。

## A. 产品与账号决策

- [ ] App Store 名称可用：优先 `Citro`，备选 `Citro 手账` / `Citro - 手账与游戏社区`
- [ ] 已检查名称占用与商标风险（Citro 与汽车品牌 Citroën 接近，必要时咨询法务）
- [ ] 确定销售范围：中国大陆 / 仅海外 / 全球（中国区另看 `china-compliance.md`）
- [ ] 确定主分类：建议 `生活`，副分类 `娱乐`；不要默认选 `游戏`（中国区可能触发版号）
- [ ] 确定年龄分级问卷答案（见 `age-rating.md`）
- [ ] 准备专用审核账号（见 `demo-account.md`）
- [ ] 确定审核联系人姓名、电话、邮箱
- [ ] 确认免费、无 IAP、无广告；如后续加付费功能，改走 IAP

## B. 后端与数据

- [ ] 生产 `trash/trash.js` 已更新到包含账号注销、举报、卡面同步的版本
- [ ] 更新时只替换 `trash.js`，没有覆盖线上 `trash/data/`
- [ ] 已备份线上 `trash/data/` 与 Nginx 配置
- [ ] `pm2 restart trash`（或其他进程管理器）后服务正常
- [ ] `https://chimu-claw.xyz/trashapi/api/posts` 返回 200，不是 404/502
- [ ] 演示账号可登录；`/api/auth/me` 正常返回
- [ ] AI 代理可用；GLM Key 只在服务端，App 内无密钥
- [ ] 举报接口可用；举报后运营者能看到记录
- [ ] 账号注销接口可用；用一次性账号测试，不用审核账号
- [ ] 社区、食谱、卡面、抽签、排行榜数据与当前 App 版本兼容
- [ ] **社区发布前有敏感词/违规内容过滤**（当前代码只看到举报/拉黑，未看到发布前过滤；Apple 1.2 可能要求）
- [ ] AI 回复有基本的违法/色情/暴力内容防护或拒绝策略
- [ ] 线上 QA 测试数据已清理或替换为可公开展示的数据
- [ ] 审核期间服务器 24 小时在线，演示账号不会被删除或改名

## C. 法务页面

- [ ] `https://chimu-claw.xyz/privacy.html` 返回 200，中文正常，内容与 App 内隐私政策一致
- [ ] `https://chimu-claw.xyz/terms.html` 返回 200
- [ ] `https://chimu-claw.xyz/account-deletion.html` 返回 200
- [ ] 隐私政策包含：手机号/昵称/头像/生日、UGC 图文语音、笔记/食谱、位置、AI 文字与图片、游戏/卡面/抽签、第三方 Open-Meteo 与智谱 GLM、注销与联系方式
- [ ] 用户协议包含：社区零容忍、举报/拉黑、账号注销、AI 娱乐免责声明
- [ ] 三个页面无需登录即可访问，手机浏览器排版正常
- [ ] 隐私政策生效日期与版本号已更新（建议与本次上架版本同步）
- [ ] `app dist/support.html` 已部署为 `https://chimu-claw.xyz/support.html`，支持 URL 可访问

## D. iOS 构建与上传

- [ ] Mac 已安装 Xcode 16+、CocoaPods、Flutter 3.47.7
- [ ] `Runner.xcworkspace` 中 Runner、CitroTimerWidget、RunnerTests 选择同一 Apple Developer Team
- [ ] 自动签名可用；Bundle ID 与 App Store Connect App ID 一致
- [ ] `flutter analyze` 无 error/warning
- [ ] `flutter test` 通过（如有测试）
- [ ] `bash ios/build_ipa.sh` 成功，产物在 `build/ios/ipa/`
- [ ] 使用 Xcode Organizer 或 Transporter 上传到 App Store Connect
- [ ] 构建处理完成；出口合规已由 Info.plist 自动回答
- [ ] TestFlight 内部测试完成：登录、社区、AI、相机/麦克风/相册、定位、通知、iPad 布局、深色模式、返回手势
- [ ] 未使用 `IPA/` 里的旧 unsigned 包
- [ ] 每次重新上传都递增 build number（1909 → 1910 → …）

## E. App Store Connect 元数据

- [ ] App 记录已创建，Bundle ID 选对，SKU 确定
- [ ] 版本号 1.9.9，选择正确的 build
- [ ] 名称、副标题、宣传文本、描述、关键词已填（`metadata.md`）
- [ ] 主分类/副分类已填
- [ ] 价格：免费；销售范围已选
- [ ] 版权人已填
- [ ] 支持 URL、隐私政策 URL、营销 URL 已填且可访问
- [ ] iPhone 6.9" 截图至少 1 张，iPad 13" 截图至少 1 张（推荐各 6 张）
- [ ] 截图不含 beta/TestFlight/QA 字样，不含真实用户隐私，内容和当前 App 一致
- [ ] App 图标 1024×1024，无透明通道
- [ ] App 隐私标签已按 `app-privacy.md` 填完
- [ ] 年龄分级问卷已按 `age-rating.md` 填完
- [ ] 内容版权声明已按实际第三方游戏/素材授权填写
- [ ] App Review Information：联系人、演示账号、备注已填
- [ ] 备注说明邀请码机制、AI、UGC 举报/拉黑、账号注销路径
- [ ] 审核期间演示账号可用，服务器在线
- [ ] 发布方式：建议手动发布；可选分阶段发布

## F. 提交后

- [ ] 提交 App Review，记录提交时间与 build
- [ ] 被拒后按 `rejection-playbook.md` 逐条修复，递增 build 重传
- [ ] 通过后手动发布，观察崩溃、登录、社区、AI、支付（无）与隐私反馈
- [ ] 上架后保留 TestFlight 构建给内部回归；build 90 天过期
- [ ] 下次更新前复核隐私标签与法务页，功能/数据变化要同步更新
