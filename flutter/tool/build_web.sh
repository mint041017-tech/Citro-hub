#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(awk '/^version:/{print $2; exit}' pubspec.yaml | cut -d+ -f1)"
flutter build web --release --no-web-resources-cdn --dart-define=APP_VERSION="$VERSION" "$@"
out="build/web"

# The JS build only selects CanvasKit; these renderer payloads are never requested.
rm -rf \
  "$out/canvaskit/webparagraph" \
  "$out/canvaskit/skwasm.js" \
  "$out/canvaskit/skwasm.wasm" \
  "$out/canvaskit/skwasm.js.symbols" \
  "$out/canvaskit/skwasm_heavy.js" \
  "$out/canvaskit/skwasm_heavy.wasm" \
  "$out/canvaskit/skwasm_heavy.js.symbols" \
  "$out/canvaskit/wimp.js" \
  "$out/canvaskit/wimp.wasm" \
  "$out/canvaskit/wimp.js.symbols"
find "$out" -name '*.symbols' -type f -delete

# Nginx can serve these directly with gzip_static.
for file in \
  main.dart.js \
  flutter_bootstrap.js \
  canvaskit/canvaskit.js \
  canvaskit/canvaskit.wasm \
  canvaskit/chromium/canvaskit.js \
  canvaskit/chromium/canvaskit.wasm; do
  gzip -9 -kf "$out/$file"
done
# 网页端已移除 Mod / 工具 / 驱动资源区，产物里不再携带 Mod 封面。
rm -rf "$out/assets/assets/images/mods"

# 小游戏改为延迟加载后，dart2js 会在根目录产出额外分片；
# 一并预压缩，避免服务器动态 gzip 增加首包等待。
find "$out" -maxdepth 1 -type f -name '*.js' -exec gzip -9 -kf {} +
# flutter build 可能从编译缓存带回上一次的延迟分片；只保留 main.dart.js 引用的版本。
node -e "const fs=require('fs');const dir='$out';const src=fs.readFileSync(dir+'/main.dart.js','utf8');const refs=new Set(src.match(/main\.dart\.js_\d+\.part\.js/g)||[]);for(const f of fs.readdirSync(dir)){const base=f.replace(/\.gz$/,'');if(/^main\.dart\.js_\d+\.part\.js$/.test(base)&&!refs.has(base))fs.unlinkSync(dir+'/'+f);}"
find "$out/assets" -type f \
  \( -name '*.ttf' -o -name '*.otf' -o -name '*.json' -o -name '*.bin' \) \
  -exec gzip -9 -kf {} +

# 可选：WEB_BROTLI=1 且本机装了 brotli 时，额外产一份 .br。
# 只有线上 nginx 装了 ngx_brotli 并用 brotli_static 才有意义，否则只是多占包体，
# 所以默认关闭。开启后 CanvasKit wasm 从 gzip 2.78 MB 降到约 2.2 MB，
# main.dart.js 从 1.59 MB 降到约 1.2 MB。
if [ "${WEB_BROTLI:-0}" = "1" ] && command -v brotli >/dev/null 2>&1; then
  for file in \
    main.dart.js \
    canvaskit/canvaskit.wasm \
    canvaskit/chromium/canvaskit.wasm; do
    [ -f "$out/$file" ] && brotli -q 11 -f -o "$out/$file.br" "$out/$file"
  done
fi

du -sh "$out"
