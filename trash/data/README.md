# trash/data —— 运行时数据目录（不入库）

本目录存放 `trash/trash.js` 运行期间产生的**真实用户数据**：

| 文件 | 内容 |
| --- | --- |
| `users.json` | 账号（昵称、手机号、salt、scrypt 哈希、生辰资料） |
| `sessions.json` | 登录会话令牌 |
| `posts.json` | 社区帖子 |
| `notes.json` | 便签 |
| `cook.json` | 食谱 |
| `games.json` | 小游戏段位/排行 |
| `lantern.json` | 灯谜答案记录 |
| `zodiac-*.json` | 星象/运势业务数据 |
| `avatars/` `postimgs/` `voices/` `cookimgs/` | 用户上传的头像、配图、语音、食谱图 |

## 为什么不在仓库里

这些是线上真实用户数据，**绝不能公开**。仓库通过 `.gitignore` 排除本目录下除本说明外的所有内容。

## 本地运行

`trash/trash.js` 会在启动时自动创建所需目录（`fs.mkdirSync(..., { recursive: true })`），
因此全新克隆后无需手工建目录，直接 `node trash/trash.js` 即可得到一个空数据库。

> 更新代码时**不要**把本地 `trash/data/` 覆盖到线上，否则会覆盖线上用户数据。
