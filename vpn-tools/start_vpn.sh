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
if clashon >/dev/null 2>&1; then
  echo "[start_vpn] ✅ Started and system proxy applied"
else
  echo "[start_vpn] ⚠️ Start reported issues (see journalctl --user -u ${BIN_KERNEL_NAME})"
fi

# Show controller health
rt="$HOME/.local/share/clash/runtime.yaml"
if [ -f "$rt" ]; then
  # Extract port digits from external-controller: ':PORT'
  port=$(awk '/^external-controller:/ {gsub(/[^0-9]/,""); print}' "$rt")
  [ -z "$port" ] && port=9090
  ver=$(curl -sS --connect-timeout 2 "http://127.0.0.1:${port}/version" || true)
  echo "[start_vpn] Controller: http://127.0.0.1:${port} ${ver:+OK} ${ver:-UNREACHABLE}"
fi

echo "[start_vpn] Done. Use vpn-tools/stop_vpn.sh to stop and clean."
