# Citro 小程序

与 Flutter / Windows / Web 端共享同一套账号和后端（`https://chimu-claw.xyz/trashapi`）
的微信原生小程序。当前版本 **0.2.4**，包含四个 tab 和全部二级页面，
不包含小游戏、社区、AI 对话、一起看与桌面端外壳。

## 四个 tab

| tab | 页面 | 内容 |
| --- | --- | --- |
| 首页 | `pages/home/home` | 时段光晕、摸鱼、心情、听隅、食谱、每日一句 |
| 计划 | `pages/plan/plan` | 今天（农历/节气/节日/倒数日）、待办摘要、记账摘要 |
| 玩法 | `pages/draw/draw` | 随机抽取玩法、大家的抽取记录 |
| 我的 | `pages/me/me` | 资料、数据概览、协议、关于、退出、注销账号 |

二级页面：`agreement`（协议）、`fish`（摸鱼日历）、
`mood`（心情）、`tingyu`（听隅）、`cook`（食谱/广场/购物清单）、
`calendar`（日历）、`todo` + `todo/edit`（待办）、`ledger`（记账）。

`app.json` 的 tabBar 图标在 `assets/tab/`（81×81 PNG，本地文件）。
首页背景不再用四张 1024×1024 webp，改为纯 CSS 的 dawn / day / dusk / night
四套时段渐变（双击 hero 可切换，选择存 `citro_home_hero_v1`），包体少了约 639KB。

> `pages/fortune`、`pages/checkin`、`pages/cards` 与 `pages/weather` 都不在包内。
> 小程序不做今日签 / 宜忌 / 卡面抽取等运势与收藏玩法，也不提供天气查询；
> 相关审核风险与定位说明随之移除；需要这些功能时请使用 App 端。

## 运行

1. 微信开发者工具 → 导入项目，目录选本目录；
2. AppID 已写入 `project.config.json`（`wx4c6c70936e99fc1a`）；
3. `Ctrl+B` 编译。开发阶段可在「详情 → 本地设置」勾选「不校验合法域名」，
   但**正式版与体验版仍会校验**，上线前必须配置服务器域名（见下）。

`app.json` 的 `entryPagePath` 固定为 `pages/home/home`，启动落在首页；
tabBar 的第一项也是首页，二者保持一致。

> 小程序运行时 `require()` **只支持 JS 模块，不支持 `.json` 文件**。
> 页面需要的静态数据必须写成 `module.exports = {...}` 的 JS 文件，
> 一旦引用 `.json`，页面会在注册前抛错，表现为整页空白。

### 服务器域名

| 类型 | 域名 | 用途 |
| --- | --- | --- |
| request | `https://chimu-claw.xyz` | 全部接口 |
| downloadFile | `https://chimu-claw.xyz` | 食谱封面 / 步骤图（`/trashapi/media/...`） |
| downloadFile | `https://obs.chimu-claw.xyz` | 听隅音频 |

`<image>` 与 `InnerAudioContext` 都走 downloadFile 域名；图片和音频缺一个都会静默失败。
域名需完成 ICP 备案，且小程序主体不能是个人。

## 上传到微信后台

代码包根目录只放小程序本体；上传工具与密钥在仓库根目录的 `miniprogram-ci/`，
不参与打包（`packOptions.ignore` 已排除 README、`.gitignore`、`*.key`）。

### 方式一：开发者工具 CLI（本机 OAuth）

```bash
"/c/Program Files (x86)/Tencent/微信web开发者工具/cli.bat" upload \
  --project "C:/webflu/Citro/miniprogram" \
  -v 0.2.2 -d "Citro 小程序 0.2.2" --lang en
```

预览用 `cli.bat preview --project ... --qr-format image -o preview.png`。
本机已开启「设置 → 安全设置 → 服务端口」；换账号时先 `cli.bat login` 扫码。

### 方式二：miniprogram-ci（代码上传密钥）

```bash
npm install --prefix miniprogram-ci
WX_APPID=wx4c6c70936e99fc1a \
WX_UPLOAD_KEY=miniprogram-ci/private.wx4c6c70936e99fc1a.key \
WX_VERSION=0.2.2 \
WX_DESC="Citro 小程序 0.2.2" \
node miniprogram-ci/upload.js
```

密钥只展示一次，必须在后台配置上传 IP 白名单。密钥文件已被两层 `.gitignore`
排除，**不要**放进代码包或提交到任何仓库。

## 登录与协议

小程序没有游客模式，首次进入先看到协议同意，再登录 / 注册；四个 tab 内都挂了
同一个 `components/login-gate`，登录态跨 tab 共享 `utils/session.js`。

- 同意：必须主动勾选，无默认勾选；版本号 `AGREEMENT_VERSION = "2026-11-17-tabs-v3"`。
  修改条款时同时提升该版本与 `pages/agreement/content.js` 的 `VERSION`；
- 登录：`POST /api/auth/login`（`account` / `password`），token 存 `citro_token`；
- 校验：启动调 `GET /api/auth/me`；失效则清 token 并重新拉起登录门禁；
- 退登：`POST /api/auth/logout` + 本地清理；退登**不清**协议同意记录；
- 切 tab：各 tab 在 `onShow` 调 `syncGate()`，避免在「我的」退出后其他 tab
  仍显示上一个账号的数据；
- 注销：我的 → 注销账号，需要再次输入密码，走 `POST /api/auth/delete`。

注册规则与服务端一致：昵称 2–16 位（中文/英文/数字/下划线，不能以「游客」开头），
密码 6–32 位，手机号为大陆 11 位。

## 数据与同步

### 计划（待办 / 日历 / 记账）

离线优先：页面先读本地缓存，再与服务端对账；写入本地后异步回传。采用整包 LWW：

- 本地键：`citro_todo_v1`、`citro_calendar_marks_v1`、`citro_ledger_v1`；
- 时间戳键：`<key>_at`，谁的时间戳更新谁覆盖；
- 接口：`GET/POST /api/todo`、`GET/POST /api/calendar`、`GET/POST /api/ledger`。

服务端这几个接口的 JSON 体积上限已放宽（待办/日历 260KB，记账 1100KB）。

### 首页

- 摸鱼：`GET/PUT /api/moyu/config`；
- 心情：读写 `citro_todo_v1.moods`，与待办共用一份快照；
- 听隅：28 条声景，`https://obs.chimu-claw.xyz/ambient%20noise/{id}.wav`；
  单轨播放、循环、15/30/60 分钟定时，页面隐藏即停止并销毁；
- 食谱：`/api/cook*`，封面/步骤图压缩后以 base64 走 `POST /api/cook/img`。

### 玩法

`GET /api/play` 取全站最近记录，`POST /api/play` 云端发签。没有冷却，没有本地签面兜底。

## UGC 与举报

食谱广场是用户内容，服务端没有接入微信内容安全接口（需要额外保管 AppSecret），
因此采用「举报 + 运营者人工审核」：

- 广场底部常驻说明：内容由用户发布，可打开详情举报；
- 详情页对非本人的公开食谱显示「举报」，原因走 `wx.showActionSheet`；
- `POST /api/report` 的 `type: "recipe"` 会校验食谱存在且公开、禁止举报自己，
  并按 `recipeId` 去重；其他类型：`post` / `comment` / `user`；
- 举报记录在 `trash/data` 里，运营者定期处理；严重内容先下架再处理。

「大家的抽取」只展示昵称和玩法结果，不含自由文本，审核风险较低。

## 后端改动（上线前必须部署）

`trash/trash.js` 已加入：

1. `/api/weather`、`/api/weather/geocode` 的 Open-Meteo 代理与缓存（App 端使用，
   小程序已不含天气）；
2. 待办/日历/记账/首页布局的请求体上限放宽；
3. `/api/report` 支持 `recipe` 类型与 `recipeId`。

部署顺序：备份 `trash/data` → 覆盖 `trash/trash.js` → `pm2 restart trash`。
举报在部署前不可用；App 端天气接口同样依赖这次部署；计划同步会退回纯本地。

## 审核清单

- [ ] 服务器域名：request `chimu-claw.xyz`，downloadFile `chimu-claw.xyz` +
      `obs.chimu-claw.xyz`；域名已备案；
- [ ] 用户隐私保护指引：声明手机号/邮箱、昵称、食谱图片（相册与相机）、
      待办/日历/记账数据；说明保存位置与删除方式；
- [ ] 注销账号入口可用，且不要求联系客服；
- [ ] 所有「抽取」均为免费，无支付、无充值、无概率公示缺失；
- [ ] 玩法文案只写娱乐，不出现改运、占卜、算命、赌博等承诺；
- [ ] 食谱广场的举报入口与说明可见；必要时审核期先隐藏广场；
- [ ] 听隅素材版权可商用/可展示（OBS 自托管）；
- [ ] 提交审核前用独立测试账号，不填真实个人密码。

已知风险（用户已知情并选择保留）：四个 tab 都是全页登录门禁，
与微信「不得强制登录」的审核口径存在冲突；若被驳回，最小改法是首页先展示
本地内容，只在需要账号的操作处拉起登录。

## 目录结构

```
miniprogram/
├─ app.js / app.json / app.wxss       # 入口、路由/tabBar、全局 token
├─ project.config.json                # 开发者工具配置
├─ assets/tab/                        # 8 个 tabBar 图标（81×81 PNG）
├─ components/login-gate/             # 协议 → 登录/注册 共用门禁
├─ pages/                             # 13 个页面（见上方表格）
└─ utils/
   ├─ api.js                          # wx.request 封装与全部接口
   ├─ session.js                      # token / 用户 / 协议同意
   ├─ todo-store.js                   # 待办快照 + LWW 同步
   ├─ calendar-store.js               # 日历标记快照 + LWW 同步
   ├─ ledger-store.js                 # 记账快照 + LWW 同步
   ├─ lunar.js                        # 农历 / 节气 / 节日
   └─ puns.js                         # 抽取滚动动画用签池
```

## 与 App 端的同步点

- 账号字段与校验在两处各有一份，改动服务端注册规则时同步
  `components/login-gate/login-gate.js`；
- 签池：`trash/trash.js` → `flutter/lib/data/puns.dart` → `utils/puns.js`；
- 协议正文 `pages/agreement/content.js` 与 App 端法律页保持同一版本口径；
  本次移除打卡、卡面与天气后，协议版本升到 `v1.3`，对应的
  `AGREEMENT_VERSION` 为 `2026-11-17-tabs-v3`。