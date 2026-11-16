# Citro 小程序

这个目录专门放小程序相关的内容，与 Flutter / Windows / Web 端源码隔离。

当前只实现一个功能：**无畏契约 · 玩法抽签**（对应 `flutter/lib/pages/play_page.dart`
与 `trash/trash.js` 的 `/api/play`）。不包含小游戏、社区、一起看等模块。

## 运行

1. 打开「微信开发者工具」，选择 **导入项目**；
2. 目录选 `Citro/miniprogram`（本目录）；
3. AppID 选「测试号」即可（`project.config.json` 里是 `touristappid`）；
4. 首次运行按 `Ctrl+B` 编译，页面应在模拟器里直接出现。

### 域名设置

接口地址是 `https://chimu-claw.xyz/trashapi`，与 App 端一致。

- **开发阶段**：工具右上角「详情 → 本地设置」勾选「不校验合法域名…」即可；
- **真机 / 正式版**：必须在小程序后台的「开发管理 → 开发设置 → 服务器域名」里把
  `https://chimu-claw.xyz` 加进 **request 合法域名**。这要求域名已完成 ICP 备案，
  且小程序主体非个人。备案完成前，真机上会直接报「不在以下 request 合法域名列表中」。

## 上传到微信后台

代码包根目录只放小程序本体；上传工具与密钥在仓库根目录的 `miniprogram-ci/`，
不参与打包。

### 方式一：微信开发者工具 CLI（本机已装）

本机已安装微信开发者工具（`C:\Program Files (x86)\Tencent\微信web开发者工具`），
并开启了「设置 → 安全设置 → 服务端口」。登录状态保留在工具里，直接上传：

```bash
"/c/Program Files (x86)/Tencent/微信web开发者工具/cli.bat" upload \
  --project "C:/webflu/Citro/miniprogram" \
  -v 0.1.0 -d "Citro Play Draw 0.1.0" --lang en
```

换账号或换机器时，先运行 `cli.bat login --qr-format image -o qr.png` 扫码登录。

### 方式二：miniprogram-ci（密钥上传）

1. 小程序后台 →「开发管理 → 开发设置 → 小程序代码上传」生成并下载**代码上传密钥**
   （`private.wx....key`，只展示一次），并配置 IP 白名单；
2. 安装依赖并上传：

```bash
npm install --prefix miniprogram-ci
WX_APPID=wx4c6c70936e99fc1a \
WX_UPLOAD_KEY=miniprogram-ci/private.wx4c6c70936e99fc1a.key \
node miniprogram-ci/upload.js
```

可选环境变量：`WX_VERSION`（默认 `0.1.0`）、`WX_DESC`、`WX_ROBOT`（默认 `1`）。
上传成功后到后台「版本管理 → 开发版本」提交审核或设为体验版。

## 登录（与 App 共用同一套账号）

小程序没有游客模式，**首次进入必须先登录**，否则抽签按钮被登录浮层拦住。

- 登录：手机号或邮箱 + 密码（`POST /api/auth/login`，字段 `account` / `password`）；
- 注册：手机号或邮箱 + 昵称 + 密码（`POST /api/auth/register`），注册成功即登录；
- 会话：登录返回的 `token` 存 `citro_token`，用户信息存 `citro_user`；
  所有需要身份的请求都带 `X-Trash-Token` 头（服务端 `currentUser` 支持 Cookie 与这个头）；
- 校验：启动时用 `GET /api/auth/me` 验证 token；失效则清会话并重新弹出登录；
- 退出：页头「退出」→ 清本地会话 + `POST /api/auth/logout`。

注册规则与服务端一致：昵称 2–16 位（中文 / 英文 / 数字 / 下划线），不能以「游客」开头；
密码 6–32 位；手机号为大陆 11 位号码。

### 抽签记录归属

登录后 `POST /api/play` 不再传 `deviceId`，服务端优先按账号记账（`u:昵称`）。
如果 token 在页面停留期间失效，请求会返回 400「缺少身份标识」，小程序会清会话并要求重新登录，
避免出现「抽签成功但记到了游客名下」的错位。

## 接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/auth/login` | `{account, password}`，返回 `{token, user}` |
| POST | `/api/auth/register` | `{phone 或 email, name, password}`，返回 `{token, user}` |
| GET | `/api/auth/me` | 带 token，返回 `{token, user}`；token 失效时 `user` 为 null |
| POST | `/api/auth/logout` | 带 token，注销当前会话 |
| GET | `/api/play` | 全站最近 40 条 + 本人记录；带 token 时返回 `you` 标记 |
| POST | `/api/play` | 带 token 发签并返回最新快照；429 为防刷限流 |

服务端已移除抽签冷却（`PLAY_CD_MS = 0`），因此小程序端没有冷却状态和倒计时。

## 已实现 / 未实现

已实现：

- 首次进入登录门禁：登录 / 注册切换、客户端校验、服务端错误原样提示；
- token 本地持久化、启动校验、过期重新登录；
- 云端发签（签面只认服务端，本地不做兜底，因此不会和「大家的抽签」对不上）；
- 抽取动画 16 帧、点击可提前结束；先 POST 后播动画，中途退出不会丢签；
- 全站记录、10 秒静默轮询、下拉刷新、手动刷新；
- 微信原生分享卡片（转发给好友 / 朋友圈）。

未实现（需要时再做）：

- 微信一键登录：`wx.login` → openid 与现有账号绑定，需要后端新增通道；
- 截图分享：小程序需要用 Canvas 2D 重画后 `wx.saveImageToPhotosAlbum`；
- 深色模式：目前只做了 light 主题。

## 目录结构

```
miniprogram/
├─ app.js / app.json / app.wxss    # 全局入口与样式
├─ project.config.json             # 开发者工具配置（urlCheck 已关闭）
├─ sitemap.json
├─ pages/draw/                     # 玩法抽签页面
│  ├─ draw.js / draw.json / draw.wxml / draw.wxss
└─ utils/
   ├─ api.js                       # wx.request 封装、账号与 /api/play
   ├─ session.js                   # token / 用户信息的本地会话
   └─ puns.js                      # 80 条签池（仅用于滚动动画）
```

上传工具与密钥放在仓库根目录的 `miniprogram-ci/`，不属于代码包；
`project.config.json` 的 `packOptions.ignore` 也已排除 README、`.gitignore` 和 `.key`。

## 与 App 端的同步点

签池有两份来源：`trash/trash.js` 的 `PLAY_PUNS` 和 `flutter/lib/data/puns.dart`。
`utils/puns.js` 是从服务端数组直接生成的，目前 80 条逐条一致；以后增删签面时，
按 `trash.js → puns.dart → utils/puns.js` 的顺序同步。

账号相关的字段与校验（手机号、邮箱、昵称、密码长度）在小程序里复制了一份，
服务端 `trash.js` 修改注册规则时要同步更新 `pages/draw/draw.js` 顶部的正则。