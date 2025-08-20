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

UNIT_DIR="$HOME/.config/systemd/user"
ORIG_UNIT="$UNIT_DIR/clash-proxy-env.service"
BACKUP_UNIT="$UNIT_DIR/clash-proxy-env.service.bak"

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

echo "[harden] Enabling + starting (idempotent)." >&2
systemctl --user enable --now clash-proxy-env.service

echo "Done. To revert: cp $BACKUP_UNIT $ORIG_UNIT && systemctl --user daemon-reload && systemctl --user restart clash-proxy-env.service" >&2
