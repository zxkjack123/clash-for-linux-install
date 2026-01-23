# Linux 一键安装 Clash (用户空间版本)

![GitHub License](https://img.shields.io/github/license/nelvko/clash-for-linux-install)
![GitHub top language](https://img.shields.io/github/languages/top/nelvko/clash-for-linux-install)
![GitHub Repo stars](https://img.shields.io/github/stars/nelvko/clash-for-linux-install)

![preview](resources/preview.png)

**🎉 全新用户空间安装版本 - 无需频繁输入密码！**

- 默认安装 `mihomo` 内核，[可选安装](https://github.com/nelvko/clash-for-linux-install/wiki/FAQ#%E5%AE%89%E8%A3%85-clash-%E5%86%85%E6%A0%B8) `clash`。
- 自动使用 [subconverter](https://github.com/tindy2013/subconverter) 进行本地订阅转换。
- **🚀 用户空间安装**：所有文件安装在用户目录，无需 root 权限运行。
- **⚡ 自动启动（systemd 用户服务）**：登录时自动启动内核，并由 `clash-proxy-env.service` 应用系统代理（GNOME/KDE/Git）。
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

# 3-5分钟一键稳定化（自愈+AI优化+验证）
./optimize_all_network_fast.sh

# 快速状态检查
./quick_vpn_check.sh

# AI 服务优化
./optimize_ai.sh

# 开发类服务优化（GitHub / NPM / PyPI）
./optimize_dev_nodes.sh

# YouTube 流媒体优化
./select_youtube_node.sh
```

### 📚 完整文档
- **[vpn-tools/README.md](vpn-tools/README.md)** - VPN工具包说明
- **[vpn-tools/TESTING_TOOLS_GUIDE.md](vpn-tools/TESTING_TOOLS_GUIDE.md)** - 完整使用指南
- **[vpn-tools/QUICK_REFERENCE.md](vpn-tools/QUICK_REFERENCE.md)** - 快速参考卡
- **帮助系统**: `cd vpn-tools && ./show_help.sh [script_name]`

### 🎯 工具分类

| 类别         | 工具                                                  | 用途                     | 耗时    |
| ------------ | ----------------------------------------------------- | ------------------------ | ------- |
| **🐳 Docker** | `test_docker_proxy.sh`                                | Docker 容器代理连接测试  | 2-3分钟 |
| **AI 优化**  | `optimize_ai.sh`                                      | ChatGPT/Claude 快速优化  | 2-3分钟 |
| **开发优化** | `optimize_dev_nodes.sh`                               | GitHub/NPM/PyPI 节点调优 | 2-3分钟 |
| **流媒体**   | `select_youtube_node.sh` / `fix_zoom_connectivity.sh` | YouTube/Zoom 诊断优化    | 3-5分钟 |
| **网络测试** | `network_connectivity_test.sh`                        | 全面连通性测试           | 5-8分钟 |
| **状态检查** | `quick_vpn_check.sh`                                  | 快速状态检查             | 30秒    |

### 📁 文件结构
```
vpn-tools/
├── README.md                      # VPN工具包说明
├── launcher.sh                    # 交互式启动器
├── optimize_ai.sh                 # AI优化工具
├── optimize_dev_nodes.sh          # GitHub/NPM/PyPI 节点优化
├── select_youtube_node.sh         # YouTube优化工具
├── network_connectivity_test.sh   # 网络连通性测试
├── quick_vpn_check.sh             # 快速状态检查
├── streaming_manager.sh           # 流媒体管理器
├── fix_zoom_connectivity.sh       # Zoom 诊断/修复
├── test_ai_connectivity.sh        # 全面AI测试
├── TESTING_TOOLS_GUIDE.md         # 完整使用指南
├── QUICK_REFERENCE.md             # 快速参考
└── ... (更多工具和文档)
```

详细使用说明请参考 [VPN工具包文档](vpn-tools/README.md)。

## 📚 完整文档

所有文档已按功能分类整理到 `docs/` 目录：

### 📖 文档导航

| 分类           | 文档                                     | 说明                           |
| -------------- | ---------------------------------------- | ------------------------------ |
| **🚀 快速开始** | [QUICK_START.md](QUICK_START.md)         | 5分钟快速上手                  |
| **📦 安装配置** | [docs/installation/](docs/installation/) | 安装指南、环境配置、安全设置   |
| **🌐 网络优化** | [docs/network/](docs/network/)           | 网络优化指南、系统审查         |
| **🔌 功能集成** | [docs/integrations/](docs/integrations/) | Docker、AI服务、VSCode Copilot |
| **🛠️ 开发调试** | [docs/development/](docs/development/)   | Bug修复、技术文档、更新说明    |
| **📝 变更日志** | [CHANGELOG.md](CHANGELOG.md)             | 版本历史和更新记录             |

**详细文档目录**: 查看 [docs/README.md](docs/README.md)

## 🆕 新版本特性

### ✅ 无密码体验
- **普通操作无需任何权限**：所有日常命令（启停、状态查看、配置修改）都不需要输入密码
- **用户服务管理**：使用 `systemctl --user` 管理服务，无需 root 权限
- **系统代理自动应用**：通过 `clash-proxy-env.service` 设置 GNOME/KDE 系统代理与 Git 代理

### ✅ 自动化部署
- **开机自启**：服务自动随用户登录启动（通过 `loginctl enable-linger`）
- **终端环境变量**：默认不在每个新 bash/zsh 里自动注入 `http_proxy`（避免 VS Code/短命令卡顿）；如需终端变量请按需配置轻量片段
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
- ✅ 登录时自动启动用户服务，并应用系统代理（GNOME/KDE/Git）
- ✅ 用户服务自动启动
- ✅ 每个用户独立安装，配置互不影响
- ✅ 安全隔离，无系统级权限风险

> 如遇问题，请在查阅[常见问题](https://github.com/nelvko/clash-for-linux-install/wiki/FAQ)及 [issue](https://github.com/nelvko/clash-for-linux-install/issues?q=is%3Aissue) 未果后进行反馈。

- 上述克隆命令使用了[加速前缀](https://gh-proxy.com/)，如失效请更换其他[可用链接](https://ghproxy.link/)。
- 默认通过远程订阅获取配置进行安装，本地配置安装详见：[#39](https://github.com/nelvko/clash-for-linux-install/issues/39)
- 没有订阅？[click me](https://次元.net/auth/register?code=oUbI)

### 命令一览

安装后推荐使用 `clashctl`（控制入口，安装脚本会尝试写到 `~/.local/bin/`）：

```bash
$ clashctl
Usage:
  clashctl COMMAND  [OPTION]

Commands:
  on                      开启代理
  off                     关闭代理
  proxy    [on|off|status] 系统代理
  ui                      面板地址
  status                  内核状况
  tun      [on|off]       Tun 模式
  mixin    [-e|-r]        Mixin 配置
  secret   [SECRET]       Web 密钥
  update   [auto|log]     更新订阅
  diag | doctor           一键诊断
```

> 说明：
> - 若你的系统没有把 `~/.local/bin` 加进 PATH，可直接运行：`bash ~/.local/share/clash/script/clashctl.sh status`
> - `clash` / `mihomo` 一般指内核二进制本身，不建议用作控制入口（避免混淆）

### 优雅启停

```bash
$ clashctl off

$ clashctl on
```

### 🧯 紧急切回直连网络

当节点全挂、代理进程异常、或你只是想临时“恢复正常不上代理”的网络时：

- **首选（已有命令）**：`clashctl off`
- **命令不可用/环境乱了**：运行独立脚本（会停止用户服务 + 卸载系统代理）

```bash
# 安装后脚本路径（推荐）
bash ~/.local/share/clash/script/emergency_off.sh

# 如果你只想停服务但保留系统/Git 代理设置（不推荐，一般会导致应用连接失败），可加：
# bash ~/.local/share/clash/script/emergency_off.sh --no-unset-proxy

# 若需要清理“当前终端”的 http_proxy/all_proxy（可选）
eval "$(bash ~/.local/share/clash/script/emergency_off.sh --print-unset)"

# 不影响网络的模拟（只展示将要执行的动作）
bash ~/.local/share/clash/script/emergency_off.sh --dry-run

# 试运行（更安全）：应用后等待 20 秒自动回滚
bash ~/.local/share/clash/script/emergency_off.sh --trial 20

# 试运行 + 直连自检：trial 默认会检查 baidu/bing/qq；不通就立刻回滚
bash ~/.local/share/clash/script/emergency_off.sh --trial 20

# 额外增加自定义站点检查（默认检查 + 你指定的都会测）
bash ~/.local/share/clash/script/emergency_off.sh --trial 20 --require-url https://www.taobao.com
```

> **用户空间版本特色**：无需输入密码，命令执行更快速！

<details>

<summary>原理</summary>

- **用户空间版本**: 使用 `systemctl --user` 控制内核服务（`mihomo`/`clash`）启停，并由 `clash-proxy-env.service` 应用系统代理（GNOME/KDE）与 Git 代理。
- **终端环境变量**: bash/zsh 默认不自动注入 `http_proxy` 等变量（避免每次新开 shell 卡顿）。如需终端变量，请参考 `docs/development/CLASH_PROXY_STARTUP_BEST_PRACTICES.md` 的轻量片段。

应用程序在发起网络请求时，会通过其指定的代理地址转发流量，不调整会造成：关闭代理但未卸载代理变量导致仍转发请求、开启代理后未设置代理地址导致请求不转发。

`clashctl on/off/proxy ...` 以及 `clash-proxy-env.service` 会完成上述流程。

</details>

### 🚀 自动启动与代理生效范围

- **服务启动**：安装后会启用 systemd 用户服务，登录时自动启动内核（`mihomo`/`clash`）。如需“开机即启”，可使用 `loginctl enable-linger`（可能需要管理员权限）。
- **系统代理**：由 `clash-proxy-env.service` 在登录时应用 GNOME/KDE 系统代理与 Git 代理，GUI 应用通常会自动生效。
- **终端环境变量**：为避免每次新开 shell 都跑重逻辑导致卡顿，bash/zsh 默认不会自动注入 `http_proxy`/`ALL_PROXY`。
  若你希望终端也自动获得代理变量，请按需配置轻量片段：`docs/development/CLASH_PROXY_STARTUP_BEST_PRACTICES.md`。

```bash
# 查看系统代理状态
$ clashctl proxy status

# 验证 GNOME 代理模式（如使用 GNOME）
$ gsettings get org.gnome.system.proxy mode
```

### Web 控制台

```bash
$ clashctl ui
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

$ clashctl secret 666
😼 密钥更新成功，已重启生效

$ clashctl secret
😼 当前密钥：666
```

- 通过浏览器打开 Web 控制台，实现可视化操作：切换节点、查看日志等。
- 控制台密钥默认为空，若暴露到公网使用建议更新密钥。

### 更新订阅

```bash
$ clashctl update https://example.com
👌 正在下载：原配置已备份...
🍃 下载成功：内核验证配置...
🍃 订阅更新成功

$ clashctl update auto [url]
😼 已设置定时更新订阅

$ clashctl update log
✅ [2025-02-23 22:45:23] 订阅更新成功：https://example.com
```

- `clashctl update` 会记住上次更新成功的订阅链接，后续执行无需再指定。
- 如需定时刷新订阅，推荐使用用户级 systemd timer：`docs/installation/AUTO_SUBSCRIPTION_REFRESH.md`。
- 通过配置文件进行更新：[pr#24](https://github.com/nelvko/clash-for-linux-install/pull/24#issuecomment-2565054701)

### `Tun` 模式

```bash
$ clashctl tun
😾 Tun 状态：关闭

$ clashctl tun on
😼 Tun 模式已开启
```

- 作用：实现本机及 `Docker` 等容器的所有流量路由到 `clash` 代理、DNS 劫持等。
- 原理：[clash-verge-rev](https://www.clashverge.dev/guide/term.html#tun)、 [clash.wiki](https://clash.wiki/premium/tun-device.html)。
- 注意事项：[#100](https://github.com/nelvko/clash-for-linux-install/issues/100#issuecomment-2782680205)

### `Mixin` 配置

```bash
$ clashctl mixin
😼 less 查看 mixin 配置

$ clashctl mixin -e
😼 vim 编辑 mixin 配置

$ clashctl mixin -r
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
  [ -f ~/url_backup.txt ] && clashctl update $(cat ~/url_backup.txt)
   ```

## 🚀 用户空间版本特性

| 特性         | 此版本                  | 其他版本对比       |
| ------------ | ----------------------- | ------------------ |
| **安装权限** | ✅ 普通用户即可          | ⚠️ 通常需要 sudo    |
| **日常操作** | ✅ 无需密码              | ⚠️ 可能需要密码     |
| **安装位置** | `~/.local/share/clash/` | 通常在系统目录     |
| **服务管理** | `systemctl --user`      | `sudo systemctl`   |
| **自动启动** | ✅ 登录自动启用代理      | ⚠️ 通常需手动启用   |
| **用户隔离** | ✅ 每用户独立            | ⚠️ 可能系统共享     |
| **安全性**   | ✅ 用户权限隔离          | ⚠️ 可能需系统权限   |
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

## � 运行时健康 & 指标 (Metrics)

新增 Prometheus 指标文件 (默认路径参考脚本变量 `CLASH_METRICS_FILE`)，可通过 `clashctl metrics` 立即生成，或 `clashctl metrics --cron-install 5` 安装每 5 分钟自动刷新任务。

当前输出的指标包括：
- `clash_health_score` / `clash_health_grade` 综合健康得分与等级 (A/B/C/D → 3/2/1/0)
- `clash_direct_rule_present{ip="1.1.1.1"|"8.8.8.8"}` 关键 DNS IP DIRECT 规则存在性
- `clash_dns_hijack_detected` 关键 DNS 是否被代理劫持 (1=是)
- `clash_upstream_failures_5m` 最近 5 分钟连接失败计数
- `clash_traffic_upload_bytes_total` / `clash_traffic_download_bytes_total` 核心接口上报累计上下行字节
- `clash_active_connections` 当前活跃连接数
- `clash_selector_groups_on_fail` 当前选择的节点含 `[FAIL]` 标签的 selector 分组数量
- `clash_metrics_timestamp_seconds` 指标生成时间戳

解析逻辑优先使用 `jq`，若系统未安装 `jq` 则自动回退到 `grep/sed`，可选安装：
```bash
sudo apt install -y jq   # 或其它发行版等价命令
```

## 🔻 节点降权 & 自动切换

命令：
```bash
clashctl downgrade [--since <分钟> --threshold <次数> --mode tag|drop --no-switch]
```

说明：
- 扫描最近 `--since` 分钟 (`默认10`) 的内核日志中 `connect error`，统计同一上游失败次数 ≥ `--threshold` (`默认5`) 的节点
- `--mode tag` 为分组引用添加后缀 `[FAIL]`；`--mode drop` 直接移除分组引用（保留节点定义）
- 变更后会执行一次原子合并+清洗+重启，确保 runtime 同步
- 默认随后自动对所有 selector 分组尝试切换到第一个非 `[FAIL]` 节点；使用 `--no-switch` 可禁止自动切换
- 操作被写入更新日志 (标记 `[DOWNGRADE-<timestamp>]`)

清理标签：
```bash
clashctl cleanfail   # 去除所有分组引用中的 [FAIL] 后缀并自动重新合并
```

并发安全：`downgrade` 与 `cleanfail` 在写入 `mixin.yaml` 前都会获取与主合并流程相同的文件锁，避免与订阅更新/其它合并并发冲突。

## 🧪 示例监控集成

Prometheus `file_sd` 示例 (prometheus.yml)：
```yaml
scrape_configs:
  - job_name: clash
    scrape_interval: 30s
    static_configs:
      - targets: ['localhost']
        labels:
          __metrics_path__: /absolute/path/to/metrics.prom
```

Grafana 可直接基于上述指标绘制：失败趋势、活跃连接、上传/下载速率（对 bytes 总量做 rate()）。


## 🔐 高级稳定性强化 (P0→P2)

| 等级 | 内容                                                         | 状态            |
| ---- | ------------------------------------------------------------ | --------------- |
| P0   | 原子合并 + 清洗 + 单次重启；强制关键 DIRECT 规则；运行时注解 | ✅ 已实现        |
| P1   | 订阅更新差异报告 (rules / fallback / 分组名)                 | ✅ 已实现        |
| P1   | runtime 守护自愈脚本 (自动检查+修复+可通知)                  | ✅ 已实现        |
| P2   | 可插入定时巡检 (cron) 与集中健康日志                         | ✅ 已实现 (示例) |

### 差异报告
执行 `clashctl update` 后若 runtime 发生变化会生成 `/tmp/runtime_diff_YYYYmmdd_HHMMSS.log`，并在更新日志里追加 `DIFF-时间戳` 标记，内容聚焦：
1. 规则增删 (常见风险触发点)
2. dns.fallback 变更 (防止裸 IP 回流)
3. proxy-groups 名称变更 (识别订阅分组漂移)

### runtime_guard.sh 自愈
脚本位置：`script/runtime_guard.sh`

用途：持续确保以下安全基线：
- 1.1.1.1 / 8.8.8.8 仅存在 DIRECT 规则
- 无代理劫持规则 (避免 DNS 递归抖动)
- YAML 结构可解析

示例：
```bash
# 单次巡检
bash script/runtime_guard.sh --check

# 巡检并自愈 + 报告 + 通知（安全模式；默认不会执行任意 shell 字符串）
# notify/webhook 会调用仓库的 vpn-tools/alert_notification.sh（可自行配置通知渠道）
bash script/runtime_guard.sh --auto-fix --report --alert notify

# 或：自定义脚本告警（安全 argv 传参）
# bash script/runtime_guard.sh --auto-fix --report --alert-script /path/to/hook.sh --alert-arg foo --alert-arg bar

# 每 10 分钟巡检 (添加到 crontab)
*/10 * * * * bash /absolute/path/script/runtime_guard.sh --auto-fix --cron >> /tmp/runtime_guard_status.log 2>&1
```
退出码语义：0=健康或已修复；1=检测到问题但未修复 (缺少 --auto-fix)。

### 推荐巡检策略
1. cron 每 10 分钟运行一次 `--auto-fix --cron`
2. 订阅更新后人工快速浏览 diff 报告 (出现大量异常规则及时人工审计)
3. 将 `/tmp/runtime_guard_status.log` 接入你自己的监控或日志收集体系

> 若想进一步扩展 (P3+): 可增加“异常规则白名单文件”“历史 diff 留存归档”“节点质量基线”等。


#### 3. 网络模式
```bash
# 使用 host 网络模式
docker run --network host your-image
```

### 配置说明

Docker 支持已自动配置以下内容：
- ✅ **安全默认**：默认更倾向仅本机监听（`127.0.0.1`），避免把代理/控制接口暴露到局域网
- ✅ **推荐方式（Linux）**：Docker 使用 `--network host`，容器内直接访问宿主机的 `127.0.0.1:7890`
- ⚠️ **bridge 模式**：如必须让容器通过 `<HOST_IP>:7890/9090` 访问，需要你显式调整监听地址并配合防火墙（详见下方文档）

### 详细文档
- **[docs/integrations/DOCKER_INTEGRATION.md](docs/integrations/DOCKER_INTEGRATION.md)** - 完整 Docker 集成指南
- **[docs/DOCKER_PROXY_GUIDE.md](docs/DOCKER_PROXY_GUIDE.md)** - Docker 代理使用与安全默认说明
- **[vpn-tools/test_docker_proxy.sh](vpn-tools/test_docker_proxy.sh)** - 完整测试套件

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
A: 本项目推荐使用 `clashctl` 作为控制入口（避免与内核二进制 `clash/mihomo` 混淆）。

1) 确认安装脚本已创建入口（默认在 `~/.local/bin/`）：
```bash
command -v clashctl || ls -l ~/.local/bin/clashctl
```

2) 如果 `~/.local/bin` 不在 PATH 中，请将其加入 PATH（或直接用完整路径运行）：
```bash
bash ~/.local/share/clash/script/clashctl.sh status
```

#### Q: 代理环境变量没有自动设置？
A: 这是**刻意的默认行为**：避免每次新开 bash/zsh 都执行重逻辑导致卡顿。

- GUI 应用通常使用系统代理（由 `clash-proxy-env.service` 设置）
- 若你希望终端自动拥有 `http_proxy/ALL_PROXY`，请按需添加轻量片段：`docs/development/CLASH_PROXY_STARTUP_BEST_PRACTICES.md`

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
A: 禁用 systemd 用户服务即可：

```bash
systemctl --user disable --now mihomo.service 2>/dev/null || true
systemctl --user disable --now clash.service 2>/dev/null || true
systemctl --user disable --now clash-proxy-env.service 2>/dev/null || true
```

如果你之前启用了开机自启（lingering），也可以关闭：

```bash
loginctl disable-linger "$USER" 2>/dev/null || true
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
