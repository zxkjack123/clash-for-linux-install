# VSCode Copilot 断开连接问题 - 诊断与解决方案

## 诊断时间
2025-10-14 15:50:00

## 问题分析

### 1. 核心问题
- **症状**: VSCode Copilot 频繁断开连接，提示网络问题
- **根本原因**: GitHub Copilot API (api.githubcopilot.com) SSL 握手不稳定
- **表现**: 
  - SSL_ERROR_SYSCALL 连接错误
  - 响应时间不稳定 (1-6秒)
  - 部分请求超时

### 2. 当前网络状态
- ✅ Clash 服务运行正常 (mihomo v1.19.2)
- ✅ 代理端口监听: 7890 (HTTP/SOCKS5)
- ✅ 代理环境变量正确配置
- ⚠️  网络健康分数: 65/100 (等级 D - 较差)
- ⚠️  AI 节点连接不稳定

### 3. 已完成的优化
- ✅ 已选择最佳 AI 节点: `V1-新加坡01|流媒体|GPT`
- ✅ GitHub 相关域名已配置使用"西瓜加速"组
- ✅ 网络全面优化已执行

## 解决方案

### 方案 1: 重启 VSCode (推荐，最简单)
```bash
# 完全退出 VSCode (File > Exit 或 Ctrl+Q)
# 等待 5 秒
# 重新启动 VSCode
```

**原因**: VSCode 进程保留了旧的网络连接状态，重启后会使用新的优化配置。

### 方案 2: 使用修复脚本重启 VSCode
```bash
cd /home/gw/opt/clash-for-linux-install/vpn-tools
bash fix_vscode_stale_proxy.sh --launch-here
```

这会：
- 检测陈旧的代理配置
- 启动一个干净的 VSCode 窗口，使用正确的代理设置

### 方案 3: 手动优化 Copilot 连接
```bash
# 1. 运行优化脚本
cd /home/gw/opt/clash-for-linux-install/vpn-tools
bash optimize_vscode_copilot.sh

# 2. 测试连接
curl -I --max-time 10 https://api.githubcopilot.com/healthz

# 3. 如果成功 (HTTP 404 是正常的)，重启 VSCode
```

### 方案 4: 切换到更稳定的节点 (如果方案 1-3 无效)
```bash
# 手动测试其他美国节点
cd /home/gw/opt/clash-for-linux-install/vpn-tools
bash optimize_ai_enhanced.sh

# 或者尝试美国节点
curl -X PUT -H "Content-Type: application/json" \
  -d '{"name": "V1-美国10|流媒体|GPT"}' \
  http://127.0.0.1:9090/proxies/西瓜加速
```

### 方案 5: 调整网络超时设置 (高级)
在 VSCode 设置中添加：
```json
{
    "http.proxyStrictSSL": false,
    "http.timeout": 30000,
    "github.copilot.advanced": {
        "timeout": 30000
    }
}
```

## 预防措施

### 1. 定期优化网络
```bash
# 添加到 crontab (每2小时优化一次)
0 */2 * * * /home/gw/opt/clash-for-linux-install/vpn-tools/optimize_ai.sh
```

### 2. 监控网络健康
```bash
# 查看实时网络状态
cd /home/gw/opt/clash-for-linux-install/vpn-tools
bash network_dashboard.sh
```

### 3. 快速诊断命令
```bash
# 创建一个快速诊断别名
alias copilot-check='curl -s -w "状态:%{http_code} 时间:%{time_total}s SSL:%{ssl_verify_result}\n" -o /dev/null --max-time 10 https://api.githubcopilot.com/healthz'

# 使用
copilot-check
```

## 常见问题

### Q1: 为什么 Copilot API 返回 404？
**A**: 404 是**正常的**！这个 endpoint 存在但需要认证，404 表示 SSL 连接成功，API 可访问。

### Q2: 如何判断连接是否正常？
**A**: 
- ✅ 正常: HTTP 404, 响应时间 < 5秒, SSL:0 (成功)
- ❌ 异常: 超时, SSL_ERROR, 响应时间 > 8秒

### Q3: 代理配置正确但仍然断开？
**A**: 尝试：
1. 完全退出 VSCode (不是关闭窗口，而是 File > Exit)
2. 清除 VSCode 的网络缓存：删除 `~/.config/Code/Cache` 和 `~/.config/Code/CachedData`
3. 重启 VSCode

### Q4: 节点经常变化怎么办？
**A**: 可以锁定特定节点：
```bash
# 编辑 ~/.local/share/clash/runtime.yaml
# 将 "西瓜加速" 的 type 从 "url-test" 改为固定节点
```

## 快速命令参考

```bash
# 检查 Clash 状态
curl -s http://127.0.0.1:9090/version

# 查看当前节点
curl -s http://127.0.0.1:9090/proxies | jq '.proxies."西瓜加速".now'

# 测试 Copilot 连接
curl -I --max-time 10 https://api.githubcopilot.com/healthz

# 优化 AI 节点
cd /home/gw/opt/clash-for-linux-install/vpn-tools && bash optimize_ai.sh

# 优化 VSCode Copilot
cd /home/gw/opt/clash-for-linux-install/vpn-tools && bash optimize_vscode_copilot.sh

# 全网络优化
cd /home/gw/opt/clash-for-linux-install/vpn-tools && bash optimize_all_network.sh
```

## 推荐操作顺序

**立即执行** (3分钟内解决):
1. 完全退出 VSCode (File > Exit)
2. 等待 5 秒
3. 重新启动 VSCode
4. 测试 Copilot 是否正常工作

**如果仍有问题** (10分钟内解决):
1. 运行: `bash /home/gw/opt/clash-for-linux-install/vpn-tools/optimize_vscode_copilot.sh`
2. 使用: `bash /home/gw/opt/clash-for-linux-install/vpn-tools/fix_vscode_stale_proxy.sh --launch-here`

**长期维护**:
- 设置定时任务优化网络
- 使用 network_dashboard.sh 监控状态
- 遇到问题时查看此文档

## 技术细节

### 连接流程
```
VSCode → http://127.0.0.1:7890 (Clash) → 西瓜加速节点 → api.githubcopilot.com
```

### 关键配置文件
- Clash 配置: `/home/gw/opt/clash-for-linux-install/resources/config.yaml`
- Clash 运行时: `/home/gw/.local/share/clash/runtime.yaml`
- 代理环境变量: `/etc/profile.d/clash.sh` 或 `~/.bashrc`

### 诊断日志位置
- Clash 日志: `/home/gw/.local/share/clash/logs/`
- 优化日志: `/home/gw/.local/share/clash/logs/optimize_*.log`

---

**最后更新**: 2025-10-14 15:50:00  
**问题状态**: 🟡 部分解决 - 需要重启 VSCode  
**预计恢复时间**: < 5 分钟
