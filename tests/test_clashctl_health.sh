#!/usr/bin/env bash
# tests/test_clashctl_health.sh — Tests for hijack detection logic in _clash_health / _clash_metrics
# We test the grep-based hijack detection patterns against synthetic runtime.yaml files.
# No running mihomo needed — we only test the config-file scanning portions.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

_tmpdir=""
_setup() { _tmpdir="$(mktemp -d)"; }
_teardown() { [[ -n "$_tmpdir" ]] && rm -rf "$_tmpdir"; _tmpdir=""; }

# Replicate the exact hijack detection pattern from clashctl.sh _clash_health (line ~1089)
_detect_hijack() {
  local file="$1"
  grep -E 'IP-CIDR,(1\.1\.1\.1|8\.8\.8\.8)/32,[^,]+,no-resolve' "$file" | grep -v ',DIRECT,' >/dev/null && echo "risk" || echo "clean"
}

# Replicate DIRECT rule detection
_detect_direct() {
  local file="$1" ip="$2"
  grep -q "IP-CIDR,${ip}/32,DIRECT" "$file" && echo "ok" || echo "miss"
}

# ── Test 1: Clean config → no hijack ──
test_health_clean_config() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
rules:
  - IP-CIDR,1.1.1.1/32,DIRECT,no-resolve
  - IP-CIDR,8.8.8.8/32,DIRECT,no-resolve
  - MATCH,DIRECT
EOF
  local result; result=$(_detect_hijack "$_tmpdir/runtime.yaml")
  assert_eq "clean" "$result" "Clean config: hijack=clean"
  _teardown
}

# ── Test 2: Config with non-DIRECT hijack → risk ──
test_health_hijack_detected() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
rules:
  - IP-CIDR,1.1.1.1/32,SomeProxy,no-resolve
  - IP-CIDR,8.8.8.8/32,DIRECT,no-resolve
  - MATCH,DIRECT
EOF
  local result; result=$(_detect_hijack "$_tmpdir/runtime.yaml")
  assert_eq "risk" "$result" "SomeProxy hijack: detected as risk"
  _teardown
}

# ── Test 3: 西瓜加速 hijack → risk ──
test_health_xigua_hijack() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
rules:
  - IP-CIDR,8.8.8.8/32,西瓜加速,no-resolve
  - MATCH,DIRECT
EOF
  local result; result=$(_detect_hijack "$_tmpdir/runtime.yaml")
  assert_eq "risk" "$result" "西瓜加速 hijack: detected as risk"
  _teardown
}

# ── Test 4: DIRECT-only rules → clean (not false positive) ──
test_health_direct_only_clean() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
rules:
  - IP-CIDR,1.1.1.1/32,DIRECT,no-resolve
  - IP-CIDR,8.8.8.8/32,DIRECT,no-resolve
  - DOMAIN,example.com,PROXY
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF
  local result; result=$(_detect_hijack "$_tmpdir/runtime.yaml")
  assert_eq "clean" "$result" "DIRECT+PROXY rules: correctly clean (no false positive)"
  _teardown
}

# ── Test 5: DIRECT rules present → ok ──
test_health_direct_present() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
rules:
  - IP-CIDR,1.1.1.1/32,DIRECT,no-resolve
  - IP-CIDR,8.8.8.8/32,DIRECT,no-resolve
EOF
  assert_eq "ok" "$(_detect_direct "$_tmpdir/runtime.yaml" "1.1.1.1")" "DIRECT 1.1.1.1: ok"
  assert_eq "ok" "$(_detect_direct "$_tmpdir/runtime.yaml" "8.8.8.8")" "DIRECT 8.8.8.8: ok"
  _teardown
}

# ── Test 6: Missing DIRECT rules → miss ──
test_health_direct_missing() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
rules:
  - MATCH,DIRECT
EOF
  assert_eq "miss" "$(_detect_direct "$_tmpdir/runtime.yaml" "1.1.1.1")" "Missing DIRECT 1.1.1.1: miss"
  assert_eq "miss" "$(_detect_direct "$_tmpdir/runtime.yaml" "8.8.8.8")" "Missing DIRECT 8.8.8.8: miss"
  _teardown
}

# ── Test 7: Mixed — hijack + DIRECT both present ──
test_health_mixed_hijack_and_direct() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
rules:
  - IP-CIDR,1.1.1.1/32,DIRECT,no-resolve
  - IP-CIDR,1.1.1.1/32,EvilProxy,no-resolve
  - IP-CIDR,8.8.8.8/32,DIRECT,no-resolve
EOF
  local result; result=$(_detect_hijack "$_tmpdir/runtime.yaml")
  assert_eq "risk" "$result" "DIRECT + hijack coexist: still risk"
  assert_eq "ok" "$(_detect_direct "$_tmpdir/runtime.yaml" "1.1.1.1")" "DIRECT still detected alongside hijack"
  _teardown
}

# ── Test 8: Score model — full health 100 ──
test_health_score_perfect() {
  local score=100 direct1=ok direct8=ok hijack=clean fails=0
  [ "$direct1" = miss ] && score=$((score-25))
  [ "$direct8" = miss ] && score=$((score-25))
  [ "$hijack" = risk ] && score=$((score-30))
  if [ "$fails" -gt 20 ]; then score=$((score-20))
  elif [ "$fails" -gt 5 ]; then score=$((score-10)); fi

  assert_eq "100" "$score" "Perfect: score=100"
}

# ── Test 9: Score model — missing both DIRECT = 50 ──
test_health_score_missing_both_direct() {
  local score=100 direct1=miss direct8=miss hijack=clean fails=0
  [ "$direct1" = miss ] && score=$((score-25))
  [ "$direct8" = miss ] && score=$((score-25))
  [ "$hijack" = risk ] && score=$((score-30))
  if [ "$fails" -gt 20 ]; then score=$((score-20))
  elif [ "$fails" -gt 5 ]; then score=$((score-10)); fi

  assert_eq "50" "$score" "Missing both DIRECT: score=50"
}

# ── Test 10: Score model — hijack detected = 70 ──
test_health_score_hijack() {
  local score=100 direct1=ok direct8=ok hijack=risk fails=0
  [ "$direct1" = miss ] && score=$((score-25))
  [ "$direct8" = miss ] && score=$((score-25))
  [ "$hijack" = risk ] && score=$((score-30))
  if [ "$fails" -gt 20 ]; then score=$((score-20))
  elif [ "$fails" -gt 5 ]; then score=$((score-10)); fi

  assert_eq "70" "$score" "Hijack detected: score=70"
}

# ── Test 11: Score model — worst case = 0 ──
test_health_score_worst() {
  local score=100 direct1=miss direct8=miss hijack=risk fails=25
  [ "$direct1" = miss ] && score=$((score-25))
  [ "$direct8" = miss ] && score=$((score-25))
  [ "$hijack" = risk ] && score=$((score-30))
  if [ "$fails" -gt 20 ]; then score=$((score-20))
  elif [ "$fails" -gt 5 ]; then score=$((score-10)); fi

  assert_eq "0" "$score" "Worst case: score=0"
}
