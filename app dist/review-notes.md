# App Review 审核备注（中英双语）

> 复制到 App Store Connect → App Review Information → Notes。
> 所有 `[待填]` 必须替换；演示账号密码只填 App Store Connect，不要写进本文件或 Git。
> 如果被拒后重新上传了 1910/1911，记得同步把英文/中文里的 build 号改成实际上传版本。

## English

```text
App: Citro
Bundle ID: com.chimu.crew
Version: 1.9.9 (build 1909)
Demo account: [DEMO PHONE] / [DEMO PASSWORD]

Sign-in is required for community, recipes, notes, cards, leaderboards and AI. The demo account is pre-created and can access all features. New registrations require an invite code; reviewers do not need to register. If you need a fresh account, contact [REVIEW CONTACT EMAIL] and we will provide an invite code.

Suggested review path:
1. Launch the app. The home journal (check-in, weather, daily cat, wallpaper, quote, zodiac, pomodoro) is visible as a guest.
2. Tap "我的" → "登录" and sign in with the demo account.
3. Community: open a post, like/hug/comment, report a post or comment, block a nickname, and delete your own content.
4. AI: open CiCi from the home/AI entry. Text and images are sent to our server-side proxy and then to Zhipu GLM to generate a reply. No API key is stored in the app. AI output is for entertainment only.
5. Account deletion: "我的" → "注销账号（永久删除）" → enter password. Please use the separate disposable account [DELETE TEST ACCOUNT] if you want to test deletion; do not delete the demo account.
6. Settings: privacy policy, terms, blacklist, notification toggle.

UGC moderation:
- Every post and comment has a Report entry.
- Users can block a nickname; blocked content is hidden locally.
- Reports are stored server-side and reviewed by the operator; illegal or abusive content is removed and accounts may be restricted.
- Anonymous posts are still attributable server-side for safety handling.

AI:
- CiCi is an entertainment assistant. It refuses/avoids sensitive personal data and disclaims professional advice.
- AI requests go through https://chimu-claw.xyz/trashapi/api/ai; the GLM key is server-side only.

Account deletion:
- In-app path works and permanently deletes account, posts, comments, images, voice, notes, recipes, game scores and card/fortune records.
- The public explanation is at https://chimu-claw.xyz/account-deletion.html.

Other notes:
- The app is universal (iPhone + iPad). iPhone is portrait-only; iPad supports all orientations and Split View.
- No ads, no in-app purchases, no tracking, no ATT prompt.
- The "资源库" tab is a companion catalog of PC tools/game mods maintained by the operator. Links open third-party pages; it is not required for the core app experience, not an App Store substitute, and no payment occurs in the app.
- Backend and demo account will remain online during review. Please contact [REVIEW CONTACT EMAIL] if anything is unavailable.
```

## 中文

```text
App：Citro
Bundle ID：com.chimu.crew
版本：1.9.9（build 1909）
演示账号：[DEMO PHONE] / [DEMO PASSWORD]

社区、食谱、笔记、卡面、排行榜和 AI 需要登录。演示账号已预先创建，可访问全部功能。新用户注册需要邀请码，审核员无需注册；如需要新账号，请联系 [REVIEW CONTACT EMAIL] 获取邀请码。

建议审核路径：
1. 启动 App，游客状态可浏览首页手账（打卡、天气、今日小猫、壁纸、一言、星象、番茄钟）。
2. 点「我的」→「登录」，用演示账号登录。
3. 社区：打开动态，点赞/抱一抱/评论，举报动态或评论，拉黑昵称，删除自己发布的内容。
4. AI：从首页/AI 入口打开 CiCi。文字和图片经我们服务端代理发送至智谱 GLM 生成回复；App 内不保存 API Key，AI 内容仅供娱乐。
5. 账号注销：「我的」→「注销账号（永久删除）」→ 输入密码。若要测试注销，请使用单独的一次性账号 [DELETE TEST ACCOUNT]，不要注销演示账号。
6. 设置：隐私政策、用户协议、黑名单、通知开关。

UGC 审核：
- 每条动态和评论都有「举报」入口；
- 可拉黑昵称，被拉黑内容在本机隐藏；
- 举报写入服务端，由运营者审核处理；违法违规内容会删除，账号可能被限制；
- 匿名发布仍会在服务端保留归属信息，用于安全处理。

AI：
- CiCi 是娱乐助手，不提供医疗/法律/投资建议；
- AI 请求走 https://chimu-claw.xyz/trashapi/api/ai，GLM Key 只在服务端。

账号注销：
- App 内路径可用，永久删除账号、帖子、评论、图片、语音、笔记、食谱、游戏成绩与卡面/抽签记录；
- 公开说明：https://chimu-claw.xyz/account-deletion.html。

其他：
- App 支持 iPhone + iPad；iPhone 竖屏，iPad 支持全方向与分屏。
- 无广告、无内购、无追踪、无 ATT 弹窗。
- 「资源库」是运营者维护的 PC 工具/游戏 Mod 补充目录，链接打开第三方页面；不是 App 核心功能的替代品，也不在 App 内发生支付。
- 审核期间后端与演示账号保持在线；如遇不可用，请联系 [REVIEW CONTACT EMAIL]。
```

## 填写检查

- [ ] `[DEMO PHONE]` / `[DEMO PASSWORD]` 已替换为真实可用账号
- [ ] `[DELETE TEST ACCOUNT]` 已替换为一次性账号（可选，但建议提供）
- [ ] `[REVIEW CONTACT EMAIL]` 已替换为审核期间可收信的邮箱
- [ ] 演示账号在 iPhone 与 iPad 上都能登录
- [ ] 审核期间不会删除/改名演示账号
- [ ] 后端 24 小时在线；AI、社区、注销接口都实际测过
- [ ] 没有把密码写进本文件、Git、截图或公开文档
