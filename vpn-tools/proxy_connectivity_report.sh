#!/bin/bash

# DESCRIPTION:
#   Generate a markdown report summarizing proxy connectivity across AI, streaming,
#   and general endpoints. Includes timestamps, raw metrics and simple grading.
#
# USAGE:
#   ./proxy_connectivity_report.sh > AI_CONNECTIVITY_REPORT.md
#   PROXY=http://127.0.0.1:7890 ./proxy_connectivity_report.sh
#
set -euo pipefail
PROXY=${PROXY:-http://127.0.0.1:7890}
TIMEOUT=${TIMEOUT:-6}
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$SCRIPT_DIR/lib/net_helpers.sh" 2>/dev/null || true
nh_init_symbols
curl_t() { nh_curl_t "$1" "$PROXY" "$TIMEOUT"; }

declare -A groups
groups[AI_openai]=https://api.openai.com/v1/models
groups[AI_chatgpt]=https://chat.openai.com/
groups[AI_claude]=https://claude.ai/
groups[AI_braintrust]=https://www.braintrust.dev/
groups[STREAM_yt_home]=https://www.youtube.com/
groups[STREAM_yt_pixel]=https://i.ytimg.com/generate_204
groups[STREAM_basejs]=https://www.youtube.com/s/player/230b3f4e/player_ias.vflset/en_US/base.js
groups[GEN_google]=https://www.google.com/
groups[GEN_cloudflare]=https://www.cloudflare.com/
groups[GEN_bing]=https://www.bing.com/
groups[DEV_github_web]=https://github.com/
groups[DEV_github_api]=https://api.github.com/
groups[DEV_copilot]=https://api.githubcopilot.com/
groups[DEV_copilot_proxy]=https://copilot-proxy.githubusercontent.com/
groups[DEV_docker_hub]=https://hub.docker.com/
groups[DEV_docker_registry]=https://registry-1.docker.io/v2/
groups[DEV_pypi]=https://pypi.org/simple/
groups[DEV_pypi_files]=https://files.pythonhosted.org/
groups[GEN_protonvpn]=https://repo.protonvpn.com/

echo "# Proxy Connectivity Report"
echo "Generated: $(date '+%F %T')"
echo "Proxy: $PROXY"
echo
echo "| Category | Target | Code | Time(s) | Grade |"
echo "|----------|--------|------|---------|-------|"

grade() { # time code
    local t="$1" c="$2"
    nh_grade_time "$c" "$t"
}

for key in "${!groups[@]}"; do
    url=${groups[$key]}; catg=${key%%_*}; target=${key#*_}
    out=$(curl_t "$url"); code=${out%%,*}; t=${out##*,}; g=$(grade "$t" "$code")
    printf '| %s | %s | %s | %s | %s |\n' "$catg" "$target" "$code" "$t" "$g"
done | sort

echo
echo "## Legend"
echo "A: <=1.5s  B: <=3s  C: <=5s  D: >5s  F: Fail/Timeout"
