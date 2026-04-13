#!/usr/bin/env bash
# optimize_dev_nodes.sh
# 选择对开发/科研站点最友好的节点 (GitHub / NPM / PyPI / Docker / Go Proxy 等)
# 默认从“PROXY”分组获取候选节点，并将最佳节点同步到 PROXY 等常用分组。
#
# 用法：
#   ./vpn-tools/optimize_dev_nodes.sh
#   SOURCE_GROUP=DEV APPLY_GROUPS="DEV" ./vpn-tools/optimize_dev_nodes.sh
#   CANDIDATE_LIMIT=5 TIMEOUT=4 ./vpn-tools/optimize_dev_nodes.sh

set -euo pipefail

TIMEOUT=${TIMEOUT:-6}
PROXY=${PROXY:-http://127.0.0.1:7890}
SOURCE_GROUP=${SOURCE_GROUP:-}
APPLY_GROUPS=${APPLY_GROUPS:-}
CANDIDATE_LIMIT=${CANDIDATE_LIMIT:-10}
SLEEP_AFTER_SWITCH=${SLEEP_AFTER_SWITCH:-2}

TARGETS=(
	"github:https://github.com/"
	"github_api:https://api.github.com/"
	"npm:https://registry.npmjs.org/"
	"pypi:https://pypi.org/simple/"
	"pypi_files:https://files.pythonhosted.org/"
	"crates:https://crates.io/"
	"docker:https://registry-1.docker.io/v2/"
	"ghcr:https://ghcr.io/v2/"
	"goproxy:https://proxy.golang.org/"
)

have() { command -v "$1" >/dev/null 2>&1; }

if declare -F clash_require_cmd >/dev/null 2>&1; then
	clash_require_cmd curl "required for controller and probe requests"
	clash_optional_cmd jq "optional (better JSON parsing)" || true
	clash_optional_cmd python3 "optional (better URL encoding)" || true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load env (optional) and bootstrap controller/secret (env override -> legacy compat -> runtime.yaml -> default)
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true

clash_env_bootstrap 2>/dev/null || true
API="${CLASH_API:-http://127.0.0.1:9090}"

# Auto-pick a selector group when SOURCE_GROUP/APPLY_GROUPS are not provided.
if [[ -z "${SOURCE_GROUP:-}" ]] && declare -F clash_pick_selector_group >/dev/null 2>&1; then
	SOURCE_GROUP="$(clash_pick_selector_group "DEV" "PROXY" "AUTO" 2>/dev/null || true)"
fi
if [[ -z "${SOURCE_GROUP:-}" ]]; then
	echo "ERROR: 无法自动选择可用的 Selector 分组 (请设置 SOURCE_GROUP)" >&2
	exit 1
fi
if [[ -z "${APPLY_GROUPS:-}" ]]; then
	if [[ "$SOURCE_GROUP" == "PROXY" ]]; then
		APPLY_GROUPS="PROXY"
	else
		APPLY_GROUPS="PROXY,$SOURCE_GROUP"
	fi
fi

# --- Helpers -----------------------------------------------------------------
urlencode() {
	local raw="$1"
	if declare -F clash_urlencode >/dev/null 2>&1; then
		clash_urlencode "$raw"
	elif have python3; then
		python3 - "$raw" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
	elif have jq; then
		printf '%s' "$raw" | jq -sRr @uri
	else
		local out="" c hex i LC_CTYPE=C
		for ((i=0;i<${#raw};i++)); do
			c=${raw:i:1}
			case "$c" in
				[a-zA-Z0-9._-]) out+="$c" ;;
				' ') out+="%20" ;;
				*) hex=$(printf '%s' "$c" | od -An -tx1 | head -n1 | tr -d ' \n'); hex=${hex^^}; out+="%${hex:-00}" ;;
			esac
		done
		printf '%s\n' "$out"
	fi
}

fetch_proxy_json() {
	local name="$1" encoded
	encoded=$(urlencode "$name")
	if declare -F clash_api_get >/dev/null 2>&1; then
		clash_api_get "/proxies/${encoded}" 2>/dev/null || true
	else
		curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "$API/proxies/${encoded}" 2>/dev/null || true
	fi
}

get_proxy_type() {
	local name="$1" json type
	json=$(fetch_proxy_json "$name")
	[[ -z "$json" ]] && { echo ""; return; }
	if have jq; then
		type=$(printf '%s' "$json" | jq -r '.type // ""' 2>/dev/null)
	else
		type=$(printf '%s' "$json" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p')
	fi
	echo "$type"
}

get_group_nodes() {
	local group="$1" json
	json=$(fetch_proxy_json "$group")
	[[ -z "$json" ]] && return 1
	if have jq; then
		mapfile -t arr < <(printf '%s' "$json" | jq -r '.all[]' 2>/dev/null)
	else
		arr=($(printf '%s' "$json" | sed -n 's/.*"all":\[\(.*\)\].*/\1/p' | tr '"' '\n' | sed '/^$/d'))
	fi
	printf '%s\n' "${arr[@]}"
}

switch_group_node() {
	local group="$1" node="$2" payload encoded
	encoded=$(urlencode "$group")
	payload=$(printf '{"name":"%s"}' "$node")
	if declare -F clash_api_put_json >/dev/null 2>&1; then
		clash_api_put_json "/proxies/${encoded}" "$payload" >/dev/null 2>&1 || true
	else
		curl -s --noproxy '*' --connect-timeout 2 --max-time 4 -X PUT "$API/proxies/${encoded}" -H 'Content-Type: application/json' -d "$payload" >/dev/null || true
	fi
}

test_endpoint() {
	local label="$1" url="$2"
	local out code time
	out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+4))" --proxy "$PROXY" "$url" 2>/dev/null || echo "000,$TIMEOUT")
	code=${out%%,*}
	time=${out##*,}
	local ok=0
	if [[ $code =~ ^[23][0-9][0-9]$ ]]; then
		ok=1
	elif [[ "$code" == "401" || "$code" == "403" || "$code" == "405" ]]; then
		ok=1
	fi
	printf '%s|%s|%s|%s\n' "$label" "$code" "$time" "$ok"
}

score_node() {
	local node="$1" label url result code time ok
	local success=0 total=0
	local details=()
	for entry in "${TARGETS[@]}"; do
		IFS=':' read -r label url <<< "$entry"
		result=$(test_endpoint "$label" "$url")
		IFS='|' read -r _ code time ok <<< "$result"
		details+=("$label:$code@${time}s${ok}")
		total=$((total + 1))
		success=$((success + ok))
		local state
		if (( ok == 1 )); then
			state="OK"
		else
			state="FAIL"
		fi
		>&2 printf '    - %s -> code=%s time=%ss status=%s\n' "$label" "$code" "$time" "$state"
	done
	printf '%s|%s|%s\n' "$success" "$total" "${details[*]}"
}

select_candidates() {
	local nodes fallback_group
	mapfile -t nodes < <(get_group_nodes "$SOURCE_GROUP" 2>/dev/null || true)
	if (( ${#nodes[@]} == 0 )); then
		fallback_group=PROXY
		mapfile -t nodes < <(get_group_nodes "$fallback_group" 2>/dev/null || true)
	fi
	if (( ${#nodes[@]} == 0 )); then
		echo "ERROR: 无法从 $SOURCE_GROUP 获取候选节点" >&2
		exit 1
	fi
	local filtered=()
	for node in "${nodes[@]}"; do
		[[ -z ${node// } ]] && continue
		local type=$(get_proxy_type "$node")
		case "$type" in
			Selector|URLTest|Fallback|LoadBalance|Unknown|"") continue;;
		esac
		filtered+=("$node")
		if (( ${#filtered[@]} >= CANDIDATE_LIMIT )); then break; fi
	done
	if (( ${#filtered[@]} == 0 )); then
		echo "ERROR: 候选节点为空 (过滤后)" >&2
		exit 1
	fi
	printf '%s\n' "${filtered[@]}"
}

main() {
	local candidates=()
	mapfile -t candidates < <(select_candidates)
	echo "=== Dev Node Optimizer ($(date '+%F %T')) ==="
	echo "Controller : $API"
	echo "Candidates : ${#candidates[@]} (source=$SOURCE_GROUP, limit=$CANDIDATE_LIMIT)"
	printf '\n'
	local best_node="" best_score=-1 best_details="" original=$(fetch_proxy_json "$SOURCE_GROUP" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p')
	for node in "${candidates[@]}"; do
		echo "🧪 Testing $node"
		switch_group_node "$SOURCE_GROUP" "$node"
		sleep "$SLEEP_AFTER_SWITCH"
		IFS='|' read -r success total details <<< "$(score_node "$node")"
		echo "  => score $success/$total"
		if (( success > best_score )); then
			best_score=$success
			best_node="$node"
			best_details="$details"
		fi
		printf '\n'
	done
	if [[ -z "$best_node" ]]; then
		echo "未找到可用节点" >&2
		exit 1
	fi
	IFS=',' read -r -a apply <<< "$APPLY_GROUPS"
	for group in "${apply[@]}"; do
		group=${group// /}
		[[ -z "$group" ]] && continue
		if [[ -n $(fetch_proxy_json "$group") ]]; then
			switch_group_node "$group" "$best_node"
			printf '✅ %s 已切换到 %s\n' "$group" "$best_node"
		else
			printf '⚠️  跳过 %s (分组不存在)\n' "$group"
		fi
		printf '\n'
	done
	echo "🏆 Best node: $best_node (score $best_score/${#TARGETS[@]})"
	echo "Details: $best_details"
	[[ -n ${original:-} ]] && echo "(original $SOURCE_GROUP node was: $original)"
}

main "$@"
