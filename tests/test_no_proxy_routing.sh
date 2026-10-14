#!/usr/bin/env bash
# tests/test_no_proxy_routing.sh — Regression guard for the "bypass local Clash" no_proxy list
# and the astral.sh PROXY routing (the deliberate opposite case).
#
# Static file checks only — no network access, no running mihomo required.
#
# Background (2026-10-14):
#   - api.deepseek.com / .deepseek.com  → DIRECT (国内可达; 绕开本地 Clash 一跳)
#   - www.smaragents.com / .smaragents.com → DIRECT (opencode sub2api 中转, 已直连)
#   - www.bing.com / cn.bing.com        → DIRECT (中国 CDN, 比代理快 6–20×)
#     ⚠️ 仅子域; 裸域 bing.com 直连超时, 必须留 PROXY
#   - astral.sh                          → **PROXY** (Cloudflare 国内直连极不稳定, 是 no_proxy 的反例)
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

CLASHCTL="$ROOT_DIR/script/clashctl.sh"
MIXIN="$ROOT_DIR/resources/mixin.yaml"

# Extract the no_proxy_addr literal from clashctl.sh (single source line).
_no_proxy_line() { grep -m1 'local no_proxy_addr=' "$CLASHCTL"; }

# ── Test 1: no_proxy includes DeepSeek (domestic-reachable AI API) ──
test_no_proxy_deepseek() {
  local line; line=$(_no_proxy_line)
  assert_contains "$line" "api.deepseek.com" "no_proxy includes api.deepseek.com"
  assert_contains "$line" ".deepseek.com" "no_proxy includes .deepseek.com suffix"
}

# ── Test 2: no_proxy includes smaragents (opencode sub2api / sub2api-demostic relay) ──
test_no_proxy_smaragents() {
  local line; line=$(_no_proxy_line)
  assert_contains "$line" "www.smaragents.com" "no_proxy includes www.smaragents.com"
  assert_contains "$line" ".smaragents.com" "no_proxy includes .smaragents.com suffix"
}

# ── Test 3: no_proxy includes bing CN CDN subdomains ONLY (not the apex) ──
test_no_proxy_bing_subdomains_only() {
  local line; line=$(_no_proxy_line)
  assert_contains "$line" "www.bing.com" "no_proxy includes www.bing.com"
  assert_contains "$line" "cn.bing.com" "no_proxy includes cn.bing.com"
  # Apex bing.com must NOT appear as a bare comma-entry (direct times out → needs PROXY).
  assert_not_contains "$line" ",bing.com" "no_proxy must NOT contain bare bing.com (apex blocked direct)"
}

# ── Test 4: astral.sh must NOT be in no_proxy (it is the deliberate PROXY case) ──
test_astral_not_in_no_proxy() {
  local line; line=$(_no_proxy_line)
  assert_not_contains "$line" "astral" "no_proxy must NOT contain astral.sh (direct unstable → needs PROXY)"
}

# ── Test 5: mixin routes astral.sh via PROXY ──
test_mixin_astral_proxy() {
  local r; r=$(grep -E 'DOMAIN-SUFFIX,astral\.sh,PROXY' "$MIXIN" || true)
  assert_contains "$r" "DOMAIN-SUFFIX,astral.sh,PROXY" "mixin routes astral.sh to PROXY"
}

# ── Test 6: GNOME ignore-hosts list also carries the new DIRECT-bypass hosts ──
test_gnome_ignore_hosts() {
  local block
  block=$(sed -n '/_gnome_build_ignore_hosts()/,/^}/p' "$CLASHCTL")
  assert_contains "$block" "api.deepseek.com" "gnome ignore-hosts includes deepseek"
  assert_contains "$block" "smaragents.com" "gnome ignore-hosts includes smaragents"
  assert_contains "$block" "www.bing.com" "gnome ignore-hosts includes www.bing.com"
}
