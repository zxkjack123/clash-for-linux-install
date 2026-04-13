#!/usr/bin/env bash
# shellcheck disable=SC2148
# shellcheck disable=SC2034
# shellcheck disable=SC2155
[ -n "$BASH_VERSION" ] && set +o noglob
[ -n "${ZSH_VERSION:-}" ] && setopt glob no_nomatch || true

# 如果作为库被严格模式脚本引用 (set -u), 且未显式设置变量, 暂时关闭 -u 以避免未绑定变量终止
[ "${CLASH_LIB_MODE:-0}" = 1 ] && set +u || true

URL_GH_PROXY='https://gh-proxy.com/'
URL_CLASH_UI="http://board.zash.run.place"

SCRIPT_BASE_DIR='./script'
SCRIPT_FISH="${SCRIPT_BASE_DIR}/clashctl.fish"

RESOURCES_BASE_DIR='./resources'
RESOURCES_BIN_DIR="${RESOURCES_BASE_DIR}/bin"
RESOURCES_CONFIG="${RESOURCES_BASE_DIR}/config.yaml"
RESOURCES_CONFIG_MIXIN="${RESOURCES_BASE_DIR}/mixin.yaml"

ZIP_BASE_DIR="${RESOURCES_BASE_DIR}/zip"
ZIP_CLASH=$(find "$ZIP_BASE_DIR" -maxdepth 1 -type f -name 'clash*' -print -quit 2>/dev/null || true)
ZIP_MIHOMO=$(find "$ZIP_BASE_DIR" -maxdepth 1 -type f -name 'mihomo*' -print -quit 2>/dev/null || true)
ZIP_YQ="${ZIP_BASE_DIR}/yq_linux_amd64.tar.gz"
ZIP_SUBCONVERTER=$(find "$ZIP_BASE_DIR" -maxdepth 1 -type f -name 'subconverter*' -print -quit 2>/dev/null || true)
ZIP_UI="${ZIP_BASE_DIR}/yacd.tar.xz"

# Use user's home directory for installation.
# Avoid eval where possible; fall back only if necessary for very minimal systems.
USER_HOME="${HOME:-}"
if [ -z "${USER_HOME}" ]; then
    _u_candidate="${SUDO_USER:-${USER:-}}"
    if command -v getent >/dev/null 2>&1; then
        USER_HOME=$(getent passwd "${_u_candidate}" 2>/dev/null | cut -d: -f6 || true)
    fi
fi
if [ -z "${USER_HOME}" ]; then
    # Fallback: parse /etc/passwd without using eval (avoid injection via USER).
    _u_candidate="${SUDO_USER:-${USER:-}}"
    if [ -n "${_u_candidate}" ] && [ -r /etc/passwd ]; then
        # Only use a safe username-like string.
        if [[ "${_u_candidate}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            USER_HOME=$(awk -F: -v u="${_u_candidate}" '($1==u){print $6; exit}' /etc/passwd 2>/dev/null || true)
        fi
    fi
fi
if [ -z "${USER_HOME}" ]; then
    # Last resort: rely on shell's tilde expansion for the *current* user (no eval).
    USER_HOME=$(cd ~ 2>/dev/null && pwd || true)
fi
if [ -z "${USER_HOME}" ]; then
    # Conservative fallback for common layouts.
    _u_candidate="${SUDO_USER:-${USER:-}}"
    if [ -n "${_u_candidate}" ] && [[ "${_u_candidate}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        [ -d "/home/${_u_candidate}" ] && USER_HOME="/home/${_u_candidate}"
        [ -z "${USER_HOME}" ] && [ -d "/Users/${_u_candidate}" ] && USER_HOME="/Users/${_u_candidate}"
    fi
    [ -z "${USER_HOME}" ] && [ -d /root ] && USER_HOME=/root
fi
unset _u_candidate 2>/dev/null || true
CLASH_BASE_DIR="${USER_HOME}/.local/share/clash"
CLASH_SCRIPT_DIR="${CLASH_BASE_DIR}/$(basename "$SCRIPT_BASE_DIR")"
CLASH_CONFIG_URL="${CLASH_BASE_DIR}/url"
CLASH_CONFIG_RAW="${CLASH_BASE_DIR}/$(basename "$RESOURCES_CONFIG")"
CLASH_CONFIG_RAW_BAK="${CLASH_CONFIG_RAW}.bak"
CLASH_CONFIG_MIXIN="${CLASH_BASE_DIR}/$(basename "$RESOURCES_CONFIG_MIXIN")"
CLASH_CONFIG_RUNTIME="${CLASH_BASE_DIR}/runtime.yaml"
CLASH_UPDATE_LOG="${CLASH_BASE_DIR}/clashupdate.log"
CLASH_DIFF_DIR="${CLASH_BASE_DIR}/diff-history"
CLASH_FINGERPRINT_FILE="${CLASH_BASE_DIR}/subscription_fingerprints.tsv"
CLASH_EXPECTED_FINGERPRINT_FILE="${CLASH_BASE_DIR}/subscription_expected_fingerprints.tsv"
CLASH_DIFF_INDEX_FILE="${CLASH_DIFF_DIR}/index.tsv"
CLASH_HEALTH_JSON="${CLASH_BASE_DIR}/health.json"
CLASH_METRICS_FILE="${CLASH_BASE_DIR}/metrics.prom"

_set_var() {
    local user=$USER
    local home=$HOME

    [ -n "${BASH_VERSION:-}" ] && {
        _SHELL=bash
    }
    [ -n "${ZSH_VERSION:-}" ] && {
        _SHELL=zsh
    }
    [ -n "${fish_version:-}" ] && {
        _SHELL=fish
    }

    # rc文件路径
    command -v bash >&/dev/null && {
        SHELL_RC_BASH="${home}/.bashrc"
    }
    command -v zsh >&/dev/null && {
        SHELL_RC_ZSH="${home}/.zshrc"
    }
    command -v fish >&/dev/null && {
        SHELL_RC_FISH="${home}/.config/fish/conf.d/clashctl.fish"
    }

    # 定时任务路径 - use user crontab
    CLASH_CRON_TAB="${home}/.crontab"
}
_set_var

# shellcheck disable=SC2120
_set_bin() {
    local bin_base_dir="${CLASH_BASE_DIR}/bin"
    [ -n "$1" ] && bin_base_dir=$1
    BIN_CLASH="${bin_base_dir}/clash"
    BIN_MIHOMO="${bin_base_dir}/mihomo"
    BIN_YQ="${bin_base_dir}/yq"
    BIN_SUBCONVERTER_DIR="${bin_base_dir}/subconverter"
    BIN_SUBCONVERTER_CONFIG="$BIN_SUBCONVERTER_DIR/pref.yml"
    BIN_SUBCONVERTER_PORT="25500"
    BIN_SUBCONVERTER="${BIN_SUBCONVERTER_DIR}/subconverter"
    BIN_SUBCONVERTER_LOG="${BIN_SUBCONVERTER_DIR}/latest.log"
    BIN_KERNEL="$BIN_MIHOMO"

    [ -f "$BIN_CLASH" ] && {
        BIN_KERNEL=$BIN_CLASH
    }
    [ -f "$BIN_MIHOMO" ] && {
        BIN_KERNEL=$BIN_MIHOMO
    }
    BIN_KERNEL_NAME=$(basename "$BIN_KERNEL")
}
_set_bin

_clean_rc_hooks() {
    for rc in "$SHELL_RC_BASH" "$SHELL_RC_ZSH"; do
        [ -n "$rc" ] && [ -f "$rc" ] || continue
        sed -i "/# >>> clashctl auto-start >>>/,/# <<< clashctl auto-start <<</d" "$rc" 2>/dev/null || true
        sed -i "\|$CLASH_SCRIPT_DIR|d" "$rc" 2>/dev/null || true
    done
    [ -n "$SHELL_RC_FISH" ] && rm -f "$SHELL_RC_FISH" 2>/dev/null || true
}

_set_rc() {
    # New behaviour:
    #   - "unset": remove legacy auto-start hooks from shell RCs and fish conf.d.
    #   - default (install/upgrade): clean old hooks, install fish helper, but DO NOT
    #     inject any bash/zsh snippet or run watch_proxy/clashon automatically.
    if [ "${1:-}" = "unset" ]; then
        _clean_rc_hooks
        return
    fi

    # On fresh install / upgrade, proactively clean any legacy RC snippets that
    # may still be calling watch_proxy/clashon on every shell startup.
    _clean_rc_hooks

    # Keep fish integration lightweight: just install the function wrapper into
    # conf.d so fish users still have `clash`/`mihomo` commands available.
    [ -n "$SHELL_RC_FISH" ] && /usr/bin/install "$SCRIPT_FISH" "$SHELL_RC_FISH"

    # Do not auto-edit bash/zsh RC anymore. Point users to the best-practice doc
    # for an optional lightweight proxy env + lazy helper stubs.
    _okcat '📄' "已清理旧的 shell 自动注入配置 (不再在每个 shell 启动时运行 watch_proxy)"
    _okcat '💡' "如需在交互 shell 中导出 http_proxy/ALL_PROXY, 请参考 docs/development/CLASH_PROXY_STARTUP_BEST_PRACTICES.md 手动添加轻量级片段"
}

# 默认集成、安装mihomo内核
# 移除/删除mihomo：下载安装clash内核
function _get_kernel() {
    [ -f "$ZIP_CLASH" ] && {
        ZIP_KERNEL=$ZIP_CLASH
        BIN_KERNEL=$BIN_CLASH
    }

    [ -f "$ZIP_MIHOMO" ] && {
        ZIP_KERNEL=$ZIP_MIHOMO
        BIN_KERNEL=$BIN_MIHOMO
    }

    [ ! -f "$ZIP_MIHOMO" ] && [ ! -f "$ZIP_CLASH" ] && {
        local arch=$(uname -m)
        _failcat "${ZIP_BASE_DIR}：未检测到可用的内核压缩包"
        _download_clash "$arch"
        ZIP_KERNEL=$ZIP_CLASH
        BIN_KERNEL=$BIN_CLASH
    }

    BIN_KERNEL_NAME=$(basename "$BIN_KERNEL")
    _okcat "安装内核：$BIN_KERNEL_NAME"
}

_get_random_port() {
    _clash_reserved_ports_list() {
        # Space-separated list of reserved ports to avoid when allocating random ports.
        # Users can provide either:
        #   - CLASH_RESERVED_PORTS="7890,7891,9090" (comma/space separated)
        #   - CLASH_RESERVED_HTTP_PORT / CLASH_RESERVED_SOCKS_PORT / CLASH_RESERVED_UI_PORT
        local s="${CLASH_RESERVED_PORTS:-}"
        s=${s//,/ }
        # Append explicit vars (if set) to the list.
        [ -n "${CLASH_RESERVED_HTTP_PORT:-}" ] && s+=" ${CLASH_RESERVED_HTTP_PORT}"
        [ -n "${CLASH_RESERVED_SOCKS_PORT:-}" ] && s+=" ${CLASH_RESERVED_SOCKS_PORT}"
        [ -n "${CLASH_RESERVED_UI_PORT:-}" ] && s+=" ${CLASH_RESERVED_UI_PORT}"
        # Trim and normalize.
        echo "$s" | tr -s ' ' | sed 's/^ *//; s/ *$//'
    }

    _clash_is_reserved_port() {
        local p="${1:-}" rp
        [ -n "$p" ] || return 1
        for rp in $(_clash_reserved_ports_list); do
            [ -n "$rp" ] || continue
            [ "$p" = "$rp" ] && return 0
        done
        return 1
    }

    local attempts=0 randomPort
    while [ "$attempts" -lt 50 ]; do
        randomPort=$(shuf -i 1024-65535 -n 1)
        _clash_is_reserved_port "$randomPort" && { attempts=$((attempts + 1)); continue; }
        ! _is_bind "$randomPort" && { echo "$randomPort"; return 0; }
        attempts=$((attempts + 1))
    done
    _error_quit "无法分配空闲端口 (尝试 50 次失败)"
}

# Port assignment policy (stability vs auto-healing)
#
# Problem this solves:
# - Some code paths (e.g. systemd oneshot that applies GNOME proxy settings)
#   call _get_proxy_port while mihomo is already running.
# - If we silently rewrite runtime.yaml to a random port due to a transient
#   detection or occupancy issue, GNOME may be pointed at a non-listening port,
#   causing "network broken" symptoms.
#
# Policy:
# - CLASH_PORT_POLICY=strict : never mutate runtime.yaml ports; fail fast on conflict.
# - CLASH_PORT_POLICY=random : keep legacy behavior (mutate runtime.yaml to a free port).
# - CLASH_PORT_POLICY=auto (default): if runtime has system-proxy.enable=true -> strict,
#   otherwise random.
_clash_port_policy() {
    local policy="${CLASH_PORT_POLICY:-auto}"
    case "$policy" in
        strict|random) printf '%s' "$policy"; return 0 ;;
        auto|"") : ;;
        *) printf '%s' "auto"; return 0 ;;
    esac

    # If the user explicitly reserved ports, prefer strict to avoid silent drift.
    if [ -n "${CLASH_RESERVED_PORTS:-}" ] || [ -n "${CLASH_RESERVED_HTTP_PORT:-}" ] || [ -n "${CLASH_RESERVED_SOCKS_PORT:-}" ] || [ -n "${CLASH_RESERVED_UI_PORT:-}" ]; then
        printf '%s' strict
        return 0
    fi

    # Auto: if the user enabled system-proxy, prefer strict (stable ports).
    local sp="false"
    if [ -x "${BIN_YQ:-}" ] && [ -f "${CLASH_CONFIG_RUNTIME:-}" ]; then
        sp=$("$BIN_YQ" -r '."system-proxy".enable // false' "$CLASH_CONFIG_RUNTIME" 2>/dev/null || echo false)
    fi
    # Strip quotes from yq output and normalize case.
    sp=$(printf '%s' "$sp" | tr -d "\"'" | tr '[:upper:]' '[:lower:]')
    if [ "$sp" = true ]; then
        printf '%s' strict
    else
        printf '%s' random
    fi
}

_port_conflict_report() {
    # Best-effort diagnostics for port conflicts.
    local port="${1:-}"
    [ -n "$port" ] || return 0
    {
        echo "[port] 冲突端口: $port"
        ss -ltnp 2>/dev/null | grep -E ":${port}\\b" || true
    } >&2
}

function _get_proxy_port() {
    # Detect actual proxy ports from runtime.yaml.
    # - mixed-port: provides HTTP + SOCKS on the same port
    # - port + socks-port: split mode
    local mixed_port http_port socks_port

    mixed_port=$("$BIN_YQ" -r '."mixed-port" // ""' "$CLASH_CONFIG_RUNTIME" 2>/dev/null || true)
    mixed_port=${mixed_port//$'\n'/}
    mixed_port=${mixed_port//\"/}
    mixed_port=${mixed_port//\'/}

    if [[ "$mixed_port" =~ ^[0-9]+$ ]]; then
        MIXED_PORT="$mixed_port"
        SOCKS_PORT="$mixed_port"

        _is_already_in_use "$MIXED_PORT" "$BIN_KERNEL_NAME" && {
            local policy
            policy=$(_clash_port_policy)
            if [ "$policy" = strict ]; then
                _failcat '🎯' "端口占用：${MIXED_PORT} (策略=strict，禁止随机改端口；请释放端口或修改配置)" || true
                _port_conflict_report "$MIXED_PORT"
                return 1
            fi

            local newPort=$(_get_random_port)
            local msg="端口占用：${MIXED_PORT} 🎲 随机分配：$newPort"
            "$BIN_YQ" -i '."mixed-port" = '"$newPort" "$CLASH_CONFIG_RUNTIME"
            MIXED_PORT=$newPort
            SOCKS_PORT=$newPort
            _failcat '🎯' "$msg" || true
        }
        return 0
    fi

    http_port=$("$BIN_YQ" -r '.port // ""' "$CLASH_CONFIG_RUNTIME" 2>/dev/null || true)
    http_port=${http_port//$'\n'/}
    http_port=${http_port//\"/}
    http_port=${http_port//\'/}

    socks_port=$("$BIN_YQ" -r '."socks-port" // ""' "$CLASH_CONFIG_RUNTIME" 2>/dev/null || true)
    socks_port=${socks_port//$'\n'/}
    socks_port=${socks_port//\"/}
    socks_port=${socks_port//\'/}

    [[ "$http_port" =~ ^[0-9]+$ ]] || http_port=7890
    MIXED_PORT="$http_port"
    [[ "$socks_port" =~ ^[0-9]+$ ]] && SOCKS_PORT="$socks_port" || SOCKS_PORT=""

    # If ports are already in use by other process, reassign to a random available one.
    _is_already_in_use "$MIXED_PORT" "$BIN_KERNEL_NAME" && {
        local policy
        policy=$(_clash_port_policy)
        if [ "$policy" = strict ]; then
            _failcat '🎯' "端口占用：${MIXED_PORT} (策略=strict，禁止随机改端口；请释放端口或修改配置)" || true
            _port_conflict_report "$MIXED_PORT"
            return 1
        fi

        local newPort=$(_get_random_port)
        local msg="端口占用：${MIXED_PORT} 🎲 随机分配：$newPort"
        "$BIN_YQ" -i '.port = '"$newPort" "$CLASH_CONFIG_RUNTIME"
        MIXED_PORT=$newPort
        _failcat '🎯' "$msg" || true
    }
    if [[ -n "${SOCKS_PORT:-}" ]]; then
        _is_already_in_use "$SOCKS_PORT" "$BIN_KERNEL_NAME" && {
            local policy
            policy=$(_clash_port_policy)
            if [ "$policy" = strict ]; then
                _failcat '🎯' "端口占用：${SOCKS_PORT} (策略=strict，禁止随机改端口；请释放端口或修改配置)" || true
                _port_conflict_report "$SOCKS_PORT"
                return 1
            fi

            local newPort=$(_get_random_port)
            local msg="端口占用：${SOCKS_PORT} 🎲 随机分配：$newPort"
            "$BIN_YQ" -i '."socks-port" = '"$newPort" "$CLASH_CONFIG_RUNTIME"
            SOCKS_PORT=$newPort
            _failcat '🎯' "$msg" || true
        }
    fi
}

function _get_ui_port() {
    local ext_addr ext_host ext_port
    ext_addr=$("$BIN_YQ" -r '.external-controller // ""' "$CLASH_CONFIG_RUNTIME" 2>/dev/null || echo "")
    ext_addr=${ext_addr//$'\n'/}
    ext_addr=${ext_addr//\"/}
    ext_addr=${ext_addr//\'/}

    # Default to localhost-only.
    if [ -z "$ext_addr" ]; then
        ext_addr="127.0.0.1:9090"
    fi

    ext_port=${ext_addr##*:}
    ext_host=${ext_addr%:*}
    [ -z "$ext_host" ] && ext_host="127.0.0.1"
    UI_PORT=${ext_port:-9090}

    _is_already_in_use "$UI_PORT" "$BIN_KERNEL_NAME" && {
        local policy
        policy=$(_clash_port_policy)
        if [ "$policy" = strict ]; then
            _failcat '🎯' "端口占用：${UI_PORT} (策略=strict，禁止随机改端口；请释放端口或修改 external-controller)" || true
            _port_conflict_report "$UI_PORT"
            return 1
        fi

        local newPort=$(_get_random_port)
        local msg="端口占用：${UI_PORT} 🎲 随机分配：$newPort"
        "$BIN_YQ" -i ".external-controller = \"${ext_host}:${newPort}\"" "$CLASH_CONFIG_RUNTIME"
        UI_PORT=$newPort
        _failcat '🎯' "$msg" || true
    }
}

_get_color() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf "\e[38;2;%d;%d;%dm" "$r" "$g" "$b"
}
_get_color_msg() {
    local color=$(_get_color "$1")
    local msg=$2
    local reset="\033[0m"
    printf "%b%s%b\n" "$color" "$msg" "$reset"
}

function _okcat() {
    local color=#c8d6e5
    local emoji=😼
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _get_color_msg "$color" "$msg" && return 0
}

function _failcat() {
    local color=#fd79a8
    local emoji=😾
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _get_color_msg "$color" "$msg" >&2 && return 1
}

function _quit() {
    exec "$_SHELL" -i
}

function _error_quit() {
    # 当作为库被其它脚本 (如 runtime_guard.sh) 调用时, 通过设置 CLASH_LIB_MODE=1 避免 exec 交互壳导致主逻辑中断
    [ $# -gt 0 ] && {
        local color=#f92f60
        local emoji=📢
        [ $# -gt 1 ] && emoji=$1 && shift
        local msg="${emoji} $1"
        _get_color_msg "$color" "$msg"
    }
    if [ "${CLASH_LIB_MODE:-0}" = 1 ]; then
        return 1
    fi
    # In non-interactive contexts (cron/systemd/background/piped) or when explicitly requested,
    # do NOT exec into an interactive shell. That behavior is convenient when sourced
    # interactively, but looks like a "hang" for scripted usage.
    if [ "${CLASH_ERROR_MODE:-}" = "exit" ] || [ ! -t 0 ]; then
        exit 1
    fi
    exec "$_SHELL" -i
}

_is_bind() {
    local port=$1
    { ss -lnptu || netstat -lnptu; } 2>/dev/null | grep ":${port}\b"
}

_is_already_in_use() {
    local port=$1
    local progress=$2
    _is_bind "$port" | grep -qs -v "$progress"
}

function _valid_env() {
    [ -z "${ZSH_VERSION:-}" ] && [ -z "${BASH_VERSION:-}" ] && _error_quit "仅支持：bash、zsh"
    [ "$(ps -p 1 -o comm=)" != "systemd" ] && _error_quit "系统不具备 systemd"
    # Create user systemd directory if it doesn't exist
    mkdir -p "${USER_HOME}/.config/systemd/user"
    mkdir -p "${USER_HOME}/.local/share"
}

function _valid_config() {
    [ -e "$1" ] && [ "$(wc -l <"$1")" -gt 1 ] && {
        local msg
        local -a cmd
        cmd=("$BIN_KERNEL" -d "$(dirname "$1")" -f "$1" -t)
        msg=$("${cmd[@]}" 2>&1) || {
            printf '%s\n' "$msg" >&2
            echo "$msg" | grep -qs "unsupport proxy type" && _error_quit "不支持的代理协议，请安装 mihomo 内核"
        }
    }
}

_download_clash() {
    local arch=$1
    local url sha256sum
    case "$arch" in
    x86_64)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-amd64-2023.08.17.gz
        sha256sum='92380f053f083e3794c1681583be013a57b160292d1d9e1056e7fa1c2d948747'
        ;;
    *86*)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-386-2023.08.17.gz
        sha256sum='254125efa731ade3c1bf7cfd83ae09a824e1361592ccd7c0cccd2a266dcb92b5'
        ;;
    armv*)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-armv5-2023.08.17.gz
        sha256sum='622f5e774847782b6d54066f0716114a088f143f9bdd37edf3394ae8253062e8'
        ;;
    aarch64)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-arm64-2023.08.17.gz
        sha256sum='c45b39bb241e270ae5f4498e2af75cecc0f03c9db3c0db5e55c8c4919f01afdd'
        ;;
    *)
        _error_quit "未知的架构版本：$arch，请自行下载对应版本至 ${ZIP_BASE_DIR} 目录下：https://downloads.clash.wiki/ClashPremium/"
        ;;
    esac

    _okcat '⏳' "正在下载：clash：${arch} 架构..."
    local clash_zip="${ZIP_BASE_DIR}/$(basename $url)"
    # Avoid long hangs on stalled downloads.
    local max_time=${CLASH_KERNEL_DOWNLOAD_MAX_TIME:-300}
    local speed_time=${CLASH_KERNEL_DOWNLOAD_SPEED_TIME:-15}
    local speed_limit=${CLASH_KERNEL_DOWNLOAD_SPEED_LIMIT:-1024}
    curl \
        --progress-bar \
        --show-error \
        --fail \
        --insecure \
        --connect-timeout 15 \
        --max-time "$max_time" \
        --speed-time "$speed_time" \
        --speed-limit "$speed_limit" \
        --retry 1 \
        --output "$clash_zip" \
        "$url"
    printf '%s  %s\n' "$sha256sum" "$clash_zip" | sha256sum -c ||
        _error_quit "下载失败：请自行下载对应版本至 ${ZIP_BASE_DIR} 目录下：https://downloads.clash.wiki/ClashPremium/"
}

_download_raw_config() {
    local dest=$1
    local url=$2
    local agent='clash-verge/v2.0.4'
    # NOTE:
    # - connect-timeout only covers DNS+TCP handshake; some subscription servers may accept
    #   the connection and then stall the response body, which previously caused "clash update"
    #   to appear hung for hours.
    # - Provide sane total timeouts with env overrides.
    local max_time=${CLASH_SUBSCRIPTION_MAX_TIME:-45}
    local speed_time=${CLASH_SUBSCRIPTION_SPEED_TIME:-15}
    local speed_limit=${CLASH_SUBSCRIPTION_SPEED_LIMIT:-1024}
    curl \
        --silent \
        --show-error \
        --location \
        --fail \
        --insecure \
        --connect-timeout 4 \
        --max-time "$max_time" \
        --speed-time "$speed_time" \
        --speed-limit "$speed_limit" \
        --retry 1 \
        --user-agent "$agent" \
        --output "$dest" \
        "$url" ||
        wget \
            --no-verbose \
            --no-check-certificate \
            --timeout 10 \
            --tries 2 \
            --waitretry 1 \
            --user-agent "$agent" \
            --output-document "$dest" \
            "$url"
}
_download_convert_config() {
    local dest=$1
    local url=$2
    _start_convert
    local convert_url=$(
        target='clash'
        base_url="http://127.0.0.1:${BIN_SUBCONVERTER_PORT}/sub"
        curl \
            --get \
            --silent \
            --show-error \
            --connect-timeout 1 \
            --max-time 3 \
            --output /dev/null \
            --data-urlencode "target=$target" \
            --data-urlencode "url=$url" \
            --write-out '%{url_effective}' \
            "$base_url"
    )
    _download_raw_config "$dest" "$convert_url"
    _stop_convert
}
function _download_config() {
    local dest=$1
    local url=$2
    [ "${url:0:4}" = 'file' ] && return 0
    _download_raw_config "$dest" "$url" || return 1
    _okcat '🍃' '下载成功：内核验证配置...'
    _valid_config "$dest" || {
        _failcat '🍂' "验证失败：尝试订阅转换..."
        _download_convert_config "$dest" "$url" || _failcat '🍂' "转换失败：请检查日志：$BIN_SUBCONVERTER_LOG"
    }
}

_start_convert() {
    _is_already_in_use "$BIN_SUBCONVERTER_PORT" 'subconverter' && {
        local newPort=$(_get_random_port)
        _failcat '🎯' "端口占用：$BIN_SUBCONVERTER_PORT 🎲 随机分配：$newPort"
        [ ! -e "$BIN_SUBCONVERTER_CONFIG" ] && {
            /bin/cp -f "$BIN_SUBCONVERTER_DIR/pref.example.yml" "$BIN_SUBCONVERTER_CONFIG"
        }
        "$BIN_YQ" -i ".server.port = $newPort" "$BIN_SUBCONVERTER_CONFIG"
        BIN_SUBCONVERTER_PORT=$newPort
    }
    local start=$(date +%s)
    local startup_timeout="${CLASH_SUBCONVERTER_START_TIMEOUT:-10}"
    # 子shell运行，屏蔽kill时的输出
    ("$BIN_SUBCONVERTER" 2>&1 | tee "$BIN_SUBCONVERTER_LOG" >/dev/null &)
    while ! _is_bind "$BIN_SUBCONVERTER_PORT" >&/dev/null; do
        sleep 1s
        local now=$(date +%s)
        [ $((now - start)) -gt "$startup_timeout" ] && _error_quit "订阅转换服务未启动，请检查日志：$BIN_SUBCONVERTER_LOG"
    done
}
_stop_convert() {
    pkill -9 -f "$BIN_SUBCONVERTER" >&/dev/null
}
