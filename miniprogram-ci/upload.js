#!/usr/bin/env node
/**
 * 用 miniprogram-ci 把当前目录的代码包上传到微信小程序后台。
 *
 * 必填环境变量：
 *   WX_APPID       小程序 AppID（wx 开头）
 *   WX_UPLOAD_KEY  代码上传密钥文件路径（小程序后台 → 开发管理 → 开发设置 →
 *                  小程序代码上传 → 生成并下载，只显示一次）
 *
 * 可选：
 *   WX_VERSION     版本号，默认 0.1.0
 *   WX_DESC        版本描述，默认 "Citro 玩法抽签"
 *   WX_ROBOT       CI 机器人编号，默认 1
 *
 * 上传机器 IP 需要在后台的 IP 白名单里（或在后台关闭白名单）。
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..", "miniprogram");

function readProjectAppid() {
  try {
    const cfg = JSON.parse(
      fs.readFileSync(path.join(ROOT, "project.config.json"), "utf8")
    );
    return cfg.appid || "";
  } catch (e) {
    return "";
  }
}

function fail(message) {
  console.error("[upload] " + message);
  process.exit(1);
}

const appid = String(process.env.WX_APPID || readProjectAppid()).trim();
const keyPath = String(process.env.WX_UPLOAD_KEY || "").trim();
const version = String(process.env.WX_VERSION || "0.1.0").trim();
const desc = String(process.env.WX_DESC || "Citro 玩法抽签").trim();
const robot = Number(process.env.WX_ROBOT || 1);

if (!appid || appid === "touristappid") {
  fail(
    "缺少真实 AppID。请设置 WX_APPID=wx...（touristappid 不能上传），" +
      "或把 project.config.json 的 appid 改成真实值。"
  );
}
if (!/^wx[a-f0-9]{16}$/i.test(appid)) {
  fail("AppID 格式不对，应以 wx 开头、共 18 位。");
}
if (!keyPath) {
  fail(
    "缺少 WX_UPLOAD_KEY。请到小程序后台下载代码上传密钥，并把文件路径传进来。"
  );
}
if (!fs.existsSync(keyPath)) {
  fail("上传密钥文件不存在：" + keyPath);
}

let ci;
try {
  ci = require("miniprogram-ci");
} catch (e) {
  fail("没有安装 miniprogram-ci。先运行：npm install --prefix " + __dirname);
}

(async () => {
  const project = new ci.Project({
    appid,
    type: "miniProgram",
    projectPath: ROOT,
    privateKeyPath: keyPath,
    ignores: [
      "node_modules/**/*",
      "**/node_modules/**/*",
      "tools/**/*",
      ".gitignore",
      "README.md",
      "*.key",
    ],
  });

  console.log("[upload] appid=" + appid);
  console.log("[upload] version=" + version + " desc=" + desc);
  console.log("[upload] key=" + keyPath);

  try {
    const result = await ci.upload({
      project,
      version,
      desc,
      robot,
      setting: {
        es6: true,
        minify: true,
        urlCheck: false,
      },
      onProgressUpdate: (task) => {
        if (task && task.message) console.log("[upload] " + task.message);
      },
    });
    console.log("[upload] 成功：");
    console.log(JSON.stringify(result, null, 2));
  } catch (e) {
    console.error("[upload] 失败：");
    console.error(e && e.message ? e.message : e);
    console.error(
      "常见原因：上传密钥不对 / 未配置 IP 白名单 / AppID 与密钥不匹配 / 网络无法访问微信服务器。"
    );
    process.exit(1);
  }
})();