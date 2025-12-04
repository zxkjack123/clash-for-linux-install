# 将阿里云日本服务器构建为个人翻墙节点指南

> 目标：把位于日本的阿里云国际服务器（公网 IP `47.245.32.3`，内网 IP `172.19.9.103`）打造成个人专用出口节点，通过 Tailscale 内网穿透，实现高隐匿、高安全的访问。

## 0. 先决条件

- 阿里云国际账号，可修改该实例的 **安全组**，确保允许 `22/tcp`、`41641/udp`（Tailscale 默认端口）以及后续需要暴露的端口。
- 可通过 SSH 登录服务器（root 或 sudo 权限）。
- 本地设备已安装 **Clash** 与 **Tailscale**（Linux/macOS/Windows 均可）。
- 可访问 GitHub/Tailscale/Sing-box 官网以下载脚本；若受限，请先通过现有代理下载到本地再上传。
- （可选）自备域名与证书，如需在公网开放 VMess/Reality/WS+TLS。
- 建议服务器系统：Debian 12 / Ubuntu 22.04 LTS（1 vCPU + 1G 内存即可，2G 体验更好）。
- 建议先在本地生成并上传 SSH 公钥，在阿里云控制台关闭「密码登录」，只保留密钥登录。

> 使用场景：默认假设这是 **你个人长期使用** 的节点，不对外分享。

为尽量做到「一次配置，长期可用」，本指南按下面逻辑组织：

- 第 2、3 章：一次性搭建步骤，正常情况下只需要做一遍。
- 第 4 章：首次搭建完成后，做一次连通性验证即可。
- 第 6 章：每 1–3 个月想起来时做一次简单维护（可选）。
- 第 7 章：只有在「出问题了」时再翻出来排查。

## 1. 架构概览与优势

```
┌──────────┐        tailscale (encrypted)        ┌────────────────┐
│ Local PC │ ───────────────────────────────────►│ JP AliCloud VM │
│ (Clash)  │◄─── proxy (SS-2022/VMess) ──────────┤ (Sing-box)     │
└──────────┘                                     └────────────────┘
```

- **隐蔽性**：端口仅在 Tailscale 内网开放，公网扫描不到任何开放端口（除了 SSH 和 Tailscale UDP）。
- **安全性**：Shadowsocks-2022 协议抗重放攻击；Tailscale 提供 WireGuard 级别的加密隧道。
- **稳定性**：阿里云国际线路（CN2/GIA 或普通线路）配合 BBR 拥塞控制。

## 2. 服务器端部署 (JP Node)

_这一章是服务器的一次性配置：完成后除非重装系统或更换机器，一般不需要再改。_

### 2.1 系统初始化与 BBR 优化

登录服务器后，先完成基础加固与内核调优：

```bash
# 设定时区并同步时钟
sudo timedatectl set-timezone Asia/Tokyo
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget unzip htop fail2ban net-tools

# 开启 BBR + FQ
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 验证 BBR 生效
sysctl net.ipv4.tcp_congestion_control
lsmod | grep bbr
```

- 建议设置 `fail2ban` 保护 SSH，或直接关闭密码登录：`PasswordAuthentication no`。
- 配置 UFW 默认策略：`sudo ufw default deny incoming` / `sudo ufw default allow outgoing`。

可选的 SSH 加固示例（确保你已经能用普通用户 + 密钥登录后再执行）：

```bash
# 创建一个普通用户并加入 sudo 组（如果你还没有非 root 账号）
sudo adduser gw
sudo usermod -aG sudo gw

# 修改 sshd 配置，禁止密码登录（请按你现有配置适当调整）
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl reload ssh
```

### 2.2 安装 Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
# 建议在 Admin Console 创建一个 1 次性 Auth Key
sudo tailscale up \
  --hostname=jp-node \
  --authkey=tskey-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  --ssh \
  --accept-dns=false \
  --accept-routes=false
```

- 若未使用 `--authkey`，首次运行会输出登录 URL，复制到浏览器完成授权即可。
- 获取 Auth Key 的位置：Tailscale 管理后台 → "Settings" → "Keys" → 生成一个适合服务器、可复用或一次性的 key。
- 在 Tailscale Admin Console 中，将 `jp-node` 的 **Key Expiry** 改为 `Never`，避免 90 天自动下线。
- 查看并记录 Tailscale IP：

  ```bash
  tailscale status --peers=false
  tailscale ip -4
  tailscale ip -6
  ```

  其中 `tailscale ip -4` 输出的 `100.x.y.z` 将用于 Sing-box 配置和 Clash 节点配置。
- 开机自启：`sudo systemctl enable --now tailscaled`。

### 2.3 部署 Sing-box (作为代理服务端)

使用官方脚本安装：

```bash
bash <(curl -fsSL https://sing-box.app/install.sh)
```

**生成强密码** (Shadowsocks-2022 必须使用固定长度密钥):

```bash
openssl rand -base64 32
# 输出示例: L7x... (请复制这个字符串)
```

> 建议将这个密钥妥善保存在密码管理器或本地加密笔记中，后面 Clash 客户端也要用同一份密码。

**配置 Sing-box**:
编辑 `/usr/local/etc/sing-box/config.json`（若文件不存在可新建；将示例 IP 替换成前面记录的 `tailscale ip -4` 实际值）：

```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "100.x.y.z",
      "listen_port": 9000,
      "method": "2022-blake3-aes-256-gcm",
      "password": "在此处粘贴上面生成的openssl密钥",
      "multiplex": {
        "enabled": true
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
```

> **注意**：若需公网访问，可改为 `listen: "0.0.0.0"`，但务必同时在安全组与 UFW 中限制来源 IP。

保存配置后，先检查 JSON 是否合法、配置是否能被解析：

```bash
sudo sing-box check -c /usr/local/etc/sing-box/config.json
```

若输出 `configuration OK` 之类信息，再继续下面的防火墙和启动步骤。

**配置防火墙 (UFW)**:

```bash
sudo ufw allow ssh
# 允许 Tailscale UDP 端口 (通常是随机的，但 Tailscale 会自动处理，这里主要是允许内网流量)
sudo ufw allow in on tailscale0 to any port 9000
# 或者简单粗暴地允许 Tailscale 网段
sudo ufw allow from 100.64.0.0/10 to any port 9000
sudo ufw enable
sudo ufw status verbose
```

**推荐的 systemd Override（自动重启 + 健康日志）**:

```bash
sudo systemctl edit sing-box
```

填入：

```
[Service]
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
```

**启动服务**:

```bash
sudo systemctl enable --now sing-box
sudo systemctl status sing-box
```

## 3. 本地客户端配置 (Local PC)

_这一章也是一次性配置：本地 Clash 和 Tailscale 设置好后，后面基本处于“开机即用”状态。_

### 3.1 确认 Tailscale 连接

在本地机器上：

```bash
tailscale ping <JP-Node-Tailscale-IP>
# 确保能 ping 通
```

其中 `<JP-Node-Tailscale-IP>` 就是你在服务器上运行 `tailscale ip -4` 时看到的 `100.x.y.z` 地址。

如果本地尚未安装 Tailscale，可以执行：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

然后通过 `tailscale status` 确认本机与 `jp-node` 同时在线：

```bash
tailscale status
```

### 3.2 修改 Clash 配置

编辑本项目中的 `resources/mixin.yaml`，添加自定义节点。

```yaml
proxies:
  - name: "JP-Tailscale"
    type: ss
    server: <JP-Node-Tailscale-IP>
    port: 9000
    cipher: 2022-blake3-aes-256-gcm
    password: "<服务器端生成的openssl密钥>"
    # udp: true # 开启 UDP 转发支持

proxy-groups:
  # 将新节点加入到现有的策略组中
  - name: AUTO-SMART
    # ... (保留原有内容)
    proxies:
      - JP-Tailscale  # <--- 添加这一行
      - V1-日本01|流媒体|GPT
      # ...
  
  - name: Development
    proxies:
      - JP-Tailscale  # <--- 添加这一行
      - AUTO-SMART
      # ...
```

> 提示：如果 `mixin.yaml` 里原本没有 `proxies:` 顶层键，可直接追加；Clash 会把 mixin 中的 `proxies` 与订阅里的节点数组合并。

编辑完成后，建议用 YAML 校验工具快速检查是否有缩进或语法错误：

```bash
yamllint resources/mixin.yaml  # 若未安装，可通过 apt/pip 安装 yamllint
```

### 3.3 应用配置

运行脚本重新生成配置：

```bash
./clashctl.sh mixin
./clashctl.sh restart
# 验证明细
./clashctl.sh status
```

## 4. 验证与测试

_建议在首次搭建完成后完整跑一遍；后续只有感觉网络异常或怀疑节点有问题时再使用这些命令。_

1. **基础连接测试**:

   ```bash
   # 测试通过新节点访问 Google
   curl -I -x http://127.0.0.1:7890 https://www.google.com
   ```
2. **AI 服务连通性测试**:

   ```bash
   # 使用项目自带工具测试
   ./vpn-tools/test_ai_connectivity.sh
   ```

   观察 `JP-Tailscale` 是否被选中（如果它在 `AUTO-SMART` 或 `AI` 组中被优选）。
3. **速度测试**:
   可以在 Clash Dashboard (http://127.0.0.1:9090/ui) 中对 `JP-Tailscale` 进行测速。

## 5. 进阶：作为 Tailscale Exit Node (可选)

如果你希望手机或其他设备也



































能通过该节点上网，而不想配置 Clash：

1. **服务器端**:

   ```bash
   sudo tailscale up --advertise-exit-node
   ```

   在 Tailscale Admin Console 中，通过该机器的 "Edit route settings" 启用 Exit Node。
2. **客户端 (手机/PC)**:
   在 Tailscale 菜单中选择 "Exit Node" -> "jp-node"。
   此时所有流量都会经过日本服务器转发。

## 6. 监控与维护

_这一章主要是「偶尔维护」用的，比如每 1–3 个月或在你准备大版本升级前后参考；日常使用时不需要频繁操作。_

- **健康检测脚本（可选，自检用）**：
  - `./vpn-tools/network_health_monitor.sh --check-only` 查看整体打分，一般只在感觉不太稳定时使用即可。
  - `./vpn-tools/optimize_dev_nodes.sh` / `quick_dev_research_test.sh` 验证 `JP-Tailscale` 的 RTT、可用性，用于对比不同节点质量。
- **日志排查**：
  - Sing-box：`journalctl -u sing-box -f`
  - Tailscale：`journalctl -u tailscaled -f`
  - Clash 本地：`./clashctl.sh logs`
- **定期更新（建议 1–3 个月一次）**：
  - `sudo sing-box update` 或重新运行安装脚本。
  - `sudo tailscale update`（或重跑 install 脚本）。
  - `sudo apt upgrade`，更新完记得 `sudo reboot` 以应用内核补丁。
- **备份配置**：使用 `scp`/`rsync` 将 `/usr/local/etc/sing-box/config.json`、`/etc/ufw/`、`~/.tailscale/` 备份到安全位置。

## 7. 故障排查清单

_只有在真的出问题（比如完全连不上、经常断、速度异常慢）时，再按这节一步步检查。_

1. **Tailscale 掉线**：

- `tailscale status --peers=false` 检查本机；若显示 `needs-login`，执行 `sudo tailscale up --reset ...`。
- 确认安全组未屏蔽 `41641/udp`；必要时重启服务 `sudo systemctl restart tailscaled`。

2. **Sing-box 无法连接**：

- `sudo ss -lnpt | grep 9000` 确认监听在 `100.x.y.z:9000`。
- 尝试从本地 `tailscale ping 100.x.y.z`；若无法 ping 通，大概率是 Tailscale 或安全组问题。
- 检查配置文件 JSON 是否有效：`sing-box check -c /usr/local/etc/sing-box/config.json`。

3. **Clash 未显示节点**：

- 确认 `resources/mixin.yaml` 合法，运行 `yamllint` 或 `clashctl.sh mixin -e` 检查。
- 重启服务：`./clashctl.sh restart`，并在 Dashboard 中刷新。

4. **速度慢**：

- 在服务器执行 `sudo ethtool -S eth0 | grep speed` 确认 NIC 状态。
- 尝试切换端口/协议，如开启 Sing-box 的 `tuic`/`hysteria2` 入站。
- 检查阿里云带宽峰值是否被打满（控制台监控）。

## 8. 日常使用极简总结

- **平时**：不改配置，保持服务器与本地机器 Tailscale 在线；Clash 正常运行即可。
- **偶尔（1–3 个月）**：SSH 上服务器，执行一组更新命令：

  ```bash
  sudo sing-box update || true
  sudo tailscale update || true
  sudo apt update && sudo apt upgrade -y
  sudo reboot
  ```
- **出问题时**：

  1. 本地先跑 `tailscale status` / `tailscale ping`，确认到 JP 节点是否通。
  2. 再跑 `./vpn-tools/network_health_monitor.sh --check-only` 看整体表现。
  3. 最后按「第 7 章 故障排查清单」逐项排查。

**维护记录**:

- 2025-10-23: 文档创建。
- 2025-10-23: 优化 Sing-box 配置与 BBR 开启步骤。
- 2025-12-03: 二次审核，补充先决条件、安全加固与运维章节。
