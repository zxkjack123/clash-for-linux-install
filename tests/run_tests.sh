#!/usr/bin/env bash
# Simple test runner for clash-for-linux-install
# Usage: bash tests/run_tests.sh
#
# No external dependencies required (no bats, no shunit2).
# Each test file should define functions named test_* and call run_tests at the end.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

_pass=0; _fail=0; _total=0

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  _total=$((_total+1))
  if [[ "$expected" == "$actual" ]]; then
    _pass=$((_pass+1))
    printf "  ${GREEN}PASS${NC} %s\n" "$msg"
  else
    _fail=$((_fail+1))
    printf "  ${RED}FAIL${NC} %s\n    expected: %s\n    actual:   %s\n" "$msg" "$expected" "$actual"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  _total=$((_total+1))
  if [[ "$haystack" == *"$needle"* ]]; then
    _pass=$((_pass+1))
    printf "  ${GREEN}PASS${NC} %s\n" "$msg"
  else
    _fail=$((_fail+1))
    printf "  ${RED}FAIL${NC} %s\n    expected to contain: %s\n    actual: %s\n" "$msg" "$needle" "${haystack:0:200}"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  _total=$((_total+1))
  if [[ "$haystack" != *"$needle"* ]]; then
    _pass=$((_pass+1))
    printf "  ${GREEN}PASS${NC} %s\n" "$msg"
  else
    _fail=$((_fail+1))
    printf "  ${RED}FAIL${NC} %s\n    expected NOT to contain: %s\n" "$msg" "$needle"
  fi
}

# Run all test_* functions found in test files
run_test_files() {
  local test_files=("$TESTS_DIR"/test_*.sh)
  if [[ ${#test_files[@]} -eq 0 ]]; then
    echo "No test files found in $TESTS_DIR"
    exit 1
  fi

  for tf in "${test_files[@]}"; do
    echo ""
    echo "=== $(basename "$tf") ==="
    # Source the test file (it defines test_* functions)
    source "$tf"
    # Find and run all test_* functions
    local funcs
    funcs=$(declare -F | awk '{print $3}' | grep '^test_' || true)
    for fn in $funcs; do
      echo "--- $fn ---"
      "$fn"
      # Unset the function to avoid re-running across files
      unset -f "$fn"
    done
  done

  echo ""
  echo "==============================="
  printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, %d total\n" "$_pass" "$_fail" "$_total"
  if [[ $_fail -gt 0 ]]; then
    exit 1
  fi
}

run_test_files
