#!/bin/bash

# One-click Zoom diagnose/repair
# - DNS check (avoid fake-ip 198.18.0.0/15)
# - HTTPS reachability and latency via Clash proxy
# - Auto-switch Streaming group to a working/fast node using Clash API
#
# Usage:
#   ./fix_zoom_connectivity.sh                          # default host us05web.zoom.us
#   ./fix_zoom_connectivity.sh https://us05web.zoom.us/j/xxxxxxxx   # meeting URL
#   HOST=us06web.zoom.us ./fix_zoom_connectivity.sh     # override host
#   PROXY=http://127.0.0.1:7890 ./fix_zoom_connectivity.sh
#   CLASH_API=http://127.0.0.1:9090 ./fix_zoom_connectivity.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load env (optional) and bootstrap controller/secret (env override -> legacy compat -> runtime.yaml -> default)
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true

clash_env_bootstrap 2>/dev/null || true

API=${CLASH_API:-http://127.0.0.1:9090}
PROXY=${PROXY:-http://127.0.0.1:7890}
TIMEOUT=${TIMEOUT:-6}
GROUP=${GROUP:-}
APPLY=0

usage(){
  cat <<EOF
One-click Zoom diagnose/repair (preview by default).

Usage:
  $0 [--apply] [--group NAME] [--proxy URL] [--timeout SEC] [meeting_url|host]

Notes:
  - Without --apply, this script may temporarily switch nodes to probe, then restores the original selection.
  - With --apply, it will keep the best candidate node selected in the target group.
EOF
}

arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift;;
    --group) GROUP="$2"; shift 2;;
    --proxy) PROXY="$2"; shift 2;;
    --timeout) TIMEOUT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) arg="$1"; shift; break;;
  esac
done

have(){ command -v "$1" >/dev/null 2>&1; }
err(){ echo "[ERROR] $*" >&2; }
info(){ echo "[INFO]  $*" >&2; }
ok(){ echo "[OK]   $*" >&2; }

parse_host_from_url(){
  local u="$1"
  if [[ -z "$u" ]]; then echo ""; return; fi
  # crude host extraction
  echo "$u" | sed -E 's#^[a-zA-Z]+://##' | cut -d'/' -f1 | cut -d'?' -f1
}

host_default=${HOST:-us05web.zoom.us}
meeting_url=""
if [[ -n "$arg" ]]; then
  if [[ "$arg" =~ ^https?:// ]]; then
    meeting_url="$arg"
    host=$(parse_host_from_url "$arg")
  else
    host="$arg"
  fi
else
  host="$host_default"
fi

[[ -z "$host" ]] && { err "Could not determine Zoom host"; exit 2; }

echo "===== Zoom Diagnose/Repair ====="
echo "Host       : $host"
[[ -n "$meeting_url" ]] && echo "Meeting URL: $meeting_url"
echo "Proxy     : $PROXY"
echo "API       : $API ($GROUP)"
echo "================================"

# 1) DNS check (avoid fake-ip range 198.18.0.0/15)
dns_ips=()
if have getent; then
  mapfile -t dns_ips < <(getent ahosts "$host" | awk '{print $1}' | sort -u)
elif have dig; then
  mapfile -t dns_ips < <(dig +short "$host" A | sort -u)
else
  info "getent/dig not found; skip DNS listing"
fi

if ((${#dns_ips[@]})); then
  echo "DNS IPs: ${dns_ips[*]}"
  bad=$(printf '%s\n' "${dns_ips[@]}" | grep -E '^(198\.1[89]\.)') || true
  if [[ -n "$bad" ]]; then
    err "Detected fake-ip like address(es): $bad"
    echo "Hint: We already disabled Fake-IP for *.zoom.us in mixin. Reload Clash if just changed."
  else
    ok "DNS looks like real IPs (no 198.18/198.19)"
  fi
fi

# 2) HTTPS reachability test function
curl_test(){ # url -> prints code,time
  local url="$1"
  curl -sS -o /dev/null -w '%{http_code},%{time_total}' \
    --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+2))" \
    --proxy "$PROXY" "$url" 2>/dev/null || echo "000,$TIMEOUT"
}

test_zoom_basic(){
  local base="https://$host/"
  local out code t pass=0 total=0
  for url in "$base" "https://zoom.us/" "https://r.zoom.us/" "https://static.zoom.us/"; do
    ((++total))
    out=$(curl_test "$url"); code=${out%%,*}; t=${out##*,}; status=FAIL
    if [[ $code =~ ^[23][0-9][0-9]$ ]]; then status=OK; ((++pass)); fi
    printf '%-35s %s (%s s)\n' "$url" "$status/$code" "$t"
  done
  echo "$pass/$total"
}

# 3) If API reachable, prepare node list under GROUP
api_up=0
if declare -F clash_api_get >/dev/null 2>&1; then
  if clash_api_get /version >/dev/null 2>&1; then api_up=1; else info "Clash API not reachable; skip auto-switch"; fi
else
  if curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "$API/version" >/dev/null 2>&1; then api_up=1; else info "Clash API not reachable; skip auto-switch"; fi
fi

group_enc="$GROUP"
if declare -F clash_urlencode >/dev/null 2>&1 && [[ -n "${GROUP:-}" ]]; then
  group_enc="$(clash_urlencode "$GROUP")"
fi

switch_node(){ # name
  local name="$1" payload
  payload=$(printf '{"name":"%s"}' "$name")
  if declare -F clash_api_put_json >/dev/null 2>&1; then
    clash_api_put_json "/proxies/$group_enc" "$payload" >/dev/null 2>&1 || return 1
  else
    curl -s --noproxy '*' --connect-timeout 2 --max-time 4 -X PUT "$API/proxies/$group_enc" -H 'Content-Type: application/json' -d "$payload" >/dev/null || return 1
  fi
}

get_nodes(){
  if ! ((api_up)); then return; fi
  local j
  if declare -F clash_api_get >/dev/null 2>&1; then
    j=$(clash_api_get "/proxies/$group_enc" 2>/dev/null || true)
  else
    j=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "$API/proxies/$group_enc" 2>/dev/null || true)
  fi
  if [[ -z "$j" ]]; then return; fi
  if have jq; then
    echo "$j" | jq -r '.all[]'
  else
    echo "$j" | sed -n 's/.*"all":\[\(.*\)\].*/\1/p' | tr '"' '\n' | sed '/^$/d'
  fi
}

best_node=""
best_score=-1
best_time=9999

echo
echo "Step 1: Basic reachability test (current node)"
score=$(test_zoom_basic)
echo "Score: $score"

if (( api_up )); then
  echo
  echo "Step 2: Auto-switch within $GROUP to find a working node"
  if [[ -z "${GROUP:-}" ]] && declare -F clash_pick_selector_group >/dev/null 2>&1; then
    GROUP="$(clash_pick_selector_group "Streaming" "STREAMING" "YOUTUBE" "YouTube" "MEDIA" "流媒体" 2>/dev/null || true)"
  fi
  GROUP=${GROUP:-Streaming}
  group_enc="$GROUP"
  if declare -F clash_urlencode >/dev/null 2>&1 && [[ -n "${GROUP:-}" ]]; then
    group_enc="$(clash_urlencode "$GROUP")"
  fi
  original=""
  if declare -F clash_group_now >/dev/null 2>&1; then
    original="$(clash_group_now "$GROUP" 2>/dev/null || true)"
  fi
  mapfile -t nodes < <(get_nodes)
  if ((${#nodes[@]}==0)); then
    info "No nodes found in group $GROUP";
  else
    echo "Candidates: ${#nodes[@]} (testing up to 8)"
    count=0
    for n in "${nodes[@]}"; do
      ((++count)); ((count>8)) && break
      echo "- Probing $n ..." >&2
      switch_node "$n"; sleep 1
      out=$(curl_test "https://$host/"); code=${out%%,*}; t=${out##*,}
      if [[ $code =~ ^[23][0-9][0-9]$ ]]; then
        ok "$n OK ($code in ${t}s)"
        # use smaller time as better
        # compute integer ms for compare
        tms=$(awk -v v="$t" 'BEGIN{print int(v*1000+0.5)}')
        if (( best_score<1 )) || (( tms<best_time )); then best_node="$n"; best_score=1; best_time=$tms; fi
      else
        info "$n FAIL ($code)"
      fi
    done
    if [[ -n "$best_node" ]]; then
      if (( APPLY == 1 )); then
        echo "Applying best node: $best_node"
        switch_node "$best_node"; sleep 1
        ok "Switched $GROUP -> $best_node"
      else
        info "(preview) Best candidate: $best_node (run with --apply to keep it)"
        if [[ -n "${original:-}" ]]; then
          switch_node "$original" >/dev/null 2>&1 || true
        fi
      fi
    else
      info "No passing node found in quick probe"
    fi
  fi
fi

echo
echo "Step 3: Verify after potential switch"
final=$(test_zoom_basic)
echo "Score: $final"

if [[ -n "$meeting_url" ]]; then
  echo
  echo "Step 4: Check meeting URL"
  out=$(curl_test "$meeting_url"); code=${out%%,*}; t=${out##*,}
  echo "$meeting_url -> $code in ${t}s"
fi

echo
echo "Summary"
echo "- Host       : $host"
echo "- Initial    : $score"
echo "- After      : $final"
[[ -n "$best_node" ]] && echo "- Selected   : $best_node ($((best_time)) ms)"
echo "- Proxy      : $PROXY"
echo "- Group      : $GROUP"

echo
if [[ "$final" =~ ^[2-4]/[2-4]$ ]]; then
  ok "Zoom likely reachable now."
  exit 0
else
  err "Zoom may still be blocked. Try switching Streaming node manually or change region."
  exit 1
fi
