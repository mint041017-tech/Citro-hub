#!/usr/bin/env bash
# 仅 macOS 可用。启动模拟器、统一状态栏，然后手动切页、逐张截屏。
# 用法：
#   bash "app dist/scripts/capture-ios-screenshots.sh" "iPhone 16 Pro Max"
#   bash "app dist/scripts/capture-ios-screenshots.sh" "iPad Pro 13-inch (M4)"
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌ 该脚本只能在 macOS 上运行（需要 Xcode Simulator）。"
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "❌ 未找到 xcrun，请先安装 Xcode。"
  exit 1
fi

DEVICE="${1:-}"
if [[ -z "${DEVICE}" ]]; then
  echo "用法: bash \"app dist/scripts/capture-ios-screenshots.sh\" \"<模拟器名称>\""
  echo
  echo "可用设备："
  xcrun simctl list devices available | sed -n '1,80p'
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT="${ROOT}/app dist/screenshots/raw"
mkdir -p "${OUT}"

xcrun simctl boot "${DEVICE}" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "${DEVICE}" -b

xcrun simctl status_bar "${DEVICE}" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4 || true

echo
echo "设备：${DEVICE}"
echo "1. 请在 Simulator 中打开 Citro，用演示账号登录。"
echo "2. 手动切到目标页面（首页/游戏/社区/食谱/听隅）。"
echo "3. 每按一次回车截一张；输入 q 回车结束。"
echo

n=1
while true; do
  read -r -p "第 ${n} 张，按回车截屏（q 结束）: " ans
  if [[ "${ans}" == "q" ]]; then
    break
  fi
  ts="$(date +%Y%m%d-%H%M%S)"
  safe_device="${DEVICE// /_}"
  file="${OUT}/${safe_device}-${n}-${ts}.png"
  xcrun simctl io "${DEVICE}" screenshot "${file}"
  echo "✅ ${file}"
  n=$((n + 1))
done

echo
echo "完成。裁切/排版后把成品放到 app dist/screenshots/final/。"
