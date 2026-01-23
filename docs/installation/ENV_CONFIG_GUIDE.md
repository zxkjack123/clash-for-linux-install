# 环境变量配置指南

## 📖 快速开始

### 1. 创建 `.env` 文件

```bash
# 复制模板文件
cp .env.example .env

# 编辑配置文件
vim .env
```

### 2. 配置 API Keys

在 `.env` 文件中填入你的 API keys：

```bash
# 硅基流动 API Key (可选)
SILICONFLOW_API_KEY="sk-xxxxxxxxxxxxxxxx"
```

### 3. 验证配置

```bash
# 测试环境变量加载
source vpn-tools/load_env.sh
echo "API Key: ${SILICONFLOW_API_KEY:0:20}..."

# 测试监控脚本
./vpn-tools/network_health_monitor.sh
```

---

## 🔧 配置项说明

### API Keys

| 配置项                | 说明              | 是否必需 | 获取地址                                |
| --------------------- | ----------------- | -------- | --------------------------------------- |
| `SILICONFLOW_API_KEY` | 硅基流动 API 密钥 | 可选     | https://cloud.siliconflow.cn/account/ak |
| `UIUI_API_KEY`        | UIUI API 密钥     | 可选     | https://sg.uiuiapi.com                  |

**注意**: 
- 这些 API keys 仅用于测试服务连接性
- 如果不配置，监控脚本仍可正常运行，只是无法测试需要认证的 API 端点

### Clash 配置

| 配置项         | 默认值                  | 说明                                                                                                                       |
| -------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `CLASH_API`    | `http://127.0.0.1:9090` | Controller API 地址（多数脚本会从 `~/.local/share/clash/runtime.yaml` 自动探测 `external-controller`；仅在需要覆盖时设置） |
| `CLASH_SECRET` | (空)                    | Controller Secret / API 认证密钥（多数脚本会从 `runtime.yaml` 自动读取；仅在需要覆盖时设置）                               |
| `PROXY`        | `http://127.0.0.1:7890` | HTTP 代理地址                                                                                                              |

> 兼容说明：旧版本文档/脚本可能使用 `API_SECRET` 或 `CLASH_API_SECRET`，当前推荐统一使用 `CLASH_SECRET`。

### 通知配置

| 配置项          | 说明                               |
| --------------- | ---------------------------------- |
| `WEBHOOK_URL`   | Webhook 通知地址（网络异常时发送） |
| `EMAIL_TO`      | 告警邮件接收地址                   |
| `EMAIL_FROM`    | 告警邮件发件地址                   |
| `SMTP_SERVER`   | SMTP 服务器地址                    |
| `SMTP_PORT`     | SMTP 服务器端口                    |
| `SMTP_USER`     | SMTP 用户名                        |
| `SMTP_PASSWORD` | SMTP 密码                          |

---

## 🔒 安全最佳实践

### ✅ 正确做法

1. **使用 `.env` 文件存储密钥**
   ```bash
   # .env 文件
   SILICONFLOW_API_KEY="sk-xxxxxxxx"
   ```

2. **设置正确的文件权限**
   ```bash
   chmod 600 .env  # 仅所有者可读写
   ```

3. **确认 `.env` 被 .gitignore 忽略**
   ```bash
   git check-ignore -v .env
   # 输出: .gitignore:24:.env    .env
   ```

### ❌ 错误做法

1. ~~直接在脚本中硬编码 API key~~
   ```bash
   # ❌ 错误示例
   api_key="sk-xxxxxxxx"
   ```

2. ~~提交 `.env` 文件到 Git~~
   ```bash
   # ❌ 绝对不要这样做
   git add .env
   git commit -m "add config"
   ```

3. ~~在公开场合分享包含密钥的配置~~

---

## 📁 文件结构

```
clash-for-linux-install/
├── .env                    # 你的私密配置 (不会被提交)
├── .env.example            # 配置模板 (提交到 Git)
├── .gitignore              # 包含 .env 忽略规则
├── SECURITY.md             # 安全配置详细指南
├── ENV_CONFIG_GUIDE.md     # 本文档
└── vpn-tools/
    ├── load_env.sh         # 环境变量加载脚本
    ├── network_health_monitor.sh
    ├── network_dashboard.sh
    └── optimize_all_network.sh
```

---

## 🛠️ 高级用法

### 方法 1: 使用 `.env` 文件 (推荐)

```bash
# 1. 创建 .env 文件
cat > .env <<'EOF'
SILICONFLOW_API_KEY="sk-xxxxxxxxxxxxxxxx"
CLASH_API="http://127.0.0.1:9090"
EOF

# 2. 脚本自动加载
./vpn-tools/network_health_monitor.sh
```

### 方法 2: 使用环境变量

```bash
# 临时设置 (仅当前会话)
export SILICONFLOW_API_KEY="sk-xxxxxxxx"
./vpn-tools/network_health_monitor.sh

# 永久设置 (添加到 ~/.bashrc)
echo 'export SILICONFLOW_API_KEY="sk-xxxxxxxx"' >> ~/.bashrc
source ~/.bashrc
```

### 方法 3: 使用系统配置文件

```bash
# 创建系统配置目录
mkdir -p ~/.config/clash-monitor

# 创建配置文件
cat > ~/.config/clash-monitor/config.env <<'EOF'
SILICONFLOW_API_KEY="sk-xxxxxxxx"
EOF

# 在脚本中加载
source ~/.config/clash-monitor/config.env
```

---

## 🔍 故障排查

### 问题 1: 环境变量未生效

**症状**: 脚本无法读取 API key

**解决方案**:
```bash
# 检查 .env 文件是否存在
ls -la .env

# 检查文件内容
cat .env

# 手动测试加载
source vpn-tools/load_env.sh
env | grep SILICONFLOW
```

### 问题 2: `.env` 文件被 Git 追踪

**症状**: `git status` 显示 `.env` 文件

**解决方案**:
```bash
# 从 Git 缓存中移除
git rm --cached .env

# 确认 .gitignore 包含 .env
grep "^\.env$" .gitignore

# 如果不存在，添加规则
echo ".env" >> .gitignore
```

### 问题 3: API key 已泄露

**解决方案**: 参考 `SECURITY.md` 中的「API Key 泄露处理流程」

---

## 📚 相关文档

- [SECURITY.md](./SECURITY.md) - 完整的安全配置指南
- [QUICK_REFERENCE.md](./vpn-tools/QUICK_REFERENCE.md) - 快速参考手册
- [README.md](./README.md) - 项目总体说明

---

## 💡 提示

1. **不要将 `.env` 文件提交到 Git**
2. **定期轮换 API keys**
3. **使用环境变量管理工具** (如 direnv, dotenv)
4. **团队协作时共享 `.env.example`，不要共享 `.env`**
5. **在 CI/CD 中使用 Secret 管理服务** (GitHub Secrets, GitLab CI/CD Variables)

---

## 🆘 需要帮助？

如果你在配置过程中遇到问题：

1. 查看 [SECURITY.md](./SECURITY.md) 获取详细的安全指南
2. 运行 `./vpn-tools/network_health_monitor.sh --help` 查看命令帮助
3. 创建 GitHub Issue 寻求帮助（**不要在 Issue 中包含真实的 API keys！**）
