#!/bin/bash
# Quick Dev/Research Connectivity Test
# Checks popular dev registries, code hosts, and research portals for reachability via proxy.
# Usage: ./quick_dev_research_test.sh [json]
set -euo pipefail
MODE=${1:-text}
TIMEOUT=${TIMEOUT:-6}
PROXY=${PROXY:-http://127.0.0.1:7890}

have(){ command -v "$1" >/dev/null 2>&1; }

test_curl(){ curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+2))" --proxy "$PROXY" "$1" 2>/dev/null || echo "000,$TIMEOUT"; }

# target map (key=url)
declare -A targets=(
  [github]="https://github.com/"
  [gitlab]="https://gitlab.com/"
  [ghcr]="https://ghcr.io/v2/"
  [docker]="https://registry-1.docker.io/v2/"
  [npm]="https://registry.npmjs.org/"
  [pypi]="https://pypi.org/"
  [pypi_files]="https://files.pythonhosted.org/"
  [crates]="https://crates.io/"
  [rustup]="https://static.rust-lang.org/rustup/release-stable.toml"
  [go_proxy]="https://proxy.golang.org/"
  [k8s]="https://registry.k8s.io/v2/"
  [aliyun]="https://developer.aliyun.com/"
  [tuna]="https://mirrors.tuna.tsinghua.edu.cn/"
  [ustc]="https://mirrors.ustc.edu.cn/"
  [gitee]="https://gitee.com/"
  [arxiv]="https://arxiv.org/"
  [springer]="https://www.springer.com/"
  [nature]="https://www.nature.com/"
  [ieee]="https://ieeexplore.ieee.org/"
  [acm]="https://dl.acm.org/"
)

status_ok=0; total=0
# output order list
order=(github gitlab ghcr docker npm pypi pypi_files crates rustup go_proxy k8s aliyun tuna ustc gitee arxiv springer nature ieee acm)

declare -A res
for k in "${order[@]}"; do
  url=${targets[$k]}
  ((total++))
  out=$(test_curl "$url"); code=${out%%,*}; t=${out##*,}; status=FAIL
  if [[ $code =~ ^2|3 ]]; then status=OK; ((status_ok++)); fi
  res[$k]="$status($code,$t)"
  [[ $MODE == text ]] && printf "%-10s %s\n" "$k" "${res[$k]}"
done

percent=$((status_ok*100/total))
if [[ $MODE == text ]]; then
  echo "-----------------------"
  echo "Score $status_ok/$total (${percent}%)"
  if (( percent>=85 )); then echo "Status: ✅ DEV/RESEARCH READY"; elif (( percent>=60 )); then echo "Status: ⚠️ PARTIAL"; else echo "Status: ❌ ISSUE"; fi
else
  printf '{\n'
  printf '  "score": %s, "max": %s, "percent": %s,\n' "$status_ok" "$total" "$percent"
  printf '  "results": {\n'
  first=1
  for k in "${order[@]}"; do
    v=${res[$k]}
    if [[ $first -eq 0 ]]; then printf ',\n'; fi
    printf '    "%s": "%s"' "$k" "$v"
    first=0
  done
  printf '\n  }\n}\n'
fi
