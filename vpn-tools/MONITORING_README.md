# 🌐 网络监控与优化系统

> 为 Clash 代理服务打造的智能网络监控、优化和告警系统

## 📦 新增工具

### 核心工具

| 工具                            | 功能                   | 使用频率       |
| ------------------------------- | ---------------------- | -------------- |
| `network_health_monitor.sh`     | 网络健康监控与自动修复 | ⏰ 每10分钟自动 |
| `intelligent_rule_optimizer.sh` | 智能规则优化器         | 📅 每周手动     |
| `alert_notification.sh`         | 多渠道告警通知         | 🔔 自动触发     |
| `setup_monitoring_cron.sh`      | 定时任务管理           | 🔧 初始化一次   |
| `network_dashboard.sh`          | 可视化监控仪表盘       | 📊 随时查看     |
| `quick_start_monitoring.sh`     | 快速启动向导           | 🚀 首次使用     |

## 🚀 快速开始

```bash
cd /path/to/clash-for-linux-install/vpn-tools

# 一键启动监控系统
./quick_start_monitoring.sh

# 或手动执行以下步骤：

# 1. 初始化系统
./setup_monitoring_cron.sh --setup

# 2. 运行健康检查
./network_health_monitor.sh

# 3. 安装定时监控
./setup_monitoring_cron.sh --install

# 4. 查看仪表盘
./network_dashboard.sh
```

## ✨ 核心功能

### 1️⃣ 实时健康监控

自动监控四大类服务：
- 🤖 **AI服务**：ChatGPT、SCNET、UIUI-API、硅基流动、OpenRouter、Kimi
- 💻 **开发服务**：GitHub、NPM、PyPI
- 🎬 **流媒体**：YouTube、Zoom、Google Meet
- 🏠 **国内网站**：百度、淘宝、B站

**监控指标**：
- ✅ 成功率（可用性）
- ⏱️ 平均延迟
- 📊 健康分数（0-100）
- 🏆 健康等级（A/B/C/D/F）

### 2️⃣ 智能规则优化

- 🔍 测试不同节点访问各类网站的性能
- 🎯 自动为每类网站推荐最佳节点
- 📚 学习历史数据持续优化
- 📝 生成优化后的配置建议

### 3️⃣ 多渠道告警

- 🖥️ 桌面通知（notify-send）
- 📋 日志文件
- 🔗 Webhook（企业微信、钉钉）
- 📧 邮件（可选）

**智能去重**：相同告警5分钟内只通知一次

### 4️⃣ 自动修复

检测到问题时自动触发修复：
- AI服务异常 → 执行 AI 优化
- 流媒体异常 → 执行节点优化
- 配置异常 → 执行运行时修复
- 服务停止 → 尝试重启服务

### 5️⃣ 可视化仪表盘

实时显示：
- 📈 系统概览
- 💚 健康状态
- 📊 服务详情
- ⚠️ 最近告警
- 📉 性能趋势

## 📋 使用场景

### 场景1: 日常监控

```bash
# 查看实时状态
./network_dashboard.sh --watch

# 查看告警历史
./alert_notification.sh --history
```

### 场景2: 遇到问题

```bash
# 快速诊断
./network_health_monitor.sh

# 详细检查
./network_connectivity_test.sh full

# 运行时修复
bash ../script/runtime_guard.sh --auto-fix
```

### 场景3: 性能优化

```bash
# AI工作优化
./optimize_ai.sh

# 流媒体优化
./select_youtube_node.sh

# 全面规则分析
./intelligent_rule_optimizer.sh --analyze
./intelligent_rule_optimizer.sh --optimize
```

## ⏰ 自动化任务

安装监控系统后，以下任务将自动运行：

| 频率        | 任务         | 说明               |
| ----------- | ------------ | ------------------ |
| 每10分钟    | 网络健康检查 | 自动监控并修复问题 |
| 每10分钟    | 运行时守护   | 确保配置完整性     |
| 每小时      | 健康快照     | 记录性能数据       |
| 每天03:00   | 规则学习     | 从历史数据学习     |
| 每周日04:00 | 全面分析     | 深度性能分析       |
| 每天02:00   | 日志清理     | 保留30天日志       |

## 📊 性能基准

### 优秀状态（A级，90-100分）
```
AI服务:     ✅ 成功率 ≥ 95% | ⏱️ 延迟 < 500ms
开发服务:   ✅ 成功率 ≥ 95% | ⏱️ 延迟 < 500ms
流媒体服务: ✅ 成功率 ≥ 90% | ⏱️ 延迟 < 800ms
国内网站:   ✅ 成功率 ≥ 98% | ⏱️ 延迟 < 200ms
```

### 良好状态（B-C级，70-89分）
```
AI服务:     ✅ 成功率 ≥ 80% | ⏱️ 延迟 < 1000ms
开发服务:   ✅ 成功率 ≥ 80% | ⏱️ 延迟 < 1000ms
流媒体服务: ✅ 成功率 ≥ 70% | ⏱️ 延迟 < 1500ms
国内网站:   ✅ 成功率 ≥ 90% | ⏱️ 延迟 < 500ms
```

### 需要优化（D-F级，< 70分）
```
❌ 任何服务成功率 < 70%
❌ 任何服务延迟 > 2000ms
💡 建议：立即运行优化和修复
```

## 📁 文件结构

```
vpn-tools/
├── network_health_monitor.sh      # 网络健康监控
├── intelligent_rule_optimizer.sh  # 智能规则优化
├── alert_notification.sh          # 告警通知系统
├── setup_monitoring_cron.sh       # 定时任务管理
├── network_dashboard.sh           # 可视化仪表盘
├── quick_start_monitoring.sh      # 快速启动向导
└── ... (其他现有工具)

~/.local/share/clash/
├── logs/                          # 日志目录
│   ├── monitor_cron.log           # 监控日志
│   ├── guard_cron.log             # 守护日志
│   ├── health_alerts.log          # 告警日志
│   └── health_history.log         # 历史记录
├── metrics/                       # 指标目录
│   └── health_metrics.json        # 健康指标
├── alert_config.conf              # 告警配置
└── rules_optimization.db          # 规则优化数据库
```

## 🔧 配置

### 告警配置

编辑 `~/.local/share/clash/alert_config.conf`：

```bash
# 桌面通知
ENABLE_DESKTOP_NOTIFICATION=true

# Webhook (企业微信/钉钉)
ENABLE_WEBHOOK=true
WEBHOOK_URL="https://your-webhook-url.com/alert"

# 邮件通知
ENABLE_EMAIL=true
EMAIL_TO="admin@example.com"

# 频率限制（秒）
RATE_LIMIT_SECONDS=300
```

### 监控阈值

在 `network_health_monitor.sh` 中自定义：

```bash
LATENCY_WARN=500          # 延迟警告阈值(ms)
LATENCY_CRITICAL=1000     # 延迟严重阈值(ms)
FAIL_RATE_WARN=20         # 失败率警告阈值(%)
MIN_HEALTH_SCORE=60       # 最低健康分数
```

## 🆘 故障排查

### 问题：监控脚本无法运行
```bash
# 设置可执行权限
chmod +x *.sh
```

### 问题：API 不可访问
```bash
# 检查服务
systemctl --user status mihomo

# 重启服务
systemctl --user restart mihomo
```

### 问题：定时任务未执行
```bash
# 检查 crontab
crontab -l | grep clash

# 查看日志
tail -f ~/.local/share/clash/logs/monitor_cron.log
```

### 问题：健康分数异常低
```bash
# 全面诊断
./network_connectivity_test.sh full

# 运行修复
./network_health_monitor.sh

# 运行时修复
bash ../script/runtime_guard.sh --auto-fix
```

## 📚 完整文档

详细使用指南请查看：
```bash
cat /path/to/clash-for-linux-install/docs/network/NETWORK_OPTIMIZATION_GUIDE.md
```

## 🎯 最佳实践

### 每天
- 🌅 早上查看仪表盘，了解昨晚的网络状态
- 🔍 工作前根据需要运行专项优化

### 每周
- 📊 查看性能趋势
- 🔧 运行智能规则分析和优化

### 每月
- 💾 备份配置文件
- 🧹 检查日志大小
- 📈 评估优化效果

## 🎉 特点

✅ **零配置启动**：一键安装，自动运行  
✅ **智能监控**：自动检测问题并修复  
✅ **可视化**：直观的仪表盘展示  
✅ **多渠道告警**：桌面、Webhook、邮件  
✅ **持续优化**：学习历史数据不断改进  
✅ **轻量级**：最小资源占用  

## 📞 支持

遇到问题？

1. 查看日志：`~/.local/share/clash/logs/`
2. 运行测试：`./setup_monitoring_cron.sh --test`
3. 查看状态：`./setup_monitoring_cron.sh --status`
4. 阅读文档：`NETWORK_OPTIMIZATION_GUIDE.md`

---

**让网络更稳定，让速度更快！** 🚀
