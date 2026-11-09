# 日历倒数日 / 纪念日云端同步接口

客户端按 `/api/todo`、`/api/ledger` 完全同构的方式读写：整包保存、服务端返回最后更新时间 `at`、客户端用 `updatedAt` 后写胜出合并。服务端实现位于 `trash/trash.js` 的 `/api/calendar`。

## 鉴权

与其他业务接口一致：

- Header：`X-Trash-Token: <登录 token>`
- 未登录或 token 失效：`401`

## GET /api/calendar

成功响应：

```json
{
  "calendar": {
    "marks": [
      {
        "id": "cal-1730000000000000",
        "title": "妈妈生日",
        "date": "1990-05-20",
        "kind": "anniversary",
        "yearly": true,
        "note": "提前订蛋糕",
        "createdAt": 1730000000000
      },
      {
        "id": "cal-1730000000000001",
        "title": "出发去大理",
        "date": "2026-12-01",
        "kind": "countdown",
        "yearly": false,
        "note": "",
        "createdAt": 1730000000000001
      }
    ],
    "updatedAt": 1730000000000000
  },
  "at": 1730000000000000
}
```

- 从未同步过时返回 `{"calendar": null, "at": 0}`。
- `at` 是服务端保存的毫秒时间戳，客户端以它判断远端是否更新。
- `marks` 为空数组代表用户主动删空了，不能当成“从未同步”。

## POST /api/calendar

请求：

```json
{
  "calendar": {
    "marks": [],
    "updatedAt": 1730000000000
  }
}
```

成功响应：

```json
{ "ok": true, "at": 1730000000000001 }
```

服务端应当：

1. 校验 `X-Trash-Token`，把数据按用户隔离保存。
2. 保存 `updatedAt`，并在响应里返回服务端时间 `at`。
3. 对未知字段保持透传，便于客户端升级。

## 字段说明

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 客户端生成的唯一 id（`cal-` 前缀） |
| `title` | string | 日子名称，1–20 字 |
| `date` | string | `YYYY-MM-DD`，倒数日的目标日或纪念日的起始日 |
| `kind` | string | `countdown` 倒数日 / `anniversary` 纪念日 |
| `yearly` | bool | 是否每年按月日重复 |
| `note` | string | 备注，最多 40 字，可为空 |
| `createdAt` | int | 创建时间（毫秒时间戳） |
| `updatedAt` | int | 整包最后修改时间（毫秒时间戳） |

> 客户端离线时只写本地 `citro_calendar_marks_v1`，登录后自动对齐云端；服务端未部署时功能不受影响，只是显示「仅本机」。