/*
 * Citro Analytics — local demo dataset.
 * All people, customers, revenue, tasks and notifications below are fictional.
 * Replace this file (and the rendering layer in app.js) when connecting real APP/web data.
 */
window.CITRO_DEMO = {
  brand: "Citro",
  product: "增长分析",
  scope: "APP + 网页",
  demoAsOf: "2026-10-25",
  defaultRange: "30d",
  disclaimer:
    "所有品牌、成员、客户、收入、任务与通知数据均为虚构演示内容，仅用于展示界面与交互，不代表真实业务表现。",

  ranges: [
    {
      id: "7d",
      label: "近 7 天",
      start: "2026-10-19",
      end: "2026-10-25",
      periodLabel: "2026.10.19 — 2026.10.25",
      compareLabel: "较前 7 天",
      granularity: "按日汇总",
      metrics: [
        {
          id: "mrr",
          label: "月度经常性收入",
          value: 477800,
          kind: "currency",
          change: 1.9,
          changeUnit: "%",
          goodWhen: "up",
          spark: [469, 472, 468, 474, 471, 476, 478]
        },
        {
          id: "customers",
          label: "活跃客户",
          value: 3764,
          kind: "integer",
          change: 2.1,
          changeUnit: "%",
          goodWhen: "up",
          spark: [3652, 3671, 3660, 3698, 3712, 3740, 3764]
        },
        {
          id: "nrr",
          label: "净留存率",
          value: 110.8,
          kind: "percent",
          change: 0.6,
          changeUnit: "pt",
          goodWhen: "up",
          spark: [108.7, 109.1, 109.4, 109.2, 110.1, 110.4, 110.8]
        },
        {
          id: "churn",
          label: "流失率",
          value: 0.4,
          kind: "percent",
          change: -0.1,
          changeUnit: "pt",
          goodWhen: "down",
          spark: [0.8, 0.7, 0.6, 0.7, 0.5, 0.5, 0.4]
        }
      ],
      revenue: {
        previousTotal: 109400,
        points: [
          { date: "2026-10-19", label: "10/19", value: 15200 },
          { date: "2026-10-20", label: "10/20", value: 16800 },
          { date: "2026-10-21", label: "10/21", value: 14600 },
          { date: "2026-10-22", label: "10/22", value: 18100 },
          { date: "2026-10-23", label: "10/23", value: 17400 },
          { date: "2026-10-24", label: "10/24", value: 19200 },
          { date: "2026-10-25", label: "10/25", value: 16700 }
        ]
      },
      plans: [
        { key: "starter", name: "Starter 入门", value: 96400, color: "#c2ad82" },
        { key: "growth", name: "Growth 成长", value: 216700, color: "#1b1d22" },
        { key: "scale", name: "Scale 规模", value: 164700, color: "#687a54" }
      ]
    },
    {
      id: "30d",
      label: "近 30 天",
      start: "2026-09-26",
      end: "2026-10-25",
      periodLabel: "2026.09.26 — 2026.10.25",
      compareLabel: "较前 30 天",
      granularity: "每 3 天汇总",
      metrics: [
        {
          id: "mrr",
          label: "月度经常性收入",
          value: 482600,
          kind: "currency",
          change: 8.2,
          changeUnit: "%",
          goodWhen: "up",
          spark: [451, 458, 455, 464, 461, 469, 474, 472, 477, 480, 483]
        },
        {
          id: "customers",
          label: "活跃客户",
          value: 3842,
          kind: "integer",
          change: 6.4,
          changeUnit: "%",
          goodWhen: "up",
          spark: [3610, 3632, 3650, 3678, 3694, 3711, 3740, 3768, 3789, 3810, 3842]
        },
        {
          id: "nrr",
          label: "净留存率",
          value: 112.4,
          kind: "percent",
          change: 2.1,
          changeUnit: "pt",
          goodWhen: "up",
          spark: [108.9, 109.6, 110.1, 111.0, 110.8, 111.2, 111.9, 111.6, 112.0, 112.2, 112.4]
        },
        {
          id: "churn",
          label: "流失率",
          value: 1.8,
          kind: "percent",
          change: -0.3,
          changeUnit: "pt",
          goodWhen: "down",
          spark: [2.4, 2.2, 2.1, 2.0, 2.1, 2.0, 1.9, 2.0, 1.9, 1.8, 1.8]
        }
      ],
      revenue: {
        previousTotal: 470100,
        points: [
          { date: "2026-09-26", label: "9/26", value: 39400 },
          { date: "2026-09-29", label: "9/29", value: 42100 },
          { date: "2026-10-02", label: "10/02", value: 41800 },
          { date: "2026-10-05", label: "10/05", value: 46300 },
          { date: "2026-10-08", label: "10/08", value: 44900 },
          { date: "2026-10-11", label: "10/11", value: 48200 },
          { date: "2026-10-14", label: "10/14", value: 50700 },
          { date: "2026-10-17", label: "10/17", value: 49800 },
          { date: "2026-10-20", label: "10/20", value: 52400 },
          { date: "2026-10-23", label: "10/23", value: 55100 },
          { date: "2026-10-25", label: "10/25", value: 53600 }
        ]
      },
      plans: [
        { key: "starter", name: "Starter 入门", value: 92800, color: "#c2ad82" },
        { key: "growth", name: "Growth 成长", value: 221600, color: "#1b1d22" },
        { key: "scale", name: "Scale 规模", value: 168200, color: "#687a54" }
      ]
    },
    {
      id: "90d",
      label: "近 90 天",
      start: "2026-07-28",
      end: "2026-10-25",
      periodLabel: "2026.07.28 — 2026.10.25",
      compareLabel: "较前 90 天",
      granularity: "每周汇总",
      metrics: [
        {
          id: "mrr",
          label: "月度经常性收入",
          value: 468900,
          kind: "currency",
          change: 18.7,
          changeUnit: "%",
          goodWhen: "up",
          spark: [398, 402, 411, 414, 421, 426, 432, 438, 441, 449, 455, 461, 469]
        },
        {
          id: "customers",
          label: "活跃客户",
          value: 3698,
          kind: "integer",
          change: 14.2,
          changeUnit: "%",
          goodWhen: "up",
          spark: [3238, 3270, 3312, 3348, 3382, 3420, 3459, 3488, 3512, 3550, 3592, 3644, 3698]
        },
        {
          id: "nrr",
          label: "净留存率",
          value: 109.6,
          kind: "percent",
          change: 3.4,
          changeUnit: "pt",
          goodWhen: "up",
          spark: [106.2, 106.8, 107.1, 107.0, 107.6, 108.0, 108.4, 108.2, 108.8, 109.0, 109.1, 109.4, 109.6]
        },
        {
          id: "churn",
          label: "流失率",
          value: 5.4,
          kind: "percent",
          change: -1.1,
          changeUnit: "pt",
          goodWhen: "down",
          spark: [6.5, 6.4, 6.2, 6.3, 6.0, 5.9, 5.8, 5.9, 5.7, 5.6, 5.5, 5.5, 5.4]
        }
      ],
      revenue: {
        previousTotal: 1402300,
        points: [
          { date: "2026-07-28", label: "7/28", value: 102400 },
          { date: "2026-08-04", label: "8/04", value: 108100 },
          { date: "2026-08-11", label: "8/11", value: 111700 },
          { date: "2026-08-18", label: "8/18", value: 106300 },
          { date: "2026-08-25", label: "8/25", value: 115900 },
          { date: "2026-09-01", label: "9/01", value: 118400 },
          { date: "2026-09-08", label: "9/08", value: 114200 },
          { date: "2026-09-15", label: "9/15", value: 122600 },
          { date: "2026-09-22", label: "9/22", value: 120800 },
          { date: "2026-09-29", label: "9/29", value: 126400 },
          { date: "2026-10-06", label: "10/06", value: 124100 },
          { date: "2026-10-13", label: "10/13", value: 130200 },
          { date: "2026-10-20", label: "10/20", value: 127800 }
        ]
      },
      plans: [
        { key: "starter", name: "Starter 入门", value: 101500, color: "#c2ad82" },
        { key: "growth", name: "Growth 成长", value: 207400, color: "#1b1d22" },
        { key: "scale", name: "Scale 规模", value: 160000, color: "#687a54" }
      ]
    }
  ],

  tasks: [
    {
      id: "task-1",
      title: "复核本周新增收入的渠道归因",
      group: "增长",
      due: "今天 17:30",
      owner: "周然",
      priority: "高",
      done: false
    },
    {
      id: "task-2",
      title: "整理 10 月流失客户回访名单",
      group: "客户成功",
      due: "明天",
      owner: "何沐",
      priority: "中",
      done: false
    },
    {
      id: "task-3",
      title: "更新套餐收入看板的指标口径",
      group: "数据",
      due: "10/28",
      owner: "林雅",
      priority: "中",
      done: true
    },
    {
      id: "task-4",
      title: "检查 APP 新版本的埋点事件清单",
      group: "产品",
      due: "10/29",
      owner: "陈序",
      priority: "高",
      done: false
    }
  ],

  team: [
    { id: "lin", name: "林雅", role: "运营负责人", initials: "林", status: "online", statusLabel: "在线", load: 68 },
    { id: "zhou", name: "周然", role: "增长产品", initials: "周", status: "online", statusLabel: "在线", load: 74 },
    { id: "chen", name: "陈序", role: "客户端工程", initials: "陈", status: "focus", statusLabel: "专注中", load: 82 },
    { id: "he", name: "何沐", role: "客户成功", initials: "何", status: "offline", statusLabel: "离线", load: 57 }
  ],

  notifications: [
    {
      id: "note-1",
      title: "套餐升级信号增多",
      body: "过去 7 天有 18 个 Starter 账户访问了升级页，可以安排一轮回访。",
      tag: "增长",
      time: "10 分钟前",
      unread: true
    },
    {
      id: "note-2",
      title: "网页端转化率上升 4.8%",
      body: "定价页到注册页的转化率较上周提升，渠道表现值得继续观察。",
      tag: "渠道",
      time: "42 分钟前",
      unread: true
    },
    {
      id: "note-3",
      title: "6 位客户进入流失预警",
      body: "客户成功队列新增高优先级回访对象，建议今天完成第一轮联系。",
      tag: "客户",
      time: "2 小时前",
      unread: true
    },
    {
      id: "note-4",
      title: "演示数据已完成对账",
      body: "本页使用的本地演示数据集已准备好，可以开始查看 APP 与网页模拟汇总。",
      tag: "系统",
      time: "今天 09:10",
      unread: false
    }
  ]
};
