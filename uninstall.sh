# shellcheck disable=SC2148
# shellcheck disable=SC1091
. script/common.sh >&/dev/null
. script/clashctl.sh >&/dev/null

_valid_env

clashoff >&/dev/null

# Stop and disable user service
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" systemctl --user disable "$BIN_KERNEL_NAME" >&/dev/null
    sudo -u "$SUDO_USER" systemctl --user stop "$BIN_KERNEL_NAME" >&/dev/null
    loginctl disable-linger "$SUDO_USER" 2>/dev/null
else
    systemctl --user disable "$BIN_KERNEL_NAME" >&/dev/null
    systemctl --user stop "$BIN_KERNEL_NAME" >&/dev/null
    loginctl disable-linger "$USER" 2>/dev/null
fi

rm -f "${USER_HOME}/.config/systemd/user/${BIN_KERNEL_NAME}.service"

# Reload systemd if running as user or with sudo
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" systemctl --user daemon-reload
else
    systemctl --user daemon-reload
fi

rm -rf "$CLASH_BASE_DIR"
sed -i '/clashupdate/d' "$CLASH_CRON_TAB" >&/dev/null 2>/dev/null
_set_rc unset

_okcat '✨' '已卸载，相关配置已清除'
_quit
