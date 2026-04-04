#!/usr/bin/env bash
set -euo pipefail
# ensure_system_proxy_best_practices.sh
# Purpose: Enforce GNOME proxy best-practice settings for ignore-hosts (LAN + Tailscale), idempotently.

have() { command -v "$1" >/dev/null 2>&1; }

# Build GVariant array string like: ['a','b']
build_list() {
  local ts_suffix="${1:-}"
  local arr=(
    "localhost" "127.0.0.0/8" "::1" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16"
    "ts.net" ".ts.net" "tailscale.io" ".tailscale.io" "100.100.100.100" "100.64.0.0/10"
  )
  if [ -n "$ts_suffix" ]; then
    arr+=("$ts_suffix" ".${ts_suffix}")
  fi
  local out="[" sep=""
  for e in "${arr[@]}"; do out+="${sep}'${e}'"; sep=", "; done
  out+="]"
  printf '%s' "$out"
}

main() {
  have gsettings || { echo "gsettings not available; skipping"; exit 0; }

  # Optional runtime-aware mode (keeps GNOME ports in sync with actual Clash config)
  local runtime="${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}"
  local yq_bin="${BIN_YQ:-$HOME/.local/share/clash/bin/yq}"
  read_ports_from_runtime() {
    # Echo: "<http_port> <socks_port>"
    # Priority:
    #   - mixed-port: http=socks=mixed
    #   - port + socks-port
    local mixed http socks
    if [[ -x "$yq_bin" && -f "$runtime" ]]; then
      mixed=$("$yq_bin" -r '."mixed-port" // ""' "$runtime" 2>/dev/null || true)
      mixed=${mixed//$'\n'/}; mixed=${mixed//\"/}; mixed=${mixed//\'/}
      if [[ "$mixed" =~ ^[0-9]+$ ]]; then
        echo "$mixed $mixed"
        return 0
      fi
      http=$("$yq_bin" -r '.port // ""' "$runtime" 2>/dev/null || true)
      http=${http//$'\n'/}; http=${http//\"/}; http=${http//\'/}
      socks=$("$yq_bin" -r '."socks-port" // ""' "$runtime" 2>/dev/null || true)
      socks=${socks//$'\n'/}; socks=${socks//\"/}; socks=${socks//\'/}
      [[ "$http" =~ ^[0-9]+$ ]] || http=7890
      [[ "$socks" =~ ^[0-9]+$ ]] || socks="$http"
      echo "$http $socks"
      return 0
    fi
    # Fallback
    echo "7890 7891"
  }
  local ts_suffix=""
  if have tailscale; then
    ts_suffix=$(tailscale status 2>/dev/null | grep -o 'tail[0-9a-f]*\.ts\.net' | head -n1 || true)
  fi
  local desired current
  desired=$(build_list "$ts_suffix")
  current=$(gsettings get org.gnome.system.proxy ignore-hosts 2>/dev/null || echo "[]")
  if [ "${current//[[:space:]]/}" != "${desired//[[:space:]]/}" ]; then
    echo "Applying ignore-hosts: $desired"
    gsettings set org.gnome.system.proxy ignore-hosts "$desired" 2>/dev/null || true
  else
    echo "ignore-hosts already optimal"
  fi
  # Ensure manual mode and port consistency if requested
  if [ "${1:-}" = "--set-manual" ]; then
    gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null || true
    local http_port="${2:-7890}"
    local socks_port="${3:-$http_port}"
    gsettings set org.gnome.system.proxy.http host '127.0.0.1' 2>/dev/null || true
    gsettings set org.gnome.system.proxy.http port "$http_port" 2>/dev/null || true
    gsettings set org.gnome.system.proxy.https host '127.0.0.1' 2>/dev/null || true
    gsettings set org.gnome.system.proxy.https port "$http_port" 2>/dev/null || true
    gsettings set org.gnome.system.proxy.socks host '127.0.0.1' 2>/dev/null || true
    gsettings set org.gnome.system.proxy.socks port "$socks_port" 2>/dev/null || true
  elif [ "${1:-}" = "--set-manual-from-runtime" ]; then
    # Usage: --set-manual-from-runtime [runtime.yaml]
    [ -n "${2:-}" ] && runtime="$2"
    read -r http_port socks_port < <(read_ports_from_runtime)
    gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null || true
    gsettings set org.gnome.system.proxy.http host '127.0.0.1' 2>/dev/null || true
    gsettings set org.gnome.system.proxy.http port "$http_port" 2>/dev/null || true
    gsettings set org.gnome.system.proxy.https host '127.0.0.1' 2>/dev/null || true
    gsettings set org.gnome.system.proxy.https port "$http_port" 2>/dev/null || true
    gsettings set org.gnome.system.proxy.socks host '127.0.0.1' 2>/dev/null || true
    gsettings set org.gnome.system.proxy.socks port "$socks_port" 2>/dev/null || true
  fi
}

main "$@"
