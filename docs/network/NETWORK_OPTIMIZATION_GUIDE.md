# 🚀 Clash 网络优化与监控完整指南

**更新时间**: 2025-10-12  
**版本**: 2.0

本指南介绍如何使用全新的网络监控和优化工具，实现网络服务的稳定性提升、速度优化、智能规则管理和异常监控告警。

---

## 📋 目录

1. [快速开始](#快速开始)
2. [核心功能](#核心功能)
3. [工具详解](#工具详解)
4. [最佳实践](#最佳实践)
5. [故障排查](#故障排查)
6. [高级配置](#高级配置)

---

## 🎯 快速开始

### 一键部署监控系统

```bash
cd /home/gw/opt/clash-for-linux-install/vpn-tools

# 1. 设置可执行权限
chmod +x network_health_monitor.sh
chmod +x intelligent_rule_optimizer.sh
chmod +x alert_notification.sh
chmod +x setup_monitoring_cron.sh
chmod +x network_dashboard.sh

# 2. 初始化监控系统
./setup_monitoring_cron.sh --setup

# 3. 配置告警通知
./alert_notification.sh --config
# 编辑 ~/.local/share/clash/alert_config.conf 配置通知方式

# 4. 运行初始健康检查
./network_health_monitor.sh

# 5. 安装定期监控任务
./setup_monitoring_cron.sh --install

# 6. 查看仪表盘
./network_dashboard.sh
```

**恭喜！** 🎉 您的网络监控系统已经启动！

---

## 🌟 核心功能

### 1. 实时网络健康监控

✅ **自动监控内容**：
- AI服务（OpenAI、Claude、Anthropic等）
- 开发服务（GitHub、NPM、PyPI等）
- 流媒体（YouTube、Netflix、Zoom）
- 国内网站（百度、淘宝、B站、知乎）

✅ **监控指标**：
- 成功率（可用性）
- 平均延迟（响应时间）
- 健康分数（0-100）
- 健康等级（A/B/C/D/F）

✅ **自动化处理**：
- 检测到问题自动触发修复
- AI服务异常→执行 AI 优化
- 流媒体异常→执行节点优化
- 配置异常→执行运行时修复

### 2. 智能规则优化

✅ **智能分析**：
- 测试不同节点访问各类网站的性能
- 自动为每类网站推荐最佳节点
- 学习历史数据优化决策

✅ **支持的网站类别**：
- AI（ChatGPT、Claude等）
- 开发（GitHub、Stack Overflow等）
- 流媒体（YouTube、Netflix等）
- 游戏（Steam、Epic等）
- 会议（Zoom、Teams等）
- 购物、社交、新闻等

✅ **自动生成**：
- 优化后的 `proxy-groups` 配置
- 优化后的 `rules` 规则
- 详细的性能报告

### 3. 多渠道告警通知

✅ **通知方式**：
- 桌面通知（notify-send）
- 日志文件
- Webhook（可集成企业微信、钉钉等）
- 邮件（可选）

✅ **告警级别**：
- **INFO**: 一般信息
- **WARNING**: 警告（需要关注）
- **CRITICAL**: 严重问题（需要立即处理）

✅ **智能去重**：
- 相同告警5分钟内只通知一次
- 避免告警风暴

### 4. 可视化仪表盘

✅ **实时显示**：
- 系统概览（服务状态、当前节点、运行时间）
- 健康状态（分数、等级、趋势）
- 服务详情（各类网站的性能）
- 最近告警
- 性能趋势图表

✅ **快速操作**：
- 一键健康检查
- 一键优化服务
- 一键重启服务
- 生成详细报告

---

## 🔧 工具详解

### 1. network_health_monitor.sh - 网络健康监控

**功能**：全面的网络健康检查和自动修复

```bash
# 运行一次检查
./network_health_monitor.sh

# 仅检查不修复
./network_health_monitor.sh --check-only

# 生成详细报告
./network_health_monitor.sh --report

# 后台守护模式（每10分钟检查一次）
./network_health_monitor.sh --daemon

# 自定义检查间隔（守护模式）
./network_health_monitor.sh --daemon --interval 600

# 禁用自动修复
./network_health_monitor.sh --no-fix
```

**输出示例**：
```
========== 健康检查结果 ==========
总体健康分数: 85/100
健康等级: B - 良好

AI服务:     成功率 100% | 平均延迟 450ms
开发服务:   成功率 100% | 平均延迟 380ms
流媒体服务: 成功率 75%  | 平均延迟 520ms
国内网站:   成功率 100% | 平均延迟 120ms
=================================
```

**自动修复逻辑**：
- 健康分数 < 60 → 触发运行时修复
- AI成功率 < 50% → 执行AI优化
- 流媒体成功率 < 50% → 执行流媒体优化
- 服务不可用 → 尝试重启服务

### 2. intelligent_rule_optimizer.sh - 智能规则优化

**功能**：基于性能测试自动优化规则配置

```bash
# 分析当前配置（测试节点性能）
./intelligent_rule_optimizer.sh --analyze

# 生成优化建议
./intelligent_rule_optimizer.sh --optimize

# 应用优化方案
./intelligent_rule_optimizer.sh --apply

# 从历史数据学习
./intelligent_rule_optimizer.sh --learn

# 详细输出
./intelligent_rule_optimizer.sh --analyze --verbose
```

**工作流程**：
1. **分析阶段**：测试各节点访问不同类型网站的性能
2. **评分阶段**：根据延迟和成功率为节点打分
3. **推荐阶段**：为每类网站选择最佳节点
4. **生成阶段**：生成优化后的配置文件

**输出文件**：
- 规则数据库：`~/.local/share/clash/rules_optimization.db`
- 优化建议：`~/.local/share/clash/rule_recommendations_*.md`

### 3. alert_notification.sh - 告警通知系统

**功能**：多渠道告警通知

```bash
# 发送告警
./alert_notification.sh INFO "系统正常运行"
./alert_notification.sh WARNING "网络延迟过高"
./alert_notification.sh CRITICAL "服务停止"

# 创建配置文件
./alert_notification.sh --config

# 测试告警系统
./alert_notification.sh --test

# 查看告警历史
./alert_notification.sh --history
```

**配置文件**：`~/.local/share/clash/alert_config.conf`

```bash
# 启用桌面通知
ENABLE_DESKTOP_NOTIFICATION=true

# 启用 Webhook（企业微信、钉钉等）
ENABLE_WEBHOOK=true
WEBHOOK_URL="https://your-webhook-url.com/alert"

# 启用邮件通知
ENABLE_EMAIL=true
EMAIL_TO="admin@example.com"

# 告警频率限制（秒）
RATE_LIMIT_SECONDS=300
```

### 4. setup_monitoring_cron.sh - 监控任务调度

**功能**：自动配置定期监控任务

```bash
# 安装监控任务
./setup_monitoring_cron.sh --install

# 查看状态
./setup_monitoring_cron.sh --status

# 测试监控脚本
./setup_monitoring_cron.sh --test

# 卸载监控任务
./setup_monitoring_cron.sh --uninstall

# 初始化目录结构
./setup_monitoring_cron.sh --setup
```

**安装的定时任务**：
- ⏰ **每10分钟**: 网络健康检查
- ⏰ **每10分钟**: 运行时守护检查（自动修复）
- ⏰ **每天03:00**: 智能规则学习
- ⏰ **每周日04:00**: 全面规则分析
- ⏰ **每天02:00**: 日志清理（保留30天）
- ⏰ **每小时**: 健康快照

### 5. network_dashboard.sh - 可视化仪表盘

**功能**：实时网络状态可视化

```bash
# 交互式仪表盘
./network_dashboard.sh

# 持续刷新模式（每10秒）
./network_dashboard.sh --watch

# 自定义刷新间隔（5秒）
./network_dashboard.sh --watch --interval 5
```

**显示内容**：
- 📊 系统概览
- 💚 健康状态（分数、等级）
- 📈 服务详情
- ⚠️ 最近告警
- 📉 性能趋势
- 🔧 快速操作

---

## 💡 最佳实践

### 日常使用流程

#### 早上启动
```bash
# 查看仪表盘
./network_dashboard.sh

# 如果健康分数低，运行优化
./network_health_monitor.sh

# 查看告警
./alert_notification.sh --history
```

#### 工作前优化
```bash
# AI工作前
./optimize_ai.sh

# 开发工作前
# 检查GitHub、NPM等服务状态

# 观看视频前
./select_youtube_node.sh

# 开会前
./fix_zoom_connectivity.sh
```

#### 遇到问题时
```bash
# 1. 快速诊断
./quick_vpn_check.sh

# 2. 全面检查
./network_connectivity_test.sh full

# 3. 修复问题
./network_health_monitor.sh

# 4. 运行时修复
bash ../script/runtime_guard.sh --auto-fix
```

### 定期维护

**每周**：
```bash
# 查看性能趋势
./network_dashboard.sh

# 分析规则优化空间
./intelligent_rule_optimizer.sh --analyze
./intelligent_rule_optimizer.sh --optimize
```

**每月**：
```bash
# 检查日志大小
du -sh ~/.local/share/clash/logs/

# 备份配置
cp -r ~/.local/share/clash/resources/ ~/clash_backup_$(date +%Y%m%d)/

# 清理旧备份
find ~/.local/share/clash/resources/backup/ -mtime +90 -delete
```

### 性能优化建议

#### 1. 针对不同场景选择节点

**AI 场景**（ChatGPT、Claude）：
- 优先：美国、新加坡、日本节点
- 要求：低延迟（<500ms），高稳定性

**开发场景**（GitHub、NPM）：
- 优先：香港、新加坡、日本节点
- 要求：稳定连接，适中延迟

**流媒体场景**（YouTube、Netflix）：
- 优先：原生IP节点，带宽大的节点
- 要求：支持流媒体解锁

**国内网站**：
- 使用：DIRECT 直连
- 确保：DNS正确解析

#### 2. 规则优化技巧

**基本原则**：
1. 国内网站优先使用 DIRECT
2. AI和开发服务使用专用分组
3. 流媒体使用支持解锁的节点
4. 避免所有流量都走代理

**推荐配置** (mixin.yaml)：
```yaml
proxy-groups:
  - name: AI
    type: select
    proxies:
      - V1-美国01|流媒体|GPT
      - V1-新加坡01|流媒体|GPT
      - V1-日本01|流媒体|GPT
  
  - name: Development
    type: select
    proxies:
      - AUTO-SMART
      - V1-香港01
      - V1-新加坡01|流媒体|GPT
  
  - name: Streaming
    type: select
    proxies:
      - V1-美国01|流媒体|GPT
      - V1-新加坡01|流媒体|GPT

rules:
  # AI服务
  - DOMAIN-SUFFIX,openai.com,AI
  - DOMAIN-SUFFIX,anthropic.com,AI
  - DOMAIN-SUFFIX,claude.ai,AI
  
  # 开发服务
  - DOMAIN-SUFFIX,github.com,Development
  - DOMAIN-SUFFIX,npmjs.com,Development
  
  # 流媒体
  - DOMAIN-SUFFIX,youtube.com,Streaming
  - DOMAIN-SUFFIX,netflix.com,Streaming
  
  # 国内直连
  - DOMAIN-SUFFIX,baidu.com,DIRECT
  - DOMAIN-SUFFIX,taobao.com,DIRECT
  - GEOIP,CN,DIRECT
```

#### 3. 监控告警配置

**告警阈值建议**：
- 健康分数 < 60 → CRITICAL
- 成功率 < 50% → WARNING
- 延迟 > 1000ms → WARNING

**通知渠道建议**：
- 桌面通知：适合日常监控
- Webhook：适合团队协作（企业微信、钉钉）
- 邮件：适合严重问题通知

---

## 🔍 故障排查

### 常见问题

#### 1. 监控脚本无法运行

**症状**：执行脚本提示权限错误

**解决**：
```bash
cd /home/gw/opt/clash-for-linux-install/vpn-tools
chmod +x *.sh
```

#### 2. API 不可访问

**症状**：`curl: (7) Failed to connect to 127.0.0.1 port 9090`

**排查**：
```bash
# 检查服务状态
systemctl --user status mihomo

# 检查端口
ss -tlnp | grep 9090

# 重启服务
systemctl --user restart mihomo
```

#### 3. 告警未收到

**症状**：有异常但没有告警通知

**排查**：
```bash
# 测试告警系统
./alert_notification.sh --test

# 检查配置
cat ~/.local/share/clash/alert_config.conf

# 查看告警日志
tail -f ~/.local/share/clash/logs/health_alerts.log
```

#### 4. 定时任务未执行

**症状**：监控数据不更新

**排查**：
```bash
# 检查crontab
crontab -l | grep clash

# 查看cron日志
tail -f ~/.local/share/clash/logs/monitor_cron.log

# 手动运行测试
./network_health_monitor.sh --check-only
```

#### 5. 健康分数异常低

**症状**：分数持续低于60

**诊断流程**：
```bash
# 1. 运行详细检查
./network_connectivity_test.sh full

# 2. 检查当前节点
./quick_vpn_check.sh

# 3. 查看运行时配置
bash ../script/runtime_guard.sh --check --report

# 4. 尝试切换节点
./optimize_ai.sh

# 5. 运行时修复
bash ../script/runtime_guard.sh --auto-fix
```

### 日志文件位置

```
~/.local/share/clash/logs/
├── monitor_cron.log        # 定时监控日志
├── guard_cron.log          # 运行时守护日志
├── optimizer_cron.log      # 规则优化日志
├── health_alerts.log       # 告警日志
├── health_history.log      # 健康历史
├── auto_fix.log            # 自动修复日志
└── rule_analysis.log       # 规则分析日志
```

---

## ⚙️ 高级配置

### 自定义监控阈值

编辑 `network_health_monitor.sh`：

```bash
# 延迟阈值
LATENCY_WARN=500      # 延迟警告阈值(ms)
LATENCY_CRITICAL=1000 # 延迟严重阈值(ms)

# 失败率阈值
FAIL_RATE_WARN=20     # 失败率警告阈值(%)
FAIL_RATE_CRITICAL=40 # 失败率严重阈值(%)

# 最低健康分数
MIN_HEALTH_SCORE=60   # 低于此分数触发告警
```

### 自定义网站分类

编辑 `intelligent_rule_optimizer.sh`：

```bash
SITE_CATEGORIES=(
    ["my_custom"]="example.com,test.com"
)
```

### 集成企业微信/钉钉

编辑告警配置 `~/.local/share/clash/alert_config.conf`：

```bash
ENABLE_WEBHOOK=true

# 企业微信
WEBHOOK_URL="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=YOUR_KEY"

# 钉钉
WEBHOOK_URL="https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN"
```

### Prometheus 集成

现有的 metrics 文件已可用于 Prometheus：

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'clash-health'
    static_configs:
      - targets: ['localhost']
        labels:
          __metrics_path__: /home/gw/.local/share/clash/metrics/health_metrics.json
```

---

## 📊 性能基准

### 优秀健康状态

```
健康分数: 90-100
等级: A

AI服务:     成功率 ≥ 95% | 平均延迟 < 500ms
开发服务:   成功率 ≥ 95% | 平均延迟 < 500ms
流媒体服务: 成功率 ≥ 90% | 平均延迟 < 800ms
国内网站:   成功率 ≥ 98% | 平均延迟 < 200ms
```

### 正常健康状态

```
健康分数: 70-89
等级: B-C

AI服务:     成功率 ≥ 80% | 平均延迟 < 1000ms
开发服务:   成功率 ≥ 80% | 平均延迟 < 1000ms
流媒体服务: 成功率 ≥ 70% | 平均延迟 < 1500ms
国内网站:   成功率 ≥ 90% | 平均延迟 < 500ms
```

### 需要优化

```
健康分数: < 70
等级: D-F

任何服务成功率 < 70% 或 延迟 > 2000ms
建议立即运行优化和修复
```

---

## 🎓 总结

通过本系统，您可以：

✅ **自动监控**：每10分钟自动检查网络健康  
✅ **智能优化**：自动为不同类型网站选择最佳节点  
✅ **及时告警**：问题发生时立即通知  
✅ **自动修复**：检测到问题自动执行修复  
✅ **可视化**：直观的仪表盘展示网络状态  
✅ **历史分析**：学习历史数据持续优化  

**推荐使用流程**：

1. **初始化**：`./setup_monitoring_cron.sh --install`
2. **日常监控**：`./network_dashboard.sh --watch`
3. **定期优化**：每周运行一次 `intelligent_rule_optimizer.sh --analyze`
4. **问题处理**：查看告警，手动或自动修复

---

## 📞 支持

如有问题，请查看：
- 日志文件：`~/.local/share/clash/logs/`
- 告警历史：`./alert_notification.sh --history`
- 运行状态：`./setup_monitoring_cron.sh --status`

**祝您使用愉快！** 🎉
