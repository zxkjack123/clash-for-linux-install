#!/bin/bash

# DESCRIPTION:
#   Minimal sequential test across all nodes of AI group (names fetched live) with
#   just OpenAI API + Claude reachability + simple latency baseline (google) for
#   quick heuristic ranking. Does not persist best choice.
#
# USAGE:
#   ./test_ai_simple.sh
#
set -euo pipefail
API=${CLASH_API:-http://127.0.0.1:9090}
GROUP=AI
TIMEOUT=6

if ! curl -fsS "$API/version" >/dev/null 2>&1; then echo "Controller unreachable" >&2; exit 1; fi
json=$(curl -fsS "$API/proxies/$GROUP") || { echo "Cannot fetch group" >&2; exit 1; }
have_jq=false; command -v jq >/dev/null 2>&1 && have_jq=true
if $have_jq; then mapfile -t nodes < <(echo "$json" | jq -r '.all[]'); else nodes=($(echo "$json" | sed -n 's/.*"all":\[\(.*\)\].*/\1/p' | tr '"' '\n' | sed '/^$/d')); fi

switch() { curl -s -X PUT "$API/proxies/$GROUP" -H 'Content-Type: application/json' -d '{"name":"'"$1"'"}' >/dev/null; }
probe() { # url label
	curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+2))" "$1" 2>/dev/null || echo "000,$TIMEOUT"; }

printf "%s\n" "Node,OpenAI,Claude,BaseLatency,Score"
for n in "${nodes[@]}"; do
	switch "$n"; sleep 2
	o=$(probe https://api.openai.com/v1/models openai); oc=${o%%,*}; ot=${o##*,}
	c=$(probe https://claude.ai/ claude);  cc=${c%%,*}; ct=${c##*,}
	b=$(probe https://www.google.com/ base); bc=${b%%,*}; bt=${b##*,}
	score=0
	[[ $oc =~ ^2|3 ]] && ((score+=3))
	[[ $cc =~ ^2|3 ]] && ((score+=3))
	if (( $(echo "$bt < 2" | bc -l 2>/dev/null || echo 0) )); then ((score+=4)); elif (( $(echo "$bt < 4" | bc -l 2>/dev/null || echo 0) )); then ((score+=2)); fi
	printf '"%s",%s/%s,%s/%s,%s/%s,%s\n' "$n" "$oc" "$ot" "$cc" "$ct" "$bc" "$bt" "$score"
done

