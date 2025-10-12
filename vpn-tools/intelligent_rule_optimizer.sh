#!/usr/bin/env bash
# intelligent_rule_optimizer.sh
# 目的: 智能规则优化器 - 根据网站类型自动推荐最佳规则方案
# 功能:
#   1. 分析不同类型网站的访问模式和延迟
#   2. 自动为每类网站推荐最优节点
#   3. 生成优化的规则配置
#   4. 支持学习历史数据优化决策
#
# 使用方法:
#   ./intelligent_rule_optimizer.sh --analyze     # 分析当前配置
#   ./intelligent_rule_optimizer.sh --optimize    # 生成优化建议
#   ./intelligent_rule_optimizer.sh --apply       # 应用优化方案
#   ./intelligent_rule_optimizer.sh --learn       # 从历史学习

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$BASE_DIR")"
MIXIN_FILE="$PARENT_DIR/resources/mixin.yaml"
RUNTIME_FILE="$HOME/.local/share/clash/runtime.yaml"
RULES_DB="$HOME/.local/share/clash/rules_optimization.db"
ANALYSIS_LOG="$HOME/.local/share/clash/logs/rule_analysis.log"

API=${CLASH_API:-http://127.0.0.1:9090}
PROXY=${PROXY:-http://127.0.0.1:7890}

MODE="analyze"
VERBOSE=false

mkdir -p "$(dirname "$RULES_DB")" "$(dirname "$ANALYSIS_LOG")"

have() { command -v "$1" >/dev/null 2>&1; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$ANALYSIS_LOG"; }
vlog() { $VERBOSE && log "$*" || true; }

# 网站分类定义
declare -A SITE_CATEGORIES
SITE_CATEGORIES=(
    ["ai"]="api.openai.com,claude.ai,chat.openai.com,api.anthropic.com,huggingface.co"
    ["development"]="github.com,gitlab.com,stackoverflow.com,npmjs.com,pypi.org,crates.io"
    ["streaming"]="youtube.com,netflix.com,twitch.tv,spotify.com"
    ["gaming"]="steampowered.com,epicgames.com,store.steampowered.com"
    ["meeting"]="zoom.us,meet.google.com,teams.microsoft.com"
    ["shopping"]="amazon.com,ebay.com,aliexpress.com"
    ["social"]="twitter.com,facebook.com,instagram.com,reddit.com"
    ["news"]="bbc.com,cnn.com,reuters.com,theguardian.com"
    ["domestic"]="baidu.com,taobao.com,bilibili.com,zhihu.com,weibo.com"
)

# 获取可用节点列表
get_available_nodes() {
    local group="$1"
    if ! have jq; then
        curl -fsS "$API/proxies/$group" 2>/dev/null | \
            grep -oP '(?<="all":\[)[^\]]+' | tr ',' '\n' | tr -d '"' | grep -v '^$'
        return
    fi
    
    curl -fsS "$API/proxies/$group" 2>/dev/null | jq -r '.all[]' 2>/dev/null || true
}

# 测试节点到特定域名的性能
test_node_performance() {
    local node="$1" domain="$2" group="${3:-西瓜加速}"
    
    vlog "测试节点 $node 访问 $domain"
    
    # 切换到指定节点
    curl -s -X PUT "$API/proxies/$group" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"$node\"}" >/dev/null 2>&1 || return 1
    
    sleep 2
    
    # 测试性能
    local start_ms end_ms duration http_code success=0
    start_ms=$(date +%s%3N 2>/dev/null || echo $(($(date +%s) * 1000)))
    
    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        --connect-timeout 5 --max-time 10 \
        --proxy "$PROXY" "https://$domain" 2>/dev/null || echo "000")
    
    end_ms=$(date +%s%3N 2>/dev/null || echo $(($(date +%s) * 1000)))
    duration=$((end_ms - start_ms))
    
    [[ "$http_code" =~ ^[23] ]] && success=1
    
    echo "$node|$domain|$duration|$http_code|$success"
}

# 分析每个类别的最佳节点
analyze_category() {
    local category="$1"
    local domains="${SITE_CATEGORIES[$category]}"
    
    log "分析类别: $category"
    log "  测试域名: $domains"
    
    # 获取可用节点
    local nodes
    mapfile -t nodes < <(get_available_nodes "西瓜加速" | head -n 10)
    
    if [ ${#nodes[@]} -eq 0 ]; then
        log "  错误: 无可用节点"
        return 1
    fi
    
    log "  可用节点数: ${#nodes[@]}"
    
    # 为每个节点打分
    declare -A node_scores
    declare -A node_latencies
    
    for node in "${nodes[@]}"; do
        [[ -z "$node" || "$node" =~ ^(剩余流量|套餐到期|官网|防丢失|网不通|招募) ]] && continue
        
        local total_score=0 test_count=0 total_latency=0
        
        # 测试该节点访问该类别的多个域名
        IFS=',' read -ra domain_list <<< "$domains"
        for domain in "${domain_list[@]:0:3}"; do  # 只测试前3个域名以节省时间
            result=$(test_node_performance "$node" "$domain" || echo "$node|$domain|9999|000|0")
            IFS='|' read -r n d lat code succ <<< "$result"
            
            ((test_count++))
            ((total_latency+=lat))
            
            if [ "$succ" -eq 1 ]; then
                # 根据延迟给分
                if [ "$lat" -lt 500 ]; then
                    ((total_score+=10))
                elif [ "$lat" -lt 1000 ]; then
                    ((total_score+=7))
                elif [ "$lat" -lt 2000 ]; then
                    ((total_score+=5))
                else
                    ((total_score+=2))
                fi
            fi
        done
        
        if [ "$test_count" -gt 0 ]; then
            node_scores["$node"]=$total_score
            node_latencies["$node"]=$((total_latency / test_count))
            vlog "  节点 $node: 得分=$total_score, 平均延迟=${node_latencies[$node]}ms"
        fi
    done
    
    # 找出得分最高的节点
    local best_node="" best_score=0 best_latency=9999
    for node in "${!node_scores[@]}"; do
        if [ "${node_scores[$node]}" -gt "$best_score" ]; then
            best_score="${node_scores[$node]}"
            best_node="$node"
            best_latency="${node_latencies[$node]}"
        elif [ "${node_scores[$node]}" -eq "$best_score" ] && [ "${node_latencies[$node]}" -lt "$best_latency" ]; then
            best_node="$node"
            best_latency="${node_latencies[$node]}"
        fi
    done
    
    log "  最佳节点: $best_node (得分=$best_score, 平均延迟=${best_latency}ms)"
    
    # 保存到数据库
    echo "$(date +%s)|$category|$best_node|$best_score|$best_latency" >> "$RULES_DB"
    
    echo "$category|$best_node|$best_score|$best_latency"
}

# 分析所有类别
analyze_all_categories() {
    log "========================================="
    log "开始智能规则分析"
    log "========================================="
    
    local results_file="/tmp/rule_analysis_$(date +%Y%m%d_%H%M%S).txt"
    
    for category in "${!SITE_CATEGORIES[@]}"; do
        # 跳过国内类别（应该DIRECT）
        [ "$category" = "domestic" ] && continue
        
        result=$(analyze_category "$category" || echo "$category|unknown|0|9999")
        echo "$result" >> "$results_file"
        
        sleep 2  # 避免过于频繁切换节点
    done
    
    log "分析完成，结果保存到: $results_file"
    echo "$results_file"
}

# 生成优化建议
generate_recommendations() {
    log "生成优化建议..."
    
    if [ ! -f "$RULES_DB" ] || [ ! -s "$RULES_DB" ]; then
        log "错误: 规则数据库为空，请先运行 --analyze"
        return 1
    fi
    
    local recommendations_file="$HOME/.local/share/clash/rule_recommendations_$(date +%Y%m%d_%H%M%S).md"
    
    cat > "$recommendations_file" <<'EOF'
# 智能规则优化建议

## 基于性能测试的规则推荐

根据对各类网站的性能测试，以下是推荐的规则配置：

### 推荐的 proxy-groups 配置

```yaml
proxy-groups:
EOF
    
    # 为每个类别生成推荐的分组
    while IFS='|' read -r timestamp category best_node score latency; do
        cat >> "$recommendations_file" <<EOF
  - name: $(echo $category | tr '[:lower:]' '[:upper:]')
    type: select
    proxies:
      - $best_node
      - AUTO-SMART
      - DIRECT
    # 性能: 得分=$score, 平均延迟=${latency}ms
EOF
    done < <(tail -n 20 "$RULES_DB" | sort -t'|' -k2 -u)
    
    cat >> "$recommendations_file" <<'EOF'
```

### 推荐的 rules 配置

```yaml
rules:
EOF
    
    # 为每个类别生成规则
    for category in "${!SITE_CATEGORIES[@]}"; do
        local group_name=$(echo $category | tr '[:lower:]' '[:upper:]')
        local domains="${SITE_CATEGORIES[$category]}"
        
        cat >> "$recommendations_file" <<EOF
  # $category 类网站
EOF
        IFS=',' read -ra domain_list <<< "$domains"
        for domain in "${domain_list[@]}"; do
            echo "  - DOMAIN-SUFFIX,$domain,$group_name" >> "$recommendations_file"
        done
        echo "" >> "$recommendations_file"
    done
    
    cat >> "$recommendations_file" <<'EOF'
```

## 应用建议

1. 将上述配置添加到 `mixin.yaml`
2. 运行 `clash update` 重新加载配置
3. 使用 `./network_health_monitor.sh` 验证效果

## 注意事项

- 建议保留原有的 DIRECT 规则以确保国内网站正常访问
- 可以根据实际使用情况微调节点选择
- 定期重新运行分析以适应节点状态变化

EOF
    
    log "优化建议已生成: $recommendations_file"
    cat "$recommendations_file"
}

# 应用优化方案
apply_optimizations() {
    log "准备应用优化方案..."
    
    if [ ! -f "$MIXIN_FILE" ]; then
        log "错误: mixin.yaml 不存在"
        return 1
    fi
    
    # 备份当前配置
    local backup_file="${MIXIN_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$MIXIN_FILE" "$backup_file"
    log "已备份当前配置到: $backup_file"
    
    # 这里应该生成新的 mixin.yaml，但为了安全，我们只生成建议
    log "为了安全，请手动审查建议后再应用"
    log "建议文件位于: $HOME/.local/share/clash/rule_recommendations_*.md"
    
    generate_recommendations
}

# 从历史学习
learn_from_history() {
    log "从历史数据学习..."
    
    if [ ! -f "$RULES_DB" ] || [ ! -s "$RULES_DB" ]; then
        log "警告: 规则数据库为空"
        return 0
    fi
    
    log "分析历史数据..."
    
    # 统计每个类别最常推荐的节点
    for category in "${!SITE_CATEGORIES[@]}"; do
        local top_nodes=$(grep "|$category|" "$RULES_DB" | \
            cut -d'|' -f3 | sort | uniq -c | sort -rn | head -n 3)
        
        if [ -n "$top_nodes" ]; then
            log "类别 $category 历史最优节点:"
            echo "$top_nodes" | while read -r count node; do
                log "  $node: $count 次"
            done
        fi
    done
    
    # 清理旧数据（保留最近100条）
    local lines=$(wc -l < "$RULES_DB")
    if [ "$lines" -gt 100 ]; then
        tail -n 100 "$RULES_DB" > "${RULES_DB}.tmp"
        mv "${RULES_DB}.tmp" "$RULES_DB"
        log "已清理旧数据，保留最近100条记录"
    fi
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --analyze|-a)
            MODE="analyze"
            shift
            ;;
        --optimize|-o)
            MODE="optimize"
            shift
            ;;
        --apply)
            MODE="apply"
            shift
            ;;
        --learn|-l)
            MODE="learn"
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            cat <<EOF
智能规则优化器

用法:
  $0 [选项]

选项:
  --analyze, -a    分析当前配置并测试节点性能
  --optimize, -o   生成优化建议
  --apply          应用优化方案
  --learn, -l      从历史数据学习
  --verbose, -v    详细输出
  -h, --help       显示帮助

示例:
  $0 --analyze     # 分析并测试
  $0 --optimize    # 生成建议
  $0 --learn       # 学习历史

工作流程:
  1. 运行 --analyze 测试各类网站的节点性能
  2. 运行 --optimize 生成优化建议
  3. 手动审查建议
  4. （可选）运行 --apply 应用优化
  5. 定期运行 --learn 从历史学习

EOF
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 主逻辑
case "$MODE" in
    analyze)
        analyze_all_categories
        ;;
    optimize)
        generate_recommendations
        ;;
    apply)
        apply_optimizations
        ;;
    learn)
        learn_from_history
        ;;
esac

log "完成"
