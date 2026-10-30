#!/usr/bin/env bash
# 匿名检查公网法务页与后端基础接口，不登录、不写数据。
# 用法：bash "app dist/scripts/verify-public-urls.sh" [https://chimu-claw.xyz]
set -uo pipefail

BASE="${1:-https://chimu-claw.xyz}"
BASE="${BASE%/}"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t citro-urls)"
trap 'rm -rf "${TMP}"' EXIT
fail=0

check() {
  local name="$1"
  local url="$2"
  local marker="${3:-}"
  local safe
  safe="$(printf '%s' "${name}" | tr -cd '[:alnum:]')"
  local out="${TMP}/${safe}.html"
  local code

  code="$(curl -L --max-time 20 -sS -o "${out}" -w '%{http_code}' "${url}" 2>/dev/null || echo '000')"
  if [[ "${code}" != "200" ]]; then
    echo "❌ ${name}: HTTP ${code}  ${url}"
    fail=1
    return
  fi

  if [[ -n "${marker}" ]] && ! grep -q "${marker}" "${out}"; then
    echo "⚠️  ${name}: 200，但未找到「${marker}」  ${url}"
    fail=1
    return
  fi

  echo "✅ ${name}: 200  ${url}"
}

echo "检查基址：${BASE}"
check "首页" "${BASE}/" "Citro"
check "支持页" "${BASE}/support.html" "Citro 支持"
check "隐私政策" "${BASE}/privacy.html" "隐私政策"
check "用户协议" "${BASE}/terms.html" "用户协议"
check "账号注销" "${BASE}/account-deletion.html" "账号注销"
check "后端帖子接口" "${BASE}/trashapi/api/posts" ""

if [[ "${fail}" -ne 0 ]]; then
  echo
  echo "有检查未通过。先修复再提交 App Store。"
fi
exit "${fail}"
