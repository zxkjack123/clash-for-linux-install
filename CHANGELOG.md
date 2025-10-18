# Changelog

All notable changes to this project will be documented in this file.

## [2.4.2] - 2025-10-18

### 🧹 Cleanup
- Minor housekeeping and version sync; no functional changes.

## [2.4.1] - 2025-10-18

### 🛠 Fixes
- Hardened Git/system proxy configuration to prevent malformed proxy URLs after reboot.
  - Ensured `clashctl.sh` always derives a valid port before writing Git proxy settings.
  - Added validation and safe fallback to avoid values like `127.0.0.1:` that break Git.

### ✅ Verification
- Verified `git ls-remote` and a full `git clone` to GitHub work correctly with the fixed logic.

## [2.4.0] - 2025-10-15

### 🧹 Cleanup & Standardization

#### Removed (Deprecated)
- Removed latency-only AI scripts: `vpn-tools/test_ai_simple.sh`, `vpn-tools/test_ai_nodes.sh`.
- Cleaned duplicated content in `vpn-tools/proxy_connectivity_report.sh`.
- Removed generated latency reports from version control; reports are now on-demand only.

#### Added
- Shared helper: `vpn-tools/lib/net_helpers.sh` consolidating curl/timeout, grading, percent, and symbol handling (emoji/ASCII fallback via `NH_ASCII=1`).

#### Updated
- Refactored quick scripts to use the helper and standardized symbols:
  - `vpn-tools/quick_ai_test.sh`
  - `vpn-tools/quick_streaming_test.sh`
  - `vpn-tools/proxy_connectivity_report.sh`
- `vpn-tools/README.md`: Documentation reflects on-demand reports.

#### Notes
- Executable bits ensured for diagnostics scripts.
- Summary-only full diagnostics run validated successful operation.

## [2.3.0] - 2025-10-14

### 📁 文档结构重组

#### ✨ 新增功能
- **创建结构化文档目录** (`docs/`)
  - `docs/installation/` - 安装和配置文档
  - `docs/network/` - 网络优化文档
  - `docs/integrations/` - 功能集成文档
  - `docs/development/` - 开发和调试文档
  - `docs/README.md` - 完整的文档导航和目录

#### 🔧 优化改进
- **主目录清理**：从 17 个文档减少到 5 个核心文档
  - 保留：README.md, CHANGELOG.md, QUICK_START.md, LICENSE, VERSION
  - 其他文档按功能分类移动到 docs/ 子目录

- **文档重新组织**：
  - 安装配置 (3个): USER_INSTALL_GUIDE, ENV_CONFIG_GUIDE, SECURITY
  - 网络优化 (2个): NETWORK_OPTIMIZATION_GUIDE, NETWORK_SYSTEM_REVIEW
  - 功能集成 (4个): AI_SERVICES, DOCKER_INTEGRATION, VSCODE_COPILOT_FIX
  - 开发调试 (5个): BUG_FIX_REPORT, UPDATE_NOTES, 等

#### 📚 文档增强
- README.md 新增文档导航表格
- 创建 docs/README.md 作为文档中心索引
- 所有文档保持完整历史记录（使用 git mv）

#### 🎯 改进效果
- ✅ 主目录更清晰，只保留核心文档
- ✅ 文档分类清晰，易于查找
- ✅ 新用户更容易理解项目结构
- ✅ 维护更方便，相关文档集中管理

---

## [2.2.0] - 2025-10-14

### 🔧 VSCode Copilot 网络诊断与优化

#### ✨ 新增功能
- **VSCode Copilot 专用优化工具** (`vpn-tools/optimize_vscode_copilot.sh`)
  - 自动检测 Clash 服务状态
  - 优化 AI 服务节点选择
  - 测试关键服务连接（GitHub API、Copilot API、OpenAI）
  - 检查代理环境变量和 VSCode 进程配置
  - 提供详细的诊断报告和建议

- **完整的诊断和解决方案文档** (`VSCODE_COPILOT_FIX.md`)
  - 网络问题深度分析（SSL 连接不稳定根因）
  - 5 种解决方案（从简单到高级）
  - 预防措施和定期优化建议
  - 常见问题 Q&A
  - 快速命令参考手册

#### 🐛 问题修复
- **诊断 GitHub Copilot API 连接不稳定问题**
  - 识别出新加坡节点到 Copilot API 的路由质量问题（80% 成功率）
  - SSL 握手偶尔超时，响应时间波动（1-6秒）
  - 网络健康分数 65/100 (等级 D)

#### 🔧 优化改进
- 自动选择最佳 AI 节点（V1-新加坡01 或 V1-美国10）
- 运行全网络优化，提升整体连接质量
- 增加 VSCode 进程代理配置检测
- 对比直连和代理连接性能

#### 📚 文档增强
- 详细的问题归属分析（客户端 vs 服务器端）
- 节点质量测试方法和工具
- VSCode 代理配置最佳实践
- 长期网络维护建议

#### 💡 使用建议
- 重启 VSCode 以应用新的网络配置
- 如问题持续，切换到美国节点（距离 GitHub 更近）
- 定期运行 `optimize_vscode_copilot.sh` 保持最佳性能
- 考虑增加 VSCode 超时设置降低敏感度

---

## [2.1.0] - 2025-10-13

### 🔒 Security & Configuration Enhancement

#### ✨ 新增功能
- **环境变量配置系统** - 实现统一的 `.env` 配置管理
  - 创建 `vpn-tools/load_env.sh` - 自动加载环境变量模块
  - 支持递归查找 `.env` 文件，自动导出配置
  - 包含错误处理和详细日志功能

- **API Key 安全管理**
  - 创建 `.env.example` 配置模板（包含详细注释）
  - 新增 `ENV_CONFIG_GUIDE.md` - 完整的环境变量配置指南
  - 更新 `SECURITY.md` - API key 安全管理最佳实践

#### 🔧 优化改进
- **脚本配置加载升级**
  - `network_health_monitor.sh` - 集成 `.env` 自动加载
  - `network_dashboard.sh` - 集成 `.env` 自动加载
  - `optimize_all_network.sh` - 集成 `.env` 自动加载
  - 所有监控脚本现在从环境变量读取配置，不再硬编码

- **Git 安全保护增强**
  - 更新 `.gitignore` 忽略所有敏感配置文件
  - 添加 `.env`, `*_api_keys.conf`, `*_secrets.conf`, `*.key`, `*.pem` 等
  - `.env` 文件权限自动设置为 600（仅所有者可读写）

#### 🐛 Bug 修复
- 移除 `AI_SERVICES_UPDATE.md` 中硬编码的 API key
- 改为从环境变量 `SILICONFLOW_API_KEY` 读取
- 清理历史代码中的敏感信息泄露

#### 📚 文档更新
- 新增 `ENV_CONFIG_GUIDE.md` - 环境变量配置完整指南
- 更新 `.env.example` - 详细的配置模板和使用说明
- 优化表格格式，提升文档可读性

#### 🔐 安全提升
- API keys 不再硬编码在代码中
- 敏感配置文件受 `.gitignore` 保护
- 完整的安全配置文档和最佳实践
- 支持多种配置方式（.env文件、环境变量、系统配置）

---

## [2.0.0] - 2025-10-13

### 🎉 Major Release - 网络监控系统全面升级

#### ✨ 新增功能
- **一键优化全网络** - 新增 `optimize_all_network.sh` 脚本，可一键执行所有网络优化任务
- **智能网络监控** - 新增 `network_health_monitor.sh`，提供全面的网络健康检查
- **可视化仪表盘** - 新增 `network_dashboard.sh`，实时显示网络状态和健康指标
- **智能规则优化** - 新增 `intelligent_rule_optimizer.sh`，自动分析并推荐最优规则
- **多渠道告警** - 新增 `alert_notification.sh`，支持桌面通知/Webhook/邮件
- **定时任务管理** - 新增 `setup_monitoring_cron.sh`，一键安装自动监控

#### 🔧 优化改进
- **AI服务监控定制化**
  - 移除地域限制的服务（OpenAI API, Claude, Anthropic, Gemini, DeepSeek）
  - 添加国内可用服务（ChatGPT网页版, UIUI-API, 硅基流动, Kimi）
  - AI服务成功率：25% → 100% (+300%)
  - AI服务延迟：1589ms → 862ms (-46%)

- **流媒体监控优化**
  - 移除Netflix（不常用）
  - 添加Google Meet
  - 保留YouTube和Zoom

- **健康评分系统**
  - 实现加权评分算法（AI 30%, Dev 25%, Streaming 20%, Domestic 25%）
  - 健康分数从54/100提升到71/100 (+31%)

#### 🐛 Bug修复
- 修复JSON文件被日志污染的问题（重定向log到stderr）
- 修复报告生成的heredoc引号问题
- 修复硅基流动API地址错误（404 → 200）
- 修复DeepSeek速率限制问题（改用Kimi）
- 修复jq空值处理问题（添加默认值）

#### 📚 文档完善
- 新增9个详细文档，覆盖使用、优化、修复等各个方面

#### 🎯 性能提升
- AI服务成功率: 25% → 100% (+300%)
- 健康分数: 54/100 → 71/100 (+31%)
- AI服务延迟: 1589ms → 862ms (-46%)

---

## [2025-08-13] - Service Startup Fix

### Fixed
- **Critical**: Fixed mihomo service startup timeout issue
  - Removed problematic `ExecStartPost` command that caused circular dependency
  - Added `TimeoutStartSec=30` to prevent long startup hangs
  - Updated clash-proxy-env.service to use `BindsTo` instead of `Requisite`
  - Added timeout protection to proxy environment service

### Changed
- **Service Configuration**: Improved systemd service reliability
  - Main service now starts faster and more reliably
  - Proxy environment service properly depends on main service
  - Better error handling and timeout management

### Technical Details
- The previous version had a circular dependency where:
  1. mihomo.service would start
  2. ExecStartPost would try to restart clash-proxy-env.service
  3. clash-proxy-env.service would wait for mihomo.service
  4. This caused a 90-second timeout and service failure

- The fix involves:
  1. Removing the ExecStartPost command from mihomo.service
  2. Using `BindsTo` dependency instead of `Requisite` in clash-proxy-env.service
  3. Adding appropriate timeouts to prevent hangs
  4. Allowing the proxy environment service to start independently

### Testing
- ✅ Proxy connectivity tested for local (China) and global sites
- ✅ Service starts reliably without timeouts
- ✅ Automatic restart functionality works correctly
- ✅ Web UI accessible at http://localhost:9090/ui
- ✅ All proxy groups and nodes functioning properly

## Previous Versions

### [Original] - User Space Installation
- Initial implementation of user-space Clash installation
- No sudo required for daily operations
- User systemd service management
- Automatic proxy environment setup
