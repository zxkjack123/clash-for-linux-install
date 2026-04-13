#!/usr/bin/env bash
# tests/test_deprecation_guards.sh — Tests for deprecation guards on obsolete scripts
# Verifies that deprecated scripts exit 1 with warning unless FORCE_LEGACY=1.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

# ── Test 1: auto_optimize_clash.sh exits 1 without FORCE_LEGACY ──
test_auto_optimize_deprecated() {
  local rc=0 output
  output=$(bash "$ROOT_DIR/script/auto_optimize_clash.sh" 2>&1) || rc=$?
  assert_eq "1" "$rc" "auto_optimize_clash.sh: exit 1 without FORCE_LEGACY"
  assert_contains "$output" "弃用" "auto_optimize_clash.sh: deprecation message shown"
}

# ── Test 2: auto_optimize_clash.sh syntax valid with FORCE_LEGACY ──
test_auto_optimize_syntax_with_force() {
  local rc=0
  bash -n "$ROOT_DIR/script/auto_optimize_clash.sh" || rc=$?
  assert_eq "0" "$rc" "auto_optimize_clash.sh: bash -n passes"
}

# ── Test 3: use_jp_tailscale_only.sh exits 1 without FORCE_LEGACY ──
test_use_jp_tailscale_deprecated() {
  local rc=0 output
  output=$(bash "$ROOT_DIR/vpn-tools/use_jp_tailscale_only.sh" 2>&1) || rc=$?
  assert_eq "1" "$rc" "use_jp_tailscale_only.sh: exit 1 without FORCE_LEGACY"
  assert_contains "$output" "弃用" "use_jp_tailscale_only.sh: deprecation message shown"
}

# ── Test 4: use_jp_tailscale_only.sh syntax valid ──
test_use_jp_tailscale_syntax() {
  local rc=0
  bash -n "$ROOT_DIR/vpn-tools/use_jp_tailscale_only.sh" || rc=$?
  assert_eq "0" "$rc" "use_jp_tailscale_only.sh: bash -n passes"
}

# ── Test 5: jp_tailscale_single_node_test --apply-tighten shows deprecation ──
test_apply_tighten_deprecated() {
  # The script needs mihomo running, so we can't fully run it.
  # But we can grep for the deprecation guard pattern.
  local match
  match=$(grep -c 'DEPRECATED.*AUTO-SMART.*no longer exists' "$ROOT_DIR/vpn-tools/jp_tailscale_single_node_test.sh" || true)
  assert_eq "1" "$match" "jp_tailscale_single_node_test.sh: --apply-tighten deprecation guard present"
}
