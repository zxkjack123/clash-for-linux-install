# Fix Monitor False-Positive "Clash服务异常" Alerts (v2)

## 背景与目标

- **问题/需求描述**：
  1. 健康监控持续误报 `[CRITICAL] Clash服务异常`（累计 2087 条），桌面通知干扰用户且掩盖真实告警。
  2. `runtime_guard.sh` 经 cron 调用时，`systemctl --user restart` 因缺少 D-Bus 环境而静默失败，自愈无效。
  3. 当前 crontab 是 2025-10-12 生成的旧版本，缺少 `--auto-fix` / `--check-only` 标志，且无环境变量声明。
  4. 原 plan（`fix-tailscale-disconnect-and-monitor-false-positives.md`）中的 XDG_RUNTIME_DIR 注入已在 `network_health_monitor.sh` 顶部手动应用（未 commit），将误报从 ~155 条/天降至 ~0，但在 `:00` 整点两个 cron 任务同时触发时仍偶发 2 条误报（如 2026-04-13 17:00）。

- **根因分析**：
  - **主因**：`check_clash_service()` 仅依赖 `systemctl --user is-active`，在 cron 环境中 D-Bus 偶尔连接失败（特别是两个 cron 实例同时启动时），导致误判服务未运行。
  - **辅因 1**：`trigger_auto_fix("service_down")` 中的 `systemctl --user restart` 和 `runtime_guard.sh` 的重启调用均未保障 `XDG_RUNTIME_DIR`，cron 中静默失败。
  - **辅因 2**：已安装的 crontab（2025-10-12 版）未传递 `--auto-fix`/`--check-only`，也无 `XDG_RUNTIME_DIR` 环境变量行。

- **目标**：
  1. 彻底消除 cron 环境下的 "Clash服务异常" 误报（添加 pgrep 兜底）
  2. 确保 cron 中 `systemctl --user restart` 能正常工作（runtime_guard.sh + network_health_monitor.sh）
  3. 重新生成 crontab，带正确的标志和环境变量
  4. 确认 Tailscale key expiry 状态并记录
  5. 清理历史误报日志

- **非目标（不做什么）**：
  - 不重构监控脚本的整体架构 — 仅修复 cron 环境兼容性
  - 不改变 cron 调度频率或监控覆盖范围
  - 不修改 mihomo/Clash 核心配置
  - 不修改 `sanitize_runtime.sh` — 从 cron 链路调用时不涉及 `--restart` 路径
  - 不修改仅由用户交互调用的脚本（`clashctl.sh`、`restart_clash_service.sh` 等）

- **已有代码/流程复用分析**：
  - `network_health_monitor.sh` 顶部 XDG 注入（lines 19-25）：复用（已存在于 working tree，本次正式 commit）
  - `check_clash_service()`：原地改造（添加 pgrep fallback）
  - `trigger_auto_fix("service_down")`：原地改造（添加 XDG export）
  - `setup_monitoring_cron.sh`：原地改造（在模板中注入 `XDG_RUNTIME_DIR`）
  - `runtime_guard.sh` line 535：原地改造（在 `systemctl --user restart` 前添加 XDG export）

## 技术方案

- **方案概述**：
  1. 在 `check_clash_service()` 中当 `systemctl --user is-active` 失败时，fallback 到 `pgrep -u "$(id -u)" -x "$SERVICE"` 检测进程存活。
  2. 在 `trigger_auto_fix("service_down")` 中 `systemctl --user restart` 前 export `XDG_RUNTIME_DIR`。
  3. 在 `runtime_guard.sh` 的 `systemctl --user restart` 前 export `XDG_RUNTIME_DIR`。
  4. 修改 `setup_monitoring_cron.sh` 模板，在 cron 任务区块顶部注入 `XDG_RUNTIME_DIR=/run/user/<UID>`。
  5. 重新安装 crontab（`--install --with-autofix`）。
  6. 确认 Tailscale key expiry 状态（Admin Console 或 CLI）。
  7. 清理 `alerts.log` 中的历史误报行。

- **关键设计决策**：
  - **pgrep -x**（精确匹配进程名）而非 `pgrep -f`（匹配命令行），避免误匹配编辑器打开了 mihomo.yaml 等场景。配合 `-u $(id -u)` 限定用户。
  - **XDG 注入采用 `${XDG_RUNTIME_DIR:-...}` 模式**：不覆盖交互环境中已有的值。
  - **crontab 模板注入 vs 脚本内注入**：两者同时保留——脚本内注入提供自包含可靠性，crontab 注入提供全局覆盖（惠及日后新增的 cron 脚本）。
  - **不对 `check_clash_service()` 乱序**：仍优先 `systemctl --user`（语义准确，能区分 enabled/disabled），pgrep 仅作最后防线。

- **影响范围**：
  - `vpn-tools/network_health_monitor.sh`：`check_clash_service()` 函数 + `trigger_auto_fix("service_down")` 分支（已有 XDG 顶部注入保留不变）
  - `script/runtime_guard.sh`：line 535 附近（`systemctl --user restart`）
  - `vpn-tools/setup_monitoring_cron.sh`：crontab 模板区块

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| `systemctl --user is-active` in cron | D-Bus socket 不可达 (exit 1) | 环境缺失/竞争 | Y | 顶部 XDG 注入 + pgrep fallback | 不再误报 |
| `pgrep -u $(id -u) -x "$SERVICE"` | `$SERVICE` 名与实际进程名不匹配 | 配置不一致 | Y | 使用 `$SERVICE` 变量（与 systemd 单元名一致），精确匹配 `-x` | 若名称不一致，仍走 CRITICAL 路径（不会比修复前更差） |
| `systemctl --user restart` in cron auto-fix | D-Bus 不可达 | 环境缺失 | N→Y | 调用前 `export XDG_RUNTIME_DIR` | 修复前自愈静默失败；修复后自愈可工作 |
| `runtime_guard.sh` systemctl restart | D-Bus 不可达 | 环境缺失 | N→Y | 调用前 `export XDG_RUNTIME_DIR` | 同上 |
| crontab `$(id -u)` 展开 | crontab 语法不支持 `$()` | 语法兼容 | Y | `setup_monitoring_cron.sh` 预计算 UID 写入静态值 | 无影响 |
| `setup_monitoring_cron.sh --install` 重写 crontab | 用户手动添加的 Clash cron 条目被覆盖 | 数据丢失 | Y | 先 `crontab -l > backup`；grep -v 仅移除 Clash 相关行；保留其他条目 | 非 Clash 条目不受影响 |

## 执行计划

### Phase 1: 修复 cron 环境中的服务检测与自愈

#### ✅ Task 1.1: 在 `check_clash_service()` 中添加 pgrep 兆底检测
- **目标**：当 `systemctl --user is-active` 因 D-Bus 不可达而失败时，用 `pgrep` 兜底检测进程是否存活
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：修改 `check_clash_service()` 函数（约 line 88-98）
  - 将：
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
        # Fallback: cron 环境中 D-Bus 可能偶发不可达，用进程检测兜底
        if ! pgrep -u "$(id -u)" -x "$SERVICE" &>/dev/null; then
            status="CRITICAL"
            msg="Clash服务未运行"
            echo "$status|$msg"
            return 1
        fi
    fi
    ```
- **修改边界**：不修改 `check_clash_service()` 中的 API 检测部分；不修改 `perform_health_check()` 调用逻辑；不修改 `alert()` 函数
- **测试要求**：
  - 语法校验：`bash -n vpn-tools/network_health_monitor.sh`
  - 模拟 cron 环境验证 pgrep 能找到进程（保留 USER 以便 id -u 解析）：
    ```bash
    env -i HOME="$HOME" USER="$USER" PATH="/usr/bin:/usr/sbin:/bin" bash -c 'pgrep -u "$(id -u)" -x mihomo && echo FOUND || echo NOT_FOUND'
    ```
    预期输出：mihomo PID + `FOUND`
  - 正常终端中验证 `systemctl --user is-active mihomo` 仍然优先生效（exit 0）
- **验收标准**：
  - ✅ `bash -n` 语法校验通过
  - ✅ 在剔除 `XDG_RUNTIME_DIR` 的环境中，pgrep fallback 能检测到 mihomo 进程
  - ✅ 在正常终端中，`systemctl --user` 路径仍优先执行（pgrep 不被触发）
- **潜在风险**：若 `$SERVICE` 值（`mihomo`）与实际二进制名称不一致，pgrep -x 匹配失败。验证方法：`pgrep -u $(id -u) -x mihomo` 确认能找到进程。

#### ✅ Task 1.2: 修复 `trigger_auto_fix("service_down")` 中的 XDG 缺失
- **目标**：确保 cron 环境触发自愈重启时 `systemctl --user restart` 能正常工作
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：修改 `trigger_auto_fix()` 函数中 `"service_down"` 分支（约 line 345-348）
  - 将：
    ```bash
        "service_down")
            log "尝试重启服务..."
            systemctl --user restart "$SERVICE" || true
            sleep 5
            ;;
    ```
  - 改为：
    ```bash
        "service_down")
            log "尝试重启服务..."
            export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
            systemctl --user restart "$SERVICE" || true
            sleep 5
            ;;
    ```
- **修改边界**：不修改其他 auto_fix 分支（`ai_fail`、`streaming_fail`、`runtime_issues`）
- **测试要求**：
  - 语法校验：`bash -n vpn-tools/network_health_monitor.sh`
  - 代码确认：`grep -A5 '"service_down"' vpn-tools/network_health_monitor.sh` 显示 `export XDG_RUNTIME_DIR` 在 `systemctl` 之前
- **验收标准**：
  - ✅ `bash -n` 语法校验通过
  - ✅ `service_down` 分支中 `systemctl --user restart` 前有 `export XDG_RUNTIME_DIR` 设置
- **潜在风险**：近乎零。`${XDG_RUNTIME_DIR:-...}` 不覆盖已有值，`/run/user/$(id -u)` 在 systemd 桌面系统上必然存在。

#### ✅ Task 1.3: 修复 `runtime_guard.sh` 中的 `systemctl --user restart` 环境
- **目标**：确保 runtime_guard 经 cron 调用自愈重启时能正常执行
- **修改内容**：
  - 文件 `script/runtime_guard.sh`：在 line 535 的 `systemctl --user restart` 前插入 XDG 保障
  - 将：
    ```bash
    mv "$TMP_FIX" "$RUNTIME" || fail "替换 runtime 失败"
    systemctl --user restart "$SERVICE" >/dev/null 2>&1 && { $JSON_OUT || ok "已自愈并重启"; } || { $JSON_OUT || warn "重启失败, 请手动检查"; }
    ```
  - 改为：
    ```bash
    mv "$TMP_FIX" "$RUNTIME" || fail "替换 runtime 失败"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    systemctl --user restart "$SERVICE" >/dev/null 2>&1 && { $JSON_OUT || ok "已自愈并重启"; } || { $JSON_OUT || warn "重启失败, 请手动检查"; }
    ```
- **修改边界**：不修改 `runtime_guard.sh` 的检测逻辑、JSON 输出格式、锁机制、alert hook
- **测试要求**：
  - 语法校验：`bash -n script/runtime_guard.sh`
  - 代码确认：`grep -B1 -A1 'systemctl --user restart' script/runtime_guard.sh` 显示 XDG export 在前
- **验收标准**：
  - ✅ `bash -n` 语法校验通过
  - ✅ `systemctl --user restart` 前一行有 `export XDG_RUNTIME_DIR=...`
- **潜在风险**：`runtime_guard.sh` 使用 `set -euo pipefail`。`export` 不会失败，`$(id -u)` 在 cron 中可用。风险极低。

### Phase 2: 更新 crontab 模板与重新安装

#### ✅ Task 2.1: 在 `setup_monitoring_cron.sh` crontab 模板中注入 `XDG_RUNTIME_DIR`
- **目标**：从 crontab 层面提供 `XDG_RUNTIME_DIR`，作为脚本内注入的双保险
- **修改内容**：
  - 文件 `vpn-tools/setup_monitoring_cron.sh`：在 `install_monitoring()` 函数中，cron 任务区块头部注释后插入环境变量
  - 在已有的 `cat >> "$temp_cron" <<EOF` 区块（约 line 77-82）中，在 `# 生成时间:` 行后、第一条 cron 命令前，添加 `XDG_RUNTIME_DIR=/run/user/$_uid`
  - 完整修改：在 `local temp_cron=$(mktemp)` 之后、crontab 写入之前，预计算 UID：
    ```bash
    local _uid
    _uid=$(id -u)
    ```
  - 模板区块改为：
    ```
    # ===== Clash 网络监控任务 =====
    # 由 setup_monitoring_cron.sh 自动生成
    # 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
    XDG_RUNTIME_DIR=/run/user/$_uid
    ```
- **修改边界**：不修改 cron 命令本身的频率/日志路径；不修改 `uninstall_monitoring()`；不修改参数解析逻辑；不修改 `show_status()`
- **测试要求**：
  - 语法校验：`bash -n vpn-tools/setup_monitoring_cron.sh`
  - 代码确认：`grep -A5 'Clash 网络监控任务' vpn-tools/setup_monitoring_cron.sh` 中有 `XDG_RUNTIME_DIR=/run/user/\$_uid`
- **验收标准**：
  - ✅ `bash -n` 语法校验通过
  - ✅ 模板输出中包含 `XDG_RUNTIME_DIR=/run/user/<UID>` 行
  - ✅ 环境变量行出现在所有 cron 任务命令之前
- **潜在风险**：重新运行 `setup_monitoring_cron.sh --install` 会重写 Clash cron 区块。已有逻辑用 `grep -v` 仅移除旧 Clash 条目，非 Clash 条目不受影响。用户手动修改的 Clash cron 行会被覆盖。

#### ✅ Task 2.2: 重新安装 crontab（手动执行）
- **依赖**：Task 2.1 已完成（模板已包含 XDG_RUNTIME_DIR）
- **目标**：将当前陈旧的 crontab（2025-10-12 版）更新为新模板生成的版本
- **修改内容**：
  - 手动执行：`bash vpn-tools/setup_monitoring_cron.sh --install --with-autofix`
- **修改边界**：不执行 `--with-optimizer`（按当前使用模式，不需要自动优化规则）
- **测试要求**：
  - 安装后验证 crontab 含 XDG：`crontab -l | grep XDG_RUNTIME_DIR`
    预期输出：`XDG_RUNTIME_DIR=/run/user/1000`
  - 验证 monitor 条目有 `--auto-fix`：`crontab -l | grep 'network_health_monitor'`
    预期输出：`*/10 * * * * .../network_health_monitor.sh --auto-fix >> ...`
  - 验证 cron 备份已创建：`ls -la ~/.local/share/clash/cron_backup_*.txt | tail -1`
- **验收标准**：
  - ✅ `crontab -l` 中有 `XDG_RUNTIME_DIR=/run/user/1000`
  - ✅ `network_health_monitor.sh` 条目带 `--auto-fix` 标志
  - ✅ `runtime_guard.sh` 条目带 `--auto-fix --cron` 标志
  - ✅ hourly 条目带 `--check-only` 标志
  - ✅ cron 备份文件存在
- **潜在风险**：crontab 中用户手动添加的 subscription update 条目（`15 3 * * * ... clashupdate ...`）不在 Clash 监控区块内，`grep -v` 不会误删。但需确认输出中该行仍保留。

### Phase 3: 验证与清理

#### ✅ Task 3.1: 确认 Tailscale Key Expiry 状态
- **目标**：确认 JP 节点和本机的 Tailscale key expiry 是否已禁用
- **修改内容**：无代码修改，仅诊断
- **修改边界**：不修改 Tailscale 设置
- **测试要求**：
  - 运行 `tailscale whois --json 100.82.241.21 | python3 -c "import sys,json; n=json.load(sys.stdin)['Node']; print('JP KeyExpiry:', n.get('KeyExpiry','ABSENT'))"`
  - 若输出 `ABSENT`（字段不存在）或 `0001-01-01T00:00:00Z`，表示 key expiry 已禁用
  - 若输出日期值（如 `2026-06-01T...`），则需手动在 Admin Console 禁用
- **验收标准**：
  - ✅ JP 节点 KeyExpiry 为 `ABSENT` 或 `0001-01-01T00:00:00Z`（已禁用）
  - ✅ 若未禁用，记录在此 task 中提醒用户手动操作
- **潜在风险**：`tailscale whois` JSON schema 随 CLI 版本变化，`KeyExpiry` 字段可能改名或嵌套。当前版本（观测）中该字段在禁用时直接缺失。若 CLI 无法确认，需通过 Admin Console Web UI 核实。

#### ✅ Task 3.2: 端到端验证
- **目标**：确认整体修复生效，误报消除
- **修改内容**：无代码修改，仅验证
- **修改边界**：不修改任何文件
- **测试要求**：
  1. 代理连通性验证：
     ```bash
     curl -x http://127.0.0.1:7890 -s --connect-timeout 5 --max-time 10 -o /dev/null -w "HTTP %{http_code}\n" https://www.google.com
     ```
     预期输出：`HTTP 200`
  2. 等待至少 2 个 cron 周期（20 分钟），然后检查：
     ```bash
     tail -20 ~/.local/share/clash/logs/monitor_cron.log | grep -c 'Clash服务异常'
     ```
     预期输出：`0`
  3. 等到整点 `:00`（两个 cron 任务同时触发），再确认：
     ```bash
     grep "$(date +%Y-%m-%d)" ~/.local/share/clash/logs/alerts.log | grep -c 'Clash服务异常'
     ```
     预期输出：`0`（或等于修复前已有的历史值 2，不再新增）
- **验收标准**：
  - ✅ 代理连通性 HTTP 200
  - ✅ 修复后的 cron 周期内不出现新的 "Clash服务异常" 行
  - ✅ 整点 `:00` 也不再出现误报
- **潜在风险**：若验证窗口内碰到 mihomo 真实崩溃（概率极低），会出现 CRITICAL 告警——此时是真实告警而非误报，需区分。

#### ✅ Task 3.3: 清理历史误报日志
- **目标**：清除 `alerts.log` 中累积的 2087 条 "Clash服务异常" 误报，恢复日志可读性
- **修改内容**：
  ```bash
  cp ~/.local/share/clash/logs/alerts.log ~/.local/share/clash/logs/alerts.log.bak-$(date +%Y%m%d)
  grep -v 'Clash服务异常' ~/.local/share/clash/logs/alerts.log.bak-$(date +%Y%m%d) > ~/.local/share/clash/logs/alerts.log || true
  ```
- **修改边界**：只操作 `alerts.log`；不删除备份文件；不修改 `health_alerts.log`
- **测试要求**：
  - 确认备份存在：`ls -la ~/.local/share/clash/logs/alerts.log.bak-*`
  - 确认误报已清除：`grep -c 'Clash服务异常' ~/.local/share/clash/logs/alerts.log`
    预期输出：`0`
  - 确认真实告警保留：`wc -l ~/.local/share/clash/logs/alerts.log`
    预期输出：行数 > 0（应保留 WARNING 等非误报条目）
- **验收标准**：
  - ✅ 备份文件 `alerts.log.bak-YYYYMMDD` 存在
  - ✅ `alerts.log` 中不含 "Clash服务异常" 行
  - ✅ 真实告警（如 "AI服务延迟过高"）保留
- **潜在风险**：`grep -v` 只移除含"Clash服务异常"的行，其他告警不受影响。`|| true` 防止 grep 无匹配时的非零退出。

### Phase 4: 提交

#### ✅ Task 4.1: 提交所有修改
- **目标**：将 Phase 1-2 的代码修改和已有的工作树改动一起提交
- **修改内容**：
  ```bash
  git add vpn-tools/network_health_monitor.sh script/runtime_guard.sh vpn-tools/setup_monitoring_cron.sh
  git commit -m "fix: eliminate cron false-positive 'Clash服务异常' alerts

  - Add pgrep fallback in check_clash_service() for cron D-Bus failures
  - Export XDG_RUNTIME_DIR before systemctl --user restart in auto-fix paths
  - Inject XDG_RUNTIME_DIR into crontab template for global cron coverage
  - Update AI/dev service check list (Copilot, Semantic Scholar)
  - Remove YouTube from streaming checks"
  ```
- **修改边界**：不 push 到远程（除非用户明确要求）
- **测试要求**：
  - `git diff --cached --stat` 确认只包含 3 个文件
  - `bash -n` 三个文件均通过
- **验收标准**：
  - ✅ 提交包含且仅包含 3 个修改文件
  - ✅ 不含敏感信息（token/secret）
- **潜在风险**：其他 working tree 修改（`resources/mixin.yaml`, `vpn-tools/optimize_vscode_copilot.sh`）不在此次提交范围。

## 回归检查清单

- [ ] `bash -n vpn-tools/network_health_monitor.sh` — 语法校验通过
- [ ] `bash -n script/runtime_guard.sh` — 语法校验通过
- [ ] `bash -n vpn-tools/setup_monitoring_cron.sh` — 语法校验通过
- [ ] 正常终端中 `systemctl --user is-active mihomo` 仍返回 0（pgrep 不被触发）
- [ ] 模拟 cron 环境：`env -i HOME="$HOME" PATH="/usr/bin:/bin" pgrep -u "$(id -u)" -x mihomo && echo OK` 返回 OK
- [ ] 代理连通性不受影响：`curl -x http://127.0.0.1:7890 https://www.google.com -sS -o /dev/null -w '%{http_code}'` 返回 200
- [ ] `crontab -l` 中有 `XDG_RUNTIME_DIR=/run/user/1000`
- [ ] `crontab -l` 中 `network_health_monitor.sh` 带 `--auto-fix`
- [ ] `crontab -l` 中 hourly 条目带 `--check-only`
- [ ] `crontab -l` 中 subscription update 条目仍保留
- [ ] 至少 3 个 cron 周期（含一个 `:00` 整点）无新增 "Clash服务异常" 告警
- [ ] `alerts.log` 中历史 "Clash服务异常" 行已清除（备份保留）

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 1 | 1 | 0 |
| R2 | 可执行性 | 2 | 2 | 0 |
| R3 | 风险与边缘 | 1 | 1 | 0 |
| **终止** | **T1 — 收敛终止（R3 剩余 0）** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整（问题描述、根因、目标、非目标、复用分析） |
| 技术方案 | 完整（概述、决策、影响范围） |
| Error & Rescue Map | 6 条映射，0 CRITICAL GAP |
| 执行计划 | 4 Phases, 9 Tasks |
| 回归检查清单 | 12 项项目特定检查 |
| 已知局限 | 1 项（见下） |

### 已知局限

- `script/sanitize_runtime.sh` line 504 也有 `systemctl --user restart "$SERVICE"` 调用（在 `--restart` 标志下触发），未包含 XDG 环境保障。当前 cron 链路（`runtime_guard.sh` → `sanitize_runtime.sh --file ... --verbose`）不传 `--restart`，因此不受影响。但如果未来有 cron 任务直接调用 `sanitize_runtime.sh --restart`，会遇到同样的 D-Bus 问题。建议后续迭代中统一处理。

### R1 Issues
- **Issue R1-1**: Task 3.1 缺少"潜在风险"字段 → ✅ 已修正（补充 tailscale whois schema 变化风险）

### R2 Issues
- **Issue R2-1**: Task 2.2 依赖 Task 2.1 未标注 → ✅ 已修正（添加依赖字段）
- **Issue R2-2**: Task 1.1 测试命令 `env -i` 未保留 USER 变量，可能导致 `id -u` 失败 → ✅ 已修正（添加 `USER="$USER"`）

### R3 Issues
- **Issue R3-1**: `sanitize_runtime.sh --restart` 在 cron 中有同样 XDG 问题 → ✅ 已记录在"已知局限"（当前 cron 链路不触发该路径，不阻断交付）
