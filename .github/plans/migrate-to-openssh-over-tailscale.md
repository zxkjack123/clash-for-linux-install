# Migrate from Tailscale SSH to OpenSSH over Tailscale

## 背景与目标

- **问题/需求描述**：Tailscale SSH 在 control plane / Magic DNS 不稳定时会挂起（已被 Task 3.2 阻塞复现）。Windows 客户端对 Tailscale SSH 支持差，多平台体验不一致。希望切换到"Tailscale 提供网络层 + OpenSSH 提供认证层"的更稳健方案。
- **审阅来源**：用户决策（在比较两方案后采纳 OpenSSH over Tailscale）。
- **关键发现（2026-04-22 Task 1.4 验证）**：Tailscale `--ssh` flag 在 tailnet IP 的 22 端口上做 userspace 拦截，sshd 即使监听 `0.0.0.0:22` 也收不到连接。**这意味着 OpenSSH 与 Tailscale SSH 在同一端口上无法共存**。采纳**方案 B**：sshd 增开 **2222 端口**，两者分端口共存。
- **目标**：
  - 在所有常用节点（jp-node、us-node、SynologyNAS923 等）让 sshd 在 **Tailscale 接口的 2222 端口**额外监听
  - 本机配置 `~/.ssh/config` 别名（含 `Port 2222`），能用 `ssh jp` / `ssh us` 走 OpenSSH 公钥认证
  - 保留 Tailscale SSH 作为应急后备（22 端口仍由 tailscaled 拦截）
  - **零停机切换**：实施过程中绝不丢失对任何节点的访问能力
- **非目标（不做什么）**：
  - 不卸载 Tailscale，也不关闭 `tailscaled` —— 网络层依赖
  - 不在本次范围内修改 Tailscale ACL policy
  - 不修改 sshd 在 22 端口的监听（保持 `Port 22` 供本地/公网回退）
  - 不强制禁用密码登录的远端节点（仅在确认公钥可用后才禁用）
  - 不做 SSH 跳板机（jump host）配置
  - 不处理 offline 节点（DELL、PC20241202、neutronics-server 等）

## 审查姿态

**Mode: HOLD** — 这是基础设施迁移，范围已明确。不扩展到证书签发、SSH CA、Ansible 自动化等延伸方向。重点在**安全落地不锁死自己**。

## 修改方案

### 方案概述

分三个阶段推进，每个阶段独立可回滚：

1. **Phase 1 — 本地准备 + jp-node 试点**：探测 → 公钥分发 → 本机 alias → **sshd 开 2222 端口** → 端到端验证 → 防火墙审计
2. **Phase 2 — 推广到其他在线节点**：us-node、SynologyNAS923，复用 jp-node 流程
3. **Phase 3 — 加固（可选）**：云厂商安全组核查、sshd 加固、防火墙收紧

### 关键设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| **端口策略** | **sshd 在 22 和 2222 同时监听；2222 走 OpenSSH，22 仍被 Tailscale 拦截** | Tailscale `--ssh` 无法与 22 端口 sshd 共存（已实测验证）；分端口可两者并存且可独立回滚 |
| **2222 端口选择** | 非标端口 2222 | 避开 Tailscale 拦截；云厂商防火墙通常不默认放行，降低公网暴露风险 |
| sshd 监听范围 | **保持 0.0.0.0:22 + 新增 0.0.0.0:2222；云厂商安全组/本地防火墙控制公网暴露** | `ListenAddress` 绑 Tailscale IP 风险高（接口漂移会锁死）；防火墙层控制更灵活 |
| 公钥分发方式 | **现有 Tailscale SSH 通道传输** | 已验证可用，无需第三方工具 |
| 密码认证 | **Phase 3 才禁用，且每节点独立确认** | 公钥失效时密码是最后的救命稻草 |
| 别名命名 | `jp` / `us` / `nas` | 简短，与现有 `~/.ssh/config` 中 `sugon-hf` 等命名风格一致 |
| 测试顺序 | **新会话验证 + 保留旧会话** | 改 sshd 配置后必须开新窗口验证再断旧窗口 |
| 回滚机制 | 每次改 sshd_config 前备份 + 改完不立即关旧 session + 用 reload 而非 restart | reload 不踢现有连接；失败时用备份恢复 |
| sshd 变更粒度 | **仅追加 `Port 2222`，不改其他任何项** | 最小变更降低风险；Phase 3 才考虑 PasswordAuthentication 等 |

### 影响范围

**本机文件**：
- `~/.ssh/config` — 新增 jp/us/nas Host 段（含 Port 2222）
- `~/.ssh/known_hosts` — 自然写入（首次连接）

**远端节点文件**（每节点）：
- `~/.ssh/authorized_keys` — 追加本机公钥
- `/etc/ssh/sshd_config` — **Phase 1 起即修改**（追加 `Port 2222`；**不删除原 `Port 22`**）
- 防火墙规则（ufw / firewalld / iptables）— Phase 1 审计现状并**放行 tailscale0 上的 2222**，Phase 3 才收紧公网

**不会触碰**：
- Tailscale 配置（`tailscaled` 仍以 `--ssh` 运行）
- sshd 在 22 端口的监听（Tailscale SSH 回退路径）
- `clash-for-linux-install` 项目代码
- 其他已有 SSH alias（sugon-hf、asipp 等）

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| `ssh-copy-id` over Tailscale SSH | Tailscale SSH 此刻挂起 | 阻塞 | Y | 用 `tailscale file cp` 传文件，或云控制台 VNC | Task 1.1-fallback |
| 修改远端 `sshd_config` 追加 Port 2222 后 `systemctl reload sshd` | 配置语法错 / sshd 启动失败 | 锁死 | Y | 改前 `sshd -t` 预检；保留活 Tailscale SSH session；reload 失败则备份恢复后再 reload | Task 1.4 CRITICAL 流程 |
| 远端云厂商安全组默认放行 2222 端口 | OpenSSH 暴露公网遭暴破 | 安全 | Y | Task 1.4 后立即用 `nc` 从本机公网侧探测；若开放则立刻在云控制台关闭；Task 3.1 二次核查 | Task 1.4/3.1 |
| 远端 ufw 已启用但未放行 2222 | OpenSSH 即使 sshd 监听也连不上 | 配置错 | Y | Task 1.4 先 `ufw status` 检查；若 active 则 `ufw allow in on tailscale0 to any port 2222` 再 reload sshd | Task 1.4 详述 |
| 远端 sshd 没装/未启用 | OpenSSH 路径不可用 | 阻塞 | Y | Task 1.1 已前置检测 | 已验证 jp-node sshd active |
| 本机 `~/.ssh/config` 已有同名 Host | 别名冲突覆盖 | 配置错 | Y | Task 1.3 grep 检查后再追加 | 已确认当前无 jp/us/nas |
| Tailscale IP 变化（peer 重装） | 别名指向失效 | 阻塞 | N（已知局限）| 文档记录：IP 变化时手动更新 `~/.ssh/config` HostName | 可见局限 |
| 网络中断 / Tailscale 离线 | 100.x 地址不可达 | 阻塞 | N（设计预期）| 保留每节点的公网 SSH 应急通道（如有） | 可见局限 |
| 修改 sshd 后 Tailscale SSH 也挂了 | 双通道全断 | 锁死 | Y | **必须在修改前保持一个活 Tailscale SSH session** + 云控制台 VNC 作最后退路 | Task 1.4 CRITICAL |

## 执行计划

### Phase 1: 本地准备 + jp-node 试点

#### ✅ Task 1.1: 远端节点能力探测（jp-node）

**执行结果 (2026-04-22)**：
- sshd active (OpenSSH_9.2, OpenSSL 3.0.17)
- whoami=root
- tailscale0 IP = 100.82.241.21（与计划一致）
- 防火墙工具：ufw（主）、iptables、nft 可用
- `~/.ssh/authorized_keys` 当前 96 字节（约单 key），Task 1.2 须严格追加

- **目标**：在动任何配置前，确认 jp-node 上 sshd 已安装并运行，且我们能用 root 身份执行命令
- **修改内容**：无（只读探测）
- **修改边界**：不修改任何文件
- **执行命令**：
  ```bash
  tailscale ssh root@jp-node 'systemctl is-active sshd; sshd -V 2>&1; whoami; ip -4 addr show tailscale0; ls -la ~/.ssh/ 2>/dev/null; which ufw firewalld iptables'
  ```
- **验收标准**：
  - ✅ `sshd` is active (running)
  - ✅ `whoami` 输出 `root`
  - ✅ tailscale0 接口存在且 IP = `100.82.241.21`
  - ✅ 已知该机器的防火墙工具（ufw / firewalld / iptables-only）
- **潜在风险**：Tailscale SSH 当前挂起（Task 3.2 已知问题）。若挂起，先执行 **Task 1.1-fallback**
- **依赖**：无

#### Task 1.1-fallback: Tailscale SSH 挂起时的应急探测

- **目标**：在 Tailscale SSH 不可用时仍能完成 jp-node 探测
- **执行步骤**：
  1. 重启 tailscaled：`sudo systemctl restart tailscaled`，等 30 秒后再 `tailscale status`
  2. 仍挂起则在 Tailscale admin console (https://login.tailscale.com/admin/machines) 检查 jp-node 是否需要 re-auth
  3. 仍不行则用云厂商控制台（阿里云/Vultr 等）VNC 登录 jp-node，手动执行 Task 1.1 的探测命令并记录结果
- **验收标准**：
  - ✅ 拿到 Task 1.1 要求的全部输出
- **潜在风险**：云厂商 VNC 可能要求二次验证；提前确认账号可登录

#### ✅ Task 1.2: 公钥分发到 jp-node

**执行结果 (2026-04-22)**：
- 检查发现本机 `id_ed25519.pub` 已存在于远端 `authorized_keys`（96 字节，完全匹配）
- 本任务实质为幂等性验证，未追加内容
- 已创建备份 `authorized_keys.bak.20260422_152317` 作为回滚锚点

- **目标**：将本机 `~/.ssh/id_ed25519.pub` 追加到 jp-node 的 `/root/.ssh/authorized_keys`，不覆盖已有内容
- **修改内容**：
  - 远端文件 `/root/.ssh/authorized_keys`：追加一行（本机公钥）
- **修改边界**：
  - 不创建新 key（用现有 `~/.ssh/id_ed25519`）
  - 不删除/覆盖现有 authorized_keys 任何行
  - 不修改 `~/.ssh/` 目录权限（如已存在）
- **执行步骤**：
  ```bash
  # 1. 本地查看公钥（确认是要分发的那把）
  cat ~/.ssh/id_ed25519.pub

  # 2. 备份远端 authorized_keys
  tailscale ssh root@jp-node 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
    [ -f ~/.ssh/authorized_keys ] && cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak.$(date +%Y%m%d) || true'

  # 3. 追加（先 grep 确认未重复）
  PUB=$(cat ~/.ssh/id_ed25519.pub)
  tailscale ssh root@jp-node "grep -qF '$PUB' ~/.ssh/authorized_keys 2>/dev/null || echo '$PUB' >> ~/.ssh/authorized_keys"

  # 4. 确认权限
  tailscale ssh root@jp-node 'chmod 600 ~/.ssh/authorized_keys && ls -la ~/.ssh/authorized_keys'

  # 5. 验证内容
  tailscale ssh root@jp-node 'tail -3 ~/.ssh/authorized_keys'
  ```
- **验收标准**：
  - ✅ 远端 `~/.ssh/authorized_keys` 末尾包含本机 `id_ed25519.pub` 完整内容
  - ✅ 文件权限 600，目录 700
  - ✅ 备份文件 `authorized_keys.bak.<date>` 存在（若原文件存在）
  - ✅ 未出现重复条目（grep 计数应为 1）
- **潜在风险**：
  - 公钥含特殊字符被 shell 截断 → 用 `ssh-copy-id` 也可，但需要 OpenSSH 已能登录；当前阶段用 echo + 完整引号保护即可
  - 若 Tailscale SSH 挂起，使用 `tailscale file cp ~/.ssh/id_ed25519.pub jp-node:` 后通过云控制台 VNC 进入手动追加
- **依赖**：Task 1.1 完成

#### ✅ Task 1.3: 本机 ~/.ssh/config 添加 jp 别名

**执行结果 (2026-04-22)**：
- 本机 `~/.ssh/config` 已追加 `Host jp` 段（未修改现有任何别名）
- `ssh -G jp` 返回：root@100.82.241.21, identityfile=`~/.ssh/id_ed25519`
- 备份 `~/.ssh/config.bak.20260422_142426` 已创建
- 对 sugon-hf / github.com 等现有别名进行了回归验证，输出未变

**⚠️ Task 1.4 验证发现 Tailscale 拦截 22 端口**：Task 1.4-B 完成后将补为 `Port 2222`。

最终追加的 `Host jp` 段（Task 1.4-C 后完整形态）：

```
# === Tailscale OpenSSH aliases (added 2026-04-22) ===
Host jp
    HostName 100.82.241.21
    Port 2222
    User root
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

#### ✅ Task 1.4-A: 验证 Tailscale SSH 拦截 22 端口

**执行结果 (2026-04-22)**：
- `ssh jp` 虽然连通，但 `ssh -vvv jp` banner 为 `remote software version Tailscale`
- `Authenticated to 100.82.241.21 using "none"` — 表明走的是 Tailscale SSH，非 OpenSSH 公钥
- 远端 `ss -tlnp` 确认 sshd 监听 `0.0.0.0:22`，但 tailscaled `--ssh` 在 tailnet 层拦截
- **结论**：必须在 sshd 上增开非 22 端口方能旁路 Tailscale 拦截

#### ✅ Task 1.4-B: jp-node sshd 追加 `Port 2222` 监听（**CRITICAL — 最高风险任务**）

**执行结果 (2026-04-23)**：
- 备份：`/etc/ssh/sshd_config.bak.20260423_235939`
- 追加 `Port 2222`后发现 sshd 默认 Port 22 被隐式丢弃——**主动补上 `Port 22` 保持双端口**（这是 sshd 语义：一旦显式声明任何 `Port`，默认 22 不再生效）
- 最终配置：`Port 22` 和 `Port 2222` 两行均存在
- `sshd -t` 两轮均通过；`systemctl reload sshd` 成功
- `ss -tlnp` 确认 sshd 同时监听 v4/v6 的 :22 和 :2222（同 pid 687）
- ufw 现为 active，已追加 `2222/tcp on tailscale0 ALLOW`（v4+v6），现有 9000/80/443 规则未受影响
- 救命 Tailscale SSH session 全程存活（`tailscale ssh` 是 userspace，不依赖 sshd:22）

- **目标**：在 jp-node 上让 sshd 额外监听 2222 端口，保留 22 端口不动
- **修改内容**：
  - 远端 `/etc/ssh/sshd_config`：**仅追加**一行 `Port 2222`（若已存在则跳过）
  - 远端 ufw（仅在 active 时）：`allow in on tailscale0 to any port 2222 proto tcp`
- **修改边界**：
  - 不删改原有任何行（不改 `Port 22`、不改 `PasswordAuthentication`、不改 `PermitRootLogin`、不改 `ListenAddress`）
  - 不改云厂商安全组（Task 3.1 才做）
  - 不启用/禁用 ufw（若 inactive 保持 inactive）
- **安全执行步骤（严格按序）**：
  ```bash
  # 第 1 步：打开一个永不关闭的救命 Tailscale SSH session（另开终端）
  tailscale ssh root@jp-node
  # （保留此窗口至 Task 1.4-D 验证通过）

  # 以下步骤在救命 session 中执行：

  # 第 2 步：备份
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)
  ls -la /etc/ssh/sshd_config.bak.*

  # 第 3 步：幂等追加 Port 2222
  grep -qE '^Port 2222$' /etc/ssh/sshd_config || echo 'Port 2222' >> /etc/ssh/sshd_config
  grep -nE '^Port ' /etc/ssh/sshd_config

  # 第 4 步：语法预检（必做，失败立即回滚）
  if sshd -t; then
    echo SYNTAX_OK
  else
    echo SYNTAX_FAIL; cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config; exit 1
  fi

  # 第 5 步：若 ufw active，先放行 2222
  if ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow in on tailscale0 to any port 2222 proto tcp
    ufw status
  else
    echo "ufw inactive, skip"
  fi

  # 第 6 步：reload（不是 restart）
  systemctl reload sshd && echo RELOADED

  # 第 7 步：验证新端口已监听
  ss -tlnp | grep -E ':(22|2222)\b'
  ```
- **验收标准**：
  - ✅ `sshd -t` 语法检查通过
  - ✅ `systemctl reload sshd` 成功，救命 session 仍活着
  - ✅ `ss -tlnp` 显示 sshd 同时监听 `:22` 和 `:2222`
  - ✅ 备份文件 `sshd_config.bak.<ts>` 存在
  - ✅ 若 ufw active，tailscale0:2222 已放行
- **潜在风险（高）**：
  - `sshd -t` 未查出运行时错误 → 救命 session 可随时 `cp` 备份回去再 reload
  - reload 使 sshd 崩溃 → restart 欢迎效应，旧 session 仍能操作；严重时云控制台 VNC 兜底
  - ufw 误操作 → 本 Task 仅做 `allow`，不做 `deny` 或 `enable/disable`
- **回滚**：
  ```bash
  cp /etc/ssh/sshd_config.bak.<ts> /etc/ssh/sshd_config && sshd -t && systemctl reload sshd
  # ufw 如需回滚：ufw delete allow in on tailscale0 to any port 2222 proto tcp
  ```
- **依赖**：Task 1.1、1.2、1.4-A 完成

#### ✅ Task 1.4-C: 本机 `ssh jp` 追加 `Port 2222` 并端到端验证 OpenSSH 通路

**执行结果 (2026-04-23)**：
- 备份 `~/.ssh/config.bak.20260423_230058`
- `Host jp` 段已加 `Port 2222`；other fields 未变
- `ssh -G jp` 输出含 `port 2222`
- `ssh -vvv jp` banner: `Remote protocol version 2.0, remote software version OpenSSH_9.2p1 Debian-2+deb12u7` — 确信走 OpenSSH
- `Authenticated to 100.82.241.21 ([100.82.241.21]:2222) using "publickey"` — 公钥认证成功
- `Server accepts key: ~/.ssh/id_ed25519 ED25519 SHA256:7KmDRv08JRf1WWD9jLdVjq3yDTzGF6b+/hi7qXK6fuI`
- scp 双向传输成功（openssh-test 文件 round-trip OK）
- `~/.ssh/known_hosts` 末尾新增 ed25519 + ecdsa 两条 hashed 宿主记录（对应 `[100.82.241.21]:2222`）

- **目标**：确认 `ssh jp` 走 OpenSSH 公钥认证（而非 Tailscale SSH）
- **修改内容**：
  - 本机 `~/.ssh/config` 的 `Host jp` 段中插入一行 `Port 2222`
- **执行步骤**：
  ```bash
  # 1. 再备份（新一轮）
  cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d_%H%M%S)

  # 2. 编辑插入 Port 2222 到 Host jp 的 HostName 行之后
  #    手动 vim/nano 最安全

  # 3. 验证 alias 解析
  ssh -G jp | grep -iE "^(hostname|port|user|identityfile)"

  # 4. 新开窗口，不影响救命 session
  ssh -o StrictHostKeyChecking=accept-new jp 'echo OK; whoami; hostname'

  # 5. 验证认证方式和远端 banner
  ssh -vvv jp 'echo done' 2>&1 | grep -E "Authenticated|Remote protocol|Connecting"

  # 6. scp 双向测试
  echo "openssh-test $(date)" > /tmp/openssh-test.txt
  scp /tmp/openssh-test.txt jp:/tmp/
  ssh jp 'cat /tmp/openssh-test.txt && rm /tmp/openssh-test.txt'
  rm /tmp/openssh-test.txt
  ```
- **验收标准**：
  - ✅ `ssh -G jp` 显示 `port 2222`
  - ✅ `ssh jp 'echo OK'` 不挂起，5 秒内返回
  - ✅ `-vvv` 显示 `Remote protocol version 2.0, remote software version OpenSSH_*`（**不是** `Tailscale`）
  - ✅ `-vvv` 显示 `Authenticated to ... using "publickey"`
  - ✅ scp 双向传输成功
  - ✅ `~/.ssh/known_hosts` 新增 `[100.82.241.21]:2222` 条目
- **潜在风险**：若连不上 → 在 Task 1.4-B 的救命 session 里 `ss -tlnp | grep 2222` 确认 sshd 确实在听；`ufw status` 确认放行；必要时回滚
- **依赖**：Task 1.4-B 完成

#### ✅ Task 1.4-D: 验证 Tailscale SSH 后备仍可用 + 关闭救命 session

**执行结果 (2026-04-23)**：
- `tailscale ssh root@jp-node 'echo TS_OK'` 返回 TS_OK（后备路径状态健康）
- `ssh jp 'echo OPENSSH_OK'` 返回 OPENSSH_OK（主路径状态健康）
- 两路径均确认后才关闭了 Task 1.4-B 保留的救命 Tailscale SSH session
- **共存目标达成**：22 走 Tailscale SSH、2222 走 OpenSSH

- **目标**：确认方案共存目标达成（两条路径都能走）
- **执行步骤**：
  ```bash
  # 1. Tailscale SSH 仍然能用
  tailscale ssh root@jp-node 'echo tailscale-ssh-still-works'

  # 2. OpenSSH 仍然能用
  ssh jp 'echo openssh-still-works'

  # 3. 两者均成功后才 exit Task 1.4-B 的救命 session
  ```
- **验收标准**：
  - ✅ 两个命令均成功
  - ✅ 仅在确认后才关闭救命 session
- **依赖**：Task 1.4-C 完成

#### ✅ Task 1.5: jp-node 端口与防火墙现状审计（不修改）

**执行结果 (2026-04-23)**：
- sshd 监听：`0.0.0.0:22` + `0.0.0.0:2222`（v4 + v6，同 pid 687）
- ufw 状态：active，default deny (incoming) / allow (outgoing)
- ufw 规则：80/tcp、443/tcp、`9000/tcp on tailscale0`、`9000/udp on tailscale0`、`2222/tcp on tailscale0`（v4 和 v6各一份）
- **公网视角探测结果**：
  | 端口 | 状态 |
  |------|------|
  | 22 | ✅ BLOCKED |
  | **2222** | **✅ BLOCKED — 未意外暴露公网** |
  | 80 | OPEN（既有 HTTP 服务）|
  | 443 | OPEN（既有 HTTPS 服务）|
- 云厂商安全组推迟到 Task 3.1 手动核查（本 Task 不需控制台访问）
- 本机网络状态健康：Tailscale 在线，ping jp-node 92ms RTT，Baidu HTTP 200 (60ms)，Google HTTP 200 (1.27s via Clash)；ICMP 公网被拦但 TCP 不受影响

- **目标**：搞清 jp-node 当前 22/2222 端口对公网的暴露，**特别是 2222 是否意外暴露公网**
- **修改内容**：无（只读审计，若发现 2222 公网暴露才立刻处置）
- **执行步骤**：
  ```bash
  # 1. 远端本地视角
  ssh jp 'ss -tlnp | grep -E ":(22|2222)\b"; \
          iptables -L INPUT -n -v | head -20; \
          (ufw status verbose 2>/dev/null || firewall-cmd --list-all 2>/dev/null || echo "no managed fw")'

  # 2. **公网视角探测 2222（新开端口必核）**
  nc -zv -w 5 47.245.32.3 2222 2>&1
  nc -zv -w 5 47.245.32.3 22 2>&1

  # 3. 若 2222 在公网可达 → 立刻上云控制台关掉安全组中的 2222 规则，或限制源 IP 为本机出口
  ```
- **验收标准**：
  - ✅ 记录：sshd 监听地址（应为 `0.0.0.0:22` + `0.0.0.0:2222`）
  - ✅ 记录：现有防火墙规则
  - ✅ 记录：公网视角 22 和 2222 可达性
  - ✅ 记录：云厂商安全组（需登录控制台手动查）
  - ✅ **若 2222 已暴露公网，已在安全组层关闭或限源**
- **潜在风险**：若云厂商安全组默认 open 所有端口，2222 会立即暴露 → 验收时立即处理
- **依赖**：Task 1.4-D 完成

### Phase 2: 推广到 us-node 和 SynologyNAS923

#### ✅ Task 2.1: us-node 完整流程（重复 Task 1.1 → 1.5）

**执行结果 (2026-04-23)**：

- **关键差异（与 jp-node 不同）**：us-node 未启用 Tailscale `--ssh`（`tailscaled` 启动参数无 `--ssh`，`/etc/default/tailscaled` FLAGS 为空），banner 测试直接返回 `OpenSSH_9.2p1 Debian-2+deb12u2`。**因此无需添加 Port 2222**，直接通过 Tailscale IP 访问 OpenSSH 默认端口 22 即可。
- **远端基线**：
  - sshd: OpenSSH 9.2，监听 `0.0.0.0:22`（pid 639）
  - 无 ufw，仅 iptables `ts-input`（Tailscale 管理）
  - `~/.ssh/authorized_keys` 已含 gw-workstation 公钥（重复 2 行 → 已 awk 去重，备份 `~/.ssh/authorized_keys.bak.20260423_231417`）
- **客户端配置**：`~/.ssh/config` 追加 `Host us` 段（HostName 100.92.101.61, Port 22, IdentityFile ~/.ssh/id_ed25519, IdentitiesOnly yes），备份 `~/.ssh/config.bak.20260423_231402`
- **验收**：
  - ✅ `ssh us 'whoami'` → `root`
  - ✅ Auth：`Authenticated to 100.92.101.61:22 using "publickey"`，server `OpenSSH_9.2p1 Debian-2+deb12u2`
  - ✅ scp 双向 round-trip 成功
  - ✅ jp 别名无回归（`ssh jp 'echo JP_OK'` → JP_OK）
  - ⚠️ Tailscale SSH fallback **N/A**（us-node 未启用 `--ssh`，无 fallback 路径）
- **公网暴露记录（待 Task 3.1 处理）**：
  | 端口 | 状态 |
  |------|------|
  | 22 | **⚠️ OPEN**（既有状态，非本任务引入；Aliyun 安全组未限源）|
  | 2222 | BLOCKED |
  | 80 / 443 | REFUSED（无服务）|
- **未执行的子任务**：Port 2222 sshd 修改（不必要）、ufw 配置（无 ufw，不引入新依赖）

---

**原任务描述（保留供参考）**：

- **目标**：us-node (`100.92.101.61`, 公网 `43.110.32.131`) 完成与 jp-node 相同的配置
- **修改内容**：
  - us-node `~/.ssh/authorized_keys` 追加本机公钥
  - 本机 `~/.ssh/config` 追加 `Host us` 段
- **修改边界**：与 Task 1.x 完全一致
- **执行**：复用 Task 1.1 ~ 1.5 的命令模板，将 `jp-node` / `jp` / `100.82.241.21` 替换为 `us-node` / `us` / `100.92.101.61`
- **验收标准**：
  - ✅ `ssh us 'whoami'` 返回 `root` 且使用 publickey
  - ✅ `ssh -vvv us` 显示 OpenSSH server
  - ✅ scp 双向成功
  - ✅ 防火墙现状已记录
- **潜在风险**：与 Task 1.x 同
- **依赖**：Phase 1 全部完成（确认流程跑通）

#### Task 2.2: SynologyNAS923 配置

- **目标**：NAS (`100.82.177.76`) 配置 OpenSSH 别名 `nas`
- **修改内容**：
  - NAS `~/.ssh/authorized_keys`（注意 NAS 用户体系特殊，可能不是 root）
  - 本机 `~/.ssh/config` 追加 `Host nas` 段
- **特别注意（Synology DSM 特殊性）**：
  - DSM 默认 SSH 用 admin 账户而非 root
  - DSM 升级会重置 `/etc/ssh/sshd_config`，但 `~/.ssh/authorized_keys` 通常保留
  - DSM 可能要求用 admin 组用户 + `sudo` 提权
  - 已有专用 key `~/.ssh/id_ed25519_nas`（见本机 ls 结果），优先复用
- **执行步骤**：
  ```bash
  # 1. 探测当前 SSH 用户和能力
  tailscale ssh <whatever-user>@SynologyNAS923 'whoami; ls -la ~/.ssh/'

  # 2. 用现有 id_ed25519_nas 公钥追加（同 Task 1.2 流程）

  # 3. 别名配置
  Host nas
      HostName 100.82.177.76
      User <实际用户名>
      IdentityFile ~/.ssh/id_ed25519_nas
      IdentitiesOnly yes
      ServerAliveInterval 30
      ServerAliveCountMax 3
  ```
- **验收标准**：
  - ✅ `ssh nas 'whoami'` 成功
  - ✅ 使用 publickey 认证
  - ✅ 已知 DSM 升级后是否需要重新配置（查 Synology 官方文档记录到 known_hosts.notes 或本任务 notes）
- **潜在风险**：DSM 行为与标准 Linux 不同；若失败不强行修改 sshd_config（会被 DSM 覆盖），改用 DSM 控制面板配置 SSH key
- **依赖**：Phase 1 完成

### Phase 3: 安全加固（可选，每节点独立判断）

#### Task 3.1: 云厂商安全组核查 **+ 2222 端口公网核查**（jp-node、us-node）

- **目标**：确认公网 IP 上 22 和 **2222** 端口的暴露范围，决定是否收紧
- **修改内容**：核查为主；**若 2222 意外暴露公网则立即收紧**
- **执行步骤**：
  1. 登录 jp-node 所在云厂商控制台，查看安全组入站规则中 22 和 2222 端口的源 IP 范围
  2. 同样检查 us-node
  3. 若 2222 对 0.0.0.0/0 开放 → 立即限制到本机公网 IP，或完全关闭（依赖 Tailscale 入站即可）
- **决策矩阵**：
  | 端口 | 现状 | 建议动作 |
  |------|------|---------|
  | 22 | 对 0.0.0.0/0 开放 | 保持（Tailscale SSH 需要）或限源 |
  | 22 | 已限源 | 保持 |
  | **2222** | **对 0.0.0.0/0 开放** | **立即限制到本机公网 IP 或完全关闭** |
  | 2222 | 已限源到本机 | 理想状态 |
  | 2222 | 完全关闭（仅 Tailscale 可达） | 最安全 |
- **验收标准**：
  - ✅ 每个云节点的 22 和 2222 端口暴露范围已记录
  - ✅ 2222 在公网层已达成"限源"或"关闭"
- **潜在风险**：错误关闭安全组规则可能锁死自己；每次改动前确认 Tailscale 通路可用作为退路
- **依赖**：Phase 1、Phase 2 完成

#### Task 3.2: （可选）远端 sshd_config 进一步加固

- **目标**：在确认 OpenSSH 公钥路径稳定后，禁用密码登录、限制 root 直接登录
- **触发条件**：仅在以下都满足时才执行：
  - Phase 1/2 全部成功超过 7 天且每天都正常使用过
  - 云厂商安全组已收紧
  - 用户有时间应对锁死风险（不在出差/重要任务期间）
- **修改内容**（每节点独立判断）：
  - `/etc/ssh/sshd_config`：
    ```
    PasswordAuthentication no
    PubkeyAuthentication yes
    PermitRootLogin prohibit-password   # 允许 root 但仅公钥
    ```
- **修改边界**：
  - 不改 `Port`（保持 22 + 2222）
  - 不改 `ListenAddress`（依赖防火墙隔离）
  - 不动 Match 段
- **执行步骤（CRITICAL — 必须严格按序）**：
  ```bash
  # 第 1 步：在节点上保持一个 root session 不要关闭！
  ssh jp
  # （这个 session 是救命窗口，整个过程不要 exit）

  # 第 2 步：备份
  sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)

  # 第 3 步：编辑
  sudo vi /etc/ssh/sshd_config

  # 第 4 步：语法预检（必做！）
  sudo sshd -t && echo "syntax OK" || echo "SYNTAX ERROR — DO NOT RELOAD"

  # 第 5 步：仅在预检通过后 reload（不是 restart）
  sudo systemctl reload sshd

  # 第 6 步：在另一个新窗口验证
  ssh jp 'echo new-session-OK'

  # 第 7 步：仅在新窗口成功后才关闭原 session
  ```
- **验收标准**：
  - ✅ `sshd -t` 通过
  - ✅ reload 后新建 ssh session 成功
  - ✅ 备份文件存在
  - ✅ 旧 session 仍然可用（确认 reload 不踢现有连接）
- **潜在风险**：**HIGH** — 配置错可能锁死。务必保留旧 session、用 reload 而非 restart、有云控制台 VNC 退路
- **依赖**：Task 3.1 完成

#### Task 3.3: （可选）防火墙规则收紧

- **触发条件**：与 Task 3.2 相同
- **执行原则**：
  - 优先在云厂商安全组层做（不需 root，不会锁死系统）
  - 若必须在节点本地做 ufw/firewalld，遵循"先 allow 再 deny 再 enable"顺序
  - 永远先 dry-run
- **示例（ufw）**：
  ```bash
  # 错误顺序（会锁死！）：
  # sudo ufw enable; sudo ufw deny 22  ← 不要这样

  # 正确顺序：
  sudo ufw status verbose                          # 当前状态
  sudo ufw allow in on tailscale0                  # 先放行 Tailscale 接口
  sudo ufw allow from 100.64.0.0/10 to any port 22 # 双保险
  sudo ufw status                                  # 确认规则就位
  # 此时如果 ufw 是 inactive 状态：
  sudo ufw --dry-run enable                        # dry-run
  sudo ufw enable                                  # 启用
  # 验证新窗口能登录后再考虑：
  sudo ufw deny 22/tcp                             # 拒绝其他来源
  ```
- **验收标准**：
  - ✅ 启用前后新建 ssh session 均成功
  - ✅ 公网视角 `nc -zv <public-ip> 22` 不通（如果策略是关闭公网 22）
  - ✅ Tailscale 视角 `ssh jp` 仍通
- **潜在风险**：**HIGH** — 同 Task 3.2
- **依赖**：Task 3.2 完成

### Phase 4: 文档与知识沉淀

#### Task 4.1: 更新 user memory

- **目标**：将本次配置经验写入 `/memories/` 或 `/memories/repo/`
- **修改内容**：
  - 文件 `/memories/environments.md`：追加"OpenSSH over Tailscale 配置惯例"小节，含别名命名约定、防火墙顺序、DSM 特殊性
- **执行**：由 memory-nudge 流程在会话结束时按需触发，**用户确认后才写入**
- **验收标准**：
  - ✅ 用户确认或拒绝
- **依赖**：Phase 1/2 完成

## 回归检查清单

- [ ] `ssh jp 'echo ok'` 返回 ok（不挂起，不询问密码，走 Port 2222 OpenSSH）
- [ ] `ssh -vvv jp` 显示 `remote software version OpenSSH_*`（**不是** `Tailscale`）
- [ ] `ssh us 'echo ok'` 返回 ok
- [ ] `ssh nas 'echo ok'` 返回 ok
- [ ] `ssh -G jp` 显示 `port 2222`, IdentityFile = `~/.ssh/id_ed25519`, User = `root`
- [ ] 现有别名 `ssh -G sugon-hf` 输出与变更前一致（diff 应为空）
- [ ] `tailscale status` 仍显示本机 online，所有目标 peer 直连或 DERP 可达
- [ ] `tailscale ssh root@jp-node 'echo ok'` 仍能工作（22 端口后备未失效）
- [ ] 远端 `ss -tlnp` 显示 sshd 同时监听 :22 和 :2222
- [ ] 本机 `~/.ssh/config.bak.<timestamp>` 存在
- [ ] 每个改过 sshd_config 的远端节点 `/etc/ssh/sshd_config.bak.<timestamp>` 存在
- [ ] 公网视角 `nc -zv <public-ip> 2222` 行为符合 Phase 3 决策（理想为关闭）
- [ ] Tailscale 健康警告（DNS）仍在排查列表中（本计划不解决，但记录）

## 已知局限

- **Tailscale 离线时不可用**：本方案依赖 100.x 网段，离线时只能走云厂商 VNC 或公网 SSH（如果安全组开放）。未在本计划范围
- **Tailscale IP 变化**：peer 重装会导致 IP 变化，需手动更新 `~/.ssh/config`
- **Magic DNS 仍未修复**：`tailscale ssh root@jp-node`（按主机名）受 DNS 警告影响；本方案改用 IP 直连规避此问题
- **DSM 升级影响**：Synology DSM 大版本升级可能重置 sshd 配置，需在升级后回归测试 nas 别名
- **Windows 客户端配置不在本计划**：Windows 上需要单独配置 OpenSSH client + `%USERPROFILE%\.ssh\config`，沿用本计划的别名命名约定并加 `Port 2222` 即可
- **2222 端口选择可能与其他服务冲突**：若远端节点已有其他服务占用 2222，需换一个非 22 的端口（如 2200、2022 等），别名也需同步更新

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 2 | 2 | 0 |
| R2 | 可执行性 | 3 | 3 | 0 |
| R3 | 风险与边缘 | 4 | 4 | 0 |
| **修订 R4** | **方案 B 重构（Tailscale 22 端口拦截实证）** | 3 | 3 | 0 |
| **终止** | **T1 — 收敛终止** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整（含非目标 + 方案 B 关键发现）|
| 技术方案 | 完整（含 8 项关键决策，含端口策略）|
| Error & Rescue Map | 9 条路径，2 条已知局限明示 |
| 执行计划 | 4 Phase，13 Task（含 1.4-A/B/C/D 四子任务）|
| 回归检查清单 | 13 项，含 OpenSSH banner 验证 |
| 已知局限 | 6 项明示 |

### R1 Issues
- **Issue R1-1**: 初稿缺"非目标"段 → 补充明确不卸 Tailscale、不改 ACL ✅ 已修正
- **Issue R1-2**: 缺 Error & Rescue Map → 补充 9 条失败路径含 Tailscale SSH 当前挂起、sshd reload 失败、防火墙锁死 ✅ 已修正

### R2 Issues
- **Issue R2-1**: Phase 3 加固任务原本嵌在 Phase 1，导致单 Task 修改面过大 → 拆为独立 Phase 且加触发条件 ✅ 已修正
- **Issue R2-2**: Task 1.4 验收标准只有"ssh 成功"过于模糊 → 增加 `-vvv` 检查 OpenSSH server banner、known_hosts 写入 ✅ 已修正
- **Issue R2-3**: 公钥分发缺乏"Tailscale SSH 挂起时怎么办"的 fallback → 新增 Task 1.1-fallback 走云厂商 VNC ✅ 已修正

### R3 Issues
- **Issue R3-1**: 未识别 DSM 特殊性（用户非 root、升级会重置 sshd_config）→ Task 2.2 详述 ✅ 已修正
- **Issue R3-2**: Task 3.2 sshd reload 步骤缺"保留旧 session"指引，存在锁死风险 → 补充 7 步严格流程 ✅ 已修正

### R4 Issues（方案 B 重构 — 2026-04-22 实测驱动）
- **Issue R4-1**: 原假设 sshd 监听 22 + OpenSSH 可用。**实测 Tailscale `--ssh` 在 tailnet IP 的 22 端口做 userspace 拦截，sshd 收不到连接** → 拆为 Task 1.4-A/B/C/D，sshd 增开 2222 端口与 Tailscale SSH 共存 ✅ 已修正
- **Issue R4-2**: 新端口 2222 可能被云安全组默认开放暴露公网 → Task 1.5 和 Task 3.1 新增"2222 公网可达性核查"，并在验收时若暴露立即处置 ✅ 已修正
- **Issue R4-3**: `ListenAddress` 绑 Tailscale IP 风险高（接口漂移会锁死）→ 关键设计决策明示保持 `0.0.0.0` 监听 + 依赖防火墙/安全组控制暴露 ✅ 已修正
- **Issue R3-3**: Task 3.3 防火墙顺序未强调"先 allow 再 enable" → 加错误/正确顺序对比 ✅ 已修正
- **Issue R3-4**: 未涵盖云厂商安全组层面的暴露 → 新增 Task 3.1 云厂商核查 ✅ 已修正

## Pre-Delivery Audit (Level: L1-Lite)

| § | Check | Status | Note |
|---|-------|--------|------|
| 1 | 单位/术语一致性 | ✅ PASS | sshd/Tailscale/control plane 等术语贯穿一致 |
| 1 | 命令可复制性 | ✅ PASS | 所有 shell 命令使用真实 IP 与现有 key 文件名 |
| 1 | 引用资源真实性 | ✅ PASS | `id_ed25519`、`id_ed25519_nas`、`~/.ssh/config` 已验证存在；jp/us 别名已验证不冲突 |

Auditor: Plan Architect | Date: 2026-04-22
