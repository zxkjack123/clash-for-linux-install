#!/usr/bin/env bash
# shellcheck disable=SC1091
. script/common.sh
. script/clashctl.sh

type _valid_env >/dev/null 2>&1 || { echo "ERROR: must run from repository root (missing script/common.sh or failed to source)" >&2; exit 2; }

_valid_env

[ -d "$CLASH_BASE_DIR" ] && _error_quit "请先执行卸载脚本,以清除安装路径：$CLASH_BASE_DIR"

_get_kernel

# Create installation directory
mkdir -p "$CLASH_BASE_DIR/bin"

# Install binaries in user space
install -D <(gzip -dc "$ZIP_KERNEL") "${CLASH_BASE_DIR}/bin/$BIN_KERNEL_NAME"
tar -xf "$ZIP_SUBCONVERTER" -C "${CLASH_BASE_DIR}/bin"
tar -xf "$ZIP_YQ" -C "${CLASH_BASE_DIR}/bin"
# shellcheck disable=SC2086
/bin/mv -f ${CLASH_BASE_DIR}/bin/yq_* "${CLASH_BASE_DIR}/bin/yq"

_set_bin "${CLASH_BASE_DIR}/bin"

# Initialize url variable
url=""

_valid_config "$RESOURCES_CONFIG" || {
    # echo -n "$(_okcat '✈️ ' '输入订阅：')"
    # read -r url
    # _okcat '⏳' '正在下载...'
    # _download_config "$RESOURCES_CONFIG" "$url" || _error_quit "下载失败: 请将配置内容写入 $RESOURCES_CONFIG 后重新安装"
    # _valid_config "$RESOURCES_CONFIG" || _error_quit "配置无效，请检查配置：$RESOURCES_CONFIG，转换日志：$BIN_SUBCONVERTER_LOG"
    _error_quit "配置无效，请检查 $RESOURCES_CONFIG"
}
_okcat '✅' '配置可用'

# Only save URL if it was obtained from user input
if [ -n "$url" ]; then
    echo "$url" >"$CLASH_CONFIG_URL"
fi

/bin/cp -rf "$SCRIPT_BASE_DIR" "$CLASH_BASE_DIR"
# Copy resources except large archives and images (safe for spaces/newlines in filenames).
find "$RESOURCES_BASE_DIR" -mindepth 1 -maxdepth 1 \
    ! -name 'zip' \
    ! -name '*.png' \
    -print0 | xargs -0 -I {} /bin/cp -rf "{}" "$CLASH_BASE_DIR"
tar -xf "$ZIP_UI" -C "$CLASH_BASE_DIR"

_set_rc
_set_bin
_merge_config_restart

# Install lightweight CLI entrypoints (avoid naming conflicts with the kernel binary `clash`/`mihomo`)
mkdir -p "${USER_HOME}/.local/bin"
# Ensure scripts are executable in the install dir
chmod +x "${CLASH_SCRIPT_DIR}/clashctl.sh" 2>/dev/null || true
if [ -f "${CLASH_SCRIPT_DIR}/emergency_off.sh" ]; then
    chmod +x "${CLASH_SCRIPT_DIR}/emergency_off.sh" 2>/dev/null || true
fi

_install_cli_link() {
    local name="$1"
    local target="${CLASH_SCRIPT_DIR}/clashctl.sh"
    local dest="${USER_HOME}/.local/bin/${name}"
    # If an existing non-symlink file is present, do not overwrite it.
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        _okcat '⚠️' "检测到已存在命令：$dest (非符号链接)，跳过安装 ${name}；你可以手动改名或删除后重试"
        return 0
    fi
    ln -sf "$target" "$dest" 2>/dev/null || true
}

_install_cli_link clashctl
_install_cli_link mihomoctl

# Create user systemd service
mkdir -p "${USER_HOME}/.config/systemd/user"
cat <<EOF >"${USER_HOME}/.config/systemd/user/${BIN_KERNEL_NAME}.service"
[Unit]
Description=$BIN_KERNEL_NAME Daemon, A[nother] Clash Kernel.
After=network.target

[Service]
Type=simple
Restart=always
ExecStart="${BIN_KERNEL}" -d "${CLASH_BASE_DIR}" -f "${CLASH_CONFIG_RUNTIME}"
RestartSec=5
TimeoutStartSec=30

[Install]
WantedBy=default.target
EOF

# Create proxy environment service
cat <<EOF >"${USER_HOME}/.config/systemd/user/clash-proxy-env.service"
[Unit]
Description=Clash Proxy Environment Setup
After=${BIN_KERNEL_NAME}.service
BindsTo=${BIN_KERNEL_NAME}.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'source ${CLASH_SCRIPT_DIR}/common.sh && source ${CLASH_SCRIPT_DIR}/clashctl.sh && _set_system_proxy'
ExecStop=/bin/bash -c 'source ${CLASH_SCRIPT_DIR}/common.sh && source ${CLASH_SCRIPT_DIR}/clashctl.sh && _unset_system_proxy'
TimeoutStartSec=10

[Install]
WantedBy=default.target
EOF

# Install optional subscription refresh units with resolved install paths.
cat <<EOF >"${USER_HOME}/.config/systemd/user/clash-subscription-refresh.service"
[Unit]
Description=Refresh Clash subscription (proxy-clean)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${CLASH_BASE_DIR}
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/snap/bin
Environment=RUN_OPTIMIZE_AFTER_REFRESH=1
Environment=OPTIMIZE_DELAY=900
Environment=OPTIMIZE_SCRIPT=${CLASH_BASE_DIR}/vpn-tools/optimize_all_network.sh
ExecStart=${CLASH_BASE_DIR}/script/refresh_subscription_direct.sh
TimeoutStartSec=45min
EOF

cat <<EOF >"${USER_HOME}/.config/systemd/user/clash-subscription-refresh.timer"
[Unit]
Description=Daily Clash subscription refresh

[Timer]
OnCalendar=*-*-* 04:30
Persistent=true
Unit=clash-subscription-refresh.service
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF

# Enable systemd user services
systemctl --user daemon-reload
systemctl --user enable "$BIN_KERNEL_NAME" >&/dev/null && _okcat '✅' "已设置开机自启" || _failcat '❌' "设置自启失败"
systemctl --user enable clash-proxy-env.service >&/dev/null || _okcat '⚠️' "代理环境服务设置失败，将依赖shell启动"
_okcat '⏱️' "已安装可选订阅自动刷新单元：clash-subscription-refresh.{service,timer}（默认未启用）"

# Enable lingering to allow user services to start at boot
loginctl enable-linger "$USER" 2>/dev/null || _okcat '⚠️' "无法设置开机自启，可手动执行: loginctl enable-linger $USER（可能需要管理员权限）"

clashui
_okcat '🎉' 'enjoy 🎉'
_okcat '📂' "说明：已安装为用户服务，无需任何特殊权限。配置位于：$CLASH_BASE_DIR"
_okcat '🚀' "代理将在每次登录时自动启动（systemd 用户服务）。命令入口：clashctl on/off/status"
_okcat '💡' "若 clashctl 不可用，请确认 ~/.local/bin 在 PATH 中，或直接运行：bash $CLASH_SCRIPT_DIR/clashctl.sh status"
clashctl
_quit
