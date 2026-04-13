# US 节点部署与本地服务改造方案

## 背景与目标

- **问题/需求描述**：新购美西节点（阿里云 LA，43.110.32.131），需部署 Tailscale + Shadowsocks-Rust 代理服务，并改造本地 mihomo 配置以支持双节点自动切换，解决 JP 节点不稳定和 AI 服务延迟高的问题。
- **根因分析**：
  - JP 节点 Tailscale P2P 直连频繁掉线（NAT 类型 `varies` 每天抖动 200~600 次），回退 DERP 中继后延迟暴增至 1~4s
  - JP 出口访问 api.openai.com SSL 握手失败（疑似 IP 封锁）
  - 单节点架构无自动容灾能力
- **目标**：
  1. 在 US 节点部署与 JP 节点相同架构的代理服务（Tailscale 隧道 + Shadowsocks-Rust）
  2. 改造本地 mihomo 配置，将 COPILOT/VSCODE/DEV 流量切换为 US 节点优先、JP 节点备份的 fallback 模式
  3. 验证端到端连通性和延迟改善
- **非目标（不做什么）**：
  - 不修改 JP 节点现有配置 — JP 节点保持运行，作为备份
  - 不修改 mihomo 核心代码或 clashctl 脚本 — 仅修改 config.yaml/mixin.yaml 声明式配置
  - 不做 SSH 安全加固（改端口/禁密码登录）— 留到后续独立任务

- **已有代码/流程复用分析**：
  - JP 节点 shadowsocks-rust 用户态 systemd 服务：**复用**（直接复制 unit 文件和二进制到 US 节点）
  - JP 节点 Tailscale 安装流程：**复用**（相同 apt 源安装方法）
  - mihomo config.yaml proxy/proxy-group 结构：**复用**（在现有结构上增加 US-Tailscale proxy 条目）
  - ssserver 二进制：**复用**（同为 x86_64 Debian 12，可直接 scp）
  - JP 节点 SS 密码：**不复用**（US 节点独立生成新密码）

## 技术方案

- **方案概述**：US 节点复刻 JP 节点的 "Tailscale mesh + ssserver on Tailscale IP" 架构。本地 mihomo 添加 `US-Tailscale` proxy 条目，将 AI 相关 proxy-group 改为 fallback 类型，US 优先。
- **关键设计决策**：
  - SS 监听在 Tailscale IP（100.x.x.x:8388），不暴露在公网——与 JP 一致
  - 使用 `aes-256-gcm` 加密，与 JP 一致
  - Tailscale 配置 `--advertise-exit-node` + `ip_forward=1`
  - 本地 proxy-group 使用 `fallback` 类型（非 `url-test`），避免频繁探测造成不必要流量
  - ssserver 以 gw 用户态 systemd 服务运行（`systemctl --user`）
- **影响范围**：
  - 新增/修改文件（US 节点）：
    - `/home/gw/.local/bin/ssserver`（二进制复制）
    - `/home/gw/.config/shadowsocks-rust/config.json`（新建）
    - `/home/gw/.config/systemd/user/shadowsocks-rust.service`（新建）
    - `/swapfile`（新建 swap）
    - `/etc/sysctl.d/99-tailscale.conf`（ip_forward）
  - 修改文件（本地）：
    - `resources/config.yaml`（添加 US-Tailscale proxy，修改 proxy-groups）

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| SSH 到 US 节点 | 中国→US 直连超时 | 网络 | Y | 使用 sshpass + 多次重试；部署完 Tailscale 后切换到 TS IP | SSH 命令超时，需重试 |
| Tailscale auth | authkey 过期或无效 | 认证 | Y | 预先生成 reusable authkey；失败时回退浏览器登录 | tailscale up 报错 |
| ssserver 端口冲突 | 8388 已被占用 | 端口 | Y | 预检查 ss -tlnp | 服务启动失败 |
| Tailscale 未分配 IP | 网络初始化未完成 | 时序 | Y | sleep + 轮询 tailscale ip | 后续步骤拿不到 Tailscale IP |
| scp 二进制到 US 失败 | SSH 断线 | 网络 | Y | 改用 wget 从 GitHub releases 下载 | 部署中断，需重试 |
| mihomo 配置语法错误 | YAML 格式错误 | 配置 | Y | 修改前备份，clash_diagnose.sh 验证 | mihomo 启动失败，用备份恢复 |
| US→Copilot 不通 | US 出口 IP 也被封 | 网络 | Y | 验证阶段检测到后报告 | AI 服务仍走 JP 节点（fallback） |

## 执行计划

### Phase 1: US 节点基础环境

#### ✅ Task 1.1: 添加 Swap
- **目标**：为 US 节点创建 512MB swap，防止 Tailscale 内存峰值导致 OOM
- **修改内容**：
  - 在 US 节点创建 `/swapfile`（512MB），启用并写入 `/etc/fstab`
- **修改边界**：不修改其他系统文件
- **测试要求**：
  - 运行 `free -h`
  - 预期输出：Swap 行显示 `511Mi` total
  - 运行 `grep swap /etc/fstab`
  - 预期输出：包含 `/swapfile none swap sw 0 0`
- **验收标准**：
  - ✅ `swapon --show` 显示 `/swapfile` 大小为 512M
  - ✅ `/etc/fstab` 包含 swap 持久化条目
- **潜在风险**：磁盘空间不足（当前 26GB 可用，不构成问题）

#### ✅ Task 1.2: 安装 Tailscale
- **目标**：在 US 节点安装 Tailscale 并加入 Tailnet，配置为 exit node
- **修改内容**：
  - 通过官方脚本安装 Tailscale：`curl -fsSL https://tailscale.com/install.sh | sh`
  - 配置 IP 转发：写入 `/etc/sysctl.d/99-tailscale.conf`
    ```
    net.ipv4.ip_forward = 1
    net.ipv6.conf.all.forwarding = 1
    ```
  - 执行 `sysctl -p /etc/sysctl.d/99-tailscale.conf`
  - 执行 `tailscale up --advertise-exit-node --hostname=us-node`
    - 需要预先在 Tailscale admin console 生成 auth key，或通过浏览器 URL 认证
- **修改边界**：不修改 `/etc/sysctl.conf`（使用 drop-in 文件）；不修改防火墙规则
- **测试要求**：
  - 在本地运行 `tailscale status` 并检查 `us-node` 是否出现
  - 在本地运行 `tailscale ping <US-TS-IP>` 验证连通性
  - 预期输出：`pong from us-node (100.x.x.x) via <direct-ip> in <N>ms`
- **验收标准**：
  - ✅ `tailscale status` 在本地可见 `us-node`，状态为 `active; offers exit node`
  - ✅ `tailscale ping` 延迟 < 300ms
  - ✅ `cat /proc/sys/net/ipv4/ip_forward` 返回 `1`
- **潜在风险**：
  - Tailscale 安装脚本需要外网访问（US 节点自身须能访问 pkgs.tailscale.com）——US 节点在美国，无需翻墙
  - 如果 authkey 方式认证失败，需要在终端打开 URL 手动确认——SSH 连接不稳定时比较麻烦

#### ✅ Task 1.3: 安装 Shadowsocks-Rust (ssserver)
- **目标**：在 US 节点以 gw 用户部署 shadowsocks-rust，监听 Tailscale IP
- **修改内容**：
  - 下载 shadowsocks-rust v1.21.2 预编译二进制到 `/home/gw/.local/bin/ssserver`
    - 来源：`https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.21.2/shadowsocks-v1.21.2.x86_64-unknown-linux-gnu.tar.xz`
    - 备选：从 JP 节点通过 Tailscale scp 复制（`scp gw@100.82.241.21:~/.local/bin/ssserver /home/gw/.local/bin/ssserver`）
  - 创建配置文件 `/home/gw/.config/shadowsocks-rust/config.json`：
    ```json
    {
      "server": "<US-Tailscale-IP>",
      "server_port": 8388,
      "password": "<新生成的 base64 密码>",
      "method": "aes-256-gcm",
      "timeout": 300,
      "mode": "tcp_and_udp",
      "fast_open": true,
      "no_delay": true
    }
    ```
    - 密钥生成：`openssl rand -base64 32`
    - `server` 字段填写 Task 1.2 中 Tailscale 分配的 100.x.x.x IP
  - 创建 systemd 用户服务 `/home/gw/.config/systemd/user/shadowsocks-rust.service`：
    ```ini
    [Unit]
    Description=Shadowsocks-Rust Server (user)
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    ExecStart=%h/.local/bin/ssserver -c %h/.config/shadowsocks-rust/config.json
    Restart=on-failure
    RestartSec=5
    LimitNOFILE=65536

    [Install]
    WantedBy=default.target
    ```
  - 启用 lingering：`sudo loginctl enable-linger gw`
  - 启动服务：`systemctl --user daemon-reload && systemctl --user enable --now shadowsocks-rust`
- **修改边界**：所有文件在 `/home/gw/` 下；不修改系统级服务或其他用户配置
- **测试要求**：
  - 运行 `systemctl --user status shadowsocks-rust`
  - 预期输出：`Active: active (running)`
  - 运行 `ss -tlnp | grep 8388`
  - 预期输出：显示 ssserver 监听在 `<US-TS-IP>:8388`
  - 从本地通过 Tailscale 测试：`curl --socks5 <US-TS-IP>:8388 ...`（不直接可用，需 SS 客户端测试）
- **验收标准**：
  - ✅ `systemctl --user is-active shadowsocks-rust` 返回 `active`
  - ✅ `ss -tlnp | grep 8388` 显示 ssserver 监听在 Tailscale IP
  - ✅ ssserver 进程以 gw 用户运行（`ps aux | grep ssserver | grep gw`）
- **潜在风险**：
  - Tailscale IP 未就绪时 ssserver 绑定失败——Task 1.2 完成确认后再执行
  - 二进制下载可能因 GitHub 访问问题中断——备选方案：从 JP 节点 scp

### Phase 2: 本地 mihomo 配置改造

#### ✅ Task 2.1: 修改 config.yaml 添加 US 节点
- **目标**：在本地 mihomo 配置中添加 US-Tailscale proxy 条目，修改 proxy-groups 为双节点 fallback
- **修改内容**：
  - 文件 `resources/config.yaml`：
    1. 在 `proxies:` 部分**替换**现有 JP-Tailscale 定义为 SS 类型（当前 repo 中是 http 占位），并**新增** US-Tailscale：
       ```yaml
       proxies:
         - name: "JP-Tailscale"
           type: ss
           server: 100.82.241.21
           port: 8388
           cipher: aes-256-gcm
           password: "<JP节点密码>"
           udp: true

         - name: "US-Tailscale"
           type: ss
           server: <US-Tailscale-IP>
           port: 8388
           cipher: aes-256-gcm
           password: "<US节点密码>"
           udp: true
       ```
    2. 修改 `proxy-groups:` 部分：
       - `PROXY`：添加 `US-Tailscale` 选项
       - `COPILOT`：改为 `fallback` 类型，US 优先
       - `VSCODE`：保持 `fallback` 类型，添加 `US-Tailscale`
       - `DEV`：改为 `fallback` 类型，US 优先
       - `DOCKER`：添加 `US-Tailscale` 选项
       - `ACADEMIC`：保持不变（DIRECT 优先）
- **修改边界**：
  - 不修改 `rules:` 部分
  - 不修改 `mixin.yaml`
  - 不修改 `script/` 下任何文件
- **测试要求**：
  - 运行 `python3 -c "import yaml; yaml.safe_load(open('resources/config.yaml'))"`
  - 预期输出：无报错（YAML 语法正确）
  - 运行 `bash script/clash_diagnose.sh --fast --json 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('status','?'))"`
  - 预期输出：`OK` 或无严重错误
- **验收标准**：
  - ✅ config.yaml YAML 语法检查通过
  - ✅ `proxies` 中包含 `JP-Tailscale` 和 `US-Tailscale` 两个 SS 类型 proxy
  - ✅ `COPILOT` 组为 `fallback` 类型，proxies 列表中 `US-Tailscale` 在 `JP-Tailscale` 之前
  - ✅ `VSCODE` 组为 `fallback` 类型，proxies 列表中 `US-Tailscale` 在首位
- **潜在风险**：
  - 密码中含特殊字符导致 YAML 解析失败——使用 base64 编码密码，仅含 `[A-Za-z0-9+/=]`
  - 订阅更新可能覆盖 config.yaml——mixin.yaml 有更高优先级，但 proxies 定义目前只在 config.yaml

### Phase 3: 端到端验证

#### ✅ Task 3.1: 验证 Tailscale 连通性
- **目标**：确认本地到 US 节点 Tailscale 直连、延迟和稳定性
- **修改内容**：无（纯验证）
- **修改边界**：不修改任何文件
- **测试要求**：
  - 运行 `tailscale ping -c 5 <US-TS-IP>`
  - 预期输出：5 次全部 pong，延迟 < 300ms，显示 `via <direct-ip>` 而非 `via DERP`
  - 运行 `tailscale status | grep us-node`
  - 预期输出：`active; offers exit node; direct <IP>`
- **验收标准**：
  - ✅ Tailscale P2P 直连建立（非 DERP 中继）
  - ✅ 平均延迟 < 300ms
  - ✅ 5 次 ping 无丢包
- **潜在风险**：与 JP 同样的 NAT 穿透问题——但中国→US 的 UDP 通常比中国→JP 更通畅

#### Task 3.2: 验证代理链路和 AI 服务延迟
- **目标**：确认通过 US-Tailscale 出口访问 Copilot/GitHub/OpenAI 的延迟显著优于 JP 节点
- **修改内容**：无（纯验证）
- **修改边界**：不修改任何文件
- **测试要求**：
  - 重载 mihomo 配置后，在控制器中确认 `US-Tailscale` 节点存在
  - 运行延迟测试（通过控制器 API）：
    ```bash
    curl -s "http://127.0.0.1:9090/proxies/US-Tailscale/delay?timeout=5000&url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204"
    ```
  - 预期输出：`{"delay": <200}`
  - 手动切换 COPILOT 组到 US-Tailscale，测试：
    ```bash
    curl -w "TTFB=%{time_starttransfer}s" -x 127.0.0.1:7890 https://copilot-proxy.githubusercontent.com/_ping
    ```
  - 预期输出：TTFB < 0.3s
  - 测试 OpenAI（之前 JP 节点 SSL 失败）：
    ```bash
    curl -w "HTTP=%{http_code}" -x 127.0.0.1:7890 https://api.openai.com
    ```
  - 预期输出：HTTP 状态码非 000（不再 SSL 错误）
- **验收标准**：
  - ✅ US-Tailscale 节点延迟 < 300ms（控制器 delay API）
  - ✅ Copilot proxy TTFB < 300ms（通过 US 出口）
  - ✅ api.openai.com 不再出现 SSL_ERROR_SYSCALL
  - ✅ fallback 自动切换验证：临时停止 US ssserver → 60s 内 COPILOT 组自动切换到 JP-Tailscale
- **潜在风险**：US 节点出口 IP 也可能被某些服务封锁——验证阶段发现后评估是否需要调整

## 回归检查清单

- [ ] `tailscale status` 同时显示 `jp-node` 和 `us-node`，两者均 active
- [ ] JP 节点 ssserver 未受影响：`ssh 100.82.241.21 "systemctl --user is-active shadowsocks-rust"` 返回 `active`
- [ ] mihomo 控制器 `/proxies` 同时包含 `JP-Tailscale` 和 `US-Tailscale`
- [ ] COPILOT 组 fallback 链路正确：US 在前，JP 在后
- [ ] `curl -x 127.0.0.1:7890 https://www.baidu.com`（DIRECT 规则仍正常）
- [ ] `script/clash_diagnose.sh --fast` 无新增严重错误
- [ ] 本地 `resources/config.yaml` YAML 语法正确
- [ ] US 节点 ssserver 以 gw 用户运行，非 root

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 3 | 3 | 0 |
| R2 | 可执行性 | 2 | 2 | 0 |
| R3 | 风险与边缘 | 1 | 1 | 0 |
| **终止** | **T1 — 收敛终止** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整 |
| 技术方案 | 完整 |
| Error & Rescue Map | 7 条路径已覆盖，0 CRITICAL GAP |
| 执行计划 | 3 Phase、6 Task |
| 回归检查清单 | 8 项（含项目特定检查） |
| 已知局限 | 无 |

### R1 Issues（结构完整性）
- **Issue R1-1**: Error & Rescue Map 缺失 → 已补充完整映射表 ✅ 已修正
- **Issue R1-2**: 已有代码/流程复用分析缺失 → 已补充复用 vs 重建分析 ✅ 已修正
- **Issue R1-3**: Task 1.2 缺少 authkey 获取步骤的具体操作 → 已在修改内容中说明两种认证方式 ✅ 已修正

### R2 Issues（可执行性）
- **Issue R2-1**: Task 1.3 依赖 Task 1.2 的 Tailscale IP 但未明确标注 → 已在潜在风险中标注时序依赖 ✅ 已修正
- **Issue R2-2**: Task 2.1 密码占位符不可直接复制执行 → 已说明密码来源和生成方法，实际值在执行时填入 ✅ 已修正

### R3 Issues（风险与边缘）
- **Issue R3-1**: 订阅更新覆盖 config.yaml 的风险未评估 → 已在 Task 2.1 潜在风险中补充说明 ✅ 已修正
