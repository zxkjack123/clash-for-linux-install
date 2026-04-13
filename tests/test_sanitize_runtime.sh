#!/usr/bin/env bash
# tests/test_sanitize_runtime.sh — Tests for script/sanitize_runtime.sh
# This file is sourced by run_tests.sh; it may also be run standalone.
#
# Strategy: run sanitize_runtime.sh against static YAML testdata in a temp dir,
# then inspect the resulting file with yq. No mihomo required.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
YQ_BIN="${BIN_YQ:-$HOME/.local/share/clash/bin/yq}"
SANITIZE="$ROOT_DIR/script/sanitize_runtime.sh"

_tmpdir=""
_setup() {
  _tmpdir="$(mktemp -d)"
}
_teardown() {
  [[ -n "$_tmpdir" ]] && rm -rf "$_tmpdir"
  _tmpdir=""
}

# ── Test 1: Scholar routing picks ACADEMIC when it exists ──
test_scholar_picks_academic() {
  _setup
  cp "$TESTS_DIR/testdata/config_minimal.yaml" "$_tmpdir/runtime.yaml"

  CLASH_CONFIG_RUNTIME="$_tmpdir/runtime.yaml" \
  BIN_YQ="$YQ_BIN" \
  BIN_KERNEL_NAME="mihomo" \
    bash "$SANITIZE" --file "$_tmpdir/runtime.yaml" 2>/dev/null

  local scholar_rule
  scholar_rule=$("$YQ_BIN" -r '.rules[] | select(test("scholar\\.google\\.com"))' "$_tmpdir/runtime.yaml" 2>/dev/null || echo "")

  assert_contains "$scholar_rule" "ACADEMIC" "Scholar rule targets ACADEMIC when group exists"
  assert_contains "$scholar_rule" "scholar.google.com" "Scholar rule contains scholar.google.com"
  _teardown
}

# ── Test 2: Scholar routing falls back to AUTO when no ACADEMIC ──
test_scholar_fallback_auto() {
  _setup
  cp "$TESTS_DIR/testdata/config_proxy_only.yaml" "$_tmpdir/runtime.yaml"

  CLASH_CONFIG_RUNTIME="$_tmpdir/runtime.yaml" \
  BIN_YQ="$YQ_BIN" \
  BIN_KERNEL_NAME="mihomo" \
    bash "$SANITIZE" --file "$_tmpdir/runtime.yaml" 2>/dev/null

  local scholar_rule
  scholar_rule=$("$YQ_BIN" -r '.rules[] | select(test("scholar\\.google\\.com"))' "$_tmpdir/runtime.yaml" 2>/dev/null || echo "")

  assert_contains "$scholar_rule" "AUTO" "Scholar rule falls back to AUTO when no ACADEMIC"
  _teardown
}

# ── Test 3: Copilot routing picks COPILOT group ──
test_copilot_picks_copilot_group() {
  _setup
  cp "$TESTS_DIR/testdata/config_minimal.yaml" "$_tmpdir/runtime.yaml"

  CLASH_CONFIG_RUNTIME="$_tmpdir/runtime.yaml" \
  BIN_YQ="$YQ_BIN" \
  BIN_KERNEL_NAME="mihomo" \
    bash "$SANITIZE" --file "$_tmpdir/runtime.yaml" 2>/dev/null

  local copilot_rule
  copilot_rule=$("$YQ_BIN" -r '[.rules[] | select(test("githubcopilot\\.com"))] | .[0]' "$_tmpdir/runtime.yaml" 2>/dev/null || echo "")

  assert_contains "$copilot_rule" "COPILOT" "Copilot rule targets COPILOT when group exists"
  _teardown
}

# ── Test 4: Copilot defaults to DIRECT when no COPILOT group ──
test_copilot_fallback_direct() {
  _setup
  cp "$TESTS_DIR/testdata/config_proxy_only.yaml" "$_tmpdir/runtime.yaml"

  CLASH_CONFIG_RUNTIME="$_tmpdir/runtime.yaml" \
  BIN_YQ="$YQ_BIN" \
  BIN_KERNEL_NAME="mihomo" \
    bash "$SANITIZE" --file "$_tmpdir/runtime.yaml" 2>/dev/null

  local copilot_rule
  copilot_rule=$("$YQ_BIN" -r '[.rules[] | select(test("githubcopilot\\.com"))] | .[0]' "$_tmpdir/runtime.yaml" 2>/dev/null || echo "")

  assert_contains "$copilot_rule" "DIRECT" "Copilot rule defaults to DIRECT when no COPILOT group"
  _teardown
}

# ── Test 5: DIRECT rules for 1.1.1.1/8.8.8.8 are injected ──
test_direct_dns_rules_injected() {
  _setup
  cp "$TESTS_DIR/testdata/config_minimal.yaml" "$_tmpdir/runtime.yaml"

  CLASH_CONFIG_RUNTIME="$_tmpdir/runtime.yaml" \
  BIN_YQ="$YQ_BIN" \
  BIN_KERNEL_NAME="mihomo" \
    bash "$SANITIZE" --file "$_tmpdir/runtime.yaml" 2>/dev/null

  local rules
  rules=$("$YQ_BIN" -r '.rules[]' "$_tmpdir/runtime.yaml" 2>/dev/null)

  assert_contains "$rules" "IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" "DNS 1.1.1.1 DIRECT rule injected"
  assert_contains "$rules" "IP-CIDR,8.8.8.8/32,DIRECT,no-resolve" "DNS 8.8.8.8 DIRECT rule injected"
  _teardown
}

# ── Test 6: No-groups config doesn't crash and stays safe ──
test_no_groups_safe() {
  _setup
  cp "$TESTS_DIR/testdata/config_no_groups.yaml" "$_tmpdir/runtime.yaml"

  CLASH_CONFIG_RUNTIME="$_tmpdir/runtime.yaml" \
  BIN_YQ="$YQ_BIN" \
  BIN_KERNEL_NAME="mihomo" \
    bash "$SANITIZE" --file "$_tmpdir/runtime.yaml" 2>/dev/null

  # Scholar rule should NOT be injected (no valid target group)
  local scholar_rule
  scholar_rule=$("$YQ_BIN" -r '.rules[] | select(test("scholar\\.google\\.com"))' "$_tmpdir/runtime.yaml" 2>/dev/null || echo "")

  assert_eq "" "$scholar_rule" "No Scholar rule injected when no proxy-groups exist"

  # DIRECT DNS rules should still be present (they don't need a proxy group)
  local rules
  rules=$("$YQ_BIN" -r '.rules[]' "$_tmpdir/runtime.yaml" 2>/dev/null)
  assert_contains "$rules" "IP-CIDR,1.1.1.1/32,DIRECT" "DNS 1.1.1.1 DIRECT still injected with no groups"
  _teardown
}
