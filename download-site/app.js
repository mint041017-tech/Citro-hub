const PLATFORM_ICONS = {
  windows: `
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M3 5.2 10.8 4v7.2H3V5.2Zm9 1.5L21 5v6.2h-9V6.7ZM3 12.4h7.8V20L3 18.8v-6.4Zm9 0h9V19l-9-1.5v-5.1Z"></path>
    </svg>`,
  android: `
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="7" y="2.5" width="10" height="19" rx="2.5"></rect>
      <path d="M10.5 5.5h3M11 18.5h2"></path>
    </svg>`,
};

const ICONS = {
  download: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12m0 0 4.5-4.5M12 15l-4.5-4.5M5 20h14"></path></svg>`,
  external: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 4h6v6M20 4l-9 9M18 14v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4"></path></svg>`,
  arrow: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"></path></svg>`,
  info: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M12 8v5M12 17h.01"></path></svg>`,
  downloadSmall: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v11m0 0 4-4m-4 4-4-4M5 20h14"></path></svg>`,
};

const APPS = [
  {
    platform: "windows",
    badge: "桌面端",
    name: "Citro for Windows",
    desc: "iPad 同款界面，窗口缩放和宽屏自适应都安排好了。资源库、社区、小游戏与更新能力全部在桌面端。",
    version: "v1.9.8",
    sizeBytes: 21989766,
    system: "Windows 10 / 11",
    format: "EXE",
    url: "https://obs.chimu-claw.xyz/exe/Citro-v1.9.8-win64-setup.exe",
    sha256: "0f967539537a54d7a8fa3462868491ede2c2f57a271d6aa6ae3a3bf33536315b",
    warning: "安装包暂未代码签名，SmartScreen 可能提示“未知发布者”；安装到当前用户目录，无需管理员权限。",
    file: "Citro-v1.9.8-win64-setup.exe",
    keywords: "windows win 桌面 电脑 客户端 安装包 更新 静默安装",
  },
  {
    platform: "android",
    badge: "移动端",
    name: "Citro for Android",
    desc: "手机上的 Citro，原生界面、小游戏、社区、食谱和星象都在。装好后可以在 App 内直接检查下一版。",
    version: "v1.9.8",
    sizeBytes: 90309532,
    system: "Android 8.0+",
    format: "APK",
    url: "https://obs.chimu-claw.xyz/APK/Citro-v1.9.8-release.apk",
    sha256: "714f71f975cf104920be4d237419f3b93f5a5d95d7c1e1469276615ba5e31800",
    warning: "通用 ABI 安装包，已使用 Citro 发布签名；安装未知来源应用时，请在系统设置中允许本次安装。",
    file: "Citro-v1.9.8-release.apk",
    keywords: "android 安卓 手机 移动端 apk 安装包 更新",
  },
];

const MODS = [
  {
    name: "REPO",
    desc: "《REPO》整合模组，前置齐全、汉化到位，开黑即装即玩。",
    tag: "整合包",
    sizeBytes: 3292063755,
    cover: "assets/mods/mod-repo.jpg",
    file: "REPO.zip",
    url: "https://obs.chimu-claw.xyz/MOD/REPO.zip",
    keywords: "repo 整合 联机 开黑 汉化",
  },
  {
    name: "雨中冒险2",
    desc: "UES 优化整合包，帧数更稳、跑图更顺，联机体验拉满。",
    tag: "性能优化",
    sizeBytes: 53561235,
    cover: "assets/mods/mod-risk2.jpg",
    file: "雨中冒险2 UES优化.zip",
    url: "https://obs.chimu-claw.xyz/MOD/%E9%9B%A8%E4%B8%AD%E5%86%92%E9%99%A92%20UES%E4%BC%98%E5%8C%96.zip",
    keywords: "雨中冒险2 risk of rain 2 ror2 ues 优化 帧数",
  },
  {
    name: "与友赌博",
    desc: "把赌场搬进游戏，和朋友欢乐梭哈，输了请客那种。",
    tag: "趣味玩法",
    sizeBytes: 32610187,
    cover: "assets/mods/mod-gamble.jpg",
    file: "与友赌博.zip",
    url: "https://obs.chimu-claw.xyz/MOD/%E4%B8%8E%E5%8F%8B%E8%B5%8C%E5%8D%9A.zip",
    keywords: "赌博 赌场 趣味 联机 欢乐",
  },
  {
    name: "PEAK",
    desc: "登山冒险整合 Mod，中文化与功能模组一步到位，开箱即玩。",
    tag: "整合包",
    sizeBytes: 91763815,
    cover: "assets/mods/mod-peak.jpg",
    file: "PEAK.zip",
    url: "https://obs.chimu-claw.xyz/MOD/PEAK.zip",
    keywords: "peak 登山 冒险 整合 中文化",
  },
  {
    name: "迷魅狩猎",
    desc: "神秘狩猎玩法扩展，给探险加点意想不到的邪门乐趣。",
    tag: "玩法扩展",
    sizeBytes: 15741533,
    cover: "assets/mods/mod-hunt.jpg",
    file: "迷魅狩猎.zip",
    url: "https://obs.chimu-claw.xyz/MOD/%E8%BF%B7%E9%AD%85%E7%8B%A9%E7%8C%8E.zip",
    keywords: "迷魅狩猎 狩猎 探险 玩法 扩展",
  },
  {
    name: "崩溃小队",
    desc: "混乱多人乱斗模组，场面越崩越快乐，适合整活之夜。",
    tag: "多人乱斗",
    sizeBytes: 1449969,
    cover: "assets/mods/mod-crash.jpg",
    file: "崩溃小队.zip",
    url: "https://obs.chimu-claw.xyz/MOD/%E5%B4%A9%E6%BA%83%E5%B0%8F%E9%98%9F.zip",
    keywords: "崩溃小队 多人 乱斗 整活 派对",
  },
];

const TOOLS = [
  {
    name: "万兴优转",
    desc: "视频格式转换与压缩，处理录屏和素材很顺手。",
    category: "装机必备",
    mark: "转",
    links: [{ label: "下载", meta: "ZIP", bytes: 361154255, kind: "download", url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/%E4%B8%87%E5%85%B4%E4%BC%98%E8%BD%AC.zip" }],
    keywords: "视频 转换 压缩 录制 素材 万兴",
  },
  {
    name: "DirectX 修复工具",
    desc: "一键修补 DirectX 运行库，解决游戏启动报错。",
    category: "装机必备",
    mark: "DX",
    links: [{ label: "下载", meta: "ZIP", bytes: 217528158, kind: "download", url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/DirectX_Repair.zip" }],
    keywords: "directx dx 运行库 修复 报错 dll 游戏",
  },
  {
    name: "图吧工具箱",
    desc: "硬件检测、烤机和系统信息，装机和排障都能用。",
    category: "装机必备",
    mark: "图",
    links: [{ label: "下载", meta: "EXE", bytes: 197547422, kind: "download", url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/%E5%9B%BE%E5%90%A7%E5%B7%A5%E5%85%B7%E7%AE%B1.exe" }],
    keywords: "图吧 硬件 检测 烤机 cpu 显卡 装机",
  },
  {
    name: "Office Tool",
    desc: "Office 部署、激活与版本管理，一个工具管明白。",
    category: "装机必备",
    mark: "OT",
    links: [{ label: "下载", meta: "ZIP", bytes: 77838370, kind: "download", url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/Office_Tool.zip" }],
    keywords: "office word excel ppt 激活 部署",
  },
  {
    name: "TreeSize",
    desc: "查清磁盘空间被谁吃了，大文件夹一目了然。",
    category: "装机必备",
    mark: "TS",
    links: [{ label: "下载", meta: "7Z", bytes: 30923172, kind: "download", url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/TreeSize.7z" }],
    keywords: "磁盘 空间 清理 文件夹 硬盘 treesize",
  },
  {
    name: "Bandizip",
    desc: "免费好用的压缩软件，压缩包预览和分卷都方便。",
    category: "装机必备",
    mark: "BZ",
    links: [{ label: "下载", meta: "EXE", bytes: 11285533, kind: "download", url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/Bandizip.exe" }],
    keywords: "压缩 解压 zip rar 7z 分卷 bandizip",
  },
  {
    name: "Geek Uninstaller",
    desc: "轻量级软件卸载，顺手清掉残留注册表和目录。",
    category: "装机必备",
    mark: "G",
    links: [{ label: "下载", meta: "EXE", bytes: 7020016, kind: "download", url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/geek.exe" }],
    keywords: "卸载 残留 清理 软件 geek uninstaller",
  },
  {
    name: "Twinkle Tray",
    desc: "给没有物理按键的显示器一个顺手的亮度调节入口。",
    category: "装机必备",
    mark: "TT",
    links: [{ label: "下载", meta: "EXE", bytes: 1106976, kind: "download", url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/Twinkle%20Tray.exe" }],
    keywords: "显示器 亮度 调节 twinkle tray 屏幕",
  },
  {
    name: "Steam",
    desc: "官方客户端，或者开箱即用的游戏管家版本，按需选。",
    category: "游戏平台",
    mark: "S",
    links: [
      { label: "Steam 官方版", meta: "EXE", bytes: 2380800, kind: "download", url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/SteamSetup.exe" },
      { label: "游戏管家专版", meta: "EXE", bytes: 14741624, kind: "download", url: "https://obs.chimu-claw.xyz/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/Steam%E6%B8%B8%E6%88%8F%E7%AE%A1%E5%AE%B6_2.0.0.2985.exe" },
    ],
    keywords: "steam 游戏 平台 客户端 管家 正版 leo",
  },
  {
    name: "瞬投",
    desc: "游戏投掷物点位地图，查点位比翻视频快。",
    category: "游戏工具",
    mark: "投",
    links: [{ label: "打开官网", meta: "在线工具", kind: "site", url: "https://shuntou.top/" }],
    keywords: "瞬投 投掷物 点位 地图 烟雾 闪光 无畏契约",
  },
  {
    name: "瞄准专家",
    desc: "无畏契约预瞄与架枪训练地图，练枪前先热身。",
    category: "游戏工具",
    mark: "瞄",
    links: [{ label: "打开官网", meta: "在线工具", kind: "site", url: "https://ishoutu.cn/aim" }],
    warn: "打瓦的时候不要挂在后台！",
    keywords: "瞄准 预瞄 架枪 练枪 无畏契约 valorant aim",
  },
  {
    name: "KOOK",
    desc: "游戏语音沟通平台，开黑、频道和社群都能装下。",
    category: "语音与远程",
    mark: "K",
    links: [{ label: "打开官网", meta: "官方下载", kind: "site", url: "https://www.kookapp.cn/" }],
    keywords: "kook 语音 开黑 频道 游戏 聊天",
  },
  {
    name: "NN 语音",
    desc: "语音聊天社交应用，找搭子和开黑房都方便。",
    category: "语音与远程",
    mark: "NN",
    links: [{ label: "打开官网", meta: "官方下载", kind: "site", url: "https://www.nn.com/home" }],
    keywords: "nn 语音 聊天 社交 开黑 搭子",
  },
  {
    name: "UU 远程",
    desc: "网易远程控制工具，出门也能连回自己的电脑。",
    category: "语音与远程",
    mark: "UU",
    links: [{ label: "打开官网", meta: "官方下载", kind: "site", url: "https://uuyc.163.com/" }],
    keywords: "uu 远程 控制 网易 串流 电脑",
  },
  {
    name: "青柠起始页",
    desc: "简洁清爽的浏览器起始页，把常用入口收在一屏。",
    category: "装机必备",
    mark: "青",
    links: [{ label: "打开官网", meta: "在线工具", kind: "site", url: "https://www.limestart.cn/" }],
    keywords: "青柠 起始页 浏览器 主页 导航 搜索",
  },
];

const DRIVERS = [
  {
    name: "ROG 奥创中心",
    desc: "ROG 外设灯效、宏按键与性能控制客户端。",
    mark: "ROG",
    kind: "client",
    bytes: 4309912,
    format: "EXE",
    url: "https://obs.chimu-claw.xyz/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/ROG%E5%A5%A5%E5%88%9B%E4%B8%AD%E5%BF%83.exe",
    keywords: "rog 华硕 asus 奥创 灯效 键盘 鼠标 耳机",
  },
  {
    name: "罗技驱动精简版",
    desc: "去掉多余组件的罗技外设驱动包，体积更克制。",
    mark: "罗技",
    kind: "client",
    bytes: 13064344,
    format: "EXE",
    url: "https://obs.chimu-claw.xyz/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/%E7%BD%97%E6%8A%80%E9%A9%B1%E5%8A%A8%E7%B2%BE%E7%AE%80%E7%89%88.exe",
    keywords: "罗技 logitech 精简 驱动 键盘 鼠标",
  },
  {
    name: "罗技 G-HUB",
    desc: "罗技 G 系列外设管理，灯效、宏和板载配置。",
    mark: "G",
    kind: "client",
    bytes: 70346392,
    format: "EXE",
    url: "https://citro.obs.cn-south-1.myhuaweicloud.com/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/%E7%BD%97%E6%8A%80G-HUB.exe",
    keywords: "罗技 logitech ghub g hub 灯效 宏 鼠标 键盘 耳机",
  },
  {
    name: "WOOT 驱动客户端",
    desc: "Wooting 键盘的桌面客户端，用于固件和按键设置。",
    mark: "WOOT",
    kind: "client",
    bytes: 111032304,
    format: "EXE",
    url: "https://obs.chimu-claw.xyz/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/Woot%E9%A9%B1%E5%8A%A8%E5%AE%A2%E6%88%B7%E7%AB%AF.exe",
    keywords: "wooting woot 磁轴 键盘 驱动 固件",
  },
  {
    name: "雷云 4",
    desc: "雷蛇外设驱动与灯效控制，支持较新的雷蛇设备。",
    mark: "RAZER",
    kind: "client",
    bytes: 14923464,
    format: "EXE",
    url: "https://citro.obs.cn-south-1.myhuaweicloud.com/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/%E9%9B%B7%E4%BA%914.exe",
    keywords: "雷蛇 razer 雷云 4 synapse 驱动 灯效 鼠标 键盘",
  },
  {
    name: "卓威 U2 驱动",
    desc: "卓威 U2 鼠标的设置工具，调节 DPI 与回报率。",
    mark: "ZOWIE",
    kind: "client",
    bytes: 128140248,
    format: "EXE",
    url: "https://obs.chimu-claw.xyz/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/%E5%8D%93%E5%A8%81U2.exe",
    keywords: "卓威 zowie u2 鼠标 驱动 dpi 回报率",
  },
  {
    name: "奥创中心",
    desc: "华硕外设在线控制台，更新固件和调灯效。",
    mark: "ASUS",
    kind: "site",
    url: "https://gearlink.asus.com.cn/zh-cn",
    keywords: "华硕 asus 奥创 控制台 键盘 鼠标 固件",
  },
  {
    name: "雷云",
    desc: "雷蛇 Synapse 在线控制台，设备配置集中管理。",
    mark: "RAZER",
    kind: "site",
    url: "https://synapse.razer.com/dashboard/",
    keywords: "雷蛇 razer synapse 雷云 控制台 键盘 鼠标",
  },
  {
    name: "铝厂 IQUNIX",
    desc: "磁轴键盘在线设置与固件更新。",
    mark: "IQX",
    kind: "site",
    url: "https://docs.iqunix.com/Magnet_Switch",
    keywords: "iqunix 铝厂 磁轴 键盘 驱动 固件",
  },
  {
    name: "小蜜蜂 MelGeek",
    desc: "MelGeek Hive 键盘控制台，改键和灯光设置。",
    mark: "MG",
    kind: "site",
    url: "https://hive.melgeek.cn/",
    keywords: "melgeek 小蜜蜂 hive 键盘 改键 灯效",
  },
  {
    name: "ATK",
    desc: "ATK Hub 驱动中心，鼠标与键盘统一管理。",
    mark: "ATK",
    kind: "site",
    url: "https://hub.atk.pro/",
    keywords: "atk hub 鼠标 键盘 驱动 固件",
  },
  {
    name: "醉鹿 DrunkDeer",
    desc: "DrunkDeer Antler 磁轴键盘控制台。",
    mark: "醉鹿",
    kind: "site",
    url: "https://drunkdeer-antler.cn/?from=kkframenew",
    keywords: "醉鹿 drunkdeer antler 磁轴 键盘 驱动",
  },
  {
    name: "迈从 MCHOSE",
    desc: "设备连接、按键设置与固件更新。",
    mark: "迈从",
    kind: "site",
    url: "https://www.mchose.com.cn/#/connectDevice",
    keywords: "迈从 mchose 键盘 鼠标 驱动 连接",
  },
  {
    name: "狼蛛 AULA",
    desc: "AULA Hub 控制台，灯效和按键设置。",
    mark: "狼蛛",
    kind: "site",
    url: "https://hub.aulacn.com/home",
    keywords: "狼蛛 aula hub 键盘 鼠标 驱动 灯效",
  },
  {
    name: "达尔优 DAREU",
    desc: "达尔优驱动中心，外设配置与固件更新。",
    mark: "达尔优",
    kind: "site",
    url: "https://dr.dareu.com/",
    keywords: "达尔优 dareu 驱动 键盘 鼠标 耳机",
  },
  {
    name: "VGN",
    desc: "VGN Hub 驱动中心，键鼠设备统一调校。",
    mark: "VGN",
    kind: "site",
    url: "https://hub.vgnlab.com.cn/#/",
    keywords: "vgn hub 键盘 鼠标 驱动 磁轴",
  },
  {
    name: "ipi",
    desc: "IPI 游戏外设支持页，驱动与说明书入口。",
    mark: "ipi",
    kind: "site",
    url: "https://www.ipigame.cn/support",
    keywords: "ipi 游戏 外设 驱动 说明书",
  },
  {
    name: "前行者",
    desc: "前行者驱动中心，连接设备后在线设置。",
    mark: "前行",
    kind: "site",
    url: "https://new-hub.eweadn.cn/",
    keywords: "前行者 eweadn 驱动 键盘 鼠标",
  },
  {
    name: "飞智",
    desc: "飞智空间站，手柄与散热背夹等设备管理。",
    mark: "飞智",
    kind: "site",
    url: "https://space_station.flydigi.com/",
    keywords: "飞智 flydigi 手柄 空间站 驱动",
  },
  {
    name: "艾石头 irok",
    desc: "irok 磁轴键盘在线设置与固件更新。",
    mark: "irok",
    kind: "site",
    url: "https://hid.irok.cn/#/",
    keywords: "艾石头 irok 磁轴 键盘 驱动 固件",
  },
  {
    name: "腹灵 FL ESPORTS",
    desc: "腹灵在线控制台，键盘参数和灯效设置。",
    mark: "腹灵",
    kind: "site",
    url: "https://www.flesports.com/index.php/home/webconsole/",
    keywords: "腹灵 flesports fl 键盘 鼠标 驱动 控制台",
  },
  {
    name: "美加狮 Mad Catz",
    desc: "美加狮外设控制台与驱动下载。",
    mark: "美加狮",
    kind: "site",
    url: "https://hub.fgg.com.cn/",
    keywords: "美加狮 mad catz 鼠标 键盘 驱动 控制台",
  },
  {
    name: "IMK 逐日",
    desc: "IMK 键盘驱动下载与在线设置。",
    mark: "IMK",
    kind: "site",
    url: "https://www.imk.net.cn/drive/",
    keywords: "imk 逐日 键盘 驱动 固件",
  },
  {
    name: "Wooting",
    desc: "Wootility 在线调校，改键、触发与灯效。",
    mark: "WOOT",
    kind: "site",
    url: "https://wootility.io/",
    keywords: "wooting wootility 磁轴 键盘 在线 调校",
  },
  {
    name: "星闪悦动",
    desc: "星闪悦动设备连接与控制台。",
    mark: "星闪",
    kind: "site",
    url: "https://www.xsyd.top/connect",
    keywords: "星闪悦动 xsyd 键盘 驱动 连接 控制台",
  },
  {
    name: "NEXUS",
    desc: "NEXUS 外设控制台与驱动入口。",
    mark: "NEXUS",
    kind: "site",
    url: "https://nexusgame.cn/",
    keywords: "nexus 外设 键盘 鼠标 驱动 控制台",
  },
  {
    name: "佳达隆 Gateron",
    desc: "佳达隆轴体与设备支持页面。",
    mark: "GAT",
    kind: "site",
    url: "https://gamelife.longeplay.cn/",
    keywords: "佳达隆 gateron 轴体 键盘 支持 驱动",
  },
  {
    name: "rakka",
    desc: "RAKKA 键盘在线控制台。",
    mark: "RAK",
    kind: "site",
    url: "https://kb.rakka.cn/#/",
    keywords: "rakka 键盘 驱动 控制台 磁轴",
  },
  {
    name: "VIA",
    desc: "开源键盘改键与配置工具，支持 VIA 协议键盘。",
    mark: "VIA",
    kind: "site",
    url: "https://www.usevia.app/",
    keywords: "via 开源 键盘 改键 固件 qmk",
  },
  {
    name: "鼠标第三方驱动",
    desc: "ClickSync 鼠标参数工具，适合折腾第三方鼠标。",
    mark: "CS",
    kind: "site",
    url: "https://nuitfanee.github.io/ClickSync.github.io",
    keywords: "鼠标 第三方 驱动 clicksync dpi 宏",
  },
];

const GROUPS = {
  apps: { data: APPS, grid: null, section: null, filter: () => true },
  mods: { data: MODS, grid: null, section: null, filter: () => true },
  tools: {
    data: TOOLS,
    grid: null,
    section: null,
    filter: (item) => state.toolFilter === "all" || item.category === state.toolFilter,
  },
  drivers: {
    data: DRIVERS,
    grid: null,
    section: null,
    filter: (item) => state.driverFilter === "all" || item.kind === state.driverFilter,
  },
};

const state = {
  query: "",
  toolFilter: "all",
  driverFilter: "all",
};

const searchInput = document.getElementById("siteSearch");
const searchBox = document.getElementById("searchBox");
const searchClear = document.getElementById("searchClear");
const searchStatus = document.getElementById("searchStatus");
const noResults = document.getElementById("noResults");
const noResultsQuery = document.getElementById("noResultsQuery");
const resetSearch = document.getElementById("resetSearch");
const toastRegion = document.getElementById("toastRegion");
const backTop = document.getElementById("backTop");

let toastTimer = 0;

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function normalize(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return "";
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(2).replace(/0+$/, "").replace(/\.$/, "")} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(1)} MB`;
  if (bytes >= 1e3) return `${(bytes / 1e3).toFixed(1)} KB`;
  return `${bytes} B`;
}

function makeSearchText(item, extra = []) {
  return normalize(
    [
      item.name,
      item.desc,
      item.category,
      item.tag,
      item.system,
      item.badge,
      ...(item.keywords ? [item.keywords] : []),
      ...extra,
      ...(item.links || []).map((link) => `${link.label} ${link.meta || ""}`),
    ]
      .filter(Boolean)
      .join(" ")
  );
}

APPS.forEach((item) => {
  item.haystack = makeSearchText(item, [item.format, item.file]);
});
MODS.forEach((item) => {
  item.haystack = makeSearchText(item, [item.file]);
});
TOOLS.forEach((item) => {
  item.haystack = makeSearchText(item);
});
DRIVERS.forEach((item) => {
  item.haystack = makeSearchText(item, [item.kind === "client" ? "客户端 直链 下载" : "官网 在线 控制台"]);
});

function renderApps() {
  const grid = document.getElementById("appGrid");
  grid.innerHTML = APPS.map(
    (app) => `
      <article class="app-card" data-platform="${app.platform}" data-search="${escapeHtml(app.haystack)}">
        <span class="app-watermark" aria-hidden="true">${PLATFORM_ICONS[app.platform]}</span>
        <div class="app-top">
          <span class="app-icon" aria-hidden="true">${PLATFORM_ICONS[app.platform]}</span>
          <span class="app-badge">${escapeHtml(app.badge)}</span>
        </div>
        <h3>${escapeHtml(app.name)}</h3>
        <p class="app-desc">${escapeHtml(app.desc)}</p>
        <dl class="app-meta">
          <div><dt>版本</dt><dd>${escapeHtml(app.version)}</dd></div>
          <div><dt>大小</dt><dd>${formatBytes(app.sizeBytes)}</dd></div>
          <div><dt>系统</dt><dd>${escapeHtml(app.system)}</dd></div>
          <div><dt>格式</dt><dd>${escapeHtml(app.format)}</dd></div>
        </dl>
        <div class="app-actions">
          <a class="button button--download" href="${escapeHtml(app.url)}" target="_blank" rel="noopener" data-download="${escapeHtml(app.file)}">
            ${ICONS.download}
            下载${app.platform === "android" ? " APK" : "安装包"}
          </a>
        </div>
        <div class="hash-row">
          <span>SHA-256</span>
          <code title="${escapeHtml(app.sha256)}">${escapeHtml(app.sha256)}</code>
          <button class="hash-copy" type="button" data-copy-sha="${escapeHtml(app.sha256)}" data-copy-label="${escapeHtml(app.name)}" aria-label="复制 ${escapeHtml(app.name)} 安装包的 SHA-256">复制</button>
        </div>
        <p class="app-warning">${ICONS.info}<span>${escapeHtml(app.warning)}</span></p>
      </article>`
  ).join("");
}

function renderMods() {
  const grid = document.getElementById("modGrid");
  grid.innerHTML = MODS.map(
    (mod) => `
      <article class="mod-card" data-search="${escapeHtml(mod.haystack)}">
        <div class="mod-cover">
          <img src="${escapeHtml(mod.cover)}" alt="${escapeHtml(mod.name)} Mod 封面" width="720" height="405" loading="lazy" decoding="async">
          <span class="mod-tag">${escapeHtml(mod.tag)}</span>
          <span class="mod-size">${formatBytes(mod.sizeBytes)}</span>
        </div>
        <div class="mod-body">
          <h3 class="mod-name">${escapeHtml(mod.name)}</h3>
          <p class="mod-desc">${escapeHtml(mod.desc)}</p>
          <div class="mod-foot">
            <span class="mod-file" title="${escapeHtml(mod.file)}">${escapeHtml(mod.file)}</span>
            <a class="mod-download" href="${escapeHtml(mod.url)}" target="_blank" rel="noopener" data-download="${escapeHtml(mod.file)}" aria-label="下载 ${escapeHtml(mod.name)} Mod，${formatBytes(mod.sizeBytes)}">
              ${ICONS.downloadSmall}
              下载
            </a>
          </div>
        </div>
      </article>`
  ).join("");
}

function renderTools() {
  const grid = document.getElementById("toolGrid");
  grid.innerHTML = TOOLS.map((tool, index) => {
    const links = tool.links
      .map((link) => {
        const isDownload = link.kind === "download";
        const meta = isDownload ? `${link.meta} · ${formatBytes(link.bytes)}` : link.meta || "官方页面";
        const action = isDownload ? `data-download="${escapeHtml(tool.name)} ${escapeHtml(link.label)}"` : `data-external="${escapeHtml(tool.name)}"`;
        return `
          <a class="resource-link" href="${escapeHtml(link.url)}" target="_blank" rel="noopener" ${action}>
            ${isDownload ? ICONS.download : ICONS.external}
            <span class="resource-link__label">
              <strong>${escapeHtml(link.label)}</strong>
              <small>${escapeHtml(meta)}</small>
            </span>
            <span class="link-goto">${ICONS.arrow}</span>
          </a>`;
      })
      .join("");

    return `
      <article class="resource-card" data-search="${escapeHtml(tool.haystack)}" data-category="${escapeHtml(tool.category)}">
        <div class="resource-head">
          <span class="resource-mark" data-tone="${index % 6}" aria-hidden="true">${escapeHtml(tool.mark)}</span>
          <div class="resource-title">
            <h3>${escapeHtml(tool.name)}</h3>
            <span class="resource-cat">${escapeHtml(tool.category)}</span>
          </div>
        </div>
        <p class="resource-desc">${escapeHtml(tool.desc)}</p>
        ${tool.warn ? `<p class="resource-warn">${escapeHtml(tool.warn)}</p>` : ""}
        <div class="resource-links">${links}</div>
      </article>`;
  }).join("");
}

function renderDrivers() {
  const grid = document.getElementById("driverGrid");
  grid.innerHTML = DRIVERS.map((driver, index) => {
    const isClient = driver.kind === "client";
    const meta = isClient ? `${driver.format} · ${formatBytes(driver.bytes)}` : "官网";
    const action = isClient ? `data-download="${escapeHtml(driver.name)} 客户端"` : `data-external="${escapeHtml(driver.name)}"`;
    return `
      <article class="driver-card" data-search="${escapeHtml(driver.haystack)}" data-kind="${driver.kind}">
        <div class="driver-head">
          <span class="driver-mark" data-tone="${index % 6}" aria-hidden="true">${escapeHtml(driver.mark)}</span>
          <div class="driver-title">
            <h3>${escapeHtml(driver.name)}</h3>
            <span class="driver-type ${isClient ? "driver-type--client" : ""}"><i aria-hidden="true"></i>${isClient ? "客户端直链" : "品牌官网"}</span>
          </div>
        </div>
        <p class="driver-desc">${escapeHtml(driver.desc)}</p>
        <a class="driver-action" href="${escapeHtml(driver.url)}" target="_blank" rel="noopener" ${action} aria-label="${escapeHtml(isClient ? `下载 ${driver.name} 客户端` : `打开 ${driver.name} 官网`)}">
          ${isClient ? ICONS.downloadSmall : ICONS.external}
          <span>${isClient ? "下载客户端" : "打开官网"}</span>
          <small>${escapeHtml(meta)}</small>
          ${ICONS.arrow}
        </a>
      </article>`;
  }).join("");
}

function setCounts() {
  const counts = {
    apps: APPS.length,
    mods: MODS.length,
    tools: TOOLS.length,
    drivers: DRIVERS.length,
  };
  Object.entries(counts).forEach(([key, value]) => {
    document.querySelectorAll(`[data-count="${key}"]`).forEach((el) => {
      el.textContent = String(value);
    });
  });
}

function matchesQuery(haystack, tokens) {
  return tokens.every((token) => haystack.includes(token));
}

function updateGroup(key, tokens) {
  const group = GROUPS[key];
  const isSearching = tokens.length > 0;
  let visible = 0;

  group.data.forEach((item, index) => {
    const card = group.grid.children[index];
    if (!card) return;
    const match = (!isSearching || matchesQuery(item.haystack, tokens)) && group.filter(item);
    card.hidden = !match;
    if (match) visible += 1;
  });

  document.querySelectorAll(`[data-count="${key}"]`).forEach((el) => {
    el.textContent = String(isSearching ? visible : group.data.length);
  });

  group.section.hidden = isSearching && visible === 0;

  const empty = document.querySelector(`[data-empty-for="${key}"]`);
  if (empty) empty.hidden = isSearching || visible > 0;

  return visible;
}

function applyFilters() {
  const tokens = normalize(state.query).split(" ").filter(Boolean);

  let visibleTotal = 0;
  Object.keys(GROUPS).forEach((key) => {
    visibleTotal += updateGroup(key, tokens);
  });

  const isSearching = tokens.length > 0;
  noResults.hidden = !isSearching || visibleTotal > 0;
  noResultsQuery.textContent = state.query.trim();

  if (searchStatus) {
    searchStatus.hidden = !isSearching;
    if (isSearching) {
      searchStatus.textContent = visibleTotal > 0 ? `找到 ${visibleTotal} 个资源` : "没有找到匹配资源，换个关键词试试";
      searchStatus.classList.toggle("is-empty", visibleTotal === 0);
    }
  }
}

function clearSearch({ focus = false, scroll = false } = {}) {
  state.query = "";
  searchInput.value = "";
  searchBox.classList.remove("has-value");
  applyFilters();
  if (scroll) {
    window.scrollTo({ top: 0, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  }
  if (focus) searchInput.focus({ preventScroll: true });
}

function showToast(message, duration = 2400) {
  if (!toastRegion) return;
  const toast = document.createElement("div");
  toast.className = "toast";
  toast.textContent = message;
  toastRegion.replaceChildren(toast);
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => {
    toast.classList.add("toast--leaving");
    toast.addEventListener("animationend", () => toast.remove(), { once: true });
  }, duration);
}

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      /* fall through to the legacy path */
    }
  }
  try {
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.append(area);
    area.select();
    const ok = document.execCommand("copy");
    area.remove();
    return ok;
  } catch {
    return false;
  }
}

function bindFilterChips() {
  const chips = document.querySelectorAll(".filter-chip");
  chips.forEach((chip) => {
    chip.setAttribute("aria-pressed", chip.classList.contains("is-active") ? "true" : "false");
    chip.addEventListener("click", () => {
      const group = chip.dataset.filterGroup;
      const value = chip.dataset.filter;
      if (group === "tools") state.toolFilter = value;
      if (group === "drivers") state.driverFilter = value;
      chips.forEach((other) => {
        if (other.dataset.filterGroup !== group) return;
        const active = other === chip;
        other.classList.toggle("is-active", active);
        other.setAttribute("aria-pressed", active ? "true" : "false");
      });
      applyFilters();
    });
  });
}

function bindSearch() {
  searchInput.addEventListener("input", () => {
    state.query = searchInput.value;
    searchBox.classList.toggle("has-value", searchInput.value.length > 0);
    applyFilters();
  });

  searchClear.addEventListener("click", () => clearSearch({ focus: true }));

  resetSearch.addEventListener("click", () => clearSearch({ focus: true, scroll: true }));

  document.addEventListener("keydown", (event) => {
    const target = event.target;
    const typing = target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable);

    if (event.key === "/" && !typing) {
      event.preventDefault();
      searchInput.focus();
      searchInput.select();
      return;
    }

    if (event.key === "Escape" && document.activeElement === searchInput) {
      if (searchInput.value) {
        event.preventDefault();
        clearSearch({ focus: true });
      } else {
        searchInput.blur();
      }
    }
  });

  document.querySelectorAll('.site-nav a[href^="#"], .footer-col a[href^="#"]').forEach((link) => {
    link.addEventListener("click", () => {
      if (state.query) clearSearch();
    });
  });
}

function bindActions() {
  document.addEventListener("click", (event) => {
    const download = event.target.closest("[data-download]");
    if (download) {
      const label = download.getAttribute("data-download");
      showToast(`开始下载 · ${label}`, 2800);
      return;
    }

    const external = event.target.closest("[data-external]");
    if (external) {
      showToast(`正在打开 · ${external.getAttribute("data-external")}`, 2200);
      return;
    }

    const copyButton = event.target.closest("[data-copy-sha]");
    if (copyButton) {
      const sha = copyButton.getAttribute("data-copy-sha");
      const label = copyButton.getAttribute("data-copy-label");
      copyText(sha).then((ok) => {
        if (!ok) {
          showToast("复制失败，请手动选择校验值", 2600);
          return;
        }
        const previous = copyButton.textContent;
        copyButton.textContent = "已复制";
        showToast(`${label} SHA-256 已复制`);
        window.setTimeout(() => {
          copyButton.textContent = previous;
        }, 1600);
      });
    }
  });
}

function bindBackTop() {
  let scheduled = false;
  const update = () => {
    if (backTop) backTop.hidden = window.scrollY < 620;
    scheduled = false;
  };
  window.addEventListener(
    "scroll",
    () => {
      if (scheduled) return;
      scheduled = true;
      window.requestAnimationFrame(update);
    },
    { passive: true }
  );
  update();

  if (backTop) {
    backTop.addEventListener("click", () => {
      window.scrollTo({ top: 0, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
    });
  }
}

function bindActiveNav() {
  if (!("IntersectionObserver" in window)) return;
  const sections = [...document.querySelectorAll("main .section")];
  const links = [...document.querySelectorAll(".site-nav a")];
  const setActive = (id) => {
    links.forEach((link) => {
      const active = link.getAttribute("href") === `#${id}`;
      link.classList.toggle("is-active", active);
      if (active) link.setAttribute("aria-current", "location");
      else link.removeAttribute("aria-current");
    });
  };

  const observer = new IntersectionObserver(
    (entries) => {
      const current = entries
        .filter((entry) => entry.isIntersecting)
        .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
      if (current) setActive(current.target.id);
    },
    { rootMargin: "-25% 0px -55% 0px", threshold: [0, 0.1, 0.4] }
  );

  sections.forEach((section) => observer.observe(section));
}

function init() {
  GROUPS.apps.grid = document.getElementById("appGrid");
  GROUPS.apps.section = document.getElementById("apps");
  GROUPS.mods.grid = document.getElementById("modGrid");
  GROUPS.mods.section = document.getElementById("mods");
  GROUPS.tools.grid = document.getElementById("toolGrid");
  GROUPS.tools.section = document.getElementById("tools");
  GROUPS.drivers.grid = document.getElementById("driverGrid");
  GROUPS.drivers.section = document.getElementById("drivers");

  renderApps();
  renderMods();
  renderTools();
  renderDrivers();
  setCounts();
  bindFilterChips();
  bindSearch();
  bindActions();
  bindBackTop();
  bindActiveNav();
  applyFilters();
}

init();
