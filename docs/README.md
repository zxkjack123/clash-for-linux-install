# 📚 文档目录

本目录包含 Clash for Linux 的所有详细文档，按功能分类整理。

## 📖 文档结构

```
docs/
├── installation/    # 安装和配置文档
├── network/         # 网络优化文档
├── integrations/    # 功能集成文档
└── development/     # 开发和调试文档
```

## 🚀 快速导航

### 安装和配置 (installation/)

- **[用户安装指南](installation/USER_INSTALL_GUIDE.md)** - 完整的安装步骤和说明
- **[环境配置指南](installation/ENV_CONFIG_GUIDE.md)** - 环境变量和配置管理
- **[安全配置](installation/SECURITY.md)** - API密钥管理和安全最佳实践
- **[自动订阅刷新](installation/AUTO_SUBSCRIPTION_REFRESH.md)** - 使用 systemd 定时任务定期刷新 Clash 订阅

### 网络优化 (network/)

- **[网络优化指南](network/NETWORK_OPTIMIZATION_GUIDE.md)** - 全面的网络优化方案和工具
- **[网络系统审查](network/NETWORK_SYSTEM_REVIEW.md)** - 系统级网络配置审查

### 功能集成 (integrations/)

- **[Docker 集成](integrations/DOCKER_INTEGRATION.md)** - Docker 容器代理配置
- **[AI 服务配置](integrations/AI_SERVICES_FINAL.md)** - OpenAI、Claude 等 AI 服务配置
- **[AI 服务更新](integrations/AI_SERVICES_UPDATE.md)** - AI 服务的最新更新和优化
- **[VSCode Copilot 修复](integrations/VSCODE_COPILOT_FIX.md)** - GitHub Copilot 连接问题诊断和解决
- **[科研/学术分流模板](integrations/RESEARCH_ACADEMIC_PROFILE.md)** - Copilot / Docker / Scholar / 期刊站点的最小分流模板

### 开发和调试 (development/)

- **[Bug 修复报告](development/BUG_FIX_REPORT.md)** - 已知问题和修复记录
- **[服务修复技术](development/SERVICE_FIX_TECHNICAL.md)** - 技术性故障排查和修复
- **[静态门禁（Static Gates）](development/STATIC_GATES.md)** - 提交前的脚本可靠性静态检查（curl 超时 / errexit 算术陷阱 / JSON stdout 纯度）
- **[SiliconFlow 修复](development/SILICONFLOW_FIX.md)** - SiliconFlow API 连接问题修复
- **[个人节点部署指南](development/JP_PERSONAL_PROXY_NODE.md)** - 将阿里云日本服务器构建为专用代理出口
- **[完成报告](development/COMPLETION_REPORT.md)** - 项目里程碑和完成情况
- **[更新说明](development/UPDATE_NOTES.md)** - 详细的更新记录和变更说明

## 🔗 相关链接

- **[主 README](../README.md)** - 项目概述和主要功能
- **[快速开始](../QUICK_START.md)** - 5分钟快速上手指南
- **[变更日志](../CHANGELOG.md)** - 版本历史和更新日志
- **[VPN 工具文档](../vpn-tools/README.md)** - VPN 工具集详细说明

## 📝 文档更新

如果你发现文档有错误或需要改进，欢迎提交 PR 或创建 Issue。

---

**最后更新**: 2026-03-02  
**版本**: v2.5.10
