#!/usr/bin/env bash
# system_network_audit.sh
# 全面检查本机网络系统与关键服务连接状况。
# 输出: 终端文本 (可重定向保存)。
#
# 功能模块:
#  1. 基本环境与时间同步
#  2. 网络接口/链路/MTU/速率
#  3. 路由表 / 策略路由 / 默认网关
#  4. DNS 配置 (resolv.conf + systemd-resolved + mihomo dns 端口占用)
#  5. 防火墙 (nftables / iptables) 规则摘要
#  6. 监听端口 (TCP/UDP) & 关键进程 (mihomo)
#  7. 活跃连接统计 (Top 目标 / 进程 / CLOSE-WAIT)
#  8. 代理健康 (端口、controller、最近错误日志提取)
#  9. 关键域名 DNS 解析对比 & TTL
# 10. TLS / HTTP 探针 (直连 vs 代理) 采样
# 11. 基础连通性（Ping / TCP 三次握手耗时）
# 12. 可选: 速度/大流量测试 (默认关闭，需要 --bandwidth)
# 13. 汇总结论 (风险/异常提示)
#
# 使用:
#   ./system_network_audit.sh              (标准模式)
#   ./system_network_audit.sh --quick      (跳过较慢部分: 防火墙全文、速度测试、重复探针)
#   ./system_network_audit.sh --bandwidth  (附加简单下载测速 - 可能消耗流量)
#   ./system_network_audit.sh --out report.txt
#
set -euo pipefail
MODE=standard
OUT=""
DO_BANDWIDTH=0
PROXY=http://127.0.0.1:7890
CTRL=http://127.0.0.1:9090
SECRET="${CLASH_SECRET:-}"
TIMEOUT=5
PING_HOSTS=(1.1.1.1 8.8.8.8 47.117.160.189 www.google.com sso.openxlab.org.cn)
TEST_URLS=(https://sso.openxlab.org.cn/ https://mineru.net/ https://www.google.com/ https://chat.openai.com/ https://api.openai.com/v1/models)
DNS_TEST=(sso.openxlab.org.cn mineru.net www.google.com api.openai.com claude.ai youtube.com)

while [[ $# -gt 0 ]]; do
  case $1 in
    --quick) MODE=quick; shift;;
    --bandwidth) DO_BANDWIDTH=1; shift;;
    --out) OUT="$2"; shift 2;;
    --proxy) PROXY="$2"; shift 2;;
    --controller) CTRL="$2"; shift 2;;
    --secret) SECRET="$2"; shift 2;;
    -h|--help)
      grep -E '^# ' "$0" | sed 's/^# \?//' | sed -n '1,60p'; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

section(){ echo; printf '===== %s =====\n' "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }
now(){ date '+%F %T'; }

curl_silent(){ curl -sS "$@"; }
ctrl_req(){ local path="$1"; curl -fsS -m 3 -H "Authorization: Bearer $SECRET" "$CTRL$path" 2>/dev/null || echo FAIL; }

collect_env(){
  section "环境与时间"
  echo "Timestamp        : $(now)"
  echo "Hostname         : $(hostname)"
  echo "Kernel           : $(uname -sr)"
  echo "Uptime           : $(uptime -p)"
  echo "Timezone         : $(date +%Z)"
  echo "NTP sync (timedatectl) : $(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo NA)"
  echo "Proxy (assumed)  : $PROXY"
  echo "Controller       : $CTRL"
}

collect_if(){
  section "网络接口 / MTU"
  ip -o link show | awk -F': ' '{print $2}' | while read -r dev; do
    [[ $dev == lo ]] && continue
    state=$(ip -o link show "$dev" | awk '{print $9}')
    mtu=$(ip -o link show "$dev" | awk '{for(i=1;i<=NF;i++) if($i ~ /mtu/) {print $(i+1); exit}}')
    addr=$(ip -o -4 addr show dev "$dev" | awk '{print $4}' | paste -sd ',')
    speed=""; have ethtool && speed=$(ethtool "$dev" 2>/dev/null | awk -F': ' '/Speed:/{print $2}')
    printf '%-12s state=%-6s mtu=%-5s addr=%s %s\n' "$dev" "$state" "$mtu" "${addr:-NONE}" "${speed:+speed=$speed}"
  done
}

collect_route(){
  section "路由与默认网关"
  ip route show || true
  echo
  ip rule show 2>/dev/null || true
}

collect_dns(){
  section "DNS 配置"
  echo "/etc/resolv.conf:"; sed -n '1,20p' /etc/resolv.conf || true
  if systemd-resolve --status >/dev/null 2>&1; then
    echo; echo "systemd-resolve status (截取前 40 行):"; systemd-resolve --status | sed -n '1,40p'
  fi
  echo; echo "本地监听 (53/1053):"; ss -ltnup 2>/dev/null | grep -E ':53 |:1053 ' || echo 'no local dns listeners'
}

collect_firewall(){
  section "防火墙摘要"
  if have nft; then nft list ruleset 2>/dev/null | head -n 120 || true; fi
  if have iptables; then echo; echo "iptables -S (前 60 行)"; iptables -S 2>/dev/null | head -n 60; fi
}

collect_listeners(){
  section "监听端口 (Top 50)"
  ss -ltnup 2>/dev/null | head -n 50 || true
  echo; echo "mihomo 进程:"; ps -o pid,cmd -C mihomo 2>/dev/null || pgrep -af mihomo || echo 'not running'
}

collect_conns(){
  section "活跃连接统计"
  echo "按状态计数:"; ss -ant 2>/dev/null | awk 'NR>1{c[$1]++} END{for(k in c) printf "%s %d\n",k,c[k]}' | sort -k2,2nr
  echo; echo "ESTAB Top 目标 (去端口)"; ss -ant 2>/dev/null | awk 'NR>1 && $1=="ESTAB" {split($4,a,":"); split($5,b,":"); print b[1]}' | sort | uniq -c | sort -nr | head -n 15
  echo; echo "CLOSE-WAIT 栈 (前 10)"; ss -ant 2>/dev/null | awk 'NR>1 && $1=="CLOSE-WAIT"{print $0}' | head -n 10 || true
}

collect_proxy(){
  section "代理服务健康"
  ver=$(ctrl_req /version); echo "Controller /version: $ver"
  if [[ $ver != FAIL ]]; then
    group_enc="%E8%A5%BF%E7%93%9C%E5%8A%A0%E9%80%9F"
    grp=$(ctrl_req /proxies/$group_enc | head -c 300 || true)
    echo "Group snippet: ${grp:-N/A}"
  fi
  echo; echo "最近 mihomo 警告/错误 (最后 40 行过滤)";
  journalctl --user -u mihomo.service -n 400 --no-pager 2>/dev/null | grep -E 'level=warning|level=error' | tail -n 40 || echo 'no warnings'
}

collect_dns_test(){
  section "关键域名解析"
  for d in "${DNS_TEST[@]}"; do
    ans=$(getent ahostsv4 "$d" 2>/dev/null | awk '{print $1}' | paste -sd ',' )
    printf '%-25s %s\n' "$d" "${ans:-RESOLVE_FAIL}"
  done
}

curl_probe(){ curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout $TIMEOUT --max-time $((TIMEOUT+4)) "$@" 2>/dev/null || echo "000,$TIMEOUT"; }

collect_http(){
  section "HTTP/TLS 探针"
  printf '%-42s %-16s %-16s\n' "URL" "direct(code,time)" "proxy(code,time)"
  for u in "${TEST_URLS[@]}"; do
    d=$(curl_probe "$u")
    p=$(curl_probe --proxy "$PROXY" "$u")
    printf '%-42s %-16s %-16s\n' "$u" "$d" "$p"
  done
}

collect_ping(){
  section "基础连通性 (Ping)"
  for h in "${PING_HOSTS[@]}"; do
    rtt=$(ping -c1 -W1 "$h" 2>/dev/null | awk -F'/' '/rtt|round-trip/{print $5"ms"}')
    status=OK; [[ -z $rtt ]] && status=FAIL
    printf '%-20s %-8s %s\n' "$h" "$status" "${rtt:-}" 
  done
}

collect_bandwidth(){
  [[ $DO_BANDWIDTH -eq 1 ]] || return 0
  section "简易下载速度测试"
  test_file=https://speed.hetzner.de/10MB.bin
  out=$(curl -m 20 -w '%{size_download},%{time_total}' -o /dev/null -s "$test_file" || true)
  size=${out%%,*}; t=${out##*,}
  if [[ -n $size && -n $t && $t != 0 ]]; then
    mbps=$(awk -v s="$size" -v t="$t" 'BEGIN{printf "%.2f", (s*8/1000/1000)/t}')
    echo "Direct: ${mbps} Mbps (${size} bytes / ${t}s)"
  else
    echo "Direct test failed"
  fi
  out2=$(curl -x "$PROXY" -m 25 -w '%{size_download},%{time_total}' -o /dev/null -s "$test_file" || true)
  size2=${out2%%,*}; t2=${out2##*,}
  if [[ -n $size2 && -n $t2 && $t2 != 0 ]]; then
    mbps2=$(awk -v s="$size2" -v t="$t2" 'BEGIN{printf "%.2f", (s*8/1000/1000)/t}')
    echo "Proxy : ${mbps2} Mbps (${size2} bytes / ${t2}s)"
  else
    echo "Proxy test failed"
  fi
}

collect_summary(){
  section "汇总与提示"
  warn=0
  echo "检查异常要点:" 
  if journalctl --user -u mihomo.service -n 200 --no-pager 2>/dev/null | grep -q 'connect error'; then
    echo "- 发现 mihomo connect error (可能节点质量/阻断)"; warn=1
  fi
  g_proxy=$(curl_probe --proxy "$PROXY" https://www.google.com/)
  [[ $g_proxy == 000,* ]] && { echo "- 代理访问 www.google.com 失败"; warn=1; }
  sso_p=$(curl_probe --proxy "$PROXY" https://sso.openxlab.org.cn/)
  [[ $sso_p == 000,* ]] && { echo "- 代理到 sso.openxlab.org.cn TLS 握手失败 (建议保持直连规则)"; warn=1; }
  [[ $warn -eq 0 ]] && echo "- 未检测到严重异常 (仍需人工复核日志)"
}

main(){
  collect_env
  collect_if
  collect_route
  collect_dns
  [[ $MODE == quick ]] || collect_firewall
  collect_listeners
  collect_conns
  collect_proxy
  collect_dns_test
  collect_http
  collect_ping
  collect_bandwidth
  collect_summary
}

if [[ -n $OUT ]]; then
  main | tee "$OUT"
else
  main
fi
exit 0
