#!/usr/bin/env bash
set -Eeuo pipefail

# Enable user-level systemd autostart for Clash/Mihomo at boot/login,
# without changing system-wide configs. Creates/refreshes user units if missing,
# enables them, and attempts to enable lingering so user services start on boot.

CLASH_HOME="$HOME/.local/share/clash"
SCRIPT_DIR="$CLASH_HOME/script"
UNIT_DIR="$HOME/.config/systemd/user"

# Load env helpers from installed location (temporarily relax nounset for upstream script)
if [ -f "$SCRIPT_DIR/common.sh" ]; then
  set +u
  # shellcheck disable=SC1090
  . "$SCRIPT_DIR/common.sh"
  # shellcheck disable=SC1090
  . "$SCRIPT_DIR/clashctl.sh"
  set -u
  # common.sh sets BIN_KERNEL_NAME, BIN_KERNEL, CLASH_CONFIG_RUNTIME, etc.
else
  echo "[enable-autostart] Could not find $SCRIPT_DIR/common.sh. Please run install.sh first." >&2
  exit 1
fi

mkdir -p "$UNIT_DIR"

KERNEL_UNIT_NAME="${BIN_KERNEL_NAME}.service"
KERNEL_UNIT_PATH="$UNIT_DIR/$KERNEL_UNIT_NAME"
PROXY_ENV_UNIT_PATH="$UNIT_DIR/clash-proxy-env.service"

# Ensure kernel unit exists (idempotent)
if [ ! -f "$KERNEL_UNIT_PATH" ]; then
  cat > "$KERNEL_UNIT_PATH" <<EOF
[Unit]
Description=$BIN_KERNEL_NAME Daemon, A[nother] Clash Kernel.
After=network.target

[Service]
Type=simple
Restart=always
ExecStart=${BIN_KERNEL} -d ${CLASH_BASE_DIR} -f ${CLASH_CONFIG_RUNTIME}
RestartSec=5
TimeoutStartSec=30

[Install]
WantedBy=default.target
EOF
  echo "[enable-autostart] Installed user unit: $KERNEL_UNIT_PATH"
fi

# Ensure proxy env unit exists (idempotent). Keep conservative behavior (ExecStop present)
if [ ! -f "$PROXY_ENV_UNIT_PATH" ]; then
  cat > "$PROXY_ENV_UNIT_PATH" <<'EOF'
[Unit]
Description=Clash Proxy Environment Setup
After=mihomo.service clash.service
BindsTo=mihomo.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -lc 'source $HOME/.local/share/clash/script/common.sh && source $HOME/.local/share/clash/script/clashctl.sh && _set_system_proxy'
ExecStop=/bin/bash -lc 'source $HOME/.local/share/clash/script/common.sh && source $HOME/.local/share/clash/script/clashctl.sh && _unset_system_proxy'
TimeoutStartSec=10

[Install]
WantedBy=default.target
EOF
  echo "[enable-autostart] Installed user unit: $PROXY_ENV_UNIT_PATH"
fi

systemctl --user daemon-reload

# Enable and start now
systemctl --user enable --now "$KERNEL_UNIT_NAME"
systemctl --user enable --now clash-proxy-env.service || true

# Try to enable lingering so user services start at boot before login
linger_state=$(loginctl show-user "$USER" 2>/dev/null | awk -F= '/^Linger=/{print $2}' || echo "no")
if [ "$linger_state" != "yes" ]; then
  if sudo -n loginctl enable-linger "$USER" >/dev/null 2>&1; then
    echo "[enable-autostart] Enabled lingering for $USER (services start at boot)."
  else
    echo "[enable-autostart] Linger is not enabled. Run (once) to start at boot without login:"
    echo "  sudo loginctl enable-linger $USER"
  fi
else
  echo "[enable-autostart] Linger already enabled for $USER."
fi

echo "[enable-autostart] Done. The Clash/Mihomo user service will start on boot/restart."
