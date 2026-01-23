#!/usr/bin/env bash
# jp_tailscale_single_node_test.sh
#
# JP-Tailscale 单节点专项测试：
#  - Tailscale 直连/DERP 判定
#  - 通过 mihomo(Clash Meta) 代理的延迟/吞吐/并发稳定性
#  - 给出 mihomo/系统参数建议
#  - 可选：自动“收敛” AUTO-SMART 为「JP-Tailscale 优先 + 可控兜底」
#
# 说明：
#  - 默认仅临时切换 AUTO-SMART 到 JP-Tailscale（可关闭 --no-switch），结束后自动恢复。
#  - 不会打印 mihomo secret/token。
#
# 用法：
#   cd vpn-tools
#   bash jp_tailscale_single_node_test.sh --quick
#   bash jp_tailscale_single_node_test.sh --full --concurrency 30
#   bash jp_tailscale_single_node_test.sh --apply-tighten --fallback balanced
#
set -euo pipefail

MODE=full
NO_SWITCH=0
CONCURRENCY=20
PING_COUNT=8
DL_SECONDS=20
NETCHECK_TIMEOUT=12
PING_TIMEOUT=12
FALLBACK_MODE=balanced  # minimal|balanced
APPLY_TIGHTEN=0

PROXY=${PROXY:-http://127.0.0.1:7890}
TS_PEER=${TS_PEER:-100.82.241.21}
TS_IFACE=${TS_IFACE:-tailscale0}
GROUP_TO_SWITCH=${GROUP_TO_SWITCH:-AUTO-SMART}
TARGET_PROXY_NAME=${TARGET_PROXY_NAME:-JP-Tailscale}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Optional env loading
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/net_helpers.sh" 2>/dev/null || true
nh_init_symbols 2>/dev/null || true

have(){ command -v "$1" >/dev/null 2>&1; }

section(){ echo; printf '===== %s =====\n' "$1"; }

mask_url(){
  # Mask common secrets in URLs, including /link/<token> path segments.
  printf '%s' "$1" | sed -E 's#^(https?://)[^/@]+@#\1***@#' | sed -E 's#/(link|subscribe)/[^/?#]{8,}#/\1/***#g' | sed -E 's/([?&](token|access_token|apikey|api_key|key|secret)=)[^&#]*/\1***/gI'
}

usage(){
  cat <<EOF
JP-Tailscale 单节点专项测试

Options:
  --quick                 快速模式（~30-60s）
  --full                  完整模式（默认，~2-5min，取决于网络）
  --no-switch             不通过 API 切换分组到 JP-Tailscale（只测当前路由）
  --group NAME            需要临时切换的 selector 分组名（默认：AUTO-SMART）
  --proxy-name NAME       要切换到的代理名（默认：JP-Tailscale）
  --ts-peer IP|NAME       需要 tailscale ping 的对端（默认：100.82.241.21）
  --concurrency N         并发请求数（默认：20）
  --dl-seconds N          吞吐测试最大时长（默认：20）
  --apply-tighten         根据建议自动收敛 AUTO-SMART（修改 ~/.local/share/clash/mixin.yaml 并重建 runtime）
  --fallback minimal|balanced   收敛策略（默认：balanced）
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) MODE=quick; shift;;
    --full) MODE=full; shift;;
    --no-switch) NO_SWITCH=1; shift;;
    --group)
      [[ $# -ge 2 ]] || { echo "ERROR: --group requires a value" >&2; exit 2; }
      GROUP_TO_SWITCH="$2"; shift 2;;
    --proxy-name)
      [[ $# -ge 2 ]] || { echo "ERROR: --proxy-name requires a value" >&2; exit 2; }
      TARGET_PROXY_NAME="$2"; shift 2;;
    --ts-peer)
      [[ $# -ge 2 ]] || { echo "ERROR: --ts-peer requires a value" >&2; exit 2; }
      TS_PEER="$2"; shift 2;;
    --concurrency)
      [[ $# -ge 2 ]] || { echo "ERROR: --concurrency requires a value" >&2; exit 2; }
      CONCURRENCY="$2"; shift 2;;
    --dl-seconds)
      [[ $# -ge 2 ]] || { echo "ERROR: --dl-seconds requires a value" >&2; exit 2; }
      DL_SECONDS="$2"; shift 2;;
    --apply-tighten) APPLY_TIGHTEN=1; shift;;
    --fallback)
      [[ $# -ge 2 ]] || { echo "ERROR: --fallback requires a value" >&2; exit 2; }
      FALLBACK_MODE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

# ---- Clash/Mihomo API helpers ----
detect_controller() {
  local runtime="${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}"
  local candidate="" host="" port="" default="http://127.0.0.1:9090"
  [ -f "$runtime" ] || { echo "$default"; return; }
  if have yq; then
    candidate=$(yq '."external-controller" // ""' "$runtime" 2>/dev/null || true)
  fi
  if [ -z "$candidate" ]; then
    candidate=$(grep -E '^ *external-controller:' "$runtime" 2>/dev/null | tail -n1 | cut -d':' -f2- | tr -d ' "' || true)
  fi
  candidate=${candidate//$'\n'/}
  candidate=${candidate//\"/}
  candidate=${candidate//\'/}
  candidate=${candidate//[[:space:]]/}
  [ -z "$candidate" ] && { echo "$default"; return; }
  if [[ "$candidate" == http*://* ]]; then
    echo "$candidate"; return
  fi
  host=${candidate%:*}; port=${candidate##*:}
  [ -z "$port" ] && port=9090
  case "$host" in
    ""|"0.0.0.0"|"::") host=127.0.0.1;;
  esac
  echo "http://${host}:${port}"
}

read_secret(){
  # Prefer env override (preferred)
  if [ -n "${CLASH_SECRET:-}" ]; then
    printf '%s' "$CLASH_SECRET"; return 0
  fi

  local runtime="${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}"
  [ -f "$runtime" ] || return 0
  local s=""
  if have yq; then
    s=$(yq '.secret // ""' "$runtime" 2>/dev/null || true)
  fi
  if [ -z "$s" ]; then
    s=$(grep -E '^ *secret:' "$runtime" 2>/dev/null | tail -n1 | cut -d':' -f2- | tr -d ' "' || true)
  fi
  s=${s//$'\n'/}
  s=${s//\"/}
  s=${s//\'/}
  printf '%s' "$s"
}

api_get(){
  local url="$1"
  local secret="${2:-}"
  local hdr=()
  [ -n "$secret" ] && hdr=(-H "Authorization: Bearer $secret")
  curl -fsS --noproxy '*' --connect-timeout 2 --max-time 3 "${url}" "${hdr[@]}" 2>/dev/null || true
}

api_put_proxy(){
  local base="$1" group="$2" name="$3" secret="$4"
  local hdr=(-H 'Content-Type: application/json')
  [ -n "$secret" ] && hdr+=(-H "Authorization: Bearer $secret")
  curl -fsS --noproxy '*' --connect-timeout 2 --max-time 3 -X PUT "${base}/proxies/${group}" "${hdr[@]}" --data "{\"name\":\"${name}\"}" >/dev/null 2>&1 || return 1
}

get_group_now(){
  local base="$1" group="$2" secret="$3"
  local js
  js=$(api_get "${base}/proxies/${group}" "$secret")
  [ -z "$js" ] && return 1
  if have jq; then
    echo "$js" | jq -r '.now // ""' 2>/dev/null || true
  else
    echo "$js" | tr '\n' ' ' | sed -n 's/.*"now"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
  fi
}

API_BASE="${CLASH_API:-$(detect_controller)}"
SECRET="$(read_secret)"

PREV_NOW=""
RESTORE_NEEDED=0
cleanup(){
  if [ "$RESTORE_NEEDED" = 1 ] && [ -n "$PREV_NOW" ]; then
    api_put_proxy "$API_BASE" "$GROUP_TO_SWITCH" "$PREV_NOW" "$SECRET" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ---- Output ----
section "BASELINE"
echo "Time          : $(date '+%F %T')"
echo "Mode          : $MODE"
echo "Proxy         : $PROXY"
echo "AUTO group    : $GROUP_TO_SWITCH"
echo "Target proxy  : $TARGET_PROXY_NAME"
echo "Tailscale peer: $TS_PEER"

# ---- Tailscale check ----
section "TAILSCALE HEALTH"
if have tailscale; then
  echo "tailscale     : $(tailscale version 2>/dev/null | head -n1 || true)"
  if ip link show "$TS_IFACE" >/dev/null 2>&1; then
    echo "iface         : $TS_IFACE (present)"
  else
    echo "iface         : $TS_IFACE (MISSING)"
  fi

  if have jq; then
    tailscale status --json 2>/dev/null | jq -r '{BackendState,Self:.Self.DNSName,MagicDNSSuffix:.MagicDNSSuffix,PeerCount:(.Peer|length)}' 2>/dev/null || true
  else
    # fallback
    tailscale status 2>/dev/null | head -n 20 || true
  fi

  echo "--- netcheck (hint: UDP/DERP) ---"
  # netcheck may hang on certain networks; keep it bounded.
  if have timeout; then
    timeout "${NETCHECK_TIMEOUT}s" tailscale netcheck 2>/dev/null | sed -n '1,120p' || true
  else
    tailscale netcheck 2>/dev/null | sed -n '1,120p' || true
  fi

  echo "--- ping (direct vs DERP) ---"
  if have timeout; then
    ping_out=$(timeout "${PING_TIMEOUT}s" tailscale ping -c "$PING_COUNT" "$TS_PEER" 2>&1 || true)
  else
    ping_out=$(tailscale ping -c "$PING_COUNT" "$TS_PEER" 2>&1 || true)
  fi
  echo "$ping_out" | sed -n '1,60p'
  # Examples:
  #   pong from <peer> via <ip>:41641 in 107ms    -> direct
  #   pong from <peer> via DERP(<region>) in ...  -> derp
  direct_cnt=$(echo "$ping_out" | grep -Eic ' direct | via [0-9a-fA-F:.]+:41641 ' || true)
  derp_cnt=$(echo "$ping_out" | grep -Eic ' derp|via DERP' || true)
  echo "direct_hits   : ${direct_cnt:-0}"
  echo "derp_hits     : ${derp_cnt:-0}"
else
  echo "tailscale     : NOT INSTALLED"
fi

# ---- API switch ----
section "MIHOMO CONTROL (optional)"
api_ok=no
if [ -n "$API_BASE" ] && [ -n "$(api_get "${API_BASE}/version" "$SECRET")" ]; then
  api_ok=yes
fi

echo "controller    : $API_BASE (reachable=$api_ok)"

if [ "$NO_SWITCH" = 1 ]; then
  echo "switch        : disabled (--no-switch)"
elif [ "$api_ok" != yes ]; then
  echo "switch        : skipped (controller not reachable)"
else
  PREV_NOW=$(get_group_now "$API_BASE" "$GROUP_TO_SWITCH" "$SECRET" || true)
  echo "prev_now      : ${PREV_NOW:-unknown}"
  if [ -n "$PREV_NOW" ]; then
    if api_put_proxy "$API_BASE" "$GROUP_TO_SWITCH" "$TARGET_PROXY_NAME" "$SECRET"; then
      RESTORE_NEEDED=1
      echo "switch        : ${NH_OK:-OK} ${GROUP_TO_SWITCH} -> ${TARGET_PROXY_NAME} (will restore on exit)"
    else
      echo "switch        : ${NH_FAIL:-FAIL} could not switch group via API"
    fi
  else
    echo "switch        : ${NH_WARN:-WARN} could not read current selector now"
  fi
fi

# ---- Latency probes ----
section "PROXY LATENCY (sample)"
LAT_N=${LAT_N:-10}
TIMEOUT=${TIMEOUT:-6}

lat_targets=(
  "https://www.cloudflare.com/cdn-cgi/trace"
  "https://api.ipify.org/"
  "https://www.google.com/generate_204"
)

curl_metrics(){
  local url="$1"
  # code,total,connect,appconnect,starttransfer
  curl -s -o /dev/null \
    --proxy "$PROXY" \
    --connect-timeout "$TIMEOUT" \
    --max-time "$((TIMEOUT+8))" \
    -w '%{http_code},%{time_total},%{time_connect},%{time_appconnect},%{time_starttransfer}' \
    "$url" 2>/dev/null || echo "000,$TIMEOUT,$TIMEOUT,$TIMEOUT,$TIMEOUT"
}

pctl(){
  # args: percentile file
  local p="$1" f="$2"
  # Portable: sort + pick index
  local n
  n=$(wc -l < "$f" 2>/dev/null | awk '{print $1}')
  [ -z "$n" ] && { echo "na"; return; }
  [ "$n" -le 0 ] && { echo "na"; return; }
  # idx = ceil(p/100 * n)
  local idx
  idx=$(awk -v P="$p" -v N="$n" 'BEGIN{p=P/100.0; i=int(p*N + 0.999999); if(i<1)i=1; if(i>N)i=N; print i}')
  sort -n "$f" 2>/dev/null | sed -n "${idx}p" || echo "na"
}

for u in "${lat_targets[@]}"; do
  tmp=$(mktemp)
  ok=0
  for i in $(seq 1 "$LAT_N"); do
    out=$(curl_metrics "$u")
    code=${out%%,*}
    rest=${out#*,}
    total=${rest%%,*}
    if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then ok=$((ok+1)); fi
    echo "$total" >> "$tmp"
  done
  p50=$(pctl 50 "$tmp")
  p95=$(pctl 95 "$tmp")
  printf '%-38s ok=%2d/%2d  p50=%ss  p95=%ss\n' "${u}" "$ok" "$LAT_N" "$p50" "$p95"
  rm -f "$tmp"
  [[ "$MODE" == quick ]] && break
done

# ---- Throughput test ----
section "PROXY THROUGHPUT"
DL_URLS=(
  "https://speed.cloudflare.com/__down?bytes=25000000"
  "https://speed.hetzner.de/100MB.bin"
  "https://download.bell-sw.com/java/21.0.5+11/bellsoft-jdk21.0.5+11-linux-amd64.tar.gz"
)

throughput_once(){
  local url="$1"
  local mx="$DL_SECONDS"
  [[ "$MODE" == quick ]] && mx=8
  # code,time,size,speed
  curl -L -s -o /dev/null \
    --proxy "$PROXY" \
    --connect-timeout 6 \
    --max-time "$mx" \
    -w '%{http_code},%{time_total},%{size_download},%{speed_download}' \
    "$url" 2>/dev/null || echo "000,$mx,0,0"
}

calc_mibps(){
  # args: bytes seconds
  awk -v S="$1" -v T="$2" 'BEGIN{ if(T<=0){printf "0.00"; exit} printf "%.2f", (S/(T*1024*1024)) }'
}

chosen=""
for u in "${DL_URLS[@]}"; do
  # Limit large files to a finite range to avoid wasting bandwidth.
  if [[ "$u" == *"hetzner.de/100MB.bin"* ]]; then
    out=$(curl -L -s -o /dev/null --range 0-49999999 --proxy "$PROXY" --connect-timeout 6 --max-time "$([[ "$MODE" == quick ]] && echo 8 || echo "$DL_SECONDS")" -w '%{http_code},%{time_total},%{size_download},%{speed_download}' "$u" 2>/dev/null || echo "000,$DL_SECONDS,0,0")
  else
    out=$(throughput_once "$u")
  fi
  code=${out%%,*}
  t=$(echo "$out" | cut -d',' -f2)
  sz=$(echo "$out" | cut -d',' -f3)
  sp=$(echo "$out" | cut -d',' -f4)
  mibps=$(calc_mibps "${sz:-0}" "${t:-0}")
  # accept 200/206 and >= 1MB
  if [[ "$code" =~ ^(200|206)$ ]] && [ "${sz:-0}" -ge 1000000 ]; then
    chosen="$u"
    printf 'chosen        : %s\n' "$(mask_url "$u")"
    printf 'result        : code=%s time=%ss size=%sB avg=%sMiB/s (curl_speed=%sB/s)\n' "$code" "$t" "$sz" "$mibps" "$sp"
    break
  else
    printf 'skip          : %s -> code=%s size=%sB\n' "$(mask_url "$u")" "$code" "$sz"
  fi
  [[ "$MODE" == quick ]] && break
done

# ---- Concurrency test ----
section "PROXY CONCURRENCY"
C_TARGET=${C_TARGET:-"https://www.cloudflare.com/cdn-cgi/trace"}
REQS=${REQS:-$((CONCURRENCY*3))}

concurrency_run(){
  local par="$1" reqs="$2" url="$3"
  local tmp="$(mktemp)"
  seq 1 "$reqs" | xargs -I{} -P "$par" bash -c '
    u="$0"; p="$1"; to="$2";
    out=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" --proxy "$p" --connect-timeout "$to" --max-time "$((to+6))" "$u" 2>/dev/null || echo "000,$to");
    echo "$out"' "$url" "$PROXY" 6 >> "$tmp"

  ok=$(awk -F, '$1 ~ /^[23][0-9][0-9]$/ {c++} END{print c+0}' "$tmp")
  tot=$(wc -l < "$tmp" | awk '{print $1}')
  # p50/p95 for time_total (portable)
  awk -F, '{print $2}' "$tmp" | sort -n > "${tmp}.t"
  nvals=$(wc -l < "${tmp}.t" | awk '{print $1}')
  idx50=$(awk -v N="$nvals" 'BEGIN{i=int(0.50*N + 0.999999); if(i<1)i=1; if(i>N)i=N; print i}')
  idx95=$(awk -v N="$nvals" 'BEGIN{i=int(0.95*N + 0.999999); if(i<1)i=1; if(i>N)i=N; print i}')
  p50=$(sed -n "${idx50}p" "${tmp}.t" 2>/dev/null || echo na)
  p95=$(sed -n "${idx95}p" "${tmp}.t" 2>/dev/null || echo na)
  printf 'target        : %s\n' "$url"
  printf 'parallel      : %s\n' "$par"
  printf 'requests      : %s\n' "$tot"
  printf 'success       : %s/%s\n' "$ok" "$tot"
  printf 'time_total    : p50=%ss p95=%ss\n' "${p50:-na}" "${p95:-na}"
  rm -f "$tmp" "${tmp}.t"
}

concurrency_run "$CONCURRENCY" "$REQS" "$C_TARGET"

# ---- System quick hints ----
section "SYSTEM HINTS"
cur_nofile=$(ulimit -n 2>/dev/null || echo "?")
echo "ulimit -n     : ${cur_nofile} (recommend >= 65535 for high concurrency)"
if have sysctl; then
  echo "somaxconn     : $(sysctl -n net.core.somaxconn 2>/dev/null || echo '?') (recommend 4096+)"
  echo "rmem_max      : $(sysctl -n net.core.rmem_max 2>/dev/null || echo '?') (recommend 8388608+)"
  echo "wmem_max      : $(sysctl -n net.core.wmem_max 2>/dev/null || echo '?') (recommend 8388608+)"
fi

# ---- Recommendations + optional tighten ----
section "RECOMMENDATIONS"

# Heuristic: if tailscale ping shows any DERP hits, flag.
if have tailscale; then
  if [ "${derp_cnt:-0}" -gt 0 ]; then
    echo "DERP detected  : ${NH_WARN:-WARN} (some pings via DERP)"
    cat <<'EOF'
Action ideas:
  - Ensure outbound UDP is allowed (especially UDP 41641) on current network.
  - Check local firewall (ufw/firewalld) and campus/ISP UDP restrictions.
  - Run: tailscale netcheck  (look for 'UDP: true' and DERP latencies)
  - If consistently stuck on DERP, expect higher jitter; keep a limited fallback in AUTO-SMART.
EOF
  else
    echo "DERP detected  : ${NH_OK:-OK} (ping looks direct)"
  fi
fi

cat <<EOF
Mihomo config hints (JP-Tailscale):
  - You already have: interface-name: ${TS_IFACE} (good; reduces multi-NIC surprises)
  - If you see random stalls under load: consider raising process NOFILE limit for user systemd service.
  - If DNS pollution hits again: keep FINAL MATCH -> AUTO-SMART and keep wikipedia/wikimedia/wikidata pinned (already handled).
EOF

if [ "$APPLY_TIGHTEN" = 1 ]; then
  section "APPLY: TIGHTEN AUTO-SMART"
  MIXIN="$HOME/.local/share/clash/mixin.yaml"
  if [ ! -f "$MIXIN" ]; then
    echo "mixin missing : $MIXIN" >&2
    exit 1
  fi

  YQ_BIN=""
  if have "$HOME/.local/share/clash/bin/yq"; then YQ_BIN="$HOME/.local/share/clash/bin/yq"; elif have yq; then YQ_BIN="yq"; fi
  if [ -z "$YQ_BIN" ]; then
    echo "yq required   : cannot find yq; abort tighten" >&2
    exit 1
  fi

  # Desired tightened list
  desired_proxies=()
  if [ "$FALLBACK_MODE" = minimal ]; then
    desired_proxies=("JP-Tailscale" "故障转移")
  else
    desired_proxies=("JP-Tailscale" "故障转移" "🇯🇵 JP-自动选择" "🇸🇬 SG-自动选择" "🇭🇰 HK-自动选择")
  fi

  # If already tightened, do not touch config nor restart (prevents VS Code/Electron network drop).
  current_auto=$(
    "$YQ_BIN" e -o=json '."proxy-groups"[] | select(.name=="AUTO-SMART") | (.proxies // [])' "$MIXIN" 2>/dev/null || echo "[]"
  )
  desired_auto=$(printf '%s\n' "${desired_proxies[@]}" | "$YQ_BIN" e -o=json -N '(. | split("\n") | map(select(length>0)))' - 2>/dev/null || echo "[]")
  if [ "$current_auto" = "$desired_auto" ]; then
    echo "tighten        : already applied (mode=$FALLBACK_MODE); skip rebuild"
    section "DONE"
    echo "Finished at    : $(date '+%T')"
    exit 0
  fi

  bak="${MIXIN}.bak.$(date +%Y%m%d_%H%M%S)"
  cp -f "$MIXIN" "$bak"
  echo "backup        : $bak"

  # Build tightened list
  if [ "$FALLBACK_MODE" = minimal ]; then
    # minimal: just JP-Tailscale + a single selector fallback group
    "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="AUTO-SMART") | .proxies) = ["JP-Tailscale","故障转移"]' "$MIXIN" 2>/dev/null || true
  else
    # balanced: JP first + limited region auto-selectors
    "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="AUTO-SMART") | .proxies) = ["JP-Tailscale","故障转移","🇯🇵 JP-自动选择","🇸🇬 SG-自动选择","🇭🇰 HK-自动选择"]' "$MIXIN" 2>/dev/null || true
  fi

  # Compatibility group: 速云梯 should point to AUTO-SMART/JP only (avoid loops)
  "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="速云梯") | .proxies) = ["AUTO-SMART","JP-Tailscale"]' "$MIXIN" 2>/dev/null || true

  echo "tighten        : done (mode=$FALLBACK_MODE)"

  echo "rebuild runtime: merging+sanitizing+restart..."
  # Rebuild runtime using repo scripts (no subscription download)
  # NOTE: CLASH_LIB_MODE must be set BEFORE sourcing clashctl.sh, otherwise the script may run its CLI path.
  if ! ( cd "$REPO_DIR" && bash -c 'set -e; export CLASH_LIB_MODE=1 CLASH_ERROR_MODE=exit; source script/common.sh; source script/clashctl.sh; _merge_sanitize_restart' ); then
    # If rebuild returns non-zero, verify whether it still applied (sometimes restart step returns non-zero but runtime is already updated).
    if [ -n "${API_BASE:-}" ] && [ -n "$(api_get "${API_BASE}/version" "${SECRET}")" ]; then
      now_all=$(api_get "${API_BASE}/proxies/${GROUP_TO_SWITCH}" "${SECRET}" | tr '\n' ' ')
      if echo "$now_all" | grep -q '"all"\s*:\s*\["JP-Tailscale","故障转移"\]'; then
        echo "apply result   : ${NH_WARN:-WARN} rebuild returned non-zero, but controller already reflects tightened AUTO-SMART"
      else
        echo "apply result   : ${NH_FAIL:-FAIL} runtime rebuild failed" >&2
        echo "hint           : you can restore from backup: $bak" >&2
        exit 1
      fi
    else
      echo "apply result   : ${NH_FAIL:-FAIL} runtime rebuild failed" >&2
      echo "hint           : you can restore from backup: $bak" >&2
      exit 1
    fi
  fi

  echo "apply result   : ${NH_OK:-OK}"
else
  echo "tighten        : skipped (use --apply-tighten to apply)"
fi

section "DONE"
echo "Finished at    : $(date '+%T')"
