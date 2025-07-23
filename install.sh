# shellcheck disable=SC2148
# shellcheck disable=SC1091
. script/common.sh >&/dev/null
. script/clashctl.sh >&/dev/null

_valid_env

[ -d "$CLASH_BASE_DIR" ] && _error_quit "请先执行卸载脚本,以清除安装路径：$CLASH_BASE_DIR"

_get_kernel

# Create installation directory
mkdir -p "$CLASH_BASE_DIR/bin"

# Install binaries without sudo
install -D <(gzip -dc "$ZIP_KERNEL") "${CLASH_BASE_DIR}/bin/$BIN_KERNEL_NAME"
tar -xf "$ZIP_SUBCONVERTER" -C "${CLASH_BASE_DIR}/bin"
tar -xf "$ZIP_YQ" -C "${CLASH_BASE_DIR}/bin"
# shellcheck disable=SC2086
/bin/mv -f ${CLASH_BASE_DIR}/bin/yq_* "${CLASH_BASE_DIR}/bin/yq"

_set_bin "${CLASH_BASE_DIR}/bin"
_valid_config "$RESOURCES_CONFIG" || {
    echo -n "$(_okcat '✈️ ' '输入订阅：')"
    read -r url
    _okcat '⏳' '正在下载...'
    _download_config "$RESOURCES_CONFIG" "$url" || _error_quit "下载失败: 请将配置内容写入 $RESOURCES_CONFIG 后重新安装"
    _valid_config "$RESOURCES_CONFIG" || _error_quit "配置无效，请检查配置：$RESOURCES_CONFIG，转换日志：$BIN_SUBCONVERTER_LOG"
}
_okcat '✅' '配置可用'
echo "$url" >"$CLASH_CONFIG_URL"

/bin/cp -rf "$SCRIPT_BASE_DIR" "$CLASH_BASE_DIR"
/bin/ls "$RESOURCES_BASE_DIR" | grep -Ev 'zip|png' | xargs -I {} /bin/cp -rf "${RESOURCES_BASE_DIR}/{}" "$CLASH_BASE_DIR"
tar -xf "$ZIP_UI" -C "$CLASH_BASE_DIR"

_set_rc
_set_bin
_merge_config_restart

# Create user systemd service
mkdir -p "${USER_HOME}/.config/systemd/user"
cat <<EOF >"${USER_HOME}/.config/systemd/user/${BIN_KERNEL_NAME}.service"
[Unit]
Description=$BIN_KERNEL_NAME Daemon, A[nother] Clash Kernel.
After=network.target

[Service]
Type=simple
Restart=always
ExecStart=${BIN_KERNEL} -d ${CLASH_BASE_DIR} -f ${CLASH_CONFIG_RUNTIME}
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Ensure proper ownership
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER:$(id -gn $SUDO_USER)" "$CLASH_BASE_DIR"
    chown -R "$SUDO_USER:$(id -gn $SUDO_USER)" "${USER_HOME}/.config/systemd"
fi

# Enable systemd user service (run as the actual user)
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" systemctl --user daemon-reload
    sudo -u "$SUDO_USER" systemctl --user enable "$BIN_KERNEL_NAME" >&/dev/null || _failcat '💥' "设置自启失败" && _okcat '🚀' "已设置开机自启"
    # Enable lingering to allow user services to start at boot
    loginctl enable-linger "$SUDO_USER" 2>/dev/null || _okcat '⚠️' "无法设置开机自启，可手动执行: sudo loginctl enable-linger $SUDO_USER"
else
    systemctl --user daemon-reload
    systemctl --user enable "$BIN_KERNEL_NAME" >&/dev/null || _failcat '💥' "设置自启失败" && _okcat '🚀' "已设置开机自启"
    # Enable lingering to allow user services to start at boot
    loginctl enable-linger "$USER" 2>/dev/null || _okcat '⚠️' "无法设置开机自启，可手动执行: sudo loginctl enable-linger $USER"
fi

clashui
_okcat '🎉' 'enjoy 🎉'
_okcat '📋' "说明：已安装为用户服务，无需sudo权限。配置位于：$CLASH_BASE_DIR"
_okcat '🚀' "代理将在每次登录时自动启动。手动控制：clash on/off"
clash
_quit
clash
_quit
