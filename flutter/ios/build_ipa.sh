#!/usr/bin/env bash
# 仅能在 macOS + Xcode 上运行。
# 用法：cd flutter && bash ios/build_ipa.sh
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌ iOS IPA 必须在 macOS 上构建（需要 Xcode / CocoaPods）。"
  exit 1
fi

cd "$(dirname "$0")/.."

VERSION="$(awk '/^version:/{print $2; exit}' pubspec.yaml | cut -d+ -f1)"
if [[ -z "${VERSION}" ]]; then
  echo "❌ 无法从 pubspec.yaml 读取版本号。"
  exit 1
fi

KEY="${GLM_API_KEY:-}"
if [[ -z "${KEY}" && -f "../密钥/glm.key" ]]; then
  KEY="$(tr -d '\r\n' < "../密钥/glm.key")"
fi
if [[ -z "${KEY}" ]]; then
  echo "❌ 缺少 GLM API Key：设置环境变量 GLM_API_KEY，或放置 ../密钥/glm.key。"
  exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "❌ 未找到 CocoaPods。请先执行：sudo gem install cocoapods"
  exit 1
fi

echo "▶ flutter pub get"
flutter pub get

echo "▶ pod install"
( cd ios && pod install --repo-update )

echo "▶ flutter build ipa (v${VERSION})"
flutter build ipa \
  --release \
  --export-method app-store \
  --dart-define=APP_VERSION="${VERSION}" \
  --dart-define=GLM_API_KEY="${KEY}"

echo
echo "✅ IPA 目录：build/ios/ipa/"
ls -lh build/ios/ipa/ 2>/dev/null || true
echo
echo "下一步：用 Xcode Organizer 或 Transporter 上传 App Store Connect。"
