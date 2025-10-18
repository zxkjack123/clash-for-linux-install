#!/usr/bin/env bash
# shellcheck disable=SC2148
# shellcheck disable=SC2155

# Ensure common environment is loaded when running this script standalone (not via shell rc sourcing)
if [ -z "$CLASH_ENV_INITIALIZED" ]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    # common.sh 相对定位 (支持在仓库根或安装目录运行)
    if [ -f "$SCRIPT_DIR/common.sh" ]; then
        # shellcheck source=/dev/null
        . "$SCRIPT_DIR/common.sh"
        export CLASH_ENV_INITIALIZED=1
    fi
fi

# 安全辅助: sed 正则转义 (用于节点名可能包含特殊字符)
_escape_sed() {
    printf '%s' "$1" | sed -e 's/[\/\\&.*$^[]/\\&/g' -e 's/]/\\]/g' -e 's/(/\\(/g' -e 's/)/\\)/g' -e 's/+\\?/+/g'
}

_set_system_proxy() {
    # Ensure MIXED_PORT is populated and valid before constructing proxy URLs
    _get_proxy_port
    if ! [[ "+${MIXED_PORT:-}" =~ ^\+[0-9]+$ ]] || [ "${MIXED_PORT:-0}" -lt 1 ] || [ "${MIXED_PORT:-0}" -gt 65535 ]; then
        # Fallback to default port to avoid producing an invalid url like 127.0.0.1:
        MIXED_PORT=7890
    fi
    local auth=$("$BIN_YQ" '.authentication[0] // ""' "$CLASH_CONFIG_RUNTIME")
    [ -n "$auth" ] && auth=$auth@

    local http_proxy_addr="http://${auth}127.0.0.1:${MIXED_PORT}"
    local socks_proxy_addr="socks5h://${auth}127.0.0.1:${MIXED_PORT}"
    # 基础直连免代理列表 (扩展 Tailscale / Funnel 域 & 100.64.0.0/10 内网网段，避免干扰 tailnet 访问)
    # 说明: curl / 浏览器 在设置 http_proxy 后，会对所有域名走代理；加入 *.ts.net 可确保 tailnet 解析 / 访问直接走 Tailscale 接口
    #      100.64.0.0/10 属于 Tailscale CGNAT 地址空间；tailscale.io 及 ts.net 控制面 / funnel 子域避免代理分层导致握手异常。
    # 初始 no_proxy 列表
    # 说明:
    #  1) 同时包含 "ts.net" 与 ".ts.net" 以兼容不同实现对前导点匹配语义 (某些实现只有前导点才匹配子域)
    #  2) tailscale MagicDNS 解析 & Funnel 域 统一走直连, 避免被 http_proxy 劫持到本地 127.0.0.1:PORT 造成连接失败
    #  3) 加入 100.100.100.100 (Tailscale 内部 DNS) 及 100.64.0.0/10 CGNAT 地址空间; 虽然多数工具不支持 CIDR 匹配, 但保留不影响
    local no_proxy_addr="localhost,127.0.0.1,::1,ts.net,.ts.net,tailscale.io,.tailscale.io,100.100.100.100,100.64.0.0/10"
    # 动态探测 tailnet MagicDNSSuffix (tailscale status --json) 例: tail69c12a.ts.net
    if command -v tailscale >/dev/null 2>&1; then
        local ts_suffix
        ts_suffix=$(tailscale status --json 2>/dev/null | grep -o '"MagicDNSSuffix"[^"]*"[^"]*"' | sed -E 's/.*"MagicDNSSuffix" *: *"([^"]+)"/\1/' | head -n1 || true)
        if [ -z "$ts_suffix" ]; then
            ts_suffix=$(tailscale status 2>/dev/null | grep -o 'tail[0-9a-f]*\.ts\.net' | head -n1 || true)
        fi
        if [ -n "$ts_suffix" ]; then
            # 为确保 synologynas923.${ts_suffix} 等多级子域在不同实现下都能匹配, 同时追加裸后缀与点前缀版本
            for _p in "$ts_suffix" ".$ts_suffix"; do
                case ",$no_proxy_addr," in
                    *",$_p,"*) :;;
                    *) no_proxy_addr="$no_proxy_addr,$_p" ;;
                esac
            done
        fi
    fi
    # 若内核未运行且上一次系统代理仍残留，避免设置一个不可达 127.0.0.1:PORT 导致 curl 直接报错
    systemctl --user is-active "$BIN_KERNEL_NAME" >/dev/null 2>&1 || {
        # 不直接退出函数，先清除遗留变量以便后续 clashon 再次设定
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
        export no_proxy=$no_proxy_addr NO_PROXY=$no_proxy_addr
        return 0
    }

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
        # 扩展内网免代理列表，避免本地/局域网走代理
    # 追加 tailscale 相关直连域 / 网段
    # 追加 tailscale 相关直连域 / 网段; GNOME 不支持 * 通配符，这里使用基础域 /8 ~ /16 & 具体后缀
    local g_ignore="['localhost', '127.0.0.0/8', '::1', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', 'ts.net', '.ts.net', 'tailscale.io', '.tailscale.io', '100.100.100.100', '100.64.0.0/10'"; \
    if [ -n "${ts_suffix:-}" ]; then g_ignore="$g_ignore, '$ts_suffix', '.${ts_suffix}'"; fi; g_ignore="$g_ignore]"; \
    gsettings set org.gnome.system.proxy ignore-hosts "$g_ignore" 2>/dev/null || true
    fi

    # Set KDE proxy settings (for KDE applications)
    if command -v kwriteconfig5 >&/dev/null; then
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 1 2>/dev/null || true
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key httpProxy "127.0.0.1:${MIXED_PORT}" 2>/dev/null || true
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key httpsProxy "127.0.0.1:${MIXED_PORT}" 2>/dev/null || true
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key NoProxyFor "localhost,127.0.0.1,::1" 2>/dev/null || true
    fi

    # Configure Git proxy – only if port is valid; otherwise do not write malformed values
    {
        port_only="${http_proxy_addr##*:}"
        if [[ "${port_only}" =~ ^[0-9]+$ ]] && [ "${port_only}" -ge 1 ] && [ "${port_only}" -le 65535 ]; then
            git config --global http.proxy "$http_proxy_addr" 2>/dev/null || true
            git config --global https.proxy "$http_proxy_addr" 2>/dev/null || true
        else
            # Avoid leaving bad settings around
            git config --global --unset http.proxy 2>/dev/null || true
            git config --global --unset https.proxy 2>/dev/null || true
        fi
    }

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
    # Auto-heal proxy env in new interactive shells. If http_proxy is missing or
    # points to a stale port (e.g., old 6209), refresh to current MIXED_PORT.
    [[ $- == *i* ]] || return 0
    # Ensure kernel is up (optional best-effort) and get current expected port
    _get_proxy_port
    local auth=$("$BIN_YQ" '.authentication[0] // ""' "$CLASH_CONFIG_RUNTIME")
    [ -n "$auth" ] && auth=$auth@
    local expect_http="http://${auth}127.0.0.1:${MIXED_PORT}"
    # If no kernel yet, defer to clashon path later
    if [ -z "$http_proxy" ] || [ "${http_proxy#*@}" != "${expect_http#*@}" ]; then
        # Only attempt if service running; else start it.
        if systemctl --user is-active "$BIN_KERNEL_NAME" >/dev/null 2>&1; then
            _set_system_proxy
        else
            clashon >/dev/null 2>&1 || true
        fi
    fi
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

_merge_build_runtime() {
    # 构建合并结果到指定输出文件 (参数1=输出路径)
    local out_file="$1"; shift || true
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
    ' "$CLASH_CONFIG_MIXIN" "$CLASH_CONFIG_RAW" "$CLASH_CONFIG_MIXIN" >"$out_file.tmp" 2>>"$merge_err"; then
        # 回退 1: slurp 模式
        if ! "$BIN_YQ" -s '
            . as $d |
            ($d[0] *+ $d[1] *+ $d[2]) as $base |
            $base |
            ."proxy-groups" = ([ ($d[0]."proxy-groups" // [])[], ($d[1]."proxy-groups" // [])[], ($d[2]."proxy-groups" // [])[] ]
               | sort_by(.name)
               | group_by(.name)
               | map(.[-1] | if .type=="select" then del(.url,.interval,.tolerance) else . end))
        ' "$CLASH_CONFIG_MIXIN" "$CLASH_CONFIG_RAW" "$CLASH_CONFIG_MIXIN" >"$out_file.tmp" 2>>"$merge_err"; then
            # 回退 2: 简单覆盖 (丢弃订阅中分组再加精简): 先 raw 写入, 再用 mixin 覆盖标量并替换 proxy-groups
            cp "$CLASH_CONFIG_RAW" "$out_file.tmp" 2>>"$merge_err" || true
            # 覆盖标量 (mixin 优先)
            "$BIN_YQ" eval-all 'select(fileIndex==0) *+ select(fileIndex==1)' \
                "$out_file.tmp" "$CLASH_CONFIG_MIXIN" > "$out_file.tmp.m" 2>>"$merge_err" || true
            mv "$out_file.tmp.m" "$out_file.tmp" 2>/dev/null || true
            # 强制采用 mixin 的 proxy-groups (精简分组)
            "$BIN_YQ" -i '."proxy-groups" = (input."proxy-groups")' "$out_file.tmp" "$CLASH_CONFIG_MIXIN" 2>>"$merge_err" || true
            # 清理 select 探测
            "$BIN_YQ" -i '.proxy-groups |= map( if .type=="select" then del(.url,.interval,.tolerance) else . end )' "$out_file.tmp" 2>>"$merge_err" || true
            if [ ! -s "$out_file.tmp" ]; then
                _error_quit "合并失败：所有策略失败 -> $(head -n 3 "$merge_err" | tr '\n' ' ')"
            fi
        fi
    fi
    mv "$out_file.tmp" "$out_file" 2>/dev/null || true
    "$BIN_YQ" -i '.proxy-groups |= ( . // [] | group_by(.name) | map(.[-1]) )' "$out_file" 2>/dev/null || true
    # 再次清理 select 探测字段
    "$BIN_YQ" -i '.proxy-groups |= map( if .type=="select" then del(.url,.interval,.tolerance) else . end )' "$out_file" 2>/dev/null || true
}

_annotate_runtime() {
    local file="$1"; shift || true
    local raw_sha mixin_sha
    raw_sha=$(sha1sum "$CLASH_CONFIG_RAW" 2>/dev/null | awk '{print $1}' | cut -c1-8)
    mixin_sha=$(sha1sum "$CLASH_CONFIG_MIXIN" 2>/dev/null | awk '{print $1}' | cut -c1-8)
    local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    grep -q 'runtime-built:' "$file" 2>/dev/null || {
        { echo "# runtime-built: $ts raw_sha=$raw_sha mixin_sha=$mixin_sha sanitized=1"; cat "$file"; } >"$file.annot" && mv "$file.annot" "$file"
    }
}

_merge_sanitize_restart() {
    local lock_file="/tmp/.clash_update.lock"
    exec 9>"$lock_file" || _error_quit '无法创建锁文件'
    flock -n 9 || _error_quit '有并发更新在进行 (锁获取失败)'
    local tmp_out="${CLASH_CONFIG_RUNTIME}.merge.$$"
    _merge_build_runtime "$tmp_out"
    # 预结构校验
    "$BIN_YQ" '.rules | type=='"!!seq"'' "$tmp_out" >/dev/null 2>&1 || _failcat 'rules 缺失或非数组'
    # 调用外部 sanitizer (针对 tmp_out)
    local sanitizer_script="$(dirname "$CLASH_SCRIPT_DIR")/script/sanitize_runtime.sh"
    [ -f "$sanitizer_script" ] && bash "$sanitizer_script" --file "$tmp_out" --verbose || true
    # 关键 DIRECT 规则强制存在 (防止订阅端再度挟持)
    "$BIN_YQ" -i '(.rules //= [])' "$tmp_out" 2>/dev/null || true
    grep -q 'IP-CIDR,1.1.1.1/32,DIRECT' "$tmp_out" 2>/dev/null || \
        "$BIN_YQ" -i '.rules += ["IP-CIDR,1.1.1.1/32,DIRECT,no-resolve"]' "$tmp_out" 2>/dev/null || true
    grep -q 'IP-CIDR,8.8.8.8/32,DIRECT' "$tmp_out" 2>/dev/null || \
        "$BIN_YQ" -i '.rules += ["IP-CIDR,8.8.8.8/32,DIRECT,no-resolve"]' "$tmp_out" 2>/dev/null || true
    # 去重 DIRECT 规则 (及所有规则防膨胀)
    "$BIN_YQ" -i '.rules |= ( . // [] | unique )' "$tmp_out" 2>/dev/null || true
    _valid_config "$tmp_out" || _error_quit '合并后验证失败(含清洗)'
    _annotate_runtime "$tmp_out"
    mv "$tmp_out" "$CLASH_CONFIG_RUNTIME" 2>/dev/null || _error_quit '替换 runtime 失败'
    clashrestart
    _okcat '🔁' '合并+清洗完成 (单次重启)'
    _cleanup_probe_fields >/dev/null 2>&1 || true
}

# 兼容旧函数名 (外部脚本若仍调用旧名称不报错)
_merge_config_restart() { _merge_sanitize_restart "$@"; }

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
        guard                  运行 runtime 守护巡检
        health                 输出综合健康评分
        ;;
    1)
        "$BIN_YQ" -i ".secret = \"$1\"" "$CLASH_CONFIG_MIXIN" || {
            _failcat "密钥更新失败，请重新输入"
            return 1
        }
    _merge_sanitize_restart
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
    _merge_sanitize_restart && _okcat "Tun 模式已关闭"
}

_tunon() {
    _tunstatus 2>/dev/null && return 0
    "$BIN_YQ" -i '.tun.enable = true' "$CLASH_CONFIG_MIXIN"
    _merge_sanitize_restart
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

    mkdir -p "$CLASH_DIFF_DIR" 2>/dev/null || true
    # 生成合并前后 diff 报告 (P1) —— 复制旧 runtime
    local pre_runtime_copy="/tmp/runtime_before_update.$$"
    [ -f "$CLASH_CONFIG_RUNTIME" ] && cp -f "$CLASH_CONFIG_RUNTIME" "$pre_runtime_copy" 2>/dev/null || true
    # 预备: 指纹期待校验 (若不匹配将会回滚, 需要先保存下载的 RAW 指纹并比较)
    local raw_sha_pre
    if [ -f "$CLASH_CONFIG_RAW" ]; then
        raw_sha_pre=$(sha256sum "$CLASH_CONFIG_RAW" | awk '{print $1}')
    fi
    _merge_sanitize_restart && _okcat '🍃' '订阅更新成功'
    # 差异计算（若存在旧 runtime）
    if [ -f "$pre_runtime_copy" ]; then
        local ts=$(date +%Y%m%d_%H%M%S)
        local diff_file="$CLASH_DIFF_DIR/runtime_diff_${ts}.log"
        # 仅提取关键信息 (rules & dns.fallback & proxy-groups 名称) 以减少噪声
        {
            echo "# runtime diff @ $ts"
            echo "# Added / Removed rules:"
            diff -u <(grep -E '^(#|rules:|  - IP-CIDR|  - DOMAIN|  - MATCH|  - GEOIP|  - DST-PORT)' "$pre_runtime_copy" 2>/dev/null || true) \
                     <(grep -E '^(#|rules:|  - IP-CIDR|  - DOMAIN|  - MATCH|  - GEOIP|  - DST-PORT)' "$CLASH_CONFIG_RUNTIME" 2>/dev/null || true) || true
            echo
            echo "# dns.fallback changes:"
            diff -u <(grep -E '^ *fallback:' "$pre_runtime_copy" || true) <(grep -E '^ *fallback:' "$CLASH_CONFIG_RUNTIME" || true) || true
            echo
            echo "# proxy-groups name list changes:"
            diff -u <(grep -E '^ *- name:' "$pre_runtime_copy" | sed 's/type:.*//' | sort || true) \
                     <(grep -E '^ *- name:' "$CLASH_CONFIG_RUNTIME" | sed 's/type:.*//' | sort || true) || true
        } > "$diff_file" 2>/dev/null || true
        if [ -s "$diff_file" ]; then
            # 压缩保存 (gzip -9) 并写索引 (ts\tsha256(diff)\tpath.gz\tsize)
            gzip -9 -f "$diff_file" 2>/dev/null || true
            local gz_file="${diff_file}.gz"
            local diff_sha diff_size
            diff_sha=$(sha256sum "$gz_file" | awk '{print $1}')
            diff_size=$(stat -c %s "$gz_file" 2>/dev/null || echo 0)
            echo -e "$ts\t$diff_sha\t$gz_file\t$diff_size" >> "$CLASH_DIFF_INDEX_FILE" 2>/dev/null || true
            _okcat '📝' "Diff 压缩: $gz_file (${diff_size}B)"
            echo "[DIFF-$ts] $gz_file" >> "$CLASH_UPDATE_LOG" 2>/dev/null || true
            # 保留最新 30 条索引
            local keep=30
            local lines
            lines=$(wc -l < "$CLASH_DIFF_INDEX_FILE" 2>/dev/null || echo 0)
            if [ "$lines" -gt "$keep" ]; then
                # 取要删除的过期行对应文件
                local remove_count=$((lines-keep))
                head -n "$remove_count" "$CLASH_DIFF_INDEX_FILE" | awk -F '\t' '{print $3}' | xargs -r rm -f --
                # 保留尾部 keep 行
                tail -n "$keep" "$CLASH_DIFF_INDEX_FILE" >"${CLASH_DIFF_INDEX_FILE}.tmp" && mv "${CLASH_DIFF_INDEX_FILE}.tmp" "$CLASH_DIFF_INDEX_FILE"
            fi
        fi
        rm -f "$pre_runtime_copy" 2>/dev/null || true
    fi
    # 订阅指纹记录 & 验证 (URL -> sha256)
    if [ -f "$CLASH_CONFIG_RAW" ]; then
        local raw_sha line_ts expected
        raw_sha=$(sha256sum "$CLASH_CONFIG_RAW" | awk '{print $1}')
        line_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        echo -e "$line_ts\t$raw_sha\t$url" >> "$CLASH_FINGERPRINT_FILE" 2>/dev/null || true
        if [ -f "$CLASH_EXPECTED_FINGERPRINT_FILE" ]; then
            expected=$(grep -F "$url" "$CLASH_EXPECTED_FINGERPRINT_FILE" | awk '{print $2}' | head -n1 || true)
            if [ -n "$expected" ]; then
                case "$raw_sha" in
                    $expected*) _okcat '🔐' "订阅指纹匹配 (${expected})" ;;
                    *)
                       _failcat '🔐' "订阅指纹不匹配: expect $expected got ${raw_sha:0:${#expected}} -> 回滚"
                       # 回滚 raw + runtime
                       [ -f "$CLASH_CONFIG_RAW_BAK" ] && cp -f "$CLASH_CONFIG_RAW_BAK" "$CLASH_CONFIG_RAW" 2>/dev/null || true
                       [ -f "$pre_runtime_copy" ] && cp -f "$pre_runtime_copy" "$CLASH_CONFIG_RUNTIME" 2>/dev/null || true
                       clashrestart
                       echo "[ROLLBACK-$ts] fingerprint mismatch" >> "$CLASH_UPDATE_LOG" 2>/dev/null || true
                       return 1
                       ;;
                esac
            fi
        fi
    fi
    echo "$url" | tee "$CLASH_CONFIG_URL" >&/dev/null
    _okcat '✅' "[$(date +"%Y-%m-%d %H:%M:%S")] 订阅更新成功：$url" | tee -a "${CLASH_UPDATE_LOG}" >&/dev/null
    # 若近期失败较多, 立即尝试标记高失败节点
    local recent_fail
    recent_fail=$(journalctl --user -u "$BIN_KERNEL_NAME" --since "5 min ago" --no-pager 2>/dev/null | grep -c 'connect error' || echo 0)
    if [ "$recent_fail" -gt 10 ]; then
        _okcat '⚠️' "过去5分钟失败: $recent_fail -> 执行降权标记"
        _downgrade_failed_nodes 10 5
    fi
}

function clashmixin() {
    case "$1" in
    -e)
        vim "$CLASH_CONFIG_MIXIN" && {
            _merge_sanitize_restart && _okcat "配置更新成功，已重启生效"
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
    guard)
        bash "$(dirname "$CLASH_SCRIPT_DIR")/script/runtime_guard.sh" --check || true
        ;;
    health)
        _clash_health
        ;;
    downgrade)
    _downgrade_failed_nodes "$@"
        ;;
    cleanfail)
        _cleanup_fail_tags
        ;;
    diag|doctor)
        bash "$(dirname "$CLASH_SCRIPT_DIR")/script/clash_diagnose.sh" "${@:2}" || true
        ;;
    metrics)
        # metrics [--cron-install <interval-min>]  (写入 metrics 文件)
        if [ "$1" = "--cron-install" ]; then
            shift
            local interval=${1:-5}
            grep -qs 'clash metrics' "$CLASH_CRON_TAB" || echo "*/${interval} * * * * $_SHELL -i -c 'clash metrics'" >> "$CLASH_CRON_TAB"
            _okcat "已安装 metrics 定时任务 (${interval} 分) -> 查看: $CLASH_CRON_TAB"
        else
            _clash_metrics
        fi
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
        downgrade              标记/删除最近失败次数高的节点 (默认10min>=5) 支持: --since --threshold --mode drop|tag --no-switch
    cleanfail              移除分组引用中的 [FAIL] 标签
    diag | doctor          一键诊断 (脚本: clash_diagnose.sh) 支持 --fast --json
    metrics                生成 Prometheus metrics 文件
    - metrics --cron-install 5   安装每5分钟自动刷新
    - downgrade --since 15 --threshold 8 --mode drop

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

__CLASHCTL_DEFERRED_ARGS=("$@")

# 健康概要: 指纹最新条目 + 关键 DIRECT 规则状态 + 节点失败统计分级
_clash_health() {
    local latest_fp direct1 direct8 hijack fails score grade
    if [ -f "$CLASH_FINGERPRINT_FILE" ]; then
        latest_fp=$(tail -n1 "$CLASH_FINGERPRINT_FILE" | awk -F '\t' '{print $1" sha="substr($2,1,8)}')
    fi
    direct1=$(grep -q 'IP-CIDR,1.1.1.1/32,DIRECT' "$CLASH_CONFIG_RUNTIME" && echo ok || echo miss)
    direct8=$(grep -q 'IP-CIDR,8.8.8.8/32,DIRECT' "$CLASH_CONFIG_RUNTIME" && echo ok || echo miss)
    hijack=$(grep -E 'IP-CIDR,(1.1.1.1|8.8.8.8)/32,.*(PROXY|西瓜加速)' "$CLASH_CONFIG_RUNTIME" >/dev/null && echo risk || echo clean)
    # 最近 5 分钟失败节点总数
    fails=$(journalctl --user -u "$BIN_KERNEL_NAME" --since "5 min ago" --no-pager 2>/dev/null | grep -c 'connect error' || echo 0)
    # 简单评分模型
    score=100
    [ "$direct1" = miss ] && score=$((score-25))
    [ "$direct8" = miss ] && score=$((score-25))
    [ "$hijack" = risk ] && score=$((score-30))
    [ "$fails" -gt 20 ] && score=$((score-20)) || [ "$fails" -gt 5 ] && score=$((score-10))
    if   [ $score -ge 90 ]; then grade=A;
    elif [ $score -ge 75 ]; then grade=B;
    elif [ $score -ge 60 ]; then grade=C; else grade=D; fi
        _okcat "健康评分: $grade ($score)  指纹: ${latest_fp:-n/a}  DIRECT(1.1.1.1:$direct1 8.8.8.8:$direct8)  劫持:$hijack  5min失败:$fails"
        # 写 JSON 状态文件供 Prometheus node_exporter textfile collector 或外部拉取
        local now_iso
        now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    cat > "$CLASH_HEALTH_JSON" 2>/dev/null <<EOFJSON
{
    "timestamp": "$now_iso",
    "score": $score,
    "grade": "$grade",
    "fails_5m": $fails,
    "direct_rules": {"1.1.1.1": "$direct1", "8.8.8.8": "$direct8"},
    "hijack": "$hijack"
}
EOFJSON
}

# 生成 Prometheus 文本暴露格式 metrics (适配 node_exporter textfile collector)
_clash_metrics() {
    local now_epoch direct1 direct8 hijack fails score grade
    now_epoch=$(date +%s)
    direct1=$(grep -q 'IP-CIDR,1.1.1.1/32,DIRECT' "$CLASH_CONFIG_RUNTIME" && echo 1 || echo 0)
    direct8=$(grep -q 'IP-CIDR,8.8.8.8/32,DIRECT' "$CLASH_CONFIG_RUNTIME" && echo 1 || echo 0)
    hijack=$(grep -E 'IP-CIDR,(1.1.1.1|8.8.8.8)/32,.*(PROXY|西瓜加速)' "$CLASH_CONFIG_RUNTIME" >/dev/null && echo 1 || echo 0)
    fails=$(journalctl --user -u "$BIN_KERNEL_NAME" --since "5 min ago" --no-pager 2>/dev/null | grep -c 'connect error' || echo 0)
    score=100
    [ $direct1 -eq 0 ] && score=$((score-25))
    [ $direct8 -eq 0 ] && score=$((score-25))
    [ $hijack -eq 1 ] && score=$((score-30))
    [ $fails -gt 20 ] && score=$((score-20)) || [ $fails -gt 5 ] && score=$((score-10))
    grade=3 # A=3 B=2 C=1 D=0 (映射成数值)
    if   [ $score -ge 90 ]; then grade=3;
    elif [ $score -ge 75 ]; then grade=2;
    elif [ $score -ge 60 ]; then grade=1; else grade=0; fi
    # 追加运行时接口信息 (流量 / 活跃连接 / FAIL 分组数)
    _get_ui_port
    local api_base="http://127.0.0.1:${UI_PORT}"
    local secret=$("$BIN_YQ" '.secret // ""' "$CLASH_CONFIG_RUNTIME" 2>/dev/null)
    local auth_header=()
    [ -n "$secret" ] && auth_header=(-H "Authorization: Bearer $secret")
    local traffic_json conn_json proxies_json up_bytes=0 down_bytes=0 active_conn=0 groups_on_fail=0
    local have_jq=0
    command -v jq >/dev/null 2>&1 && have_jq=1
    traffic_json=$(curl -s --max-time 1 "${api_base}/traffic" "${auth_header[@]}" || echo '{}')
    if [ $have_jq -eq 1 ]; then
        up_bytes=$(echo "$traffic_json" | jq -r '.up // 0' 2>/dev/null || echo 0)
        down_bytes=$(echo "$traffic_json" | jq -r '.down // 0' 2>/dev/null || echo 0)
    else
        up_bytes=$(echo "$traffic_json" | grep -Eo '"up":[0-9]+' | head -n1 | cut -d: -f2 || echo 0)
        down_bytes=$(echo "$traffic_json" | grep -Eo '"down":[0-9]+' | head -n1 | cut -d: -f2 || echo 0)
    fi
    conn_json=$(curl -s --max-time 1 "${api_base}/connections" "${auth_header[@]}" || echo '{}')
    if [ $have_jq -eq 1 ]; then
        active_conn=$(echo "$conn_json" | jq -r '.connections | length' 2>/dev/null || echo 0)
    else
        active_conn=$(echo "$conn_json" | grep -Eo '"connections":\[[^]]*\]' | sed -E 's/.*\[(.*)\].*/\1/' | grep -c '{' 2>/dev/null || echo 0)
    fi
    proxies_json=$(curl -s --max-time 1 "${api_base}/proxies" "${auth_header[@]}" || echo '{}')
    if [ $have_jq -eq 1 ]; then
        groups_on_fail=$(echo "$proxies_json" | jq '[.proxies | to_entries[] | select(.value.type=="Selector" and (.value.now|test("\\[FAIL\\]"))) ] | length' 2>/dev/null || echo 0)
    else
        # 非 jq 模式：仅统计 now 中含 [FAIL] 的 selector
        if echo "$proxies_json" | grep -q '\[FAIL\]'; then
            groups_on_fail=$(echo "$proxies_json" | tr '\n' ' ' | sed 's/},/\n/g' | grep '"type":"Selector"' | grep '\[FAIL\]' | wc -l | awk '{print $1}')
        else
            groups_on_fail=0
        fi
    fi
    # 直接调用 guard 获取 JSON, 采样 lockWaitSeconds (即使返回非 0 也继续)
    local guard_script="$CLASH_SCRIPT_DIR/runtime_guard.sh" guard_json guard_lock_wait=0 guard_last_fix=0 have_jq
    command -v jq >/dev/null 2>&1 && have_jq=1 || have_jq=0
    if [ -x "$guard_script" ]; then
        guard_json=$(bash "$guard_script" --check --json 2>/dev/null || true)
        if [ -n "$guard_json" ]; then
            if [ $have_jq -eq 1 ]; then
                guard_lock_wait=$(echo "$guard_json" | jq -r '.lockWaitSeconds // 0' 2>/dev/null || echo 0)
                # 若 status=FIXED, 用当前 runtime mtime 作为 last_fix_timestamp (一并输出指标)
                if echo "$guard_json" | jq -e '.status=="FIXED"' >/dev/null 2>&1; then
                    guard_last_fix=$(stat -c %Y "$CLASH_CONFIG_RUNTIME" 2>/dev/null || echo 0)
                fi
            else
                guard_lock_wait=$(echo "$guard_json" | grep -Eo '"lockWaitSeconds":[0-9.]+' | head -n1 | cut -d: -f2 || echo 0)
            fi
        fi
    fi
    # 若本次未捕获 FIXED 状态, 尝试从独立 guard metrics 文件读取上次自愈时间
    if [ "${guard_last_fix:-0}" -eq 0 ]; then
        guard_metrics_file="${CLASH_GUARD_METRICS_FILE:-$CLASH_BASE_DIR/metrics_guard.prom}"
        if [ -f "$guard_metrics_file" ]; then
            guard_last_fix=$(grep -E '^clash_guard_last_fix_timestamp ' "$guard_metrics_file" | awk '{print $2}' | tail -n1 || echo 0)
        fi
    fi
    GUARD_EXTRA_METRICS=$(cat <<EOF
# HELP clash_guard_lock_wait_seconds Last observed lock wait seconds from guard check
# TYPE clash_guard_lock_wait_seconds gauge
clash_guard_lock_wait_seconds ${guard_lock_wait:-0}
$( if [ "${guard_last_fix:-0}" -gt 0 ]; then cat <<EOFIX
# HELP clash_guard_last_fix_timestamp Unix timestamp of last guard auto-fix (runtime mtime)
# TYPE clash_guard_last_fix_timestamp gauge
clash_guard_last_fix_timestamp ${guard_last_fix}
EOFIX
fi )
EOF
    )
    cat > "$CLASH_METRICS_FILE" 2>/dev/null <<EOFPM
# HELP clash_health_score Composite health score
# TYPE clash_health_score gauge
clash_health_score $score
# HELP clash_health_grade Categorical grade A=3 B=2 C=1 D=0
# TYPE clash_health_grade gauge
clash_health_grade $grade
# HELP clash_direct_rule_present Presence of DIRECT rule for critical DNS IPs (1=present)
# TYPE clash_direct_rule_present gauge
clash_direct_rule_present{ip="1.1.1.1"} $direct1
clash_direct_rule_present{ip="8.8.8.8"} $direct8
# HELP clash_dns_hijack_detected Hijack rule detected for critical DNS IPs
# TYPE clash_dns_hijack_detected gauge
clash_dns_hijack_detected $hijack
# HELP clash_upstream_failures_5m Upstream connect errors in last 5 minutes
# TYPE clash_upstream_failures_5m counter
clash_upstream_failures_5m $fails
# HELP clash_traffic_upload_bytes_total Total upload bytes reported by Clash
# TYPE clash_traffic_upload_bytes_total counter
clash_traffic_upload_bytes_total $up_bytes
# HELP clash_traffic_download_bytes_total Total download bytes reported by Clash
# TYPE clash_traffic_download_bytes_total counter
clash_traffic_download_bytes_total $down_bytes
# HELP clash_active_connections Current active connections count
# TYPE clash_active_connections gauge
clash_active_connections $active_conn
# HELP clash_selector_groups_on_fail Selector groups whose current choice contains [FAIL]
# TYPE clash_selector_groups_on_fail gauge
clash_selector_groups_on_fail $groups_on_fail
# HELP clash_metrics_timestamp_seconds Unix time metrics generated
# TYPE clash_metrics_timestamp_seconds gauge
clash_metrics_timestamp_seconds $now_epoch
${GUARD_EXTRA_METRICS}
EOFPM
    _okcat "Metrics 写入: $CLASH_METRICS_FILE"
}

# 聚合最近连接失败上游并为超阈值节点打标签/从特定分组降权
_downgrade_failed_nodes() {
    # 获取共享写锁防止与其他合并/清洗并发
    local lock_file="/tmp/.clash_update.lock"
    exec 8>"$lock_file" || { _failcat '无法创建锁文件'; return 1; }
    flock -n 8 || { _failcat '降权操作等待其他更新完成(锁冲突)'; return 1; }
    local since_min=10 threshold=5 mode=tag try_switch=1 tag_suffix='[FAIL]'
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since) since_min="$2"; shift 2;;
            --threshold) threshold="$2"; shift 2;;
            --mode) mode="$2"; shift 2;;
            --no-switch) try_switch=0; shift;;
            *) break;;
        esac
    done
    local raw bad tmp_yaml changed=0
    raw=$(journalctl --user -u "$BIN_KERNEL_NAME" --since "${since_min} min ago" --no-pager 2>/dev/null | grep 'connect error' || true)
    [ -z "$raw" ] && { _okcat "无失败记录 (since=${since_min}m)"; return 0; }
    bad=$(echo "$raw" | sed -E 's/.*error: ([^ ]+) connect error.*/\1/' | sort | uniq -c | awk -v t=$threshold '$1>=t {print $2}')
    # 回退解析：若为空，再尝试 grep -Eo
    if [ -z "$bad" ]; then
        bad=$(echo "$raw" | grep -Eo 'error: [^ ]+ connect error' | awk '{print $2}' | sort | uniq -c | awk -v t=$threshold '$1>=t {print $2}')
    fi
    [ -z "$bad" ] && { _okcat "无达到阈值节点 (阈值=${threshold})"; return 0; }
    tmp_yaml="${CLASH_CONFIG_MIXIN}.failtag.$$"
    cp -f "$CLASH_CONFIG_MIXIN" "$tmp_yaml" || return 0
    while read -r node; do
        [ -z "$node" ] && continue
        local node_esc
        node_esc=$(_escape_sed "$node")
        if [ "$mode" = tag ]; then
            sed -i -E "/- name: /! s/([[:space:]]+- $node_esc)([[:space:]]|$)/\1${tag_suffix} /" "$tmp_yaml" 2>/dev/null || true
        else
            sed -i -E "/- name: /! {/^[[:space:]]+- $node_esc([[:space:]]|$)/d}" "$tmp_yaml" 2>/dev/null || true
        fi
    done <<< "$bad"
    if ! diff -q "$CLASH_CONFIG_MIXIN" "$tmp_yaml" >/dev/null 2>&1; then
        mv "$tmp_yaml" "$CLASH_CONFIG_MIXIN"
        changed=1
    else
        rm -f "$tmp_yaml"
    fi
    if [ $changed -eq 1 ]; then
        local ts_dg action
        ts_dg=$(date +%Y%m%d_%H%M%S)
        action=$([ "$mode" = tag ] && echo TAG || echo DROP)
        echo "[DOWNGRADE-$ts_dg][$action] $(echo "$bad" | tr '\n' ' ')" >> "$CLASH_UPDATE_LOG" 2>/dev/null || true
        _okcat "已处理节点: $(echo "$bad" | tr '\n' ' ') 模式=$mode"
        _merge_sanitize_restart
        if [ $try_switch -eq 1 ]; then
            _get_ui_port
            local secret=$("$BIN_YQ" '.secret // ""' "$CLASH_CONFIG_RUNTIME" 2>/dev/null)
            local api_base="http://127.0.0.1:${UI_PORT}" hdr=()
            [ -n "$secret" ] && hdr=(-H "Authorization: Bearer $secret")
            local proxies_json have_jq=0
            command -v jq >/dev/null 2>&1 && have_jq=1
            proxies_json=$(curl -s --max-time 2 "${api_base}/proxies" "${hdr[@]}" || echo '{}')
            if [ $have_jq -eq 1 ]; then
                echo "$proxies_json" | jq -r '.proxies | to_entries[] | select(.value.type=="Selector") | [.key, .value.now] | @tsv' 2>/dev/null | while IFS=$'\t' read -r name current; do
                    # 构造候选列表 (排除 FAIL 后第一个)
                    local first_good
                    first_good=$(echo "$proxies_json" | jq -r --arg n "$name" '.proxies[$n].all | map(select(test("\\[FAIL\\]")==false))[0] // ""')
                    [ -n "$first_good" ] && [ "$first_good" != "$current" ] && \
                        curl -s -X PUT "${api_base}/proxies/${name}" -H 'Content-Type: application/json' "${hdr[@]}" \
                            --data "{\"name\":\"$first_good\"}" >/dev/null 2>&1 && _infocat "Selector $name 切换 $current -> $first_good"
                done
            else
                echo "$proxies_json" | grep '"type":"Selector"' >/dev/null || return 0
                echo "$proxies_json" | tr '\n' ' ' | sed 's/},/\n/g' | grep '"type":"Selector"' | while read -r line; do
                    local name current all first_good item
                    name=$(echo "$line" | grep -Eo '"name":"[^"]+"' | head -n1 | cut -d '"' -f4)
                    current=$(echo "$line" | grep -Eo '"now":"[^"]+"' | head -n1 | cut -d '"' -f4)
                    all=$(echo "$line" | sed -n 's/.*"all":\[\([^]]*\)\].*/\1/p')
                    [ -z "$name" ] && continue
                    first_good=""
                    IFS=',' read -ra arr <<< "$all"
                    for item in "${arr[@]}"; do
                        item=$(echo "$item" | sed 's/[" ]//g')
                        [ -z "$item" ] && continue
                        if [[ "$item" != *"[FAIL]"* ]]; then
                            first_good="$item"; break
                        fi
                    done
                    if [ -n "$first_good" ] && [ "$current" != "$first_good" ]; then
                        curl -s -X PUT "${api_base}/proxies/${name}" -H 'Content-Type: application/json' "${hdr[@]}" \
                            --data "{\"name\":\"$first_good\"}" >/dev/null 2>&1 && \
                            _infocat "Selector $name 切换 $current -> $first_good"
                    fi
                done
            fi
        fi
    else
        _okcat '无需更新 (已有标记或无差异)'
    fi
}

# 清理所有 [FAIL] 标记 (仅移除标签, 不改排序) 并记录日志
_cleanup_fail_tags() {
    local lock_file="/tmp/.clash_update.lock"
    exec 8>"$lock_file" || { _failcat '无法创建锁文件'; return 1; }
    flock -n 8 || { _failcat '清理操作等待其他更新完成(锁冲突)'; return 1; }
    [ -f "$CLASH_CONFIG_MIXIN" ] || { _failcat '缺少 mixin'; return 1; }
    grep '\[FAIL\]' "$CLASH_CONFIG_MIXIN" >/dev/null 2>&1 || { _okcat '无 [FAIL] 标签'; return 0; }
    local tmp="${CLASH_CONFIG_MIXIN}.cleanfail.$$"
    # 仅对 proxy-groups 段列表项移除标签，避免误伤其它注释/上下文
    awk 'BEGIN{inpg=0} /^proxy-groups:/ {inpg=1; print; next} /^[^ \t-]/ {inpg=0; print; next} { if(inpg && $0 ~ /^ *-/){ gsub(/\[FAIL\] ?/,"",$0); print; next } print }' "$CLASH_CONFIG_MIXIN" > "$tmp" 2>/dev/null || return 1
    if ! diff -q "$CLASH_CONFIG_MIXIN" "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$CLASH_CONFIG_MIXIN"
        local ts_cf
        ts_cf=$(date +%Y%m%d_%H%M%S)
        echo "[CLEANFAIL-$ts_cf]" >> "$CLASH_UPDATE_LOG" 2>/dev/null || true
        _okcat '已移除所有 [FAIL] 标签'
    _merge_sanitize_restart
    else
        rm -f "$tmp"
    fi
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

# 入口: 放在所有函数之后，确保定义已加载。
if [[ "${BASH_SOURCE[0]}" == "$0" ]] && [ ${#__CLASHCTL_DEFERRED_ARGS[@]} -gt 0 ]; then
    clashctl "${__CLASHCTL_DEFERRED_ARGS[@]}"
    exit $?
fi
