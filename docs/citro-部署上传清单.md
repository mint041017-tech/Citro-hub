# Citro 部署上传清单

> 站点根目录示例：`/path/to/site/`（下文以宝塔默认站点根为例）。把下面文件按原目录结构覆盖即可。

## 1. 前端页面（必须）

| 上传内容 | 说明 |
| --- | --- |
| `index.html` | 整站单页，所有页面、脚本、内联样式都在里面 |
| `manifest.json` | PWA 名称、图标 |
| `styles/*.css` | 11 个样式文件（`citro-core / home / pages / games / community / cook / overlays / refine / arcade / scrapbook / glass`；`glass` 在 `index.html` 里带 `?v=` 版本号，改它时同步升版本号） |
| `fonts/*.woff2` | 本地字体（5 个：`zcool-kuaile-400-sub` + 4 个 `noto-sans-sc-*-sub`） |
| `素材/citro-logo.png` | 左上角 logo、各页水印 |
| `素材/favicon-32.png`、`favicon-64.png`、`apple-touch-icon.png` | 浏览器 / iOS 图标 |
| `素材/icon-192.png`、`icon-512.png` | manifest 里的 PWA 图标 |
| `素材/citro-og.jpg` | 社交分享缩略图 |
| `素材/赞赏码.png` | 赞赏弹窗 |
| `素材/MOD图片/*.jpg` | 资源页 6 张 Mod 封面 |
| `素材/猫猫/*.png` | 首页「今日小猫」随机图 |
| `privacy.html` | 隐私政策公开页（应用商店隐私政策 URL） |
| `terms.html` | 用户协议公开页 |
| `account-deletion.html` | 账号注销/数据删除说明公开页（应用商店数据删除 URL） |
| `support.html` | App Store 支持页（来源：`app dist/support.html`，发布时复制到站点根目录） |

## 2. 大文件（服务器已有就不用重传）

| 目录 | 用途 | 体积参考 |
| --- | --- | --- |
| `APK/Citro-v1.8.0-release.apk` | 站内 APK 下载（`index.html` 直链 OBS：`https://obs.chimu-claw.xyz/APK/Citro-v1.8.0-release.apk`，上传到 OBS 的 `APK/` 目录；旧版本可保留也可删除） | ~75.0 MB |
| `APK/update.json` | 应用内更新清单（`flutter/build.js release` 生成，与 APK 一起上传到 OBS 的 `APK/`；缺失时 App 回退读取同目录 APK 列表） | <1 KB |
| `小工具/` | 工具下载直链（`https://你的域名/小工具/...`） | ~865 MB |
| `外设驱动/` | 驱动下载直链（`https://你的域名/外设驱动/...`） | ~340 MB |

这些链接在 `index.html` 里写的是绝对 URL，换域名/换服务器时要么一起上传，要么改下载地址。
`小工具/`、`外设驱动/` 体积大且含客户端安装包，**不在本仓库内**，需单独上传到站点根目录。

## 3. 后端（社区 / 登录 / 食谱 / 星象才需要）

| 上传内容 | 说明 |
| --- | --- |
| `trash/trash.js` | Node 零依赖服务，默认端口 10003；Nginx 反代 `/trashapi` 到 `127.0.0.1:10003`。v1.7.10 起新增账号注销 `/api/auth/delete` 与社区举报 `/api/report`，**必须先更新此文件**，否则 App 内注销/举报会返回 404。 |
| `trash/data/` | 用户、帖子、头像、食谱图等持久数据（**仓库不含，目录不存在时服务会自动创建**）；举报写入 `reports.json`，需运营者定期审核。 |
| `zodiac-ai.json` | 星象运势缓存（**仓库不含**，服务端按需生成） |

### 3.1 密钥配置（不要写进代码 / 不要提交）

`trash/trash.js` 从环境变量读取敏感配置，其次读 `trash/config.local.json`（已被 `.gitignore` 排除）：

| 变量 / 字段 | 用途 | 不配置时 |
| --- | --- | --- |
| `SHOWAPI_KEY` | 万维易源 appKey（星座运势接口） | 运势接口不可用，其余功能正常 |
| `INVITE_CODE` | 注册邀请码 | 注册不校验邀请码（开放注册） |

两种配置方式任选：

```bash
# 方式一：环境变量（PM2 示例）
pm2 start trash/trash.js --name trash --env SHOWAPI_KEY=xxx
# 或在 PM2 配置文件里写 env: { SHOWAPI_KEY: 'xxx', INVITE_CODE: 'xxx' }

# 方式二：本地配置文件（复制模板后填写）
cp trash/config.local.example.json trash/config.local.json
```

### ⚠️ 数据目录不要覆盖

更新代码时只传 `trash/trash.js`，**不要把本地 `trash/data/` 覆盖到线上**，否则会覆盖用户、帖子、会话等数据。
正确顺序：备份线上 `trash/data` → 停服务 → 替换 `trash.js` → 启动（PM2：`pm2 restart trash`）。

## 4. 更新后检查

1. 浏览器强刷（Ctrl+F5）或清 CDN/宝塔缓存，CSS 更新后尤其容易缓存旧文件。
2. 首页、资源页、游戏页、手机端各看一遍。
3. 社区发帖 / 登录 / 摸鱼配置 / 天气接口正常，说明 `/trashapi` 反代没断。
4. 控制台无 404（重点看 `styles/`、`素材/`、`fonts/`）。

## 5. 建议备份

- `index.html`
- `styles/`
- `trash/data/`
- 服务器上的 Nginx/Apache 反代配置（线上 vhost 与 `/trashapi` 反代的同步副本在 `docs/nginx/`）
- `trash/config.local.json`（含密钥，单独保管）
