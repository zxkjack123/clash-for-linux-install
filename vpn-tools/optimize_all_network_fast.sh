#!/usr/bin/env bash
# optimize_all_network_fast.sh
# 一键"快速"稳定化：在3-5分钟内完成最关键的修复与优化，尽可能提升稳定与速度
# 步骤：
#  1) 运行时守护自检 + 自愈（关键DIRECT规则、防劫持）
#  2) 快速AI节点优选（轻量）
#  3) 开发/常用服务连通性快测 + 提示
#  4) 写入健康指标并给出后续建议
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$BASE_DIR")"
log(){ echo "[$(date '+%F %T')] $*"; }
step(){ echo; echo "==== $* ===="; }

step "1/4 运行时守护自检 + 自愈"
if [ -x "$PARENT_DIR/script/runtime_guard.sh" ]; then
  bash "$PARENT_DIR/script/runtime_guard.sh" --auto-fix --report || true
else
  log "未找到 runtime_guard.sh"
fi

step "2/4 快速AI节点优选"
if [ -x "$BASE_DIR/optimize_ai.sh" ]; then
  timeout 180 "$BASE_DIR/optimize_ai.sh" || true
else
  log "未找到 optimize_ai.sh"
fi

step "3/4 常用服务连通性快测"
if [ -x "$BASE_DIR/quick_vpn_check.sh" ]; then
  "$BASE_DIR/quick_vpn_check.sh" || true
fi

step "4/4 写入健康指标 + 建议"
if command -v clash >/dev/null 2>&1; then
  clash metrics || true
fi
cat <<'TIP'

建议：
- 若 5 分钟内仍频繁断流，可执行：
    clash downgrade --since 15 --threshold 8 --mode tag
  然后在面板/分组中避免选择带 [FAIL] 的节点。
- 想要持续守护与告警：
    cd vpn-tools && ./setup_monitoring_cron.sh --install
- 一键全量优化（较慢，含流媒体/国内站）：
    cd vpn-tools && ./optimize_all_network.sh
TIP
