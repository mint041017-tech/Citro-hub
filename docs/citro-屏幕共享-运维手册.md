# Citro 屏幕共享 · 运维手册

配套方案：`citro-屏幕共享-cloudflare升级方案.md`

本手册只写「怎么部署、怎么观察、怎么救火」。架构与成本见方案文档。

---

## 1. 架构速览

```
App（Flutter）  ──REST/WS──>  Cloudflare Worker（citro-screen-share）
                                  │
                                  ├── Durable Object：Room（房间状态 + 事件广播）
                             
 ┌───────────────────────────────┘
                                  └── Cloudflare Realtime SFU（媒体，不过 Worker）
                                       ↑
                        网页观众端（public/index.html）
```

- **信令**：Worker + Durable Object，只搬几 KB 的 JSON。
- **媒体**：Cloudflare Realtime SFU，P2P 不通时走 Cloudflare TURN。
- **密钥**：全部只在 Worker / SFU 侧，客户端永远拿不到 App Secret。

---

## 2. 前置条件

| 项目 | 说明 |
|---|---|
| Cloudflare 账号 | 已开通 Workers Paid（$5/月，DO 与静态资源需要） |
| Realtime 应用 | Dashboard → Realtime → 新建应用，拿到 **App ID** 与 **App Secret** |
| TURN Key | Dashboard → Realtime → TURN Keys，拿到 **Key ID** 与 **Key Secret** |
| wrangler | `npm i -g wrangler`，或仓库内 `npx wrangler` |
| 登录 | `wrangler login`（浏览器授权一次即可） |

> 没有 TURN Key 也能跑通大部分网络（STUN + host/srflx），但对称 NAT 下会失败。
> 大陆网络下 TURN 大概率是必需的，**不要跳过**。

---

## 3. 密钥清单

全部通过 `wrangler secret put` 设置，**绝不写进 `wrangler.toml` 或入库**。

| 变量 | 必填 | 作用 | 不配的后果 |
|---|---|---|---|
| `CF_REALTIME_APP_ID` | ✅ | SFU 应用 ID | 所有发布/订阅报「未配置」 |
| `CF_REALTIME_APP_SECRET` | ✅ | SFU 应用密钥 | 同上 |
| `CF_TURN_KEY_ID` | 建议 | 生成短期 TURN 凭证 | 回落到仅 STUN，对称 NAT 失败 |
| `CF_TURN_KEY_SECRET` | 建议 | 同上 | 同上 |
| `ROOM_TOKEN_SECRET` | ✅ | 签发房间 JWT（HS256） | 创建房间报 502 `sfu_error`（提示去配这个密钥） |
| `TRASH_API_BASE` | 生产必填 | 校验 `X-Trash-Token` | **不配则任何人都能创建房间** |
| `TRASH_API_SECRET` | 可选 | Worker 会带上 `X-Trash-Api-Secret`，但** trash.js 目前不校验它**（全文没有 secret 相关逻辑），所以配了也不生效 | 无 |

设置命令：

```bash
cd screen-share

wrangler secret put CF_REALTIME_APP_ID
wrangler secret put CF_REALTIME_APP_SECRET
wrangler secret put CF_TURN_KEY_ID
wrangler secret put CF_TURN_KEY_SECRET
wrangler secret put ROOM_TOKEN_SECRET
wrangler secret put TRASH_API_BASE
wrangler secret put TRASH_API_SECRET
```

每条命令会进入交互式输入，粘贴后回车。

> `ROOM_TOKEN_SECRET` 用 32 字节以上随机串：
> `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`

> **媒体密钥已配置（2026-11-14）**：`CF_REALTIME_APP_ID` /
> `CF_REALTIME_APP_SECRET` / `CF_TURN_KEY_ID` / `CF_TURN_KEY_SECRET`
> 四个都已写入 Worker（`wrangler secret list` 可见）。凭证是在 Dashboard
> 创建的（Realtime → Serverless SFU 建应用；Realtime → TURN Server 建密钥），
> 本地 `screen-share/.dev.vars` 里也有一份同值，供 `wrangler dev` 与
> vitest-pool-workers 使用。
>
> **不要试图用 API 创建 SFU 应用或 TURN 密钥**：`POST /accounts/{id}/calls/apps`
> 与 `/calls/turn_keys` 这两个接口确实存在，但本账户的 API 令牌（含 wrangler
> 的 OAuth 令牌）调用一律返回 `403 10000 Authentication error`；社区另有报告称
> 即使带了 Calls/Realtime 权限也会吃到 `10002 Authorization Failure`。所以这两样
> 只能走 Dashboard，这也是上面这四个密钥不能完全自动化的原因。
>
> 验证方式：`GET /api/ice?token=<房间 token>` 的 `iceServers` 应包含一条
> `turn:turn.cloudflare.com:...` 且带 `username` / `credential`；只返回
> `stun:` 就说明 TURN 密钥没生效。

### ⚠️ 关于 `TRASH_API_BASE`

`src/trash.ts` 里有一段本地 POC 兜底：**没有 `TRASH_API_BASE` 时，任意
`X-Trash-Token` 都会被放行成一个 `guest_xxxxxx` 身份**。

这是为了让 POC 不依赖 trash.js 就能跑通链路。**生产环境必须配置
`TRASH_API_BASE`**，否则房间创建是开放的。部署上线前请确认这一点。

本地开发在 `screen-share/.dev.vars` 里配（该文件已 gitignore）。

---

## 4. 部署

### 4.1 workers.dev：⚠️ 大陆不可用

> **2026-11-14 实测结论：`*.workers.dev` 在大陆被 DNS 污染 + SNI 重置双重阻断，
> 不能作为 POC 入口。** 方案里「先用 workers.dev 做 POC」的假设不成立。
> 媒体端点（`rtc.live.cloudflare.com` / `stun.cloudflare.com` / `turn.cloudflare.com`）
> 实测正常，所以 Cloudflare 架构本身在大陆可用，问题只在域名。

最近一次部署（2026-11-13，版本号未记录）：

```
Worker 名称   citro-screen-share
URL           https://citro-screen-share.citro.workers.dev
workers.dev   citro（已通过 API 注册，账户原本没有）
密钥          ROOM_TOKEN_SECRET / TRASH_API_BASE 已设置
```

> 仓库里不记录部署版本号，权威来源是 `npx wrangler deployments list`。
> 注意 2026-11-14 的代码改动（满员判定、错误透传、房主宽限）**还没部署上去**。

**这个 URL 只能在境外网络访问**。大陆实测：

| 解析方式 | 结果 |
|---|---|
| 中国移动 DNS | Facebook / Twitter 的 IP |
| AliDNS 223.5.5.5 | Twitter `199.16.156.38` |
| DNSPod 119.29.29.29 | Twitter `199.96.62.21` |
| AliDNS DoH / DNSPod DoH | 同样是被污染的 IP |
| 绕过 DNS 直连 Cloudflare 边缘 | TLS 握手被重置（SNI 阻断） |

### 4.2 POC 必须走自定义域名

> **域名现状（2026-11-14 更新）**：下面按 `chimu-claw.xyz` 写的迁移步骤都已经执行过，
> zone 也建好了；但之后 `chimu-claw.xyz` 的**注册局委派又回到了华为云 DNS**
> （`.xyz` 的 TLD 服务器当前一致返回 `ns1.huaweicloud-dns.*`，见 §4.4），
> 而华为云侧没有 `share` 记录，所以 `share.chimu-claw.xyz` 在公网是 NXDOMAIN。
>
> 因此**屏幕分享现在改用 `share.mint1017.cn`**：zone `cd9934c8…`（NS
> `kirk` / `tessa`）已 active，自定义域绑定 `enabled`，证书已签发，
> `https://share.mint1017.cn/` 与 `/api/health` 均返回 200，App 内的
> `kShareApiBase` 默认值与邀请链接也都指向它。
>
> `wrangler.toml` 目前**两个域都保留**：`share.chimu-claw.xyz` 作为备用，
> 哪天它的 NS 指回 Cloudflare 就能直接恢复，无需重新部署。
>
> 下面的迁移叙述依然有效（记录怎么建、为什么必须橙云），只是最终对外域名换成了
> `share.mint1017.cn`。

原始约束：账户原本**一个 zone 都没有**（`GET /zones` 返回空），而
`chimu-claw.xyz` 托管在华为云 DNS。要让 `share.*` 可用，需要先把 zone 建起来。

#### 为什么 partial（CNAME）setup 走不通

2026-11-14 查证，两条独立理由都否掉了这条路：

1. **套餐限制**：Cloudflare 官方文档明确写
   「A CNAME setup (partial) is only available to customers on a Business
   or Enterprise plan」。当前账户 `type: standard`（免费），用不了。
2. **CNAME 目标不解析**：partial setup 要求在华为云加
   `share.chimu-claw.xyz CNAME share.chimu-claw.xyz.cdn.cloudflare.net`，
   但实测 `cdn.cloudflare.net` 与 `share.chimu-claw.xyz.cdn.cloudflare.net`
   都查不到 A/AAAA 记录（8.8.8.8 如此，Cloudflare 自己的权威 NS 也如此）。
   注：也不排除要等 zone 建好后才会应答，但既然卡在套餐上，这条已无关紧要。

另外，`wrangler login` 的 OAuth token 只有 `zone (read)`，**没有 `zone (edit)`**，
用它永远建不了 zone —— 必须去 Dashboard 建一个 API Token。

#### 可行路径：整域迁到 Cloudflare（Free 即可）

Workers Custom Domains 在 Free 套餐可用，唯一前提是**同账户下有 active zone**。
所以把 `chimu-claw.xyz` 的 NS 换成 Cloudflare 的就行，不需要升级套餐。

**关键是代理记录会被 CNAME 展平。** 官方文档：

> Proxied records are flattened by default as they return Cloudflare anycast IPs.

也就是说 `share.chimu-claw.xyz` 解析出来直接是 Cloudflare 边缘 IP，
**客户端的递归 DNS 根本不会去查 `*.workers.dev`**，TLS SNI 也是
`share.chimu-claw.xyz`（未被阻断）。这是大陆能用的关键，也是整域迁移
风险可控的原因。

**`chimu-claw.xyz` zone 记录清单（2026-11-14 实测，共 6 条）**：

| 记录 | 类型 | 值 | 迁移后是否代理 |
|---|---|---|---|
| `chimu-claw.xyz` | A | `110.41.11.107` | 否（灰云） |
| `www.chimu-claw.xyz` | A | `110.41.11.107` | 否（灰云） |
| `dl.chimu-claw.xyz` | A | `110.41.11.107` | 否（灰云） |
| `test.chimu-claw.xyz` | A | `110.41.11.107` | 否（灰云） |
| `obs.chimu-claw.xyz` | CNAME | `citro.obs.cn-south-1.myhuaweicloud.com` | 否（灰云，OBS 不能走代理） |
| `share.chimu-claw.xyz` | AAAA | `100::`（Workers 自定义域占位记录） | **是（橙云）** |

**`mint1017.cn` zone 记录清单（2026-11-14 实测，共 1 条）**：

| 记录 | 类型 | 值 | 迁移后是否代理 |
|---|---|---|---|
| `share.mint1017.cn` | AAAA | `100::`（Workers 自定义域占位记录） | **是（橙云）** |

没有 MX / TXT / CAA / SRV / DMARC / DKIM，注册商处也没有 DS 记录
（即**未启用 DNSSEC**），所以迁移不会碰到邮箱和 DNSSEC 的坑。

> 现有记录全部设为 **DNS only（灰云）**，流量还是直连华为云，主站行为
> 完全不变；只有新加的 `share` 一条走 Cloudflare 代理。

#### 操作顺序

1. Dashboard 建 API Token（需要 `zone:edit` / `dns:edit` / `workers_routes:write`）；
2. 用 API 建 `chimu-claw.xyz` 的 **full zone**，拿到 Cloudflare 分配的 NS；
3. 在 Cloudflare 里把上面 4 条记录建好（灰云），再加 `share`（橙云）；
4. 去注册商把 NS 改成 Cloudflare 的（华为云 DNSPod / 注册商控制台）；
5. 等 zone 变 active，验证主站与 `obs` 都没事；
6. `wrangler.toml` 里把 `routes` 取消注释，重新 `wrangler deploy`。

> 第 1、4 步需要账号权限，是当前唯一卡住的环节。

### 4.3 验证部署

```bash
# 静态页
curl -I https://<域名>/
# 应返回 200 text/html，且包含「加入房间」

# 健康检查
curl https://<域名>/api/health
# {"ok":true,...}

# 创建房间（必须带 X-Trash-Token；只有本地 POC —— 未配 TRASH_API_BASE —— 才任意值都放行）
curl -X POST https://<域名>/api/rooms \
  -H 'Content-Type: application/json' \
  -H 'X-Trash-Token: <你的 token>' \
  -d '{"title":"联调","roomType":"one_to_many"}'
```

浏览器打开 `https://<域名>/?room=<6位码>`，应能看到「等待主持人开始共享」。

---

### 4.4 chimu-claw.xyz 委派回归：症状与排查（2026-11-14）

`chimu-claw.xyz` 的 zone 建好后曾正常服务 `share.chimu-claw.xyz`；之后**注册局
委派又变回华为云 DNS**，导致该子域在公网变成 NXDOMAIN。Cloudflare 侧一切正常，
所以这类故障只能从注册局查。

**确认委派（不要只看递归解析器 —— 它们会缓存负答案）**：直连 `.xyz` 的 TLD
服务器读 Authority 段。先用 DoH 查 `xyz` 的 NS 拿到 IP
（`x.nic.xyz` / `y.nic.xyz` / `z.nic.xyz` / `generationxyz.nic.xyz`），
再直连 UDP 53 问 `chimu-claw.xyz` 的 NS。

2026-11-14 实测：4 台 TLD 服务器一致返回 `ns1.huaweicloud-dns.{org,cn,com,net}`；
Google / Cloudflare / AliDNS 三家 DoH 的 NS 答案也一致 —— 委派确实在华为云。

**症状特征**：

| 观测点 | 表现 |
|---|---|
| Cloudflare zone / 绑定 / 证书 | 全部正常（`active`、`enabled`、证书在） |
| 直连 Cloudflare 边缘 IP + SNI | 仍然 200（边缘认得这个 hostname） |
| 公网递归 | `share.chimu-claw.xyz` NXDOMAIN |
| 同 zone 其他名字（apex / www / dl / test） | 正常（华为云 DNS 里那些记录还在） |
| 直接问 Cloudflare 的权威 NS | 有记录（自建自答） |

「问 Cloudflare NS 有、问公网没有」是这个故障的典型特征 —— 说明 zone 没坏，
坏的是委派。

**修复**：去注册商把 `chimu-claw.xyz` 的 DNS 服务器改回
`eleanor.ns.cloudflare.com` / `kareem.ns.cloudflare.com`。
当前屏幕分享不依赖它（走 `share.mint1017.cn`），所以不是紧急项。

---

## 5. 房间生命周期

| 事件 | 行为 |
|---|---|
| 创建 | DO `/internal/reset`，写入 `expiresAt` 并 `setAlarm` |
| 加入 | 满 50 人拒绝（`ROOM_MAX_VIEWERS`）；房主重连不占名额 |
| 到期 | DO alarm 触发 → 状态置 `ended` → 广播 → 关闭所有 WS → 删库 |
| 主持人结束 | REST `/end` → 关闭所有 SFU session → 同上 |
| 断开 | WS 断开只标记该成员离线；**SFU session 保留**，重连可续 |
| 房主断线 | 还有观众在线时，把 DO 闹钟改成 `now + HOST_GRACE_MINUTES`（默认 5 分钟）；房主重连则恢复成 `expiresAt`。宽限超时按「主持人已断开连接」回收 |

**房间存活时长**由 `ROOM_TTL_HOURS`（默认 12）控制。房间结束时 `closeAll()` 直接
`deleteAll()` 清空 DO 存储并断开所有 WS，不再另设闹钟。

### SFU session 的回收

Cloudflare **没有 DELETE session 接口**。拆 session 靠：

1. `PUT /sessions/{id}/tracks/close`，`force: true` 逐路关掉（`closeSession()`）；
2. 客户端断开 `RTCPeerConnection`。

session 本身在 30 秒无媒体后被 SFU 回收。因此**客户端退出时必须主动调
`/leave`**，否则会留下最多 30 秒的孤儿 session。

---

## 6. 监控与告警

### 6.1 现在能看的

- `wrangler tail`：实时看 Worker 日志与异常。
- Cloudflare Dashboard → Realtime：流量、会话数、错误率。
- Cloudflare Dashboard → Workers → 用量。

```bash
npx wrangler tail          # 实时日志
npx wrangler tail --format pretty
```

### 6.2 方案里要求、但尚未实现的部分

方案 §10 的验收标准要求「每月出口流量报表；800 GB 预警；超过 1 TB 自动限流
或提醒」。**这三项目前没有实现**，需要接 Cloudflare GraphQL Analytics API
加一个定时 Worker。

在补齐之前，建议人工每周看一次 Dashboard 的流量面板。免费额度是 1 TB/月
（SFU 与 TURN 共享），超出按 $0.05/GB 计。

### 6.3 关键告警阈值（建议）

| 指标 | 阈值 | 动作 |
|---|---|---|
| SFU 出口流量 | 800 GB/月 | 预警，检查是否有异常房间 |
| 房间创建失败率 | > 5% | 看 trash.js 可用性 |
| Worker 5xx | > 1% | `wrangler tail` 定位 |
| 平均加入耗时 | > 3 s | 检查 DO 冷启动 / 网络 |

---

## 7. 故障处理

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 创建房间 502 `sfu_error`「未配置 ROOM_TOKEN_SECRET」 | 没配 `ROOM_TOKEN_SECRET` | `wrangler secret put ROOM_TOKEN_SECRET` |
| 发布 / 订阅报 502 `sfu_error` | 没配或配错 `CF_REALTIME_APP_ID` / `CF_REALTIME_APP_SECRET` | 配对这两个密钥。注意**创建房间不校验它们**，所以房间能建、能进，但一发布就失败 |
| 房间能建但没画面 | SFU session 未建立 | 看 `wrangler tail`；确认 App Secret 有效 |
| 订阅报 410 | SFU session 已失效 | 客户端新建 session 重试（正常兜底） |
| 订阅报 425 | PeerConnection 还没连上 | 稍后重试 |
| 订阅报 406 | 同一 session 并发 mutation | 检查客户端是否串行化 SDP 交换 |
| 观众听不到声音 | 只订阅了 `screen`，没订阅 `mic` | 订阅两路；或确认主持人开了麦克风 |
| 网页端进不去房间 | 房间码错 / 房间已结束 | 页面会提示具体错误 |
| 网页端一直在「等待主持人」 | 主持人在另一房间 / 未开始共享 | 核对房间码 |
| Android 共享黑屏 | 没走前台服务 | 确认 `ScreenCaptureService` 已起、权限已授 |
| 大陆网络卡顿 | 无大陆节点 | 降到 720p30（2.5 Mbps，已是最低档）；确认 TURN 生效 |

---

## 8. 常用命令

```bash
# 本地开发（读 .dev.vars，无需真实密钥）
cd screen-share
npm run dev

# 类型检查 / 测试
npm run typecheck
npm test

# 部署（用本机 wrangler OAuth 登录即可；.cf-token 里的 API Token
# 没有 Workers 权限，设成 CLOUDFLARE_API_TOKEN 会报 No access）
npx wrangler deploy

# 实时日志
npx wrangler tail
```

### Flutter 侧

```bash
# POC：指向 workers.dev
flutter build apk --debug --dart-define=SHARE_API_BASE=https://<子域>.workers.dev

# 正式：默认就是 https://share.mint1017.cn，无需 define
flutter build apk --release
```

---

## 9. 上线前 checklist

- [ ] `TRASH_API_BASE` 已配置（**否则房间创建是开放的**）
- [ ] `ROOM_TOKEN_SECRET` 已配置且与本地不同
- [ ] TURN Key 已配置
- [ ] `share.mint1017.cn` DNS 已接入 Cloudflare（当前域名）
- [ ] App 的 `SHARE_API_BASE` 与线上一致
- [ ] Android release 已配 ProGuard（flutter_webrtc 自带 consumer rules）
- [ ] 大陆三大运营商网络实测通过（方案 §7.2 矩阵）
- [ ] 流量告警已配置（或已安排人工巡检）
