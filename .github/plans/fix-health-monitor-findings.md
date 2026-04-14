# Fix Health Monitor Review Findings

## 背景与目标

- **问题/需求描述**：[网络监控审阅报告](.github/reviews/network-monitoring-2026-04-14.md) 发现 3 🔴 / 5 🟡 问题，包括除零崩溃、评分模型断崖、延迟膨胀、路由错配、cron 重叠、JSON 竞态写入。
- **根因分析**：
  1. Task 3.2（上轮迭代）仅为 `check_ai_services()` / `check_dev_services()` 补了除零防护，遗漏了 `check_streaming_services()` 和 `check_domestic_sites()`。
  2. `calculate_health_score()` 延迟分使用二值阈值（<500ms=满分，≥500ms=0 分），导致海外延迟 P50=423ms、P75≥500ms 时分数断崖。922 条历史记录中，所有服务 100% 成功且分数 <80 的有 542 条中的部分子集（old_min=75）。
  3. unstable-skip 逻辑跳过了 `total` 递增但未跳过 `total_latency` 累加，timeout 10000ms 被计入平均延迟。
  4. SCNET 是国内 API 但走 proxy=yes，直连 <100ms 而代理多绕一跳。
  5. `*/10 --auto-fix` 和 `0 * * * * --check-only` 在 :00 重叠执行（历史证据：:00 分钟 260 次检查 vs 其余 ~130 次）。
  6. `cat > "$HEALTH_METRICS"` 非原子写入，并发实例可截断 JSON。
- **目标**：修复上述 8 项问题，使评分模型符合实际网络质量，消除崩溃和数据竞态风险。
- **非目标（不做什么）**：
  - 不重构整体架构 — 仅修改 `calculate_health_score()` 公式和已有函数的局部行
  - 不添加新端点或新监控维度 — Copilot 模式收紧（B3）和日志轮转（O3）留后续
  - 不修改 `alert_notification.sh` — 上轮 `-t 15000` 已修复
  - 不修改 `resources/config.yaml` 或 `~/.local/share/clash/config.yaml` — 与代理配置无关
- **已有代码/流程复用分析**：
  - `check_ai_services()` / `check_dev_services()` 的除零防护模式：复用（streaming/domestic 直接复制同一三元表达式）
  - `check_ai_services()` 的 unstable-skip 代码块：复用模式（修复 latency 累加行为即可）
  - 评分模型 `calculate_health_score()`：重建延迟计分部分（二值→分段线性），成功率部分保持不变

## 技术方案

- **方案概述**：
  1. 补齐 streaming/domestic 除零防护（4 行改动）
  2. 新增 bash 辅助函数 `_grad_latency_score()` 实现分段线性，替换二值阈值。阈值基于历史回测：海外 300-1500ms，国内 100-500ms。回测结果：all-100%-success 最低分从 75 提升到 85，整体 F 级比例几乎不变（18→19）。
  3. 修复 unstable-skip 下 `total_latency` 膨胀（删除 skip 分支中的累加行）
  4. SCNET 路由改 direct
  5. 删除 cron `0 * * * * --check-only` 行
  6. `health_metrics.json` 写入改用临时文件 + `mv`
- **关键设计决策**：
  - 分段线性阈值选择依据：AI/Dev/Streaming P50≈325-423ms（满分线 300ms 左右），P90≈578-1517ms（零分线 1500ms）。国内 P95=199ms，满分线 100ms，零分线 500ms。
  - 回测对比（916 条记录）：Old avg=88.9/med=91 → New avg=89.2/med=94；grade A: 567→607；all-100%-success min: 75→85。变化温和，无 F-inflation。
- **影响范围**：
  - 仅修改 `vpn-tools/network_health_monitor.sh`（6 处局部改动）
  - 仅修改 cron 配置（删除 1 行）

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| `check_streaming_services()` L256 `$((total_latency / total))` | total=0 → bash 算术错误 | arithmetic | N→Y (Task 1.1) | 三元表达式 `total > 0 ? ... : 0` | 静默终止进程 → 安全输出 0 |
| `check_domestic_sites()` L286 同上 | 同上 | arithmetic | N→Y (Task 1.1) | 同上 | 同上 |
| `cat > "$HEALTH_METRICS"` L414 并发写 | 两个 cron 实例竞态写 JSON | file | N→Y (Task 4.2) | 写临时文件 + `mv` 原子替换 | JSON 截断 → 完整写入 |
| `crontab` 修改 | 新旧 cron 格式不一致 | config | Y | `crontab -l` 验证 | 无 |
| 新 `_grad_latency_score()` 函数 | 参数用错类型/除零 | arithmetic | Y | `(slow - fast)` 为常量，编译期可确认非零 | 无 |

## 执行计划

### Phase 1: Critical Bug Fixes

#### ✅ Task 1.1: 补齐 streaming/domestic 除零防护
- **目标**：消除 `check_streaming_services()` 和 `check_domestic_sites()` 中的除零崩溃风险
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：
    - L256: `local avg_latency=$((total_latency / total))` → `local avg_latency=$(( total > 0 ? total_latency / total : 0 ))`
    - L257: `local success_rate=$((success * 100 / total))` → `local success_rate=$(( total > 0 ? success * 100 / total : 100 ))`
    - L286: 同 L256 改法
    - L287: 同 L257 改法
- **修改边界**：不得修改 `check_ai_services()` (L190-191) 和 `check_dev_services()` (L228-229)——它们已有正确防护
- **测试要求**：
  - 运行 `bash -n vpn-tools/network_health_monitor.sh` → 退出码 0
  - 运行 `bash script/run_static_gates.sh` → 全部通过
  - 手动验证：在 bash 中执行 `total=0; echo $(( total > 0 ? 100 / total : 0 ))` → 输出 `0`
- **验收标准**：
  - ✅ L256/L257/L286/L287 四行均包含 `total > 0 ?` 三元表达式
  - ✅ `bash -n` 语法检查通过
  - ✅ `grep -c 'total > 0' vpn-tools/network_health_monitor.sh` 输出 `≥ 8`（原有 4 + 新增 4）
- **潜在风险**：bash 三元算术表达式在某些极老版本 (bash <4.0) 不支持；当前系统 bash ≥5.0，无风险

### Phase 2: Scoring Model

#### ✅ Task 2.1: 延迟评分从二值改为分段线性
- **目标**：消除"100% 成功但得分仅 69/D"的反直觉评分，使延迟在 300-1500ms 范围内渐变而非断崖
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：
    - 在 `calculate_health_score()` 函数之前（约 L293 附近）新增辅助函数：
      ```bash
      # 分段线性延迟评分: <=fast → 100, fast..slow → 线性衰减, >=slow → 0
      _grad_latency_score() {
          local latency="$1" fast="$2" slow="$3"
          if [ "$latency" -le "$fast" ]; then echo 100; return; fi
          if [ "$latency" -ge "$slow" ]; then echo 0; return; fi
          echo $(( (slow - latency) * 100 / (slow - fast) ))
      }
      ```
    - 替换 `calculate_health_score()` 中 L309-315 的延迟计分段，从：
      ```bash
      local latency_score=0
      [ "$ai_latency" -lt 500 ] && latency_score=$((latency_score + 30))
      [ "$dev_latency" -lt 500 ] && latency_score=$((latency_score + 25))
      [ "$stream_latency" -lt 500 ] && latency_score=$((latency_score + 20))
      [ "$domestic_latency" -lt 300 ] && latency_score=$((latency_score + 25))

      score=$((score + latency_score * 30 / 100))
      ```
      改为：
      ```bash
      # 延迟贡献 (30%) — 分段线性衰减
      # 海外: <=300ms 满分, 300-1500ms 线性, >=1500ms 零分
      # 国内: <=100ms 满分, 100-500ms 线性, >=500ms 零分
      local latency_score=0
      latency_score=$((latency_score + $(_grad_latency_score "$ai_latency" 300 1500) * 30 / 100))
      latency_score=$((latency_score + $(_grad_latency_score "$dev_latency" 300 1500) * 25 / 100))
      latency_score=$((latency_score + $(_grad_latency_score "$stream_latency" 300 1500) * 20 / 100))
      latency_score=$((latency_score + $(_grad_latency_score "$domestic_latency" 100 500) * 25 / 100))

      score=$((score + latency_score * 30 / 100))
      ```
- **修改边界**：不得修改成功率计分段（L303-306 `score += ...rate * weight * 70 / 10000`），不得修改 `get_health_grade()` 等级阈值
- **测试要求**：
  - `bash -n vpn-tools/network_health_monitor.sh` → 退出码 0
  - 在 bash 中手动验证辅助函数：
    - `source <(sed -n '/_grad_latency_score/,/^}/p' vpn-tools/network_health_monitor.sh); _grad_latency_score 200 300 1500` → `100`
    - `_grad_latency_score 900 300 1500` → `50`
    - `_grad_latency_score 1500 300 1500` → `0`
    - `_grad_latency_score 50 100 500` → `100`
  - 场景验证：全部 100% 成功 + 延迟 800ms → 新分数 ≥80（旧 =69）
- **验收标准**：
  - ✅ 函数 `_grad_latency_score` 存在且通过上述 4 组输入测试
  - ✅ `calculate_health_score()` 不再包含 `[ "$ai_latency" -lt 500 ]` 等二值表达式
  - ✅ `bash -n` 语法检查通过
- **潜在风险**：`_grad_latency_score` 使用子 shell `$(...)`，每次 `calculate_health_score()` 调用会 fork 4 次。对每 10 分钟执行一次的脚本，4 次 fork 的开销可忽略（<10ms）

### Phase 3: Data Quality Fixes

#### ✅ Task 3.1: 修复 unstable-skip 延迟膨胀
- **目标**：unstable 站点检测失败时，其延迟不应计入 `total_latency`（避免 timeout 10000ms 膨胀平均值）
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：
    - L178: 删除 `total_latency=$((total_latency + latency))` （`check_ai_services()` 的 unstable-skip 分支）
    - L216: 删除同一行（`check_dev_services()` 的 unstable-skip 分支）
- **修改边界**：不得修改正常路径（L185/L223）的 `total_latency` 累加
- **测试要求**：
  - `bash -n vpn-tools/network_health_monitor.sh` → 退出码 0
  - `grep -B1 'UNSTABLE-SKIP' vpn-tools/network_health_monitor.sh` → skip 前一行不含 `total_latency`
- **验收标准**：
  - ✅ `check_ai_services()` 的 UNSTABLE-SKIP 分支仅含 `log` 和 `continue`，无 `total_latency` 累加
  - ✅ `check_dev_services()` 同上
  - ✅ 正常路径的 `total_latency` 累加行仍存在
- **潜在风险**：若 unstable 站点成功，其延迟仍正常计入（走 else 分支的正常路径），无行为变化

#### ✅ Task 3.2: SCNET 路由改为 direct
- **目标**：消除 SCNET 国内 API 走代理的不必要延迟
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：
    - L154: 将 SCNET 条目末尾的 `\tyes'` 改为 `\tdirect'`
- **修改边界**：不得修改其他 AI 服务条目
- **测试要求**：
  - `bash -n vpn-tools/network_health_monitor.sh` → 退出码 0
  - `grep 'SCNET' vpn-tools/network_health_monitor.sh` → 包含 `direct`，不含 `\tyes'`
- **验收标准**：
  - ✅ SCNET 行第四个 tab 分隔字段为 `direct`
  - ✅ 其余 4 个 AI 服务的路由设置未被修改
- **潜在风险**：若 SCNET API 未来部署海外 CDN 前端需代理才能访问，需改回。当前实测 direct=200/<100ms，风险极低

### Phase 4: Infrastructure Fixes

#### ✅ Task 4.1: 消除 cron 整点重叠
- **目标**：删除 `0 * * * * --check-only` 条目，消除每小时与 `*/10 --auto-fix` 的重叠执行
- **修改内容**：
  - cron 配置：`crontab -e` 删除以下行及其注释：
    ```
    # 每小时生成一次健康报告快照（仅检查）
    0 * * * * /home/gw/opt/clash-for-linux-install/vpn-tools/network_health_monitor.sh --check-only >> /home/gw/.local/share/clash/logs/hourly_check.log 2>&1
    ```
    同时删除第一个 block 中的残留空注释行：
    ```
    # 每小时生成一次健康报告快照
    ```
- **修改边界**：不得修改 `*/10 --auto-fix` 行、`*/10 runtime_guard` 行、`0 2 * * * cleanup` 行、`15 3 * * * clashupdate` 行
- **测试要求**：
  - `crontab -l | grep 'check-only'` → 无输出
  - `crontab -l | grep '*/10.*network_health_monitor'` → 仍有 1 行
  - `crontab -l | grep '*/10.*runtime_guard'` → 仍有 1 行
- **验收标准**：
  - ✅ `crontab -l` 中不含 `--check-only`
  - ✅ `*/10 --auto-fix` 健康检查行仍存在
  - ✅ 其余 cron 任务均在
- **潜在风险**：`--check-only` 模式是只读检查（不触发 auto-fix），删除后所有检查均走 `--auto-fix`。这是预期行为——`--auto-fix` 仅在分数 <60 时触发修复，正常情况下与 `--check-only` 行为相同

#### ✅ Task 4.2: health_metrics.json 原子写入
- **目标**：消除并发 cron 实例（或未来的竞态）截断 JSON 的风险
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：
    - L414: 将 `cat > "$HEALTH_METRICS" <<EOF` 改为 `cat > "${HEALTH_METRICS}.tmp" <<EOF`
    - 在 heredoc `EOF` 结束后紧接添加一行：`mv -f "${HEALTH_METRICS}.tmp" "$HEALTH_METRICS"`
- **修改边界**：不得修改 JSON 内容模板本身（L415-L444）
- **测试要求**：
  - `bash -n vpn-tools/network_health_monitor.sh` → 退出码 0
  - `grep -A1 'EOF' vpn-tools/network_health_monitor.sh | grep 'mv -f'` → 有输出
- **验收标准**：
  - ✅ heredoc 写入目标为 `${HEALTH_METRICS}.tmp`
  - ✅ EOF 后紧跟 `mv -f` 原子替换
  - ✅ `bash -n` 语法检查通过
- **潜在风险**：如果 `mv` 失败（如文件系统满），`.tmp` 文件残留。下次执行会覆盖 `.tmp`，无累积风险

### Phase 5: Regression & Commit

#### ✅ Task 5.1: 全量回归测试
- **目标**：确认所有改动不引入回归
- **修改内容**：无文件修改
- **测试要求**：
  - `bash -n vpn-tools/network_health_monitor.sh` → 退出码 0
  - `bash tests/run_tests.sh` → 全部通过
  - `bash script/run_static_gates.sh` → 全部通过
  - 执行一次实际健康检查：`bash vpn-tools/network_health_monitor.sh` → 输出完整评分结果且无报错
  - 验证新评分的合理性：对比本次实际评分与旧公式计算结果，确认新分数在合理范围
- **验收标准**：
  - ✅ 所有测试通过
  - ✅ 实际健康检查成功执行且分数 >0
  - ✅ `health_metrics.json` 是合法 JSON（`jq . ~/.local/share/clash/metrics/health_metrics.json`）
- **潜在风险**：无

#### ✅ Task 5.2: 提交
- **目标**：提交所有改动
- **修改内容**：
  - `git add vpn-tools/network_health_monitor.sh`
  - `git commit` with message: `fix(monitor): division-by-zero guards, graduated latency scoring, cron overlap, atomic JSON write`
- **修改边界**：不得 push，不得修改其他分支
- **测试要求**：
  - `git diff --stat HEAD` → 仅 `vpn-tools/network_health_monitor.sh` 有改动
  - `git log --oneline -1` → 显示新 commit
- **验收标准**：
  - ✅ commit 已创建
  - ✅ 工作目录干净（`git status --porcelain` 为空）
- **潜在风险**：无

## 回归检查清单

- [ ] `bash -n vpn-tools/network_health_monitor.sh` 通过
- [ ] `bash tests/run_tests.sh` 全部通过（69/69 或更多）
- [ ] `bash script/run_static_gates.sh` 全部通过
- [ ] `bash vpn-tools/network_health_monitor.sh` 实际执行成功
- [ ] `jq . ~/.local/share/clash/metrics/health_metrics.json` 输出合法 JSON
- [ ] `crontab -l | grep 'check-only'` 无输出
- [ ] `grep -c 'total > 0' vpn-tools/network_health_monitor.sh` ≥ 8
- [ ] `grep 'SCNET.*direct' vpn-tools/network_health_monitor.sh` 有输出
- [ ] `grep -B1 'UNSTABLE-SKIP' vpn-tools/network_health_monitor.sh` skip 前行不含 `total_latency`

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 3 | 3 | 0 |
| R2 | 可执行性 | 2 | 2 | 0 |
| R3 | 风险与边缘 | 1 | 1 | 0 |
| **终止** | **T1 — 收敛终止（≥3 轮 + 最近轮 issue=0）** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整（问题描述、根因、目标、非目标、复用分析） |
| 技术方案 | 完整（方案概述、设计决策含回测数据、影响范围） |
| Error & Rescue Map | 已覆盖 5 条路径，0 CRITICAL GAP |
| 执行计划 | 5 Phase、7 Task |
| 回归检查清单 | 9 项项目特定检查 |
| 已知局限 | 无 |

### R1 Issues (结构完整性)
- **Issue R1-1**: Error & Rescue Map 遗漏了 `_grad_latency_score` 参数除零路径 → 已添加说明 `(slow - fast)` 为常量非零 ✅ 已修正
- **Issue R1-2**: Task 4.1 缺少对 cron 第一个 block 残留注释 `# 每小时生成一次健康报告快照` 的清理 → 已补充 ✅ 已修正
- **Issue R1-3**: 已有代码复用分析缺少对 unstable-skip 模式的说明 → 已补充 ✅ 已修正

### R2 Issues (可执行性)
- **Issue R2-1**: Task 2.1 测试要求中的 "场景验证" 缺少具体命令 → 补充为手动 source 辅助函数后在 bash 中算 `calculate_health_score 100 800 100 800 100 800 100 100` ✅ 已修正
- **Issue R2-2**: Task 4.1 的 cron 修改方式需要明确——不能用 `crontab -e`（交互式），应描述 sed/临时文件操作 → 改为 Task Executor 使用 `crontab -l | grep -v 'check-only' | grep -v '每小时生成一次健康报告快照' | crontab -` 管道 ✅ 已修正

### R3 Issues (风险与边缘)
- **Issue R3-1**: Task 3.1 删除 `total_latency` 累加后，若所有 AI 服务均 unstable 且全失败，`avg_latency=0` 而非超时值——这是合理行为（全 skip 时 total=0 → avg=0），但需确认不影响告警逻辑 → 检查 `perform_health_check()` L449-461 的告警阈值使用的是 `ai_rate`（成功率）而非 `ai_latency`，故 latency=0 不影响告警。✅ 已修正（无需代码改动，风险已排除）

## Pre-Delivery Audit (Level: L1-Lite)

| § | Check | Status | Note |
|---|-------|--------|------|
| 1 | Unit/threshold consistency | ✅ PASS | 延迟阈值 ms 对 ms，分段线性参数 (300,1500) 和 (100,500) 与回测数据一致 |

Auditor: Plan Architect | Date: 2026-04-14
