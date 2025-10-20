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
    local port="${2:-7890}"
    gsettings set org.gnome.system.proxy.http host '127.0.0.1' 2>/dev/null || true
    gsettings set org.gnome.system.proxy.http port "$port" 2>/dev/null || true
    gsettings set org.gnome.system.proxy.https host '127.0.0.1' 2>/dev/null || true
    gsettings set org.gnome.system.proxy.https port "$port" 2>/dev/null || true
    gsettings set org.gnome.system.proxy.socks host '127.0.0.1' 2>/dev/null || true
    gsettings set org.gnome.system.proxy.socks port "$port" 2>/dev/null || true
  fi
}

main "$@"
