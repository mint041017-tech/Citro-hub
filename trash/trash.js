/* ============================================================
 * 迟暮·Crew 站点 API（零依赖，仅 Node 内置模块）
 *   · 队友账号：注册 / 登录 / 登出 / 会话（scrypt + httpOnly Cookie）
 *   · 迟暮社区：发帖(实名/匿名) / 点赞 / 抱一抱 / 评论(支持回复) / 本人删除
 *               内容永久保留
 * 宝塔反代到 /trashapi/ ，启动：node trash.js（或 PM2，端口 10003）
 * ============================================================ */
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFile } = require('child_process');

/* ---------------- 本地敏感配置 ----------------
 * 优先读环境变量，其次读同目录 config.local.json（已在 .gitignore 中排除，不会入库）。
 * 可配置项：SHOWAPI_KEY（万维易源 appKey）、INVITE_CODE（注册邀请码）。
 */
const LOCAL_CFG = (function () {
  try { return JSON.parse(fs.readFileSync(path.join(__dirname, 'config.local.json'), 'utf8')) || {}; }
  catch (e) { return {}; }
})();
function envCfg(key, fallback) {
  if (process.env[key]) return process.env[key];
  if (LOCAL_CFG[key] !== undefined && LOCAL_CFG[key] !== null) return String(LOCAL_CFG[key]);
  return fallback;
}

const PORT = process.env.PORT || 10003;
const HOST = process.env.HOST || '127.0.0.1';
const DATA_DIR = path.join(__dirname, 'data');
const AV_DIR = path.join(DATA_DIR, 'avatars');    // 用户头像
const IMG_DIR = path.join(DATA_DIR, 'postimgs');  // 帖子配图
const VOICE_DIR = path.join(DATA_DIR, 'voices');  // 帖子语音
const COOK_DIR = path.join(DATA_DIR, 'cookimgs'); // 食谱封面 / 步骤图
[AV_DIR, IMG_DIR, VOICE_DIR, COOK_DIR].forEach(function (d) { try { if (!fs.existsSync(d)) fs.mkdirSync(d, { recursive: true }); } catch (e) {} });
const SESSION_DAYS = 30;
const FEED_MAX = 100;        // 每次拉取最新动态条数（数据永久保留）
const MAX_COMMENTS = 100;    // 单帖最多评论
const MAX_LEN = 200;         // 帖子/评论最大字数
const MAX_IMGS = 3;          // 单帖最多配图数
/* 注册邀请码：环境变量 INVITE_CODE 或 config.local.json 配置；留空表示不校验（开放注册） */
const INVITE_CODE = envCfg('INVITE_CODE', '');
/* Web AI 只通过本站代理访问 GLM，密钥不会下发到浏览器。 */
const GLM_API_KEY = envCfg('GLM_API_KEY', '');
const GLM_MODEL = 'glm-5.3-flash';

const FRUIT = ["破防橘子","沉默柠檬","暴躁椰子","摆烂桃子","心碎草莓","无语西瓜","委屈芒果",
  "躺平菠萝","暴躁猕猴桃","emo蓝莓","裂开柚子","佛系山楂","发癫芭乐","头铁榴莲","emo车厘子",
  "摆烂龙眼","暴躁小番茄","委屈水蜜桃","裂开哈密瓜","躺平火龙果","叹气番石榴","干饭菠萝蜜"];

/* ---------------- 基础工具 ---------------- */
function dayStr() { return new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10); }
let today = dayStr();
function yesterdayStr() {
  return new Date(Date.now() + 8 * 3600 * 1000 - 86400000).toISOString().slice(0, 10);
}
function checkinStatus(u) {
  const d = dayStr();
  const last = u && u.checkinLast ? String(u.checkinLast) : '';
  const checked = last === d;
  const alive = checked || last === yesterdayStr();
  return {
    date: d,
    last: last,
    checkedInToday: checked,
    streak: alive ? Math.max(0, parseInt(u.checkinStreak, 10) || 0) : 0
  };
}

function writeAtomic(file, obj) {
  try {
    if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
    const tmp = file + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(obj));
    fs.renameSync(tmp, file);
  } catch (e) { console.error('[write]', path.basename(file), e.message); }
}
function readJson(file, fallback) {
  try { return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : fallback; }
  catch (e) { return fallback; }
}

/* ---------------- 帖子数据（永久保留，单文件存储） ---------------- */
let posts = [];
const postsFile = path.join(DATA_DIR, 'posts.json');
function loadPosts() {
  let arr = readJson(postsFile, null);
  if (!Array.isArray(arr)) {
    /* 首次升级：若存在旧的按天文件，迁移当天数据，避免丢帖 */
    arr = readJson(path.join(DATA_DIR, 'trash-' + dayStr() + '.json'), []);
    if (!Array.isArray(arr)) arr = [];
    posts = arr; savePosts();
  } else { posts = arr; }
}
function savePosts() { writeAtomic(postsFile, posts); }
loadPosts();

/* ---------------- 笔记数据（按用户隔离，单文件存储） ---------------- */
const notesFile = path.join(DATA_DIR, 'notes.json');
let notes = readJson(notesFile, { notes: [] }).notes || [];
function saveNotes() { writeAtomic(notesFile, { notes: notes }); }
const NOTE_TITLE_MAX = 50;
const NOTE_CONTENT_MAX = 5000;
const NOTE_MAX_PER_USER = 50;

/* ---------------- ★食谱日记（按用户隔离，单文件存储） ----------------
   前端「食谱日记」：我的食谱库 + 食谱广场 + 购物清单。
   结构：{ recipes: [ {id,uid,name,…} ], shopping: { "昵称": [ {id,text,done} ] } }
   recipes 按 uid（账号昵称）归属；visibility=public 的才会出现在食谱广场。
   注意：食谱 id 会同时出现在「我的食谱库」和「食谱广场」两个列表里（前端按 id 定位，
   广场详情靠 cookData.square 查），因此必须全局唯一，统一由 cookId() 生成。 */
const cookFile = path.join(DATA_DIR, 'cook.json');
const cookRaw = readJson(cookFile, {});
let cookRecipes = (cookRaw && Array.isArray(cookRaw.recipes)) ? cookRaw.recipes : [];
let cookShopping = (cookRaw && cookRaw.shopping && typeof cookRaw.shopping === 'object' && !Array.isArray(cookRaw.shopping))
  ? cookRaw.shopping : {};
/* 我的冰箱（2026-10-16 新增）：{ "昵称": [ {id,name,qty,unit,buyDate,expDate} ] }
   与购物清单同样是「按用户隔离 + 前端整体覆盖保存」的结构 */
let cookFridge = (cookRaw && cookRaw.fridge && typeof cookRaw.fridge === 'object' && !Array.isArray(cookRaw.fridge))
  ? cookRaw.fridge : {};
function saveCook() { writeAtomic(cookFile, { recipes: cookRecipes, shopping: cookShopping, fridge: cookFridge }); }

const COOK_NAME_MAX = 40;       // 食谱名
const COOK_TAG_MAX = 12;        // 单个标签字数
const COOK_TAGS_MAX = 8;        // 每份食谱标签数
const COOK_ING_MAX = 40;        // 食材行数
const COOK_STEP_MAX = 40;       // 步骤数
const COOK_STEP_LEN = 1000;     // 单步字数
const COOK_DIARY_MAX = 100;     // 单份食谱的下厨日记条数
const COOK_MAX_PER_USER = 200;  // 每人食谱上限
const COOK_SHOP_MAX = 100;      // 购物清单条数上限
const COOK_FRIDGE_MAX = 200;    // 冰箱食材条数上限
const COOK_SQUARE_MAX = 300;    // 广场返回条数上限
const COOK_TEXT_MAX = 200;      // 食材名 / 用量 / 心得改动等短文本
const COOK_MAX_TS = 4102444800000; /* 2100-01-01，用于挡住异常时间戳 */

/* 菜系 / 菜品类型：前端也是这两张表，必须保持一致（存的是中文名本身） */
const COOK_CUISINES = ['中式', '意式', '日式', '韩式', '泰式', '墨西哥菜', '美式', '法式', '西班牙菜',
  '印度菜', '希腊菜', '越南菜', '地中海菜', '中东菜', '土耳其菜', '英式', '德式', '巴西菜', '加勒比菜'];
const COOK_DISH_TYPES = ['凉菜', '早餐', '面食', '米饭', '主菜', '肉类', '海鲜', '素菜', '沙拉', '配菜',
  '蘸酱与酱汁', '汤类', '小吃', '烘焙', '甜点', '饮品', '其他'];
/* 食材分组：main 主料 / aux 辅料 / season 调料（旧数据没有 group，按主料处理） */
const COOK_ING_GROUPS = ['main', 'aux', 'season'];

function cookText(s, max) {
  return String(s == null ? '' : s).replace(/\s+/g, ' ').trim().slice(0, max || COOK_TEXT_MAX);
}
/* 保留换行的文本清洗：步骤说明与私房笔记都是多行的，不能被压成一行 */
function cookTextMulti(s, max) {
  return String(s == null ? '' : s)
    .replace(/\r\n?/g, '\n')
    .replace(/[ \t]+/g, ' ')
    .replace(/ *\n */g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
    .slice(0, max || COOK_TEXT_MAX);
}
function cookNum(v, min, max) {
  const n = parseInt(v, 10);
  if (!isFinite(n)) return min;
  return Math.min(max, Math.max(min, n));
}
/* 生成全局唯一食谱 id（撞了就重摇，最多 8 次，兜底再拼时间戳） */
function cookId() {
  for (let i = 0; i < 8; i++) {
    const id = newId();
    if (!cookRecipes.some(function (r) { return r.id === id; })) return id;
  }
  return newId() + Date.now().toString(36);
}
function cookTags(v) {
  if (!Array.isArray(v)) return [];
  const out = [];
  for (let i = 0; i < v.length && out.length < COOK_TAGS_MAX; i++) {
    const t = cookText(v[i], COOK_TAG_MAX);
    if (t && out.indexOf(t) === -1) out.push(t);
  }
  return out;
}
/* 食材：{name, amount, group}。group 只认 main/aux/season，其余一律当主料，
   这样 2026-10-16 之前存下的老食谱（没有 group）会自动落进「主料」而不丢。 */
function cookIngredients(v) {
  if (!Array.isArray(v)) return [];
  const out = [];
  for (let i = 0; i < v.length && out.length < COOK_ING_MAX; i++) {
    const it = v[i] || {};
    const name = cookText(it.name, COOK_TEXT_MAX);
    if (!name) continue;   /* 前端允许留空行，空行直接丢弃 */
    const g = COOK_ING_GROUPS.indexOf(it.group) > -1 ? it.group : 'main';
    out.push({ name: name, amount: cookText(it.amount, 60), group: g });
  }
  return out;
}
/* 只接受本站自己的食谱图路径，挡掉外链 / 相对路径注入 */
function cookImgPath(s) {
  const m = /^\/api\/img\/cook\/([A-Za-z0-9_-]+\.jpg)$/.exec(String(s || ''));
  return m ? '/api/img/cook/' + m[1] : '';
}
/* 步骤：{text, img, timer}。旧数据是纯字符串，这里统一升级成对象，
   前端渲染时两种都能吃，但落盘一律是对象。 */
function cookSteps(v) {
  if (!Array.isArray(v)) return [];
  const out = [];
  for (let i = 0; i < v.length && out.length < COOK_STEP_MAX; i++) {
    const raw = v[i];
    let text = '', img = '', timer = 0;
    if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
      text = cookTextMulti(raw.text, COOK_STEP_LEN);
      img = cookImgPath(raw.img);
      timer = cookNum(raw.timer, 0, 600);   /* 单步计时上限 10 小时，够用了 */
    } else {
      text = cookTextMulti(raw, COOK_STEP_LEN);
    }
    if (!text && !img) continue;   /* 既没字也没图，空步骤丢掉 */
    out.push({ text: text, img: img, timer: timer });
  }
  return out;
}
/* 菜系 / 菜品类型：只收白名单里的值，非法值存空串（老食谱没有这两个字段） */
function cookPick(list, v) {
  const s = cookText(v, 20);
  return list.indexOf(s) > -1 ? s : '';
}
/* 下厨日记：只保留最近 COOK_DIARY_MAX 条（超出丢最旧的，避免单文件无限膨胀） */
function cookDiary(v) {
  if (!Array.isArray(v)) return [];
  const out = [];
  const start = Math.max(0, v.length - COOK_DIARY_MAX);
  for (let i = start; i < v.length; i++) {
    const d = v[i] || {};
    const tweaks = cookText(d.tweaks, COOK_TEXT_MAX);
    const result = cookTextMulti(d.result, 500);
    if (!tweaks && !result) continue;   /* 空日记不入库 */
    out.push({
      id: cookText(d.id, 40) || newId(),
      date: /^\d{4}-\d{2}-\d{2}$/.test(d.date) ? d.date : dayStr(),
      tweaks: tweaks,
      rating: cookNum(d.rating, 0, 5),
      result: result,
      ts: cookNum(d.ts, 0, COOK_MAX_TS) || Date.now()
    });
  }
  return out;
}
function cookShoppingClean(v) {
  if (!Array.isArray(v)) return [];
  const out = [];
  for (let i = 0; i < v.length && out.length < COOK_SHOP_MAX; i++) {
    const it = v[i] || {};
    const text = cookText(it.text, 80);
    if (!text) continue;
    out.push({ id: cookText(it.id, 40) || newId(), text: text, done: !!it.done });
  }
  return out;
}
/* 日期：只收 YYYY-MM-DD，其余存空串（前端 date input 天然是这个格式） */
function cookDate(s) {
  const t = String(s == null ? '' : s).trim();
  return /^\d{4}-\d{2}-\d{2}$/.test(t) ? t : '';
}
/* 冰箱食材清洗：name 必填，qty 存字符串（「少许」「适量」这类没法当数字），unit 限白名单 */
const COOK_UNITS = ['个', '包', '瓶', '罐', '把', '克', '斤', '毫升', '升', '杯', '少许', '适量'];
function cookFridgeClean(v) {
  if (!Array.isArray(v)) return [];
  const out = [];
  for (let i = 0; i < v.length && out.length < COOK_FRIDGE_MAX; i++) {
    const it = v[i] || {};
    const name = cookText(it.name, 40);
    if (!name) continue;
    const unit = COOK_UNITS.indexOf(String(it.unit || '')) > -1 ? String(it.unit) : '个';
    out.push({
      id: cookText(it.id, 40) || newId(),
      name: name,
      qty: cookText(it.qty, 20) || '1',
      unit: unit,
      buyDate: cookDate(it.buyDate),
      expDate: cookDate(it.expDate)   /* 空 = 没设到期日 */
    });
  }
  return out;
}
/* 后端 → 本人（完整字段，含下厨日记） */
function cookPubMine(r) {
  /* 从广场收藏来的副本保留原作者；自己写的食谱作者就是自己 */
  const author = r.fromOwner || r.uid;
  return {
    id: r.id, name: r.name, emoji: r.emoji, tags: r.tags || [],
    cuisine: r.cuisine || '', dishType: r.dishType || '', cover: r.cover || '',
    prepMin: r.prepMin || 0, cookMin: r.cookMin || 0, calories: r.calories || 0,
    source: r.source || '', servings: r.servings || 0,
    ingredients: r.ingredients || [], steps: r.steps || [], note: r.note || '',
    diary: r.diary || [],
    owner: author, ownerAv: avatarOf(author), fromOwner: r.fromOwner || '',
    visibility: r.visibility === 'public' ? 'public' : 'private',
    createdAt: r.createdAt, updatedAt: r.updatedAt
  };
}
/* 后端 → 广场（公开字段；故意不含 uid 与 diary —— 下厨日记只属于本人） */
function cookPubSquare(r, me) {
  return {
    id: r.id, name: r.name, emoji: r.emoji, tags: r.tags || [],
    cuisine: r.cuisine || '', dishType: r.dishType || '', cover: r.cover || '',
    prepMin: r.prepMin || 0, cookMin: r.cookMin || 0, calories: r.calories || 0,
    source: r.source || '', servings: r.servings || 0,
    ingredients: r.ingredients || [], steps: r.steps || [], note: r.note || '',
    owner: r.uid, ownerAv: avatarOf(r.uid),
    mine: !!me && r.uid === me.name,
    cookCount: (r.diary || []).length,
    createdAt: r.createdAt, updatedAt: r.updatedAt
  };
}
/* 新建 / 更新一份食谱：id 命中且属于本人则更新，否则新建（id 由服务端生成） */
function cookPut(uid, src) {
  const r = src || {};
  const name = cookText(r.name, COOK_NAME_MAX);
  if (!name) return { err: '食谱得有个名字' };
  const rid = cookText(r.id, 40);
  let rec = rid ? cookRecipes.find(function (x) { return x.id === rid; }) : null;
  if (rec && rec.uid !== uid) return { err: '只能编辑自己的食谱', code: 403 };
  const now = Date.now();
  if (!rec) {
    const mine = cookRecipes.filter(function (x) { return x.uid === uid; });
    if (mine.length >= COOK_MAX_PER_USER) return { err: '食谱最多 ' + COOK_MAX_PER_USER + ' 份，删掉一些再存吧' };
    rec = { id: cookId(), uid: uid };
    /* 仅新建时记录来源作者（收录副本），更新时不可篡改 */
    const fromOwner = cookText(r.fromOwner, 40);
    if (fromOwner && fromOwner !== uid) rec.fromOwner = fromOwner;
    cookRecipes.push(rec);
  }
  rec.name = name;
  rec.emoji = cookText(r.emoji, 16) || '🍳';
  rec.tags = cookTags(r.tags);
  rec.source = cookText(r.source, 500);
  rec.servings = cookNum(r.servings, 0, 99);
  rec.cuisine = cookPick(COOK_CUISINES, r.cuisine);
  rec.dishType = cookPick(COOK_DISH_TYPES, r.dishType);
  rec.cover = cookImgPath(r.cover);
  rec.prepMin = cookNum(r.prepMin, 0, 24 * 60);
  rec.cookMin = cookNum(r.cookMin, 0, 24 * 60);
  rec.calories = cookNum(r.calories, 0, 20000);
  rec.ingredients = cookIngredients(r.ingredients);
  rec.steps = cookSteps(r.steps);
  rec.note = cookTextMulti(r.note, 2000);
  rec.diary = cookDiary(r.diary);
  rec.visibility = (r.visibility === 'public') ? 'public' : 'private';
  rec.createdAt = cookNum(r.createdAt, 0, COOK_MAX_TS) || now;
  rec.updatedAt = now;
  saveCook();
  return { rec: rec };
}
/* 改昵称时把食谱与购物清单一并过户，否则数据会「凭空消失」 */
function cookMigrateUser(oldName, name) {
  let dirty = false;
  cookRecipes.forEach(function (r) {
    if (r.uid === oldName) { r.uid = name; dirty = true; }
    /* 别人收藏过我的食谱：署名跟着改昵称走 */
    if (r.fromOwner === oldName) { r.fromOwner = name; dirty = true; }
  });
  if (cookShopping[oldName]) {
    /* 新昵称一般没有条目；已有则接在后面，避免覆盖丢数据 */
    const merged = (Array.isArray(cookShopping[name]) ? cookShopping[name] : []).concat(cookShopping[oldName]);
    cookShopping[name] = merged.slice(0, COOK_SHOP_MAX);
    delete cookShopping[oldName];
    dirty = true;
  }
  if (cookFridge[oldName]) {
    const merged = (Array.isArray(cookFridge[name]) ? cookFridge[name] : []).concat(cookFridge[oldName]);
    cookFridge[name] = merged.slice(0, COOK_FRIDGE_MAX);
    delete cookFridge[oldName];
    dirty = true;
  }
  if (dirty) saveCook();
}

function bdayOf(u) {
  if (!u) return null;
  if (u.bday && u.bday.month && u.bday.day) return { month: u.bday.month, day: u.bday.day };
  if (u.birth && u.birth.month && u.birth.day) return { month: u.birth.month, day: u.birth.day };
  return null;
}

/* ---------------- ★消息通知已读标记（按用户，单文件存储） ---------------- */
const notifReadFile = path.join(DATA_DIR, 'notif-read.json');
let notifRead = readJson(notifReadFile, { marks: {} }).marks || {};
function saveNotifRead() { writeAtomic(notifReadFile, { marks: notifRead }); }

/* ---------------- ★社区举报队列（仅运营者审核，不在前端公开） ----------------
   每条记录保留被举报内容的短快照与 targetUid，便于处理；
   账号注销时会删除该用户提交的举报，并把针对该用户内容的举报匿名化。 */
const reportsFile = path.join(DATA_DIR, 'reports.json');
let reports = readJson(reportsFile, { items: [] }).items || [];
function saveReports() { writeAtomic(reportsFile, { items: reports }); }
const REPORT_REASONS = ['垃圾广告', '辱骂攻击', '色情低俗', '违法违规', '侵犯隐私', '其他'];
const REPORT_MAX = 5000;

/* 删除帖子/评论/食谱附带的图片或语音文件（只接受受控文件名） */
function removeUploaded(url, dir) {
  const m = /\/([A-Za-z0-9_-]+\.(?:jpg|jpeg|png|webp|webm|mp4|m4a|ogg|oga|mp3|wav))$/.exec(String(url || ''));
  if (m) { try { fs.unlinkSync(path.join(dir, m[1])); } catch (e) {} }
}
function removePostImage(url) { removeUploaded(url, IMG_DIR); }
function removePostVoice(url) { removeUploaded(url, VOICE_DIR); }
function removeCookImage(url) { removeUploaded(url, COOK_DIR); }

/* ---------------- ★中秋猜灯谜（按中秋日持久化，登录才能猜） ---------------- */
const lanternFile = path.join(DATA_DIR, 'lantern.json');
let lanternDays = readJson(lanternFile, { days: {} }).days || {};
function saveLantern() { writeAtomic(lanternFile, { days: lanternDays }); }
/* 正式灯谜 30 条（与 index.html 题面 q 对齐）；谜底只在此处 */
const LANTERN_RIDDLES = [
  { id: 1, q: "十五的月亮（打一成语）", a: ["正大光明"] },
  { id: 2, q: "中秋赏菊（打一成语）", a: ["花好月圆"] },
  { id: 3, q: "举头望明月（打一中药名）", a: ["当归"] },
  { id: 4, q: "广寒宫中伴嫦娥（打一动物）", a: ["玉兔"] },
  { id: 5, q: "圆圆甜饼香又甜，中秋家家都尝鲜（打一食物）", a: ["月饼"] },
  { id: 6, q: "夜空挂银盘，十五圆又满（打一天体）", a: ["月亮"] },
  { id: 7, q: "云盖中秋月（打一字）", a: ["育"] },
  { id: 8, q: "中秋去旅游（打一成语）", a: ["喜出望外"] },
  { id: 9, q: "八月十五的月亮（打一山西地名）", a: ["太原"] },
  { id: 10, q: "嫦娥的居所（打一神话地名）", a: ["广寒宫"] },
  { id: 11, q: "中秋桂下叙家常（打一成语）", a: ["花前月下"] },
  { id: 12, q: "十五天（打一字）", a: ["胖"] },
  { id: 13, q: "掬水月在手（打一成语）", a: ["掌上明珠"] },
  { id: 14, q: "八月十五分月饼（打一成语）", a: ["平分秋色"] },
  { id: 15, q: "中秋国庆传捷报（打一成语）", a: ["节节胜利"] },
  { id: 16, q: "中秋结伴去出游（打一旅游名词）", a: ["观光团"] },
  { id: 17, q: "中秋过后又重阳（打一俗语）", a: ["一节接一节"] },
  { id: 18, q: "嫦娥奔月（打一成语）", a: ["远走高飞"] },
  { id: 19, q: "中秋家家庆团圆（打一成语）", a: ["普天同庆"] },
  { id: 20, q: "月有阴晴圆缺（打一财经名词）", a: ["盈亏"] },
  { id: 21, q: "一轮明月照窗前（打一礼貌用语）", a: ["光临寒舍"] },
  { id: 22, q: "广寒宫的桂树（打一成语）", a: ["高不可攀"] },
  { id: 23, q: "一轮明月挂疏林（打一字）", a: ["梦"] },
  { id: 24, q: "广寒宫中奏仙乐（打一成语）", a: ["不同凡响"] },
  { id: 25, q: "明月松间照（打一成语）", a: ["黑白分明"] },
  { id: 26, q: "中秋前后巧相逢（打一字）", a: ["种"] },
  { id: 27, q: "中秋大丰收（打一江苏城市）", a: ["常熟"] },
  { id: 28, q: "明月照我还（打一成语）", a: ["回光返照"] },
  { id: 29, q: "闰八月（打一成语）", a: ["多事之秋"] },
  { id: 30, q: "举杯邀月成三人（打一成语）", a: ["举一反三"] }
];
/* 附加题：emoji 猜成语（抽取制，每题 0.5 分，答对才能抽下一题） */
const LANTERN_EMOJI = [
  { id: 1, emoji: "👀🚀🌈💃", a: ["眉飞色舞"] },
  { id: 2, emoji: "9️⃣🐂1️⃣🐱", a: ["九牛一毛"] },
  { id: 3, emoji: "🪑🗾👀🌌", a: ["坐井观天"] },
  { id: 4, emoji: "🖊️🛶🔍🗡️", a: ["刻舟求剑"] },
  { id: 5, emoji: "🐑➡️🐅👄", a: ["羊入虎口"] },
  { id: 6, emoji: "🖌️🐍➕🦶", a: ["画蛇添足"] },
  { id: 7, emoji: "👊🌿😲🐍", a: ["打草惊蛇"] },
  { id: 8, emoji: "❌🐑🧱🏠", a: ["亡羊补牢"] },
  { id: 9, emoji: "🐟👀👹🐷", a: ["鱼目混珠"] },
  { id: 10, emoji: "👀🍓⛔️🥵", a: ["望梅止渴"] },
  { id: 11, emoji: "🐔✈🐕🕺", a: ["鸡飞狗跳"] },
  { id: 12, emoji: "1️⃣👀🕰💘", a: ["一见钟情"] },
  { id: 13, emoji: "❤️❤️🤝👣", a: ["心心相印"] },
  { id: 14, emoji: "🚗💧🐎🐉", a: ["车水马龙"] },
  { id: 15, emoji: "👨🤸🐎🤯", a: ["人仰马翻"] },
  { id: 16, emoji: "🍜🔴👂🦅", a: ["面红耳赤"] },
  { id: 17, emoji: "🔙❤️≈🏹", a: ["归心似箭"] },
  { id: 18, emoji: "😠🔥🏹🔥", a: ["怒火中烧"] },
  { id: 19, emoji: "🚶🐎👀🌼", a: ["走马观花"] },
  { id: 20, emoji: "👋👂👤🔔", a: ["掩耳盗铃"] },
  { id: 21, emoji: "🍃👴😍🐉", a: ["叶公好龙"] },
  { id: 22, emoji: "🐔✈️🐕👯", a: ["鸡飞狗跳"] },
  { id: 23, emoji: "👓🕵️‍♂️🦣", a: ["盲人摸象"] },
  { id: 24, emoji: "💧➡️🛣️✅", a: ["水到渠成"] },
  { id: 25, emoji: "💨🌸❄️🌙", a: ["风花雪月"] },
  { id: 26, emoji: "💋❌🦷🥶", a: ["唇亡齿寒"] },
  { id: 27, emoji: "👨‍🦱⬆️🐎🌀", a: ["人仰马翻"] },
  { id: 28, emoji: "🥛🏹🐍👀", a: ["杯弓蛇影"] },
  { id: 29, emoji: "🕷️🧵🐎👣", a: ["蛛丝马迹"] },
  { id: 30, emoji: "🐉🐎💪", a: ["龙马精神"] }
];
function lanternNorm(s) {
  return String(s || '').trim().toLowerCase().replace(/[\s　·・，,。.！!？?、;；:：'\"“”‘’（）()【】\[\]]/g, '');
}
function lanternAnswerOk(riddle, answer) {
  const n = lanternNorm(answer);
  if (!n) return false;
  return (riddle.a || []).some(function (x) { return lanternNorm(x) === n; });
}
function lanternDayBox(date) {
  if (!lanternDays[date]) lanternDays[date] = { solves: {} };
  if (!lanternDays[date].solves) lanternDays[date].solves = {};
  if (!lanternDays[date].emoji) lanternDays[date].emoji = {};
  return lanternDays[date];
}
function lanternEmojiUser(box, name) {
  if (!box.emoji[name]) box.emoji[name] = { current: null, solved: [] };
  return box.emoji[name];
}
function lanternOpenState() {
  /* 中秋 00:00 起可进可答，至次日 03:00（UTC+8）收卷。2026：09-25 ~ 09-26 03:00 */
  const w = lanternWindow();
  const now = Date.now();
  return {
    date: w ? w.date : dayStr(),
    open: !!w && now < w.endMs,
    closedAfter: w ? w.closedAfter : (dayStr() + ' 03:00'),
    isMidAutumn: !!w, /* 活动档期：入口/作答同一窗口 */
    active: !!w
  };
}
function isZhongqiuDate(date) {
  return !!lanternWindowForZq(date);
}
function lanternWindow() {
  const now = Date.now();
  const ZQ = ["2025-10-06", "2026-09-25", "2027-09-15", "2028-10-03", "2029-09-22"];
  for (let i = 0; i < ZQ.length; i++) {
    const w = lanternWindowForZq(ZQ[i]);
    if (w && now >= w.startMs && now < w.endMs) return w;
  }
  return null;
}
function lanternWindowForZq(zq) {
  if (!zq) return null;
  const startMs = Date.parse(zq + 'T00:00:00+08:00');
  const endMs = Date.parse(nextDayStr(zq) + 'T03:00:00+08:00');
  return { date: zq, startMs: startMs, endMs: endMs, closedAfter: nextDayStr(zq) + ' 03:00' };
}
function nextDayStr(date) {
  const t = Date.parse(date + 'T00:00:00Z') + 86400000;
  return new Date(t).toISOString().slice(0, 10);
}

/* ---------------- ★星座运势：锁定 + 全站按日缓存（省万维易源额度） ---------------- */
/* 万维易源 appKey：环境变量 SHOWAPI_KEY 或 config.local.json 配置（不写进仓库） */
const SHOWAPI_KEY = envCfg('SHOWAPI_KEY', '');
const SHOWAPI_STAR = {
  aries: 'baiyang', taurus: 'jinniu', gemini: 'shuangzi', cancer: 'juxie',
  leo: 'shizi', virgo: 'chunv', libra: 'tiancheng', scorpio: 'tianxie',
  sagittarius: 'sheshou', capricorn: 'mojie', aquarius: 'shuiping', pisces: 'shuangyu'
};
const zodiacSignsFile = path.join(DATA_DIR, 'zodiac-signs.json');     // 键：u:昵称 / d:设备号
const zodiacFortFile = path.join(DATA_DIR, 'zodiac-fortunes.json');   // 键：YYYY-MM-DD:aries
let zodiacSigns = readJson(zodiacSignsFile, { signs: {} }).signs || {};
let zodiacForts = readJson(zodiacFortFile, { days: {} }).days || {};
const zodiacDrawFile = path.join(DATA_DIR, 'zodiac-draws.json');       // 每日运签：键为 身份|日期
let zodiacDraws = readJson(zodiacDrawFile, { draws: {} }).draws || {};
function saveZodiacSigns() { writeAtomic(zodiacSignsFile, { signs: zodiacSigns }); }
function saveZodiacForts() { writeAtomic(zodiacFortFile, { days: zodiacForts }); }
function saveZodiacDraws() { writeAtomic(zodiacDrawFile, { draws: zodiacDraws }); }

/* ---------------- ★玩法抽签（无畏契约整活）：全站最近记录 + 10 分钟冷却 ----------------
   登录按账号、游客按设备 ID 记冷却；只保留最近 60 条，内容必须是预设池里的原文，
   避免有人把任意文本推到所有人的列表里。池子与 flutter/lib/data/puns.dart 保持一致。 */
const PLAY_PUNS = [
  '使用技能要说技能', '听到爆点拿出盘盘', '听到报点丢枪', '听到报点蹲下',
  '全程只能使用鬼魅', '全程禁止使用跳跃', '只能用英语交流', '全程禁止使用Q技能',
  '全程禁止使用C技能', '全程禁止使用E技能', '全程禁止使用技能', '不许拆包/下包',
  '不能进入爆能器部署区域', '只能刀人', '只能使用冲锋枪', '只能使用手枪',
  '全程必须开镜', '无准星', '不能用皮肤', '只能用一个弹夹', '只能瞄地走路',
  '只能打对面战绩垫底的', '全程模仿所选角色语音', '说话只能用成语',
  '只能用骇灵和标配', '只能用技能', '不能发枪/要枪', '不许起甲',
  '灵敏度最低', '灵敏度拉满', '灵敏度减半', '灵敏度翻倍',
  '只能用鸟狙和标配', '只能跑打', '每小局报三次自己的位置给对方',
  '当宝宝，对队内实时第一名提供情绪价值', '不/只能静步', '只能蹲下走路（半场）',
  '限喷子（半场）', '开枪键与跳绑一起（半场）', '大冒险（不过分即可）',
  '真心话（不过分即可）', '开一枪丢一次枪', '开一枪喷漆一次',
  '退弹（只能用每个弹夹最后一发）',
  '小姐（每杀一个人说：老板走好。每次被击杀说：mua+对方id）',
  '殉情（队内第一阵亡，需要跟着一起）',
  '只能前往a包点', '只能前往b包点',
  '所有人喊乌萨奇都得喊“到！”（开局把这个规则告知对面）',
  '螃蟹（只能AD移动）', '定身（只要有人释放技能定身2s）',
  '士兵（不能后退）', '泉水指挥官（不能对枪）',
  '走地鸡（只能选择一突且不能脱离地面和不能高速位移）',
  '唱一首歌', 'all in（每把都花光所有的钱）',
  '队伍里任何人造成击杀喊“Banana！”',
  '只能跳着走路', '游戏限制30帧'
];
const PLAY_CD_MS = 10 * 60 * 1000;
const PLAY_KEEP = 60;
const playFile = path.join(DATA_DIR, 'play.json');
const playRaw = readJson(playFile, {});
let playRecords = Array.isArray(playRaw.records)
  ? playRaw.records.filter(function (r) { return r && typeof r.t === 'string' && typeof r.ts === 'number'; })
  : [];
let playCooldowns = (playRaw.cooldowns && typeof playRaw.cooldowns === 'object' && !Array.isArray(playRaw.cooldowns))
  ? playRaw.cooldowns : {};
function savePlay() { writeAtomic(playFile, { records: playRecords, cooldowns: playCooldowns }); }
function playKeyOf(me, deviceId) {
  if (me && me.name) return 'u:' + me.name;
  const g = String(deviceId || '').trim();
  return GID_RE.test(g) ? 'g:' + g : null;
}
function playList(key) {
  const now = Date.now();
  return {
    ok: true,
    cd: key ? Math.max(0, (parseInt(playCooldowns[key], 10) || 0) - now) : 0,
    records: playRecords.slice(-40).reverse().map(function (r) {
      return { t: r.t, name: r.name, ts: r.ts, you: !!key && r.key === key };
    })
  };
}

/* 星盘解读缓存：本命 = 出生数据 SHA1（永久复用）；行运 = 出生数据+当天日期（按天复用） */
const astroInterpretFile = path.join(DATA_DIR, 'astro-interprets.json');
let astroInterprets = readJson(astroInterpretFile, { items: {} }).items || {};
function saveAstroInterprets() { writeAtomic(astroInterpretFile, { items: astroInterprets }); }

/* ---------------- ★历史上的今天：全站按天缓存一份（UTC+8 当天复用） ---------------- */
const historyTodayFile = path.join(DATA_DIR, 'history-today.json');
let historyToday = readJson(historyTodayFile, null);
if (!historyToday || typeof historyToday !== 'object' || Array.isArray(historyToday)) historyToday = null;
function saveHistoryToday() { writeAtomic(historyTodayFile, historyToday); }
function astroInterpretKey(birth, scope){
  const norm = {
    y: birth.year, m: birth.month, d: birth.day,
    h: birth.hour, mi: birth.minute,
    lat: Math.round(birth.lat*100)/100,
    lng: Math.round(birth.lng*100)/100,
    tz: birth.tz || 'Asia/Shanghai'
  };
  /* 行运按「出生地时区的今天」分片缓存，跨天自动失效 */
  if (scope === 'transit') {
    let day = '';
    try {
      day = new Intl.DateTimeFormat('en-CA', { timeZone: norm.tz }).format(new Date());
    } catch (e) {
      day = new Date().toISOString().slice(0, 10);
    }
    norm.scope = 'transit:' + day;
  }
  return crypto.createHash('sha1').update(JSON.stringify(norm)).digest('hex');
}

/* 同日同星座并发请求只打一次上游 */
const zodiacInflight = {};

function zodiacKeyOf(me, deviceId) {
  if (me && me.name) return 'u:' + me.name;
  if (deviceId) return 'd:' + String(deviceId).slice(0, 64);
  return null;
}
function validZodiac(sign) {
  return !!(sign && Object.prototype.hasOwnProperty.call(SHOWAPI_STAR, sign));
}
function mapShowApiDay(day, sign, date) {
  if (!day || !day.general_txt) return null;
  function s2p(star) {
    const n = parseInt(star, 10);
    if (isNaN(n) || n < 1 || n > 5) return null;
    return 50 + n * 10;
  }
  let text = String(day.general_txt || '').trim();
  if (day.day_notice) text += (text ? ' ' : '') + String(day.day_notice).trim();
  return {
    source: 'showapi',
    sign: sign,
    day: date,
    score: s2p(day.summary_star),
    tag: day.lucky_time ? ('开运 ' + day.lucky_time) : '今日开运',
    text: text,
    love: s2p(day.love_star),
    work: s2p(day.work_star),
    wealth: s2p(day.money_star),
    health: s2p(day.summary_star),
    color: day.lucky_color || null,
    number: day.lucky_num || null,
    item: day.lucky_direction || null,
    ts: Date.now()
  };
}
function fetchShowApiFortune(sign) {
  const star = SHOWAPI_STAR[sign];
  if (!star) return Promise.reject(new Error('unknown sign ' + sign));
  const month = new Date(Date.now() + 8 * 3600 * 1000).getUTCMonth() + 1;
  const url = 'https://route.showapi.com/872-1?appKey=' + encodeURIComponent(SHOWAPI_KEY) +
    '&star=' + encodeURIComponent(star) + '&month=' + month;
  return fetch(url, { signal: AbortSignal.timeout(15000) }).then(function (r) {
    if (!r.ok) throw new Error('http ' + r.status);
    return r.json();
  }).then(function (j) {
    if (!j || j.showapi_res_code !== 0) throw new Error((j && j.showapi_res_error) || 'showapi fail');
    const body = j.showapi_res_body;
    if (!body || body.ret_code !== 0) throw new Error((body && body.remark) || 'biz fail');
    return body.day || null;
  });
}
function getZodiacFortune(sign) {
  const date = dayStr();
  const ck = date + ':' + sign;
  const hit = zodiacForts[ck];
  /* 命中缓存直接返回（整日有效） */
  if (hit && hit.text) return Promise.resolve({ ok: true, data: hit, cached: true });
  if (zodiacInflight[ck]) return zodiacInflight[ck];
  const p = fetchShowApiFortune(sign).then(function (day) {
    const mapped = mapShowApiDay(day, sign, date);
    if (!mapped || !mapped.text) throw new Error('empty');
    zodiacForts[ck] = mapped;
    saveZodiacForts();
    return { ok: true, data: mapped, cached: false };
  }).catch(function (e) {
    console.error('[zodiac] showapi fail', sign, e && e.message);
    return { ok: false, err: '运势接口暂不可用，请稍后再试', detail: String(e && e.message || e) };
  }).then(function (r) {
    delete zodiacInflight[ck];
    return r;
  });
  zodiacInflight[ck] = p;
  return p;
}

function pubNote(n, me) {
  return {
    id: n.id, uid: n.uid,
    title: n.title, content: n.content,
    ts: n.ts, updated: n.updated,
    mine: !!me && n.uid === me.name
  };
}

function avatarOf(name) {
  const u = findUser(name);
  return (u && u.av) ? '/api/img/avatars/' + u.av : null;
}
function pub(p, me) {
  return {
    id: p.id, anon: !!p.anon, nick: p.anon ? p.nick : p.uid,
    mine: !!me && p.uid === me.name,
    av: p.anon ? null : avatarOf(p.uid),
    text: p.text, likes: p.likes, hugs: p.hugs,
    voice: p.voice || null, voiceDur: p.voiceDur || 0,
    imgs: Array.isArray(p.imgs) ? p.imgs : [],
    liked: !!me && p.likers.indexOf(me.name) !== -1,
    hugged: !!me && p.huggers.indexOf(me.name) !== -1,
    nComments: (p.comments || []).length,
    comments: (p.comments || []).map(function (c) { return pubComment(c, me); }),
    ts: p.ts
  };
}
/* 评论公开字段：replyTo 为被回复者昵称快照（目标评论删除后仍可显示） */
function pubComment(c, me) {
  return { id: c.id, anon: !!c.anon, nick: c.anon ? c.nick : c.uid,
    av: c.anon ? null : avatarOf(c.uid), text: c.text,
    replyTo: (c.reply && c.reply.nick) || null,
    voice: c.voice || null, voiceDur: c.voiceDur || 0,
    imgs: Array.isArray(c.imgs) ? c.imgs : [],
    mine: !!me && c.uid === me.name, ts: c.ts };
}

/* ---------------- 账号 / 会话 ---------------- */
const usersFile = path.join(DATA_DIR, 'users.json');
const sessFile = path.join(DATA_DIR, 'sessions.json');
let users = readJson(usersFile, { users: [] }).users || [];
let sessions = readJson(sessFile, { tokens: {} }).tokens || {};
function saveUsers() { writeAtomic(usersFile, { users: users }); }
function saveSessions() { writeAtomic(sessFile, { tokens: sessions }); }
function hashPw(pw, salt) { return crypto.scryptSync(pw, salt, 64).toString('hex'); }
function makeSalt() { return crypto.randomBytes(16).toString('hex'); }
function makeToken() { return crypto.randomBytes(32).toString('hex'); }
function findUser(name) { return users.find(function (u) { return u.name === name; }) || null; }
function findUserByPhone(phone) { return users.find(function (u) { return u.phone === phone; }) || null; }
function currentUser(req) {
  /* 主：HttpOnly Cookie（持久 Max-Age=30d）；兜底：X-Trash-Token 头（前端 localStorage 回传） */
  let tok = null;
  const m = /(?:^|;\s*)trash_token=([a-f0-9]+)/.exec(req.headers.cookie || '');
  if (m) tok = m[1];
  if (!tok) {
    const h = String(req.headers['x-trash-token'] || '').trim();
    if (/^[a-f0-9]{1,128}$/.test(h)) tok = h;
  }
  if (!tok) return null;
  const s = sessions[tok];
  if (!s) return null;
  if (s.exp < Date.now()) { delete sessions[tok]; saveSessions(); return null; }
  return { name: s.name, token: tok };
}
function setCookie(res, req, token) {
  const proto = String((req.headers['x-forwarded-proto'] || '').split(',')[0]).trim();
  const origin = String(req.headers.origin || '');
  /* APK 跨域（origin=https://localhost）需 SameSite=None 才能種 Cookie；網站同源保持 Lax 更安全 */
  const ss = (origin && origin !== 'https://chimu-claw.xyz') ? 'None' : 'Lax';
  let c = 'trash_token=' + token + '; Path=/; HttpOnly; SameSite=' + ss + '; Max-Age=' + (SESSION_DAYS * 86400);
  if (proto === 'https' || ss === 'None') c += '; Secure';  /* SameSite=None 必須 Secure；API 永遠走 HTTPS */
  res.setHeader('Set-Cookie', c);
}
function clearCookie(res, req) {
  const proto = String((req.headers['x-forwarded-proto'] || '').split(',')[0]).trim();
  const origin = String(req.headers.origin || '');
  const ss = (origin && origin !== 'https://chimu-claw.xyz') ? 'None' : 'Lax';
  let c = 'trash_token=; Path=/; HttpOnly; SameSite=' + ss + '; Max-Age=0';
  if (proto === 'https' || ss === 'None') c += '; Secure';  /* 同上 */
  res.setHeader('Set-Cookie', c);
}

/* ---------------- 小游戏成绩（按昵称/gid 记录最高分） ----------------
   白名单必须覆盖前端全部会落榜的游戏键，漏掉哪个键，那个游戏就会
   提交 400「未知游戏」而永远不上榜（前端对 4xx 不弹错，表现为空榜）。 */
const GAME_IDS = [
  '2048', 'memory:easy', 'memory:std', 'memory:hard',
  'sudoku:easy', 'sudoku:med', 'sudoku:hard', 'sudoku:exp',
  /* 统一数独入口：异形 / 雪花 / 重叠 / 高级阶数。经典四档沿用上面的旧键。 */
  'sudoku:jigsaw-medium', 'sudoku:jigsaw-hard', 'sudoku:jigsaw-expert',
  'sudoku:snowflake-hard', 'sudoku:snowflake-expert',
  'sudoku:overlap-2', 'sudoku:overlap-3', 'sudoku:overlap-4',
  'sudoku:overlap-5', 'sudoku:overlap-8', 'sudoku:overlap-13',
  'sudoku:windmill-hard', 'sudoku:windmill-expert',
  'sudoku:evenodd-hard', 'sudoku:evenodd-expert',
  'sudoku:diag-hard', 'sudoku:diag-expert',
  'sudoku:ineq-hard', 'sudoku:ineq-expert',
  'sudoku:killer-hard', 'sudoku:killer-expert',
  'sudoku:cube3d-hard', 'sudoku:cube3d-expert',
  'nono:easy', 'nono:std', 'nono:hard',
  'slide:easy', 'slide:std', 'slide:hard',
  'snake:easy', 'snake:std', 'snake:hard',
  'sheep', 'jump', 'peng', 'brake', 'idiom', 'feihua', 'liquid',
  /* 旧异形数独键保留给还没升级的客户端 */
  'jigsaw:easy', 'jigsaw:normal', 'jigsaw:hard', 'knockwater',
];
const gamesFile = path.join(DATA_DIR, 'games.json');
let gameScores = readJson(gamesFile, {});
if (!gameScores || typeof gameScores !== 'object' || Array.isArray(gameScores)) gameScores = {};
function saveGames() { writeAtomic(gamesFile, gameScores); }
function gameBoard(key) {
  const arr = Array.isArray(gameScores[key]) ? gameScores[key].slice() : [];
  arr.sort(function (a, b) { return (b.score - a.score) || ((a.ts || 0) - (b.ts || 0)); });
  return arr;
}
/* 游客昵称校验：形如「游客·青松明月」，前缀固定，后接 2-5 个中文，无数字 */
const GUEST_RE = /^游客·[一-龥]{2,5}$/;
function validGuestName(s) { return typeof s === 'string' && s.length <= 12 && GUEST_RE.test(s); }
/* 游客设备 ID：前端生成并持久保存的随机串（小写字母+数字）。
   旧版游客成绩按昵称记账 → 昵称可被两个人撞上/自行修改，会把别人的分数算到你头上。
   现在游客一律按 gid 记账，昵称只用于展示。 */
const GID_RE = /^[a-z0-9]{12,40}$/;
/* 定位游客记录：优先按 gid；若该 gid 尚无记录，则认领一条「按昵称存且尚未绑定 gid」
   的老记录（一次性平滑迁移，避免老玩家成绩凭空消失）。 */
function claimGuestRec(arr, gid, name) {
  for (const r of arr) { if (r && r.gid === gid) return { rec: r, adopted: false }; }
  for (const r of arr) { if (r && !r.gid && r.name === name) { r.gid = gid; return { rec: r, adopted: true }; } }
  return { rec: null, adopted: false };
}

/* ---------------- 小游戏「正在玩」在线表（内存态，不落盘） ----------------
   前端进入任一游戏页即每 4s POST /api/games/live 上报进度，离开时带 leave 下线；
   这里只登记「谁在玩 + 进度」，靠 TTL 判定离线，进程重启即清空（不需要持久化）。
   注意 game 用的是前端页面键（g2048/gmem/…），与成绩榜的 GAME_IDS 不是一套，别混用。 */
const LIVE_GAMES = ['g2048', 'gmem', 'gsudoku', 'gnono', 'gslide', 'gsnake', 'gsheep', 'gjump', 'gpeng', 'gbrake', 'gidiom', 'gfeihua', 'gliquid', 'gjigsaw', 'gknockwater'];
const LIVE_TTL = 20000;    // 心跳 4s，留 5 倍余量；超过即认为已离开
const LIVE_PROG_MAX = 60;  // 进度文案上限，防止被塞长文本
const liveUsers = new Map();   // game -> Map(身份 key -> { name, av, progress, ts })
function livePrune() {
  const now = Date.now();
  liveUsers.forEach(function (m, game) {
    m.forEach(function (r, id) { if (now - r.ts > LIVE_TTL) m.delete(id); });
    if (!m.size) liveUsers.delete(game);
  });
}
setInterval(livePrune, 60000);

/* ---------------- 频率限制 ---------------- */
const hits = {};
function limited(ip, key, max, win) {
  const now = Date.now(), k = ip + ':' + key;
  const arr = (hits[k] || []).filter(function (t) { return now - t < win; });
  if (arr.length >= max) return true;
  arr.push(now); hits[k] = arr; return false;
}
setInterval(function () {
  const now = Date.now();
  for (const k in hits) { hits[k] = hits[k].filter(function (t) { return now - t < 60000; }); if (!hits[k].length) delete hits[k]; }
}, 60000);

/* ---------------- HTTP 辅助 ---------------- */
function clientIp(req) {
  const x = req.headers['x-forwarded-for'];
  return (x ? String(x).split(',')[0].trim() : null) || req.socket.remoteAddress || 'unknown';
}
function cors(res, code, ctype, body) {
  const origin = (res._req && res._req.headers.origin) || '*';
  res.writeHead(code, {
    'Content-Type': ctype + '; charset=utf-8',
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,X-Trash-Token',
    'Access-Control-Allow-Credentials': 'true',
    'Access-Control-Max-Age': '86400',
    'Cache-Control': 'no-store'
  });
  res.end(body);
}
function json(res, code, obj) { cors(res, code, 'application/json', JSON.stringify(obj)); }
function glmCompletion(payload) {
  return new Promise(function (resolve, reject) {
    const encoded = Buffer.from(JSON.stringify(payload));
    const req = https.request({
      hostname: 'open.bigmodel.cn',
      path: '/api/paas/v4/chat/completions',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Length': encoded.length,
        'Authorization': 'Bearer ' + GLM_API_KEY
      },
      timeout: 65000
    }, function (upstream) {
      let raw = '';
      upstream.setEncoding('utf8');
      upstream.on('data', function (chunk) {
        raw += chunk;
        if (raw.length > 4 * 1024 * 1024) {
          upstream.destroy();
          reject(new Error('AI 响应过大'));
        }
      });
      upstream.on('end', function () {
        let data = null;
        try { data = JSON.parse(raw); } catch (e) {}
        if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
          const message = data && data.error && data.error.message;
          reject(new Error(message || ('AI 服务返回 ' + upstream.statusCode)));
          return;
        }
        if (!data) {
          reject(new Error('AI 返回格式异常'));
          return;
        }
        resolve(data);
      });
    });
    req.on('timeout', function () { req.destroy(new Error('AI 响应超时')); });
    req.on('error', reject);
    req.end(encoded);
  });
}
function glmStream(payload, res) {
  const encoded = Buffer.from(JSON.stringify(payload));
  let started = false;
  const req = https.request({
    hostname: 'open.bigmodel.cn',
    path: '/api/paas/v4/chat/completions',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': encoded.length,
      'Authorization': 'Bearer ' + GLM_API_KEY,
      'Accept': 'text/event-stream'
    },
    timeout: 65000
  }, function (upstream) {
    if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
      let raw = '';
      upstream.setEncoding('utf8');
      upstream.on('data', function (chunk) { raw += chunk; });
      upstream.on('end', function () {
        let message = '';
        try {
          const data = JSON.parse(raw);
          message = data && data.error && data.error.message || '';
        } catch (e) {}
        if (!res.headersSent) {
          json(res, 502, { err: message || ('AI 服务返回 ' + upstream.statusCode) });
        } else {
          res.end();
        }
      });
      return;
    }
    started = true;
    const origin = (res._req && res._req.headers.origin) || '*';
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no',
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Credentials': 'true'
    });
    if (typeof res.flushHeaders === 'function') res.flushHeaders();
    upstream.pipe(res);
    upstream.on('end', function () { if (!res.writableEnded) res.end(); });
    res.on('close', function () {
      if (!upstream.complete) upstream.destroy();
    });
  });
  req.on('timeout', function () { req.destroy(new Error('AI 响应超时')); });
  req.on('error', function (e) {
    if (!started && !res.headersSent) {
      json(res, 502, { err: e && e.message ? e.message : 'AI 服务暂不可用' });
    } else if (!res.writableEnded) {
      res.end();
    }
  });
  req.end(encoded);
}
function readBody(req, max) {
  const limit = max || 16384;
  return new Promise(function (resolve) {
    let b = '', done = false, len = 0;
    req.on('data', function (c) {
      len += c.length;
      if (len > limit) { req.destroy(); if (!done) { done = true; resolve(null); } return; }
      b += c;
    });
    req.on('end', function () { if (!done) { done = true; resolve(b); } });
    req.on('error', function () { if (!done) { done = true; resolve(null); } });
  });
}
/* 解析 dataURL 图片（前端压缩后以 base64 提交） */
function parseDataUrl(s) {
  const m = /^data:image\/(jpeg|jpg|png|webp);base64,([a-z0-9+/=\s]+)$/i.exec(String(s || ''));
  if (!m) return null;
  let buf;
  try { buf = Buffer.from(m[2].replace(/\s/g, ''), 'base64'); } catch (e) { return null; }
  if (!buf.length || buf.length < 64) return null;
  return buf;
}
function imgName() { return newId() + '.jpg'; }
function serveImg(req, res, dir, file) {
  if (!/^[A-Za-z0-9_-]+\.jpg$/.test(file)) { res.writeHead(404); res.end('nope'); return; }
  const fp = path.join(dir, file);
  if (!fp.startsWith(dir) || !fs.existsSync(fp)) { res.writeHead(404); res.end('nope'); return; }
  let st;
  try { st = fs.statSync(fp); } catch (e) { res.writeHead(404); res.end('nope'); return; }
  /* 图片名即内容指纹（上传时随机生成、永不覆盖），可以放心长缓存；
     补上 Content-Length + ETag，客户端二次加载直接 304，不会再整张重传。 */
  const etag = '"' + st.size.toString(16) + '-' + Math.floor(st.mtimeMs).toString(16) + '"';
  const headers = {
    'Content-Type': 'image/jpeg',
    'Cache-Control': 'public, max-age=31536000, immutable',
    'Access-Control-Allow-Origin': '*',
    'ETag': etag,
    'Last-Modified': st.mtime.toUTCString()
  };
  if (String(req.headers['if-none-match'] || '') === etag) {
    res.writeHead(304, headers);
    res.end();
    return;
  }
  headers['Content-Length'] = st.size;
  res.writeHead(200, headers);
  if (req.method === 'HEAD') { res.end(); return; }
  fs.createReadStream(fp).pipe(res);
}
/* 解析 dataURL 语音（前端 MediaRecorder 录制后 base64 提交），返回 {buf, ext} */
const VOICE_EXT = { webm: 'audio/webm', mp4: 'audio/mp4', m4a: 'audio/mp4', ogg: 'audio/ogg', oga: 'audio/ogg', mpeg: 'audio/mpeg', mp3: 'audio/mpeg', wav: 'audio/wav' };
function parseVoiceUrl(s) {
  const m = /^data:audio\/([a-z0-9-]+)(?:;codecs=[a-z0-9,.=+-]+)?;base64,([a-z0-9+/=\s]+)$/i.exec(String(s || ''));
  if (!m) return null;
  let ext = m[1].toLowerCase();
  if (ext === 'x-m4a') ext = 'm4a';
  if (!VOICE_EXT[ext]) return null;
  let buf;
  try { buf = Buffer.from(m[2].replace(/\s/g, ''), 'base64'); } catch (e) { return null; }
  if (!buf.length || buf.length < 64) return null;
  return { buf: buf, ext: ext };
}
function serveVoice(req, res, file) {
  const m = /^([A-Za-z0-9_-]+)\.(webm|mp4|m4a|ogg|oga|mp3|wav)$/.exec(file);
  if (!m) { res.writeHead(404); res.end('nope'); return; }
  const fp = path.join(VOICE_DIR, file);
  if (!fp.startsWith(VOICE_DIR) || !fs.existsSync(fp)) { res.writeHead(404); res.end('nope'); return; }
  res.writeHead(200, {
    'Content-Type': VOICE_EXT[m[2]] || 'application/octet-stream',
    'Cache-Control': 'public, max-age=31536000, immutable',
    'Access-Control-Allow-Origin': '*',
    'Accept-Ranges': 'bytes'
  });
  fs.createReadStream(fp).pipe(res);
}
const NAME_RE = /^[一-龥A-Za-z0-9_]{2,16}$/;
const PHONE_RE = /^1[3-9]\d{9}$/;
function needAuth(res, me) { if (me) return false; json(res, 401, { err: '请先登录后再操作' }); return true; }
function cleanText(s) { return String(s == null ? '' : s).replace(/\s+/g, ' ').trim().slice(0, MAX_LEN); }
function newId() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 7); }

/* 昵称是当前系统的身份键：改名时把游戏成绩、灯谜、运签与举报记录一并过户，
   否则注销账号时旧昵称的数据会变成无主残留。 */
function migrateAuxUserData(oldName, name) {
  let gamesDirty = false;
  Object.keys(gameScores).forEach(function (key) {
    (gameScores[key] || []).forEach(function (r) {
      if (r && !r.gid && r.name === oldName) { r.name = name; gamesDirty = true; }
    });
  });
  if (gamesDirty) saveGames();

  let lanternDirty = false;
  Object.keys(lanternDays).forEach(function (day) {
    const box = lanternDays[day] || {};
    Object.keys(box.solves || {}).forEach(function (rid) {
      (box.solves[rid] || []).forEach(function (s) {
        if (s && s.name === oldName) { s.name = name; lanternDirty = true; }
      });
    });
    if (box.emoji && box.emoji[oldName]) {
      box.emoji[name] = box.emoji[oldName];
      delete box.emoji[oldName];
      lanternDirty = true;
    }
  });
  if (lanternDirty) saveLantern();

  let drawsDirty = false;
  const oldPrefix = 'u:' + oldName + '|';
  const newPrefix = 'u:' + name + '|';
  Object.keys(zodiacDraws).forEach(function (key) {
    if (key.indexOf(oldPrefix) === 0) {
      zodiacDraws[newPrefix + key.slice(oldPrefix.length)] = zodiacDraws[key];
      delete zodiacDraws[key];
      drawsDirty = true;
    }
  });
  if (drawsDirty) saveZodiacDraws();

  /* 玩法抽签：昵称是身份键，改名一并过户（记录 + 冷却） */
  let playDirty = false;
  playRecords.forEach(function (r) {
    if (r && r.key === 'u:' + oldName) {
      r.key = 'u:' + name;
      r.name = name;
      playDirty = true;
    }
  });
  if (playCooldowns['u:' + oldName] !== undefined) {
    playCooldowns['u:' + name] = playCooldowns['u:' + oldName];
    delete playCooldowns['u:' + oldName];
    playDirty = true;
  }
  if (playDirty) savePlay();

  let reportsDirty = false;
  reports.forEach(function (r) {
    if (r.reporter === oldName) { r.reporter = name; reportsDirty = true; }
    if (r.targetUid === oldName) {
      r.targetUid = name;
      if (r.targetNick === oldName) r.targetNick = name;
      reportsDirty = true;
    }
  });
  if (reportsDirty) saveReports();
}

/* ---------------- 星盘：调用本地 Python（Kerykeion）计算 ----------------
 * 说明：走子进程 + stdin/stdout 传 JSON，不占端口、不需要新增反代规则。
 *       星盘按用户生辰实时计算，无法像每日运势那样静态预生成。
 * 路径：astro.py 与 Python 解释器都按下面的候选表自动查找，通常不用配环境变量；
 *       若目录布局很特别，用 ASTRO_SCRIPT / ASTRO_PY 指定绝对路径即可。
 */
const ASTRO_TIMEOUT = Number(process.env.ASTRO_TIMEOUT || 30000);
/* interpret 模式要等 AI 生成（实测 ~13s，留足余量） */
const ASTRO_INTERPRET_TIMEOUT = Number(process.env.ASTRO_INTERPRET_TIMEOUT || 60000);

/* astro.py 候选位置：取第一个**存在**的 */
const ASTRO_SCRIPT_CANDIDATES = [
  process.env.ASTRO_SCRIPT,
  path.join(__dirname, '..', 'zodiac-ai', 'astro.py'),   // trash.js 在 /www/xxx/ 时
  '/www/zodiac-ai/astro.py',                             // 宝塔惯用位置
  path.join(__dirname, 'astro.py')                       // 与 trash.js 同目录
].filter(Boolean);

/* Python 解释器候选：取第一个**能 import kerykeion** 的 */
const ASTRO_PY_CANDIDATES = [
  process.env.ASTRO_PY,
  path.join(__dirname, 'venv', 'bin', 'python3'),
  path.join(__dirname, '..', 'zodiac-ai', 'venv', 'bin', 'python3'),
  path.join(__dirname, '..', 'zodiac-ai', '.venv', 'bin', 'python3'),
  '/www/zodiac-ai/venv/bin/python3',
  '/www/zodiac-ai/.venv/bin/python3',
  'python3',
  'python'
].filter(Boolean);

/* zodiac-ai.json 候选位置：环境变量 → 上级 → 同级 → 上级各子目录（取 mtime 最新）→ 服务器兜底 */
let zodiacAiPath = null;
function resolveZodiacAiPath() {
  if (zodiacAiPath) return zodiacAiPath;
  const candidates = [
    process.env.ZODIAC_AI_JSON,
    path.join(__dirname, '..', 'zodiac-ai.json'),
    path.join(__dirname, 'zodiac-ai.json'),
    '/www/wwwroot/chimu-claw.xyz/zodiac-ai.json'
  ].filter(Boolean);
  for (let i = 0; i < candidates.length; i++) {
    try { if (fs.existsSync(candidates[i])) { zodiacAiPath = candidates[i]; return zodiacAiPath; } } catch (e) {}
  }
  /* 上级目录各子目录扫描，取 mtime 最新的 zodiac-ai.json */
  try {
    const parent = path.join(__dirname, '..');
    let best = null, bestM = 0;
    for (const name of fs.readdirSync(parent)) {
      const fp = path.join(parent, name, 'zodiac-ai.json');
      try {
        if (fs.existsSync(fp)) {
          const m = fs.statSync(fp).mtimeMs;
          if (m > bestM) { best = fp; bestM = m; }
        }
      } catch (e) {}
    }
    if (best) { zodiacAiPath = best; return zodiacAiPath; }
  } catch (e) {}
  return null;
}

let astroPy = null;          // 已确定的 Python 解释器
let astroScript = null;      // 已确定的 astro.py 路径

function resolveAstroScript() {
  if (astroScript) return astroScript;
  for (let i = 0; i < ASTRO_SCRIPT_CANDIDATES.length; i++) {
    try {
      if (fs.existsSync(ASTRO_SCRIPT_CANDIDATES[i])) {
        astroScript = ASTRO_SCRIPT_CANDIDATES[i];
        return astroScript;
      }
    } catch (e) { /* 换下一个 */ }
  }
  return null;
}

function clampNum(v, min, max) {
  const n = Number(v);
  if (!isFinite(n)) return null;
  if (n < min || n > max) return null;
  return n;
}
function shortStr(v, max) { return String(v == null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, max); }

/* 出生数据：严格校验，避免脏数据进入星历计算 */
function sanitizeBirth(b) {
  if (!b || typeof b !== 'object') return null;
  const year = clampNum(b.year, 1800, 2200), month = clampNum(b.month, 1, 12),
    day = clampNum(b.day, 1, 31), hour = clampNum(b.hour, 0, 23),
    minute = clampNum(b.minute, 0, 59), lat = clampNum(b.lat, -89.9, 89.9),
    lng = clampNum(b.lng, -180, 180);
  if ([year, month, day, hour, minute, lat, lng].some(function (x) { return x === null; })) return null;
  const tz = shortStr(b.tz, 64) || 'Asia/Shanghai';
  if (!/^[A-Za-z][A-Za-z0-9_+/-]{1,63}$/.test(tz)) return null;
  return {
    name: shortStr(b.name, 24) || '本人',
    year: Math.round(year), month: Math.round(month), day: Math.round(day),
    hour: Math.round(hour), minute: Math.round(minute),
    lat: lat, lng: lng, tz: tz, city: shortStr(b.city, 32) || '未知'
  };
}

const TZ_RE = /^[A-Za-z][A-Za-z0-9_+/-]{1,63}$/;

/* 观测点：只需要经纬度，其他字段可选 */
function sanitizeObs(o, fallback) {
  if (!o || typeof o !== 'object') return fallback;
  const lat = clampNum(o.lat, -89.9, 89.9), lng = clampNum(o.lng, -180, 180);
  const tz = shortStr(o.tz, 64), city = shortStr(o.city, 32);
  return {
    lat: lat === null ? fallback.lat : lat,
    lng: lng === null ? fallback.lng : lng,
    tz: TZ_RE.test(tz) ? tz : fallback.tz,
    city: city || fallback.city
  };
}

function execAstro(py, script, mode, payload, timeoutMs) {
  return new Promise(function (resolve, reject) {
    let child;
    try {
      child = execFile(py, [script, mode], {
        timeout: timeoutMs || ASTRO_TIMEOUT, maxBuffer: 16 * 1024 * 1024, windowsHide: true
      }, function (err, stdout, stderr) {
        const text = String(stdout || '').trim();
        if (!text) {
          const e = new Error('星盘计算未返回结果：' +
            ((err && err.message) || '') + ' ' + String(stderr || '').slice(-300));
          e.noOutput = true;
          return reject(e);
        }
        let out;
        try { out = JSON.parse(text); }
        catch (e) {
          return reject(new Error('星盘输出无法解析：' + text.slice(0, 300)));
        }
        resolve(out);
      });
    } catch (e) { return reject(e); }
    child.on('error', function (e) { e.noOutput = true; reject(e); });
    child.stdin.on('error', function () { /* 子进程提前退出时忽略 EPIPE */ });
    child.stdin.end(JSON.stringify(payload || {}), 'utf8');
  });
}

/* 探测可用的 Python 解释器：取第一个能 import kerykeion 的 */
async function resolveAstroPy(script, force) {
  if (astroPy && !force) return astroPy;
  for (let i = 0; i < ASTRO_PY_CANDIDATES.length; i++) {
    try {
      const r = await execAstro(ASTRO_PY_CANDIDATES[i], script, 'version', {});
      if (r && r.ok === true && r.kerykeion) { astroPy = ASTRO_PY_CANDIDATES[i]; return astroPy; }
    } catch (e) { /* 换下一个 */ }
  }
  astroPy = null;
  return null;
}

async function runAstro(mode, payload) {
  const script = resolveAstroScript();
  if (!script) {
    const e = new Error('没找到 astro.py。已在这些位置查找：' + ASTRO_SCRIPT_CANDIDATES.join(' / '));
    e.astroEnv = true;
    e.tried = ASTRO_SCRIPT_CANDIDATES;
    throw e;
  }
  const py = await resolveAstroPy(script, false);
  if (!py) {
    const e = new Error('没有找到装了 kerykeion 的 Python。已尝试：' + ASTRO_PY_CANDIDATES.join(' / '));
    e.astroEnv = true;
    e.tried = ASTRO_PY_CANDIDATES;
    throw e;
  }
  try {
    const tmo = (mode === 'interpret' || mode === 'history') ? ASTRO_INTERPRET_TIMEOUT : ASTRO_TIMEOUT;
    return await execAstro(py, script, mode, payload, tmo);
  } catch (e) {
    /* 解释器若被替换/删除，重新探测一次再试 */
    if (e && e.noOutput) {
      const again = await resolveAstroPy(script, true);
      if (again && again !== py) {
        const tmo = (mode === 'interpret' || mode === 'history') ? ASTRO_INTERPRET_TIMEOUT : ASTRO_TIMEOUT;
        return await execAstro(again, script, mode, payload, tmo);
      }
    }
    throw e;
  }
}

/* ---------------- 路由 ---------------- */
const server = http.createServer(async function (req, res) {
  res._req = req;
  if (req.method === 'OPTIONS') { cors(res, 204, 'text/plain', ''); return; }
  const url = req.url.split('?')[0].replace(/^\/trashapi/, '');
  const ip = clientIp(req);
  const me = currentUser(req);
  const body = function () {
    return readBody(req).then(function (raw) {
      if (raw == null) return null;
      try { return JSON.parse(raw); } catch (e) { return {}; }
    });
  };

  /* ===== Web AI：GLM-5.3-Flash 轻度思考代理（密钥仅在服务端） ===== */
  if (req.method === 'POST' && url === '/api/ai') {
    if (!GLM_API_KEY) return json(res, 503, { err: 'AI 服务暂未配置' });
    if (limited(ip, 'ai', 30, 60000)) return json(res, 429, { err: 'AI 请求太频繁，请稍后再试' });
    const rawAi = await readBody(req, 256 * 1024);
    let b = null;
    try { b = rawAi ? JSON.parse(rawAi) : null; } catch (e) { return json(res, 400, { err: '请求格式错误' }); }
    const rawMessages = b && Array.isArray(b.messages) ? b.messages : [];
    const messages = [];
    let chars = 0;
    for (const item of rawMessages.slice(0, 30)) {
      if (!item || typeof item !== 'object') continue;
      const role = String(item.role || '');
      const content = String(item.content || '');
      if (!['system', 'user', 'assistant'].includes(role) || !content) continue;
      chars += content.length;
      if (chars > 32000) return json(res, 400, { err: '对话内容过长' });
      messages.push({ role: role, content: content });
    }
    if (!messages.length) return json(res, 400, { err: '缺少对话内容' });
    const maxTokens = Math.max(64, Math.min(2048, Number(b.max_tokens) || 1024));
    const temperature = Math.max(0, Math.min(1.5, Number(b.temperature) || 0.6));
    const wantsStream = b && b.stream === true;
    const payload = {
      model: GLM_MODEL,
      messages: messages,
      thinking: { type: 'enabled' },
      reasoning_effort: 'low',
      temperature: temperature,
      max_tokens: maxTokens,
      stream: wantsStream
    };
    if (wantsStream) {
      glmStream(payload, res);
      return;
    }
    try {
      const data = await glmCompletion(payload);
      return json(res, 200, data);
    } catch (e) {
      return json(res, 502, { err: e && e.message ? e.message : 'AI 服务暂不可用' });
    }
  }

  /* ===== 账号：当前会话 ===== */
  if (req.method === 'GET' && url === '/api/auth/me') {
    const bu = me ? findUser(me.name) : null;
    return json(res, 200, {
      token: me ? me.token : null,   /* 回吐 token 供前端重建 localStorage 兜底 */
      user: me ? {
        name: me.name,
        av: avatarOf(me.name),
        bday: bdayOf(bu),
        profileDone: bu ? bu.profileDone !== false : true,
        checkin: checkinStatus(bu)
      } : null,
      count: posts.length
    });
  }

  /* ===== 账号：注册（手机号 + 昵称 + 密码 + 邀请码） ===== */
  if (req.method === 'POST' && url === '/api/auth/register') {
    if (limited(ip, 'auth', 8, 60000)) return json(res, 429, { err: '尝试太频繁，稍后再试' });
    const b = await body();
    const pw = String(b && b.password || '');
    const phone = String(b && b.phone || '').replace(/\D/g, '');
    const name = String(b && b.name || '').trim();
    if (!PHONE_RE.test(phone)) return json(res, 400, { err: '请填写正确的 11 位手机号' });
    if (!NAME_RE.test(name)) return json(res, 400, { err: '昵称需 2-16 位，中英文/数字/下划线' });
    if (name.startsWith('游客')) return json(res, 400, { err: '该昵称不可用，换一个吧' });
    if (pw.length < 6 || pw.length > 32) return json(res, 400, { err: '密码需 6-32 位' });
    if (INVITE_CODE && String(b && b.invite || '').trim() !== INVITE_CODE) return json(res, 403, { err: '邀请码不正确，找站长大人要一个吧' });
    if (findUserByPhone(phone)) return json(res, 409, { err: '这个手机号已经注册过啦，直接登录吧' });
    if (findUser(name)) return json(res, 409, { err: '这个昵称已经被人占啦' });
    const salt = makeSalt();
    /* profileDone=false：新注册用户还没在「更改信息」弹窗里点过保存，
       前端据此强制弹一次资料确认弹窗（老用户没有该字段，一律视为已完成）。 */
    users.push({ name: name, phone: phone, salt: salt, hash: hashPw(pw, salt), createdAt: Date.now(), profileDone: false });
    saveUsers();
    const token = makeToken();
    sessions[token] = { name: name, exp: Date.now() + SESSION_DAYS * 86400000 };
    saveSessions(); setCookie(res, req, token);
    return json(res, 200, { token: token, user: { name: name, av: null, bday: null, profileDone: false } });
  }

  /* ===== 账号：登录（手机号 + 密码） ===== */
  if (req.method === 'POST' && url === '/api/auth/login') {
    if (limited(ip, 'auth', 8, 60000)) return json(res, 429, { err: '尝试太频繁，稍后再试' });
    const b = await body();
    const phone = String(b && b.phone || '').replace(/\D/g, '');
    const pw = String(b && b.password || '');
    if (!PHONE_RE.test(phone)) return json(res, 400, { err: '请填写正确的 11 位手机号' });
    const u = findUserByPhone(phone);
    let ok = false;
    if (u) { try { ok = crypto.timingSafeEqual(Buffer.from(hashPw(pw, u.salt), 'hex'), Buffer.from(u.hash, 'hex')); } catch (e) {} }
    if (!ok) return json(res, 401, { err: '手机号或密码不对' });
    const token = makeToken();
    sessions[token] = { name: u.name, exp: Date.now() + SESSION_DAYS * 86400000 };
    saveSessions(); setCookie(res, req, token);
    return json(res, 200, { token: token, user: { name: u.name, av: avatarOf(u.name), bday: bdayOf(u), profileDone: u.profileDone !== false } });
  }

  /* ===== 账号：改昵称（同步会话/帖子/评论/笔记/运势） ===== */
  if (req.method === 'POST' && url === '/api/auth/name') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'auth', 8, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
    const b = await body();
    const name = String(b && b.name || '').trim();
    if (!NAME_RE.test(name)) return json(res, 400, { err: '昵称需 2-16 位，中英文/数字/下划线' });
    if (name.startsWith('游客')) return json(res, 400, { err: '该昵称不可用，换一个吧' });
    if (name === me.name) {
      /* 昵称没改也算「已保存过一次」：新用户的一次性资料确认就此完成 */
      const same = findUser(me.name);
      if (same && same.profileDone === false) { same.profileDone = true; saveUsers(); }
      return json(res, 200, { user: { name: me.name, av: avatarOf(me.name), bday: bdayOf(same), profileDone: true } });
    }
    if (findUser(name)) return json(res, 409, { err: '这个昵称已经被人占啦' });
    const oldName = me.name;
    const u = findUser(oldName);
    if (!u) return json(res, 401, { err: '请先登录' });
    u.name = name;
    u.profileDone = true;   /* 已确认过资料，后续登录不再强制弹窗 */
    saveUsers();
    Object.keys(sessions).forEach(function (tok) {
      if (sessions[tok] && sessions[tok].name === oldName) sessions[tok].name = name;
    });
    saveSessions();
    notes.forEach(function (n) { if (n.uid === oldName) n.uid = name; });
    saveNotes();
    cookMigrateUser(oldName, name);
    migrateAuxUserData(oldName, name);
    posts.forEach(function (p) {
      if (p.uid === oldName) p.uid = name;
      (p.comments || []).forEach(function (c) { if (c.uid === oldName) c.uid = name; });
    });
    savePosts();
    const oldSign = zodiacSigns['u:' + oldName];
    if (oldSign !== undefined) {
      zodiacSigns['u:' + name] = oldSign;
      delete zodiacSigns['u:' + oldName];
      saveZodiacSigns();
    }
    if (notifRead[oldName]) {
      notifRead[name] = notifRead[oldName];
      delete notifRead[oldName];
      saveNotifRead();
    }
    return json(res, 200, { user: { name: name, av: avatarOf(name), bday: bdayOf(u), profileDone: true } });
  }

  /* ===== 账号：更改信息（昵称 + 生日；头像走 /api/auth/avatar） ===== */
  if (req.method === 'POST' && url === '/api/auth/profile') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'auth', 12, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
    const b = await body();
    const u = findUser(me.name);
    if (!u) return json(res, 401, { err: '请先登录' });
    let newName = u.name;
    if (b && typeof b.name === 'string' && b.name.trim()) {
      const name = String(b.name).trim();
      if (!NAME_RE.test(name)) return json(res, 400, { err: '昵称需 2-16 位，中英文/数字/下划线' });
      if (name.startsWith('游客')) return json(res, 400, { err: '该昵称不可用，换一个吧' });
      if (name !== u.name) {
        if (findUser(name)) return json(res, 409, { err: '这个昵称已经被人占啦' });
        const oldName = u.name;
        u.name = name;
        newName = name;
        saveUsers();
        Object.keys(sessions).forEach(function (tok) {
          if (sessions[tok] && sessions[tok].name === oldName) sessions[tok].name = name;
        });
        saveSessions();
        notes.forEach(function (n) { if (n.uid === oldName) n.uid = name; });
        saveNotes();
        cookMigrateUser(oldName, name);
    migrateAuxUserData(oldName, name);
        posts.forEach(function (p) {
          if (p.uid === oldName) p.uid = name;
          (p.comments || []).forEach(function (c) { if (c.uid === oldName) c.uid = name; });
        });
        savePosts();
        const oldSign = zodiacSigns['u:' + oldName];
        if (oldSign !== undefined) {
          zodiacSigns['u:' + name] = oldSign;
          delete zodiacSigns['u:' + oldName];
          saveZodiacSigns();
        }
        if (notifRead[oldName]) {
          notifRead[name] = notifRead[oldName];
          delete notifRead[oldName];
          saveNotifRead();
        }
      }
    }
    if (b && b.bday === null) {
      delete u.bday;
      saveUsers();
    } else if (b && b.bday) {
      const bm = parseInt(b.bday.month, 10);
      const bd = parseInt(b.bday.day, 10);
      if (!(bm >= 1 && bm <= 12 && bd >= 1 && bd <= 31)) return json(res, 400, { err: '生日日期不正确' });
      const dim = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][bm - 1];
      if (bd > dim) return json(res, 400, { err: '这个月没有 ' + bd + ' 号' });
      u.bday = { month: bm, day: bd };
      saveUsers();
    }
    /* 只要保存过一次资料，就视为完成新用户的一次性确认 */
    if (u.profileDone !== true) { u.profileDone = true; saveUsers(); }
    return json(res, 200, { user: { name: newName, av: avatarOf(newName), bday: bdayOf(u), profileDone: true } });
  }

  /* ===== 账号：登出 ===== */
  if (req.method === 'POST' && url === '/api/auth/logout') {
    if (me) { delete sessions[me.token]; saveSessions(); }
    clearCookie(res, req);
    return json(res, 200, { ok: true });
  }

  /* ===== 账号：注销（密码确认，永久删除账号与个人数据） ===== */
  if (req.method === 'POST' && url === '/api/auth/delete') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'account-delete', 3, 3600000)) return json(res, 429, { err: '操作太频繁，请稍后再试' });
    const b = await body();
    const password = String(b && b.password || '');
    const u = findUser(me.name);
    if (!u) return json(res, 401, { err: '请先登录' });
    let ok = false;
    try {
      ok = crypto.timingSafeEqual(Buffer.from(hashPw(password, u.salt), 'hex'), Buffer.from(u.hash, 'hex'));
    } catch (e) {}
    if (!ok) return json(res, 403, { err: '密码不正确' });

    const name = u.name;
    const deleted = { posts: 0, comments: 0, notes: 0, recipes: 0, scores: 0 };

    /* 头像 */
    if (u.av) { try { fs.unlinkSync(path.join(AV_DIR, u.av)); } catch (e) {} }

    /* 社区：本人帖子整帖删除；本人在他人帖下的评论、点赞、抱一抱逐条清理 */
    const keptPosts = [];
    posts.forEach(function (p) {
      if (p.uid === name) {
        (p.imgs || []).forEach(removePostImage);
        if (p.voice) removePostVoice(p.voice);
        (p.comments || []).forEach(function (c) {
          (c.imgs || []).forEach(removePostImage);
          if (c.voice) removePostVoice(c.voice);
        });
        deleted.posts++;
        return;
      }
      const keptComments = [];
      (p.comments || []).forEach(function (c) {
        if (c.uid === name) {
          (c.imgs || []).forEach(removePostImage);
          if (c.voice) removePostVoice(c.voice);
          deleted.comments++;
        } else {
          if (c.reply && c.reply.nick === name) c.reply.nick = '已注销用户';
          keptComments.push(c);
        }
      });
      p.comments = keptComments;
      p.likers = (p.likers || []).filter(function (x) { return x !== name; });
      p.huggers = (p.huggers || []).filter(function (x) { return x !== name; });
      p.likes = p.likers.length;
      p.hugs = p.huggers.length;
      if (p.likeTs) delete p.likeTs[name];
      keptPosts.push(p);
    });
    posts = keptPosts;
    savePosts();

    /* 笔记 */
    const notesBefore = notes.length;
    notes = notes.filter(function (n) { return n.uid !== name; });
    deleted.notes = notesBefore - notes.length;
    saveNotes();

    /* 食谱 / 冰箱 / 购物清单 */
    const keptRecipes = [];
    cookRecipes.forEach(function (r) {
      if (r.uid !== name) { keptRecipes.push(r); return; }
      if (r.cover) removeCookImage(r.cover);
      (r.steps || []).forEach(function (s) { if (s && s.img) removeCookImage(s.img); });
      deleted.recipes++;
    });
    cookRecipes = keptRecipes;
    /* 注销后清掉别人副本上的旧署名，避免继续展示已注销昵称 */
    cookRecipes.forEach(function (r) { if (r.fromOwner === name) r.fromOwner = ''; });
    delete cookShopping[name];
    delete cookFridge[name];
    saveCook();

    /* 游戏成绩（登录用户记录不带 gid；不要误删同名的游客记录） */
    Object.keys(gameScores).forEach(function (key) {
      const arr = Array.isArray(gameScores[key]) ? gameScores[key] : [];
      const before = arr.length;
      const kept = arr.filter(function (r) { return !(r && r.name === name && !r.gid); });
      if (kept.length !== before) {
        gameScores[key] = kept;
        deleted.scores += before - kept.length;
      }
    });
    saveGames();

    /* 通知已读 / 星座 / 星盘缓存 */
    if (notifRead[name]) { delete notifRead[name]; saveNotifRead(); }
    if (zodiacSigns['u:' + name] !== undefined) {
      delete zodiacSigns['u:' + name];
      saveZodiacSigns();
    }
    const drawPrefix = 'u:' + name + '|';
    let drawDirty = false;
    Object.keys(zodiacDraws).forEach(function (key) {
      if (key.indexOf(drawPrefix) === 0) { delete zodiacDraws[key]; drawDirty = true; }
    });
    if (drawDirty) saveZodiacDraws();

    /* 玩法抽签：清掉本人记录与冷却 */
    const playBefore = playRecords.length;
    const hadPlayCd = playCooldowns['u:' + name] !== undefined;
    playRecords = playRecords.filter(function (r) { return !(r && r.key === 'u:' + name); });
    delete playCooldowns['u:' + name];
    if (playRecords.length !== playBefore || hadPlayCd) savePlay();
    if (u.birth) {
      ['natal', 'transit'].forEach(function (scope) {
        try {
          const key = astroInterpretKey(u.birth, scope);
          if (astroInterprets[key]) { delete astroInterprets[key]; saveAstroInterprets(); }
        } catch (e) {}
      });
    }

    /* 灯谜成绩 */
    let lanternDirty = false;
    Object.keys(lanternDays).forEach(function (day) {
      const box = lanternDays[day] || {};
      Object.keys(box.solves || {}).forEach(function (rid) {
        const arr = box.solves[rid] || [];
        const kept = arr.filter(function (s) { return !(s && s.name === name); });
        if (kept.length !== arr.length) { box.solves[rid] = kept; lanternDirty = true; }
      });
      if (box.emoji && box.emoji[name]) { delete box.emoji[name]; lanternDirty = true; }
    });
    if (lanternDirty) saveLantern();

    /* 在线状态 */
    liveUsers.forEach(function (m, game) {
      m.delete('u:' + name);
      m.forEach(function (r, key) { if (r && r.name === name) m.delete(key); });
      if (!m.size) liveUsers.delete(game);
    });

    /* 举报：删除本人提交的；针对本人内容的保留但匿名化，仅用于安全审核 */
    let reportsDirty = false;
    const keptReports = [];
    reports.forEach(function (r) {
      if (r.reporter === name) { reportsDirty = true; return; }
      if (r.targetUid === name) {
        r.targetUid = null;
        r.targetNick = '已注销用户';
        r.targetText = '';
        reportsDirty = true;
      }
      keptReports.push(r);
    });
    if (reportsDirty) { reports = keptReports; saveReports(); }

    /* 账号与会话 */
    users = users.filter(function (x) { return x.name !== name; });
    saveUsers();
    Object.keys(sessions).forEach(function (tok) {
      if (sessions[tok] && sessions[tok].name === name) delete sessions[tok];
    });
    saveSessions();
    clearCookie(res, req);
    return json(res, 200, { ok: true, deleted: deleted });
  }

  /* ===== 账号：上传头像（前端压缩后 base64） ===== */
  if (req.method === 'POST' && url === '/api/auth/avatar') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'avatar', 12, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
    const raw = await readBody(req, 8 * 1024 * 1024);
    if (raw == null) return json(res, 413, { err: '图片太大了' });
    let b; try { b = JSON.parse(raw); } catch (e) { return json(res, 400, { err: '参数错误' }); }
    const buf = parseDataUrl(b && b.img);
    if (!buf) return json(res, 400, { err: '图片格式不正确' });
    if (buf.length > 2 * 1024 * 1024) return json(res, 400, { err: '头像图片过大' });
    const u = findUser(me.name);
    if (!u) return json(res, 401, { err: '请先登录' });
    const fname = imgName();
    try { fs.writeFileSync(path.join(AV_DIR, fname), buf); } catch (e) { return json(res, 500, { err: '保存失败，请重试' }); }
    if (u.av) { try { fs.unlinkSync(path.join(AV_DIR, u.av)); } catch (e) {} }
    u.av = fname; saveUsers();
    return json(res, 200, { user: { name: u.name, av: '/api/img/avatars/' + fname, bday: bdayOf(u), profileDone: u.profileDone !== false } });
  }

  /* ===== 图片读取（头像 / 帖子配图 / 食谱图） ===== */
  const imgGet = url.match(/^\/api\/img\/(avatars|posts|cook)\/([^/]+)$/);
  if ((req.method === 'GET' || req.method === 'HEAD') && imgGet) {
    const imgDir = imgGet[1] === 'avatars' ? AV_DIR : (imgGet[1] === 'cook' ? COOK_DIR : IMG_DIR);
    return serveImg(req, res, imgDir, imgGet[2]);
  }

  /* ===== 语音读取（帖子配语音，支持拖动进度） ===== */
  const voiceGet = url.match(/^\/api\/voice\/([A-Za-z0-9_-]+\.(?:webm|mp4|m4a|ogg|oga|mp3|wav))$/);
  if (req.method === 'GET' && voiceGet) {
    return serveVoice(req, res, voiceGet[1]);
  }

  /* ===== 帖子：列表 ===== */
  if (req.method === 'GET' && url === '/api/posts') {
    const list = posts
      .slice()
      .sort(function (a, b) { return b.ts - a.ts; })
      .slice(0, FEED_MAX)
      .map(function (p) { return pub(p, me); });
    return json(res, 200, {
      date: dayStr(),
      me: me ? me.name : null,
      count: posts.length,
      posts: list
    });
  }

  /* ===== 帖子：发表（可带最多 3 张配图，前端压缩后 base64） ===== */
  if (req.method === 'POST' && url === '/api/posts') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'post', 5, 60000)) return json(res, 429, { err: '发得太快啦，歇口气' });
    const raw = await readBody(req, 20 * 1024 * 1024);
    if (raw == null) return json(res, 413, { err: '内容太大了' });
    let b; try { b = JSON.parse(raw); } catch (e) { return json(res, 400, { err: '参数错误' }); }
    const text = cleanText(b && b.text);
    const hasVoice = !!(b && b.voice);
    /* 先做空校验再落盘，避免产生孤儿文件 */
    if (!text && !(Array.isArray(b && b.imgs) && b.imgs.length) && !hasVoice) {
      return json(res, 400, { err: '内容不能为空' });
    }
    /* 保存配图 */
    let imgs = [];
    if (Array.isArray(b && b.imgs) && b.imgs.length) {
      if (b.imgs.length > MAX_IMGS) return json(res, 400, { err: '最多上传 ' + MAX_IMGS + ' 张图片' });
      for (let i = 0; i < b.imgs.length; i++) {
        const buf = parseDataUrl(b.imgs[i]);
        if (!buf) return json(res, 400, { err: '第 ' + (i + 1) + ' 张图片格式不正确' });
        if (buf.length > 5 * 1024 * 1024) return json(res, 400, { err: '第 ' + (i + 1) + ' 张图片过大' });
        const fname = imgName();
        try { fs.writeFileSync(path.join(IMG_DIR, fname), buf); } catch (e) { return json(res, 500, { err: '图片保存失败，请重试' }); }
        imgs.push('/api/img/posts/' + fname);
      }
    }
    /* 保存语音（≤3MB / 1-60 秒，前端 MediaRecorder 录制后 base64） */
    let voice = null, voiceDur = 0;
    if (hasVoice) {
      const v = parseVoiceUrl(b.voice);
      if (!v) return json(res, 400, { err: '语音格式不正确' });
      if (v.buf.length > 3 * 1024 * 1024) return json(res, 400, { err: '语音太大（超过 3MB）' });
      voiceDur = Math.round(Number(b.voiceDur) || 0);
      if (!(voiceDur >= 1 && voiceDur <= 60)) return json(res, 400, { err: '语音时长需在 1-60 秒' });
      const vname = newId() + '.' + v.ext;
      try { fs.writeFileSync(path.join(VOICE_DIR, vname), v.buf); } catch (e) { return json(res, 500, { err: '语音保存失败，请重试' }); }
      voice = '/api/voice/' + vname;
    }
    const anon = !!(b && b.anon);
    const p = {
      id: newId(), uid: me.name, anon: anon,
      nick: anon ? FRUIT[Math.floor(Math.random() * FRUIT.length)] : me.name,
      text: text, imgs: imgs, voice: voice, voiceDur: voiceDur,
      likes: 0, hugs: 0, likers: [], huggers: [], comments: [], ts: Date.now()
    };
    posts.unshift(p);
    savePosts();
    return json(res, 200, { post: pub(p, me) });
  }

  /* ===== 帖子：互动（点赞/抱一抱/评论/删除） ===== */
  const act = url.match(/^\/api\/posts\/([A-Za-z0-9]+)\/(like|hug|comment)$/);
  if (req.method === 'POST' && act) {
    if (needAuth(res, me)) return;
    const p = posts.find(function (x) { return x.id === act[1]; });
    if (!p) return json(res, 404, { err: '这条吐槽已被清空' });
    if (act[2] === 'like') {
      if (limited(ip, 'react', 60, 60000)) return json(res, 429, { err: '操作太频繁' });
      const i = p.likers.indexOf(me.name);
      if (i === -1) { p.likers.push(me.name); p.likes++; p.likeTs = p.likeTs || {}; p.likeTs[me.name] = Date.now(); }
      else { p.likers.splice(i, 1); p.likes = Math.max(0, p.likes - 1); if (p.likeTs) delete p.likeTs[me.name]; }
      savePosts();
      return json(res, 200, { id: p.id, likes: p.likes, liked: i === -1 });
    }
    if (act[2] === 'hug') {
      if (limited(ip, 'react', 60, 60000)) return json(res, 429, { err: '操作太频繁' });
      const i = p.huggers.indexOf(me.name);
      if (i === -1) { p.huggers.push(me.name); p.hugs++; } else { p.huggers.splice(i, 1); p.hugs = Math.max(0, p.hugs - 1); }
      savePosts();
      return json(res, 200, { id: p.id, hugs: p.hugs, hugged: i === -1 });
    }
    if (act[2] === 'comment') {
      if (limited(ip, 'comment', 15, 60000)) return json(res, 429, { err: '评论太快啦' });
      if ((p.comments || []).length >= MAX_COMMENTS) return json(res, 400, { err: '这条评论太多啦' });
      /* ★评论可带图/带语音：与发帖同格式，body 上限同发帖 20MB（旧 body() 仅 16KB，带语音必超） */
      const raw = await readBody(req, 20 * 1024 * 1024);
      if (raw == null) return json(res, 413, { err: '内容太大了' });
      let b; try { b = JSON.parse(raw); } catch (e) { return json(res, 400, { err: '参数错误' }); }
      const text = cleanText(b && b.text);
      const hasVoice = !!(b && b.voice);
      /* 空校验：文字/图片/语音至少一项（先校验后落盘，避免孤儿文件） */
      if (!text && !(Array.isArray(b && b.imgs) && b.imgs.length) && !hasVoice) {
        return json(res, 400, { err: '评论不能为空' });
      }
      /* 保存评论配图（最多 2 张，与前端 CM_MAX_IMGS 一致） */
      let imgs = [];
      if (Array.isArray(b && b.imgs) && b.imgs.length) {
        if (b.imgs.length > 2) return json(res, 400, { err: '评论最多上传 2 张图片' });
        for (let i = 0; i < b.imgs.length; i++) {
          const buf = parseDataUrl(b.imgs[i]);
          if (!buf) return json(res, 400, { err: '第 ' + (i + 1) + ' 张图片格式不正确' });
          if (buf.length > 5 * 1024 * 1024) return json(res, 400, { err: '第 ' + (i + 1) + ' 张图片过大' });
          const fname = imgName();
          try { fs.writeFileSync(path.join(IMG_DIR, fname), buf); } catch (e) { return json(res, 500, { err: '图片保存失败，请重试' }); }
          imgs.push('/api/img/posts/' + fname);
        }
      }
      /* 保存评论语音（≤3MB / 1-60 秒） */
      let voice = null, voiceDur = 0;
      if (hasVoice) {
        const v = parseVoiceUrl(b.voice);
        if (!v) return json(res, 400, { err: '语音格式不正确' });
        if (v.buf.length > 3 * 1024 * 1024) return json(res, 400, { err: '语音太大（超过 3MB）' });
        voiceDur = Math.round(Number(b.voiceDur) || 0);
        if (!(voiceDur >= 1 && voiceDur <= 60)) return json(res, 400, { err: '语音时长需在 1-60 秒' });
        const vname = newId() + '.' + v.ext;
        try { fs.writeFileSync(path.join(VOICE_DIR, vname), v.buf); } catch (e) { return json(res, 500, { err: '语音保存失败，请重试' }); }
        voice = '/api/voice/' + vname;
      }
      const anon = !!(b && b.anon);
      /* ★回复：replyId 指向本帖内被回复的评论，保存昵称快照 */
      let reply = null;
      const rid = String(b && b.replyId || '');
      if (rid) {
        const target = (p.comments || []).find(function (c) { return c.id === rid; });
        if (target) reply = { id: target.id, nick: target.anon ? target.nick : target.uid };
      }
      const c = { id: newId(), uid: me.name, anon: anon,
        nick: anon ? FRUIT[Math.floor(Math.random() * FRUIT.length)] : me.name,
        reply: reply,
        text: text, imgs: imgs, voice: voice, voiceDur: voiceDur, ts: Date.now() };
      p.comments = p.comments || []; p.comments.push(c);
      savePosts();
      return json(res, 200, { id: p.id, nComments: p.comments.length, comment: pubComment(c, me) });
    }
  }

  /* 帖子：评论列表 */
  const cm = url.match(/^\/api\/posts\/([A-Za-z0-9]+)\/comments$/);
  if (req.method === 'GET' && cm) {
    const p = posts.find(function (x) { return x.id === cm[1]; });
    if (!p) return json(res, 404, { err: '这条吐槽已被清空' });
    return json(res, 200, { comments: (p.comments || []).map(function (c) { return pubComment(c, me); }) });
  }

  /* 评论：删除（仅评论作者） */
  const cd = url.match(/^\/api\/posts\/([A-Za-z0-9]+)\/comments\/([A-Za-z0-9]+)$/);
  if (req.method === 'DELETE' && cd) {
    if (needAuth(res, me)) return;
    const p = posts.find(function (x) { return x.id === cd[1]; });
    if (!p) return json(res, 404, { err: '这条吐槽已被清空' });
    const ci = (p.comments || []).findIndex(function (c) { return c.id === cd[2]; });
    if (ci === -1) return json(res, 404, { err: '评论不存在' });
    if (p.comments[ci].uid !== me.name) return json(res, 403, { err: '只能删除自己的评论' });
    /* ★清理评论自带的图片/语音文件，避免孤儿文件 */
    (p.comments[ci].imgs || []).forEach(function (u) {
      const m = /\/([A-Za-z0-9_-]+\.jpg)$/.exec(u);
      if (m) { try { fs.unlinkSync(path.join(IMG_DIR, m[1])); } catch (e) {} }
    });
    if (p.comments[ci].voice) {
      const vm = /\/([A-Za-z0-9_-]+\.(?:webm|mp4|m4a|ogg|oga|mp3|wav))$/.exec(p.comments[ci].voice);
      if (vm) { try { fs.unlinkSync(path.join(VOICE_DIR, vm[1])); } catch (e) {} }
    }
    p.comments.splice(ci, 1); savePosts();
    return json(res, 200, { ok: true, nComments: p.comments.length });
  }

  /* 帖子：删除（仅作者） */
  const dl = url.match(/^\/api\/posts\/([A-Za-z0-9]+)$/);
  if (req.method === 'DELETE' && dl) {
    if (needAuth(res, me)) return;
    const idx = posts.findIndex(function (x) { return x.id === dl[1]; });
    if (idx === -1) return json(res, 404, { err: '这条吐槽已被清空' });
    if (posts[idx].uid !== me.name) return json(res, 403, { err: '只能删除自己发布的吐槽' });
    (posts[idx].imgs || []).forEach(function (u) {
      const m = /\/([A-Za-z0-9_-]+\.jpg)$/.exec(u);
      if (m) { try { fs.unlinkSync(path.join(IMG_DIR, m[1])); } catch (e) {} }
    });
    if (posts[idx].voice) {
      const vm = /\/([A-Za-z0-9_-]+\.(?:webm|mp4|m4a|ogg|oga|mp3|wav))$/.exec(posts[idx].voice);
      if (vm) { try { fs.unlinkSync(path.join(VOICE_DIR, vm[1])); } catch (e) {} }
    }
    /* ★顺带清理帖子评论自带的图片/语音文件 */
    (posts[idx].comments || []).forEach(function (c) {
      (c.imgs || []).forEach(function (u) {
        const m = /\/([A-Za-z0-9_-]+\.jpg)$/.exec(u);
        if (m) { try { fs.unlinkSync(path.join(IMG_DIR, m[1])); } catch (e) {} }
      });
      if (c.voice) {
        const vm = /\/([A-Za-z0-9_-]+\.(?:webm|mp4|m4a|ogg|oga|mp3|wav))$/.exec(c.voice);
        if (vm) { try { fs.unlinkSync(path.join(VOICE_DIR, vm[1])); } catch (e) {} }
      }
    });
    posts.splice(idx, 1); savePosts();
    return json(res, 200, { ok: true });
  }

  /* ===== ★社区举报 ===== */
  if (req.method === 'POST' && url === '/api/report') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'report', 10, 60000)) return json(res, 429, { err: '举报太频繁，请稍后再试' });
    const b = await body();
    const type = String(b && b.type || '');
    const reason = String(b && b.reason || '').slice(0, 40);
    const detail = String(b && b.detail || '').replace(/\s+/g, ' ').trim().slice(0, 300);
    if (['post', 'comment', 'user'].indexOf(type) === -1) return json(res, 400, { err: '举报类型不正确' });
    if (REPORT_REASONS.indexOf(reason) === -1) return json(res, 400, { err: '请选择举报原因' });
    const postId = String(b && b.postId || '').trim();
    const commentId = String(b && b.commentId || '').trim();
    const suppliedNick = String(b && b.targetNick || '').trim().slice(0, 40);
    let targetUid = null, targetText = '', targetNick = suppliedNick, p = null, c = null;
    if (type === 'post' || type === 'comment') {
      p = posts.find(function (x) { return x.id === postId; });
      if (!p) return json(res, 404, { err: '内容不存在或已被删除' });
      if (type === 'post') {
        if (p.uid === me.name) return json(res, 400, { err: '不能举报自己的内容' });
        targetUid = p.anon ? null : p.uid;
        targetNick = p.anon ? p.nick : p.uid;
        targetText = String(p.text || '').slice(0, 200);
      } else {
        c = (p.comments || []).find(function (x) { return x.id === commentId; });
        if (!c) return json(res, 404, { err: '评论不存在或已被删除' });
        if (c.uid === me.name) return json(res, 400, { err: '不能举报自己的评论' });
        targetUid = c.anon ? null : c.uid;
        targetNick = c.anon ? c.nick : c.uid;
        targetText = String(c.text || '').slice(0, 200);
      }
    } else {
      if (!suppliedNick) return json(res, 400, { err: '缺少被举报用户' });
      if (suppliedNick === me.name) return json(res, 400, { err: '不能举报自己' });
      const tu = findUser(suppliedNick);
      targetUid = tu ? tu.name : null;
      targetNick = suppliedNick;
    }
    /* 同一用户 10 分钟内对同一目标重复提交只记一条 */
    const duplicate = reports.some(function (r) {
      return r.reporter === me.name && r.type === type && r.postId === (postId || null) &&
        r.commentId === (commentId || null) && r.targetNick === targetNick && Date.now() - r.ts < 10 * 60000;
    });
    if (duplicate) return json(res, 200, { ok: true, duplicate: true });
    reports.unshift({
      id: newId(), type: type, reason: reason, detail: detail,
      postId: postId || null, commentId: commentId || null,
      targetUid: targetUid, targetNick: targetNick, targetText: targetText,
      reporter: me.name, ts: Date.now(), status: 'open'
    });
    if (reports.length > REPORT_MAX) reports = reports.slice(0, REPORT_MAX);
    saveReports();
    return json(res, 200, { ok: true });
  }

  /* ===== 笔记：列表（仅当前用户） ===== */
  if (req.method === 'GET' && url === '/api/notes') {
    if (needAuth(res, me)) return;
    const list = notes
      .filter(function (n) { return n.uid === me.name; })
      .sort(function (a, b) { return b.updated - a.updated; })
      .map(function (n) { return pubNote(n, me); });
    return json(res, 200, { notes: list });
  }

  /* ===== 笔记：新建 ===== */
  if (req.method === 'POST' && url === '/api/notes') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'note', 10, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
    const raw = await readBody(req, 256 * 1024);
    if (raw == null) return json(res, 413, { err: '内容太大了' });
    let b; try { b = JSON.parse(raw); } catch (e) { return json(res, 400, { err: '参数错误' }); }
    const title = String(b && b.title || '').replace(/\s+/g, ' ').trim().slice(0, NOTE_TITLE_MAX);
    const content = String(b && b.content || '').slice(0, NOTE_CONTENT_MAX);
    if (!title && !content) return json(res, 400, { err: '笔记内容不能为空' });
    const mine = notes.filter(function (n) { return n.uid === me.name; });
    if (mine.length >= NOTE_MAX_PER_USER) return json(res, 400, { err: '笔记最多 ' + NOTE_MAX_PER_USER + ' 条，删掉一些再写吧' });
    const n = { id: newId(), uid: me.name, title: title, content: content, ts: Date.now(), updated: Date.now() };
    notes.push(n); saveNotes();
    return json(res, 200, { note: pubNote(n, me) });
  }

  /* ===== 笔记：更新 / 删除 ===== */
  const noteAct = url.match(/^\/api\/notes\/([A-Za-z0-9]+)$/);
  if (noteAct) {
    if (needAuth(res, me)) return;
    const n = notes.find(function (x) { return x.id === noteAct[1]; });
    if (!n) return json(res, 404, { err: '笔记不存在' });
    if (n.uid !== me.name) return json(res, 403, { err: '只能操作自己的笔记' });

    if (req.method === 'POST') {
      if (limited(ip, 'note', 10, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
      const raw = await readBody(req, 256 * 1024);
      if (raw == null) return json(res, 413, { err: '内容太大了' });
      let b; try { b = JSON.parse(raw); } catch (e) { return json(res, 400, { err: '参数错误' }); }
      const title = String(b && b.title || '').replace(/\s+/g, ' ').trim().slice(0, NOTE_TITLE_MAX);
      const content = String(b && b.content || '').slice(0, NOTE_CONTENT_MAX);
      if (!title && !content) return json(res, 400, { err: '笔记内容不能为空' });
      n.title = title; n.content = content; n.updated = Date.now();
      saveNotes();
      return json(res, 200, { note: pubNote(n, me) });
    }

    if (req.method === 'DELETE') {
      const idx = notes.indexOf(n);
      notes.splice(idx, 1); saveNotes();
      return json(res, 200, { ok: true });
    }
  }

  /* ===== ★消息通知：列表（派生自帖子数据，无需额外写入） ===== */
  if (req.method === 'GET' && url === '/api/notifications') {
    if (needAuth(res, me)) return;
    const lastRead = notifRead[me.name] || 0;
    const list = [];
    posts.forEach(function (p) {
      /* 我在本帖发过的评论 id 集合（用于识别"回复了我的评论"） */
      const myCids = {};
      (p.comments || []).forEach(function (c) { if (c.uid === me.name) myCids[c.id] = true; });
      (p.comments || []).forEach(function (c) {
        if (c.uid === me.name) return;
        let type = null;
        if (c.reply && myCids[c.reply.id]) type = 'reply';       // 回复了我的评论（优先）
        else if (p.uid === me.name) type = 'comment';            // 评论了我的动态
        if (!type) return;
        list.push({
          id: p.id + '-' + c.id, postId: p.id, type: type,
          nick: c.anon ? c.nick : c.uid, anon: !!c.anon,
          text: c.text, postText: (p.text || '').slice(0, 40),
          ts: c.ts, unread: c.ts > lastRead
        });
      });
      /* ★点赞通知：仅对有 likeTs 记录的点赞生成（避免历史点赞一次性涌入） */
      if (p.uid === me.name && p.likeTs) {
        p.likers.forEach(function (liker) {
          if (liker === me.name) return;
          const ts = p.likeTs[liker];
          if (!ts) return;
          list.push({
            id: p.id + '-like-' + liker, postId: p.id, type: 'like',
            nick: liker, anon: false, text: '', postText: (p.text || '').slice(0, 40),
            ts: ts, unread: ts > lastRead
          });
        });
      }
    });
    list.sort(function (a, b) { return b.ts - a.ts; });
    const unread = list.filter(function (n) { return n.unread; }).length;
    return json(res, 200, { notifications: list.slice(0, 30), unread: unread, total: list.length });
  }

  /* ===== ★消息通知：全部已读 ===== */
  if (req.method === 'POST' && url === '/api/notifications/read') {
    if (needAuth(res, me)) return;
    notifRead[me.name] = Date.now();
    saveNotifRead();
    return json(res, 200, { ok: true });
  }

  /* ===== ★中秋猜灯谜：状态（不含谜底） ===== */
  if (req.method === 'GET' && url === '/api/lantern') {
    if (limited(ip, 'lantern', 60, 60000)) return json(res, 429, { err: '查询太频繁' });
    const st = lanternOpenState();
    if (!st.isMidAutumn) return json(res, 200, { date: st.date, open: false, midAutumn: false, riddles: [], board: [] });
    const box = lanternDayBox(st.date);
    const riddles = LANTERN_RIDDLES.map(function (r) {
      const solvers = (box.solves[String(r.id)] || []).map(function (s) {
        return { name: s.name, ts: s.ts };
      });
      return { id: r.id, q: r.q, solvers: solvers };
    });
    /* 排行：灯谜 1 分/题 + 附加题 0.5 分/题；同分比最早解出时间 */
    const scoreMap = {};
    Object.keys(box.solves).forEach(function (rid) {
      (box.solves[rid] || []).forEach(function (s) {
        if (!scoreMap[s.name]) scoreMap[s.name] = { name: s.name, score: 0, firstTs: s.ts, solvedCount: 0, bonus: 0 };
        scoreMap[s.name].score += 1;
        scoreMap[s.name].solvedCount += 1;
        if (s.ts < scoreMap[s.name].firstTs) scoreMap[s.name].firstTs = s.ts;
      });
    });
    Object.keys(box.emoji || {}).forEach(function (name) {
      const u = box.emoji[name] || {};
      const n = (u.solved || []).length;
      if (!n) return;
      if (!scoreMap[name]) scoreMap[name] = { name: name, score: 0, firstTs: Date.now(), solvedCount: 0, bonus: 0 };
      scoreMap[name].bonus = n;
      scoreMap[name].score = Math.round((scoreMap[name].score + n * 0.5) * 10) / 10;
    });
    const board = Object.keys(scoreMap).map(function (k) { return scoreMap[k]; })
      .sort(function (a, b) { return (b.score - a.score) || (a.firstTs - b.firstTs); });
    const meSolved = [];
    if (me) {
      Object.keys(box.solves).forEach(function (rid) {
        if ((box.solves[rid] || []).some(function (s) { return s.name === me.name; })) meSolved.push(parseInt(rid, 10));
      });
    }
    let emojiState = null;
    if (me) {
      const eu = (box.emoji && box.emoji[me.name]) || { current: null, solved: [] };
      let cur = null;
      if (eu.current != null) {
        const er = LANTERN_EMOJI.find(function (x) { return x.id === eu.current; });
        if (er) cur = { id: er.id, emoji: er.emoji };
      }
      emojiState = {
        current: cur,
        solved: (eu.solved || []).slice(),
        score: Math.round((eu.solved || []).length * 0.5 * 10) / 10,
        total: LANTERN_EMOJI.length
      };
    }
    return json(res, 200, {
      date: st.date, open: st.open, closedAfter: st.closedAfter, midAutumn: true,
      riddles: riddles,
      emoji: emojiState,
      me: me ? {
        name: me.name, solved: meSolved,
        score: Math.round((meSolved.length + (emojiState ? emojiState.solved.length : 0) * 0.5) * 10) / 10
      } : null,
      board: board
    });
  }

  /* ===== ★中秋猜灯谜：作答（登录；对全员记 solvers；不回谜底） ===== */
  if (req.method === 'POST' && url === '/api/lantern/answer') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'lantern-ans', 30, 60000)) return json(res, 429, { err: '手速太快，歇一下' });
    const st = lanternOpenState();
    if (!st.isMidAutumn) return json(res, 403, { err: '灯谜活动尚未开始或已结束', closed: true });
    if (!st.open) return json(res, 403, { err: '灯谜已收卷（截止 ' + st.closedAfter + '）', closed: true });
    const b = await body();
    const id = b && parseInt(b.id, 10);
    const answer = b && b.answer;
    const riddle = LANTERN_RIDDLES.find(function (r) { return r.id === id; });
    if (!riddle) return json(res, 400, { err: '没有这道灯谜' });
    if (!answer || !String(answer).trim()) return json(res, 400, { err: '写个答案再交' });
    const box = lanternDayBox(st.date);
    const key = String(riddle.id);
    if (!box.solves[key]) box.solves[key] = [];
    const already = box.solves[key].some(function (s) { return s.name === me.name; });
    if (already) return json(res, 409, { err: '这题你已经猜中过啦' });
    const ok = lanternAnswerOk(riddle, answer);
    if (!ok) return json(res, 200, { ok: false });
    box.solves[key].push({ name: me.name, ts: Date.now() });
    saveLantern();
    return json(res, 200, {
      ok: true,
      solvers: box.solves[key].map(function (s) { return { name: s.name, ts: s.ts }; })
    });
  }

  /* ===== ★附加题：emoji 猜成语 · 抽题（未解出当前题不能抽下一题） ===== */
  if (req.method === 'POST' && url === '/api/lantern/emoji/draw') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'lantern-emoji', 20, 60000)) return json(res, 429, { err: '抽太频繁了' });
    const st = lanternOpenState();
    if (!st.isMidAutumn) return json(res, 403, { err: '活动尚未开始或已结束', closed: true });
    if (!st.open) return json(res, 403, { err: '已收卷（截止 ' + st.closedAfter + '）', closed: true });
    const box = lanternDayBox(st.date);
    const eu = lanternEmojiUser(box, me.name);
    if (eu.current != null) return json(res, 409, { err: '先答对当前这题' });
    const left = LANTERN_EMOJI.filter(function (r) { return eu.solved.indexOf(r.id) === -1; });
    if (!left.length) return json(res, 200, { ok: true, done: true, current: null });
    const pick = left[Math.floor(Math.random() * left.length)];
    eu.current = pick.id;
    saveLantern();
    return json(res, 200, { ok: true, current: { id: pick.id, emoji: pick.emoji } });
  }

  /* ===== ★附加题：emoji 猜成语 · 作答（答对 +0.5 并可抽下一题） ===== */
  if (req.method === 'POST' && url === '/api/lantern/emoji/answer') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'lantern-emoji', 30, 60000)) return json(res, 429, { err: '手速太快' });
    const st = lanternOpenState();
    if (!st.isMidAutumn) return json(res, 403, { err: '活动尚未开始或已结束', closed: true });
    if (!st.open) return json(res, 403, { err: '已收卷（截止 ' + st.closedAfter + '）', closed: true });
    const b = await body();
    const box = lanternDayBox(st.date);
    const eu = lanternEmojiUser(box, me.name);
    if (eu.current == null) return json(res, 400, { err: '先抽一题' });
    const riddle = LANTERN_EMOJI.find(function (x) { return x.id === eu.current; });
    if (!riddle) { eu.current = null; saveLantern(); return json(res, 400, { err: '题目丢失，重新抽一题' }); }
    const answer = b && b.answer;
    if (!answer || !String(answer).trim()) return json(res, 400, { err: '写个答案呀' });
    const ok = lanternAnswerOk(riddle, answer);
    if (!ok) return json(res, 200, { ok: false });
    if (eu.solved.indexOf(riddle.id) === -1) eu.solved.push(riddle.id);
    eu.current = null;
    saveLantern();
    return json(res, 200, {
      ok: true,
      solved: eu.solved.slice(),
      score: Math.round(eu.solved.length * 0.5 * 10) / 10
    });
  }

  /* ===== ★星座运势：读取当前身份已锁定的星座 ===== */
  if (req.method === 'GET' && url === '/api/zodiac') {
    const qs = new URL(req.url, 'http://x').searchParams;
    const zkey = zodiacKeyOf(me, qs.get('deviceId'));
    if (!zkey) return json(res, 400, { sign: null });
    return json(res, 200, { sign: zodiacSigns[zkey] || null, keyType: me ? 'account' : 'device' });
  }

  /* ===== ★星座运势：锁定星座（一旦锁定不可改） ===== */
  if (req.method === 'POST' && url === '/api/zodiac') {
    if (limited(ip, 'zodiac-lock', 10, 60000)) return json(res, 429, { err: '操作太频繁' });
    const b = await body();
    const sign = String(b && b.sign || '').trim().toLowerCase();
    if (!validZodiac(sign)) return json(res, 400, { err: '星座参数不正确' });
    const deviceId = b && b.deviceId;
    const zkey = zodiacKeyOf(me, deviceId);
    if (!zkey) return json(res, 400, { err: '缺少身份标识' });
    /* 已锁定则拒绝更改 */
    if (zodiacSigns[zkey] && zodiacSigns[zkey] !== sign) {
      return json(res, 403, { err: '星座已锁定，不可更改', sign: zodiacSigns[zkey] });
    }
    zodiacSigns[zkey] = sign;
    /* 登录用户同时写一份到设备键，清登录后本机仍可读 */
    if (me && deviceId) {
      const dk = 'd:' + String(deviceId).slice(0, 64);
      if (!zodiacSigns[dk] || zodiacSigns[dk] === sign) zodiacSigns[dk] = sign;
    }
    saveZodiacSigns();
    return json(res, 200, { ok: true, sign: sign });
  }

  /* ===== ★AI 星象运势数据（zodiac-ai.json 由 generate.js 每日生成；带 CORS 供离线壳跨域拉取） ===== */
  if (req.method === 'GET' && url === '/api/zodiac/ai') {
    if (limited(ip, 'zodiac-ai', 30, 60000)) return json(res, 429, { err: '查询太频繁' });
    const fp = resolveZodiacAiPath();
    if (!fp) return json(res, 503, { err: 'AI 运势数据暂不可用' });
    try {
      const raw = fs.readFileSync(fp, 'utf8');
      const d = JSON.parse(raw);
      return json(res, 200, d);
    } catch (e) {
      console.error('[zodiac] ai read fail', e && e.message);
      return json(res, 503, { err: 'AI 运势数据暂不可用' });
    }
  }

  /* ===== ★星座运势：取今日运势（全站按 日+星座 缓存，最多 12 次/天上游调用） ===== */
  if (req.method === 'GET' && url === '/api/zodiac/fortune') {
    if (limited(ip, 'zodiac-fort', 30, 60000)) return json(res, 429, { err: '查询太频繁' });
    const qs = new URL(req.url, 'http://x').searchParams;
    const sign = String(qs.get('sign') || '').trim().toLowerCase();
    if (!validZodiac(sign)) return json(res, 400, { err: '星座参数不正确' });
    const r = await getZodiacFortune(sign);
    if (!r.ok) return json(res, 502, { err: r.err });
    return json(res, 200, { fortune: r.data, cached: !!r.cached, date: dayStr() });
  }

  /* ===== ★玩法抽签：全站最近记录 + 抽签（登录/游客都可用） ===== */
  if (req.method === 'GET' && url === '/api/play') {
    if (limited(ip, 'play', 60, 60000)) return json(res, 429, { err: '查询太频繁' });
    const qs = new URL(req.url, 'http://x').searchParams;
    return json(res, 200, playList(playKeyOf(me, qs.get('deviceId'))));
  }
  if (req.method === 'POST' && url === '/api/play') {
    if (limited(ip, 'playdraw', 20, 60000)) return json(res, 429, { err: '操作太频繁' });
    const b = await body();
    const key = playKeyOf(me, b && b.deviceId);
    if (!key) return json(res, 400, { err: '缺少身份标识' });
    const now = Date.now();
    const left = Math.max(0, (parseInt(playCooldowns[key], 10) || 0) - now);
    if (left > 0) {
      const r = playList(key);
      r.err = '冷却中，稍后再抽';
      return json(res, 429, r);
    }
    const gn = String(b && b.name || '').trim();
    const who = me ? me.name : (validGuestName(gn) ? gn : '游客');
    const text = PLAY_PUNS[Math.floor(Math.random() * PLAY_PUNS.length)];
    playRecords.push({ key: key, name: who, t: text, ts: now });
    if (playRecords.length > PLAY_KEEP) playRecords = playRecords.slice(-PLAY_KEEP);
    playCooldowns[key] = now + PLAY_CD_MS;
    /* 顺手清掉过期一天以上的冷却键，避免文件无限长大 */
    Object.keys(playCooldowns).forEach(function (k) {
      if ((parseInt(playCooldowns[k], 10) || 0) < now - 86400000) delete playCooldowns[k];
    });
    savePlay();
    return json(res, 200, Object.assign({ t: text, ts: now }, playList(key)));
  }

  /* ===== ★每日运签：领取/读取当日一签（账号或设备，当日固定，不重抽） ===== */
  /* 节日日：全员固定节日签（内容在前端 FESTIVAL_FORTUNES）；已抽记录迁移为节日签 */
  const DRAW_N = 8; // 与前端 FORTUNES 条数一致
  const FESTIVAL_DATE_MAP = {
    "2025-01-29":"chunjie","2025-02-12":"yuanxiao","2025-03-01":"longtaitou","2025-04-04":"qingming",
    "2025-05-31":"duanwu","2025-08-29":"qixi","2025-09-06":"zhongyuan","2025-10-06":"zhongqiu","2025-10-29":"chongyang",
    "2026-01-26":"laba","2026-02-10":"xiaonian","2026-02-16":"chuxi","2026-02-17":"chunjie","2026-03-03":"yuanxiao",
    "2026-03-20":"longtaitou","2026-04-05":"qingming","2026-06-19":"duanwu","2026-08-19":"qixi","2026-08-27":"zhongyuan",
    "2026-09-25":"zhongqiu","2026-10-18":"chongyang",
    "2027-01-15":"laba","2027-01-30":"xiaonian","2027-02-05":"chuxi","2027-02-06":"chunjie","2027-02-20":"yuanxiao",
    "2027-03-09":"longtaitou","2027-04-05":"qingming","2027-06-09":"duanwu","2027-08-08":"qixi","2027-08-16":"zhongyuan",
    "2027-09-15":"zhongqiu","2027-10-08":"chongyang",
    "2028-01-04":"laba","2028-01-19":"xiaonian","2028-01-25":"chuxi","2028-01-26":"chunjie","2028-02-09":"yuanxiao",
    "2028-02-26":"longtaitou","2028-04-04":"qingming","2028-05-28":"duanwu","2028-08-26":"qixi","2028-09-03":"zhongyuan",
    "2028-10-03":"zhongqiu","2028-10-26":"chongyang",
    "2029-01-22":"laba","2029-02-06":"xiaonian","2029-02-12":"chuxi","2029-02-13":"chunjie","2029-02-27":"yuanxiao",
    "2029-03-16":"longtaitou","2029-04-04":"qingming","2029-06-16":"duanwu","2029-08-16":"qixi","2029-08-24":"zhongyuan",
    "2029-09-22":"zhongqiu","2029-10-16":"chongyang"
  };
  const FESTIVAL_NAMES = {
    chunjie: "春节", yuanxiao: "元宵节", longtaitou: "龙抬头", qingming: "清明节",
    duanwu: "端午节", qixi: "七夕节", zhongyuan: "中元节", zhongqiu: "中秋节",
    chongyang: "重阳节", laba: "腊八节", xiaonian: "小年", chuxi: "除夕"
  };
  function festivalIdToday() { return FESTIVAL_DATE_MAP[dayStr()] || null; }
  /* 节日日：已抽迁移为节日签，返回固定节日 id；当日首次 first=true */
  function lockFestivalDraw(ck, zkey) {
    const festId = festivalIdToday();
    if (!festId) return null;
    const hit = zodiacDraws[ck];
    const had = !!(hit && (hit.idx != null || hit.festival));
    if (!hit || hit.festival !== festId) {
      zodiacDraws[ck] = {
        festival: festId, ts: Date.now(), key: zkey,
        prevIdx: (hit && hit.idx != null) ? hit.idx : undefined
      };
      saveZodiacDraws();
    }
    return {
      idx: null, festival: festId,
      festivalName: FESTIVAL_NAMES[festId] || festId,
      first: !had, date: dayStr()
    };
  }
  if (req.method === 'GET' && url === '/api/draw') {
    if (limited(ip, 'draw', 30, 60000)) return json(res, 429, { err: '查询太频繁' });
    const qs = new URL(req.url, 'http://x').searchParams;
    const zkey = zodiacKeyOf(me, qs.get('deviceId'));
    if (!zkey) return json(res, 400, { err: '缺少身份标识' });
    const ck = zkey + '|' + dayStr();
    const fest = lockFestivalDraw(ck, zkey);
    if (fest) return json(res, 200, fest);
    const hit = zodiacDraws[ck];
    if (hit && hit.idx != null) {
      return json(res, 200, {
        idx: hit.idx, first: false, date: dayStr(), transfer: !!hit.transfer
      });
    }
    return json(res, 200, { idx: null, first: false, date: dayStr() });
  }
  if (req.method === 'POST' && url === '/api/draw') {
    if (limited(ip, 'draw', 20, 60000)) return json(res, 429, { err: '操作太频繁' });
    const b = await body();
    const zkey = zodiacKeyOf(me, b && b.deviceId);
    if (!zkey) return json(res, 400, { err: '缺少身份标识' });
    const ck = zkey + '|' + dayStr();
    const fest = lockFestivalDraw(ck, zkey);
    if (fest) return json(res, 200, fest);
    /* 今日已抽：原样返回，绝不重抽 */
    if (zodiacDraws[ck] && zodiacDraws[ck].idx != null) {
      return json(res, 200, {
        idx: zodiacDraws[ck].idx, first: false, date: dayStr(),
        transfer: !!zodiacDraws[ck].transfer
      });
    }
    const idx = Math.floor(Math.random() * DRAW_N);
    zodiacDraws[ck] = { idx: idx, ts: Date.now(), key: zkey };
    saveZodiacDraws();
    return json(res, 200, { idx: idx, first: true, date: dayStr() });
  }
  /* ===== ★抽签转运：下签/下下签分享好事后重抽一次 =====
     只允许当天 idx=6（下签）或 7（下下签），每天一次，且只从 0..5 里重抽，
     不能「转运」又转回凶签；节日签不参与。 */
  if (req.method === 'POST' && url === '/api/draw/reroll') {
    if (limited(ip, 'drawreroll', 10, 60000)) return json(res, 429, { err: '操作太频繁' });
    const b = await body();
    const zkey = zodiacKeyOf(me, b && b.deviceId);
    if (!zkey) return json(res, 400, { err: '缺少身份标识' });
    const ck = zkey + '|' + dayStr();
    const hit = zodiacDraws[ck];
    if (!hit || hit.idx == null) return json(res, 400, { err: '今天还没有抽签' });
    if (hit.festival) return json(res, 400, { err: '节日签不能转运' });
    if (hit.transfer) {
      return json(res, 409, { err: '今天已经转运过了', idx: hit.idx, transfer: true });
    }
    if (hit.idx !== 6 && hit.idx !== 7) {
      return json(res, 400, { err: '只有下签才需要转运' });
    }
    const idx = Math.floor(Math.random() * 6);
    zodiacDraws[ck] = {
      idx: idx, ts: Date.now(), key: zkey, transfer: true, prevIdx: hit.idx
    };
    saveZodiacDraws();
    return json(res, 200, { ok: true, idx: idx, transfer: true, prevIdx: hit.idx });
  }

  /* ===== 打卡：连续天数跨端同步 ===== */
  if (req.method === 'GET' && url === '/api/checkin/stats') {
    if (needAuth(res, me)) return;
    const bu = findUser(me.name);
    if (!bu) return json(res, 404, { err: '账号不存在' });
    return json(res, 200, checkinStatus(bu));
  }
  if (req.method === 'POST' && url === '/api/checkin') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'checkin', 20, 60000)) return json(res, 429, { err: '操作太频繁' });
    const bu = findUser(me.name);
    if (!bu) return json(res, 404, { err: '账号不存在' });
    const b = await body();
    let dirty = false;
    /* 首次上云：用客户端已有的本地连续天数做迁移，避免老用户被清零 */
    if (!bu.checkinLast && b && b.last) {
      const last = String(b.last);
      if (last === dayStr() || last === yesterdayStr()) {
        bu.checkinLast = last;
        bu.checkinStreak = Math.max(1, Math.min(100000, parseInt(b.streak, 10) || 0));
        dirty = true;
      }
    }
    const d = dayStr();
    if (bu.checkinLast !== d) {
      bu.checkinStreak = bu.checkinLast === yesterdayStr()
        ? (parseInt(bu.checkinStreak, 10) || 0) + 1
        : 1;
      bu.checkinLast = d;
      dirty = true;
    }
    if (dirty) saveUsers();
    return json(res, 200, checkinStatus(bu));
  }

  /* ===== ★星盘：本命盘 / 行运盘（Kerykeion 本地计算，登录后可用） ===== */
  if (url === '/api/astro/natal' || url === '/api/astro/transit') {
    if (needAuth(res, me)) return;                                    /* 未登录直接 401 */
    if (limited(ip, 'astro', 40, 60000)) return json(res, 429, { err: '查询太频繁，歇一会儿再来' });
    const mode = url.endsWith('/natal') ? 'natal' : 'transit';
    const b = await body();
    if (!b || typeof b !== 'object') return json(res, 400, { err: '请求格式不正确' });

    const natal = sanitizeBirth(b.natal || b);
    if (!natal) return json(res, 400, { err: '出生信息不完整或超出范围（日期/时间/经纬度）' });
    const dt = new Date(Date.UTC(natal.year, natal.month - 1, natal.day));
    if (dt.getUTCFullYear() !== natal.year || dt.getUTCMonth() !== natal.month - 1 || dt.getUTCDate() !== natal.day) {
      return json(res, 400, { err: '出生日期不存在，请检查' });
    }

    let payload;
    if (mode === 'natal') {
      payload = natal;
    } else {
      /* 行运盘：以出生地做观测点（可用 obs 覆盖） */
      const obs = sanitizeObs(b.obs, natal);
      payload = { lat: obs.lat, lng: obs.lng, tz: obs.tz, city: obs.city, natal: natal };
    }

    let r;
    try {
      r = await runAstro(mode, payload);
    } catch (e) {
      console.error('[astro] ' + mode + ' 失败:', e && e.message);
      return json(res, 503, {
        ok: false,
        err: (e && e.astroEnv) ? '服务器还没装好星盘引擎（需要 Python + kerykeion），请联系管理员'
                               : '星盘服务暂时不可用，请稍后再试'
      });
    }
    if (!r || r.ok !== true) {
      console.error('[astro] ' + mode + ' 返回错误:', r && r.err);
      return json(res, 502, { ok: false, err: (r && r.err) || '星盘计算失败' });
    }
    return json(res, 200, r);
  }

  /* ===== 星盘解读（AI 深度版 + 本地保底 + 缓存）=====
     * GET /api/astro/interpret?birth=<JSON>&scope=natal|transit&force=1
     *   - 未登录 401；birth 必须过 sanitizeBirth 校验（缺字段 400）
     *   - scope=transit：行运解读，按「出生地时区的当天」缓存；缺省 natal 永久缓存
     *   - 命中缓存：{ ok, interpretation, cached:true }（秒出）
     *   - 未命中：调 astro.py interpret（AI 生成，最长约 60s；最多 30/min/IP）
     *   - force=1：跳过服务端缓存强制重算
     *   - 405 仅支持 GET
     */
  if (url === '/api/astro/interpret') {
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET');
      return json(res, 405, { err: '仅支持 GET' });
    }
    if (needAuth(res, me)) return;
    if (limited(ip, 'astro_interpret', 30, 60000)) return json(res, 429, { err: '解读请求太频繁，稍后再试' });

    let raw = '', force = false, scope = 'natal';
    try {
      const u = new URL(req.url, 'http://localhost');
      raw = u.searchParams.get('birth') || '';
      force = u.searchParams.get('force') === '1';
      scope = u.searchParams.get('scope') === 'transit' ? 'transit' : 'natal';
    } catch (e) { raw = ''; }
    let birth;
    try { birth = sanitizeBirth(raw ? JSON.parse(decodeURIComponent(raw)) : null); }
    catch (e) { return json(res, 400, { err: 'birth 参数不是合法 JSON：' + (e && e.message || '') }); }
    if (!birth) return json(res, 400, { err: '缺少或非法的 birth（需含 year/month/day/hour/minute/lat/lng/tz）' });

    const key = astroInterpretKey(birth, scope);
    if (!force) {
      const hit = astroInterprets[key];
      if (hit && hit.interpretation) {
        return json(res, 200, { ok: true, cached: true, key: key, scope: scope, interpretation: hit.interpretation, summary: hit.summary || null, source: hit.source || 'local', updated: hit.updated || 0 });
      }
    }
    try {
      const payload = Object.assign({}, birth, { scope: scope });
      const r = await runAstro('interpret', payload);
      if (!r || !r.ok) {
        return json(res, 502, Object.assign({ err: (r && r.err) || 'astro 解读失败' }, r || {}));
      }
      const item = {
        interpretation: r.interpretation,
        summary: r.summary || null,
        source: r.source || 'local',
        updated: Date.now()
      };
      astroInterprets[key] = item;
      saveAstroInterprets();
      return json(res, 200, { ok: true, cached: false, key: key, scope: scope, interpretation: item.interpretation, summary: item.summary, source: item.source, updated: item.updated });
    } catch (e) {
      return json(res, 503, { err: String(e && e.message || e).slice(0, 400), tried: (e && e.tried) || null });
    }
  }

  /* ===== 星盘：出生信息同步到云端（跟随账号，换设备/清缓存登录即可恢复） ===== */
  if (url === '/api/astro/birth') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'astro_birth', 30, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
    const bu = findUser(me.name);
    if (!bu) return json(res, 401, { err: '账号不存在' });

    if (req.method === 'GET') {
      /* 不返回头像/手机号/密码等敏感字段，只返出生信息和更新时间 */
      return json(res, 200, { ok: true, birth: bu.birth || null, updated: bu.birthUpdated || 0 });
    }
    if (req.method === 'DELETE') {
      /* 清空云端存档（与本地的"重填"按钮联动） */
      if (bu.birth) { delete bu.birth; bu.birthUpdated = Date.now(); saveUsers(); }
      return json(res, 200, { ok: true, birth: null });
    }
    if (req.method !== 'PUT' && req.method !== 'POST') {
      return json(res, 405, { err: '支持 GET / PUT / POST / DELETE' });
    }
    const rb = await body();
    const birth = sanitizeBirth(rb && rb.birth || rb);  /* 兼容 {birth:{...}} 和 直接 {...} 两种提交 */
    if (!birth) return json(res, 400, { err: '出生信息不完整或超出范围（日期/时间/经纬度/时区）' });
    bu.birth = birth;
    bu.birthUpdated = Date.now();
    saveUsers();
    return json(res, 200, { ok: true, birth: birth, updated: bu.birthUpdated });
  }

  /* ===== 摸鱼日历：休息日/上班时间配置同步到云端（跟随账号） ===== */
  if (url === '/api/moyu/config') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'moyu_cfg', 30, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
    const bu = findUser(me.name);
    if (!bu) return json(res, 401, { err: '账号不存在' });

    if (req.method === 'GET') {
      return json(res, 200, { ok: true, config: bu.moyuConfig || null, updated: bu.moyuUpdated || 0 });
    }
    if (req.method !== 'PUT' && req.method !== 'POST') {
      return json(res, 405, { err: '支持 GET / PUT / POST' });
    }
    const rb = await body();
    const cfg = rb && rb.config;
    const rest = Array.isArray(cfg && cfg.rest)
      ? cfg.rest.map(Number).filter(function (d) { return d >= 0 && d <= 6; })
      : null;
    const tm = /^([01]\d|2[0-3]):[0-5]\d$/;
    if (!rest || !tm.test((cfg && cfg.start) || '') || !tm.test((cfg && cfg.end) || '')) {
      return json(res, 400, { err: '摸鱼配置格式不正确' });
    }
    /* 中途休息（午休等）：可选项，填了就必须成对且开始早于结束 */
    const bs = cfg && cfg.breakStart, be = cfg && cfg.breakEnd;
    let brkS = null, brkE = null;
    if (bs || be) {
      if (!tm.test(bs || '') || !tm.test(be || '') || bs >= be) {
        return json(res, 400, { err: '中途休息时间不正确' });
      }
      brkS = bs; brkE = be;
    }
    const out = { rest: rest, start: cfg.start, end: cfg.end, breakStart: brkS, breakEnd: brkE };
    bu.moyuConfig = out;
    bu.moyuUpdated = Date.now();
    saveUsers();
    return json(res, 200, { ok: true, config: out, updated: bu.moyuUpdated });
  }

  /* ===== 星盘服务自检（部署后先访问它确认 Python 环境就绪） ===== */
  if (req.method === 'GET' && url === '/api/astro/version') {
    try {
      const r = await runAstro('version', {});
      return json(res, r.ok ? 200 : 503,
        Object.assign({ python: astroPy, script: astroScript }, r));
    } catch (e) {
      return json(res, 503, {
        ok: false,
        err: String(e && e.message || e).slice(0, 400),
        tried: (e && e.tried) || ASTRO_PY_CANDIDATES,
        py_candidates: ASTRO_PY_CANDIDATES,
        script_candidates: ASTRO_SCRIPT_CANDIDATES
      });
    }
  }

  /* ===== 历史上的今天（AI 生成，按天缓存，免登录）=====
   * GET /api/history/today?force=1
   *   - 免登录；当天缓存命中：{ ok, cached:true, date, items, source, ts }
   *   - 未命中：调 astro.py history（AI 挑选当天真实历史事件，最长约 60s；10/min/IP）
   *   - force=1：跳过服务端缓存强制重算（管理员换一版用）
   */
  if (req.method === 'GET' && url === '/api/history/today') {
    let force = false;
    try { force = new URL(req.url, 'http://localhost').searchParams.get('force') === '1'; } catch (e) {}
    const today = dayStr();
    if (!force && historyToday && historyToday.date === today && Array.isArray(historyToday.items) && historyToday.items.length) {
      return json(res, 200, { ok: true, cached: true, date: historyToday.date, items: historyToday.items, source: historyToday.source || 'ai', ts: historyToday.ts || 0 });
    }
    if (limited(ip, 'history', 10, 60000)) return json(res, 429, { err: '刷新太快啦，稍后再试' });
    try {
      const r = await runAstro('history', { month: Number(today.slice(5, 7)), day: Number(today.slice(8, 10)) });
      if (!r || !r.ok || !Array.isArray(r.items) || !r.items.length) {
        return json(res, 502, { err: (r && r.err) || '历史上的今天生成失败' });
      }
      historyToday = { date: today, items: r.items, source: r.source || 'ai', ts: Date.now() };
      saveHistoryToday();
      return json(res, 200, { ok: true, cached: false, date: today, items: historyToday.items, source: historyToday.source, ts: historyToday.ts });
    } catch (e) {
      return json(res, 503, { err: String(e && e.message || e).slice(0, 400) });
    }
  }

  /* ===== 小游戏：2048 / 记忆卡牌（账号同步 + 全站排行榜） ===== */
  if (req.method === 'POST' && url === '/api/games/score') {
    if (limited(ip, 'games', 40, 60000)) return json(res, 429, { err: '提交太频繁，稍后再试' });
    const b = await body();
    const key = String(b && b.game || '');
    if (GAME_IDS.indexOf(key) === -1) return json(res, 400, { err: '未知游戏' });
    const score = Math.floor(Number(b && b.score));
    if (!isFinite(score) || score < 0 || score > 1e9) return json(res, 400, { err: '成绩不合法' });
    /* 登录用户按账号昵称记账（昵称唯一且不允许以「游客」开头）；
       游客按设备 ID（gid）记账，昵称仅用于展示，避免同名玩家串号。
       旧客户端（页面没刷新、没带 gid）退回按昵称记账，保证不断供。 */
    let who = me ? me.name : '';
    let gid = '';
    if (!who) {
      who = String(b && b.name || '').trim();
      if (!validGuestName(who)) return json(res, 400, { err: '请先登录或刷新页面再试' });
      const g = String(b && b.gid || '').trim();
      if (GID_RE.test(g)) gid = g;
    }
    const arr = Array.isArray(gameScores[key]) ? gameScores[key] : (gameScores[key] = []);
    let rec = null, adopted = false;
    if (gid) { const c = claimGuestRec(arr, gid, who); rec = c.rec; adopted = c.adopted; }
    /* 旧客户端（没带 gid）只允许命中「也没绑定 gid」的老记录；
       绝不能碰到已绑定 gid 的记录，否则同名老客户端又能源源不断污染别人的成绩 */
    else { for (const r of arr) { if (r && !r.gid && r.name === who) { rec = r; break; } } }
    let improved = false, dirty = adopted;
    if (!rec) {
      rec = { name: who, score: score, ts: Date.now() };
      if (gid) rec.gid = gid;
      arr.push(rec); improved = true; dirty = true;
    } else {
      /* 昵称可能被改过：以提交时的昵称为准，身份仍是 gid */
      if (rec.name !== who) { rec.name = who; dirty = true; }
      if (score > rec.score) { rec.score = score; rec.ts = Date.now(); improved = true; dirty = true; }
    }
    if (dirty) saveGames();
    const board = gameBoard(key);
    let rank = 0;
    for (let i = 0; i < board.length; i++) { if (board[i] === rec) { rank = i + 1; break; } }
    return json(res, 200, { ok: true, improved: improved, best: rec.score, rank: rank || null, total: board.length });
  }

  if (req.method === 'GET' && url === '/api/games/board') {
    const sp = new URL(req.url, 'http://local').searchParams;
    const key = String(sp.get('game') || '');
    if (GAME_IDS.indexOf(key) === -1) return json(res, 400, { err: '未知游戏' });
    const all = gameBoard(key);
    /* 登录用户按账号昵称定位；游客按设备 ID（gid）定位，昵称仅在旧客户端没带 gid 时兜底 */
    let who = me ? me.name : '';
    let gid = '';
    if (!who) {
      const gn = String(sp.get('name') || '').trim();
      if (validGuestName(gn)) who = gn;
      const g = String(sp.get('gid') || '').trim();
      if (GID_RE.test(g)) gid = g;
    }
    const isMine = gid
      ? function (r) { return r.gid === gid; }
      : function (r) { return !!who && !r.gid && r.name === who; };
    let mine = null;
    for (let i = 0; i < all.length; i++) {
      if (isMine(all[i])) { mine = { rank: i + 1, score: all[i].score }; break; }
    }
    const board = all.slice(0, 50).map(function (r, i) {
      return { rank: i + 1, name: r.name, av: avatarOf(r.name), score: r.score, ts: r.ts, you: isMine(r) };
    });
    return json(res, 200, { ok: true, board: board, me: mine });
  }

  /* ===== 小游戏：正在玩（谁在玩 + 实时进度） =====
     心跳即取数：上报自己的进度，同时把该游戏当前在线的人整体返给前端。
     身份规则与成绩榜一致：登录用户按账号，游客按设备 ID（gid），旧客户端退回昵称。 */
  if (req.method === 'POST' && url === '/api/games/live') {
    if (limited(ip, 'gameslive', 60, 60000)) return json(res, 429, { err: '上报太频繁，稍后再试' });
    const b = await body();
    const game = String(b && b.game || '');
    if (LIVE_GAMES.indexOf(game) === -1) return json(res, 400, { err: '未知游戏' });
    let id = '', who = '', av = null;
    if (me) {
      id = 'u:' + me.name; who = me.name; av = avatarOf(me.name);
    } else {
      who = String(b && b.name || '').trim();
      if (!validGuestName(who)) who = '';
      const g = String(b && b.gid || '').trim();
      if (GID_RE.test(g)) id = 'g:' + g;          /* 游客按设备 ID，改昵称也不会串号 */
      else if (who) id = 'n:' + who;              /* 老客户端没带 gid，退回昵称记账 */
    }
    livePrune();   /* 先清过期，再取出/新建，避免新建的空表被清掉 */
    let list = liveUsers.get(game);
    if (!list) { list = new Map(); liveUsers.set(game, list); }
    if (id) {
      if (b && b.leave) list.delete(id);
      else list.set(id, { name: who || '游客', av: av, progress: String(b && b.progress || '').slice(0, LIVE_PROG_MAX), ts: Date.now() });
    }
    const out = [];
    list.forEach(function (r, key) {
      out.push({ name: r.name, av: r.av, progress: r.progress, ts: r.ts, you: key === id });
    });
    return json(res, 200, { ok: true, now: Date.now(), list: out });
  }

  /* ===== ★食谱日记：我的食谱库 + 购物清单（仅当前用户） ===== */
  if (req.method === 'GET' && url === '/api/cook') {
    if (needAuth(res, me)) return;
    const list = cookRecipes
      .filter(function (r) { return r.uid === me.name; })
      .sort(function (a, b) { return (b.updatedAt || 0) - (a.updatedAt || 0); })
      .map(cookPubMine);
    const shop = cookShopping[me.name];
    const fr = cookFridge[me.name];
    return json(res, 200, {
      ok: true, recipes: list,
      shopping: Array.isArray(shop) ? shop : [],
      fridge: Array.isArray(fr) ? fr : []
    });
  }

  /* ===== ★食谱广场：所有人的公开食谱（不含下厨日记） ===== */
  if (req.method === 'GET' && url === '/api/cook/square') {
    if (needAuth(res, me)) return;
    const list = cookRecipes
      .filter(function (r) { return r.visibility === 'public'; })
      .sort(function (a, b) { return (b.updatedAt || 0) - (a.updatedAt || 0); })
      .slice(0, COOK_SQUARE_MAX)
      .map(function (r) { return cookPubSquare(r, me); });
    return json(res, 200, { ok: true, recipes: list });
  }

  /* ===== ★食谱图：上传封面 / 步骤图（前端压缩后 base64，返回可直用的路径） =====
     图片单独上传、食谱只存路径：食谱体量小（<256KB 限制不变），
     且用户在向导里选完图就能立刻预览，不必等整份食谱保存。 */
  if (req.method === 'POST' && url === '/api/cook/img') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'cookimg', 80, 60000)) return json(res, 429, { err: '上传太频繁，歇口气再试' });
    const raw = await readBody(req, 12 * 1024 * 1024);
    if (raw == null) return json(res, 413, { err: '图片太大了' });
    let b; try { b = JSON.parse(raw); } catch (e) { return json(res, 400, { err: '参数错误' }); }
    const buf = parseDataUrl(b && b.img);
    if (!buf) return json(res, 400, { err: '图片格式不正确' });
    if (buf.length > 5 * 1024 * 1024) return json(res, 400, { err: '图片过大（超过 5MB）' });
    const fname = imgName();
    try { fs.writeFileSync(path.join(COOK_DIR, fname), buf); } catch (e) { return json(res, 500, { err: '图片保存失败，请重试' }); }
    return json(res, 200, { ok: true, url: '/api/img/cook/' + fname });
  }

  /* ===== ★食谱：新建 / 更新（recipe.id 为空或未命中则新建） ===== */
  if (req.method === 'POST' && url === '/api/cook/recipe') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'cook', 60, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
    const raw = await readBody(req, 256 * 1024);
    if (raw == null) return json(res, 413, { err: '内容太大了' });
    let b; try { b = JSON.parse(raw); } catch (e) { return json(res, 400, { err: '参数错误' }); }
    const out = cookPut(me.name, b && b.recipe);
    if (out.err) return json(res, out.code || 400, { err: out.err });
    return json(res, 200, { ok: true, recipe: cookPubMine(out.rec) });
  }

  /* ===== ★食谱：删除（仅本人） ===== */
  if (req.method === 'POST' && url === '/api/cook/recipe/delete') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'cook', 60, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
    const raw = await readBody(req, 8 * 1024);
    if (raw == null) return json(res, 413, { err: '内容太大了' });
    let b; try { b = JSON.parse(raw); } catch (e) { return json(res, 400, { err: '参数错误' }); }
    const id = String(b && b.id || '');
    const idx = cookRecipes.findIndex(function (r) { return r.id === id; });
    if (idx === -1) return json(res, 404, { err: '食谱不存在' });
    if (cookRecipes[idx].uid !== me.name) return json(res, 403, { err: '只能删除自己的食谱' });
    const gone = cookRecipes.splice(idx, 1)[0];
    saveCook();
    /* 顺手清掉这份食谱独占的图片（被别人「收藏」共享的图要留着，否则对方会裂图） */
    const used = {};
    cookRecipes.forEach(function (r) {
      if (r.cover) used[r.cover] = 1;
      (r.steps || []).forEach(function (s) { if (s && s.img) used[s.img] = 1; });
    });
    const mine = [];
    if (gone.cover) mine.push(gone.cover);
    (gone.steps || []).forEach(function (s) { if (s && s.img) mine.push(s.img); });
    mine.forEach(function (p) {
      if (used[p]) return;
      const m = /^\/api\/img\/cook\/([A-Za-z0-9_-]+\.jpg)$/.exec(p);
      if (!m) return;
      try { fs.unlinkSync(path.join(COOK_DIR, m[1])); } catch (e) {}
    });
    return json(res, 200, { ok: true });
  }

  /* ===== ★购物清单：整体覆盖保存（按用户隔离） ===== */
  if (req.method === 'POST' && url === '/api/cook/shopping') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'cook', 60, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
    const raw = await readBody(req, 256 * 1024);
    if (raw == null) return json(res, 413, { err: '内容太大了' });
    let b; try { b = JSON.parse(raw); } catch (e) { return json(res, 400, { err: '参数错误' }); }
    cookShopping[me.name] = cookShoppingClean(b && b.shopping);
    saveCook();
    return json(res, 200, { ok: true, shopping: cookShopping[me.name] });
  }

  /* ===== ★我的冰箱：整体覆盖保存（按用户隔离） ===== */
  if (req.method === 'POST' && url === '/api/cook/fridge') {
    if (needAuth(res, me)) return;
    if (limited(ip, 'cook', 60, 60000)) return json(res, 429, { err: '操作太频繁，稍后再试' });
    const raw = await readBody(req, 256 * 1024);
    if (raw == null) return json(res, 413, { err: '内容太大了' });
    let b; try { b = JSON.parse(raw); } catch (e) { return json(res, 400, { err: '参数错误' }); }
    cookFridge[me.name] = cookFridgeClean(b && b.fridge);
    saveCook();
    return json(res, 200, { ok: true, fridge: cookFridge[me.name] });
  }

  if (req.method === 'GET' && url === '/') {
    return json(res, 200, { ok: true, name: 'chimu-api', date: dayStr(), posts: posts.length, users: users.length });
  }
  cors(res, 404, 'text/plain', 'Not Found');
});

server.listen(PORT, HOST, function () {
  console.log('[chimu] on ' + HOST + ':' + PORT + ' | today=' + today + ' | posts=' + posts.length + ' | users=' + users.length + ' | notes=' + notes.length);
});
