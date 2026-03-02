#!/usr/bin/env bash
set -euo pipefail

# One-click start: start mihomo and set system proxy safely
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export CLASH_LIB_MODE=1
# shellcheck source=/dev/null
. "$ROOT_DIR/script/common.sh" >/dev/null 2>&1 || true
# shellcheck source=/dev/null
. "$ROOT_DIR/script/clashctl.sh" >/dev/null 2>&1 || true

echo "[start_vpn] Starting proxy service and applying system proxy..."
if type -t clashctl >/dev/null 2>&1; then
  if clashctl on >/dev/null 2>&1; then
    echo "[start_vpn] ✅ Started and system proxy applied"
  else
    echo "[start_vpn] ⚠️ Start reported issues (see journalctl --user -u ${BIN_KERNEL_NAME:-mihomo.service})"
  fi
elif type -t clashon >/dev/null 2>&1; then
  if clashon >/dev/null 2>&1; then
    echo "[start_vpn] ✅ Started and system proxy applied"
  else
    echo "[start_vpn] ⚠️ Start reported issues (see journalctl --user -u ${BIN_KERNEL_NAME:-mihomo.service})"
  fi
else
  echo "[start_vpn] ❌ clashctl/clashon not available. Try running via clashctl.sh or reinstall."
  exit 1
fi

# Show controller health
rt="$HOME/.local/share/clash/runtime.yaml"
if [ -f "$rt" ]; then
  # Controller secret (optional)
  secret="${CLASH_SECRET:-}"
  YQ_BIN="${BIN_YQ:-$HOME/.local/share/clash/bin/yq}"
  if [ -z "$secret" ] && [ -x "$YQ_BIN" ]; then
    secret=$($YQ_BIN -r '.secret // ""' "$rt" 2>/dev/null || echo '')
    secret=$(printf '%s' "$secret" | tr -d "\"'")
  fi
  if [ -z "$secret" ]; then
    secret=$(awk -F': *' '/^secret:/ {print $2; exit}' "$rt" 2>/dev/null | tr -d "\"'" || true)
  fi
  auth_hdr=()
  [ -n "$secret" ] && auth_hdr=(-H "Authorization: Bearer $secret")

  # Extract port digits from external-controller: ':PORT'
  port=$(awk -F: '/^ *external-controller:/ {print $NF; exit}' "$rt" | tr -cd '0-9')
  [ -z "$port" ] && port=9090
  ver=$(curl -sS --noproxy '*' --connect-timeout 2 --max-time 4 ${auth_hdr[@]+"${auth_hdr[@]}"} "http://127.0.0.1:${port}/version" || true)
  echo "[start_vpn] Controller: http://127.0.0.1:${port} ${ver:+OK} ${ver:-UNREACHABLE}"
fi

echo "[start_vpn] Done. Use vpn-tools/stop_vpn.sh to stop and clean."
