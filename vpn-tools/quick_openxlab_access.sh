#!/bin/bash

# 🎯 Quick OpenXLab/MinerU Access
# 
# DESCRIPTION:
#   Quick launcher for OpenXLab and MinerU with optimal settings
#   Automatically handles proxy bypass and browser configuration
#
# USAGE:
#   ./quick_openxlab_access.sh           # print URLs only (safe default)
#   ./quick_openxlab_access.sh --open    # actually launch browser

set -euo pipefail

OPEN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --open) OPEN=1; shift;;
        -h|--help)
            grep -E '^#' "$0" | head -n 40
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2;;
    esac
done

echo "🎯 OpenXLab/MinerU Quick Access"
echo "==============================="

# Export variables to bypass proxy
export no_proxy="*.openxlab.org.cn,openxlab.org.cn,mineru.net"
export NO_PROXY="*.openxlab.org.cn,openxlab.org.cn,mineru.net"

echo "🔧 Proxy bypass configured for OpenXLab domains"
echo ""

# URLs to try
declare -A urls=(
    ["MinerU Login"]="https://sso.openxlab.org.cn/mineru-login?redirect=https://mineru.net/OpenSourceTools/Extractor/?clientId=4m2wonemkv2rm37nwen8&source=minerU"
    ["OpenXLab Main"]="https://openxlab.org.cn/"
    ["MinerU Main"]="https://mineru.net/"
    ["OpenXLab GitHub"]="https://github.com/OpenXLab"
    ["MinerU GitHub"]="https://github.com/opendatalab/MinerU"
)

echo "🌐 Available URLs:"
echo "=================="

count=1
for name in "${!urls[@]}"; do
    echo "$count. $name"
    echo "   ${urls[$name]}"
    echo ""
    ((++count))
done

if [[ $OPEN -ne 1 ]]; then
    echo "ℹ️ Preview mode: not launching a browser. Re-run with --open to launch automatically."
    echo ""
fi

# Try to open the specific MinerU URL
minerU_url="https://sso.openxlab.org.cn/mineru-login?redirect=https://mineru.net/OpenSourceTools/Extractor/?clientId=4m2wonemkv2rm37nwen8&source=minerU"

if [[ $OPEN -eq 1 ]]; then
  # Try different browsers
  if command -v firefox >/dev/null 2>&1; then
      echo "🦊 Opening in Firefox..."
      firefox --new-window "$minerU_url" >/dev/null 2>&1 &
      echo "✅ Firefox launched"
  elif command -v google-chrome >/dev/null 2>&1; then
      echo "🌐 Opening in Chrome..."
      google-chrome --new-window "$minerU_url" >/dev/null 2>&1 &
      echo "✅ Chrome launched"
  elif command -v chromium-browser >/dev/null 2>&1; then
      echo "🌐 Opening in Chromium..."
      chromium-browser --new-window "$minerU_url" >/dev/null 2>&1 &
      echo "✅ Chromium launched"
  else
      echo "❌ No supported browser found"
      echo ""
      echo "📋 Please manually copy and paste this URL:"
      echo "$minerU_url"
  fi
else
  echo "📋 MinerU login URL:"
  echo "$minerU_url"
fi

echo ""
echo "💡 If the page doesn't load:"
echo "1. Try the OpenXLab main site: https://openxlab.org.cn/"
echo "2. Use the GitHub alternative: https://github.com/opendatalab/MinerU"
echo "3. Clear browser cache and try again"
echo "4. Try in private/incognito mode"
echo ""
echo "🔧 Troubleshooting:"
echo "• If still getting ERR_CONNECTION_CLOSED, the issue is likely ISP blocking"
echo "• Try using a different DNS (8.8.8.8, 1.1.1.1)"
echo "• Consider using a different VPN/proxy service"
echo "• The GitHub version works as an alternative: https://github.com/opendatalab/MinerU"
