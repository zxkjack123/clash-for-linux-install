#!/usr/bin/env bash
set -euo pipefail

# One-click stop: stop mihomo and fully unset system proxy with no residue
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export CLASH_LIB_MODE=1
# shellcheck source=/dev/null
. "$ROOT_DIR/script/common.sh" >/dev/null 2>&1 || true
# shellcheck source=/dev/null
. "$ROOT_DIR/script/clashctl.sh" >/dev/null 2>&1 || true

echo "[stop_vpn] Stopping proxy service and removing system proxy..."
if clashoff >/dev/null 2>&1; then
  echo "[stop_vpn] ✅ Stopped and system proxy removed"
else
  echo "[stop_vpn] ⚠️ Stop reported issues (service may already be stopped)"
fi

# Verify no residue
residual=0
for v in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; do
  if [ -n "${!v:-}" ]; then echo "[stop_vpn] ❌ Residual env var: $v=${!v}"; residual=1; fi
done

if command -v gsettings >/dev/null 2>&1; then
  mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo none)
  if [ "$mode" != "'none'" ]; then echo "[stop_vpn] ❌ GNOME proxy mode is $mode"; residual=1; fi
fi

[ -f /tmp/95clash-proxy ] && { echo "[stop_vpn] ❌ /tmp/95clash-proxy exists"; residual=1; }
[ -f /tmp/.clash_system_proxy_state ] && { echo "[stop_vpn] ❌ system proxy state exists"; residual=1; }

if [ $residual -eq 0 ]; then
  echo "[stop_vpn] 🧹 Environment clean (no residual proxy settings)"
else
  echo "[stop_vpn] ⚠️ Residual items detected (see above). You can re-run or clear manually."
fi

echo "[stop_vpn] Done."
