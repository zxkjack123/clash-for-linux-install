#!/usr/bin/env bash
# tests/test_common_ports.sh — Tests for _get_proxy_port / _get_ui_port in common.sh
# These functions read port config from runtime.yaml via yq. We test them by
# creating minimal YAML files and running the functions in a controlled subshell.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
YQ_BIN="${BIN_YQ:-$HOME/.local/share/clash/bin/yq}"

_tmpdir=""
_setup() {
  _tmpdir="$(mktemp -d)"
}
_teardown() {
  [[ -n "$_tmpdir" ]] && rm -rf "$_tmpdir"
  _tmpdir=""
}

# Run _get_proxy_port in a subshell that sources common.sh with stubs.
# Outputs: MIXED_PORT SOCKS_PORT RC (space-separated)
_run_get_proxy_port() {
  local yaml="$1"
  (
    cd "$ROOT_DIR"
    # Pre-set globals common.sh expects
    export CLASH_LIB_MODE=1
    BIN_YQ="$YQ_BIN"
    BIN_KERNEL_NAME="mihomo"
    BIN_KERNEL="$HOME/.local/share/clash/bin/mihomo"
    # Stub functions to avoid side effects
    _is_already_in_use() { return 1; }
    _okcat() { :; }
    _failcat() { :; }
    _clash_port_policy() { echo "permissive"; }
    _get_random_port() { echo "19999"; }
    _port_conflict_report() { :; }
    # Source common.sh (it overwrites CLASH_CONFIG_RUNTIME) then re-set it
    source script/common.sh 2>/dev/null || true
    CLASH_CONFIG_RUNTIME="$yaml"
    local rc=0
    _get_proxy_port || rc=$?
    echo "${MIXED_PORT:-}|${SOCKS_PORT:-}|${rc}"
  ) 2>/dev/null | tail -1
}

# Run _get_ui_port similarly.
_run_get_ui_port() {
  local yaml="$1"
  (
    cd "$ROOT_DIR"
    export CLASH_LIB_MODE=1
    BIN_YQ="$YQ_BIN"
    BIN_KERNEL_NAME="mihomo"
    BIN_KERNEL="$HOME/.local/share/clash/bin/mihomo"
    _is_already_in_use() { return 1; }
    _okcat() { :; }
    _failcat() { :; }
    _clash_port_policy() { echo "permissive"; }
    _get_random_port() { echo "19999"; }
    _port_conflict_report() { :; }
    source script/common.sh 2>/dev/null || true
    CLASH_CONFIG_RUNTIME="$yaml"
    local rc=0
    _get_ui_port || rc=$?
    echo "${UI_PORT:-}|${rc}"
  ) 2>/dev/null | tail -1
}

# ── Test 1: mixed-port is detected ──
test_mixed_port_detected() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
mixed-port: 7890
EOF
  local out; out=$(_run_get_proxy_port "$_tmpdir/runtime.yaml")
  local mp sp rc
  mp=$(echo "$out" | cut -d'|' -f1)
  sp=$(echo "$out" | cut -d'|' -f2)
  rc=$(echo "$out" | cut -d'|' -f3)

  assert_eq "7890" "$mp" "mixed-port: MIXED_PORT=7890"
  assert_eq "7890" "$sp" "mixed-port: SOCKS_PORT=7890 (same as mixed)"
  assert_eq "0" "$rc" "mixed-port: return code 0"
  _teardown
}

# ── Test 2: split port + socks-port ──
test_split_port_detected() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
port: 7890
socks-port: 7891
EOF
  local out; out=$(_run_get_proxy_port "$_tmpdir/runtime.yaml")
  local mp sp
  mp=$(echo "$out" | cut -d'|' -f1)
  sp=$(echo "$out" | cut -d'|' -f2)

  assert_eq "7890" "$mp" "split: MIXED_PORT=7890 from port"
  assert_eq "7891" "$sp" "split: SOCKS_PORT=7891"
  _teardown
}

# ── Test 3: missing port falls back to 7890 ──
test_missing_port_defaults() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
rules: []
EOF
  local out; out=$(_run_get_proxy_port "$_tmpdir/runtime.yaml")
  local mp sp
  mp=$(echo "$out" | cut -d'|' -f1)
  sp=$(echo "$out" | cut -d'|' -f2)

  assert_eq "7890" "$mp" "missing port: defaults to 7890"
  assert_eq "" "$sp" "missing port: SOCKS_PORT empty"
  _teardown
}

# ── Test 4: external-controller detected by _get_ui_port ──
test_ui_port_detected() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
external-controller: 127.0.0.1:9090
EOF
  local out; out=$(_run_get_ui_port "$_tmpdir/runtime.yaml")
  local port rc
  port=$(echo "$out" | cut -d'|' -f1)
  rc=$(echo "$out" | cut -d'|' -f2)

  assert_eq "9090" "$port" "UI port: 9090"
  assert_eq "0" "$rc" "UI port: return code 0"
  _teardown
}

# ── Test 5: custom UI port ──
test_ui_port_custom() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
external-controller: 0.0.0.0:19090
EOF
  local out; out=$(_run_get_ui_port "$_tmpdir/runtime.yaml")
  local port
  port=$(echo "$out" | cut -d'|' -f1)

  assert_eq "19090" "$port" "UI port: custom 19090"
  _teardown
}

# ── Test 6: missing external-controller defaults to 9090 ──
test_ui_port_default() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
rules: []
EOF
  local out; out=$(_run_get_ui_port "$_tmpdir/runtime.yaml")
  local port
  port=$(echo "$out" | cut -d'|' -f1)

  assert_eq "9090" "$port" "UI port: default 9090 when missing"
  _teardown
}

# ── Test 7: mixed-port with non-numeric value falls through to port ──
test_mixed_port_nonnumeric() {
  _setup
  cat > "$_tmpdir/runtime.yaml" <<'EOF'
mixed-port: ""
port: 8080
EOF
  local out; out=$(_run_get_proxy_port "$_tmpdir/runtime.yaml")
  local mp
  mp=$(echo "$out" | cut -d'|' -f1)

  assert_eq "8080" "$mp" "non-numeric mixed-port: falls to port=8080"
  _teardown
}
