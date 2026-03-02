#!/usr/bin/env bash
set -euo pipefail

# One-click stop: stop mihomo and fully unset system proxy with no residue
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export CLASH_LIB_MODE=1
# shellcheck source=/dev/null
. "$ROOT_DIR/script/common.sh" >/dev/null 2>&1 || true
# shellcheck source=/dev/null
. "$ROOT_DIR/script/clashctl.sh" >/dev/null 2>&1 || true

CLASH_BASE_DIR_EFFECTIVE="${CLASH_BASE_DIR:-$HOME/.local/share/clash}"
CLASH_STATE_DIR_EFFECTIVE="${CLASH_STATE_DIR:-${XDG_RUNTIME_DIR:-$CLASH_BASE_DIR_EFFECTIVE}}"
CLASH_APT_PROXY_STAGE_FILE_EFFECTIVE="${CLASH_APT_PROXY_STAGE_FILE:-${CLASH_STATE_DIR_EFFECTIVE}/95clash-proxy}"
CLASH_APT_PROXY_STAGE_FILE_LEGACY="${CLASH_APT_PROXY_STAGE_FILE_LEGACY:-/tmp/95clash-proxy}"
CLASH_PROXY_STATE_FILE_EFFECTIVE="${CLASH_PROXY_STATE_FILE:-${CLASH_STATE_DIR_EFFECTIVE}/.clash_system_proxy_state}"
CLASH_PROXY_STATE_FILE_LEGACY="/tmp/.clash_system_proxy_state"

echo "[stop_vpn] Stopping proxy service and removing system proxy..."
if type -t clashctl >/dev/null 2>&1; then
  if clashctl off >/dev/null 2>&1; then
    echo "[stop_vpn] ✅ Stopped and system proxy removed"
  else
    echo "[stop_vpn] ⚠️ Stop reported issues (service may already be stopped)"
  fi
elif type -t clashoff >/dev/null 2>&1; then
  if clashoff >/dev/null 2>&1; then
    echo "[stop_vpn] ✅ Stopped and system proxy removed"
  else
    echo "[stop_vpn] ⚠️ Stop reported issues (service may already be stopped)"
  fi
else
  echo "[stop_vpn] ❌ clashctl/clashoff not available. Try running via clashctl.sh or reinstall."
  exit 1
fi

# Verify no residue
residual=0
for v in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY; do
  if [ -n "${!v:-}" ]; then echo "[stop_vpn] ❌ Residual env var: $v is set"; residual=1; fi
done

if command -v gsettings >/dev/null 2>&1; then
  mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo none)
  if [ "$mode" != "'none'" ]; then echo "[stop_vpn] ❌ GNOME proxy mode is $mode"; residual=1; fi
fi

[ -f "$CLASH_APT_PROXY_STAGE_FILE_EFFECTIVE" ] && { echo "[stop_vpn] ❌ ${CLASH_APT_PROXY_STAGE_FILE_EFFECTIVE} exists"; residual=1; }
[ -f "$CLASH_APT_PROXY_STAGE_FILE_LEGACY" ] && { echo "[stop_vpn] ❌ ${CLASH_APT_PROXY_STAGE_FILE_LEGACY} exists"; residual=1; }
[ -f "$CLASH_PROXY_STATE_FILE_EFFECTIVE" ] && { echo "[stop_vpn] ❌ system proxy state exists: ${CLASH_PROXY_STATE_FILE_EFFECTIVE}"; residual=1; }
[ -f "$CLASH_PROXY_STATE_FILE_LEGACY" ] && { echo "[stop_vpn] ❌ legacy system proxy state exists: ${CLASH_PROXY_STATE_FILE_LEGACY}"; residual=1; }

if [ $residual -eq 0 ]; then
  echo "[stop_vpn] 🧹 Environment clean (no residual proxy settings)"
else
  echo "[stop_vpn] ⚠️ Residual items detected (see above). You can re-run or clear manually."
fi

echo "[stop_vpn] Done."
