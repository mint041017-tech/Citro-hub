# 记账云同步接口契约

客户端按与 `/api/todo` 完全同构的方式读写账本：整包保存、服务端返回最后更新时间 `at`，
客户端用 `updatedAt` 做后写胜合并。服务端实现位于 `trash/trash.js` 的 `/api/ledger`，
未登录或服务不可用时客户端自动使用本地缓存，功能不受影响。

## 鉴权

与其他业务接口一致：

- Header：`X-Trash-Token: <登录 token>`
- 未登录/ token 失效：`401`

## GET /api/ledger

成功响应：

```json
{
  "ledger": {
    "entries": [
      {
        "id": "exp-1730000000000000",
        "kind": "expense",
        "amount": 1850,
        "category": "food",
        "note": "午饭",
        "occurredAt": 1730000000000,
        "createdAt": 1730000000000,
        "source": "manual"
      }
    ],
    "categories": [
      {
        "id": "food",
        "name": "餐饮",
        "kind": "expense",
        "color": 4290738762,
        "icon": "fork",
        "builtIn": true,
        "active": true
      }
    ],
    "plans": {
      "2026-11": {
        "budget": 300000,
        "income": 1000000,
        "categoryBudgets": { "food": 80000 }
      }
    },
    "updatedAt": 1730000000000
  },
  "at": 1730000000000
}
```

- 从未同步过时返回 `{"ledger": null, "at": 0}`。
- `at` 是服务端保存的毫秒时间戳，客户端以它判断远端是否更新。
- 所有金额字段单位为「分」的整数，不要用浮点。

## POST /api/ledger

请求：

```json
{
  "ledger": {
    "entries": [],
    "categories": [],
    "plans": {},
    "updatedAt": 1730000000000
  }
}
```

成功响应：

```json
{ "ok": true, "at": 1730000001000 }
```

服务端应：

1. 校验 `X-Trash-Token`，把数据按用户隔离保存（整包或按表拆开均可）。
2. 保存 `updatedAt`，并在响应里返回服务端时间 `at`；客户端下次 GET 用 `at > updatedAt` 判断是否覆盖本地。
3. 对未知字段保持透传，便于客户端升级。

## 字段说明

### entries

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 客户端生成的唯一 id（`exp-` / `inc-` 前缀） |
| `kind` | `expense` / `income` | 收支类型 |
| `amount` | int | 金额，单位分，必须大于 0 |
| `category` | string | 分类 id |
| `note` | string | 备注，最长 40 字 |
| `occurredAt` | int | 账单发生时间（毫秒） |
| `createdAt` | int | 记录创建时间（毫秒） |
| `source` | `manual` / `scan` / `cici` | 录入来源 |

### categories

`color` 为 ARGB 整数；`builtIn=true` 的分类只能隐藏（`active=false`），客户端不允许硬删除。
服务端如果自行维护默认分类，请确保 id 与客户端一致：`food / transport / shopping / home / fun / health / study / social / other_expense`，收入 `salary / bonus / invest / parttime / gift / other_income`。

### plans

键为 `yyyy-MM`。`budget` 为总支出预算，`income` 为收入目标，`categoryBudgets` 为分类预算。
金额单位均为分；0 或缺失表示未设置。

## 冲突与离线

- 客户端每次修改后 900ms 防抖推送整包；离线失败会在下一次修改时重试。
- 登录后立即拉取一次：`at > 本地 updatedAt` 时覆盖本地，否则把本地推上去。
- 冲突策略与待办一致：整包后写胜。若后续需要多端同时编辑，请在服务端按 `updatedAt` 增量合并，并保持响应结构不变。