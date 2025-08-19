# shellcheck disable=SC2148
# shellcheck disable=SC2155

_set_system_proxy() {
    local auth=$("$BIN_YQ" '.authentication[0] // ""' "$CLASH_CONFIG_RUNTIME")
    [ -n "$auth" ] && auth=$auth@

    local http_proxy_addr="http://${auth}127.0.0.1:${MIXED_PORT}"
    local socks_proxy_addr="socks5h://${auth}127.0.0.1:${MIXED_PORT}"
    local no_proxy_addr="localhost,127.0.0.1,::1"

    # Idempotency / jitter reduction: avoid re-applying unchanged settings which can
    # trigger desktop-wide NET::ERR_NETWORK_CHANGED events (especially in Electron / Chrome).
    # Create a small state file capturing last applied port & auth.
    local state_file="/tmp/.clash_system_proxy_state"
    local current_state="${MIXED_PORT}|${auth}"
    if [ -f "$state_file" ]; then
        local previous_state shell_http shell_mode
        previous_state=$(cat "$state_file" 2>/dev/null || echo '')
        # Quick env check (fast path) – if environment already points to same proxy, skip heavy desktop mutations.
        if [ "$previous_state" = "$current_state" ] && [ "${http_proxy:-}" = "$http_proxy_addr" ]; then
            # For GNOME, verify only if mode already manual & host/port correct; else fall through.
            if command -v gsettings >/dev/null 2>&1; then
                shell_mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo '')
                shell_http=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null || echo '')
                if [ "$shell_mode" = "'manual'" ] && [ "$shell_http" = "'127.0.0.1'" ]; then
                    # Nothing to change – keep env fresh (exports) and exit early.
                    export http_proxy=$http_proxy_addr https_proxy=$http_proxy HTTP_PROXY=$http_proxy HTTPS_PROXY=$http_proxy
                    export all_proxy=$socks_proxy_addr ALL_PROXY=$all_proxy
                    export no_proxy=$no_proxy_addr NO_PROXY=$no_proxy
                    return 0
                fi
            else
                # Non-GNOME path, settings already applied; exit.
                export http_proxy=$http_proxy_addr https_proxy=$http_proxy HTTP_PROXY=$http_proxy HTTPS_PROXY=$http_proxy
                export all_proxy=$socks_proxy_addr ALL_PROXY=$all_proxy
                export no_proxy=$no_proxy_addr NO_PROXY=$no_proxy
                return 0
            fi
        fi
    fi

    # Set environment variables for terminal applications
    export http_proxy=$http_proxy_addr
    export https_proxy=$http_proxy
    export HTTP_PROXY=$http_proxy
    export HTTPS_PROXY=$http_proxy

    export all_proxy=$socks_proxy_addr
    export ALL_PROXY=$all_proxy

    export no_proxy=$no_proxy_addr
    export NO_PROXY=$no_proxy

    # Enable Clash system proxy (affects system-level settings)
    "$BIN_YQ" -i '.system-proxy.enable = true' "$CLASH_CONFIG_MIXIN"

    # Set GNOME/GTK proxy settings (for GUI applications)
    if command -v gsettings >&/dev/null; then
        gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null || true
        gsettings set org.gnome.system.proxy.http host '127.0.0.1' 2>/dev/null || true
        gsettings set org.gnome.system.proxy.http port "${MIXED_PORT}" 2>/dev/null || true
        gsettings set org.gnome.system.proxy.https host '127.0.0.1' 2>/dev/null || true
        gsettings set org.gnome.system.proxy.https port "${MIXED_PORT}" 2>/dev/null || true
        gsettings set org.gnome.system.proxy.socks host '127.0.0.1' 2>/dev/null || true
        gsettings set org.gnome.system.proxy.socks port "${MIXED_PORT}" 2>/dev/null || true
        gsettings set org.gnome.system.proxy ignore-hosts "['localhost', '127.0.0.0/8', '::1']" 2>/dev/null || true
    fi

    # Set KDE proxy settings (for KDE applications)
    if command -v kwriteconfig5 >&/dev/null; then
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 1 2>/dev/null || true
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key httpProxy "127.0.0.1:${MIXED_PORT}" 2>/dev/null || true
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key httpsProxy "127.0.0.1:${MIXED_PORT}" 2>/dev/null || true
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key NoProxyFor "localhost,127.0.0.1,::1" 2>/dev/null || true
    fi

    # Configure Git proxy
    git config --global http.proxy "$http_proxy_addr" 2>/dev/null || true
    git config --global https.proxy "$http_proxy_addr" 2>/dev/null || true

    # Configure APT proxy (create/update configuration file)
    local apt_proxy_file="/tmp/95clash-proxy"
    cat > "$apt_proxy_file" 2>/dev/null << EOF || true
Acquire::http::Proxy "$http_proxy_addr";
Acquire::https::Proxy "$http_proxy_addr";
EOF
    [ -f "$apt_proxy_file" ] && _okcat '📦' "APT代理配置已生成：$apt_proxy_file (需要sudo权限应用: sudo cp $apt_proxy_file /etc/apt/apt.conf.d/)"

    echo "$current_state" >"$state_file" 2>/dev/null || true
}

_unset_system_proxy() {
    # Unset environment variables
    unset http_proxy
    unset https_proxy
    unset HTTP_PROXY
    unset HTTPS_PROXY
    unset all_proxy
    unset ALL_PROXY
    unset no_proxy
    unset NO_PROXY

    # Disable Clash system proxy
    "$BIN_YQ" -i '.system-proxy.enable = false' "$CLASH_CONFIG_MIXIN"

    # Unset GNOME/GTK proxy settings
    if command -v gsettings >&/dev/null; then
        gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null || true
    fi

    # Unset KDE proxy settings
    if command -v kwriteconfig5 >&/dev/null; then
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 0 2>/dev/null || true
    fi

    # Unset Git proxy
    git config --global --unset http.proxy 2>/dev/null || true
    git config --global --unset https.proxy 2>/dev/null || true

    # Remove APT proxy configuration
    rm -f /tmp/95clash-proxy 2>/dev/null || true
    [ -f /etc/apt/apt.conf.d/95clash-proxy ] && _okcat '📦' "APT代理配置需要手动删除: sudo rm /etc/apt/apt.conf.d/95clash-proxy"

    # Clear state file so next enable actually re-applies.
    rm -f /tmp/.clash_system_proxy_state 2>/dev/null || true
}

function clashon() {
    _get_proxy_port
    systemctl --user is-active "$BIN_KERNEL_NAME" >&/dev/null || {
        systemctl --user start "$BIN_KERNEL_NAME" >/dev/null || {
            _failcat '启动失败: 执行 clashstatus 查看日志'
            return 1
        }
    }
    _set_system_proxy
    _okcat '已开启代理环境'
}

watch_proxy() {
    [ -z "$http_proxy" ] && [[ $- == *i* ]] && {
        clashproxy status >&/dev/null && clashon
    }
}

function clashoff() {
    systemctl --user stop "$BIN_KERNEL_NAME" && _okcat '已关闭代理程序' ||
        _failcat '关闭失败: 执行 "clashstatus" 查看日志' || return 1
    _unset_system_proxy
}

clashrestart() {
    { clashoff && clashon; } >&/dev/null
}

function clashproxy() {
    case "$1" in
    on)
        systemctl --user is-active "$BIN_KERNEL_NAME" >&/dev/null || {
            _failcat '代理程序未运行，请执行 clashon 开启代理环境'
            return 1
        }
        _set_system_proxy
        _okcat '已开启系统代理'
        ;;
    off)
        _unset_system_proxy
        _okcat '已关闭系统代理'
        ;;
    status)
        local system_proxy_status=$("$BIN_YQ" '.system-proxy.enable' "$CLASH_CONFIG_MIXIN" 2>/dev/null)
        [ "$system_proxy_status" = "false" ] && {
            _failcat "系统代理：关闭"
            return 1
        }
        _okcat "系统代理：开启
http_proxy： $http_proxy
socks_proxy：$all_proxy"
        ;;
    *)
        cat <<EOF
用法: clashproxy [on|off|status]
    on      开启系统代理
    off     关闭系统代理
    status  查看系统代理状态
EOF
        ;;
    esac
}

function clashstatus() {
    systemctl --user status "$BIN_KERNEL_NAME" "$@"
}

function clashui() {
    _get_ui_port
    # 公网ip
    # ifconfig.me
    local query_url='api64.ipify.org'
    local public_ip=$(curl -s --noproxy "*" --connect-timeout 2 $query_url)
    local public_address="http://${public_ip:-公网}:${UI_PORT}/ui"
    # 内网ip
    # ip route get 1.1.1.1 | grep -oP 'src \K\S+'
    local local_ip=$(hostname -I | awk '{print $1}')
    local local_address="http://${local_ip}:${UI_PORT}/ui"
    printf "\n"
    printf "╔═══════════════════════════════════════════════╗\n"
    printf "║                %s                  ║\n" "$(_okcat 'Web 控制台')"
    printf "║═══════════════════════════════════════════════║\n"
    printf "║                                               ║\n"
    printf "║     🔓 注意放行端口：%-5s                    ║\n" "$UI_PORT"
    printf "║     🏠 内网：%-31s  ║\n" "$local_address"
    printf "║     🌏 公网：%-31s  ║\n" "$public_address"
    printf "║     ☁️  公共：%-31s  ║\n" "$URL_CLASH_UI"
    printf "║                                               ║\n"
    printf "╚═══════════════════════════════════════════════╝\n"
    printf "\n"
}

_merge_config_restart() {
    local backup="/tmp/rt.backup"
    cat "$CLASH_CONFIG_RUNTIME" 2>/dev/null | tee $backup >&/dev/null
    # 合并策略: 多级回退 (eval-all -> slurp -s -> 简单三向覆盖) 确保不同发行版的 yq 构建兼容。
    local merge_err="/tmp/.clash_merge_err"; : > "$merge_err"
    if ! "$BIN_YQ" eval-all '
        (select(fileIndex==0)."proxy-groups" // []) as $m1 |
        (select(fileIndex==1)."proxy-groups" // []) as $raw |
        (select(fileIndex==2)."proxy-groups" // []) as $m2 |
        (select(fileIndex==0) *+ select(fileIndex==1) *+ select(fileIndex==2)) as $base |
        $base |
        ."proxy-groups" = ($m1 + $raw + $m2
            | sort_by(.name)
            | group_by(.name)
            | map(.[-1] | if .type=="select" then del(.url,.interval,.tolerance) else . end))
    ' "$CLASH_CONFIG_MIXIN" "$CLASH_CONFIG_RAW" "$CLASH_CONFIG_MIXIN" >"$CLASH_CONFIG_RUNTIME.tmp" 2>>"$merge_err"; then
        # 回退 1: slurp 模式
        if ! "$BIN_YQ" -s '
            . as $d |
            ($d[0] *+ $d[1] *+ $d[2]) as $base |
            $base |
            ."proxy-groups" = ([ ($d[0]."proxy-groups" // [])[], ($d[1]."proxy-groups" // [])[], ($d[2]."proxy-groups" // [])[] ]
               | sort_by(.name)
               | group_by(.name)
               | map(.[-1] | if .type=="select" then del(.url,.interval,.tolerance) else . end))
        ' "$CLASH_CONFIG_MIXIN" "$CLASH_CONFIG_RAW" "$CLASH_CONFIG_MIXIN" >"$CLASH_CONFIG_RUNTIME.tmp" 2>>"$merge_err"; then
            # 回退 2: 简单覆盖 (丢弃订阅中分组再加精简): 先 raw 写入, 再用 mixin 覆盖标量并替换 proxy-groups
            cp "$CLASH_CONFIG_RAW" "$CLASH_CONFIG_RUNTIME.tmp" 2>>"$merge_err" || true
            # 覆盖标量 (mixin 优先)
            "$BIN_YQ" eval-all 'select(fileIndex==0) *+ select(fileIndex==1)' \
                "$CLASH_CONFIG_RUNTIME.tmp" "$CLASH_CONFIG_MIXIN" > "$CLASH_CONFIG_RUNTIME.tmp.m" 2>>"$merge_err" || true
            mv "$CLASH_CONFIG_RUNTIME.tmp.m" "$CLASH_CONFIG_RUNTIME.tmp" 2>/dev/null || true
            # 强制采用 mixin 的 proxy-groups (精简分组)
            "$BIN_YQ" -i '."proxy-groups" = (input."proxy-groups")' "$CLASH_CONFIG_RUNTIME.tmp" "$CLASH_CONFIG_MIXIN" 2>>"$merge_err" || true
            # 清理 select 探测
            "$BIN_YQ" -i '.proxy-groups |= map( if .type=="select" then del(.url,.interval,.tolerance) else . end )' "$CLASH_CONFIG_RUNTIME.tmp" 2>>"$merge_err" || true
            if [ ! -s "$CLASH_CONFIG_RUNTIME.tmp" ]; then
                cat $backup | tee "$CLASH_CONFIG_RUNTIME" >&/dev/null
                _error_quit "合并失败：所有策略失败 -> $(head -n 3 "$merge_err" | tr '\n' ' ')"
            fi
        fi
    fi
    mv "$CLASH_CONFIG_RUNTIME.tmp" "$CLASH_CONFIG_RUNTIME" 2>/dev/null || true
    # 运行时再保险：去重同名 proxy-groups（保持最后一个定义）
    "$BIN_YQ" -i '.proxy-groups |= ( . // [] | group_by(.name) | map(.[-1]) )' "$CLASH_CONFIG_RUNTIME" 2>/dev/null || true
    _valid_config "$CLASH_CONFIG_RUNTIME" || {
        cat $backup | tee "$CLASH_CONFIG_RUNTIME" >&/dev/null
        _error_quit "验证失败：请检查 Mixin 配置 (运行时回滚)"
    }

        # 强制二次清理（保险）：去除所有 select 组里残留的 url / interval / tolerance 字段（无论是否上面已删除）。
        # 某些 yq 版本在 flow style map 上的 del 可能未生效；此处再执行一次确保 runtime.yaml 干净，避免内核继续探测。
        "$BIN_YQ" -i '
            .proxy-groups |= map(
                if .type == "select" then with_entries(select(.key != "url" and .key != "interval" and .key != "tolerance")) else . end
            )
        ' "$CLASH_CONFIG_RUNTIME" 2>/dev/null || true

        # 再次校验（失败也不回滚，只提示）。
        _valid_config "$CLASH_CONFIG_RUNTIME" || _failcat '清理后验证警告：请手动检查 runtime.yaml'
    # 合并后自动清理残留探测字段再重启
    _cleanup_probe_fields >/dev/null 2>&1 || true
    clashrestart
}

# 手动触发一次运行时配置清理，不做合并，只移除 select 组探测字段。
_cleanup_probe_fields() {
    [ -f "$CLASH_CONFIG_RUNTIME" ] || { _failcat '缺少 runtime.yaml'; return 1; }
    # 第一次尝试：原地删除
    "$BIN_YQ" -i '.proxy-groups |= map( if .type=="select" then del(.url,.interval,.tolerance) else . end )' "$CLASH_CONFIG_RUNTIME" 2>/dev/null || true
    if grep -qE '^\s*- \{name: .*type: select.*(url:|interval:|tolerance:)' "$CLASH_CONFIG_RUNTIME"; then
        # Fallback：重新构建文件（非 inline flow style），保证 yq 能序列化正确
        local tmp_file="${CLASH_CONFIG_RUNTIME}.clean"
        "$BIN_YQ" '.proxy-groups = (.proxy-groups | map( if .type=="select" then del(.url,.interval,.tolerance) else . end ))' \
            "$CLASH_CONFIG_RUNTIME" > "$tmp_file" 2>/dev/null && {
            mv "$tmp_file" "$CLASH_CONFIG_RUNTIME"
        }
    fi
    # 如果仍然检测到残留（多为 flow style 行内映射 yq 未清除），用 sed 兜底删除文本片段。
    if grep -qE 'url:|interval:|tolerance:' "$CLASH_CONFIG_RUNTIME"; then
        sed -E -i \
            -e "s/, *url: *'[^']*'//g" \
            -e 's/, *interval: *[0-9]+//g' \
            -e 's/, *tolerance: *[0-9]+//g' \
            -e 's/, *}/}/g' \
            "$CLASH_CONFIG_RUNTIME" 2>/dev/null || true
    fi
    if grep -qE 'url:|interval:|tolerance:' "$CLASH_CONFIG_RUNTIME"; then
        # 深度检测：用 yq 再判定 select 组内部是否仍残留
        local remain=$("$BIN_YQ" '.proxy-groups[] | select(.type=="select" and (has("url") or has("interval") or has("tolerance"))) | .name' "$CLASH_CONFIG_RUNTIME" 2>/dev/null | wc -l || echo 0)
        [ "$remain" -gt 0 ] && {
            _failcat "仍有 ${remain} 个 select 分组残留探测字段（请手工检查）"
            return 1
        }
    fi
    _okcat '🧹 已清理 select 组探测字段'
}

function clashsecret() {
    case "$#" in
    0)
        _okcat "当前密钥：$("$BIN_YQ" '.secret // ""' "$CLASH_CONFIG_RUNTIME")"
        ;;
    1)
        "$BIN_YQ" -i ".secret = \"$1\"" "$CLASH_CONFIG_MIXIN" || {
            _failcat "密钥更新失败，请重新输入"
            return 1
        }
        _merge_config_restart
        _okcat "密钥更新成功，已重启生效"
        ;;
    *)
        _failcat "密钥不要包含空格或使用引号包围"
        ;;
    esac
}

_tunstatus() {
    local tun_status=$("$BIN_YQ" '.tun.enable' "${CLASH_CONFIG_RUNTIME}")
    # shellcheck disable=SC2015
    [ "$tun_status" = 'true' ] && _okcat 'Tun 状态：启用' || _failcat 'Tun 状态：关闭'
}

_tunoff() {
    _tunstatus >/dev/null || return 0
    "$BIN_YQ" -i '.tun.enable = false' "$CLASH_CONFIG_MIXIN"
    _merge_config_restart && _okcat "Tun 模式已关闭"
}

_tunon() {
    _tunstatus 2>/dev/null && return 0
    "$BIN_YQ" -i '.tun.enable = true' "$CLASH_CONFIG_MIXIN"
    _merge_config_restart
    sleep 0.5s
    journalctl --user -u "$BIN_KERNEL_NAME" --since "1 min ago" | grep -E -m1 'unsupported kernel version|Start TUN listening error' && {
        _tunoff >&/dev/null
        _error_quit '不支持的内核版本'
    }

    # 开启TUN模式时卸载环境变量，避免冲突
    _unset_system_proxy
    _okcat "Tun 模式已开启，已自动卸载环境变量代理"
}

function clashtun() {
    case "$1" in
    on)
        _tunon
        ;;
    off)
        _tunoff
        ;;
    *)
        _tunstatus
        ;;
    esac
}

function clashupdate() {
    local url=$(cat "$CLASH_CONFIG_URL")
    local is_auto

    case "$1" in
    auto)
        is_auto=true
        [ -n "$2" ] && url=$2
        ;;
    log)
        tail "${CLASH_UPDATE_LOG}" 2>/dev/null || _failcat "暂无更新日志"
        return 0
        ;;
    *)
        [ -n "$1" ] && url=$1
        ;;
    esac

    # 如果没有提供有效的订阅链接（url为空或者不是http开头），则使用默认配置文件
    [ "${url:0:4}" != "http" ] && {
        _failcat "没有提供有效的订阅链接：使用 ${CLASH_CONFIG_RAW} 进行更新..."
        url="file://$CLASH_CONFIG_RAW"
    }

    # 如果是自动更新模式，则设置定时任务
    [ "$is_auto" = true ] && {
        grep -qs 'clashupdate' "$CLASH_CRON_TAB" || echo "0 0 */2 * * $_SHELL -i -c 'clashupdate $url'" | tee -a "$CLASH_CRON_TAB" >&/dev/null
        _okcat "已设置定时更新订阅" && return 0
    }

    _okcat '👌' "正在下载：原配置已备份..."
    cat "$CLASH_CONFIG_RAW" | tee "$CLASH_CONFIG_RAW_BAK" >&/dev/null

    _rollback() {
        _failcat '🍂' "$1"
        cat "$CLASH_CONFIG_RAW_BAK" | tee "$CLASH_CONFIG_RAW" >&/dev/null
        _failcat '❌' "[$(date +"%Y-%m-%d %H:%M:%S")] 订阅更新失败：$url" 2>&1 | tee -a "${CLASH_UPDATE_LOG}" >&/dev/null
        _error_quit
    }

    _download_config "$CLASH_CONFIG_RAW" "$url" || _rollback "下载失败：已回滚配置"
    _valid_config "$CLASH_CONFIG_RAW" || _rollback "转换失败：已回滚配置，转换日志：$BIN_SUBCONVERTER_LOG"

    _merge_config_restart && _okcat '🍃' '订阅更新成功'
    echo "$url" | tee "$CLASH_CONFIG_URL" >&/dev/null
    _okcat '✅' "[$(date +"%Y-%m-%d %H:%M:%S")] 订阅更新成功：$url" | tee -a "${CLASH_UPDATE_LOG}" >&/dev/null
}

function clashmixin() {
    case "$1" in
    -e)
        vim "$CLASH_CONFIG_MIXIN" && {
            _merge_config_restart && _okcat "配置更新成功，已重启生效"
        }
        ;;
    -r)
        less -f "$CLASH_CONFIG_RUNTIME"
        ;;
    *)
        less -f "$CLASH_CONFIG_MIXIN"
        ;;
    esac
}

function clashctl() {
    case "$1" in
    on)
        clashon
        ;;
    off)
        clashoff
        ;;
    ui)
        clashui
        ;;
    status)
        shift
        clashstatus "$@"
        ;;
    proxy)
        shift
        clashproxy "$@"
        ;;
    tun)
        shift
        clashtun "$@"
        ;;
    mixin)
        shift
        clashmixin "$@"
        ;;
    secret)
        shift
        clashsecret "$@"
        ;;
    update)
        shift
        clashupdate "$@"
        ;;
    cleanup)
        _cleanup_probe_fields || return 1
        ;;
    failnodes)
        shift
        _fail_nodes "$@"
        ;;
    *)
        cat <<EOF

Usage:
    clash COMMAND  [OPTION]

Commands:
    on                      开启代理
    off                     关闭代理
    proxy    [on|off]       系统代理
    ui                      面板地址
    status                  内核状况
    tun      [on|off]       Tun 模式
    mixin    [-e|-r]        Mixin 配置
    secret   [SECRET]       Web 密钥
    update   [auto|log]     更新订阅
    cleanup                清理 select 组残留探测字段
    failnodes [MIN]        统计最近(默认2)分钟失败上游节点

说明:
    - clashon: 启动代理程序，并开启系统代理
    - clashproxy: 仅控制系统代理，不影响代理程序

EOF
        ;;
    esac
}

function mihomoctl() {
    clashctl "$@"
}

function clash() {
    clashctl "$@"
}

function mihomo() {
    clashctl "$@"
}

# 统计最近失败上游节点 (默认2分钟, 可传分钟值) 并列出前10个目标 (host:port)
_fail_nodes() {
        local since_min=${1:-2}
        local limit=10
        [[ $since_min =~ ^[0-9]+$ ]] || { _failcat '分钟参数需为整数'; return 1; }
        local raw
        raw=$(journalctl --user -u "$BIN_KERNEL_NAME" --since "${since_min} min ago" --no-pager 2>/dev/null | grep 'connect error' || true)
        [ -z "$raw" ] && { _okcat "最近 ${since_min} 分钟无失败记录"; return 0; }
        echo "$raw" \
            | sed -E 's/.*error: ([^ ]+) connect error.*/\1/' \
            | sort | uniq -c | sort -nr | head -n "$limit" \
            | awk 'BEGIN{printf "  次数  上游(主机:端口)\n"}{printf "%6s  %s\n", $1,$2}'
        _okcat '可考虑在 mixin 中重定义分组剔除高失败节点或面板手动切换。'
}
