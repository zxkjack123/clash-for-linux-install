#!/usr/bin/env bash

# DESCRIPTION:
#   Show aggregated status of Clash/Mihomo environment: controller version, active
#   AI/YOUTUBE groups current node, quick connectivity probes, exit IP geolocation.
#
# USAGE:
#   ./show_vpn_status.sh
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Optional .env + controller/secret auto-detection
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true
clash_env_bootstrap 2>/dev/null || true

API="${CLASH_API:-http://127.0.0.1:9090}"
PROXY="${PROXY:-http://127.0.0.1:7890}"

# Controller API calls must not hang.
CTRL_CURL_OPTS=(--noproxy '*' --connect-timeout 2 --max-time 4)

AUTH_HDR=()
_hdr="$(clash_auth_header 2>/dev/null || true)"
[[ -n "${_hdr:-}" ]] && AUTH_HDR=(-H "${_hdr}")

curl_api() {
    if declare -F clash_api_get >/dev/null 2>&1; then
        clash_api_get "$1" 2>/dev/null
    else
        curl -fsS "${CTRL_CURL_OPTS[@]}" "${AUTH_HDR[@]}" "$1" 2>/dev/null
    fi
}

STATUS_GROUPS=()
PREFERRED_GROUPS=(
    "AUTO"
    "PROXY"
    "COPILOT"
    "DEV"
    "VSCODE"
    "DOCKER"
    "ACADEMIC"
)

for g in "${PREFERRED_GROUPS[@]}"; do
    if declare -F clash_group_exists >/dev/null 2>&1; then
        clash_group_exists "$g" && STATUS_GROUPS+=("$g") || true
    else
        STATUS_GROUPS+=("$g")
    fi
done

# If available, append a few more Selector groups (to handle JP-only/custom names)
if declare -F clash_pick_selector_group >/dev/null 2>&1; then
    # Grab /proxies and list selectors; keep it best-effort.
    proxies_json=$(curl_api "$API/proxies" 2>/dev/null || true)
    if [[ -n "$proxies_json" ]] && command -v jq >/dev/null 2>&1; then
        while IFS= read -r extra; do
            [[ -z "$extra" ]] && continue
            printf '%s\n' "${STATUS_GROUPS[@]}" | grep -Fxq "$extra" && continue
            STATUS_GROUPS+=("$extra")
            [[ ${#STATUS_GROUPS[@]} -ge 10 ]] && break
        done < <(printf '%s' "$proxies_json" | jq -r '.proxies | to_entries[] | select(.value.type=="Selector") | .key' 2>/dev/null)
    fi
fi
declare -A GROUP_DESCRIPTIONS=(
    ["AUTO"]="url-test 自动选择最快节点 (tolerance 200ms)"
    ["PROXY"]="手动选择，默认走 AUTO"
    ["COPILOT"]="Copilot/AI 流量 fallback(AUTO → DIRECT)"
    ["DEV"]="GitHub/开发 fallback(AUTO → DIRECT)"
    ["VSCODE"]="VS Code 更新/市场 fallback(AUTO → DIRECT)"
    ["DOCKER"]="Docker 镜像 fallback(AUTO → DIRECT)"
    ["ACADEMIC"]="学术站点 手动选择(PROXY/DIRECT)"
)

have() { command -v "$1" >/dev/null 2>&1; }

if declare -F clash_require_cmd >/dev/null 2>&1; then
    clash_require_cmd curl "required for controller/proxy probes"
    clash_optional_cmd jq "optional (richer group listing)" || true
fi
fetch_json() { curl_api "$1" || echo '{}'; }

urlencode_component() {
    local raw="$1"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$raw" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
    elif command -v jq >/dev/null 2>&1; then
        printf '%s' "$raw" | jq -sRr @uri
    elif command -v perl >/dev/null 2>&1; then
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

get_now() {
    local group="$1" encoded
    if declare -F clash_group_now >/dev/null 2>&1; then
        clash_group_now "$group" 2>/dev/null || true
        return 0
    fi
    encoded=$(urlencode_component "$group")
    curl_api "$API/proxies/${encoded}" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p'
}

echo "=== VPN Status ($(date '+%F %T')) ==="
if curl_api "$API/version" >/dev/null 2>&1; then
    ver=$(curl_api "$API/version" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
    echo "Controller: UP (version=$ver)"
else
    echo "Controller: DOWN ($API)" # 不立即退出，继续尝试后续信息
fi

for g in "${STATUS_GROUPS[@]}"; do
    now=$(get_now "$g")
    printf '%-20s current: %s\n' "$g" "${now:-Unknown}"
done

echo
echo "-- Quick Probes (proxy) --"
probe() { local url="$1" label="$2" out code t; out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 5 --max-time 8 --proxy "$PROXY" "$url" 2>/dev/null || echo "000,5"); code=${out%%,*}; t=${out##*,}; printf '%-10s %s %ss\n' "$label" "$code" "$t"; }
probe https://api.openai.com/v1/models openai
probe https://www.youtube.com/ youtube
probe https://i.ytimg.com/generate_204 yt_pixel
probe https://www.netflix.com/ netflix

echo
# Geo lookup should never hang (best-effort only).
geo=$(curl -sS --connect-timeout 5 --max-time 8 --proxy "$PROXY" https://ipapi.co/json 2>/dev/null || echo '{}')
ip=$(echo "$geo" | sed -n 's/.*"ip":"\([^"]*\)".*/\1/p')
country=$(echo "$geo" | sed -n 's/.*"country_name":"\([^"]*\)".*/\1/p')
echo "Exit IP: ${ip:-unknown} (${country:-N/A})"

echo
echo "Tip: run ./quick_vpn_check.sh or ./network_connectivity_test.sh for deeper checks"
