#!/usr/bin/env bash
# network_health_check.sh — 轻量级三链路健康巡检 (Nagios 风格三态输出)
#
# 功能:
#   每次运行采样 GitHub / Copilot / VSCode 三条链路延迟 + Clash 失败计数,
#   基于可配置阈值输出 OK / WARN / CRIT 三态及对应退出码 (0/1/2).
#   支持"连续 N 次"防抖: 历史状态持久化到状态文件, 仅连续触发才升级告警.
#
# 用法:
#   ./network_health_check.sh              # 单次巡检 (cron / systemd 推荐)
#   ./network_health_check.sh --json       # JSON 输出
#   ./network_health_check.sh --verbose    # 详细模式 (调试用)
#   ./network_health_check.sh --reset      # 清除历史状态重新计数
#   ./network_health_check.sh --dry-run    # 采样但不更新状态文件
#
# 退出码:
#   0 = OK     1 = WARNING     2 = CRITICAL
#
# cron 示例 (每分钟巡检):
#   * * * * * /home/gw/opt/clash-for-linux-install/vpn-tools/network_health_check.sh --json >> /tmp/_health_check.jsonl 2>&1

set -uo pipefail

# ── 环境引导 ────────────────────────────────────────────────
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "$XDG_RUNTIME_DIR/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$BASE_DIR")"

# 加载项目环境 (controller address, auth, proxy port, etc.)
if [[ -f "$BASE_DIR/load_env.sh" ]]; then
    # shellcheck source=/dev/null
    source "$BASE_DIR/load_env.sh" 2>/dev/null || true
fi

# ── 外部可配置参数 (环境变量覆盖) ───────────────────────────
PROXY="${PROXY:-http://127.0.0.1:7890}"
API="${CLASH_API:-http://127.0.0.1:9090}"
AUTH_HDR=()
_hdr="$(clash_auth_header 2>/dev/null || true)"
[[ -n "${_hdr:-}" ]] && AUTH_HDR=(-H "${_hdr}")

SERVICE="${BIN_KERNEL_NAME:-mihomo}"
STATE_DIR="${HEALTH_STATE_DIR:-$HOME/.local/share/clash/health}"
STATE_FILE="$STATE_DIR/check_state.json"
ALERT_SCRIPT="${ALERT_SCRIPT:-$BASE_DIR/alert_notification.sh}"
DIAG_SCRIPT="${DIAG_SCRIPT:-$PARENT_DIR/script/clash_diagnose.sh}"

# ── 链路阈值 ────────────────────────────────────────────────
# 格式: <名称>_WARN_S  <名称>_CRIT_S  <名称>_CONSEC_CRIT
# 单次超过 WARN → 记录 warning; 连续 CONSEC_CRIT 次超过 CRIT → critical
GITHUB_WARN_S="${GITHUB_WARN_S:-2.0}"
GITHUB_CRIT_S="${GITHUB_CRIT_S:-2.5}"
GITHUB_CONSEC_CRIT="${GITHUB_CONSEC_CRIT:-3}"
GITHUB_OK_CODES="${GITHUB_OK_CODES:-200,301,302}"

COPILOT_WARN_S="${COPILOT_WARN_S:-1.2}"
COPILOT_CRIT_S="${COPILOT_CRIT_S:-2.0}"
COPILOT_CONSEC_CRIT="${COPILOT_CONSEC_CRIT:-3}"
COPILOT_OK_CODES="${COPILOT_OK_CODES:-200,401}"

VSCODE_WARN_S="${VSCODE_WARN_S:-1.5}"
VSCODE_CRIT_S="${VSCODE_CRIT_S:-2.5}"
VSCODE_CONSEC_CRIT="${VSCODE_CONSEC_CRIT:-3}"
VSCODE_OK_CODES="${VSCODE_OK_CODES:-200,301,302}"

# 可用性: 连续 N 次 HTTP 不在 OK_CODES → critical
HTTP_CONSEC_FAIL="${HTTP_CONSEC_FAIL:-2}"

# 全局 Clash 阈值
FAILS_5M_WARN="${FAILS_5M_WARN:-15}"
FAILS_5M_CRIT="${FAILS_5M_CRIT:-30}"
ZERO_XFER_WARN="${ZERO_XFER_WARN:-5}"
ZERO_XFER_CRIT="${ZERO_XFER_CRIT:-15}"
ZERO_XFER_CONSEC="${ZERO_XFER_CONSEC:-3}"

# 恢复: 连续 N 次正常 → 清除告警
RECOVER_COUNT="${RECOVER_COUNT:-2}"

# ── 运行选项 ────────────────────────────────────────────────
JSON=0; VERBOSE=0; DRY_RUN=0; RESET=0; NO_NOTIFY=0
for arg in "$@"; do
    case "$arg" in
        --json)    JSON=1 ;;
        --verbose|-v) VERBOSE=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --reset)   RESET=1 ;;
        --no-notify) NO_NOTIFY=1 ;;
        -h|--help) grep -E '^#' "$0" | head -25 | sed 's/^# \?//'; exit 0 ;;
    esac
done

# ── 工具函数 ────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }
ts()   { date '+%Y-%m-%d %H:%M:%S'; }
dbg()  { [[ $VERBOSE -eq 1 ]] && echo "[dbg] $*" >&2 || true; }

# 比较浮点: $1 > $2 → 0 (true)
float_gt() { python3 -c "import sys;sys.exit(0 if float('$1')>float('$2') else 1)" 2>/dev/null; }

# ── 状态文件管理 ─────────────────────────────────────────────
mkdir -p "$STATE_DIR"

init_state() {
    python3 -c "
import json, pathlib
pathlib.Path('$STATE_FILE').write_text(json.dumps({
    'github_crit_streak': 0, 'github_fail_streak': 0, 'github_ok_streak': 0,
    'copilot_crit_streak': 0, 'copilot_fail_streak': 0, 'copilot_ok_streak': 0,
    'vscode_crit_streak': 0, 'vscode_fail_streak': 0, 'vscode_ok_streak': 0,
    'zero_xfer_streak': 0,
    'last_check': '', 'last_verdict': 'OK'
}, indent=2))
"
}

if [[ $RESET -eq 1 ]] || [[ ! -f "$STATE_FILE" ]]; then
    init_state
    [[ $RESET -eq 1 ]] && echo "State reset." && exit 0
fi

# ── 采样 ─────────────────────────────────────────────────────
# curl 一条链路, 返回: http_code total_s
probe_link() {
    local url="$1"
    local out
    out=$(curl -x "$PROXY" -o /dev/null -s \
        -w '%{http_code}\t%{time_total}' \
        --connect-timeout 10 --max-time 20 \
        "$url" 2>/dev/null) || out="0\t99.0"
    echo "$out"
}

# Clash 控制接口: fails_5m, active_conns, zero_xfer
probe_clash() {
    local fails_5m=-1 active=0 zero=0

    # fails_5m from diagnose (fast json)
    # NOTE: diagnose exits 2 on warnings, which triggers pipefail → ||.
    # Capture output first, then validate.
    if [[ -x "$DIAG_SCRIPT" ]] || [[ -f "$DIAG_SCRIPT" ]]; then
        local _diag_out
        _diag_out=$(bash "$DIAG_SCRIPT" --fast --json 2>/dev/null | cat) || true
        if [[ -n "$_diag_out" ]]; then
            fails_5m=$(echo "$_diag_out" | python3 -c "import json,sys;print(json.load(sys.stdin).get('fails_5m',-1))" 2>/dev/null) || fails_5m=-1
        fi
    fi

    # connections summary
    local cjson
    cjson=$(curl -s --connect-timeout 3 --max-time 5 "${AUTH_HDR[@]}" "${API}/connections" 2>/dev/null || echo '{}')
    read -r active zero < <(echo "$cjson" | python3 -c "
import json,sys
try:
    cs=json.load(sys.stdin).get('connections') or []
    z=sum(1 for c in cs if c.get('download',0)==0 and c.get('upload',0)==0)
    print(len(cs), z)
except: print(0, 0)
" 2>/dev/null) || { active=0; zero=0; }

    # 169.254 leak check (should always be 0 after REJECT rule)
    local proxy_169=0
    proxy_169=$(journalctl --user -u "$SERVICE" --since '5 min ago' --no-pager 2>/dev/null \
        | grep -c '169.254.169.254:80 match Match using PROXY' 2>/dev/null) || proxy_169=0

    echo "$fails_5m $active $zero $proxy_169"
}

# ── 主采样 ───────────────────────────────────────────────────
NOW="$(ts)"
dbg "Probing 3 links + clash metrics at $NOW ..."

# 并行采样三条链路
gh_raw=$(probe_link "https://github.com")
cop_raw=$(probe_link "https://api.github.com/copilot_internal/v2/token")
vs_raw=$(probe_link "https://update.code.visualstudio.com/api/update/linux-x64/stable/latest")
read -r clash_fails clash_active clash_zero clash_169 < <(probe_clash)

# 解析
IFS=$'\t' read -r gh_code gh_total <<< "$gh_raw"
IFS=$'\t' read -r cop_code cop_total <<< "$cop_raw"
IFS=$'\t' read -r vs_code vs_total <<< "$vs_raw"

dbg "github=$gh_code/${gh_total}s copilot=$cop_code/${cop_total}s vscode=$vs_code/${vs_total}s"
dbg "fails_5m=$clash_fails active=$clash_active zero=$clash_zero proxy_169=$clash_169"

# ── 判定逻辑 ─────────────────────────────────────────────────
# 读取历史状态
STATE_JSON=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')

read_streak() {
    echo "$STATE_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('$1',0))" 2>/dev/null || echo 0
}

# 更新 + 判定一条链路
# 参数: name http_code total_s warn_s crit_s consec_crit ok_codes http_consec_fail
# 输出: link_verdict (OK/WARN/CRIT), 并设置 new_*_streak 变量
declare -A LINK_VERDICT
declare -A NEW_STREAKS

eval_link() {
    local name="$1" code="$2" total="$3" warn_s="$4" crit_s="$5" consec_crit="$6" ok_codes_csv="$7" http_consec="$8"

    local crit_streak ok_streak fail_streak
    crit_streak=$(read_streak "${name}_crit_streak")
    ok_streak=$(read_streak "${name}_ok_streak")
    fail_streak=$(read_streak "${name}_fail_streak")

    local http_ok=0
    IFS=',' read -ra codes_arr <<< "$ok_codes_csv"
    for c in "${codes_arr[@]}"; do
        [[ "$code" == "$c" ]] && http_ok=1
    done

    local verdict="OK"

    # HTTP 不可用判定
    if [[ $http_ok -eq 0 ]]; then
        fail_streak=$((fail_streak + 1))
        ok_streak=0
        crit_streak=0
        if [[ $fail_streak -ge $http_consec ]]; then
            verdict="CRIT"
        else
            verdict="WARN"
        fi
    else
        fail_streak=0

        # 延迟判定
        if float_gt "$total" "$crit_s"; then
            crit_streak=$((crit_streak + 1))
            ok_streak=0
            if [[ $crit_streak -ge $consec_crit ]]; then
                verdict="CRIT"
            else
                verdict="WARN"
            fi
        elif float_gt "$total" "$warn_s"; then
            crit_streak=0
            ok_streak=0
            verdict="WARN"
        else
            ok_streak=$((ok_streak + 1))
            crit_streak=0
            verdict="OK"
        fi
    fi

    LINK_VERDICT[$name]="$verdict"
    NEW_STREAKS["${name}_crit_streak"]="$crit_streak"
    NEW_STREAKS["${name}_ok_streak"]="$ok_streak"
    NEW_STREAKS["${name}_fail_streak"]="$fail_streak"

    dbg "$name: code=$code total=${total}s verdict=$verdict crit_streak=$crit_streak fail_streak=$fail_streak ok=$ok_streak"
}

eval_link "github"  "$gh_code"  "$gh_total"  "$GITHUB_WARN_S"  "$GITHUB_CRIT_S"  "$GITHUB_CONSEC_CRIT"  "$GITHUB_OK_CODES"  "$HTTP_CONSEC_FAIL"
eval_link "copilot" "$cop_code" "$cop_total" "$COPILOT_WARN_S" "$COPILOT_CRIT_S" "$COPILOT_CONSEC_CRIT" "$COPILOT_OK_CODES" "$HTTP_CONSEC_FAIL"
eval_link "vscode"  "$vs_code"  "$vs_total"  "$VSCODE_WARN_S"  "$VSCODE_CRIT_S"  "$VSCODE_CONSEC_CRIT"  "$VSCODE_OK_CODES"  "$HTTP_CONSEC_FAIL"

# Clash 全局判定
CLASH_VERDICT="OK"

# fails_5m
if [[ "$clash_fails" -ge "$FAILS_5M_CRIT" ]] 2>/dev/null; then
    CLASH_VERDICT="CRIT"
elif [[ "$clash_fails" -ge "$FAILS_5M_WARN" ]] 2>/dev/null; then
    [[ "$CLASH_VERDICT" != "CRIT" ]] && CLASH_VERDICT="WARN"
fi

# zero_xfer
zero_streak=$(read_streak "zero_xfer_streak")
if [[ "$clash_zero" -ge "$ZERO_XFER_CRIT" ]] 2>/dev/null; then
    CLASH_VERDICT="CRIT"
    zero_streak=$((zero_streak + 1))
elif [[ "$clash_zero" -ge "$ZERO_XFER_WARN" ]] 2>/dev/null; then
    zero_streak=$((zero_streak + 1))
    if [[ $zero_streak -ge $ZERO_XFER_CONSEC ]]; then
        [[ "$CLASH_VERDICT" != "CRIT" ]] && CLASH_VERDICT="WARN"
    fi
else
    zero_streak=0
fi
NEW_STREAKS["zero_xfer_streak"]="$zero_streak"

# 169.254 leak (instant critical)
if [[ "$clash_169" -gt 0 ]] 2>/dev/null; then
    CLASH_VERDICT="CRIT"
fi

# ── 综合判定 ─────────────────────────────────────────────────
OVERALL="OK"
for v in "${LINK_VERDICT[@]}" "$CLASH_VERDICT"; do
    if [[ "$v" == "CRIT" ]]; then
        OVERALL="CRIT"; break
    elif [[ "$v" == "WARN" ]]; then
        OVERALL="WARN"
    fi
done

# ── 持久化状态 ───────────────────────────────────────────────
if [[ $DRY_RUN -eq 0 ]]; then
    python3 -c "
import json, pathlib
s = ${NEW_STREAKS[github_crit_streak]:-0}  # dummy to check syntax
d = {
    'github_crit_streak': ${NEW_STREAKS[github_crit_streak]:-0},
    'github_fail_streak': ${NEW_STREAKS[github_fail_streak]:-0},
    'github_ok_streak': ${NEW_STREAKS[github_ok_streak]:-0},
    'copilot_crit_streak': ${NEW_STREAKS[copilot_crit_streak]:-0},
    'copilot_fail_streak': ${NEW_STREAKS[copilot_fail_streak]:-0},
    'copilot_ok_streak': ${NEW_STREAKS[copilot_ok_streak]:-0},
    'vscode_crit_streak': ${NEW_STREAKS[vscode_crit_streak]:-0},
    'vscode_fail_streak': ${NEW_STREAKS[vscode_fail_streak]:-0},
    'vscode_ok_streak': ${NEW_STREAKS[vscode_ok_streak]:-0},
    'zero_xfer_streak': ${NEW_STREAKS[zero_xfer_streak]:-0},
    'last_check': '${NOW}',
    'last_verdict': '${OVERALL}'
}
pathlib.Path('$STATE_FILE').write_text(json.dumps(d, indent=2))
"
fi

# ── 告警通知 (仅 WARN/CRIT, 且未禁用通知) ────────────────────
if [[ "$OVERALL" != "OK" ]] && [[ -x "$ALERT_SCRIPT" ]] && [[ $DRY_RUN -eq 0 ]] && [[ $NO_NOTIFY -eq 0 ]]; then
    # alert_notification.sh expects INFO/WARNING/CRITICAL, not OK/WARN/CRIT
    local_level="$OVERALL"
    [[ "$local_level" == "WARN" ]] && local_level="WARNING"
    [[ "$local_level" == "CRIT" ]] && local_level="CRITICAL"
    local_msg="[health-check] $OVERALL | gh=${LINK_VERDICT[github]} cop=${LINK_VERDICT[copilot]} vs=${LINK_VERDICT[vscode]} clash=$CLASH_VERDICT | fails=$clash_fails zero=$clash_zero"
    "$ALERT_SCRIPT" "$local_level" "$local_msg" 2>/dev/null || true
fi

# ── 输出 ─────────────────────────────────────────────────────
if [[ $JSON -eq 1 ]]; then
    python3 -c "
import json
d = {
    'timestamp': '${NOW}',
    'overall': '${OVERALL}',
    'github': {
        'http': ${gh_code}, 'total_s': ${gh_total},
        'verdict': '${LINK_VERDICT[github]}',
        'crit_streak': ${NEW_STREAKS[github_crit_streak]:-0},
        'fail_streak': ${NEW_STREAKS[github_fail_streak]:-0}
    },
    'copilot': {
        'http': ${cop_code}, 'total_s': ${cop_total},
        'verdict': '${LINK_VERDICT[copilot]}',
        'crit_streak': ${NEW_STREAKS[copilot_crit_streak]:-0},
        'fail_streak': ${NEW_STREAKS[copilot_fail_streak]:-0}
    },
    'vscode': {
        'http': ${vs_code}, 'total_s': ${vs_total},
        'verdict': '${LINK_VERDICT[vscode]}',
        'crit_streak': ${NEW_STREAKS[vscode_crit_streak]:-0},
        'fail_streak': ${NEW_STREAKS[vscode_fail_streak]:-0}
    },
    'clash': {
        'fails_5m': ${clash_fails},
        'active_conns': ${clash_active},
        'zero_xfer': ${clash_zero},
        'proxy_169': ${clash_169},
        'verdict': '${CLASH_VERDICT}'
    }
}
print(json.dumps(d, ensure_ascii=False))
"
else
    # Human-readable Nagios-style one-liner
    echo "${OVERALL} | github=${LINK_VERDICT[github]}(${gh_code}/${gh_total}s) copilot=${LINK_VERDICT[copilot]}(${cop_code}/${cop_total}s) vscode=${LINK_VERDICT[vscode]}(${vs_code}/${vs_total}s) clash=${CLASH_VERDICT}(fails=${clash_fails},zero=${clash_zero}) | ts=${NOW}"
fi

# ── 退出码 ───────────────────────────────────────────────────
case "$OVERALL" in
    OK)   exit 0 ;;
    WARN) exit 1 ;;
    CRIT) exit 2 ;;
    *)    exit 3 ;;
esac
