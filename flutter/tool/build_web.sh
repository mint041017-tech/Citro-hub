#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

flutter build web --release --no-web-resources-cdn "$@"
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
find "$out/assets" -type f \
  \( -name '*.ttf' -o -name '*.otf' -o -name '*.json' -o -name '*.bin' \) \
  -exec gzip -9 -kf {} +

du -sh "$out"
