#!/usr/bin/env bash
# VSCode Copilot 网络优化脚本
# 确保 GitHub Copilot 和相关服务使用最佳节点

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

echo "=== VSCode Copilot 网络优化 ($(date '+%Y-%m-%d %H:%M:%S')) ==="

# 1. 检查 Clash 服务状态
echo ""
echo "📡 检查 Clash 服务..."
if ! curl -s http://127.0.0.1:9090/version >/dev/null 2>&1; then
    echo "❌ Clash 服务未运行"
    exit 1
fi
echo "✅ Clash 服务正常"

# 2. 优化 AI 节点 (包括 GitHub Copilot)
echo ""
echo "🔧 优化 AI 服务节点..."
if [ -f "$SCRIPT_DIR/optimize_ai.sh" ]; then
    bash "$SCRIPT_DIR/optimize_ai.sh" 2>&1 | tail -10
else
    echo "⚠️  optimize_ai.sh 不存在，跳过"
fi

# 3. 测试关键服务连接
echo ""
echo "🧪 测试关键服务连接..."

test_endpoint() {
    local name="$1"
    local url="$2"
    local result
    result=$(curl -s -w "HTTP:%{http_code} Time:%{time_total}s" -o /dev/null --connect-timeout 5 --max-time 10 "$url" 2>&1)
    if echo "$result" | grep -q "HTTP:"; then
        echo "  ✓ $name - $result"
    else
        echo "  ✗ $name - 连接失败"
    fi
}

test_endpoint "GitHub API" "https://api.github.com"
test_endpoint "GitHub Copilot" "https://api.githubcopilot.com/healthz"
test_endpoint "Copilot Proxy" "https://copilot-proxy.githubusercontent.com"
test_endpoint "OpenAI API" "https://api.openai.com/v1/models"

# 4. 检查代理环境变量
echo ""
echo "🔍 检查代理配置..."
if [ -n "${http_proxy:-}" ]; then
    echo "  HTTP_PROXY: $http_proxy"
else
    echo "  ⚠️  HTTP_PROXY 未设置"
fi

if [ -n "${https_proxy:-}" ]; then
    echo "  HTTPS_PROXY: $https_proxy"
else
    echo "  ⚠️  HTTPS_PROXY 未设置"
fi

# 5. 检查 VSCode 进程代理配置
echo ""
echo "🔍 检查 VSCode 进程代理..."
if pgrep -f "code.*extensionHost" >/dev/null 2>&1; then
    vscode_pids=$(pgrep -f "code.*extensionHost" | head -3)
    for pid in $vscode_pids; do
        proxy_info=$(tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -i proxy | head -3 || true)
        if [ -n "$proxy_info" ]; then
            echo "  PID $pid:"
            echo "$proxy_info" | sed 's/^/    /'
            break
        fi
    done
else
    echo "  ℹ️  VSCode 未运行"
fi

# 6. 提供建议
echo ""
echo "=== 建议 ==="
echo "1. 如果 Copilot 仍然断开，请完全退出 VSCode (File > Exit)"
echo "2. 重新启动 VSCode 以应用新的代理配置"
echo "3. 或使用: bash $SCRIPT_DIR/fix_vscode_stale_proxy.sh --launch-here"
echo ""
echo "✅ 优化完成 ($(date '+%Y-%m-%d %H:%M:%S'))"
