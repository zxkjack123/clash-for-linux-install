#!/usr/bin/env bash
# load_env.sh
# 统一的环境变量加载函数
# 用法: source "$(dirname "$0")/load_env.sh"

# Note:
# - This file is commonly sourced by scripts using `set -e`.
# - Therefore, it MUST NOT return non-zero just because `.env` is missing.
#   Missing `.env` is a valid state (use defaults).

# 查找 .env 文件（向上递归查找）
find_env_file() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.env" ]]; then
            echo "$dir/.env"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# 加载 .env 配置
load_env_config() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local parent_dir="$(dirname "$script_dir")"
    local env_file=""
    
    # 优先级: 1. 当前目录 2. 父目录 3. 递归查找
    if [[ -f "$script_dir/.env" ]]; then
        env_file="$script_dir/.env"
    elif [[ -f "$parent_dir/.env" ]]; then
        env_file="$parent_dir/.env"
    else
        env_file=$(find_env_file "$script_dir" 2>/dev/null || echo "")
    fi
    
    if [[ -n "$env_file" && -f "$env_file" ]]; then
        # 使用 set -a 自动导出所有变量
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a

        export ENV_FILE_LOADED=1
        export ENV_FILE_PATH="$env_file"
        
        # 记录加载成功（仅在详细模式下）
        [[ "${VERBOSE:-0}" == "1" ]] && echo "[INFO] 已加载配置: $env_file" >&2
        return 0
    else
        # 没有找到 .env 文件，使用默认配置
        [[ "${VERBOSE:-0}" == "1" ]] && echo "[WARN] 未找到 .env 配置文件，使用默认配置" >&2
        export ENV_FILE_LOADED=0
        export ENV_FILE_PATH=""
        # IMPORTANT: Do not fail when `.env` is absent.
        return 0
    fi
}

# ------------------------------
# Clash controller/secret helpers
# ------------------------------

clash_runtime_file() {
    printf '%s' "${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}"
}

clash_yq_bin() {
    # Prefer repo/bundled yq when available, then PATH.
    # Output: absolute path to yq binary, or empty string.
    if [[ -n "${YQ_BIN:-}" && -x "${YQ_BIN}" ]]; then
        printf '%s' "${YQ_BIN}"
        return 0
    fi

    local c
    for c in \
        "$HOME/.local/share/clash/bin/yq" \
        "$HOME/.local/share/mihomo/bin/yq" \
        "$HOME/.local/bin/yq" \
        "/usr/local/bin/yq" \
        "/usr/bin/yq"; do
        if [[ -x "$c" ]]; then
            printf '%s' "$c"
            return 0
        fi
    done

    if command -v yq >/dev/null 2>&1; then
        command -v yq
        return 0
    fi

    printf ''
    return 0
}

clash_detect_controller_url() {
    # Output: normalized URL like http://127.0.0.1:9090
    # Best-effort; never fails.
    local runtime candidate host port default
    runtime="$(clash_runtime_file)"
    default="http://127.0.0.1:9090"
    candidate=""

    [[ -f "$runtime" ]] || { echo "$default"; return 0; }

    local yq_bin
    yq_bin="$(clash_yq_bin)"
    if [[ -n "$yq_bin" ]]; then
        candidate=$($yq_bin -r '."external-controller" // ""' "$runtime" 2>/dev/null || true)
    fi
    if [[ -z "$candidate" ]]; then
        candidate=$(grep -E '^ *external-controller:' "$runtime" 2>/dev/null | tail -n1 | cut -d':' -f2- | tr -d ' "\t\r' || true)
    fi

    candidate=${candidate//$'\n'/}
    candidate=${candidate//\"/}
    candidate=${candidate//\'/}
    candidate=${candidate//[[:space:]]/}

    [[ -z "$candidate" ]] && { echo "$default"; return 0; }
    if [[ "$candidate" == http*://* ]]; then
        echo "$candidate"; return 0
    fi

    # Accept ":PORT" or "HOST:PORT"
    if [[ "$candidate" == :* ]]; then
        host="127.0.0.1"
        port="${candidate#:}"
    else
        host="${candidate%:*}"
        port="${candidate##*:}"
    fi

    [[ -z "$port" ]] && port=9090
    case "$host" in
        ""|"0.0.0.0"|"::") host="127.0.0.1";;
    esac
    echo "http://${host}:${port}"
}

clash_detect_secret() {
    # Output: secret string (may be empty)
    local runtime secret
    runtime="$(clash_runtime_file)"
    secret=""

    [[ -f "$runtime" ]] || { echo ""; return 0; }
    local yq_bin
    yq_bin="$(clash_yq_bin)"
    if [[ -n "$yq_bin" ]]; then
        secret=$($yq_bin -r '.secret // ""' "$runtime" 2>/dev/null || true)
    fi
    if [[ -z "$secret" ]]; then
        secret=$(grep -E '^ *secret:' "$runtime" 2>/dev/null | tail -n1 | cut -d':' -f2- | tr -d ' "\t\r' || true)
    fi
    secret=${secret//$'\n'/}
    secret=${secret//\"/}
    secret=${secret//\'/}
    printf '%s' "$secret"
}

clash_auth_header() {
    # Output: "Authorization: Bearer ..." or empty
    [[ -n "${CLASH_SECRET:-}" ]] && printf 'Authorization: Bearer %s' "$CLASH_SECRET" || true
}

clash_env_bootstrap() {
    # 1) Backward-compat: map legacy env vars -> CLASH_SECRET (prefer CLASH_SECRET)
    if [[ -z "${CLASH_SECRET:-}" ]]; then
        if [[ -n "${CLASH_API_SECRET:-}" ]]; then
            export CLASH_SECRET="$CLASH_API_SECRET"
        elif [[ -n "${API_SECRET:-}" ]]; then
            export CLASH_SECRET="$API_SECRET"
        fi
    fi

    # 2) Auto-detect controller/secret from runtime.yaml if still unset
    if [[ -z "${CLASH_API:-}" ]]; then
        export CLASH_API
        CLASH_API="$(clash_detect_controller_url)"
    fi
    if [[ -z "${CLASH_SECRET:-}" ]]; then
        export CLASH_SECRET
        CLASH_SECRET="$(clash_detect_secret)"
    fi

    # 3) Ensure stable defaults
    [[ -z "${CLASH_API:-}" ]] && export CLASH_API="http://127.0.0.1:9090"
    return 0
}

# ------------------------------
# Shared helpers (deps / url / api)
# ------------------------------

clash_have() { command -v "$1" >/dev/null 2>&1; }

clash_require_cmd() {
    local cmd="$1"; shift || true
    if ! clash_have "$cmd"; then
        echo "[ERR] missing dependency: $cmd${1:+ ($*)}" >&2
        return 1
    fi
    return 0
}

clash_optional_cmd() {
    local cmd="$1"; shift || true
    if ! clash_have "$cmd"; then
        echo "[WARN] missing optional dependency: $cmd${1:+ ($*)}" >&2
        return 1
    fi
    return 0
}

clash_urlencode() {
    # URL-encode a path component. Uses python3/jq/perl when available.
    local raw="${1-}"
    if clash_have python3; then
        python3 - "$raw" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
    elif clash_have jq; then
        printf '%s' "$raw" | jq -sRr @uri
    elif clash_have perl; then
        perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$raw"
    else
        local LC_CTYPE=C
        local out="" c hex i
        for ((i=0; i<${#raw}; i++)); do
            c=${raw:i:1}
            case "$c" in
                [a-zA-Z0-9._-]) out+="$c" ;;
                ' ') out+="%20" ;;
                *)
                    hex=$(printf '%s' "$c" | od -An -tx1 | head -n1 | tr -d ' \n')
                    hex=${hex^^}
                    out+="%${hex:-00}"
                ;;
            esac
        done
        printf '%s\n' "$out"
    fi
}

clash_ctrl_connect_timeout() { printf '%s' "${CLASH_CTRL_CONNECT_TIMEOUT:-2}"; }
clash_ctrl_max_time() { printf '%s' "${CLASH_CTRL_MAX_TIME:-4}"; }

clash_api_get() {
    # Usage: clash_api_get <url-or-path>
    # - Adds auth header if CLASH_SECRET set
    # - Adds timeouts and forces no-proxy to avoid env proxy interference
    local url="${1-}"
    [[ -z "$url" ]] && return 1
    clash_env_bootstrap >/dev/null 2>&1 || true
    if [[ "$url" != http*://* ]]; then
        url="${CLASH_API%/}/${url#/}"
    fi
    local hdr=""
    hdr="$(clash_auth_header 2>/dev/null || true)"
    if [[ -n "$hdr" ]]; then
        curl -fsS --noproxy '*' --connect-timeout "$(clash_ctrl_connect_timeout)" --max-time "$(clash_ctrl_max_time)" -H "$hdr" "$url"
    else
        curl -fsS --noproxy '*' --connect-timeout "$(clash_ctrl_connect_timeout)" --max-time "$(clash_ctrl_max_time)" "$url"
    fi
}

clash_api_put_json() {
    # Usage: clash_api_put_json <url-or-path> <json-payload>
    local url="${1-}" payload="${2-}"
    [[ -z "$url" ]] && return 1
    clash_env_bootstrap >/dev/null 2>&1 || true
    if [[ "$url" != http*://* ]]; then
        url="${CLASH_API%/}/${url#/}"
    fi
    local hdr=""
    hdr="$(clash_auth_header 2>/dev/null || true)"
    if [[ -n "$hdr" ]]; then
        curl -fsS --noproxy '*' --connect-timeout "$(clash_ctrl_connect_timeout)" --max-time "$(clash_ctrl_max_time)" -X PUT -H "$hdr" -H 'Content-Type: application/json' --data "$payload" "$url" >/dev/null
    else
        curl -fsS --noproxy '*' --connect-timeout "$(clash_ctrl_connect_timeout)" --max-time "$(clash_ctrl_max_time)" -X PUT -H 'Content-Type: application/json' --data "$payload" "$url" >/dev/null
    fi
}

clash_pick_selector_group() {
    # Pick an existing Selector group name.
    # Usage: clash_pick_selector_group [preferred1 preferred2 ...]
    # Output: group name or empty.
    local json g blob
    json="$(clash_api_get /proxies 2>/dev/null || true)"
    [[ -z "$json" ]] && { printf '%s' ""; return 0; }

    if clash_have jq; then
        for g in "$@"; do
            [[ -z "${g// }" ]] && continue
            if printf '%s' "$json" | jq -e --arg k "$g" '.proxies[$k].type == "Selector"' >/dev/null 2>&1; then
                printf '%s\n' "$g"
                return 0
            fi
        done
        printf '%s' "$json" | jq -r '.proxies | to_entries[] | select(.value.type=="Selector") | .key' 2>/dev/null | head -n1
        return 0
    fi

    blob=$(printf '%s' "$json" | tr '\n' ' ' | sed 's/},/}\n/g')
    for g in "$@"; do
        [[ -z "${g// }" ]] && continue
        if printf '%s' "$blob" | grep -F "\"$g\":" | grep -q '"type":"Selector"'; then
            printf '%s\n' "$g"
            return 0
        fi
    done

    printf '%s' "$blob" | grep '"type":"Selector"' | sed -n 's/.*"\([^"]\+\)":{.*"type":"Selector".*/\1/p' | head -n1
    return 0

}

clash_group_exists() {
    # Usage: clash_group_exists <group-name>
    # Returns 0 if exists in /proxies, else 1.
    local group="${1-}"
    [[ -z "$group" ]] && return 1
    local json blob
    json="$(clash_api_get /proxies 2>/dev/null || true)"
    [[ -z "$json" ]] && return 1
    if clash_have jq; then
        printf '%s' "$json" | jq -e --arg k "$group" '.proxies[$k] != null' >/dev/null 2>&1
        return $?
    fi
    blob=$(printf '%s' "$json" | tr '\n' ' ' | sed 's/},/}\n/g')
    printf '%s' "$blob" | grep -F "\"$group\":" >/dev/null 2>&1
}

clash_group_now() {
    # Usage: clash_group_now <group-name>
    # Output: .now (may be empty)
    local group="${1-}" enc json
    [[ -z "$group" ]] && { printf '%s' ""; return 0; }
    enc="$(clash_urlencode "$group")"
    json="$(clash_api_get "/proxies/$enc" 2>/dev/null || true)"
    [[ -z "$json" ]] && { printf '%s' ""; return 0; }
    if clash_have jq; then
        printf '%s' "$json" | jq -r '.now // ""' 2>/dev/null
        return 0
    fi
    printf '%s' "$json" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p'
}


# 验证必需的环境变量
require_env_var() {
    local var_name="$1"
    local var_value="${!var_name:-}"
    
    if [[ -z "$var_value" ]]; then
        echo "错误: 未设置环境变量 $var_name" >&2
        echo "请在 .env 文件中配置，或通过环境变量设置" >&2
        return 1
    fi
    return 0
}

# 自动加载（当被 source 时）
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Never fail the caller even when `.env` is absent.
    load_env_config || true
    clash_env_bootstrap || true
fi
