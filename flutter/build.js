// build.js — Citro 原生 Flutter 版一键打包（v1.1.3 起）
// 用法: node build.js [debug|release]   （默认 release）
// 产物输出到 ../APK/Citro-v<版本>-<类型>.apk
//
// v1.1.3 起不再打包网页资源：所有页面由 Flutter Widget 原生实现，
// 不依赖 WebView / assets/www，也不再调用 kotlin/sync-www.js。
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const dir = __dirname;
const rootDir = path.resolve(dir, '..');
const flutterBin = process.env.FLUTTER_BIN || 'C:\\Android\\flutter\\bin\\flutter.bat';

const buildType = (process.argv[2] || 'release').toLowerCase();
if (['debug', 'release'].indexOf(buildType) < 0) {
  console.error('type 只能是 debug / release');
  process.exit(1);
}

let version = 'x';
let versionCode = 0;
try {
  const pub = fs.readFileSync(path.join(dir, 'pubspec.yaml'), 'utf8');
  const m = pub.match(/^version:\s*(\d+\.\d+\.\d+)\s*\+\s*(\d+)/m);
  if (m) {
    version = m[1];
    versionCode = Number(m[2]);
  }
} catch (e) {}
if (!versionCode && version !== 'x') {
  const parts = version.split('.').map(Number);
  versionCode = parts[0] * 1000 + parts[1] * 100 + parts[2];
}

const keyProps = path.join(dir, 'android', 'app', 'key.properties');
if (buildType === 'release' && !fs.existsSync(keyProps)) {
  console.error('\n❌ 缺少 ' + path.relative(rootDir, keyProps));
  console.error('   release 构建需要签名配置（密钥/citro-release.jks + key.properties）。');
  process.exit(1);
}

// 中文路径：JVM 默认 GBK 会把源码路径转义成乱码（同 kotlin / 旧版 flutter 构建的踩坑结论）。
const env = Object.assign({}, process.env, {
  JAVA_TOOL_OPTIONS: '-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8',
});

const buildArgs = ['build', 'apk', '--' + buildType, '--dart-define=APP_VERSION=' + version];
console.log(`> flutter build apk --${buildType}  (v${version})`);
try {
  cp.execFileSync(flutterBin, buildArgs, {
    cwd: dir,
    stdio: 'inherit',
    env,
    shell: true,
    windowsHide: true,
  });
} catch (e) {
  console.error('\n❌ Flutter 构建失败');
  process.exit(1);
}

const src = path.join(dir, 'build', 'app', 'outputs', 'flutter-apk',
  buildType === 'release' ? 'app-release.apk' : 'app-debug.apk');
if (!fs.existsSync(src)) {
  console.error('❌ 找不到构建产物：' + src);
  process.exit(1);
}
const dst = path.join(rootDir, 'APK', `Citro-v${version}-${buildType}.apk`);
fs.mkdirSync(path.dirname(dst), { recursive: true });
fs.copyFileSync(src, dst);
const mb = (fs.statSync(dst).size / 1024 / 1024).toFixed(1);
console.log(`\n✅ 已输出 ${path.relative(rootDir, dst)} (${mb} MB)`);
console.log('   签名：密钥/citro-release.jks（与 v1.1.1 相同，可直接覆盖升级）');

/* 应用内更新清单：和 APK 一起上传到 OBS 的 APK/ 目录。
   更新说明从 update_notes.txt 读取（每行一条），没有则用通用文案；
   强制更新可在生成后把 force 改为 true。 */
if (buildType === 'release' && version !== 'x') {
  const manifestPath = path.join(rootDir, 'APK', 'update.json');
  let notes = [];
  try {
    notes = fs.readFileSync(path.join(dir, 'update_notes.txt'), 'utf8')
      .split(/\r?\n/)
      .map((line) => line.replace(/^\s*[-•*]\s*/, '').trim())
      .filter(Boolean);
  } catch (e) {}
  if (notes.length === 0) notes = ['修复已知问题，优化使用体验。'];
  const manifest = {
    version,
    versionCode,
    url: `https://obs.chimu-claw.xyz/APK/${path.basename(dst)}`,
    size: fs.statSync(dst).size,
    notes,
    publishedAt: new Date().toISOString().slice(0, 10),
    force: false,
  };
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  console.log(`✅ 已输出 ${path.relative(rootDir, manifestPath)}（随 APK 一起上传，App 内更新依赖它）`);
}
