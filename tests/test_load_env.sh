#!/usr/bin/env bash
# tests/test_load_env.sh — Tests for utility functions in vpn-tools/load_env.sh
# Tests clash_urlencode and other pure functions that don't need a running controller.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

# Source load_env.sh in a way that skips controller-dependent init.
# We only need the pure utility functions.
_source_load_env() {
  # Provide stubs for functions that load_env.sh may call during source
  CLASH_API="http://127.0.0.1:9090"
  CLASH_SECRET=""
  clash_have() { command -v "$1" >/dev/null 2>&1; }
  # Source it
  source "$ROOT_DIR/vpn-tools/load_env.sh" 2>/dev/null || true
}

_source_load_env

# ── Test 1: URL-encode simple ASCII ──
test_urlencode_ascii() {
  local result
  result=$(clash_urlencode "hello")
  assert_eq "hello" "$result" "urlencode: simple ASCII unchanged"
}

# ── Test 2: URL-encode spaces ──
test_urlencode_spaces() {
  local result
  result=$(clash_urlencode "hello world")
  assert_eq "hello%20world" "$result" "urlencode: space → %20"
}

# ── Test 3: URL-encode special characters ──
test_urlencode_special() {
  local result
  result=$(clash_urlencode "a/b?c=d&e")
  assert_contains "$result" "%2F" "urlencode: / encoded"
  assert_contains "$result" "%3F" "urlencode: ? encoded"
  assert_contains "$result" "%3D" "urlencode: = encoded"
  assert_contains "$result" "%26" "urlencode: & encoded"
}

# ── Test 4: URL-encode CJK characters (中文) ──
test_urlencode_cjk() {
  local result
  result=$(clash_urlencode "西瓜加速")
  # Should not contain raw CJK
  assert_not_contains "$result" "西" "urlencode: CJK encoded (no raw 西)"
  # Should contain percent-encoded bytes
  assert_contains "$result" "%" "urlencode: CJK produces percent sequences"
}

# ── Test 5: URL-encode empty string ──
test_urlencode_empty() {
  local result
  result=$(clash_urlencode "")
  assert_eq "" "$result" "urlencode: empty string → empty"
}

# ── Test 6: URL-encode preserves safe chars ──
test_urlencode_safe_chars() {
  local result
  result=$(clash_urlencode "a-b_c.d~e")
  assert_eq "a-b_c.d~e" "$result" "urlencode: safe chars (- _ . ~) preserved"
}

# ── Test 7: Round-trip encode/decode via python ──
test_urlencode_roundtrip() {
  if ! command -v python3 >/dev/null 2>&1; then
    # Skip if no python3
    assert_eq "1" "1" "urlencode roundtrip: SKIPPED (no python3)"
    return
  fi
  local original="AUTO-SMART/速云梯 (test)"
  local encoded decoded
  encoded=$(clash_urlencode "$original")
  decoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.unquote(sys.argv[1]))" "$encoded")
  assert_eq "$original" "$decoded" "urlencode: round-trip via python3 decode"
}
