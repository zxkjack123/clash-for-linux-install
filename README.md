# Linux 一键安装 Clash (用户空间版本)

![GitHub License](https://img.shields.io/github/license/nelvko/clash-for-linux-install)
![GitHub top language](https://img.shields.io/github/languages/top/nelvko/clash-for-linux-install)
![GitHub Repo stars](https://img.shields.io/github/stars/nelvko/clash-for-linux-install)

![preview](resources/preview.png)

**🎉 全新用户空间安装版本 - 无需频繁输入密码！**

- 默认安装 `mihomo` 内核，[可选安装](https://github.com/nelvko/clash-for-linux-install/wiki/FAQ#%E5%AE%89%E8%A3%85-clash-%E5%86%85%E6%A0%B8) `clash`。
- 自动使用 [subconverter](https://github.com/tindy2013/subconverter) 进行本地订阅转换。
- **🚀 用户空间安装**：所有文件安装在用户目录，无需 root 权限运行。
- **⚡ 自动代理启动**：登录时自动启用代理，无需手动操作。
- **🔒 安全隔离**：每个用户独立安装，互不影响。
- 多架构支持，适配主流 `Linux` 发行版：`CentOS 7.6`、`Debian 12`、`Ubuntu 24.04.1 LTS`。

## 🛠️ VPN 测试工具套件

本项目包含完整的代理测试和优化工具集，帮助您获得最佳的网络性能。所有工具已整理到 `vpn-tools/` 文件夹中：

### 🚀 快速启动
```bash
# 进入工具目录
cd vpn-tools

# 交互式工具启动器（推荐）
./launcher.sh

# 快速状态检查
./quick_vpn_check.sh

# AI 服务优化
./optimize_ai.sh

# YouTube 流媒体优化
./select_youtube_node.sh
```

### 📚 完整文档
- **[vpn-tools/README.md](vpn-tools/README.md)** - VPN工具包说明
- **[vpn-tools/TESTING_TOOLS_GUIDE.md](vpn-tools/TESTING_TOOLS_GUIDE.md)** - 完整使用指南
- **[vpn-tools/QUICK_REFERENCE.md](vpn-tools/QUICK_REFERENCE.md)** - 快速参考卡
- **帮助系统**: `cd vpn-tools && ./show_help.sh [script_name]`

### 🎯 工具分类

| 类别 | 工具 | 用途 | 耗时 |
|------|------|------|------|
| **🐳 Docker** | `test_docker_proxy.sh` | Docker 容器代理连接测试 | 2-3分钟 |
| **AI 优化** | `optimize_ai.sh` | ChatGPT/Claude 快速优化 | 2-3分钟 |
| **流媒体** | `select_youtube_node.sh` | YouTube 快速优化 | 3-5分钟 |
| **网络测试** | `network_connectivity_test.sh` | 全面连通性测试 | 5-8分钟 |
| **状态检查** | `quick_vpn_check.sh` | 快速状态检查 | 30秒 |

### 📁 文件结构
```
vpn-tools/
├── README.md                      # VPN工具包说明
├── launcher.sh                    # 交互式启动器
├── optimize_ai.sh                 # AI优化工具
├── select_youtube_node.sh         # YouTube优化工具
├── network_connectivity_test.sh   # 网络连通性测试
├── quick_vpn_check.sh             # 快速状态检查
├── streaming_manager.sh           # 流媒体管理器
├── test_ai_connectivity.sh        # 全面AI测试
├── TESTING_TOOLS_GUIDE.md         # 完整使用指南
├── QUICK_REFERENCE.md             # 快速参考
└── ... (更多工具和文档)
```

详细使用说明请参考 [VPN工具包文档](vpn-tools/README.md)。

## 🆕 新版本特性

### ✅ 无密码体验
- **普通操作无需任何权限**：所有日常命令（启停、状态查看、配置修改）都不需要输入密码
- **用户服务管理**：使用 `systemctl --user` 管理服务，无需 root 权限
- **环境变量自动设置**：代理环境变量自动配置，无需手动干预

### ✅ 自动化部署
- **开机自启**：服务自动随用户登录启动（通过 `loginctl enable-linger`）
- **终端自动代理**：打开新终端时自动启用代理环境
- **用户空间安装**：所有文件位于 `~/.local/share/clash/`，易于管理和备份

### ✅ 安全与隔离
- **命令保持一致**：所有原有命令继续有效，使用体验无变化
- **配置文件兼容**：原有配置文件格式完全兼容
- **用户级隔离**：每个用户独立安装，配置互不影响

### ✅ 稳定性改进 (2025-08-13)
- **服务启动修复**：解决了mihomo服务启动超时问题
- **循环依赖修复**：优化systemd服务依赖关系，避免启动死锁
- **快速启动**：服务启动时间显著缩短，避免90秒超时
- **自动重启**：改进服务重启机制，确保高可用性

### ✅ 订阅智能合并与慢节点筛选 (2025-08-20)
新增 `vpn-tools/merge_subscription.sh`：
* 仅替换 `proxies` 块，保留本地自定义 `proxy-groups` / `rules`
* 输出新增 / 删除 / 变更节点 diff 概要
* 可选 `--auto-append-new` 将新节点自动追加到指定分组
* 新增高延迟/超时节点筛选：
  - `--screen-timeout tag|drop` 选择为慢节点打标或直接剔除
  - `--timeout-threshold <毫秒>` 建连耗时阈值 (默认 1500ms)
  - `--slow-suffix [SLOW]` 自定义标记后缀 (tag 模式)
  - 并发 `/dev/tcp` + `timeout` 测试 TCP connect 时间；失败或超阈值即判定慢节点
示例：
```bash
# 下载订阅并剔除慢节点后直接应用
./vpn-tools/merge_subscription.sh --url "https://example/sub" \
  --screen-timeout drop --timeout-threshold 1800 --apply

# 本地文件并为慢节点加标签
./vpn-tools/merge_subscription.sh --new sub.yaml \
  --screen-timeout tag --timeout-threshold 1500 --slow-suffix "[SLOW]" > merged.yaml
```
> 建议在执行节点优化脚本前先剔除明显超时/失效节点，减少噪声。

## 快速开始

### 环境要求

- **用户权限**：普通用户即可，无需任何管理员权限
- **Shell 支持**：`bash`、`zsh`、`fish`
- **系统要求**：支持 `systemd` 的 Linux 发行版

### 一键安装

```bash
git clone --depth 1 https://gh-proxy.com/https://github.com/zxkjack123/clash-for-linux-install.git \
  && cd clash-for-linux-install \
  && bash install.sh
```

#### 安装说明

这是一个**用户空间安装版本**，具有以下特点：
- ✅ 安装到 `~/.local/share/clash/`
- ✅ 无需任何管理员权限运行日常命令
- ✅ 自动设置代理环境
- ✅ 用户服务自动启动
- ✅ 每个用户独立安装，配置互不影响
- ✅ 安全隔离，无系统级权限风险

> 如遇问题，请在查阅[常见问题](https://github.com/nelvko/clash-for-linux-install/wiki/FAQ)及 [issue](https://github.com/nelvko/clash-for-linux-install/issues?q=is%3Aissue) 未果后进行反馈。

- 上述克隆命令使用了[加速前缀](https://gh-proxy.com/)，如失效请更换其他[可用链接](https://ghproxy.link/)。
- 默认通过远程订阅获取配置进行安装，本地配置安装详见：[#39](https://github.com/nelvko/clash-for-linux-install/issues/39)
- 没有订阅？[click me](https://次元.net/auth/register?code=oUbI)

### 命令一览

执行 `clash` 列出开箱即用的快捷命令。

> 兼容多种命令风格

```bash
$ clash
Usage:
    clash     COMMAND [OPTION]
    mihomo    COMMAND [OPTION]
    clashctl  COMMAND [OPTION]
    mihomoctl COMMAND [OPTION]

Commands:
    on                   开启代理
    off                  关闭代理
    ui                   面板地址
    status               内核状况
    tun      [on|off]    Tun 模式
    mixin    [-e|-r]     Mixin 配置
    secret   [SECRET]    Web 密钥
    update   [auto|log]  更新订阅
```

### 优雅启停

```bash
$ clashoff
😼 已关闭代理环境

$ clashon
😼 已开启代理环境
```

> **用户空间版本特色**：无需输入密码，命令执行更快速！

<details>

<summary>原理</summary>

- **用户空间版本**: 使用 `systemctl --user` 控制 `clash` 启停，直接调整用户环境变量（http_proxy 等），无需 sudo 权限。
- **系统版本**: 使用 `systemctl` 控制 `clash` 启停，并调整代理环境变量的值（http_proxy 等）。

应用程序在发起网络请求时，会通过其指定的代理地址转发流量，不调整会造成：关闭代理但未卸载代理变量导致仍转发请求、开启代理后未设置代理地址导致请求不转发。

`clashon` 等命令封装了上述流程。

</details>

### 🚀 自动代理启动

用户空间版本的一大特色是**自动代理启动**：

- **登录自动启用**：每次登录系统或打开新终端时，代理自动启用
- **环境变量自动设置**：`http_proxy`、`https_proxy` 等环境变量自动配置
- **后台静默运行**：代理服务在后台运行，不影响正常使用
- **开机自启**：通过 `loginctl enable-linger` 实现开机自动启动

```bash
# 打开新终端时自动显示
$ echo $http_proxy
http://127.0.0.1:7890

# 检查代理状态
$ clash proxy status
😼 系统代理：开启
http_proxy： http://127.0.0.1:7890
socks_proxy：socks5h://127.0.0.1:7890
```

### Web 控制台

```bash
$ clashui
╔═══════════════════════════════════════════════╗
║                😼 Web 控制台                  ║
║═══════════════════════════════════════════════║
║                                               ║
║     🔓 注意放行端口：9090                      ║
║     🏠 内网：http://192.168.0.1:9090/ui       ║
║     🌏 公网：http://255.255.255.255:9090/ui   ║
║     ☁️ 公共：http://board.zash.run.place      ║
║                                               ║
╚═══════════════════════════════════════════════╝

$ clashsecret 666
😼 密钥更新成功，已重启生效

$ clashsecret
😼 当前密钥：666
```

- 通过浏览器打开 Web 控制台，实现可视化操作：切换节点、查看日志等。
- 控制台密钥默认为空，若暴露到公网使用建议更新密钥。

### 更新订阅

```bash
$ clashupdate https://example.com
👌 正在下载：原配置已备份...
🍃 下载成功：内核验证配置...
🍃 订阅更新成功

$ clashupdate auto [url]
😼 已设置定时更新订阅

$ clashupdate log
✅ [2025-02-23 22:45:23] 订阅更新成功：https://example.com
```

- `clashupdate` 会记住上次更新成功的订阅链接，后续执行无需再指定。
- 可通过 `crontab -e` 修改定时更新频率及订阅链接。
- 通过配置文件进行更新：[pr#24](https://github.com/nelvko/clash-for-linux-install/pull/24#issuecomment-2565054701)

### `Tun` 模式

```bash
$ clashtun
😾 Tun 状态：关闭

$ clashtun on
😼 Tun 模式已开启
```

- 作用：实现本机及 `Docker` 等容器的所有流量路由到 `clash` 代理、DNS 劫持等。
- 原理：[clash-verge-rev](https://www.clashverge.dev/guide/term.html#tun)、 [clash.wiki](https://clash.wiki/premium/tun-device.html)。
- 注意事项：[#100](https://github.com/nelvko/clash-for-linux-install/issues/100#issuecomment-2782680205)

### `Mixin` 配置

```bash
$ clashmixin
😼 less 查看 mixin 配置

$ clashmixin -e
😼 vim 编辑 mixin 配置

$ clashmixin -r
😼 less 查看 运行时 配置
```

- 将自定义配置写在 `Mixin` 而不是原配置中，可避免更新订阅后丢失自定义配置。
- 运行时配置是订阅配置和 `Mixin` 配置的并集。
- 相同配置项优先级：`Mixin` 配置 > 订阅配置。

### 卸载

```bash
bash uninstall.sh
```

### 📁 文件位置

- **安装目录**: `~/.local/share/clash/`
- **配置文件**: `~/.local/share/clash/*.yaml`
- **服务文件**: `~/.config/systemd/user/mihomo.service`
- **日志查看**: `journalctl --user -u mihomo -f`

### 🔄 升级与迁移

如果你之前使用过其他版本的Clash安装脚本，可以平滑迁移到这个用户空间版本：

1. **备份现有配置**（如有需要）：
   ```bash
   # 如果之前有用户安装，备份配置
   [ -f ~/.local/share/clash/mixin.yaml ] && cp ~/.local/share/clash/mixin.yaml ~/mixin_backup.yaml
   [ -f ~/.local/share/clash/url ] && cp ~/.local/share/clash/url ~/url_backup.txt
   ```

2. **卸载旧版本**（如有）：
   ```bash
   # 如果之前有安装，先卸载
   cd /path/to/old/clash-for-linux-install && bash uninstall.sh
   ```

3. **安装新的用户空间版本**：
   ```bash
   git clone --depth 1 https://gh-proxy.com/https://github.com/zxkjack123/clash-for-linux-install.git \
     && cd clash-for-linux-install \
     && bash install.sh
   ```

4. **恢复配置**（如有备份）：
   ```bash
   [ -f ~/mixin_backup.yaml ] && cp ~/mixin_backup.yaml ~/.local/share/clash/mixin.yaml
   [ -f ~/url_backup.txt ] && clash update $(cat ~/url_backup.txt)
   ```

## 🚀 用户空间版本特性

| 特性         | 此版本                  | 其他版本对比     |
| ------------ | ----------------------- | ---------------- |
| **安装权限** | ✅ 普通用户即可          | ⚠️ 通常需要 sudo  |
| **日常操作** | ✅ 无需密码              | ⚠️ 可能需要密码   |
| **安装位置** | `~/.local/share/clash/` | 通常在系统目录    |
| **服务管理** | `systemctl --user`      | `sudo systemctl` |
| **自动启动** | ✅ 登录自动启用代理      | ⚠️ 通常需手动启用 |
| **用户隔离** | ✅ 每用户独立            | ⚠️ 可能系统共享   |
| **安全性**   | ✅ 用户权限隔离          | ⚠️ 可能需系统权限 |
| **配置管理** | ✅ 用户可完全控制        | ⚠️ 可能需管理员权限 |
| **卸载清理** | ✅ 只影响当前用户        | ⚠️ 可能影响整个系统 |

### 🎯 适用场景

**此版本特别适合**：
- 个人开发环境
- 多用户系统中的独立使用
- 不想频繁输入密码的用户
- 需要自动化代理环境的场景
- 对安全性有要求的环境
- 学习和测试环境

## 🐳 Docker 容器代理支持

本项目已完全支持 Docker 容器代理访问，允许容器内的应用通过 Clash 代理访问网络。

### 快速验证
```bash
# 运行 Docker 代理测试套件
cd vpn-tools && ./test_docker_proxy.sh

# 快速测试容器代理功能
docker run --rm curlimages/curl curl -x http://$(hostname -I | awk '{print $1}'):7890 http://httpbin.org/ip
```

### 使用方法

#### 1. 环境变量方式（推荐）
```bash
# 单个容器
docker run --rm -e HTTP_PROXY=http://$(hostname -I | awk '{print $1}'):7890 your-image

# Docker Compose
version: '3.8'
services:
  your-app:
    image: your-image
    environment:
      - HTTP_PROXY=http://host.docker.internal:7890
      - HTTPS_PROXY=http://host.docker.internal:7890
    extra_hosts:
      - "host.docker.internal:HOST_IP"
```

#### 2. 直接指定代理
```bash
# 使用 curl 示例
docker run --rm curlimages/curl curl -x http://HOST_IP:7890 https://www.google.com
```

#### 3. 网络模式
```bash
# 使用 host 网络模式
docker run --network host your-image
```

### 配置说明

Docker 支持已自动配置以下内容：
- ✅ **端口绑定**：代理服务监听所有网络接口 (`:::7890`)
- ✅ **防火墙规则**：允许 Docker 网络访问代理端口
- ✅ **LAN 访问**：启用 `allow-lan: true` 支持容器访问
- ✅ **API 接口**：Web 控制台支持容器内访问 (`:::9090`)

### 详细文档
- **[DOCKER_INTEGRATION.md](DOCKER_INTEGRATION.md)** - 完整 Docker 集成指南
- **[vpn-tools/test_docker_proxy.sh](vpn-tools/test_docker_proxy.sh)** - 完整测试套件

## 常见问题

## 常见问题

### 新用户常见问题

#### Q: 重启后代理没有自动启动？
A: 检查 lingering 是否启用：
```bash
loginctl show-user $USER | grep Linger
# 如果显示 Linger=no，执行：
sudo loginctl enable-linger $USER
```

#### Q: 新终端中 clash 命令不可用？
A: 检查 shell 配置文件：
```bash
# 检查是否已添加到 bashrc/zshrc
grep clash ~/.bashrc ~/.zshrc
# 如果没有，重新安装或手动添加：
echo 'source ~/.local/share/clash/script/common.sh && source ~/.local/share/clash/script/clashctl.sh' >> ~/.bashrc
```

#### Q: 代理环境变量没有自动设置？
A: 重新加载 shell 配置：
```bash
source ~/.bashrc  # 或 source ~/.zshrc
# 然后手动启用代理：
clashon
```

#### Q: 服务无法启动？
A: 检查服务状态和日志：
```bash
systemctl --user status mihomo
journalctl --user -u mihomo -f
```

如果遇到启动超时问题，这通常是由于systemd服务配置问题导致的。最新版本已修复此问题。如果仍有问题，可以手动重启：
```bash
systemctl --user restart mihomo
```

#### Q: 想要禁用自动代理启动？
A: 编辑 shell 配置文件，注释掉相关行：
```bash
# 编辑 ~/.bashrc 或 ~/.zshrc，在包含 clashon 的行前加 #
sed -i 's/.*clashon.*/#&/' ~/.bashrc
```

### 通用问题

[wiki](https://github.com/nelvko/clash-for-linux-install/wiki/FAQ)

## 引用

- [Clash 知识库](https://clash.wiki/)
- [Clash 家族下载](https://www.clash.la/releases/)
- [Clash Premium 2023.08.17](https://downloads.clash.wiki/ClashPremium/)
- [mihomo v1.19.2](https://github.com/MetaCubeX/mihomo)
- [subconverter v0.9.0：本地订阅转换](https://github.com/tindy2013/subconverter)
- [yacd v0.3.8：Web 控制台](https://github.com/haishanh/yacd)
- [yq v4.45.1：处理 yaml](https://github.com/mikefarah/yq)

## Star History

<a href="https://www.star-history.com/#nelvko/clash-for-linux-install&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=nelvko/clash-for-linux-install&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=nelvko/clash-for-linux-install&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=nelvko/clash-for-linux-install&type=Date" />
 </picture>
</a>

## Thanks

[@鑫哥](https://github.com/TrackRay)

## 特别声明

1. 编写本项目主要目的为学习和研究 `Shell` 编程，不得将本项目中任何内容用于违反国家/地区/组织等的法律法规或相关规定的其他用途。
2. 本项目保留随时对免责声明进行补充或更改的权利，直接或间接使用本项目内容的个人或组织，视为接受本项目的特别声明。
