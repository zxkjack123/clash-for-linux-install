#!/usr/bin/env bash

# Fix apt update timeouts to ProtonVPN repo by forcing IPv4 and enabling APT proxy
#
# Usage:
#   ./fix_apt_protonvpn_repo.sh           # Diagnose and print next steps (no changes)
#   ./fix_apt_protonvpn_repo.sh --apply   # Apply APT config via sudo (creates 95clash-proxy)
#   ./fix_apt_protonvpn_repo.sh --dry-run # Show the config that would be written
#
# What it does:
#   1) Detects your Clash/Mihomo mixed-port (defaults to 7890)
#   2) Tests connectivity to https://repo.protonvpn.com over IPv4/IPv6 (direct & via proxy)
#   3) If IPv6 is failing but IPv4 works, recommends ForceIPv4 for APT
#   4) Optionally writes /etc/apt/apt.conf.d/95clash-proxy with:
#        Acquire::ForceIPv4 "true";
#        Acquire::http::Proxy  "http://127.0.0.1:<port>/";
#        Acquire::https::Proxy "http://127.0.0.1:<port>/";

set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

conf_path="/etc/apt/apt.conf.d/95clash-proxy"
runtime_yaml="$HOME/.local/share/clash/runtime.yaml"

# Detect proxy port from runtime.yaml (fallback to 7890)
detect_port() {
  local port=""
  if [[ -f "$runtime_yaml" ]]; then
    port=$(awk -F': ' '/^mixed-port:/ {print $2; exit}' "$runtime_yaml" 2>/dev/null || true)
  fi
  [[ -n "${port:-}" ]] && echo "$port" || echo "7890"
}

PORT=${PROXY_PORT:-$(detect_port)}
PROXY_URL="http://127.0.0.1:${PORT}"

echo -e "${CYAN}🔧 APT ProtonVPN repo diagnostic${NC}"
echo "-----------------------------------"
echo "APT proxy conf: ${conf_path}"
echo "Detected proxy: ${PROXY_URL}"
echo "Runtime file:   ${runtime_yaml}"
echo

# Show protonvpn source if present
if [[ -f /etc/apt/sources.list.d/protonvpn-stable.sources ]]; then
  echo "ProtonVPN source file: /etc/apt/sources.list.d/protonvpn-stable.sources"
  sed -n '1,80p' /etc/apt/sources.list.d/protonvpn-stable.sources | sed 's/^/  /'
  echo
fi

echo "1) DNS results (getent ahosts):"
getent ahosts repo.protonvpn.com | sed 's/^/  /' || true
echo

test_head() {
  local label="$1"; shift
  local cmd=(curl -I -sS -m 8 "$@" https://repo.protonvpn.com/debian)
  local out status=0
  if ! out=$("${cmd[@]}" 2>&1); then
    status=$?
  fi
  # Success if HTTP code is one of 200/204/301/302/403 (reachable)
  local code
  code=$(printf "%s" "$out" | awk '/^HTTP\//{c=$2} END{print c+0}')
  if [[ "$code" =~ ^(200|204|301|302|403)$ ]]; then
    echo -e "  ${GREEN}OK${NC} ${label} (HTTP $code)"
    return 0
  fi
  echo -e "  ${RED}FAIL${NC} ${label} (${code:-curl-$status})"
  return 1
}

echo "2) Reachability (HEAD /debian):"
v4_direct_ok=false
v6_direct_ok=false
v4_proxy_ok=false
v6_proxy_ok=false

if test_head "Direct IPv4" -4; then v4_direct_ok=true; fi
if test_head "Direct IPv6" -6; then v6_direct_ok=true; fi
if test_head "Via proxy IPv4 (-x ${PROXY_URL})" -4 -x "$PROXY_URL"; then v4_proxy_ok=true; fi
if test_head "Via proxy IPv6 (-x ${PROXY_URL})" -6 -x "$PROXY_URL"; then v6_proxy_ok=true; fi
echo

need_force_ipv4=false
if [[ "$v6_direct_ok" = false && "$v4_direct_ok" = true ]]; then
  need_force_ipv4=true
fi

echo "3) Analysis:"
if [[ "$need_force_ipv4" = true ]]; then
  echo -e "  ${YELLOW}IPv6 to repo.protonvpn.com appears unreachable, IPv4 works.${NC}"
  echo -e "  Recommending APT setting: Acquire::ForceIPv4 \"true\";"
else
  if [[ "$v6_direct_ok" = true ]]; then
    echo -e "  ${GREEN}IPv4 and IPv6 both reachable to repo.protonvpn.com.${NC}"
  else
    echo -e "  ${GREEN}IPv4 reachable; IPv6 fails (will rely on IPv4 via ForceIPv4).${NC}"
  fi
fi

echo
echo "4) Proposed APT config (${conf_path}):"
cat <<EOF | sed 's/^/  /'
Acquire::ForceIPv4 "true";
Acquire::http::Proxy  "${PROXY_URL}/";
Acquire::https::Proxy "${PROXY_URL}/";
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::Retries "1";
EOF
echo

apply=${1:-}
case "${apply:-}" in
  --apply)
    echo "Applying APT config (requires sudo)..."
    tmpfile=$(mktemp)
    cat >"$tmpfile" <<CONF
Acquire::ForceIPv4 "true";
Acquire::http::Proxy  "${PROXY_URL}/";
Acquire::https::Proxy "${PROXY_URL}/";
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::Retries "1";
CONF
    if sudo -n true 2>/dev/null; then
      sudo mkdir -p /etc/apt/apt.conf.d
      sudo cp "$tmpfile" "$conf_path"
    else
      echo -e "${YELLOW}sudo password required${NC}"
      sudo mkdir -p /etc/apt/apt.conf.d
      sudo cp "$tmpfile" "$conf_path"
    fi
    rm -f "$tmpfile"
    echo -e "${GREEN}Config written:${NC} $conf_path"
    echo "You can now run:"
    echo "  sudo apt -o Acquire::ForceIPv4=true update"
    ;;
  --dry-run)
    echo "Dry-run: no changes written. Use --apply to write ${conf_path}."
    ;;
  *)
    echo "No changes made. To apply the above config, run:"
    echo "  ./fix_apt_protonvpn_repo.sh --apply"
    echo
    echo "Or test a one-off update with IPv4 forced (without writing config):"
    echo "  sudo apt -o Acquire::ForceIPv4=true update"
    ;;
esac

exit 0
