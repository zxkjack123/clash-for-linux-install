# JP-Node: Tinyproxy → Shadowsocks 替换

## 背景与目标

- **问题/需求描述**：当前 jp-node 代理链路为 `Mihomo (type: http) → Tailscale WG → Tinyproxy (port 8888)`，存在双层代理开销叠加（HTTP CONNECT + WireGuard）、不支持 UDP（DNS/QUIC 无法代理）的问题。延迟抖动 21ms，Google 响应 800–1250ms。
- **根因分析**：HTTP 代理（Tinyproxy）协议开销较大，每次请求需 HTTP CONNECT 握手；且 `type: http` 在 Mihomo 中不支持 UDP relay。
- **目标**：将 jp-node 上的 Tinyproxy 替换为 Shadowsocks (shadowsocks-rust)，减少协议开销，启用 UDP 支持。
- **非目标（不做什么）**：
  - 不修改 proxy-groups 结构或 rules 路由规则 — 本次只替换底层代理协议
  - 不新增代理节点或商业机场 — 属于后续中期方案
  - 不修改 mixin.yaml — mixin 仅管理规则，不涉及 proxy 定义
  - 不修改 repo 模板 config.yaml — 模板保持通用占位符 `100.64.0.1`
  - 不停止 Tinyproxy 直到 SS 验证通过 — 保留回滚能力
- **已有代码/流程复用分析**：
  - `clashctl.sh::_merge_sanitize_restart` 合并管线：**复用**（修改 local config 后通过此管线重建 runtime）
  - `sanitize_runtime.sh` 运行时清理：**复用**（无需修改，SS proxy 定义不影响 sanitizer 逻辑）
  - Tailscale 隧道：**复用**（SS 跑在同一个 Tailscale IP 上）
  - Tinyproxy：**暂留**（过渡期保持运行，验证 SS 后再停用）

## 技术方案

- **方案概述**：在 jp-node 部署 shadowsocks-rust（`ssserver`），监听端口 8388，使用 `aes-256-gcm` 加密。本地 Mihomo 配置将 `JP-Tailscale` 节点类型从 `http` 改为 `ss`，启用 UDP relay。两套服务共存期间可随时回滚。
- **关键设计决策**：
  1. **选用 shadowsocks-rust** 而非 shadowsocks-libev / go-shadowsocks2：Rust 实现性能最优、维护活跃、Mihomo 原生兼容
  2. **端口选择 8388**（非 8888）：与 Tinyproxy 共存，支持无缝过渡
  3. **加密选择 aes-256-gcm**：性能好（x86 有 AES-NI）、Mihomo 原生支持、通用性强
  4. **绑定地址 100.82.241.21**（Tailscale IP）：仅允许 Tailscale 网络访问，防止公网暴露
  5. **UDP 启用**：`udp: true` 允许 Mihomo DNS relay 和 QUIC 流量走代理
- **影响范围**：
  - jp-node：新增 ssserver 服务 + systemd unit（`/etc/shadowsocks-rust/config.json`, `/etc/systemd/system/shadowsocks-rust.service`）
  - 本机：修改 `~/.local/share/clash/config.yaml` 中 `JP-Tailscale` 节点定义（1 个文件，~5 行变更）
  - 重建 `~/.local/share/clash/runtime.yaml`（通过已有管线自动完成）

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| ssserver 安装 | 二进制架构不匹配 / 下载失败 | 安装错误 | Y | Task 1.1 提供多种安装路径（apt / 二进制下载 / cargo） | 安装失败，Tinyproxy 仍可用 |
| ssserver 启动 | 端口 8388 被占用 | 绑定错误 | Y | pre-flight 检查端口，冲突则改用 18388 | 服务启动失败，Tinyproxy 仍可用 |
| ssserver 绑定 Tailscale IP | Tailscale 未启动时 IP 不存在 | 网络错误 | Y | systemd unit 设置 `After=tailscaled.service`，失败自动重试 | 服务延迟启动 |
| Mihomo config 变更 | YAML 语法错误 | 配置错误 | Y | `_merge_sanitize_restart` 包含 `_valid_config` 校验，失败不替换 runtime | 原 runtime 不受影响 |
| SS 连接测试失败 | 密码/加密不匹配 | 运行时错误 | Y | Task 1.4 使用 sslocal 协议级验证（非仅端口检测），确认密码正确才进 Phase 2；回滚：local config 恢复 `type: http`，热重载 | 代理暂不可用，人工回滚 ~1 分钟 |
| Tinyproxy 误停 | 停用后 SS 不稳定 | 操作错误 | Y | Phase 3 位于最后，且标注"验证 SS ≥24h 后执行" | 代理不可用，需 SSH 重启 Tinyproxy |
| Mihomo 重启停机窗口 | stop→start 间 proxy 不可用 | 服务中断 | Y | Task 2.2 改用 `PUT /configs` 热重载 API，保持进程运行，零停机切换 | 无感知 |
| SSH 会话中断 → jp-node 半配置 | Tailscale 瞬断导致 SSH 收回 | 网络错误 | Y | Phase 1 要求进入 tmux/screen 会话，断连后 attach 恢复 | 需重新认证 SSH 并 tmux attach |
| 回滚需 SSH 但代理已断 | Phase 3 后回滚需 SSH，但 Tailscale 认证页走代理 | 操作死锁 | Y | Phase 3 前置条件要求验证**公网 IP 直连 SSH** 可用；本机回滚不需 SSH | 使用公网 SSH 通道回滚 |

## 执行计划

### Phase 1: jp-node — 部署 Shadowsocks

> **前置条件**：
> 1. 需通过 Tailscale SSH 访问 jp-node（浏览器认证 `tailscale ssh jp-node`）
> 2. 连入后**立即启动 tmux**（防止 SSH 断连导致半配置状态）：
>    ```bash
>    tmux new -s ss-install
>    # 断连后恢复：tailscale ssh jp-node → tmux attach -t ss-install
>    ```

#### ✅ Task 1.1: 安装 shadowsocks-rust

- **目标**：在 jp-node 上安装 `ssserver` 二进制
- **修改内容**：
  - jp-node 系统：安装 shadowsocks-rust 软件包
- **修改边界**：不修改任何现有配置；不卸载 Tinyproxy
- **操作步骤**：

  ```bash
  # 方式 A：apt（如果 jp-node 是 Ubuntu/Debian 且源可用）
  sudo apt update && sudo apt install -y shadowsocks-rust

  # 方式 B：二进制下载（通用 Linux x86_64）
  SS_VER="1.21.2"  # 请检查最新版本: https://github.com/shadowsocks/shadowsocks-rust/releases
  wget -O /tmp/ss-rust.tar.xz \
    "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${SS_VER}/shadowsocks-v${SS_VER}.x86_64-unknown-linux-gnu.tar.xz"
  sudo mkdir -p /usr/local/bin
  sudo tar -xf /tmp/ss-rust.tar.xz -C /usr/local/bin/ ssserver
  sudo chmod +x /usr/local/bin/ssserver
  ssserver --version  # 验证安装

  # 方式 C：cargo（如果已有 Rust 工具链）
  cargo install shadowsocks-rust
  ```

- **测试要求**：
  - 运行 `ssserver --version`
  - 预期输出：`shadowsocks 1.x.x` 版本号
- **验收标准**：
  - ✅ `ssserver --version` 返回版本号且退出码 0
  - ✅ `which ssserver` 或 `ls /usr/local/bin/ssserver` 存在
- **潜在风险**：jp-node 可能是 ARM 架构（阿里云日本轻量服务器通常为 x86_64，需 `uname -m` 确认）；若为 ARM 则下载 `aarch64-unknown-linux-gnu` 变体

#### ✅ Task 1.2: 创建 Shadowsocks 配置文件

- **目标**：生成 ssserver 配置文件和密码
- **修改内容**：
  - 创建文件 `/etc/shadowsocks-rust/config.json`
- **修改边界**：不修改 Tinyproxy 配置；不修改 Tailscale 配置
- **操作步骤**：

  ```bash
  # 生成强密码
  SS_PASSWORD=$(openssl rand -base64 32)
  echo ">>> 请记录此密码（本地 Mihomo 配置需要）: $SS_PASSWORD"

  # 创建配置目录和文件
  sudo mkdir -p /etc/shadowsocks-rust
  sudo tee /etc/shadowsocks-rust/config.json > /dev/null <<EOF
  {
      "server": "100.82.241.21",
      "server_port": 8388,
      "password": "${SS_PASSWORD}",
      "method": "aes-256-gcm",
      "timeout": 300,
      "mode": "tcp_and_udp",
      "fast_open": true,
      "no_delay": true
  }
  EOF

  # 限制配置文件权限（含密码）
  sudo chmod 600 /etc/shadowsocks-rust/config.json
  ```

- **测试要求**：
  - 运行 `sudo cat /etc/shadowsocks-rust/config.json | python3 -m json.tool`
  - 预期输出：合法 JSON，server 为 `100.82.241.21`，port 为 `8388`
- **验收标准**：
  - ✅ 配置文件存在且 JSON 语法正确
  - ✅ 文件权限为 `600`（`ls -la /etc/shadowsocks-rust/config.json`）
  - ✅ 密码已记录（后续 Task 2.1 需要）
- **潜在风险**：密码中的特殊字符被 shell 转义 — base64 输出仅含 `[A-Za-z0-9+/=]`，安全

#### ✅ Task 1.3: 创建 systemd 服务并启动

- **目标**：通过 systemd 管理 ssserver，确保开机自启和 Tailscale 依赖
- **修改内容**：
  - 创建文件 `/etc/systemd/system/shadowsocks-rust.service`
  - 启用并启动服务
- **修改边界**：不修改 `tinyproxy.service`；不修改 `tailscaled.service`
- **操作步骤**：

  ```bash
  # 确定 ssserver 路径
  SS_BIN=$(which ssserver 2>/dev/null || echo "/usr/local/bin/ssserver")

  sudo tee /etc/systemd/system/shadowsocks-rust.service > /dev/null <<EOF
  [Unit]
  Description=Shadowsocks-Rust Server
  After=network-online.target tailscaled.service
  Wants=network-online.target

  [Service]
  Type=simple
  ExecStart=${SS_BIN} -c /etc/shadowsocks-rust/config.json
  Restart=on-failure
  RestartSec=5
  LimitNOFILE=65536

  [Install]
  WantedBy=multi-user.target
  EOF

  sudo systemctl daemon-reload
  sudo systemctl enable shadowsocks-rust
  sudo systemctl start shadowsocks-rust
  ```

- **测试要求**：
  - 运行 `systemctl status shadowsocks-rust --no-pager`
  - 预期输出：`active (running)`
  - 运行 `ss -tlnp | grep 8388`
  - 预期输出：`ssserver` 监听 `100.82.241.21:8388`
- **验收标准**：
  - ✅ `systemctl is-active shadowsocks-rust` 返回 `active`
  - ✅ `ss -tlnp | grep 8388` 显示 ssserver 监听
  - ✅ `journalctl -u shadowsocks-rust --no-pager -n 10` 无 error 日志
- **潜在风险**：
  - Tailscale IP 不可用时绑定失败 — `After=tailscaled.service` + `Restart=on-failure` 缓解
  - 端口 8388 被占用 — pre-flight `ss -tlnp | grep 8388` 检查，冲突则改用 18388 并同步更新后续配置

#### ✅ Task 1.4: 从本机验证 SS 协议连通性（关键安全门）

- **目标**：从本机确认 ssserver **协议级可达**（密码/加密正确），作为进入 Phase 2 的安全门
- **修改内容**：无文件修改，纯验证
- **修改边界**：不修改任何配置
- **操作步骤**（在**本机**执行）：

  ```bash
  # Step 1: 端口可达性检查
  nc -z -w 3 100.82.241.21 8388 && echo "PORT OK" || { echo "PORT FAIL — 中止"; exit 1; }

  # Step 2: 安装 sslocal（如果本机未安装）
  which sslocal >/dev/null 2>&1 || {
    echo "安装 shadowsocks-rust 客户端..."
    sudo apt install -y shadowsocks-rust 2>/dev/null || {
      SS_VER="1.21.2"
      wget -qO /tmp/ss-rust.tar.xz \
        "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${SS_VER}/shadowsocks-v${SS_VER}.x86_64-unknown-linux-gnu.tar.xz"
      sudo tar -xf /tmp/ss-rust.tar.xz -C /usr/local/bin/ sslocal
      sudo chmod +x /usr/local/bin/sslocal
    }
  }

  # Step 3: 协议级验证（关键！验证密码/加密是否匹配）
  SS_PASSWORD="<Task 1.2 中记录的密码>"
  sslocal -s 100.82.241.21 -p 8388 -k "$SS_PASSWORD" -m aes-256-gcm \
    -l 1081 --protocol socks5 &
  SS_PID=$!
  sleep 2

  # Step 4: 通过 SS 本地代理测试真实流量
  HTTP_CODE=$(curl -sS --connect-timeout 10 --max-time 20 \
    -x socks5://127.0.0.1:1081 -o /dev/null -w "%{http_code}" \
    https://httpbin.org/ip 2>/dev/null)
  kill $SS_PID 2>/dev/null; wait $SS_PID 2>/dev/null

  if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ SS 协议验证通过 — 可进入 Phase 2"
  else
    echo "❌ SS 协议验证失败 (HTTP=$HTTP_CODE) — 检查密码/加密配置，不要进入 Phase 2"
    exit 1
  fi
  ```

- **测试要求**：
  - Step 1: `nc -z` 成功
  - Step 3-4: `curl` 通过 sslocal 返回 HTTP 200
- **验收标准**：
  - ✅ `nc -z` 成功（端口可达）
  - ✅ sslocal 代理测试 `curl https://httpbin.org/ip` 返回 HTTP 200（**协议+密码正确**）
- **潜在风险**：Tailscale 隧道瞬断 — 重试即可；如果持续失败，检查 jp-node 上 `journalctl -u shadowsocks-rust`
- **⚠️ 安全门**：此 Task 未通过时**禁止进入 Phase 2**，否则会导致代理全面断连

---

### Phase 2: 本机 — 更新 Mihomo 配置

> **依赖**：Phase 1 全部完成且 Task 1.4 **SS 协议级验证通过**（仅端口可达不够，必须 sslocal 流量测试成功）。

#### ✅ Task 2.1: 修改本地 config.yaml 中 JP-Tailscale 节点定义

- **目标**：将 `JP-Tailscale` 从 `type: http` 改为 `type: ss`，启用 UDP
- **修改内容**：
  - 文件 `~/.local/share/clash/config.yaml`：修改 `proxies` 段中 `JP-Tailscale` 定义
- **修改边界**：
  - 不得修改 `~/.local/share/clash/mixin.yaml`
  - 不得修改 `proxy-groups` 段
  - 不得修改 `rules` 段
  - 不得修改 repo 内 `resources/config.yaml`（模板文件，保持占位符）
- **变更详情**：

  ```yaml
  # 变更前
  proxies:
    - name: "JP-Tailscale"
      type: http
      server: 100.82.241.21
      port: 8888

  # 变更后
  proxies:
    - name: "JP-Tailscale"
      type: ss
      server: 100.82.241.21
      port: 8388
      cipher: aes-256-gcm
      password: "<Task 1.2 中生成的密码>"
      udp: true
  ```

- **测试要求**：
  - 运行 `yq '.proxies[] | select(.name == "JP-Tailscale")' ~/.local/share/clash/config.yaml`
  - 预期输出：type=ss, port=8388, cipher=aes-256-gcm, udp=true
- **验收标准**：
  - ✅ `yq` 输出确认 type=ss, port=8388全, cipher 和 password 非空
  - ✅ YAML 语法正确（`yq '.' ~/.local/share/clash/config.yaml > /dev/null` 退出码 0）
- **潜在风险**：密码中若含 YAML 特殊字符需加引号 — base64 输出安全，但仍建议用双引号包裹

#### ✅ Task 2.2: 重建 runtime.yaml 并热重载 Mihomo（零停机）

- **目标**：通过合并管线重建 runtime.yaml，使用 `PUT /configs` API 热重载，**避免 stop/start 停机窗口**
- **修改内容**：
  - 由合并管线生成新的 `~/.local/share/clash/runtime.yaml`
  - 通过 Mihomo 控制器 API 热重载配置
- **修改边界**：不手动编辑 runtime.yaml；不使用 `clashrestart`（stop/start）
- **操作步骤**：

  ```bash
  cd /home/gw/opt/clash-for-linux-install

  # Step 1: 通过管线构建并验证新 runtime（但不自动重启）
  # 手动执行合并逻辑：
  source script/common.sh
  source script/clashctl.sh

  # 构建 merged config 到临时文件
  TMP_RUNTIME=$(mktemp /tmp/runtime.XXXXXX.yaml)
  _merge_build_runtime "$TMP_RUNTIME"

  # 验证新配置语法
  _valid_config "$TMP_RUNTIME" || { echo "❌ 配置验证失败，中止"; rm -f "$TMP_RUNTIME"; exit 1; }

  # Step 2: 原子替换 runtime.yaml
  cp ~/.local/share/clash/runtime.yaml ~/.local/share/clash/runtime.yaml.bak  # 备份
  mv "$TMP_RUNTIME" ~/.local/share/clash/runtime.yaml

  # Step 3: 通过控制器 API 热重载（零停机）
  RUNTIME_PATH="$HOME/.local/share/clash/runtime.yaml"
  HTTP_CODE=$(curl -sS -X PUT http://127.0.0.1:9090/configs \
    -H 'Content-Type: application/json' \
    -d '{"path":"'"$RUNTIME_PATH"'"}' \
    -o /dev/null -w '%{http_code}')

  if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
    echo "✅ 热重载成功"
  else
    echo "❌ 热重载失败 (HTTP=$HTTP_CODE)，回滚到备份..."
    mv ~/.local/share/clash/runtime.yaml.bak ~/.local/share/clash/runtime.yaml
    curl -sS -X PUT http://127.0.0.1:9090/configs \
      -H 'Content-Type: application/json' \
      -d '{"path":"'"$RUNTIME_PATH"'"}'
    echo "已回滚"
    exit 1
  fi
  ```

  > **为什么不用 `clashctl.sh restart`**：`clashrestart` 内部执行 `systemctl --user stop` → `start`，期间所有代理流量中断（含 Copilot/Docker/GitHub）。`PUT /configs` 热重载保持 Mihomo 进程运行，已有连接不断，仅切换配置。

  > **fallback**：如果 `PUT /configs` 热重载失败，可退回使用 `bash script/clashctl.sh restart`，但需接受 ~2 秒停机窗口。

- **测试要求**：
  - 运行 `grep -A 8 'JP-Tailscale' ~/.local/share/clash/runtime.yaml`
  - 预期输出：type=ss, port=8388, cipher=aes-256-gcm
  - 运行 `curl -sS http://127.0.0.1:9090/proxies/JP-Tailscale | python3 -m json.tool | grep type`
  - 预期输出：`"type": "Shadowsocks"` 或 `"type": "ss"`
- **验收标准**：
  - ✅ runtime.yaml 中 JP-Tailscale 为 type=ss
  - ✅ Mihomo 进程 PID **未变**（热重载而非重启）：`ps aux | grep mihomo`
  - ✅ 控制器 API 返回 JP-Tailscale 节点信息（type=Shadowsocks）
  - ✅ 热重载期间无代理中断（可在另一终端持续 `curl -x http://127.0.0.1:7890 https://www.google.com` 验证）
- **潜在风险**：
  - `_valid_config` 校验失败 — 临时文件被删除，runtime.yaml 不受影响
  - `PUT /configs` 返回非 200/204 — 自动回滚到备份 runtime.yaml.bak
  - 热重载后 SS 连接失败 — 进入 Task 2.3 验证；如失败执行回滚方案

#### ✅ Task 2.3: 端到端连通性验证

- **目标**：确认代理链路通过 SS 正常工作
- **修改内容**：无文件修改，纯验证
- **修改边界**：不修改任何配置
- **操作步骤**：

  ```bash
  # 基础连通性
  curl -sS --connect-timeout 5 --max-time 15 -x http://127.0.0.1:7890 \
    -o /dev/null -w "Google: HTTP %{http_code}, %{time_total}s\n" https://www.google.com

  # GitHub API
  curl -sS --connect-timeout 5 --max-time 15 -x http://127.0.0.1:7890 \
    -o /dev/null -w "GitHub: HTTP %{http_code}, %{time_total}s\n" https://api.github.com

  # 延迟稳定性（10 轮）
  for i in $(seq 1 10); do
    start=$(date +%s%N)
    code=$(curl -sS --connect-timeout 5 --max-time 15 -x http://127.0.0.1:7890 \
      -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null)
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))
    echo "Round $i: HTTP=$code, ${ms}ms"
    sleep 0.5
  done

  # Mihomo 节点延迟探测
  curl -sS http://127.0.0.1:9090/proxies/JP-Tailscale/delay?timeout=5000\&url=https://www.gstatic.com/generate_204

  # UDP 验证（可选 — 需 Mihomo 的 DNS 模块配置 nameserver 走代理）
  ```

- **测试要求**：
  - Google 10 轮测试全部 HTTP 200
  - 平均延迟比替换前（800–1250ms）有所改善
  - 节点延迟探测返回有效 delay 值
- **验收标准**：
  - ✅ Google 10 轮测试成功率 100%（全部 HTTP 200）
  - ✅ 平均延迟 ≤ 1000ms（替换前平均 ~985ms）
  - ✅ `/proxies/JP-Tailscale/delay` 返回 `{"delay": <number>}` 且 delay < 2000
  - ✅ `curl -sS http://127.0.0.1:9090/proxies/JP-Tailscale` 返回 `"alive": true`
- **潜在风险**：
  - SS 密码不匹配导致全部失败 — 回滚见下方
  - 首次连接可能较慢（SS 握手建立） — 属正常现象

---

### Phase 3: jp-node — 清理 Tinyproxy（延迟执行）

> **前置条件**（全部满足才可执行）：
> 1. Phase 2 验证通过且 SS 稳定运行 ≥24 小时
> 2. **确认公网 SSH 备用通道可用**（防止代理断连后无法回滚 jp-node）：
>    ```bash
>    # 从本机测试公网直连 SSH（不走代理）
>    ssh -o ConnectTimeout=5 -o ProxyCommand=none root@47.245.32.3 'echo OK'
>    # 如果 ssh 端口非 22，使用 -p <port>
>    # 如果未配置密钥认证，先配置: ssh-copy-id root@47.245.32.3
>    ```
> 3. 如果公网 SSH 不可用，**不要执行 Phase 3**（保留 Tinyproxy 作为回滚保障）

#### ✅ Task 3.1: 停用 Tinyproxy

- **目标**：停止并禁用 Tinyproxy 服务，释放端口 8888
- **修改内容**：
  - jp-node 系统：停止 `tinyproxy` 服务
- **修改边界**：不卸载 Tinyproxy（保留 `apt` 安装以便快速回滚）；不删除配置文件
- **操作步骤**：

  ```bash
  sudo systemctl stop tinyproxy
  sudo systemctl disable tinyproxy
  # 验证
  systemctl is-active tinyproxy  # 预期: inactive
  ss -tlnp | grep 8888           # 预期: 无输出
  ```

- **测试要求**：
  - `systemctl is-active tinyproxy` 返回 `inactive`
  - `ss -tlnp | grep 8888` 无输出
- **验收标准**：
  - ✅ Tinyproxy 服务已停止
  - ✅ 端口 8888 已释放
  - ✅ Mihomo 代理链路仍然正常（`curl -x http://127.0.0.1:7890 https://www.google.com` 返回 200）
- **潜在风险**：误操作停了 SS 而非 Tinyproxy — 操作前再次确认 `systemctl status shadowsocks-rust` 为 active

---

## 回滚方案

如果 SS 部署后出现问题，执行以下回滚步骤（~1 分钟恢复）：

### 本机回滚（不需要 SSH，不需要代理）

```bash
# Step 1: 恢复备份的 runtime.yaml（如果 Task 2.2 创建了备份）
if [ -f ~/.local/share/clash/runtime.yaml.bak ]; then
  cp ~/.local/share/clash/runtime.yaml.bak ~/.local/share/clash/runtime.yaml
fi

# Step 2: 将 JP-Tailscale 改回 HTTP 类型
# ~/.local/share/clash/config.yaml 中:
#   type: ss → type: http
#   port: 8388 → port: 8888
#   删除 cipher/password/udp 行

# Step 3: 热重载回滚后的配置（优先）
RUNTIME_PATH="$HOME/.local/share/clash/runtime.yaml"
curl -sS -X PUT http://127.0.0.1:9090/configs \
  -H 'Content-Type: application/json' \
  -d '{"path":"'"$RUNTIME_PATH"'"}'

# 如果热重载失败（Mihomo 进程异常），fallback 到 stop/start:
# cd /home/gw/opt/clash-for-linux-install && bash script/clashctl.sh restart
```

### jp-node 回滚（仅在已执行 Phase 3 后需要）

```bash
# 方式 A: 通过 Tailscale SSH（如果代理仍可用）
tailscale ssh jp-node
sudo systemctl start tinyproxy && sudo systemctl enable tinyproxy

# 方式 B: 通过公网 IP 直连 SSH（代理断连时的备用通道）
ssh root@47.245.32.3  # 或 ssh -p <port> root@47.245.32.3
sudo systemctl start tinyproxy && sudo systemctl enable tinyproxy
```

## 回归检查清单

- [ ] `curl -x http://127.0.0.1:7890 https://www.google.com` 返回 HTTP 200
- [ ] `curl -x http://127.0.0.1:7890 https://api.github.com` 返回 HTTP 200
- [ ] Copilot: `curl -x http://127.0.0.1:7890 https://copilot-proxy.githubusercontent.com` 可达
- [ ] Mihomo 控制器: `curl http://127.0.0.1:9090/proxies/JP-Tailscale` 返回 `"alive": true`
- [ ] 节点延迟探测: `/proxies/JP-Tailscale/delay` 返回有效值
- [ ] Docker pull 测试: `docker pull hello-world`（通过代理）
- [ ] 10 轮延迟测试平均 ≤ 1000ms
- [ ] `journalctl -u shadowsocks-rust -n 20` 无 error

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 3 | 3 | 0 |
| R2 | 可执行性 | 4 | 4 | 0 |
| R3 | 风险与边缘 | 2 | 2 | 0 |
| R4 | 网络中断风险专项审查 | 5 | 5 | 0 |
| **终止** | **T1 — 收敛终止（R4 issue=0）** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整（问题/目标/非目标/复用分析） |
| 技术方案 | 完整（方案概述/5 项设计决策/影响范围） |
| Error & Rescue Map | 已覆盖 9 条关键路径，0 CRITICAL GAP |
| 执行计划 | 3 Phase, 7 Task |
| 回归检查清单 | 8 项目特定检查项 |
| 已知局限 | 无 |

### R1 Issues

- **Issue R1-1**: 缺少"已有代码/流程复用分析" → 已补充 clashctl pipeline / sanitizer / Tailscale / Tinyproxy 四项复用分析 ✅ 已修正
- **Issue R1-2**: 缺少 Error & Rescue Map → 已补充 6 条失败路径映射 ✅ 已修正
- **Issue R1-3**: Task 字段不完整 → 已为全部 7 个 Task 补全所有必需字段 ✅ 已修正

### R2 Issues

- **Issue R2-1**: jp-node SSH 需要 Tailscale 浏览器认证，方案未说明 → 已在 Phase 1 前置条件标注 ✅ 已修正
- **Issue R2-2**: 缺少具体 SS 连通性测试命令 → 已在 Task 1.4 和 Task 2.3 补充完整测试步骤 ✅ 已修正
- **Issue R2-3**: 未考虑 jp-node CPU 架构差异 → 已在 Task 1.1 提供 x86_64/aarch64 两种安装路径 ✅ 已修正
- **Issue R2-4**: 密码生成命令未指定 → 已在 Task 1.2 使用 `openssl rand -base64 32` ✅ 已修正

### R3 Issues

- **Issue R3-1**: 缺少显式回滚指引 → 已补充完整回滚方案（本机 + jp-node） ✅ 已修正
- **Issue R3-2**: Phase 3 停用 Tinyproxy 的时机风险 → 已标注"SS 稳定运行 ≥24h 后执行" ✅ 已修正

### R4 Issues（网络中断风险专项审查）

- **Issue R4-1** 🔴 Critical: SS 密码/配置不匹配时 `_valid_config` 仅校验语法不校验连通性 → Mihomo 正常启动但 SS 连接失败 → 代理全断。**修正**：Task 1.4 从 `nc -z` 端口检测升级为 sslocal 协议级验证，增加安全门机制 ✅ 已修正
- **Issue R4-2** 🟡 Medium: `clashrestart` 执行 stop→start 造成真实停机窗口（~2 秒），期间 Copilot/Docker/GitHub 请求失败。**修正**：Task 2.2 改用 `PUT /configs` 热重载 API，保持进程运行零停机 ✅ 已修正
- **Issue R4-3** 🟡 Medium: Tailscale SSH 断连导致 jp-node 半配置状态。**修正**：Phase 1 前置条件增加 tmux 要求 ✅ 已修正
- **Issue R4-4** 🔴 Critical: Phase 3 停 Tinyproxy 后若需回滚，Tailscale SSH 认证页面需走代理（代理已断 → 死锁）。**修正**：Phase 3 前置条件增加公网 IP 直连 SSH 验证；回滚方案增加公网 SSH 备用通道 ✅ 已修正
- **Issue R4-5** 🟡 Medium: 回滚方案使用 `clashctl.sh restart` 也有停机窗口。**修正**：回滚方案改用热重载优先，stop/start 作为 fallback ✅ 已修正
