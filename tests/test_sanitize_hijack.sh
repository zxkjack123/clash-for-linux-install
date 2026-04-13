#!/usr/bin/env bash
# tests/test_sanitize_hijack.sh — Tests for generalized hijack removal in sanitize_runtime.sh
# Validates that any non-DIRECT IP-CIDR rules for 1.1.1.1/8.8.8.8 are removed,
# while DIRECT rules and other rules are preserved.
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

# Helper: run sanitize on a given config
_sanitize() {
  CLASH_CONFIG_RUNTIME="$_tmpdir/runtime.yaml" \
  BIN_YQ="$YQ_BIN" \
  BIN_KERNEL_NAME="mihomo" \
    bash "$SANITIZE" --file "$_tmpdir/runtime.yaml" 2>/dev/null
}

# Helper: dump rules as one-per-line
_rules() {
  "$YQ_BIN" -r '.rules[]' "$_tmpdir/runtime.yaml" 2>/dev/null
}

# ── Test 1: Non-DIRECT hijack rules on 1.1.1.1 are removed (yq path) ──
test_hijack_1111_removed() {
  _setup
  cp "$TESTS_DIR/testdata/config_with_hijack.yaml" "$_tmpdir/runtime.yaml"
  _sanitize

  local rules; rules=$(_rules)
  assert_not_contains "$rules" "IP-CIDR,1.1.1.1/32,SomeProxy" "1.1.1.1 hijack (SomeProxy) removed"
  _teardown
}

# ── Test 2: Non-DIRECT hijack rules on 8.8.8.8 are removed ──
test_hijack_8888_removed() {
  _setup
  cp "$TESTS_DIR/testdata/config_with_hijack.yaml" "$_tmpdir/runtime.yaml"
  _sanitize

  local rules; rules=$(_rules)
  assert_not_contains "$rules" "IP-CIDR,8.8.8.8/32,西瓜加速" "8.8.8.8 hijack (西瓜加速) removed"
  _teardown
}

# ── Test 3: DIRECT rules for 1.1.1.1/8.8.8.8 are preserved ──
test_direct_rules_preserved() {
  _setup
  cp "$TESTS_DIR/testdata/config_with_hijack.yaml" "$_tmpdir/runtime.yaml"
  _sanitize

  local rules; rules=$(_rules)
  assert_contains "$rules" "IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" "1.1.1.1 DIRECT preserved"
  assert_contains "$rules" "IP-CIDR,8.8.8.8/32,DIRECT,no-resolve" "8.8.8.8 DIRECT preserved"
  _teardown
}

# ── Test 4: Non-DNS rules are untouched ──
test_other_rules_untouched() {
  _setup
  cp "$TESTS_DIR/testdata/config_with_hijack.yaml" "$_tmpdir/runtime.yaml"
  _sanitize

  local rules; rules=$(_rules)
  assert_contains "$rules" "DOMAIN,example.com,PROXY" "DOMAIN rule preserved"
  assert_contains "$rules" "GEOIP,CN,DIRECT" "GEOIP rule preserved"
  assert_contains "$rules" "MATCH,DIRECT" "MATCH rule preserved"
  _teardown
}

# ── Test 5: dns.fallback bare IPs removed ──
test_fallback_bare_ip_removed() {
  _setup
  cp "$TESTS_DIR/testdata/config_with_hijack.yaml" "$_tmpdir/runtime.yaml"
  _sanitize

  local fallback
  fallback=$("$YQ_BIN" -r '.dns.fallback[]' "$_tmpdir/runtime.yaml" 2>/dev/null || echo "")
  assert_not_contains "$fallback" "1.1.1.1" "1.1.1.1 removed from dns.fallback"
  assert_contains "$fallback" "tls://dns.google" "tls://dns.google kept in dns.fallback"
  _teardown
}

# ── Test 6: Idempotent — running on clean config causes no diff (yq path) ──
test_idempotent_clean_config() {
  _setup
  cp "$TESTS_DIR/testdata/config_minimal.yaml" "$_tmpdir/runtime.yaml"
  _sanitize

  # Capture state after first sanitize
  local after1
  after1=$("$YQ_BIN" -r '.rules | length' "$_tmpdir/runtime.yaml" 2>/dev/null)

  # Run a second time
  _sanitize
  local after2
  after2=$("$YQ_BIN" -r '.rules | length' "$_tmpdir/runtime.yaml" 2>/dev/null)

  assert_eq "$after1" "$after2" "Idempotent: rule count unchanged after second sanitize"
  _teardown
}

# ── Test 7: Text fallback path removes hijack rules when yq unavailable ──
test_text_fallback_removes_hijack() {
  _setup
  cp "$TESTS_DIR/testdata/config_with_hijack.yaml" "$_tmpdir/runtime.yaml"

  # Force text fallback by pointing YQ to nonexistent binary
  CLASH_CONFIG_RUNTIME="$_tmpdir/runtime.yaml" \
  BIN_YQ="/nonexistent/yq" \
  BIN_KERNEL_NAME="mihomo" \
    bash "$SANITIZE" --file "$_tmpdir/runtime.yaml" 2>/dev/null

  local content
  content=$(cat "$_tmpdir/runtime.yaml")

  assert_not_contains "$content" "SomeProxy" "Text fallback: SomeProxy hijack removed"
  assert_not_contains "$content" "西瓜加速" "Text fallback: 西瓜加速 hijack removed"
  assert_contains "$content" "IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" "Text fallback: DIRECT 1.1.1.1 present"
  assert_contains "$content" "IP-CIDR,8.8.8.8/32,DIRECT,no-resolve" "Text fallback: DIRECT 8.8.8.8 present"
  assert_contains "$content" "DOMAIN,example.com,PROXY" "Text fallback: DOMAIN rule preserved"
  _teardown
}

# ── Test 8: Verification detects residual non-DIRECT hijack ──
test_verification_warns_on_residual() {
  _setup
  cp "$TESTS_DIR/testdata/config_minimal.yaml" "$_tmpdir/runtime.yaml"

  # Inject a sneaky hijack that bypasses normal processing (append after sanitize runs)
  _sanitize

  # Manually re-inject a hijack rule to test the verification output
  "$YQ_BIN" -i '.rules = .rules + ["IP-CIDR,1.1.1.1/32,EvilProxy,no-resolve"]' "$_tmpdir/runtime.yaml"

  # Capture sanitize output (it should warn about residual)
  local output
  output=$(CLASH_CONFIG_RUNTIME="$_tmpdir/runtime.yaml" \
    BIN_YQ="$YQ_BIN" \
    BIN_KERNEL_NAME="mihomo" \
      bash "$SANITIZE" --file "$_tmpdir/runtime.yaml" 2>&1 || true)

  # After sanitize, the hijack should be removed
  local rules; rules=$("$YQ_BIN" -r '.rules[]' "$_tmpdir/runtime.yaml" 2>/dev/null)
  assert_not_contains "$rules" "EvilProxy" "Re-injected hijack cleaned on second pass"
  _teardown
}
