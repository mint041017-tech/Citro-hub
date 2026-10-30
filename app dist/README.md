# Citro App Store 上架工作区（app dist）

本目录是 Citro iOS 上架 App Store 的独立材料区，只放文案、清单、模板和 Mac 辅助脚本，不改线上后端、法务页面或 iOS 工程。

## 当前基线（2026-10-30）

- 版本：`1.9.9+1909`，唯一版本源为 `flutter/pubspec.yaml`
- Bundle ID：Runner `com.chimu.crew`，TimerWidget `com.chimu.crew.TimerWidget`
- 部署目标：Runner iOS 15.0，Widget iOS 16.1
- 设备：iPhone 运行时锁竖屏；iPad 支持全方向与分屏
- API：`https://chimu-claw.xyz/trashapi`
- 已有：应用内隐私政策/用户协议、应用内账号注销、举报、拉黑、PrivacyInfo.xcprivacy、`ITSAppUsesNonExemptEncryption=false`
- 已完成：TestFlight 1909、演示账号 `CitroReview`、iPhone 6.3"/iPad 13" 各 6 张截图并上传 ASC、App 审核信息
- 未完成：生产 `trash.js` 部署、三个法务页与支持页公网核验、真实数据恢复、中国区备案/AI 合规评估
- 需要决策：社区发布前内容过滤（当前代码有举报/拉黑，但未看到发布前敏感词过滤；Apple 1.2 可能要求）

> 仓库发布清单仍把生产 `trash.js`、法务页部署和真实数据恢复列为待办；提交前必须实际核验，不要只看文档。

## 本次同步

- 新增 `app dist/` 全套上架材料和支持页。
- 新增 `screenshots/final/` 12 张 App Store 截图，并在根 README 展示；截图已上传 ASC。
- 根目录 `privacy.html` 的公开文本已对齐 App 内政策：补 AI 图片、卡面/抽卡/每日运签/好事记录、注销删除范围；仍需部署到公网。
- `docs/citro-部署上传清单.md` 已加入 `support.html` 部署项。
- 未改线上后端、数据库和 iOS 工程；生产 `trash.js` 与真实数据恢复仍需执行。

## 目录

| 文件 | 用途 |
| --- | --- |
| `checklist.md` | 从今天到提交审核的总检查单，按负责人和证据拆分 |
| `metadata.md` | App Store Connect 商店文案、分类、价格、URL、版权等可复制内容 |
| `app-privacy.md` | App 隐私标签逐项填法，含“关联用户/追踪/用途” |
| `age-rating.md` | 年龄分级问卷草稿与 UGC/AI/网页访问注意事项 |
| `review-notes.md` | 中英双语审核备注模板，含演示账号占位符 |
| `demo-account.md` | 审核账号的准备、演示数据、安全与维护要求 |
| `screenshots.md` | iPhone 6.9" / iPad 13" 截图清单、文案与 Mac 拍摄命令 |
| `china-compliance.md` | 中国区备案、版号、生成式 AI、PIPL 检查清单 |
| `legal-and-backend.md` | 法务 URL、后端接口、注销/举报/AI 的核验清单 |
| `mac-build-upload.md` | Mac 构建、上传、TestFlight 与 App Store 版本提交步骤 |
| `rejection-playbook.md` | Citro 高概率拒审项与处理方式 |
| `support.html` | App Store 支持页，部署为 `https://chimu-claw.xyz/support.html` |
| `scripts/capture-ios-screenshots.sh` | Mac 模拟器截图辅助脚本（手动切页，逐张截屏） |
| `scripts/verify-public-urls.sh` | 公网法务页与基础 API 的可访问性检查 |
| `screenshots/final/` | iPhone 6.3" 与 iPad 13" 各 6 张 App Store 截图（JPG） |

## 使用顺序

1. 先补 `metadata.md`、`review-notes.md`、`demo-account.md` 里的 `[待填]`。
2. 按 `legal-and-backend.md` 核验线上法务页、后端、注销/举报/AI。
3. 在 Mac 上按 `mac-build-upload.md` 出包并上传。
4. 先内部 TestFlight 自测，再按 `screenshots.md` 拍素材。
5. 在 App Store Connect 填 `metadata.md`、`app-privacy.md`、`age-rating.md` 的内容。
6. 按 `checklist.md` 逐项打勾后提交；被拒时看 `rejection-playbook.md`。

## 安全规则

- **不要把真实审核账号密码、App Store Connect API Key、证书私钥写进本目录或提交到 Git。**
- 演示账号密码直接填进 App Store Connect 的 App Review Information，不要落到仓库。
- 截图、审核备注、公开文案里不要出现真实用户手机号、微信、社区私密内容或 QA 测试垃圾数据。
- 本目录不构成法律意见；中国区备案、版号、生成式 AI 合规请按实际业务咨询专业人士。
