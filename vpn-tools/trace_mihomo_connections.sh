#!/usr/bin/env bash
# DESCRIPTION:
#   Live-trace mihomo/clash controller /connections and print matching connections.
#   Useful to prove whether VS Code/Copilot traffic is reaching mihomo, and which rule/chain it hits.
#
# USAGE:
#   FILTER='github\.com|githubusercontent\.com|wxiai' PROCESS_RE='code|Code|electron|node|git' \
#     ./trace_mihomo_connections.sh --seconds 30 --interval 0.5
#
# NOTES:
#   - Reads controller address + secret from: ~/.local/share/clash/runtime.yaml
#   - Prints: process, host, dst, rule, rulePayload, chains

set -euo pipefail

DURATION=30
INTERVAL=0.5
FILTER="${FILTER:-github\\.com|githubusercontent\\.com|githubassets\\.com|codeload\\.github\\.com|raw\\.githubusercontent\\.com|api\\.github\\.com}"
PROCESS_RE="${PROCESS_RE:-code|Code|electron|node|git}"

usage(){
  cat <<EOF
Usage:
  FILTER='<regex>' PROCESS_RE='<regex>' bash vpn-tools/trace_mihomo_connections.sh [--seconds N] [--interval S]

Env:
  FILTER      Regex applied to .metadata.host and .metadata.destinationIP/.destinationPort string
  PROCESS_RE  Regex applied to .metadata.process (best-effort; empty process is allowed)

Notes:
  - Reads controller address + secret from: ~/.local/share/clash/runtime.yaml
  - Requires: jq, curl, yq (preferred) or falls back to grep parsing.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --seconds) DURATION="$2"; shift 2;;
    --interval) INTERVAL="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

case "$DURATION" in ''|*[!0-9]*) echo "--seconds must be integer" >&2; exit 2;; esac
case "$INTERVAL" in ''|*[!0-9.]*) echo "--interval must be a positive number" >&2; exit 2;; esac

RUNTIME="${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}"
YQ_BIN="${BIN_YQ:-$HOME/.local/share/clash/bin/yq}"

[ -f "$RUNTIME" ] || { echo "runtime.yaml not found: $RUNTIME" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }

ui_addr="127.0.0.1:9090"
secret=""
if [ -x "$YQ_BIN" ]; then
  ui_addr=$($YQ_BIN -r '."external-controller" // "127.0.0.1:9090"' "$RUNTIME" 2>/dev/null || echo '127.0.0.1:9090')
  secret=$($YQ_BIN -r '.secret // ""' "$RUNTIME" 2>/dev/null || echo '')
else
  ui_addr=$(grep -E '^ *external-controller:' "$RUNTIME" | tail -n1 | cut -d: -f2- | tr -d " '\"" || echo '127.0.0.1:9090')
  secret=$(grep -E '^ *secret:' "$RUNTIME" | tail -n1 | cut -d: -f2- | tr -d " '\"" || echo '')
fi
ui_addr=$(printf '%s' "$ui_addr" | tr -d "\"'")
secret=$(printf '%s' "$secret" | tr -d "\"'")

ui_host="${ui_addr%:*}"
ui_port="${ui_addr##*:}"
case "$ui_host" in
  ''|0.0.0.0|::) ui_host='127.0.0.1' ;;
esac
api="http://${ui_host}:${ui_port}"

hdr=()
[ -n "$secret" ] && hdr=(-H "Authorization: Bearer $secret")

end=$(( $(date +%s) + DURATION ))

echo "Tracing controller ${api} for ${DURATION}s (interval=${INTERVAL}s)"
echo "Filter host =~ /$FILTER/  process =~ /$PROCESS_RE/"
echo

# Print a compact line per match; dedupe by connection id to reduce spam.
# NOTE: Do NOT use a pipeline to feed the while-read loop, otherwise dedupe state
# will be lost in a subshell.
declare -A seen_ids=()
DELIM=$'\x1f'

while [ $(date +%s) -lt "$end" ]; do
  json=$(curl -sS --connect-timeout 1 --max-time 2 "${hdr[@]}" "${api}/connections" 2>/dev/null || echo '{}')

  while IFS="$DELIM" read -r id proc host dst rule payload chains; do
    [ -z "${id:-}" ] && continue
    # dedupe by id
    if [[ -n "${seen_ids[$id]+x}" ]]; then
      continue
    fi
    seen_ids[$id]=1
    ts=$(date '+%H:%M:%S')
    [ -z "${proc:-}" ] && proc='?'
    printf '[%s] proc=%s host=%s dst=%s rule=%s payload=%s chains=%s\n' "$ts" "$proc" "$host" "$dst" "$rule" "$payload" "$chains"
  done < <(
    echo "$json" | jq -r --arg re "$FILTER" --arg pre "$PROCESS_RE" '
      .connections // []
      | map({
          id,
          host:(.metadata.host // ""),
          dst:((.metadata.destinationIP // "") + ":" + ((.metadata.destinationPort // 0)|tostring)),
          process:(.metadata.process // ""),
          rule:(.rule // ""),
          rulePayload:(.rulePayload // ""),
          chains:(.chains // [])
        })
      | map(select((.host|test($re)) or (.dst|test($re))))
      | map(select((.process|test($pre)) or (.process=="")))
      | .[]
      | "\(.id)\u001f\(.process)\u001f\(.host)\u001f\(.dst)\u001f\(.rule)\u001f\(.rulePayload)\u001f\(.chains|@json)"'
  )

  sleep "$INTERVAL"
done
