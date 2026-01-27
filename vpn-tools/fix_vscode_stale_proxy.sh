#!/usr/bin/env bash
# Detect and remediate stale VS Code proxy environment pointing to 127.0.0.1:6209.
# This does NOT kill VS Code by default. Use the provided options to relaunch VS Code
# with a sanitized proxy environment (pointing to current Clash port) or to exit safely.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Load common env for paths (BIN_YQ, CLASH_CONFIG_RUNTIME, etc.)
# common.sh may reference positional parameters; shield from -u during sourcing.
# shellcheck source=/dev/null
set +u
. "$ROOT_DIR/script/common.sh"
set -u

usage() {
  cat <<EOF
fix_vscode_stale_proxy.sh [--check] [--launch-here] [--launch <path>] [--print-port]

Options:
  --check           Only detect VS Code processes carrying 127.0.0.1:6209 in env.
  --launch-here     Start a new VS Code window for current directory with sanitized proxy env.
  --launch <path>   Start a new VS Code window for the specified path with sanitized proxy env.
  --print-port      Print the current Clash mixed-port and exit.

Notes:
  - Stale 6209 proxies come from an older VS Code process environment. The reliable fix is to
    fully exit all VS Code windows (File > Exit) and relaunch. This tool helps you verify and
    launch a clean window immediately.
EOF
}

get_port() {
  local port
  if command -v yq >/dev/null 2>&1; then
    # Prefer BIN_YQ from common.sh if available, else fallback to yq
    local _yq="${BIN_YQ:-yq}"
    local _rt="${CLASH_CONFIG_RUNTIME:-$ROOT_DIR/resources/config.yaml}"
    port=$("$_yq" '.mixed-port // 7890' "$_rt" 2>/dev/null || echo 7890)
  else
    port=7890
  fi
  [[ "$port" =~ ^[0-9]+$ ]] || port=7890
  echo "$port"
}

detect_6209() {
  # Safely detect VS Code processes whose environment still references 127.0.0.1:6209
  # NOTE: Avoid `ps e` which can dump full environments (may contain secrets).
  local pids found any_code
  any_code=0
  found=0

  pids=$(pgrep -x code 2>/dev/null || true)
  if [ -z "$pids" ]; then
    echo "No VS Code processes found."
    return 0
  fi
  any_code=1

  for pid in $pids; do
    [ -r "/proc/$pid/environ" ] || continue
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -q '127\.0\.0\.1:6209'; then
      if [ "$found" -eq 0 ]; then
        echo "Found VS Code processes carrying stale proxies (127.0.0.1:6209):"
      fi
      found=1
      echo "  PID $pid:"
      tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
        | grep -iE '^(http|https|all|no)_proxy=' \
        | sed 's/^/    /'
    fi
  done

  if [ "$any_code" -eq 1 ] && [ "$found" -eq 0 ]; then
    echo "No VS Code process found with 127.0.0.1:6209 in proxy env."
  fi
}

launch_clean() {
  local target="$1"; shift || true
  local port auth http_proxy_addr socks_proxy_addr no_proxy_addr
  port=$(get_port)
  if command -v yq >/dev/null 2>&1; then
    local _yq="${BIN_YQ:-yq}"
    local _rt="${CLASH_CONFIG_RUNTIME:-$ROOT_DIR/resources/config.yaml}"
    auth=$("$_yq" '.authentication[0] // ""' "$_rt" 2>/dev/null || echo "")
  else
    auth=""
  fi
  [ -n "$auth" ] && auth="$auth@"
  http_proxy_addr="http://${auth}127.0.0.1:${port}"
  socks_proxy_addr="socks5h://${auth}127.0.0.1:${port}"
  # Bypass local proxy for localhost/LAN/Tailscale and Copilot endpoints (to avoid flaky proxy paths)
  no_proxy_addr="localhost,127.0.0.1,::1,ts.net,.ts.net,tailscale.io,.tailscale.io,tailscale.com,.tailscale.com,controlplane.tailscale.com,100.100.100.100,100.64.0.0/10,api.githubcopilot.com,api.individual.githubcopilot.com,copilot-proxy.githubusercontent.com,.githubcopilot.com,api.github.com,github.com"

  echo "Launching VS Code with sanitized proxy env (http=${http_proxy_addr}) -> $target"
  # Clear any inherited *_proxy and set correct ones for the new window only
  env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    http_proxy="$http_proxy_addr" \
    https_proxy="$http_proxy_addr" \
    all_proxy="$socks_proxy_addr" \
    HTTP_PROXY="$http_proxy_addr" \
    HTTPS_PROXY="$http_proxy_addr" \
    ALL_PROXY="$socks_proxy_addr" \
    no_proxy="$no_proxy_addr" \
    NO_PROXY="$no_proxy_addr" \
    code -n "$target" >/dev/null 2>&1 &
}

print_listener_status() {
  echo "Checking listeners for 6209 and active Clash port..."
  local port
  port=$(get_port)
  (ss -ltnp 2>/dev/null | grep -E ":6209\\b" && true) || echo "No listener on 6209"
  (ss -ltnp 2>/dev/null | grep -E ":${port}\\b" && true) || echo "No listener on ${port} (unexpected)"
}

main() {
  local mode="--check" target=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) mode="--check"; shift ;;
      --launch-here) mode="--launch"; target="$(pwd)"; shift ;;
      --launch) mode="--launch"; target="$2"; shift 2 ;;
      --print-port) get_port; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
  done

  print_listener_status
  detect_6209

  if [ "$mode" = "--launch" ]; then
    if [ -z "$target" ]; then
      echo "No target path provided" >&2; exit 1
    fi
    launch_clean "$target"
    echo "Started a clean VS Code window. Recommended: File > Exit in old windows to drop stale env."
  else
    echo
    echo "Next steps:"
    echo "  1) Fully exit all VS Code windows (File > Exit)."
    echo "  2) Optionally run: $0 --launch-here to open a fresh window with correct proxy env."
  fi
}

main "$@"
