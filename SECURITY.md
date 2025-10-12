# 安全配置指南

## ⚠️ API Key 管理

### 不要在代码中硬编码 API Keys！

**错误示例** ❌:
```bash
api_key="sk-avdenocgxjqjdpuqraipuoqhwnrevydosnprqtflabcxhkrj"
```

**正确做法** ✅:

#### 方案 1: 使用环境变量

```bash
# 在 ~/.bashrc 或 ~/.zshrc 中添加:
export SILICONFLOW_API_KEY="your_api_key_here"

# 在脚本中读取:
api_key="${SILICONFLOW_API_KEY:-}"
if [[ -z "$api_key" ]]; then
    echo "错误: 未设置 SILICONFLOW_API_KEY 环境变量"
    exit 1
fi
```

#### 方案 2: 使用 .env 文件

```bash
# 1. 复制模板文件
cp .env.example .env

# 2. 编辑 .env 文件，填入真实 API key
vim .env

# 3. 在脚本中加载 .env
if [[ -f .env ]]; then
    source .env
fi
```

#### 方案 3: 使用独立配置文件

```bash
# 创建配置文件 ~/.config/network-monitor/api_keys.conf
mkdir -p ~/.config/network-monitor
cat > ~/.config/network-monitor/api_keys.conf <<'EOF'
SILICONFLOW_API_KEY="your_api_key_here"
EOF

chmod 600 ~/.config/network-monitor/api_keys.conf

# 在脚本中加载
if [[ -f ~/.config/network-monitor/api_keys.conf ]]; then
    source ~/.config/network-monitor/api_keys.conf
fi
```

## 🔒 .gitignore 保护

本项目已配置 `.gitignore` 忽略以下敏感文件：

- `.env` 和 `.env.local`
- `*_api_keys.conf`
- `*_secrets.conf`
- `*.key`, `*.pem`, `*.p12`

## 🚨 如果 API Key 已泄露

如果你不小心将 API key 提交到了 Git 仓库：

### 1. 立即撤销泄露的 API Key
- 硅基流动: https://cloud.siliconflow.cn/account/ak
- UIUI API: 登录后台撤销并重新生成

### 2. 从 Git 历史中删除敏感信息

#### 方案 A: 使用 git filter-repo (推荐)

```bash
# 安装 git-filter-repo
pip3 install git-filter-repo

# 删除包含 API key 的文件
git filter-repo --invert-paths --path AI_SERVICES_UPDATE.md

# 或者替换 API key 为占位符
git filter-repo --replace-text <(echo 'sk-avdenocgxjqjdpuqraipuoqhwnrevydosnprqtflabcxhkrj==>YOUR_API_KEY_HERE')

# 强制推送到远程 (危险操作!)
git push origin --force --all
git push origin --force --tags
```

#### 方案 B: 使用 BFG Repo-Cleaner

```bash
# 下载 BFG
wget https://repo1.maven.org/maven2/com/madgag/bfg/1.14.0/bfg-1.14.0.jar

# 删除敏感文件
java -jar bfg-1.14.0.jar --delete-files AI_SERVICES_UPDATE.md

# 或替换文本
echo 'sk-avdenocgxjqjdpuqraipuoqhwnrevydosnprqtflabcxhkrj' > passwords.txt
java -jar bfg-1.14.0.jar --replace-text passwords.txt

# 清理并推送
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push origin --force --all
```

### 3. 通知协作者

如果是团队项目，通知所有协作者：
- 旧的 Git 历史已失效
- 需要重新克隆仓库
- 不要使用泄露的 API key

## 📋 检查清单

提交代码前，确保：

- [ ] 没有硬编码的 API keys
- [ ] 没有硬编码的密码或 tokens
- [ ] 敏感配置文件已添加到 `.gitignore`
- [ ] 使用环境变量或配置文件管理密钥
- [ ] 配置文件模板 (`.example`) 不包含真实密钥

## 🔍 扫描工具

使用工具自动检测敏感信息：

```bash
# 安装 gitleaks
brew install gitleaks  # macOS
# 或
wget https://github.com/gitleaks/gitleaks/releases/download/v8.18.0/gitleaks_8.18.0_linux_x64.tar.gz

# 扫描当前仓库
gitleaks detect --verbose

# 扫描未提交的更改
gitleaks protect --verbose
```

## 📞 联系方式

如果发现安全问题，请通过以下方式联系：
- 创建 Issue (不要包含敏感信息！)
- 发送邮件到: [你的邮箱]
