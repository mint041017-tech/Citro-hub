#!/usr/bin/env node
// upload-obs.mjs — 把构建产物上传到 OBS（obs.chimu-claw.xyz）
//
// 这个桶是公开读写的，匿名即可 PUT / DELETE，不需要 AK/SK，也不需要 obsutil。
// 用法：
//   node devtools/upload-obs.mjs <远端目录> <本地文件> [更多文件...]
//   node devtools/upload-obs.mjs --delete <远端目录> <远端文件名> [更多文件名...]
//   node devtools/upload-obs.mjs --base https://other.host <远端目录> <文件...>
//
// 例：
//   node devtools/upload-obs.mjs APK APK/Citro-v2.1.2-release.apk APK/update.json
//   node devtools/upload-obs.mjs exe exe/Citro-v2.1.2-win64-setup.exe exe/update.json
//
// 注意：公开写意味着任何拿到地址的人都能覆盖同名文件，
// 所以版本号 / 文件名不要复用（本项目一直用版本号做文件名，没问题）。
import fs from 'node:fs';
import path from 'node:path';
import https from 'node:https';

const DEFAULT_BASE = 'https://obs.chimu-claw.xyz';

const MIME = {
  '.json': 'application/json; charset=utf-8',
  '.apk': 'application/vnd.android.package-archive',
  '.exe': 'application/vnd.microsoft.portable-executable',
  '.zip': 'application/zip',
  '.txt': 'text/plain; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.woff2': 'font/woff2',
};

function parseArgs(argv) {
  const opts = { base: DEFAULT_BASE, del: false, dir: '', files: [] };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--delete') opts.del = true;
    else if (a === '--base') opts.base = argv[++i].replace(/\/+$/, '');
    else rest.push(a);
  }
  if (rest.length < 1) {
    console.error('缺少远端目录。用法: node devtools/upload-obs.mjs <远端目录> <文件...>');
    process.exit(2);
  }
  opts.dir = rest[0].replace(/^\/+|\/+$/g, '');
  opts.files = rest.slice(1);
  return opts;
}

function request(method, url, { body, contentType } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const headers = { 'Content-Length': body ? body.length : 0 };
    if (contentType) headers['Content-Type'] = contentType;
    const req = https.request(
      { hostname: u.hostname, path: u.pathname + u.search, method, headers },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () =>
          resolve({
            status: res.statusCode,
            body: Buffer.concat(chunks).toString('utf8'),
          }),
        );
      },
    );
    req.on('error', reject);
    req.setTimeout(120_000, () => req.destroy(new Error('请求超时')));
    if (body) req.write(body);
    req.end();
  });
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.files.length === 0) {
    console.error('没有要上传的文件。');
    process.exit(2);
  }
  let failed = 0;
  for (const name of opts.files) {
    const key = `${opts.dir}/${path.basename(name)}`;
    const url = `${opts.base}/${key}`;
    if (opts.del) {
      const r = await request('DELETE', url);
      const ok = r.status >= 200 && r.status < 300;
      console.log(`${ok ? '🗑 ' : '❌'} DELETE ${url} → ${r.status}`);
      if (!ok) failed++;
      continue;
    }
    if (!fs.existsSync(name)) {
      console.error(`❌ 找不到本地文件：${name}`);
      failed++;
      continue;
    }
    const body = fs.readFileSync(name);
    const mime = MIME[path.extname(name).toLowerCase()] || 'application/octet-stream';
    const up = await request('PUT', url, { body, contentType: mime });
    const ok = up.status >= 200 && up.status < 300;
    console.log(
      `${ok ? '✅' : '❌'} PUT ${url}  (${(body.length / 1024 / 1024).toFixed(1)} MB) → ${up.status}`,
    );
    if (!ok) {
      console.error(`   响应：${up.body.slice(0, 300)}`);
      failed++;
      continue;
    }
    // 回读校验：公开写桶也可能被 CDN 缓存，确认状态码即可。
    const head = await request('HEAD', url);
    if (head.status !== 200) {
      console.warn(`⚠️  回读 ${url} → ${head.status}（可能是 CDN 缓存，稍后再看）`);
    }
  }
  if (failed > 0) {
    console.error(`\n${failed} 个文件处理失败。`);
    process.exit(1);
  }
  console.log('\n全部完成。');
}

main().catch((e) => {
  console.error('❌', e.message || e);
  process.exit(1);
});
