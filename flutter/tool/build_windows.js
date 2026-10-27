#!/usr/bin/env node
// Windows 一键打包：Flutter release → 便携目录 → Inno Setup 安装包 → 更新清单
// 用法: node tool/build_windows.js [--no-installer]
// 产物: ../WIN/Citro-v<版本>-win64/（便携版）、../exe/Citro-v<版本>-win64-setup.exe 与 update.json
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');

const dir = path.resolve(__dirname, '..');
const rootDir = path.resolve(dir, '..');
const flutterBin = process.env.FLUTTER_BIN || 'C:\\Android\\flutter\\bin\\flutter.bat';
const skipInstaller = process.argv.includes('--no-installer');

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
  const p = version.split('.').map(Number);
  versionCode = p[0] * 1000 + p[1] * 100 + p[2];
}
if (version === 'x') {
  console.error('❌ 无法从 pubspec.yaml 读取版本号');
  process.exit(1);
}

const distDir = path.join(dir, 'build', 'windows', 'x64', 'runner', 'Release');
const portableRoot = path.join(rootDir, 'WIN');
const setupRoot = path.join(rootDir, 'exe');
const portableDir = path.join(portableRoot, `Citro-v${version}-win64`);
const updateBase = (process.env.UPDATE_BASE_URL || 'https://obs.chimu-claw.xyz/exe').replace(/\/$/, '');

if (fs.existsSync(path.join(portableDir, 'Citro.exe'))) {
  try {
    fs.rmSync(portableDir, { recursive: true, force: true });
  } catch (e) {
    console.error(`❌ 无法清理旧的便携目录，可能 Citro 正在运行：${portableDir}`);
    process.exit(1);
  }
}

const buildArgs = ['build', 'windows', '--release', `--dart-define=APP_VERSION=${version}`];
if (process.env.WINDOWS_UPDATE_MANIFEST_URL) {
  buildArgs.push(`--dart-define=WINDOWS_UPDATE_MANIFEST_URL=${process.env.WINDOWS_UPDATE_MANIFEST_URL}`);
}
if (process.env.AI_PROXY_URL) {
  buildArgs.push(`--dart-define=AI_PROXY_URL=${process.env.AI_PROXY_URL}`);
}
console.log(`> flutter ${buildArgs.join(' ')}`);
try {
  cp.execFileSync(flutterBin, buildArgs, {
    cwd: dir,
    stdio: 'inherit',
    shell: true,
    windowsHide: true,
    env: Object.assign({}, process.env, {
      JAVA_TOOL_OPTIONS: '-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8',
    }),
  });
} catch (e) {
  console.error('\n❌ Flutter Windows 构建失败');
  process.exit(1);
}

if (!fs.existsSync(path.join(distDir, 'Citro.exe'))) {
  console.error(`❌ 找不到构建产物：${distDir}`);
  process.exit(1);
}
fs.mkdirSync(portableRoot, { recursive: true });
fs.mkdirSync(setupRoot, { recursive: true });
fs.cpSync(distDir, portableDir, { recursive: true });
// WebView2 运行缓存会留在这里，不应该进入安装包。
const webviewCache = path.join(portableDir, 'Citro.exe.WebView2');
if (fs.existsSync(webviewCache)) {
  fs.rmSync(webviewCache, { recursive: true, force: true });
}
const portableMb = (() => {
  let bytes = 0;
  const walk = (p) => {
    for (const entry of fs.readdirSync(p, { withFileTypes: true })) {
      const full = path.join(p, entry.name);
      if (entry.isDirectory()) walk(full);
      else bytes += fs.statSync(full).size;
    }
  };
  walk(portableDir);
  return (bytes / 1024 / 1024).toFixed(1);
})();
console.log(`\n✅ 便携版：${path.relative(rootDir, portableDir)} (${portableMb} MB)`);

let setupPath = null;
if (!skipInstaller) {
  const candidates = [
    process.env.INNO_ISCC,
    path.join(process.env.LOCALAPPDATA || '', 'Programs', 'Inno Setup 6', 'ISCC.exe'),
    'C:\\Program Files (x86)\\Inno Setup 6\\ISCC.exe',
    'C:\\Program Files\\Inno Setup 6\\ISCC.exe',
  ].filter(Boolean);
  const iscc = candidates.find((p) => fs.existsSync(p));
  if (!iscc) {
    console.error('\n❌ 未找到 Inno Setup 6 的 ISCC.exe。请安装后重试，或使用 --no-installer。');
    process.exit(1);
  }
  const script = path.join(dir, 'tool', 'windows_installer.iss');
  const icon = path.join(dir, 'windows', 'runner', 'resources', 'app_icon.ico');
  try {
    cp.execFileSync(
      iscc,
      [
        '/Qp',
        `/DMyAppVersion=${version}`,
        `/DSourceDir=${portableDir}`,
        `/DOutputDir=${setupRoot}`,
        `/DSetupIcon=${icon}`,
        script,
      ],
      { cwd: rootDir, stdio: 'inherit', windowsHide: true },
    );
    setupPath = path.join(setupRoot, `Citro-v${version}-win64-setup.exe`);
  } catch (e) {
    console.error('\n❌ Inno Setup 打包失败');
    process.exit(1);
  }
  if (!fs.existsSync(setupPath)) {
    console.error(`❌ 找不到安装包：${setupPath}`);
    process.exit(1);
  }
  console.log(`✅ 安装包：${path.relative(rootDir, setupPath)} (${(fs.statSync(setupPath).size / 1024 / 1024).toFixed(1)} MB)`);
}

let notes = [];
try {
  notes = fs
    .readFileSync(path.join(dir, 'update_notes_windows.txt'), 'utf8')
    .split(/\r?\n/)
    .map((line) => line.replace(/^\s*[-•*]\s*/, '').trim())
    .filter(Boolean);
} catch (e) {}
if (notes.length === 0) notes = ['修复已知问题，优化桌面端体验。'];

const manifest = {
  version,
  versionCode,
  url: `${updateBase}/Citro-v${version}-win64-setup.exe`,
  size: setupPath ? fs.statSync(setupPath).size : 0,
  sha256: setupPath
    ? crypto.createHash('sha256').update(fs.readFileSync(setupPath)).digest('hex')
    : null,
  notes,
  publishedAt: new Date().toISOString().slice(0, 10),
  force: false,
};
const manifestPath = path.join(setupRoot, 'update.json');
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
console.log(`✅ 更新清单：${path.relative(rootDir, manifestPath)}`);
console.log(`   将清单与安装包上传到 ${updateBase}/ 即可启用应用内更新。`);
