#!/usr/bin/env bash
# Purpose: Reduce browser NET::ERR_NETWORK_CHANGED churn caused by frequent
# start/stop cycles of clash-proxy-env.service which presently unsets and then
# immediately re-sets system proxy (GNOME gsettings / env vars) on each mihomo
# restart because the unit uses BindsTo= + ExecStop calling _unset_system_proxy.
#
# Strategy:
# 1. Install an improved user unit that:
#    - Uses PartOf=mihomo.service (no hard stop on kernel restart)
#    - Removes ExecStop (keeps proxy stable during kernel restarts)
#    - Runs _set_system_proxy once at login / manual enable
# 2. Preserve the original unit as a backup (~/.config/systemd/user/clash-proxy-env.service.bak)
# 3. Provide a manual disable command (clashproxy off) still available to unset.
#
# Safe: We retain idempotent guard already in _set_system_proxy (state file) so
# re-running causes no additional gsettings writes.

set -euo pipefail

DO_APPLY=0
DO_NOW=0

usage() {
  cat <<'EOF'
Install a more stable user unit for clash-proxy-env.service (safe by default)

By default this script runs in PREVIEW mode and makes no changes.

Options:
  --apply   Write/update the unit file and enable it
  --now     Start the unit immediately (requires --apply)
  -h,--help Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) DO_APPLY=1; shift ;;
    --now) DO_NOW=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[harden] Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [ "$DO_NOW" -eq 1 ] && [ "$DO_APPLY" -ne 1 ]; then
  echo "[harden] ERROR: --now requires --apply" >&2
  exit 2
fi

UNIT_DIR="$HOME/.config/systemd/user"
ORIG_UNIT="$UNIT_DIR/clash-proxy-env.service"
BACKUP_UNIT="$UNIT_DIR/clash-proxy-env.service.bak"

if [ "$DO_APPLY" -ne 1 ]; then
  echo "[harden] PREVIEW mode (no changes will be made)." >&2
  if [ -d "$UNIT_DIR" ]; then
    echo "[harden] OK: systemd user unit dir exists: $UNIT_DIR" >&2
  else
    echo "[harden] NOTE: systemd user unit dir does not exist yet: $UNIT_DIR" >&2
  fi
  if [ -f "$ORIG_UNIT" ]; then
    echo "[harden] OK: unit exists: $ORIG_UNIT" >&2
  else
    echo "[harden] WOULD create unit: $ORIG_UNIT" >&2
  fi
  if [ -f "$ORIG_UNIT" ] && [ ! -f "$BACKUP_UNIT" ]; then
    echo "[harden] WOULD create backup: $BACKUP_UNIT" >&2
  elif [ -f "$BACKUP_UNIT" ]; then
    echo "[harden] OK: backup exists: $BACKUP_UNIT" >&2
  fi
  echo "[harden] To apply: bash script/harden_proxy_env.sh --apply [--now]" >&2
  exit 0
fi

mkdir -p "$UNIT_DIR"
if [ -f "$ORIG_UNIT" ] && [ ! -f "$BACKUP_UNIT" ]; then
  cp "$ORIG_UNIT" "$BACKUP_UNIT"
fi

cat > "$ORIG_UNIT" <<'EOF'
[Unit]
Description=Clash Proxy Environment Setup (stable)
After=mihomo.service
PartOf=mihomo.service

[Service]
Type=oneshot
RemainAfterExit=yes
# Only apply (idempotent) – do NOT unset automatically on kernel restarts.
ExecStart=/bin/bash -c 'source $HOME/.local/share/clash/script/common.sh && source $HOME/.local/share/clash/script/clashctl.sh && _set_system_proxy'
# No ExecStop (manual: clashproxy off)
TimeoutStartSec=10

[Install]
WantedBy=default.target
EOF

echo "[harden] Installed improved clash-proxy-env.service (previous backed up to $BACKUP_UNIT if existed)." >&2
echo "[harden] Reloading systemd user daemon..." >&2
systemctl --user daemon-reload

if [ "$DO_NOW" -eq 1 ]; then
  echo "[harden] Enabling + starting (idempotent)." >&2
  systemctl --user enable --now clash-proxy-env.service
else
  echo "[harden] Enabling (not starting by default)." >&2
  systemctl --user enable clash-proxy-env.service
fi

echo "Done. To revert: cp $BACKUP_UNIT $ORIG_UNIT && systemctl --user daemon-reload && systemctl --user restart clash-proxy-env.service" >&2
