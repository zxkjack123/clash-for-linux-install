# Migrate from Tailscale SSH to OpenSSH over Tailscale

## 背景与目标

- **问题/需求描述**：Tailscale SSH 在 control plane / Magic DNS 不稳定时会挂起（已被 Task 3.2 阻塞复现）。Windows 客户端对 Tailscale SSH 支持差，多平台体验不一致。希望切换到"Tailscale 提供网络层 + OpenSSH 提供认证层"的更稳健方案。
- **审阅来源**：用户决策（在比较两方案后采纳 OpenSSH over Tailscale）。
- **目标**：
  - 在所有常用节点（jp-node、us-node、SynologyNAS923 等）启用原生 sshd，绑定到 Tailscale 接口或受防火墙限制
  - 本机配置 `~/.ssh/config` 别名，能用 `ssh jp` / `ssh us` 直接登录
  - 保留 Tailscale SSH 作为应急后备（不主动关闭 `--ssh` flag）
  - **零停机切换**：实施过程中绝不丢失对任何节点的访问能力
- **非目标（不做什么）**：
  - 不卸载 Tailscale，也不关闭 `tailscaled` —— 网络层依赖
  - 不在本次范围内修改 Tailscale ACL policy
  - 不强制禁用密码登录的远端节点（仅在确认公钥可用后才禁用）
  - 不做 SSH 跳板机（jump host）配置
  - 不处理 offline 节点（DELL、PC20241202、neutronics-server 等）

## 审查姿态

**Mode: HOLD** — 这是基础设施迁移，范围已明确。不扩展到证书签发、SSH CA、Ansible 自动化等延伸方向。重点在**安全落地不锁死自己**。

## 修改方案

### 方案概述

分三个阶段推进，每个阶段独立可回滚：

1. **Phase 1 — 本地准备 + 单节点验证**：用 jp-node 作为试点，配公钥 + 测试 OpenSSH 通路 + 验证防火墙隔离 22 端口对公网
2. **Phase 2 — 推广到其他在线节点**：us-node、SynologyNAS923，复用 jp-node 的配置模板
3. **Phase 3 — 加固与文档化**：所有节点确认无误后，再考虑禁用密码认证、限制监听地址等收紧操作

### 关键设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| sshd 监听范围 | **防火墙限制 + 默认监听** | `ListenAddress` 修改风险高（若 Tailscale 接口名/IP 变化会锁死），用防火墙更灵活；保留 `0.0.0.0:22` 但 `ufw deny 22` + `ufw allow in on tailscale0` |
| 公钥分发方式 | **现有 Tailscale SSH 通道传输** | 已经能 `tailscale ssh` 登录的节点，用它当临时通道传公钥，避免引入第三方工具 |
| 密码认证 | **Phase 3 才禁用，且每节点独立确认** | 公钥失效时密码是最后的救命稻草 |
| 别名命名 | `jp` / `us` / `nas` | 简短，与现有 `~/.ssh/config` 中 `sugon-hf` 等命名风格一致 |
| 测试顺序 | **新会话验证 + 保留旧会话** | 改 sshd 配置后必须开新窗口验证再断旧窗口 |
| 回滚机制 | 每次改 sshd_config 前备份 + 改完不立即关旧 session | sshd reload 失败时旧 session 仍能 `mv` 备份回去 |

### 影响范围

**本机文件**：
- `~/.ssh/config` — 新增 jp/us/nas Host 段
- `~/.ssh/known_hosts` — 自然写入（首次连接）

**远端节点文件**（每节点）：
- `~/.ssh/authorized_keys` — 追加本机公钥
- `/etc/ssh/sshd_config` — Phase 3 才动（仅 us-node/jp-node，可选）
- 防火墙规则（ufw / firewalld / iptables）— Phase 1/2 验证现状，Phase 3 才收紧

**不会触碰**：
- Tailscale 配置（`tailscaled` 仍以 `--ssh` 运行）
- `clash-for-linux-install` 项目代码
- 其他已有 SSH alias（sugon-hf、asipp 等）

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| `ssh-copy-id` over Tailscale SSH | Tailscale SSH 此刻挂起 | 阻塞 | Y | Plan B：用 `tailscale file cp` 传文件，再 ssh 进去手动 cat 追加；或 web console 临时启用密码 | 手动 fallback 流程在 Task 1.2 中详述 |
| 修改远端 `sshd_config` 后 `systemctl reload sshd` | 配置语法错 / sshd 启动失败 | 锁死 | Y | 改前 `sshd -t` 预检；reload 失败时旧 session 用备份恢复 | Task 3.x 标记为 CRITICAL，必须保留旧 session |
| 远端启用 ufw 但忘记放行 tailscale0 | 自身 SSH 被防火墙踢掉 | 锁死 | Y | 必须按"先 allow 再 enable"顺序；先用 `ufw --dry-run` | Task 1.4 详述顺序 |
| 远端 sshd 没装/未启用 | OpenSSH 路径不可用 | 阻塞 | Y | Task 1.1 先检测 `systemctl status sshd`，缺失则 `apt install openssh-server` | 检测步骤前置 |
| 公网 IP 节点（jp-node 47.245.32.3）22 端口被云厂商安全组开放 | OpenSSH 暴露公网，遭暴力破解 | 安全 | Y | Phase 3 的安全检查清单包含云厂商安全组核查 | Task 3.1 明确要求 |
| 本机 `~/.ssh/config` 已有同名 Host | 别名冲突覆盖 | 配置错 | Y | Task 1.5 grep 检查后再追加 | 已确认当前无 jp/us/nas |
| Tailscale IP 变化（peer 重装） | 别名指向失效 | 阻塞 | N（已知局限）| 文档记录：IP 变化时手动更新 `~/.ssh/config` HostName 字段 | 可见局限 |
| 远端节点 root 用户禁用 | `User root` 别名无法登录 | 配置错 | Y | Task 1.1 先 `tailscale ssh root@host whoami` 验证 root 身份可用 | 检测前置 |
| 网络中断 / Tailscale 离线 | 100.x 地址不可达 | 阻塞 | N（设计预期）| 这种情况下任何 100.x 方案都不可用；保留每节点的公网 SSH 应急通道（如有） | 可见局限 |

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

#### Task 1.3: 本机 ~/.ssh/config 添加 jp 别名

- **目标**：本机能用 `ssh jp` 走 OpenSSH 登录 jp-node
- **修改内容**：
  - 文件 `~/.ssh/config`：追加 `Host jp` 段
- **修改边界**：
  - 不修改现有任何 Host 段（sugon-hf、asipp、github.com 等）
  - 不全局改 `Host *` 默认值
- **追加内容**：
  ```
  # === Tailscale OpenSSH aliases (added 2026-04-22) ===
  Host jp
      HostName 100.82.241.21
      User root
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      ServerAliveInterval 30
      ServerAliveCountMax 3
  ```
- **执行步骤**：
  ```bash
  # 1. 备份
  cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d_%H%M%S)

  # 2. 确认无冲突
  grep -E "^Host (jp|us|nas)\b" ~/.ssh/config && echo "CONFLICT!" || echo "OK"

  # 3. 追加（用 cat <<EOF >> 或编辑器手动）
  ```
- **验收标准**：
  - ✅ `ssh -G jp | grep -E "hostname|user|identityfile"` 输出预期值
  - ✅ 备份文件存在
  - ✅ 现有别名 `ssh -G sugon-hf` 输出未变化
- **潜在风险**：低
- **依赖**：Task 1.2 完成

#### Task 1.4: 端到端验证 OpenSSH 通路（jp-node）

- **目标**：确认 `ssh jp` 走 OpenSSH 公钥认证成功，不需要密码、不挂在 Tailscale SSH 上
- **修改内容**：无
- **执行步骤**：
  ```bash
  # 1. 详细输出确认认证方式
  ssh -vvv jp 'whoami; uname -a; date' 2>&1 | grep -E "Authenticated|Offering|Server accepts|Remote protocol"

  # 2. 简单连通性
  ssh jp 'echo OK'

  # 3. scp 测试
  echo "test $(date)" > /tmp/openssh-test.txt
  scp /tmp/openssh-test.txt jp:/tmp/
  ssh jp 'cat /tmp/openssh-test.txt && rm /tmp/openssh-test.txt'
  rm /tmp/openssh-test.txt
  ```
- **验收标准**：
  - ✅ `ssh jp` 不挂起，5 秒内返回 prompt 或命令输出
  - ✅ `-vvv` 输出含 `Authenticated to ... using "publickey"`
  - ✅ `-vvv` 输出 `Remote protocol version` 显示 `OpenSSH_*`，**不是** `Tailscale`
  - ✅ scp 双向传输成功
  - ✅ `~/.ssh/known_hosts` 新增 `100.82.241.21` 条目
- **潜在风险**：
  - 若仍走到 Tailscale SSH（端口 22 未监听 sshd 进程）→ 检查远端 `ss -tlnp | grep :22` 确认是 sshd 在监听而不是 tailscaled
  - 若挂起 → 远端可能没 sshd（罕见），回到 Task 1.1 重新确认
- **依赖**：Task 1.2、Task 1.3 完成

#### Task 1.5: jp-node 防火墙现状审计（不修改）

- **目标**：搞清 jp-node 当前 22 端口对公网的暴露程度，为 Phase 3 决策提供依据
- **修改内容**：无（只读审计）
- **执行步骤**：
  ```bash
  # 1. 远端本地视角
  ssh jp 'ss -tlnp | grep :22; iptables -L INPUT -n -v | head -20; \
          (ufw status 2>/dev/null || firewall-cmd --list-all 2>/dev/null || echo "no managed fw")'

  # 2. 公网视角（从本机走 clash 出去）
  curl --connect-timeout 5 -sI telnet://47.245.32.3:22 2>&1 | head -5 || \
    nc -zv -w 5 47.245.32.3 22 2>&1
  ```
- **验收标准**：
  - ✅ 记录：sshd 监听地址（`0.0.0.0:22` / `100.82.241.21:22` / 仅 `[::]:22`）
  - ✅ 记录：现有防火墙规则
  - ✅ 记录：22 端口公网是否可达
  - ✅ 记录：云厂商安全组（需登录控制台查看，记入 Phase 3 输入）
- **潜在风险**：无
- **依赖**：Task 1.4 完成（确认 OpenSSH 通路后再审计）

### Phase 2: 推广到 us-node 和 SynologyNAS923

#### Task 2.1: us-node 完整流程（重复 Task 1.1 → 1.5）

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

#### Task 3.1: 云厂商安全组核查（jp-node、us-node）

- **目标**：确认公网 IP 上 22 端口的暴露范围，决定是否收紧
- **修改内容**：仅检查，不一定修改
- **执行步骤**：
  1. 登录 jp-node 所在云厂商控制台（阿里云/Vultr/etc.），查看安全组入站规则中 22 端口的源 IP 范围
  2. 同样检查 us-node
- **决策矩阵**：
  | 现状 | 建议动作 |
  |------|---------|
  | 22 端口对 0.0.0.0/0 开放 | 改为限制到本人公网 IP；或彻底关闭，依赖 Tailscale 入站 |
  | 22 端口仅对特定 IP | 维持，或改为彻底关闭依赖 Tailscale |
  | 22 端口已关闭 | 保持，确认 OpenSSH 仅经 Tailscale 可达 |
- **验收标准**：
  - ✅ 每个云节点的 22 端口暴露范围已记录
  - ✅ 已做出"是否收紧"的明确决策
- **潜在风险**：错误关闭安全组规则可能锁死自己；每次改动前确认 Tailscale 通路可用作为退路
- **依赖**：Phase 1、Phase 2 完成

#### Task 3.2: （可选）远端 sshd_config 加固

- **目标**：在确认 OpenSSH 公钥路径稳定后，禁用密码登录、限制 root 直接登录
- **触发条件**：仅在以下都满足时才执行：
  - Phase 1/2 全部成功超过 7 天且每天都正常使用过
  - 云厂商安全组已收紧或已确认 22 端口仅经 Tailscale 可达
  - 用户有时间应对锁死风险（不在出差/重要任务期间）
- **修改内容**（每节点独立判断）：
  - `/etc/ssh/sshd_config`：
    ```
    PasswordAuthentication no
    PubkeyAuthentication yes
    PermitRootLogin prohibit-password   # 允许 root 但仅公钥
    ```
- **修改边界**：
  - 不改 `Port`（保持 22）
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

- [ ] `ssh jp 'echo ok'` 返回 ok（不挂起，不询问密码）
- [ ] `ssh us 'echo ok'` 返回 ok
- [ ] `ssh nas 'echo ok'` 返回 ok
- [ ] `ssh -G jp` 显示 IdentityFile = `~/.ssh/id_ed25519`，User = `root`
- [ ] 现有别名 `ssh -G sugon-hf` 输出与变更前一致（diff 应为空）
- [ ] `tailscale status` 仍显示本机 online，所有目标 peer 直连或 DERP 可达
- [ ] `tailscale ssh root@jp-node 'echo ok'` 仍能工作（应急后备未失效）
- [ ] 本机 `~/.ssh/config.bak.<timestamp>` 存在
- [ ] 每个改过 sshd_config 的远端节点 `/etc/ssh/sshd_config.bak.<timestamp>` 存在
- [ ] 公网视角 `nc -zv <public-ip> 22` 行为符合 Phase 3 决策（开放或关闭）
- [ ] Tailscale 健康警告（DNS）仍在排查列表中（本计划不解决，但记录）

## 已知局限

- **Tailscale 离线时不可用**：本方案依赖 100.x 网段，离线时只能走云厂商 VNC 或公网 SSH（如果安全组开放）。未在本计划范围
- **Tailscale IP 变化**：peer 重装会导致 IP 变化，需手动更新 `~/.ssh/config`
- **Magic DNS 仍未修复**：`tailscale ssh root@jp-node`（按主机名）受 DNS 警告影响；本方案改用 IP 直连规避此问题
- **DSM 升级影响**：Synology DSM 大版本升级可能重置 sshd 配置，需在升级后回归测试 nas 别名
- **Windows 客户端配置不在本计划**：Windows 上需要单独配置 OpenSSH client + `%USERPROFILE%\.ssh\config`，沿用本计划的别名命名约定即可

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 2 | 2 | 0 |
| R2 | 可执行性 | 3 | 3 | 0 |
| R3 | 风险与边缘 | 4 | 4 | 0 |
| **终止** | **T1 — 收敛终止** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整（含非目标）|
| 技术方案 | 完整（含 6 项关键决策）|
| Error & Rescue Map | 9 条路径，2 条已知局限明示 |
| 执行计划 | 4 Phase，11 Task |
| 回归检查清单 | 10 项，含 Tailscale 健康基线 |
| 已知局限 | 5 项明示 |

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
- **Issue R3-3**: Task 3.3 防火墙顺序未强调"先 allow 再 enable" → 加错误/正确顺序对比 ✅ 已修正
- **Issue R3-4**: 未涵盖云厂商安全组层面的暴露 → 新增 Task 3.1 云厂商核查 ✅ 已修正

## Pre-Delivery Audit (Level: L1-Lite)

| § | Check | Status | Note |
|---|-------|--------|------|
| 1 | 单位/术语一致性 | ✅ PASS | sshd/Tailscale/control plane 等术语贯穿一致 |
| 1 | 命令可复制性 | ✅ PASS | 所有 shell 命令使用真实 IP 与现有 key 文件名 |
| 1 | 引用资源真实性 | ✅ PASS | `id_ed25519`、`id_ed25519_nas`、`~/.ssh/config` 已验证存在；jp/us 别名已验证不冲突 |

Auditor: Plan Architect | Date: 2026-04-22
