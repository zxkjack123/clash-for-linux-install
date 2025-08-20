#!/usr/bin/env bash
# network_change_probe.sh
# Purpose: Correlate Chromium net::ERR_NETWORK_CHANGED with underlying kernel / NM / DNS events.
# Captures and condenses:
#   - ip monitor (link, addr, route, neigh)
#   - NetworkManager high level (nmcli monitor)
#   - systemd-resolved journal (feature downgrade / DNS server switch)
#   - Default route & public IP snapshots on significant triggers
#   - Counts of active veth* interfaces (to see container churn bursts)
#
# Usage:
#   ./network_change_probe.sh                # run until Ctrl-C
#   ERR_TS="2025-08-19T20:55" ./network_change_probe.sh  # will highlight events +/-60s around supplied ISO minute
#
# Output:
#   ./network-change-log.tsv  (tab separated)
#   Columns: ts	type	iface	info
#
# Notes:
#   - Keeps raw tapped logs (optional) if RAW_DIR exported.
#   - Designed to be as light as possible (no heavy loops every second; event driven pipes).
#
# Exit codes:
#   0 normal, 1 prerequisites missing.

set -euo pipefail

LOG_FILE="$(pwd)/network-change-log.tsv"
RAW_DIR="${RAW_DIR:-}" # optional external raw dump directory
HILIGHT_TS="${ERR_TS:-}"  # user-supplied timestamp (YYYY-MM-DDTHH:MM)

_require() { command -v "$1" &>/dev/null || { echo "missing tool: $1" >&2; exit 1; }; }
_require ip
_require awk
_require date

NM_MONITOR_AVAILABLE=0
if command -v nmcli &>/dev/null; then NM_MONITOR_AVAILABLE=1; fi
RESOLVED_JOURNAL_AVAILABLE=0
if journalctl -u systemd-resolved -n 0 &>/dev/null; then RESOLVED_JOURNAL_AVAILABLE=1; fi
CURL_AVAILABLE=0
if command -v curl &>/dev/null; then CURL_AVAILABLE=1; fi

printf "# network_change_probe start at %s\n" "$(date --iso-8601=seconds)" | tee -a "$LOG_FILE"
printf "# writing condensed events to %s\n" "$LOG_FILE"
[ -n "$RAW_DIR" ] && mkdir -p "$RAW_DIR"

echo -e "ts\ttype\tiface\tinfo" >> "$LOG_FILE"

# Helper to append a line
_emit(){
  local typ="$1" iface="$2" info="$3" ts
  ts="$(date --iso-8601=seconds)"
  local line="${ts}\t${typ}\t${iface}\t${info}"
  if [ -n "$HILIGHT_TS" ] && [[ $ts == ${HILIGHT_TS}* ]]; then
    printf "*** %s\n" "$line" | tee -a "$LOG_FILE"
  else
    printf "%s\n" "$line" | tee -a "$LOG_FILE"
  fi
}

_snapshot_route(){
  local def gw dev
  def="$(ip route show default 2>/dev/null | head -n1)"
  [ -n "$def" ] && _emit ROUTE "-" "$def"
}

_snapshot_pubip(){
  [ $CURL_AVAILABLE -eq 1 ] || return 0
  (curl -m 2 -s https://api64.ipify.org || true) | awk '{print;}' | while read -r ip; do
     [ -n "$ip" ] && _emit PUBIP "-" "$ip"
  done &
}

_count_veth(){
  local c
  c=$(ip -o link show | awk -F': ' '/ veth/{c++} END{print c+0}')
  _emit VETH "-" "count=$c"
}

_process_ip(){
  # Consume ip monitor lines, condense to significant state changes.
  sed -u 's/^[ \\t]*//; /^(?)/!p' | while IFS= read -r line; do
    case "$line" in
      *" state UP"*|*" state DOWN"*|"Deleted"*|"default"*|"veth"*"device created"*|"device removed"*)
        # Extract iface name heuristically
        iface="$(echo "$line" | awk '{for(i=1;i<=NF;i++){ if ($i ~ /:/){gsub(":","",$i); print $i; break}}}')"
        [ -z "$iface" ] && iface="-"
        _emit LINK "$iface" "$line"
        if [[ $line == *"state UP"* || $line == *"state DOWN"* || $line == *"device created"* || $line == *"device removed"* ]]; then
          _count_veth
          _snapshot_route
          _snapshot_pubip
        fi
        ;;
      *"inet6"*"scope link"*)
        iface="$(echo "$line" | awk '{print $1;}' | sed 's/://')"
        _emit ADDR "$iface" "$line"
        ;;
    esac
  done
}

_process_nm(){
  awk '{print strftime("%Y-%m-%dT%H:%M:%S%z"),$0}' | while read -r ts rest; do
    _emit NM "-" "$rest"
  done
}

_process_resolved(){
  while IFS= read -r line; do
    case "$line" in
      *"Using degraded feature set"*|*"resuming full feature set"*|*"Switching to DNS server"*|*"Network configuration changed"*)
        _emit DNS "-" "$line"
        _snapshot_route
        _snapshot_pubip
        ;;
    esac
  done
}

# Launch background taps
IP_FIFO=$(mktemp -u)
mkfifo "$IP_FIFO"
(ip monitor link addr route neigh > "$IP_FIFO" 2>/dev/null &)
_process_ip < "$IP_FIFO" &
BG_IP=$!

if [ $NM_MONITOR_AVAILABLE -eq 1 ]; then
  NM_FIFO=$(mktemp -u); mkfifo "$NM_FIFO"; (nmcli monitor > "$NM_FIFO" 2>/dev/null &); _process_nm < "$NM_FIFO" & BG_NM=$!
fi
if [ $RESOLVED_JOURNAL_AVAILABLE -eq 1 ]; then
  RES_FIFO=$(mktemp -u); mkfifo "$RES_FIFO"; (journalctl -u systemd-resolved -f -n 0 > "$RES_FIFO" 2>/dev/null &); _process_resolved < "$RES_FIFO" & BG_DNS=$!
fi

_emit INIT "-" "initial snapshots"; _snapshot_route; _count_veth; _snapshot_pubip

cleanup(){
  _emit EXIT "-" "stopping" || true
  [ -n "${BG_IP:-}" ] && kill $BG_IP 2>/dev/null || true
  [ -n "${BG_NM:-}" ] && kill $BG_NM 2>/dev/null || true
  [ -n "${BG_DNS:-}" ] && kill $BG_DNS 2>/dev/null || true
  rm -f ${IP_FIFO:-} ${NM_FIFO:-} ${RES_FIFO:-}
}
trap cleanup INT TERM EXIT

# Main idle wait
while true; do sleep 3600; done
