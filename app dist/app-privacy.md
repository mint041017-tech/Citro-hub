# App 隐私标签填写稿

> 依据：Flutter 代码、iOS 权限文案、App 内隐私政策（`flutter/lib/pages/legal_page.dart`）与根目录 `privacy.html`。
> App Store Connect 的“App 隐私”是数据申报，不是隐私政策本身；两边必须一致。

## 结论

- **追踪（Tracking）：无**。没有广告 SDK、没有 ATT 弹窗、没有跨 App 追踪、没有数据经纪。
- **关联到用户的数据**：手机号、昵称、照片/视频、音频、其他用户内容、游戏内容、用户 ID。
- **不关联到用户的数据**：大致位置（仅用于天气，不写入账号资料）。
- **未接入第三方统计/崩溃 SDK**：当前没有 Firebase、Sentry、友盟、Google Analytics 等；`citro-analytics/` 是本地演示工作台，不连接线上 App。

## 逐项填写

| Apple 数据类别 | 是否收集 | 是否关联用户 | 是否用于追踪 | 用途 | 对应场景 |
| --- | --- | --- | --- | --- | --- |
| Contact Info → Phone Number | 是 | 是 | 否 | App Functionality | 手机号注册/登录 |
| Contact Info → Name | 是 | 是 | 否 | App Functionality | 用户自选昵称、公开显示名 |
| Location → Coarse Location | 是 | 否 | 否 | App Functionality | 授权后读取大致位置，用于城市天气；不写入账号资料 |
| User Content → Photos or Videos | 是 | 是 | 否 | App Functionality | 头像、帖子配图、食谱步骤图、发给 AI 的图片 |
| User Content → Audio Data | 是 | 是 | 否 | App Functionality | 社区语音消息、语音输入 |
| User Content → Other User Content | 是 | 是 | 否 | App Functionality | 帖子、评论、点赞/抱一抱、笔记、食谱、冰箱、购物清单、生日、星座、AI 对话、抽签/卡面、好事记录 |
| User Content → Gameplay Content | 是 | 是 | 否 | App Functionality | 游戏成绩、排行榜、“正在玩”、抽卡/抽签记录 |
| Identifiers → User ID | 是 | 是 | 否 | App Functionality | 账号 ID、昵称、游客 ID、排行榜身份 |

## 明确不申报的项目

| 类别 | 结论 | 说明 |
| --- | --- | --- |
| Financial Info | 不收集 | 免费，无 IAP、无支付 |
| Purchases | 不收集 | 无购买 |
| Contacts | 不收集 | 不读取通讯录 |
| Health & Fitness | 不收集 | 无健康数据 |
| Sensitive Info | 不收集 | 不收集种族、宗教、性取向、健康、生物识别等 |
| Browsing History | 不收集 | 搜索只在本地/当前会话；不向开发者回传浏览历史 |
| Search History | 暂不收集 | 如果后续把搜索词上报服务端分析，补报此类别 |
| Usage Data | 暂不收集 | 无第三方统计 SDK；若服务端开始做行为分析/访问日志画像，补报 Product Interaction |
| Diagnostics | 暂不收集 | 无崩溃/性能 SDK；Apple 自身的崩溃报告不由开发者直接收集 |
| Advertising Data | 不收集 | 无广告 |
| Device ID | 不收集 | 游客名是随机本地昵称，不是 IDFA/IDFV；不要把它误报成 Device ID |
| Surroundings | 不收集 | 相机仅用于用户主动拍照，不做 AR/环境扫描 |
| Body | 不收集 | 无体感数据 |
| Music/Contacts 等 | 不收集 | — |

## 位置数据的边界

当前 iOS 代码使用 `LocationAccuracy.low`（约公里级）并把经纬度发送给 Open-Meteo 获取天气，符合“大致位置/Coarse Location”。注意：

- 如果后续改成高精度定位、保存精确坐标或用于天气以外用途，必须改为 `Precise Location` 并更新隐私政策。
- 如果服务端把天气城市写入账号资料，位置数据会变成“关联用户”，需改关联标记。
- Windows/Web 端还会调用 BigDataCloud 做逆地理编码；iOS 端用系统 `CLGeocoder`，不经过 BigDataCloud。

## 第三方处理

App 隐私标签之外，隐私政策必须写清：

| 第三方 | 数据 | 用途 |
| --- | --- | --- |
| Open-Meteo | 经纬度 | 获取天气 |
| 智谱 GLM | 用户主动提交的 AI 文本、图片、食谱上下文 | 生成 AI 回复 |
| BigDataCloud | 经纬度（仅 Windows/Web 逆地理） | 城市名解析 |
| Apple 系统服务 | 定位、相机、麦克风、相册、通知 | 系统权限与能力 |

- 智谱 GLM 由服务端代理调用，App 内不保存 GLM Key；这不改变“数据离开 App”的事实，隐私政策已披露。
- 没有把数据卖给第三方，也没有用于广告画像。
- 如果 Nginx/服务端保留可识别个人的访问日志并用于分析，需评估补报 Usage Data/Diagnostics，或缩短日志保留期并在隐私政策说明。

## 与现有隐私政策的差异（提交前修正）

根目录 `privacy.html` 目前比 App 内政策旧，缺少：

- AI 发送“图片”的说明（当前只写了对话文本/食谱上下文）；
- 卡面收藏、抽卡、每日运签、好事记录；
- 注销后删除“抽签记录、卡面进度”等；
- 游客 ID 与游戏数据的完整表述。

App 内政策（`legal_page.dart`）已包含这些内容。提交前把 `privacy.html` 对齐到同一口径，并更新生效日期/版本号，详见 `legal-and-backend.md`。

## 填写步骤

1. App Store Connect → App → App Privacy → Get Started。
2. “Do you or your third-party partners collect data from this app?” → **Yes**。
3. 按上表勾选数据类别，逐项选择“Linked to the user”“Used for tracking”“Purposes”。
4. 追踪问题选择 **No**（没有 ATT/广告/数据经纪）。
5. 检查生成的 “Data Not Collected” 列表，确认没有漏报。
6. 保存后，用 App Store Connect 的预览核对；每次版本更新前复核。
