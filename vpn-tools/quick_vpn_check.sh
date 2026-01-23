#!/bin/bash

# DESCRIPTION:
#   Ultra-fast (<=30s) diagnostic to confirm Clash/Mihomo proxy + AI reachability.
#   Tests controller, local ports, outbound via proxy, a few AI/streaming endpoints,
#   and reports a concise PASS/FAIL summary with simple scoring.
#
# USAGE:
#   ./quick_vpn_check.sh
#   ./quick_vpn_check.sh json   # machine-readable JSON output
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load env (optional) and bootstrap controller/secret (env override -> legacy compat -> runtime.yaml -> default)
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true

API="${CLASH_API:-http://127.0.0.1:9090}"
SECRET="${CLASH_SECRET:-}"
PROXY_HOST=127.0.0.1
HTTP_PORT=7890
SOCKS_PORT=7891
MODE=${1:-text}
TIMEOUT=6

have() { command -v "$1" >/dev/null 2>&1; }
json_escape() { sed 's/\\/\\\\/g; s/"/\\"/g'; }
timed_curl() { curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+2))" "$@" 2>/dev/null || echo "000,$TIMEOUT"; }
curl_body() { curl -sS --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+3))" "$@" 2>/dev/null || true; }

declare -A RESULTS
# Scoring baseline components: controller + ports(2) + proxy_http + youtube + github_web + github_api + copilot_edge = 8
# We'll dynamically increase max_score as we add more tests below (Docker Hub/Registry, PyPI, ProtonVPN, Copilot Proxy).
score=0; max_score=8

controller_status_details=""

test_step() {
	local key="$1" desc="$2"; shift 2
	local out http t status
	out=$(timed_curl "$@")
	http=${out%%,*}; t=${out##*,}
	status=FAIL
	# Accept 2xx/3xx codes explicitly (3 digits)
	if [[ $http =~ ^[23][0-9][0-9]$ ]]; then status=OK; ((++score)); fi
	RESULTS[$key]="$status($http,$t)"
	[[ $MODE == text ]] && printf "%-28s %s\n" "$desc" "$status ($http $t s)"
}

echo "=== Quick VPN Check ($(date '+%F %T')) ===" >&2
[[ -n $SECRET ]] && echo "(Detected controller secret)" >&2

# Controller (capture nuanced auth states)
ctrl_code=""; ctrl_code_nosecret=""; ctrl_latency=""; ctrl_latency_nosecret=""
if [[ -n $SECRET ]]; then
	ctrl_raw=$(timed_curl --noproxy '*' -H "Authorization: Bearer $SECRET" "$API/version")
	ctrl_code=${ctrl_raw%%,*}; ctrl_latency=${ctrl_raw##*,}
fi
if [[ -z $ctrl_code || $ctrl_code == 401 || $ctrl_code == 403 || -z $SECRET ]]; then
	# Try without secret
	ctrl_raw2=$(timed_curl --noproxy '*' "$API/version")
	ctrl_code_nosecret=${ctrl_raw2%%,*}; ctrl_latency_nosecret=${ctrl_raw2##*,}
fi

controller_label="Controller"
if [[ $ctrl_code == 200 ]]; then
	RESULTS[controller]="OK(200,${ctrl_latency}s)"; ((++score))
elif [[ $ctrl_code_nosecret == 200 ]]; then
	# Auth not required
	RESULTS[controller]="OK(200,${ctrl_latency_nosecret}s)"; ((++score))
elif [[ $ctrl_code == 401 || $ctrl_code_nosecret == 401 || $ctrl_code == 403 || $ctrl_code_nosecret == 403 ]]; then
	# Auth required but unreachable without proper secret. Treat as reachable (no network issue) so score counts.
	RESULTS[controller]="AUTH(${ctrl_code:-${ctrl_code_nosecret}})"; ((++score))
	controller_label="Controller (auth)"
else
	# Network / other failure
	RESULTS[controller]="FAIL(${ctrl_code:-${ctrl_code_nosecret:-noresp}})"
fi
[[ $MODE == text ]] && printf "%-28s %s\n" "$controller_label" "${RESULTS[controller]}"

# Port reachability (TCP SYN)
for p in $HTTP_PORT $SOCKS_PORT; do
	# Skip SOCKS test if no dedicated socks-port configured (only mixed-port 7890 present)
	if [[ $p -eq $SOCKS_PORT ]]; then
		if ! ss -ltn | grep -q ":$SOCKS_PORT"; then
			RESULTS[port_$p]=SKIP
			# Adjust denominator since SOCKS not active
			((max_score--))
			[[ $MODE == text ]] && printf "%-28s %s\n" "Port $p" "SKIP (not configured)"
			continue
		fi
	fi
	if timeout 1 bash -c "</dev/tcp/$PROXY_HOST/$p" 2>/dev/null; then
		RESULTS[port_$p]=OK; ((++score))
	else RESULTS[port_$p]=FAIL; fi
	[[ $MODE == text ]] && printf "%-28s %s\n" "Port $p" "${RESULTS[port_$p]}"
done

# Proxy basic reachability (with fallback matrix to avoid transient 503 from httpbin)
proxy_ok=0
for url in \
	https://cloudflare.com/cdn-cgi/trace \
	https://httpbin.org/ip \
	https://ipapi.co/ip; do
	out=$(timed_curl --proxy http://$PROXY_HOST:$HTTP_PORT "$url"); code=${out%%,*}; t=${out##*,}
	if [[ $code =~ ^[23][0-9][0-9]$ ]]; then proxy_ok=1; proxy_code=$code; proxy_t=$t; break; fi
done
if (( proxy_ok )); then RESULTS[proxy_http]="OK($proxy_code,$proxy_t)"; ((++score)); else RESULTS[proxy_http]="FAIL(${code:-noresp},${t:-$TIMEOUT})"; fi
[[ $MODE == text ]] && printf "%-28s %s\n" "Proxy HTTP" "${RESULTS[proxy_http]}"

# AI endpoints (lightweight HEAD via -I still counts a GET sometimes; keep GET)
# (Removed OpenAI / Claude by request) Add GitHub & Copilot tests

# Streaming quick (YouTube base HTML)
test_step youtube "YouTube" --proxy http://$PROXY_HOST:$HTTP_PORT https://www.youtube.com/
# Upwork access check (common geo-verify issue, ensure proxied works)
((max_score++))
test_step upwork "Upwork" --proxy http://$PROXY_HOST:$HTTP_PORT https://www.upwork.com/
test_step github_web "GitHub Web" --proxy http://$PROXY_HOST:$HTTP_PORT https://github.com/
# GitHub API: be resilient against sporadic network hiccups and rate-limit edges
# Try root, then /zen, then /rate_limit; include a simple UA to avoid 403s in rare environments
{
	out=$(timed_curl --proxy http://$PROXY_HOST:$HTTP_PORT -H "User-Agent: curl/8.4" https://api.github.com/); code=${out%%,*}; t=${out##*,}
	if [[ $code =~ ^[23][0-9][0-9]$ ]]; then
		RESULTS[github_api]="OK($code,$t)"; ((++score))
	else
		out=$(timed_curl --proxy http://$PROXY_HOST:$HTTP_PORT -H "User-Agent: curl/8.4" https://api.github.com/zen); code=${out%%,*}; t=${out##*,}
		if [[ $code =~ ^[23][0-9][0-9]$ ]]; then
			RESULTS[github_api]="OK($code,$t)"; ((++score))
		else
			out=$(timed_curl --proxy http://$PROXY_HOST:$HTTP_PORT -H "User-Agent: curl/8.4" https://api.github.com/rate_limit); code=${out%%,*}; t=${out##*,}
			if [[ $code =~ ^[23][0-9][0-9]$ ]]; then
				RESULTS[github_api]="OK($code,$t)"; ((++score))
			else
				RESULTS[github_api]="FAIL(${code:-noresp},${t:-$TIMEOUT})"
			fi
		fi
	fi
}
[[ $MODE == text ]] && printf "%-28s %s\n" "GitHub API" "${RESULTS[github_api]}"
# Copilot root may return 401/403; accept 2xx/3xx/401/403/404 as reachable
out=$(timed_curl --proxy http://$PROXY_HOST:$HTTP_PORT https://api.githubcopilot.com/)
code=${out%%,*}; t=${out##*,}; status=FAIL
if [[ $code =~ ^([23][0-9][0-9]|401|403|404)$ ]]; then status=OK; ((++score)); fi
RESULTS[copilot_edge]="$status($code,$t)"
[[ $MODE == text ]] && printf "%-28s %s\n" "Copilot Edge" "${RESULTS[copilot_edge]}"

# Additional developer/infra endpoints (requested): Docker Hub, Docker Registry, PyPI, ProtonVPN, Copilot Proxy

# PyPI main index
((max_score++))
test_step pypi "PyPI" --proxy http://$PROXY_HOST:$HTTP_PORT https://pypi.org/simple/

# PyPI file CDN
((max_score++))
test_step pypi_files "PyPI Files" --proxy http://$PROXY_HOST:$HTTP_PORT https://files.pythonhosted.org/

# Docker Hub web
((max_score++))
test_step docker_hub "Docker Hub" --proxy http://$PROXY_HOST:$HTTP_PORT https://hub.docker.com/

# Docker Registry v2 endpoint (401/403 are acceptable as reachability)
((max_score++))
out=$(timed_curl --proxy http://$PROXY_HOST:$HTTP_PORT https://registry-1.docker.io/v2/); code=${out%%,*}; t=${out##*,}
status=FAIL
if [[ $code =~ ^([23][0-9][0-9]|401|403)$ ]]; then status=OK; ((++score)); fi
RESULTS[docker_registry]="$status($code,$t)"
[[ $MODE == text ]] && printf "%-28s %s\n" "Docker Registry" "${RESULTS[docker_registry]}"

# ProtonVPN repository (package mirror) – accept 2xx/3xx/403 as reachable
((max_score++))
out=$(timed_curl --proxy http://$PROXY_HOST:$HTTP_PORT https://repo.protonvpn.com/); code=${out%%,*}; t=${out##*,}
status=FAIL
if [[ $code =~ ^([23][0-9][0-9]|403)$ ]]; then status=OK; ((++score)); fi
RESULTS[protonvpn_repo]="$status($code,$t)"
[[ $MODE == text ]] && printf "%-28s %s\n" "ProtonVPN Repo" "${RESULTS[protonvpn_repo]}"

# Copilot Proxy endpoint (401/403/404 acceptable)
((max_score++))
out=$(timed_curl --proxy http://$PROXY_HOST:$HTTP_PORT https://copilot-proxy.githubusercontent.com/); code=${out%%,*}; t=${out##*,}
status=FAIL
if [[ $code =~ ^([23][0-9][0-9]|401|403|404)$ ]]; then status=OK; ((++score)); fi
RESULTS[copilot_proxy]="$status($code,$t)"
[[ $MODE == text ]] && printf "%-28s %s\n" "Copilot Proxy" "${RESULTS[copilot_proxy]}"

# Geo check (which exit IP)
geo_json=$(curl_body --proxy http://$PROXY_HOST:$HTTP_PORT https://ipapi.co/json)
country=$(echo "$geo_json" | sed -n 's/.*"country_name":"\([^"]*\)".*/\1/p')
ip=$(echo "$geo_json" | sed -n 's/.*"ip":"\([^"]*\)".*/\1/p')
if [[ -z $ip ]]; then
	# Fallback to ipinfo.io
	alt=$(curl_body --proxy http://$PROXY_HOST:$HTTP_PORT https://ipinfo.io/json)
	ip=$(echo "$alt" | sed -n 's/.*"ip":"\([^"]*\)".*/\1/p')
	cc=$(echo "$alt" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
	[[ -z $country && -n $cc ]] && country=$cc
fi
if [[ -z $ip ]]; then
	# Final fallback to Cloudflare trace
	cf=$(curl_body --proxy http://$PROXY_HOST:$HTTP_PORT https://cloudflare.com/cdn-cgi/trace)
	ip=$(echo "$cf" | awk -F= '/^ip=/{print $2; exit}')
	cc=$(echo "$cf" | awk -F= '/^loc=/{print $2; exit}')
	[[ -z $country && -n $cc ]] && country=$cc
fi
[[ -n $ip ]] && RESULTS[geo]="$ip/${country:-unknown}" || RESULTS[geo]=unknown
[[ $MODE == text ]] && printf "%-28s %s\n" "Exit IP Country" "${RESULTS[geo]}"

SUMMARY=$((score*100/max_score))

if [[ $MODE == text ]]; then
	echo "---------------------------------------"
	echo "Score: $score/$max_score  (${SUMMARY}%)"
	if (( SUMMARY >= 75 )); then echo "Status: ✅ GOOD"; elif (( SUMMARY >= 50 )); then echo "Status: ⚠️ PARTIAL"; else echo "Status: ❌ PROBLEM"; fi
else
	# JSON output
	{
		echo '{'
		echo '  "timestamp": '"$(date +%s)",
		for k in controller port_$HTTP_PORT port_$SOCKS_PORT proxy_http youtube upwork github_web github_api copilot_edge pypi pypi_files docker_hub docker_registry protonvpn_repo copilot_proxy geo; do
			v=${RESULTS[$k]:-NA}; printf '  "%s": "%s",\n' "$k" "$v" | json_escape
		done
		echo '  "score": '"$score",'
		echo '  "max_score": '"$max_score",'
		echo '  "percent": '"$SUMMARY"
		echo '}'
	}
fi

