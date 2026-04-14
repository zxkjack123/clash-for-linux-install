# Fix Tailscale Periodic Disconnect & Monitor False-Positive Alerts

## 背景与目标

- **问题/需求描述**：
  1. 本机到 JP 节点的 Shadowsocks 代理会周期性断开，需要 SSH 到 JP 节点重新认证 Tailscale 后恢复。
  2. 健康监控每 10 分钟误报 `[CRITICAL] Clash服务异常`（至今已累计 2000+ 条），其成因是 cron 环境下 `systemctl --user is-active mihomo` 因缺少 `XDG_RUNTIME_DIR` 而永远返回失败。
  3. `trigger_auto_fix("service_down")` 中的 `systemctl --user restart` 在 cron 中也静默失败，同理 `runtime_guard.sh` 的自愈重启亦然。

- **根因分析**：
  - **断连根因**：Tailscale 节点 key 默认 180 天过期（JP 节点 key 将于 2026-06-01 过期）。过期后 WireGuard 隧道中断，SS 代理随之不可达。
  - **误报根因**：`network_health_monitor.sh` 的 `check_clash_service()` 先调用 `systemctl --user is-active $SERVICE`。Cron 执行时没有 `XDG_RUNTIME_DIR=/run/user/$(id -u)`，导致 D-Bus 连接失败，`systemctl --user` 永远返回 exit 1，即使 mihomo 用户单元实际 active。

- **目标**：
  1. 禁用 Tailscale 节点 key 过期，消除周期性断连。
  2. 修复 cron 环境中 `systemctl --user` 的 D-Bus 访问问题，消除误报。
  3. 增强 `check_clash_service()` 的鲁棒性，添加 process-level 兜底检测。

- **非目标（不做什么）**：
  - 不重构整个 network_health_monitor.sh 的架构 — 仅修复与服务检测相关的路径
  - 不改变 cron 调度频率或监控覆盖范围
  - 不修改 Shadowsocks 或 mihomo 本身的配置
  - 不改动 `setup_monitoring_cron.sh` 的安装逻辑结构（只在其生成的 crontab 条目前添加环境变量）

- **已有代码/流程复用分析**：
  - `load_env.sh`：复用（已被 monitor 的 `source`），但不在其中注入 XDG — 职责不符
  - `check_clash_service()`：原地改造（添加 fallback 逻辑）
  - `trigger_auto_fix("service_down")`：原地改造（添加环境保障）
  - `setup_monitoring_cron.sh`：原地改造（在 crontab 模板中注入 `XDG_RUNTIME_DIR`）

## 技术方案

- **方案概述**：
  1. **Tailscale Admin Console**：在 Web 控制台对 `jp-node` 和 `gw-precision-5820-tower` 两台机器 Disable key expiry（手动操作，非代码）。
  2. **Cron 环境修复**：在 `setup_monitoring_cron.sh` 生成的 crontab 模板头部添加 `XDG_RUNTIME_DIR=/run/user/$(id -u)` 环境变量声明。
  3. **服务检测增强**：在 `check_clash_service()` 中，当 `systemctl --user is-active` 失败时，fallback 到 `pgrep -u "$USER" -f "$SERVICE"` 检测进程。
  4. **自愈重启环境保障**：在 `trigger_auto_fix("service_down")` 和 `runtime_guard.sh` 的 `systemctl --user restart` 调用前，确保 `XDG_RUNTIME_DIR` 已设置。

- **关键设计决策**：
  - 选择在 crontab 模板层面注入 `XDG_RUNTIME_DIR` 而非在每个脚本内部硬编码 — 因为这是 cron 执行环境的全局问题，修一处影响所有任务。
  - `check_clash_service()` 仍优先使用 `systemctl --user`（语义更准确），仅在其失败时 fallback 到 `pgrep`，避免 "僵尸进程存在但服务不健康" 的场景。
  - 不使用 `systemctl` 的 system-level 检测（`systemctl is-active mihomo`），因为当前部署使用的是用户级单元。

- **影响范围**：
  - `vpn-tools/network_health_monitor.sh`：修改 `check_clash_service()` 函数 + `trigger_auto_fix("service_down")` 分支
  - `script/runtime_guard.sh`：修改 line 535 附近的 `systemctl --user restart` 调用
  - `vpn-tools/setup_monitoring_cron.sh`：修改 crontab 模板头部
  - Tailscale Admin Console：手动操作，非代码变更

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| `systemctl --user is-active` in cron | D-Bus 连接失败 (exit 1) | 环境缺失 | N→Y | fallback 到 `pgrep` 检测 + crontab 注入 `XDG_RUNTIME_DIR` | 修复前：每10分钟误报 CRITICAL；修复后：正常 |
| `systemctl --user restart` in cron (auto-fix) | D-Bus 连接失败，重启静默失败 | 环境缺失 | N→Y | 确保 `XDG_RUNTIME_DIR` 在调用前已设置 | 修复前：自愈无效且不报真因；修复后：重启可工作 |
| `pgrep -f "$SERVICE"` fallback | 匹配到非目标进程（如 `vim mihomo.yaml`） | 误匹配 | Y | 使用 `pgrep -u "$USER" -x "$SERVICE"` 精确匹配可执行文件名 | 几乎不会误匹配 |
| Tailscale key 过期 | JP 节点隧道断开 | 远端认证 | N→Y | Disable key expiry in Admin Console | 修复前：每 ~180 天断连一次；修复后：永不因 key 过期断连 |
| Tailscale Admin Console 操作失误 | 选错节点 / 操作错误 | 人为失误 | Y | 验收标准要求检查 `tailscale whois` 确认 KeyExpiry="0001-01-01T00:00:00Z"（表示永不过期） | 可回滚（重新启用 key expiry） |
| `XDG_RUNTIME_DIR=/run/user/$(id -u)` 在 crontab 中不生效 | 某些 cron 实现不展开 `$(...)` | 语法兼容 | Y | 在 `setup_monitoring_cron.sh` 中预计算 UID 写入静态值 | 降级为修复前行为（有 pgrep fallback 兜底） |

## 执行计划

### Phase 1: Tailscale Key 过期修复（手动操作）

#### Task 1.1: 禁用 JP 节点和本机的 Tailscale Key 过期
- **目标**：消除 Tailscale key 180 天过期导致的周期性断连
- **修改内容**：
  - 登录 https://login.tailscale.com/admin/machines
  - 对 `jp-node` → `...` → **Disable key expiry**
  - 对 `gw-precision-5820-tower` → `...` → **Disable key expiry**
- **修改边界**：不修改其他节点的设置；不修改 Tailscale ACL 或路由配置
- **测试要求**：
  - 运行 `tailscale whois --json 100.82.241.21 | python3 -c "import sys,json; n=json.load(sys.stdin)['Node']; print('KeyExpiry:', n.get('KeyExpiry','?'))"`
  - 预期输出：`KeyExpiry: 0001-01-01T00:00:00Z`（Tailscale 用此值表示永不过期）
  - 对本机 100.94.75.11 执行同样检查
- **验收标准**：
  - ✅ `jp-node` 的 KeyExpiry 为 `0001-01-01T00:00:00Z`
  - ✅ `gw-precision-5820-tower` 的 KeyExpiry 为 `0001-01-01T00:00:00Z`
  - ✅ `tailscale ping --c 3 100.82.241.21` 返回 pong 且延迟 <200ms
- **潜在风险**：禁用 key expiry 意味着即使凭证泄露，节点 key 也不会自动失效。对于私人网络这是可接受的安全折衷。如果账户安全有疑虑，可改用较长有效期（如 365 天）而非永不过期。

### Phase 2: 修复 Cron 环境中 `systemctl --user` 失败问题

#### Task 2.1: 在 `check_clash_service()` 中添加 pgrep 兜底检测
- **目标**：即使 `systemctl --user is-active` 因 D-Bus 不可用而失败，仍能正确检测 mihomo 进程存活
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：修改 `check_clash_service()` 函数（约 line 82-111）
  - 将原来的：
    ```bash
    if ! systemctl --user is-active "$SERVICE" &>/dev/null; then
        status="CRITICAL"
        msg="Clash服务未运行"
        echo "$status|$msg"
        return 1
    fi
    ```
  - 改为：
    ```bash
    if ! systemctl --user is-active "$SERVICE" &>/dev/null; then
        # Fallback: cron 环境可能缺少 XDG_RUNTIME_DIR，systemctl --user 会失败
        # 用进程检测兜底
        if ! pgrep -u "$(id -u)" -x "$SERVICE" &>/dev/null; then
            status="CRITICAL"
            msg="Clash服务未运行"
            echo "$status|$msg"
            return 1
        fi
    fi
    ```
- **修改边界**：不修改 `check_clash_service()` 中的 API 检测部分（line 92-109）；不修改 `perform_health_check()` 调用逻辑；不修改 `vpn-tools/alert_notification.sh`
- **测试要求**：
  - 模拟 cron 环境运行：`env -i HOME="$HOME" USER="$USER" PATH="/usr/bin:/usr/sbin:/bin" bash -c 'source vpn-tools/network_health_monitor.sh; check_clash_service; echo "exit=$?"'`（注：这需要脚本可 source）
  - 替代验证：`env -i HOME="$HOME" PATH="/usr/bin:/bin" pgrep -u "$(id -u)" -x mihomo && echo OK`
  - 预期输出：输出 mihomo PID 并打印 OK
  - 等待下一个 10 分钟 cron 周期，检查 `tail -5 ~/.local/share/clash/logs/monitor_cron.log`
  - 预期输出：不再出现 `[CRITICAL] Clash服务异常`，而是正常进入健康评分逻辑
- **验收标准**：
  - ✅ 在正常终端中 `check_clash_service` 行为不变（systemctl --user 仍成功）
  - ✅ 在模拟 cron 环境中（无 XDG_RUNTIME_DIR），`pgrep` 兜底成功检测到 mihomo
  - ✅ 等待一个 cron 周期后，`monitor_cron.log` 不再出现 "Clash服务异常"
- **潜在风险**：`pgrep -x` 精确匹配二进制名，如果 mihomo 以其他名称运行（如 `clash`），需要确认 `$SERVICE` 变量值与实际进程名一致。已通过 `pgrep -u $(id -u) -x "$SERVICE"` 限定用户 + 精确名，误匹配概率极低。

#### Task 2.2: 修复 `trigger_auto_fix("service_down")` 中的 `systemctl --user restart`
- **目标**：确保 cron 触发的自愈重启能实际工作
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：修改 `trigger_auto_fix()` 函数中 `"service_down"` 分支（约 line 337-342）
  - 在 `systemctl --user restart` 前确保环境变量：
    ```bash
    "service_down")
        log "尝试重启服务..."
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        systemctl --user restart "$SERVICE" || true
        sleep 5
        ;;
    ```
- **修改边界**：不修改其他 auto_fix 分支（`ai_fail`, `streaming_fail`, `runtime_issues`）；不修改 `CHECK_ONLY` / `AUTO_FIX` 守卫逻辑
- **测试要求**：
  - 运行 `grep -A5 '"service_down"' vpn-tools/network_health_monitor.sh` 确认代码正确
  - 运行 `bash -n vpn-tools/network_health_monitor.sh` 确认语法无误
  - 预期输出：无错误输出
- **验收标准**：
  - ✅ `service_down` 分支在 `systemctl --user restart` 前有 `export XDG_RUNTIME_DIR=...`
  - ✅ `bash -n` 语法校验通过
- **潜在风险**：`/run/user/$(id -u)` 在某些非标准系统上可能不存在。但目标系统（Ubuntu/Debian desktops with systemd）总是有此路径。`${XDG_RUNTIME_DIR:-...}` 保证不覆盖已有值。

#### Task 2.3: 修复 `runtime_guard.sh` 中的 `systemctl --user restart` 环境
- **目标**：确保 runtime_guard 的自愈重启在 cron 中生效
- **修改内容**：
  - 文件 `script/runtime_guard.sh`：在 line 535 的 `systemctl --user restart` 前添加环境保障
  - 将：
    ```bash
    mv "$TMP_FIX" "$RUNTIME" || fail "替换 runtime 失败"
    systemctl --user restart "$SERVICE" >/dev/null 2>&1 && ...
    ```
  - 改为：
    ```bash
    mv "$TMP_FIX" "$RUNTIME" || fail "替换 runtime 失败"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    systemctl --user restart "$SERVICE" >/dev/null 2>&1 && ...
    ```
- **修改边界**：不修改 `runtime_guard.sh` 的其他检测逻辑、JSON 输出格式、锁机制、alert hook
- **测试要求**：
  - 运行 `bash -n script/runtime_guard.sh` 确认语法无误
  - 运行 `grep -B1 -A1 'systemctl --user restart' script/runtime_guard.sh` 确认环境注入位置正确
  - 预期输出：`systemctl --user restart` 前一行有 `export XDG_RUNTIME_DIR=...`
- **验收标准**：
  - ✅ `bash -n` 语法校验通过
  - ✅ `systemctl --user restart` 前有 `export XDG_RUNTIME_DIR` 设置
- **潜在风险**：`runtime_guard.sh` 使用 `set -euo pipefail`，`export` 命令不会失败；`$(id -u)` 在 cron 中可用。风险极低。

#### Task 2.4: 在 `setup_monitoring_cron.sh` 的 crontab 模板中注入 `XDG_RUNTIME_DIR`
- **目标**：从源头确保所有 cron 任务都有正确的 systemd 用户会话环境
- **修改内容**：
  - 文件 `vpn-tools/setup_monitoring_cron.sh`：在生成的 crontab 头部注释后、任务条目前，添加环境变量声明
  - 在 `# ===== Clash 网络监控任务 =====` 注释块后添加：
    ```
    XDG_RUNTIME_DIR=/run/user/$(id -u)
    ```
  - 注意 crontab 的环境变量赋值语法不支持 `$()`，需在脚本中预计算 UID 写入静态值：
    ```bash
    local _uid
    _uid=$(id -u)
    cat >> "$temp_cron" <<EOF
    XDG_RUNTIME_DIR=/run/user/$_uid
    EOF
    ```
- **修改边界**：不修改现有 crontab 任务的命令、频率、日志路径；不修改 `setup_monitoring_cron.sh` 的参数解析逻辑
- **测试要求**：
  - 运行 `bash -n vpn-tools/setup_monitoring_cron.sh` 确认语法无误
  - 运行 `bash vpn-tools/setup_monitoring_cron.sh --dry-run 2>&1 | grep 'XDG_RUNTIME_DIR'`（若有 dry-run 支持）
  - 若无 dry-run，则在代码中确认 `_uid=$(id -u)` + `XDG_RUNTIME_DIR=/run/user/$_uid` 的模板写入逻辑
  - 安装后验证：`crontab -l | grep XDG_RUNTIME_DIR`
  - 预期输出：`XDG_RUNTIME_DIR=/run/user/1000`
- **验收标准**：
  - ✅ `bash -n` 语法校验通过
  - ✅ 生成的 crontab 包含 `XDG_RUNTIME_DIR=/run/user/<UID>` 行
  - ✅ 该环境变量行出现在所有 `*/10 * * * *` 任务之前
- **潜在风险**：重新运行 `setup_monitoring_cron.sh` 会重写 crontab 的 Clash 部分。已有逻辑会保留非 Clash 条目（`grep -v` 旧条目），所以不丢失其他 cron 任务。但如果用户手动修改过 Clash cron 条目，那些修改会被覆盖。

### Phase 3: 验证与清理

#### Task 3.1: 端到端验证
- **目标**：确认所有修复生效，误报消除，Tailscale 永不过期
- **修改内容**：
  - 无代码修改，仅执行验证命令
- **修改边界**：不修改任何文件
- **测试要求**：
  1. Tailscale key 验证：
     ```bash
     tailscale whois --json 100.82.241.21 | python3 -c "import sys,json; n=json.load(sys.stdin)['Node']; assert n['KeyExpiry'] == '0001-01-01T00:00:00Z', f'JP key still expires: {n[\"KeyExpiry\"]}'; print('JP: key never expires ✓')"
     tailscale whois --json 100.94.75.11 | python3 -c "import sys,json; n=json.load(sys.stdin)['Node']; assert n['KeyExpiry'] == '0001-01-01T00:00:00Z', f'Local key still expires: {n[\"KeyExpiry\"]}'; print('Local: key never expires ✓')"
     ```
  2. 监控修复验证（等待一个 cron 周期后）：
     ```bash
     # 检查最近一次 monitor_cron.log 不含误报
     tail -20 ~/.local/share/clash/logs/monitor_cron.log | grep -c 'Clash服务异常'
     # 预期输出: 0
     ```
  3. 代理连通性验证：
     ```bash
     curl -x http://127.0.0.1:7890 -s --connect-timeout 5 --max-time 10 -o /dev/null -w "HTTP %{http_code}\n" https://www.google.com
     # 预期输出: HTTP 200
     ```
- **验收标准**：
  - ✅ 两台机器 Tailscale key 均为永不过期
  - ✅ 至少 3 个 cron 周期（30 分钟）内无新增 "Clash服务异常" 告警
  - ✅ 代理连通性测试 HTTP 200

#### Task 3.2: 清理历史误报日志（可选）
- **目标**：清除累积的 2000+ 条误报告警，恢复日志可读性
- **修改内容**：
  - 执行 `cp ~/.local/share/clash/logs/alerts.log ~/.local/share/clash/logs/alerts.log.bak-$(date +%Y%m%d)`
  - 从 `alerts.log` 中过滤掉 "Clash服务异常" 行：
    ```bash
    grep -v 'Clash服务异常' ~/.local/share/clash/logs/alerts.log.bak-* > ~/.local/share/clash/logs/alerts.log
    ```
- **修改边界**：只操作 `alerts.log`；不删除备份；不修改 `health_alerts.log`（保留完整历史以供审计）
- **测试要求**：
  - 运行 `wc -l ~/.local/share/clash/logs/alerts.log` 确认行数大幅减少
  - 运行 `ls -la ~/.local/share/clash/logs/alerts.log.bak-*` 确认备份文件存在
- **验收标准**：
  - ✅ `alerts.log` 中不含 "Clash服务异常" 行
  - ✅ 备份文件 `alerts.log.bak-YYYYMMDD` 存在
- **潜在风险**：清除日志不可逆（但有备份）。如果 grep -v 出错可能清空文件，但 pipeline 保证了先读后写。

## 回归检查清单

- [ ] `bash -n vpn-tools/network_health_monitor.sh` — 语法校验通过
- [ ] `bash -n script/runtime_guard.sh` — 语法校验通过
- [ ] `bash -n vpn-tools/setup_monitoring_cron.sh` — 语法校验通过
- [ ] 正常终端中 `check_clash_service` 仍输出 `OK|` 且 exit 0
- [ ] 模拟 cron 环境（`env -i HOME=... PATH=...`）中 `pgrep -u $(id -u) -x mihomo` 成功
- [ ] 代理连通性不受影响：`curl -x http://127.0.0.1:7890 https://www.google.com` 返回 200
- [ ] `tailscale ping 100.82.241.21` 正常
- [ ] 至少 3 个 cron 周期无新增 "Clash服务异常" 告警
- [ ] `crontab -l` 中有 `XDG_RUNTIME_DIR=/run/user/1000`（重新安装 cron 后）

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 3 | 3 | 0 |
| R2 | 可执行性 | 2 | 2 | 0 |
| R3 | 风险与边缘 | 1 | 1 | 0 |
| **终止** | **T1 — 收敛终止（R3 issues = 0）** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整（问题描述、根因、目标、非目标、复用分析均存在） |
| 技术方案 | 完整（概述、决策、影响范围） |
| Error & Rescue Map | 6 条路径覆盖，0 CRITICAL GAP |
| 执行计划 | 3 Phase, 7 Task |
| 回归检查清单 | 9 项检查，含项目特定项 |
| 已知局限 | 无 |

### R1 Issues（结构完整性）
- **Issue R1-1**: Error & Rescue Map 中缺少 `pgrep` 误匹配场景 → 已添加 `pgrep -x` 精确匹配分析行 ✅ 已修正
- **Issue R1-2**: Task 2.4 缺少 crontab 中 `$()` 展开兼容性的讨论 → 在修改内容中明确改为脚本预计算 UID 写入静态值 ✅ 已修正
- **Issue R1-3**: 已有代码/流程复用分析缺少 `setup_monitoring_cron.sh` → 已补充 ✅ 已修正

### R2 Issues（可执行性）
- **Issue R2-1**: Task 2.1 的测试要求 "source network_health_monitor.sh" 不可行（脚本有 main 逻辑）→ 改为用 `env -i ... pgrep` 验证 fallback 路径，再等 cron 周期验证端到端 ✅ 已修正
- **Issue R2-2**: Task 2.4 验收标准中 "重新安装 cron 后" 未说明何时执行 → 在回归清单中明确标注 "(重新安装 cron 后)" ✅ 已修正

### R3 Issues（风险与边缘）
- **Issue R3-1**: Task 3.2 日志清理的 `grep -v` 如果源文件无匹配行会输出全部内容（非错误），但如果 alerts.log 为空则输出空文件 — 属正常行为，无需额外处理，但补充了 "pipeline 保证先读后写" 说明 ✅ 已修正
