// tool/perf_web.js — 本地 Web 性能采样包（PerfProbe + 静态服务）
//
// 用法:
//   node tool/perf_web.js                 # wasm 构建（默认，和生产一致）
//   node tool/perf_web.js --js            # CanvasKit/JS 构建，用来做 A/B 对比
//   node tool/perf_web.js --profile       # profile 构建（数值偏向未优化编译）
//   node tool/perf_web.js --serve-only    # 复用已有 build/web，仅起本地服务
//   node tool/perf_web.js --no-isolate    # 去掉 COOP/COEP，模拟未跨域隔离的站点
//   node tool/perf_web.js --require-corp  # 用 require-corp 验证 OBS 资源兼容性
//   node tool/perf_web.js --port=9000 --verbose
//
// 打开终端里打印的地址，F12 控制台过滤 "CITRO_PERF" 即可看到
// 每次切页/滚动的 build 与 raster p50/p90、cadence 与 jank 比例。
const fs = require('fs');
const path = require('path');
const http = require('http');
const cp = require('child_process');

const dir = path.resolve(__dirname, '..');
const out = path.join(dir, 'build', 'web');
const flutterBin = process.env.FLUTTER_BIN || 'C:\\Android\\flutter\\bin\\flutter.bat';

const argv = process.argv.slice(2);
const has = (flag) => argv.includes(flag);
const serveOnly = has('--serve-only');
const profile = has('--profile');
const useWasm = !has('--js');
const isolate = !has('--no-isolate');
const requireCorp = has('--require-corp');
const verbose = has('--verbose');
const portArg = argv.find((a) => a.startsWith('--port='));
const port = portArg ? Number(portArg.split('=')[1]) : 8099;

if (!Number.isInteger(port) || port <= 0 || port > 65535) {
  console.error('❌ --port 需要是 1-65535 的整数');
  process.exit(1);
}

let version = 'x';
try {
  const pub = fs.readFileSync(path.join(dir, 'pubspec.yaml'), 'utf8');
  const m = pub.match(/^version:\s*(\d+\.\d+\.\d+)/m);
  if (m) version = m[1];
} catch (e) {}

if (!serveOnly) {
  // release 才能反映线上真实的编译优化与帧耗时；probe 由 define 显式打开。
  const buildArgs = [
    'build', 'web',
    profile ? '--profile' : '--release',
    ...(useWasm ? ['--wasm'] : []),
    '--no-web-resources-cdn',
    '--dart-define=CITRO_PERF_PROBE=true',
    '--dart-define=APP_VERSION=' + version,
  ];
  console.log(`> flutter ${buildArgs.join(' ')}`);
  try {
    cp.execFileSync(flutterBin, buildArgs, {
      cwd: dir,
      stdio: 'inherit',
      env: Object.assign({}, process.env, {
        JAVA_TOOL_OPTIONS: '-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8',
      }),
      shell: true,
      windowsHide: true,
    });
  } catch (e) {
    console.error('\n❌ Flutter 构建失败');
    process.exit(1);
  }
}

const indexFile = path.join(out, 'index.html');
if (!fs.existsSync(indexFile)) {
  console.error('❌ 找不到 ' + path.relative(dir, indexFile) + '，先跑一次不带 --serve-only 的构建');
  process.exit(1);
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
  '.map': 'application/json; charset=utf-8',
  '.symbols': 'text/plain; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
};

const server = http.createServer((req, res) => {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch (e) {
    res.writeHead(400).end('bad request');
    return;
  }
  if (pathname === '/' || pathname === '') pathname = '/index.html';
  const file = path.join(out, path.normalize(pathname).replace(/^([\\/])+/, ''));

  const headers = {
    'Content-Type': 'application/octet-stream',
    'Cache-Control': 'no-store',
  };
  if (isolate) {
    // Skwasm 多线程依赖 SharedArrayBuffer，必须有 cross-origin isolation。
    // credentialless 允许 OBS 这类没有 CORP/CORS 头的跨域图片继续加载；
    // require-corp 更严格，但会直接拦掉它们，只用于验证线上配置。
    headers['Cross-Origin-Opener-Policy'] = 'same-origin';
    headers['Cross-Origin-Embedder-Policy'] =
      requireCorp ? 'require-corp' : 'credentialless';
    headers['Cross-Origin-Resource-Policy'] = 'cross-origin';
  }

  if (!file.startsWith(out) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404, headers).end('not found');
    return;
  }
  headers['Content-Type'] =
    MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';
  if (verbose) console.log('  ' + req.method + ' ' + pathname);
  res.writeHead(200, headers);
  fs.createReadStream(file).pipe(res);
});

server.listen(port, '127.0.0.1', () => {
  const url = `http://127.0.0.1:${port}/`;
  const renderer = useWasm ? 'Skwasm (wasm)' : 'CanvasKit (js)';
  console.log('\n✅ 采样包就绪（' + (profile ? 'profile' : serveOnly ? '已有构建' : 'release') + ' / ' + renderer + '）');
  console.log('   ' + url);
  if (isolate) {
    console.log('   跨域隔离已开启（COOP + COEP ' + (requireCorp ? 'require-corp' : 'credentialless') + '）');
  } else {
    console.log('   未开启跨域隔离：Skwasm 会退回单线程，Raster 仍在主线程');
  }
  console.log('   1) 打开 F12 → Console，过滤 CITRO_PERF');
  console.log('   2) 首帧后会自动切 3 次页签并做一次合成滚动，期间不要操作');
  console.log('   3) 之后手动滚动手帐页，同样会输出 scroll 样本');
  console.log('   4) 关注 build over 与 raster over 谁更高：build 高改代码，raster 高才考虑换引擎');
  console.log('   Ctrl+C 结束服务\n');
});