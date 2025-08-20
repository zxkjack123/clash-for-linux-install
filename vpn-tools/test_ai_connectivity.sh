#!/bin/bash
# AI connectivity test (clean rebuild)
# Usage: ./test_ai_connectivity.sh [--group AI] [--rounds 5] [--limit N] [--apply] [--json out.json] [--md report.md]
set -euo pipefail

API=${CLASH_API:-http://127.0.0.1:9090}
GROUP=AI
ROUNDS=5
LIMIT=0
APPLY=0
JSON_OUT=""
MD_OUT=""
QUIET=0

# Secret autodetect
API_SECRET=${CLASH_API_SECRET:-}
if [[ -z $API_SECRET ]]; then
  for f in "$(dirname "$0")/../resources/mixin.yaml" "$(dirname "$0")/../resources/config.yaml" "$(dirname "$0")/../config.yaml"; do
    [[ -z $API_SECRET && -f $f ]] || continue
    s=$(grep -E '^secret:' "$f" | awk '{print $2}' | head -n1 || true)
    [[ -n ${s:-} ]] && API_SECRET=$s
  done
fi
AUTH_HEADER=()
[[ -n $API_SECRET ]] && AUTH_HEADER=(-H "Authorization: Bearer $API_SECRET")

have(){ command -v "$1" >/dev/null 2>&1; }
log(){ [[ $QUIET -eq 1 ]] || echo "$@" >&2; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --group) GROUP=$2; shift 2;;
    --rounds) ROUNDS=$2; shift 2;;
    --limit) LIMIT=$2; shift 2;;
    --apply) APPLY=1; shift;;
    --json) JSON_OUT=$2; shift 2;;
    --md) MD_OUT=$2; shift 2;;
    -q|--quiet) QUIET=1; shift;;
    -h|--help) grep -E '^#' "$0" | head -n 40; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if ! curl -fsS "${AUTH_HEADER[@]}" "$API/version" >/dev/null 2>&1; then
  echo "Controller unreachable $API" >&2; exit 1
fi

nodes_json=$(curl -fsS "${AUTH_HEADER[@]}" "$API/proxies/$GROUP") || { echo "Cannot fetch group $GROUP" >&2; exit 1; }
if have jq; then
  mapfile -t NODES < <(echo "$nodes_json" | jq -r '.all[]' | sed 's/ /%20/g')
else
  NODES=($(echo "$nodes_json" | sed -n 's/.*"all":\[\([^]]*\)\].*/\1/p' | tr '"' '\n' | sed '/^$/d' | sed 's/ /%20/g'))
fi
[[ ${#NODES[@]} -eq 0 ]] && { echo "No nodes in group $GROUP" >&2; exit 1; }
if [[ $LIMIT -gt 0 && ${#NODES[@]} -gt $LIMIT ]]; then NODES=(${NODES[@]:0:$LIMIT}); fi

ENDPOINTS=(
  "chatgpt:https://chat.openai.com/"
  "braintrust:https://api.braintrustdata.com/health"
  "huggingface:https://huggingface.co/"
  "ghapi:https://api.github.com/"
  "latency1:https://www.gstatic.com/generate_204"
  "latency2:https://www.cloudflare.com/cdn-cgi/trace"
)

declare -A MET

curl_probe(){ local url=$1 out code t; out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --max-time 12 "$url" || true); code=${out%%,*}; t=${out##*,}; [[ -z $code ]] && code=000; echo "$code,$t"; }
percentile(){ local p=$1; shift; local arr=($(printf '%s\n' "$@" | sort -n)); local n=${#arr[@]}; [[ $n -eq 0 ]] && { echo 0; return; }; [[ $n -eq 1 ]] && { echo ${arr[0]}; return; }; local rank=$(awk -v p=$p -v n=$n 'BEGIN{print (p/100)*(n-1)}'); local lo=${rank%.*}; local hi=$((lo+1)); (( hi>=n )) && hi=$lo; local frac=$(awk -v r=$rank -v l=$lo 'BEGIN{print r-l}'); awk -v a=${arr[$lo]} -v b=${arr[$hi]} -v f=$frac 'BEGIN{print a+(b-a)*f}'; }
score_node(){ local sr=$1 med=$2 p95=$3; awk -v sr=$sr -v m=$med -v p=$p95 'BEGIN{s=sr*60; L=(m*0.6+p*0.4); l=(L>4?0:(4-L)/4*30); printf "%.2f", s+l}'; }
apply_group(){ curl -fsS -X PUT "${AUTH_HEADER[@]}" "$API/proxies/$GROUP" -H 'Content-Type: application/json' -d '{"name":"'"$1"'"}' >/dev/null 2>&1; }

log "Group=$GROUP Nodes=${#NODES[@]} Rounds=$ROUNDS"
start=$(date +%s)
for node in "${NODES[@]}"; do
  decoded=${node//%20/ }
  curl -fsS -X PUT "${AUTH_HEADER[@]}" "$API/proxies/$GROUP" -H 'Content-Type: application/json' -d '{"name":"'"$decoded"'"}' >/dev/null || { log "Switch fail $decoded"; continue; }
  sleep 1
  lat=(); attempts=0; successes=0
  for ((r=1;r<=ROUNDS;r++)); do
    mapfile -t SHUF < <(printf '%s\n' "${ENDPOINTS[@]}" | shuf)
    for ep in "${SHUF[@]}"; do
      svc=${ep%%:*}; url=${ep#*:}; res=$(curl_probe "$url"); code=${res%%,*}; t=${res##*,}; attempts=$((attempts+1))
      if [[ $code == 200 || $code == 204 || $code == 101 ]]; then successes=$((successes+1)); lat+=($t); fi
    done
    if [[ $r -eq 2 ]]; then sr_tmp=$(awk -v s=$successes -v a=$attempts 'BEGIN{if(a==0)print 0; else print s/a}'); awk -v v=$sr_tmp 'BEGIN{exit !(v<0.3)}'; [[ $? -eq 0 ]] && break; fi
  done
  sr=$(awk -v s=$successes -v a=$attempts 'BEGIN{if(a==0)print 0; else print s/a}')
  med=$(percentile 50 "${lat[@]}"); p95=$(percentile 95 "${lat[@]}")
  sc=$(score_node $sr $med $p95)
  MET[$node.sr]=$sr; MET[$node.med]=$med; MET[$node.p95]=$p95; MET[$node.score]=$sc; MET[$node.rounds]=$ROUNDS
done

best=""; best_score=0
for n in "${NODES[@]}"; do s=${MET[$n.score]:-0}; awk -v s=$s -v b=$best_score 'BEGIN{exit !(s>b)}'; [[ $? -eq 0 ]] && { best=$n; best_score=$s; }; done
decoded_best=${best//%20/ }
elapsed=$(( $(date +%s)-start ))

printf '\n%-30s %7s %8s %8s %8s %6s\n' Node Score SRate Med P95 Rounds
printf '%s\n' '--------------------------------------------------------------'
for n in "${NODES[@]}"; do printf '%-30s %7s %8.2f %8.2f %8.2f %6s\n' "${n//%20/ }" "${MET[$n.score]:-0}" "${MET[$n.sr]:-0}" "${MET[$n.med]:-0}" "${MET[$n.p95]:-0}" "${MET[$n.rounds]:-0}"; done | sort -k2 -nr
echo; echo "Best node: $decoded_best (score=${MET[$best.score]:-0}) Elapsed:${elapsed}s"

[[ $APPLY -eq 1 ]] && { apply_group "$decoded_best" && echo "Applied best to $GROUP" || echo "Apply failed" >&2; }

if [[ -n $JSON_OUT ]]; then
  { echo '{"group":"'$GROUP'","rounds":'$ROUNDS',"elapsed":'$elapsed',"best":"'${decoded_best//"/\\"}'","nodes":['; f=1; for n in "${NODES[@]}"; do [[ $f -eq 1 ]] || echo ','; f=0; printf '{"name":"%s","score":%s,"success_ratio":%.4f,"latency_med":%.4f,"latency_p95":%.4f,"rounds":%s}' "${n//%20/ }" "${MET[$n.score]:-0}" "${MET[$n.sr]:-0}" "${MET[$n.med]:-0}" "${MET[$n.p95]:-0}" "${MET[$n.rounds]:-0}"; done; echo ']}'; } > "$JSON_OUT"; echo "Wrote JSON $JSON_OUT"; fi

if [[ -n $MD_OUT ]]; then
  { echo "# AI Connectivity Test"; echo; echo "Group: $GROUP  Rounds: $ROUNDS  Elapsed: ${elapsed}s  Generated: $(date '+%F %T')"; echo; echo "Best Node: **$decoded_best** (Score ${MET[$best.score]:-0})"; echo; echo '| Node | Score | Success% | Median | P95 | Rounds |'; echo '|------|------:|---------:|------:|----:|-------:|'; for n in "${NODES[@]}"; do printf '| %s | %s | %.0f | %.2f | %.2f | %s |\n' "${n//%20/ }" "${MET[$n.score]:-0}" "$(awk -v v=${MET[$n.sr]:-0} 'BEGIN{print v*100}')" "${MET[$n.med]:-0}" "${MET[$n.p95]:-0}" "${MET[$n.rounds]:-0}"; done | sort -t '|' -k3 -nr; } > "$MD_OUT"; echo "Wrote markdown $MD_OUT"; fi

exit 0
