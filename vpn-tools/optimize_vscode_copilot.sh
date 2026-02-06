#!/usr/bin/env bash
# VSCode Copilot 网络优化脚本
# 确保 GitHub Copilot 和相关服务使用最佳节点

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<'EOF'
VSCode Copilot 网络优化 / 诊断

Usage:
  optimize_vscode_copilot.sh              # 默认：优化 + 检查
  optimize_vscode_copilot.sh --check      # 仅检查（不切换节点/不运行 optimize_ai.sh）

Options:
  --check, --no-optimize   Skip optimization (fast, non-invasive)
  --optimize               Force run optimization (default)
  --proxy URL              Override local proxy URL (default: http://127.0.0.1:7890)
  --api URL                Override Clash controller API (default: http://127.0.0.1:9090)
  -h, --help               Show help
EOF
}

DO_OPTIMIZE=1
PROXY_URL="http://127.0.0.1:7890"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check|--no-optimize)
            DO_OPTIMIZE=0; shift ;;
        --optimize)
            DO_OPTIMIZE=1; shift ;;
        --proxy)
            [[ $# -ge 2 ]] || { echo "[ERROR] --proxy requires a URL" >&2; exit 2; }
            PROXY_URL="$2"; shift 2 ;;
        --api)
            [[ $# -ge 2 ]] || { echo "[ERROR] --api requires a URL" >&2; exit 2; }
            CLASH_API="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "[ERROR] Unknown arg: $1" >&2
            usage
            exit 2
            ;;
    esac
done

echo "=== VSCode Copilot 网络优化 ($(date '+%Y-%m-%d %H:%M:%S')) ==="

# Load env (optional) and bootstrap controller/secret
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true

API="${CLASH_API:-http://127.0.0.1:9090}"
API="${API%/}"
AUTH_HDR=()
_hdr="$(clash_auth_header 2>/dev/null || true)"
[[ -n "${_hdr:-}" ]] && AUTH_HDR=(-H "${_hdr}")

# 1. 检查 Clash 服务状态
echo ""
echo "📡 检查 Clash 服务..."
if ! curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "${AUTH_HDR[@]}" "${API}/version" >/dev/null 2>&1; then
    echo "❌ Clash 服务未运行"
    echo "   (提示) 如果你已启用 controller secret，请确保本脚本能读取 runtime.yaml 中的 secret。"
    exit 1
fi
echo "✅ Clash 服务正常"

# 2. 优化 AI 节点 (包括 GitHub Copilot)
echo ""
echo "🔧 优化 AI 服务节点..."
if [[ "$DO_OPTIMIZE" -eq 1 ]]; then
    if [ -f "$SCRIPT_DIR/optimize_ai.sh" ]; then
        bash "$SCRIPT_DIR/optimize_ai.sh" 2>&1 | tail -10 || true
    else
        echo "⚠️  optimize_ai.sh 不存在，跳过"
    fi
else
    echo "ℹ️  --check 模式：跳过节点优化（不切换节点）"
fi

# 3. 测试关键服务连接
echo ""
echo "🧪 测试关键服务连接..."

_curl_code_time() {
    # Print: <code> <time_total>
    # If curl errors, return code=000.
    local url="$1"; shift
    local out rc code t
    out=$(curl -sS -o /dev/null -w '%{http_code} %{time_total}' \
        --connect-timeout 6 --max-time 10 \
        --proxy "$PROXY_URL" "$url" 2>/dev/null) || rc=$?
    rc=${rc:-0}
    code=${out%% *}
    t=${out#* }
    [[ -n "${code:-}" ]] || code=000
    [[ -n "${t:-}" && "$t" != "$code" ]] || t=0
    if [[ $rc -ne 0 ]]; then
        code=000
    fi
    printf '%s %s\n' "$code" "$t"
}

_is_ok_code() {
    local code="$1" allow_re="$2"
    [[ "$code" =~ $allow_re ]]
}

test_endpoint() {
    local name="$1" url="$2" allow_re="$3"
    local code t
    read -r code t < <(_curl_code_time "$url")
    if _is_ok_code "$code" "$allow_re"; then
        echo "  ✓ $name - HTTP:$code Time:${t}s"
    else
        echo "  ✗ $name - HTTP:$code Time:${t}s"
    fi
}

# NOTE: treat 404 as reachable for Copilot endpoints (healthz / proxy root often returns 404).
test_endpoint "GitHub API (proxy)" "https://api.github.com/" '^(200|301|302|401|403)$'
test_endpoint "Copilot API (proxy)" "https://api.githubcopilot.com/healthz" '^(200|204|301|302|404)$'
test_endpoint "Copilot Proxy (proxy)" "https://copilot-proxy.githubusercontent.com/" '^(200|301|302|404)$'
test_endpoint "OpenAI API (proxy)" "https://api.openai.com/v1/models" '^(200|401|403)$'

# If Copilot endpoints fail via proxy, check direct path and recommend VS Code relaunch with NO_PROXY bypass
echo ""
echo "🔍 Copilot endpoint bypass check (direct vs proxy) ..."
direct_copilot=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 4 --max-time 6 --noproxy '*' https://api.githubcopilot.com/healthz 2>/dev/null); rc=$?; [[ $rc -eq 0 ]] || direct_copilot=000
proxy_copilot=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 6 --max-time 10 --proxy "$PROXY_URL" https://api.githubcopilot.com/healthz 2>/dev/null); rc=$?; [[ $rc -eq 0 ]] || proxy_copilot=000
echo "  Direct: $direct_copilot  |  Proxy: $proxy_copilot"
if [[ "$proxy_copilot" == "000" || "$proxy_copilot" == "408" ]] && [[ "$direct_copilot" =~ ^(200|204|301|302|404)$ ]]; then
    echo ""
    echo "💡 观察到 Copilot 通过代理失败、直连成功 —— 为 VS Code 临时绕过代理 (NO_PROXY) 可快速恢复稳定性。"
    echo "   接下来会提供一条命令启动一个带 NO_PROXY 绕过的 VS Code 窗口。"
    echo ""
    echo "👉 运行: $SCRIPT_DIR/fix_vscode_stale_proxy.sh --launch-here"
fi

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
vscode_pids=$(pgrep -x code 2>/dev/null | head -10 || true)
if [ -n "$vscode_pids" ]; then
    found_proxy=0
    for pid in $vscode_pids; do
        [ -r "/proc/$pid/environ" ] || continue
        proxy_info=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
            | grep -iE '^(http|https|all|no)_proxy=' \
            | head -10 || true)
        if [ -n "$proxy_info" ]; then
            echo "  PID $pid:"
            echo "$proxy_info" | sed 's/^/    /'
            if echo "$proxy_info" | grep -q '127\.0\.0\.1:6209'; then
                echo "    ⚠️  检测到 6209 stale proxy（旧 VS Code 环境残留），建议完全退出 VS Code 并用 fix_vscode_stale_proxy.sh --launch-here 重新打开。"
            fi
            found_proxy=1
            break
        fi
    done

    if [ "$found_proxy" -eq 0 ]; then
        echo "  ℹ️  检测到 VS Code 进程，但未在前几个进程环境中发现 proxy 变量（可能由 VS Code 内部设置控制，或进程为 zygote/renderer）。"
    fi
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
