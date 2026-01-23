# 🚀 一键优化快速参考

## 最新更新 (2025-10-13)

### ✅ 已完成的调整

#### 1. AI服务监控 🤖
```
移除：OpenAI API, Claude, Anthropic（地域限制）
新增：UIUI-API (sg.uiuiapi.com)        ← 您常用
新增：硅基流动 (api.siliconflow.cn)    ← 您常用
新增：Gemini (gemini.google.com)
保留：ChatGPT (chat.openai.com)
```

#### 2. 流媒体监控 📺
```
移除：Netflix（不常用）
新增：Google Meet（视频会议）
保留：YouTube, Zoom
```

#### 3. 一键优化全网络 🎯
```
新建：optimize_all_network.sh
功能：自动执行所有网络优化任务
位置：仪表盘 [7] 一键优化全网络
```

## 快速使用指南

## 🧯 紧急：一键切回直连（不走代理）

当 clash/mihomo 节点异常导致网络不可用时，直接运行：

```bash
bash ~/.local/share/clash/script/emergency_off.sh
```

如需在**不改网络**的情况下先看看它会做什么：

```bash
bash ~/.local/share/clash/script/emergency_off.sh --dry-run
```

如需更安全的“试运行”（到点自动回滚）：

```bash
bash ~/.local/share/clash/script/emergency_off.sh --trial 20
```

试运行 + 直连自检（推荐）：trial 默认会检查 baidu/bing/qq；不通就立刻回滚。

```bash
bash ~/.local/share/clash/script/emergency_off.sh --trial 20

# 额外加一个你关心的站点（默认检查 + 你指定的都会测）
bash ~/.local/share/clash/script/emergency_off.sh --trial 20 --require-url https://www.taobao.com
```

> 默认会**停止服务 + 卸载系统/Git 代理**，让系统恢复到“无代理直连”状态。
> 如果你只想停服务而不动代理设置（不推荐），可用：`bash ~/.local/share/clash/script/emergency_off.sh --no-unset-proxy`

> 若你当前终端仍残留 `http_proxy/all_proxy`，可选执行：
>
> `eval "$(bash ~/.local/share/clash/script/emergency_off.sh --print-unset)"`

### 方式1: 使用仪表盘（推荐）

```bash
cd /path/to/clash-for-linux-install/vpn-tools
./network_dashboard.sh

# 选择 [7] 一键优化全网络
```

### 方式2: 直接运行脚本

```bash
cd /path/to/clash-for-linux-install/vpn-tools
./optimize_all_network.sh
```

### 方式3: 单独优化某项

```bash
# 只优化AI服务
./optimize_ai.sh

# 只优化流媒体
./optimize_youtube_streaming.sh

# 只运行健康检查
./network_health_monitor.sh
```

## 一键优化执行流程

```
╔════════════════════════════════════════╗
║     🚀 一键优化全网络连接 🚀            ║
╚════════════════════════════════════════╝

步骤 1/5: 运行时环境修复
  → 检查Clash配置
  → 修复环境变量
  → 重启必要服务
  ⏱️ 约30秒

步骤 2/5: 优化AI服务连接
  → 测试所有AI节点
  → 选择最快节点
  → 切换并验证
  ⏱️ 约1-2分钟

步骤 3/5: 优化开发服务连接
  → 测试GitHub
  → 测试NPM
  → 测试PyPI
  ⏱️ 约30秒

步骤 4/5: 优化流媒体连接
  → 测试YouTube节点
  → 选择最优节点
  → 验证播放性能
  ⏱️ 约1分钟

步骤 5/5: 检查国内网站连接
  → 测试百度、淘宝
  → 测试B站、知乎
  → 确认直连正常
  ⏱️ 约20秒

最终检查：生成健康报告
  → 运行完整健康检查
  → 显示健康分数
  → 保存详细日志
  ⏱️ 约30秒

总耗时：约4-5分钟
```

## 测试结果示例

### 最新健康检查结果

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
检查时间：2025-10-13 00:04:27
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AI服务 (75% ✓)
  ✅ ChatGPT     308  (1396ms)
  ✅ UIUI-API    200  (2097ms)
  ❌ 硅基流动     404  (90ms)    ← 需要检查API地址
  ✅ Gemini      200  (2775ms)

开发服务 (75% ✓)
  ✅ GitHub      200  (1554ms)
  ✅ NPM         200  (1399ms)
  ✅ PyPI        200  (1517ms)
  ❌ Crates      403  (1161ms)

流媒体 (100% ✓)
  ✅ YouTube     200  (2223ms)
  ✅ Zoom        301  (1137ms)
  ✅ Google Meet 200  (1213ms)

国内网站 (100% ✓)
  ✅ 百度         200  (95ms)
  ✅ 淘宝         200  (137ms)
  ✅ B站          200  (113ms)
  ✅ 知乎         302  (158ms)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
总体健康分数: 65/100 (D - 较差)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

建议：运行一键优化降低延迟
```

## 仪表盘快捷键

```
════════════════════════════════════════════
           CLASH 网络监控仪表盘
════════════════════════════════════════════

[1] 运行健康检查        [2] 优化AI服务
[3] 优化流媒体          [4] 查看详细报告
[5] 重启Clash服务       [6] 运行时修复
[7] 一键优化全网络      [q] 退出
    ^^^^^^^^^^^^^^
    新增功能！

════════════════════════════════════════════
```

## 常见问题

### Q1: 硅基流动连接失败怎么办？

**A**: 可能API地址不正确，修改方法：

```bash
nano /path/to/clash-for-linux-install/vpn-tools/network_health_monitor.sh

# 找到第107行，修改为正确的API地址
"https://api.siliconflow.cn/v1/models|硅基流动"
```

### Q2: 一键优化需要多久？

**A**: 正常情况下4-5分钟，包括：
- 环境修复: 30秒
- AI优化: 1-2分钟
- 开发服务: 30秒
- 流媒体: 1分钟
- 国内网站: 20秒
- 最终检查: 30秒

### Q3: 可以自动定期优化吗？

**A**: 可以！添加到crontab：

```bash
crontab -e

# 每天早上8点自动优化
0 8 * * * /path/to/clash-for-linux-install/vpn-tools/optimize_all_network.sh
```

### Q4: 优化日志在哪里？

**A**: 日志文件位置：
```
~/.local/share/clash/logs/optimize_all_YYYYMMDD_HHMMSS.log
```

查看最新日志：
```bash
ls -lt ~/.local/share/clash/logs/optimize_all_*.log | head -1 | awk '{print $NF}' | xargs cat
```

### Q5: 为什么延迟还是很高？

**A**: 可能原因：
1. 当前节点负载高 → 运行一键优化切换节点
2. 网络拥堵 → 换个时间段再试
3. 目标服务器本身慢 → 无法优化

运行诊断：
```bash
./network_health_monitor.sh --report
```

## 监控系统架构

```
┌─────────────────────────────────────────────┐
│         用户界面层                           │
│  network_dashboard.sh (交互式仪表盘)         │
│  optimize_all_network.sh (一键优化)         │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│         核心监控层                           │
│  network_health_monitor.sh (健康检查)       │
│  intelligent_rule_optimizer.sh (规则优化)   │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│         专项优化层                           │
│  optimize_ai.sh (AI服务)                    │
│  optimize_youtube_streaming.sh (流媒体)     │
│  runtime_guard.sh (运行时修复)              │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│         通知与存储                           │
│  alert_notification.sh (多渠道告警)         │
│  health_metrics.json (指标存储)             │
│  health_history.log (历史记录)              │
└─────────────────────────────────────────────┘
```

## 文件清单

### 核心文件
```
/path/to/clash-for-linux-install/vpn-tools/
├── network_health_monitor.sh      (监控引擎) ✅ 已更新
├── network_dashboard.sh            (可视化界面) ✅ 已更新
├── optimize_all_network.sh         (一键优化) ✅ 新建
├── intelligent_rule_optimizer.sh   (规则优化)
├── alert_notification.sh           (告警通知)
└── setup_monitoring_cron.sh        (定时任务)
```

### 配置文件
```
~/.local/share/clash/
├── metrics/health_metrics.json     (实时指标)
├── logs/health_history.log         (历史日志)
├── logs/health_alerts.log          (告警日志)
└── logs/optimize_all_*.log         (优化日志)
```

### 文档文件
```
/path/to/clash-for-linux-install/
├── UPDATE_NOTES.md                 (本次更新说明) ✅ 新建
├── BUG_FIX_REPORT.md               (bug修复报告)
├── NETWORK_OPTIMIZATION_GUIDE.md   (优化指南)
└── vpn-tools/MONITORING_README.md  (监控文档)
```

## 下一步操作

### 立即执行
1. ✅ 测试新的健康检查：`./network_health_monitor.sh`
2. ✅ 查看仪表盘：`./network_dashboard.sh`
3. 🎯 运行一键优化：选择选项 [7]

### 可选配置
1. 修正硅基流动API地址（如果您知道正确地址）
2. 安装定时监控：`./setup_monitoring_cron.sh`
3. 配置告警通知：编辑 `alert_notification.sh`

### 性能监控
1. 定期查看健康分数变化
2. 关注告警日志
3. 每周运行一次规则优化

## 支持命令

```bash
# 查看当前健康状态
./network_health_monitor.sh

# 生成详细报告
./network_health_monitor.sh --report

# 打开仪表盘
./network_dashboard.sh

# Watch模式（自动刷新）
./network_dashboard.sh --watch

# 一键优化全网络
./optimize_all_network.sh

# 查看最新优化日志
ls -lt ~/.local/share/clash/logs/optimize_all_*.log | head -1
```

---

**更新完成** ✅ 立即体验新功能！

```bash
cd /path/to/clash-for-linux-install/vpn-tools
./network_dashboard.sh
# 然后按 7
```
