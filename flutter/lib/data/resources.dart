// 资源数据：与 index.html MODS/TOOLS/DRIVERS 同源。
class ModItem {
  final String name, desc, tag, url, image;
  const ModItem(this.name, this.desc, this.tag, this.url, this.image);
}

class ResourceVersion {
  final String name, desc, url;
  final bool recommended;
  const ResourceVersion(
    this.name,
    this.desc,
    this.url, {
    this.recommended = false,
  });
}

class ToolItem {
  final String name, desc, section, icon;
  final String? hash;
  final String? url;
  final String? warn;
  final List<ResourceVersion> versions;
  const ToolItem({
    required this.name,
    required this.desc,
    required this.section,
    required this.icon,
    this.hash,
    this.url,
    this.warn,
    this.versions = const [],
  });
}

class DriverItem {
  final String name, url;
  final bool client;
  const DriverItem(this.name, this.url, {this.client = false});
}

const List<ModItem> kMods = [
  ModItem(
    "REPO",
    "《REPO》整合模组，前置齐全、汉化到位，开黑即装即玩。",
    "整合包",
    "https://obs.chimu-claw.xyz/MOD/REPO.zip",
    "assets/images/mods/REPO.jpg",
  ),
  ModItem(
    "雨中冒险2",
    "UES 优化整合包，帧数更稳、跑图更顺，联机体验拉满。",
    "性能优化",
    "https://obs.chimu-claw.xyz/MOD/%E9%9B%A8%E4%B8%AD%E5%86%92%E9%99%A92%20UES%E4%BC%98%E5%8C%96.zip",
    "assets/images/mods/雨中冒险2.jpg",
  ),
  ModItem(
    "与友赌博",
    "把赌场搬进游戏，和朋友欢乐梭哈，输了请客那种。",
    "趣味玩法",
    "https://obs.chimu-claw.xyz/MOD/%E4%B8%8E%E5%8F%8B%E8%B5%8C%E5%8D%9A.zip",
    "assets/images/mods/与友赌博.jpg",
  ),
  ModItem(
    "PEAK",
    "登山冒险整合 Mod，中文化与功能模组一步到位，开箱即玩。",
    "整合包",
    "https://obs.chimu-claw.xyz/MOD/PEAK.zip",
    "assets/images/mods/PEAK.jpg",
  ),
  ModItem(
    "迷魅狩猎",
    "神秘狩猎玩法扩展，给探险加点意想不到的邪门乐趣。",
    "玩法扩展",
    "https://obs.chimu-claw.xyz/MOD/%E8%BF%B7%E9%AD%85%E7%8B%A9%E7%8C%8E.zip",
    "assets/images/mods/迷魅狩猎.jpg",
  ),
  ModItem(
    "崩溃小队",
    "混乱多人乱斗模组，场面越崩越快乐，适合整活之夜。",
    "多人乱斗",
    "https://obs.chimu-claw.xyz/MOD/%E5%B4%A9%E6%BA%83%E5%B0%8F%E9%98%9F.zip",
    "assets/images/mods/崩溃小队.jpg",
  ),
];

const List<ToolItem> kTools = [
  ToolItem(
    name: "灵敏度",
    desc: "跨游戏灵敏度精确换算",
    section: "游戏工具",
    icon: "<path d=\"M12 20a8 8 0 1 0 0-16 8 8 0 0 0 0 16z\"/><path d=\"M12 8v4l3 2\"/>",
    hash: "#/sens",
    url: null,
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "玩法抽签",
    desc: "无畏契约整活玩法抽签",
    section: "游戏工具",
    icon: "<rect x=\"2\" y=\"2\" width=\"20\" height=\"20\" rx=\"5\"/><path d=\"M12 8v8M8 12h8\"/>",
    hash: "#/play",
    url: null,
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "瞬投",
    desc: "游戏投掷物点位地图",
    section: "游戏工具",
    icon: "<path d=\"M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z\"/><circle cx=\"12\" cy=\"10\" r=\"3\"/>",
    hash: null,
    url: "https://shuntou.top/",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "视野live",
    desc: "实时视野 · 在线直播",
    section: "游戏工具",
    icon:
        "<path d=\"M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z\"/><circle cx=\"12\" cy=\"12\" r=\"3\"/>",
    hash: null,
    url: "https://shijiao.xingpaste.com/",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "MsLab",
    desc: "毫秒实验室 · 无畏契约灵敏度调试",
    section: "游戏工具",
    icon:
        "<circle cx=\"12\" cy=\"12\" r=\"8\"/><path d=\"M12 8v4l2.5 1.5\"/><path d=\"M12 1v3M12 20v3M1 12h3M20 12h3\"/>",
    hash: null,
    url: "https://mslab.gg/",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "瞄准专家",
    desc: "无畏契约预瞄架枪训练地图",
    section: "游戏工具",
    icon: "<circle cx=\"12\" cy=\"12\" r=\"9\"/><line x1=\"21\" y1=\"12\" x2=\"17\" y2=\"12\"/><line x1=\"7\" y1=\"12\" x2=\"3\" y2=\"12\"/><line x1=\"12\" y1=\"7\" x2=\"12\" y2=\"3\"/><line x1=\"12\" y1=\"21\" x2=\"12\" y2=\"17\"/>",
    hash: null,
    url: "https://ishoutu.cn/aim",
    warn: "打瓦的时候不要挂在后台！！！",
    versions: const [],
  ),
  ToolItem(
    name: "万兴优转",
    desc: "视频格式转换与压缩",
    section: "装机必备",
    icon: "<polygon points=\"23 7 16 12 23 17 23 7\"/><rect x=\"1\" y=\"5\" width=\"15\" height=\"14\" rx=\"2\" ry=\"2\"/>",
    hash: null,
    url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/%E4%B8%87%E5%85%B4%E4%BC%98%E8%BD%AC.zip",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "TreeSide",
    desc: "磁盘空间分析",
    section: "装机必备",
    icon: "<path d=\"M21.21 15.89A10 10 0 1 1 8 2.83\"/><path d=\"M22 12A10 10 0 0 0 12 2v10z\"/>",
    hash: null,
    url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/TreeSize.7z",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "Twinkle Tray",
    desc: "显示器亮度调节",
    section: "装机必备",
    icon: "<circle cx=\"12\" cy=\"12\" r=\"5\"/><path d=\"M12 1v2\"/><path d=\"M12 21v2\"/><path d=\"M4.22 4.22l1.42 1.42\"/><path d=\"M18.36 18.36l1.42 1.42\"/><path d=\"M1 12h2\"/><path d=\"M21 12h2\"/><path d=\"M4.22 19.78l1.42-1.42\"/><path d=\"M18.36 5.64l1.42-1.42\"/>",
    hash: null,
    url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/Twinkle%20Tray.exe",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "Office Tool",
    desc: "Office 激活与管理",
    section: "装机必备",
    icon: "<path d=\"M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z\"/><polyline points=\"14 2 14 8 20 8\"/><line x1=\"16\" y1=\"13\" x2=\"8\" y2=\"13\"/><line x1=\"16\" y1=\"17\" x2=\"8\" y2=\"17\"/>",
    hash: null,
    url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/Office_Tool.zip",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "Direct X",
    desc: "DirectX 运行库修复",
    section: "装机必备",
    icon: "<rect x=\"4\" y=\"4\" width=\"16\" height=\"16\" rx=\"2\"/><rect x=\"9\" y=\"9\" width=\"6\" height=\"6\"/><path d=\"M9 1v3M15 1v3M9 20v3M15 20v3M1 9h3M1 15h3M20 9h3M20 15h3\"/>",
    hash: null,
    url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/DirectX_Repair.zip",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "Geek",
    desc: "轻量级软件卸载",
    section: "装机必备",
    icon: "<polyline points=\"3 6 5 6 21 6\"/><path d=\"M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2\"/>",
    hash: null,
    url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/geek.exe",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "Steam",
    desc: "游戏平台客户端",
    section: "游戏相关",
    icon: "<line x1=\"6\" y1=\"2\" x2=\"6\" y2=\"14\"/><line x1=\"18\" y1=\"2\" x2=\"18\" y2=\"14\"/><path d=\"M6 14c0 3 2.7 5 6 5s6-2 6-5\"/><path d=\"M2 6h4M18 6h4\"/>",
    hash: null,
    url:
        "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/SteamSetup.exe",
    warn: null,
    versions: const [
      ResourceVersion(
        "Steam（官方正版）",
        "Valve 官方客户端，正版游戏首选",
        "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/SteamSetup.exe",
        recommended: true,
      ),
      ResourceVersion(
        "Steam游戏管家（Leo专版）",
        "Leo 定制专版，开箱即用",
        "https://obs.chimu-claw.xyz/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/Steam%E6%B8%B8%E6%88%8F%E7%AE%A1%E5%AE%B6_2.0.0.2985.exe",
        recommended: false,
      ),
    ],
  ),
  ToolItem(
    name: "BAND ZIP",
    desc: "免费好用的压缩软件",
    section: "装机必备",
    icon: "<polyline points=\"21 8 21 21 3 21 3 8\"/><rect x=\"1\" y=\"3\" width=\"22\" height=\"5\"/><line x1=\"10\" y1=\"12\" x2=\"14\" y2=\"12\"/>",
    hash: null,
    url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/Bandizip.exe",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "图吧工具箱",
    desc: "硬件检测与系统优化",
    section: "装机必备",
    icon: "<path d=\"M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z\"/>",
    hash: null,
    url: "https://obs.chimu-claw.xyz/%E5%B0%8F%E5%B7%A5%E5%85%B7/%E5%9B%BE%E5%90%A7%E5%B7%A5%E5%85%B7%E7%AE%B1.exe",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "KOOK",
    desc: "游戏语音沟通平台",
    section: "语音聊天",
    icon: "<path d=\"M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z\"/>",
    hash: null,
    url: "https://www.kookapp.cn/",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "NN语音",
    desc: "语音聊天社交应用",
    section: "语音聊天",
    icon: "<path d=\"M3 18v-6a9 9 0 0 1 18 0v6\"/><path d=\"M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z\"/>",
    hash: null,
    url: "https://www.nn.com/home",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "UU远程",
    desc: "网易远程控制工具",
    section: "语音聊天",
    icon: "<rect x=\"2\" y=\"3\" width=\"20\" height=\"14\" rx=\"2\"/><line x1=\"8\" y1=\"21\" x2=\"16\" y2=\"21\"/><line x1=\"12\" y1=\"17\" x2=\"12\" y2=\"21\"/>",
    hash: null,
    url: "https://uuyc.163.com/",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "屏幕分享",
    desc: "网页屏幕共享与远程演示",
    section: "语音聊天",
    icon: "<rect x=\"2\" y=\"3\" width=\"20\" height=\"14\" rx=\"2\"/><line x1=\"8\" y1=\"21\" x2=\"16\" y2=\"21\"/><line x1=\"12\" y1=\"17\" x2=\"12\" y2=\"21\"/><path d=\"M12 6v8M9 9l3-3 3 3\"/>",
    hash: null,
    url: "https://demo.piik.tv/",
    warn: null,
    versions: const [],
  ),
  ToolItem(
    name: "青柠起始页",
    desc: "简洁清爽的浏览器起始页",
    section: "装机必备",
    icon: "<circle cx=\"11\" cy=\"11\" r=\"8\"/><line x1=\"21\" y1=\"21\" x2=\"16.65\" y2=\"16.65\"/>",
    hash: null,
    url: "https://www.limestart.cn/",
    warn: null,
    versions: const [],
  ),
];

const List<DriverItem> kDriversWeb = [
  DriverItem("奥创中心", "https://gearlink.asus.com.cn/zh-cn"),
  DriverItem("雷云", "https://synapse.razer.com/dashboard/"),
  DriverItem("铝厂 IQUNIX", "https://docs.iqunix.com/Magnet_Switch"),
  DriverItem("小蜜蜂 MelGeek", "https://hive.melgeek.cn/"),
  DriverItem("ATK", "https://hub.atk.pro/"),
  DriverItem("醉鹿", "https://drunkdeer-antler.cn/?from=kkframenew"),
  DriverItem("迈从", "https://www.mchose.com.cn/#/connectDevice"),
  DriverItem("狼蛛", "https://hub.aulacn.com/home"),
  DriverItem("达尔优", "https://dr.dareu.com/"),
  DriverItem("VGN", "https://hub.vgnlab.com.cn/#/"),
  DriverItem("ipi", "https://www.ipigame.cn/support"),
  DriverItem("前行者", "https://new-hub.eweadn.cn/"),
  DriverItem("飞智", "https://space_station.flydigi.com/"),
  DriverItem("艾石头", "https://hid.irok.cn/#/"),
  DriverItem("腹灵", "https://www.flesports.com/index.php/home/webconsole/"),
  DriverItem("美加狮", "https://hub.fgg.com.cn/"),
  DriverItem("IMK逐日", "https://www.imk.net.cn/drive/"),
  DriverItem("wooting", "https://wootility.io/"),
  DriverItem("星闪悦动", "https://www.xsyd.top/connect"),
  DriverItem("NEXUS", "https://nexusgame.cn/"),
  DriverItem("佳达隆", "https://gamelife.longeplay.cn/"),
  DriverItem("rakka", "https://kb.rakka.cn/#/"),
  DriverItem("VIA", "https://www.usevia.app/"),
  DriverItem("鼠标第三方驱动", "https://nuitfanee.github.io/ClickSync.github.io"),
];

const List<DriverItem> kDriversClient = [
  DriverItem(
    "ROG奥创中心",
    "https://obs.chimu-claw.xyz/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/ROG%E5%A5%A5%E5%88%9B%E4%B8%AD%E5%BF%83.exe",
    client: true,
  ),
  DriverItem(
    "罗技驱动精简版",
    "https://obs.chimu-claw.xyz/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/%E7%BD%97%E6%8A%80%E9%A9%B1%E5%8A%A8%E7%B2%BE%E7%AE%80%E7%89%88.exe",
    client: true,
  ),
  DriverItem(
    "罗技G-HUB",
    "https://citro.obs.cn-south-1.myhuaweicloud.com/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/%E7%BD%97%E6%8A%80G-HUB.exe",
    client: true,
  ),
  DriverItem(
    "WOOT驱动客户端",
    "https://obs.chimu-claw.xyz/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/Woot%E9%A9%B1%E5%8A%A8%E5%AE%A2%E6%88%B7%E7%AB%AF.exe",
    client: true,
  ),
  DriverItem(
    "雷云4",
    "https://citro.obs.cn-south-1.myhuaweicloud.com/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/%E9%9B%B7%E4%BA%914.exe",
    client: true,
  ),
  DriverItem(
    "卓威U2驱动",
    "https://obs.chimu-claw.xyz/%E5%A4%96%E8%AE%BE%E9%A9%B1%E5%8A%A8/%E5%8D%93%E5%A8%81U2.exe",
    client: true,
  ),
];
