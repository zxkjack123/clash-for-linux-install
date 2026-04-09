# Fix Supplementary Review Findings (2026-04-09)

## 背景与目标
- **问题/需求描述**：补充审查（`.github/reviews/codebase-supplement-2026-04-09.md`）发现 3 🔴 + 6 🟡 + 3 🟢 问题。本计划覆盖全部 🔴 和可快速修复的 🟡，共 9 项。
- **根因分析**：
  - B6/B7：与已修复的 B1 完全同类 —— `awk 'BEGIN{exit ...}'; [[ $? -eq 0 ]]` 在 `set -e` 下，awk 异常退出直接终止脚本。
  - Q6：mixin 合并回退路径为防止部署受阻，对每步 yq 操作加了 `|| true`，但缺少最终完整性校验，导致半废配置可能被静默采纳。
  - 其余为防御性编程缺失。
- **目标**：
  1. 修复 B6+B7（🔴 `set -e` + `$?`）+ B8（🟡 unquoted 数组）在 `test_ai_connectivity.sh`
  2. 强化 Q6（🔴 mixin 合并后校验）在 `clashctl.sh`
  3. 修复 Q7（🟡 无 yq 时的 YAML 基本校验）在 `update_clash_subscription.sh`
  4. 修复 Q8（🟡 订阅获取阶段无锁）在 `update_clash_subscription.sh`
  5. 修复 Q11（🟡 卸载遗漏 subscription refresh units）在 `uninstall.sh`
  6. 修复 S1（🟢 缺 network-online 依赖）在 `systemd/clash-subscription-refresh.service`
- **非目标（不做什么）**：
  - Q9 common.sh CWD-relative paths — 影响面广（所有 sourcing 脚本），需独立评估和全量测试
  - Q10 load_env.sh set -a 全局导出 — 属于架构级改动（需重构 .env 加载模式），风险大
  - S2 systemd 安全加固（NoNewPrivileges 等）— 增强型需求，不影响正确性
  - S3 URL scheme 限制 — 低风险，curl 本身不会自动执行危险 scheme
- **已有代码/流程复用分析**：
  - `_merge_sanitize_restart` 中已有 `flock` 锁机制：复用其模式，为 `update_clash_subscription.sh` 添加同类锁
  - `bash -n` + `run_static_gates.sh`：复用，作为每个 task 的回归验证
  - B1 修复模式（`if cmd; then ... fi` 替代 `cmd; [[ $? -eq 0 ]]`）：复用于 B6/B7

## 技术方案
- **方案概述**：逐文件精确修补。B6/B7/B8 集中在同一文件可合并为一个 task；Q6 单独 task（需谨慎修改合并逻辑的错误处理）；Q7/Q8 在同一文件可合并；Q11 + S1 各自独立。
- **关键设计决策**：
  - B6/B7：用 `if awk ...; then` 替代 `awk ...; [[ $? -eq 0 ]]`，保持单行风格不变
  - B8：`percentile()` 函数用 `mapfile -t arr < <(...)` 替代 `arr=($(...))`
  - Q6：在 `_merge_build_runtime` 回退路径 2 末尾，追加结构性完整性检查——验证 `proxy-groups` key 存在且为数组。若检查失败且 `$out_file.tmp` 非空，回退到 raw config（已有 `_error_quit` 在空文件时触发）。不移除 `|| true`（合并回退路径 2 的设计意图就是尽力而为），而是在最终 `mv` 前加校验门。
  - Q7：无 yq 时用 `grep -qE '(^proxies:|^proxy-groups:|^rules:)' "$TMP_DECODE"` 做最小结构检查
  - Q8：用 `flock` 包裹 fetch→backup→write 阶段，锁文件放在 `$XDG_RUNTIME_DIR`（与 `_merge_sanitize_restart` 保持一致模式）
  - Q11：在 `uninstall.sh` 清理列表中添加 `clash-subscription-refresh.{service,timer}`
  - S1：添加 `After=network-online.target` + `Wants=network-online.target`
- **影响范围**：
  - `vpn-tools/test_ai_connectivity.sh`（B6 + B7 + B8）
  - `script/clashctl.sh`（Q6）
  - `script/update_clash_subscription.sh`（Q7 + Q8）
  - `uninstall.sh`（Q11）
  - `systemd/clash-subscription-refresh.service`（S1）

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| B6: `awk 'BEGIN{exit !(v<0.3)}'` 成功率 ≥30% | awk exit 1 | 命令退出码 | N → Y | 改用 `if awk ...; then break; fi` | 修复前：脚本中断。修复后：继续正常轮次 |
| B7: `awk 'BEGIN{exit !(s>b)}'` 分数不大于当前最佳 | awk exit 1 | 命令退出码 | N → Y | 改用 `if awk ...; then ...; fi` | 修复前：最优节点选错。修复后：正确比较 |
| Q6: yq 合并回退 2 部分失败 | 半成品 config 写入 | 逻辑错误 | N → Y | 合并后校验 `proxy-groups` 存在且为数组 | 修复前：静默使用坏 config → mihomo 启动异常。修复后：校验失败时回退到 raw config 并打警告 |
| Q7: 无 yq 且订阅返回 HTML 错误页 | 非 YAML 写入为 config | 缺失校验 | N → Y | grep 基本结构标记 | 修复前：HTML 写为 config。修复后：拒绝并 exit 3 |
| Q8: 手动 + cron 同时运行订阅更新 | 交叉写入 config | 竞态条件 | N → Y | flock 排他锁 | 修复前：互相覆盖。修复后：后者立即报错退出 |

## 执行计划

### Phase 1: Critical Bug Fixes in test_ai_connectivity.sh

#### ✅ Task 1.1: Fix B6 + B7 + B8 — set-e/awk + unquoted array in test_ai_connectivity.sh
- **目标**：修复最优节点选择逻辑（B6 早退、B7 比较）和 percentile 函数数组初始化
- **修改内容**：
  - 文件 `vpn-tools/test_ai_connectivity.sh`：
    - L157: 将 `awk -v v=$sr_tmp 'BEGIN{exit !(v<0.3)}'; [[ $? -eq 0 ]] && break` 改为 `if awk -v v="$sr_tmp" 'BEGIN{exit !(v<0.3)}'; then break; fi`
    - L181: 将 `awk -v s=$s -v b=$best_score 'BEGIN{exit !(s>b)}'; [[ $? -eq 0 ]] && { best=$n; best_score=$s; }` 改为 `if awk -v s="$s" -v b="$best_score" 'BEGIN{exit !(s>b)}'; then best=$n; best_score=$s; fi`
    - L131（`percentile` 函数）: 将 `local arr=($(printf '%s\n' "$@" | sort -n))` 改为 `local arr=(); mapfile -t arr < <(printf '%s\n' "$@" | sort -n)`
- **修改边界**：不得修改 `curl_probe`、`score_node`、`apply_group` 函数；不得修改 endpoint 列表、命令行参数解析、JSON/Markdown 输出格式
- **测试要求**：
  - 运行 `bash -n vpn-tools/test_ai_connectivity.sh` — 预期 exit 0
  - 运行 `bash script/run_static_gates.sh` — 预期 "OK: all static gates passed"
  - 验证 B6 修复：`bash -c 'set -e; if awk -v v=0.5 "BEGIN{exit !(v<0.3)}"; then echo BREAK; else echo CONTINUE; fi; echo ALIVE'` — 预期输出 CONTINUE + ALIVE（不中断）
  - 验证 B7 修复：`bash -c 'set -e; if awk -v s=3 -v b=5 "BEGIN{exit !(s>b)}"; then echo BETTER; else echo WORSE; fi; echo ALIVE'` — 预期输出 WORSE + ALIVE
- **验收标准**：
  - ✅ `bash -n` 通过
  - ✅ 代码中不再有 `awk ...; [[ $? -eq 0 ]]` 模式
  - ✅ `percentile()` 函数使用 `mapfile -t` 而非 unquoted `$(...)`
  - ✅ 静态门禁通过
- **潜在风险**：B6 行（L157）是一个很长的单行链式命令，修改时需保持上下文缩进和同行风格一致。`percentile()` 是一行压缩函数，`mapfile` 替换后需确保不引入额外换行。

### Phase 2: Mixin Merge Integrity Check

#### ✅ Task 2.1: Fix Q6 — Add post-merge structural validation in clashctl.sh
- **目标**：在 mixin 合并回退路径 2 完成后、`mv` 到目标文件前，验证合并产出具有必需的结构
- **修改内容**：
  - 文件 `script/clashctl.sh`：
    - 在 `_merge_build_runtime` 函数中，回退路径 2 的 `if [ ! -s "$out_file.tmp" ]` 检查之后、`fi; fi` 结束之前，追加结构校验：
      ```bash
      # 结构完整性校验：确认合并产出包含必需 key
      if [ -s "$out_file.tmp" ] && ! "$BIN_YQ" -e '.["proxy-groups"] | type == "!!seq"' "$out_file.tmp" >/dev/null 2>&1; then
          warn "合并产出缺少有效 proxy-groups，回退到原始订阅"
          cp "$CLASH_CONFIG_RAW" "$out_file.tmp" 2>>"$merge_err" || true
      fi
      ```
    - 插入位置：在现有 `if [ ! -s "$out_file.tmp" ]; then _error_quit ...` 之后、`fi` + `fi` 闭合之前
- **修改边界**：不得修改合并策略 1/2 的 yq 表达式逻辑；不得修改 `_merge_sanitize_restart`、`_annotate_runtime` 或其他函数；不移除现有 `|| true`（回退路径 2 的设计意图是尽力而为）
- **测试要求**：
  - 运行 `bash -n script/clashctl.sh` — 预期 exit 0
  - 运行 `bash script/run_static_gates.sh` — 预期 "OK: all static gates passed"
- **验收标准**：
  - ✅ `bash -n` 通过
  - ✅ 在 `_merge_build_runtime` 回退路径 2 之后存在 `proxy-groups` 类型校验
  - ✅ 校验失败时回退到 `$CLASH_CONFIG_RAW` 副本（而非空文件或半成品）
  - ✅ 静态门禁通过
- **潜在风险**：`$BIN_YQ` 可能不存在（zip 未安装） — 但此时合并本身已经跳过（合并入口需要 yq），所以此代码路径不可达。回退到 raw config 可能丢失 mixin 定制 — 但比使用结构损坏的 config 更安全。

### Phase 3: Subscription Update Hardening

#### ✅ Task 3.1: Fix Q7 + Q8 — YAML fallback validation + flock in update_clash_subscription.sh
- **目标**：无 yq 时添加基本结构验证；用 flock 防止并发运行冲突
- **修改内容**：
  - 文件 `script/update_clash_subscription.sh`：
    - Q7 — L91 之后（`fi` 结束 yq 检查之后），添加 `else` 分支做最小结构检查：
      ```bash
      else
        # Minimal structure check without yq
        if ! grep -qE '^(proxies|proxy-groups|rules):' "$TMP_DECODE"; then
          echo "Downloaded file does not look like a valid Clash config (missing proxies/proxy-groups/rules)" >&2
          exit 3
        fi
      ```
    - Q8 — 在 `APPLY` 检查通过后（L106 `if [ "$APPLY" -ne 1 ]` 的 else 分支开始处），添加 flock：
      ```bash
      LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.clash_sub_update.lock"
      exec 8>"$LOCK_FILE" || { echo "Cannot create lock file" >&2; exit 1; }
      flock -n 8 || { echo "Another subscription update is running (lock held)" >&2; exit 1; }
      ```
- **修改边界**：不得修改 URL 获取逻辑、base64 解码逻辑、backup 命名格式、`--restart` 行为
- **测试要求**：
  - 运行 `bash -n script/update_clash_subscription.sh` — 预期 exit 0
  - 运行 `bash script/run_static_gates.sh` — 预期 "OK: all static gates passed"
- **验收标准**：
  - ✅ `bash -n` 通过
  - ✅ 无 yq 时有 `grep -qE` 基本结构检查
  - ✅ apply 路径开头有 flock 排他锁
  - ✅ 静态门禁通过
- **潜在风险**：Q7 的 `grep` 检查要求 YAML 中 `proxies:`/`proxy-groups:`/`rules:` 至少出现一个在行首 — 某些极简订阅可能只有 `proxies:` 而无 `rules:` —— 用 OR（任一匹配即通过）而非 AND 来避免误拒。Q8 的 lock FD 8 需确认不与脚本中其他 FD 冲突（当前脚本无其他 FD 重定向）。

### Phase 4: Uninstall Cleanup + systemd Fix

#### Task 4.1: Fix Q11 — Add subscription refresh unit cleanup to uninstall.sh
- **目标**：卸载时同时清理 subscription refresh 的 systemd units
- **修改内容**：
  - 文件 `uninstall.sh`：
    - 在现有 `rm -f "${USER_HOME}/.config/systemd/user/clash-proxy-env.service"` 之后，添加：
      ```bash
      systemctl --user stop clash-subscription-refresh.timer >&/dev/null
      systemctl --user disable clash-subscription-refresh.timer >&/dev/null
      systemctl --user stop clash-subscription-refresh.service >&/dev/null
      rm -f "${USER_HOME}/.config/systemd/user/clash-subscription-refresh.service"
      rm -f "${USER_HOME}/.config/systemd/user/clash-subscription-refresh.timer"
      ```
- **修改边界**：不得修改 `CLASH_BASE_DIR` 安全检查逻辑、`_set_rc` 调用、crontab 清理逻辑
- **测试要求**：
  - 运行 `bash -n uninstall.sh` — 预期 exit 0
- **验收标准**：
  - ✅ `bash -n` 通过
  - ✅ `uninstall.sh` 包含 `clash-subscription-refresh.timer` 的 stop + disable + rm
  - ✅ `uninstall.sh` 包含 `clash-subscription-refresh.service` 的 stop + rm
- **潜在风险**：若这些 units 不存在，`systemctl stop/disable` 和 `rm -f` 会静默成功——这是预期行为。timer 必须在 service 之前 stop 以避免 timer 在 service 删除后触发启动失败。

#### Task 4.2: Fix S1 — Add network-online dependency to subscription refresh service
- **目标**：确保订阅刷新在网络就绪后才执行
- **修改内容**：
  - 文件 `systemd/clash-subscription-refresh.service`：
    - L3: 将 `After=default.target` 改为 `After=default.target network-online.target`
    - L3 之后添加: `Wants=network-online.target`
- **修改边界**：不得修改 `ExecStart`、`Restart` 策略、`TimeoutStartSec`、`StartLimit` 配置
- **测试要求**：
  - 运行 `grep -c 'network-online.target' systemd/clash-subscription-refresh.service` — 预期输出 2
- **验收标准**：
  - ✅ `After=` 行包含 `network-online.target`
  - ✅ 存在 `Wants=network-online.target` 行
- **潜在风险**：若用户未启用 `systemd-networkd-wait-online.service` 或 `NetworkManager-wait-online.service`，`network-online.target` 可能永远不会 reach — 但 `Wants=` 是弱依赖，不会阻塞。现有 `After=default.target` 保留作为兜底。

### Phase 5: Regression Verification

#### Task 5.1: Full static gate + syntax check
- **目标**：确认所有修改未引入新问题
- **修改内容**：无代码修改
- **测试要求**：
  - 运行 `bash -n` 对全部已修改文件：
    ```
    bash -n vpn-tools/test_ai_connectivity.sh
    bash -n script/clashctl.sh
    bash -n script/update_clash_subscription.sh
    bash -n uninstall.sh
    ```
    预期：全部 exit 0
  - 运行 `bash script/run_static_gates.sh` — 预期 "OK: all static gates passed"
  - 运行 `git diff --stat` — 确认只有 5 个文件被修改（test_ai_connectivity.sh, clashctl.sh, update_clash_subscription.sh, uninstall.sh, clash-subscription-refresh.service）
- **验收标准**：
  - ✅ 4 个 shell 文件 `bash -n` 全部通过
  - ✅ 静态门禁全部通过
  - ✅ `git diff --stat` 显示恰好 5 个目标文件变更
- **潜在风险**：`clashctl.sh` 修改（Q6）可能触发 curl block audit 的新告警 — 如出现需确认是否为误报

## 回归检查清单
- [ ] 全部已修改文件 `bash -n` 语法检查通过
- [ ] `bash script/run_static_gates.sh` 通过（含 curl block audit、errexit arithmetic audit、JSON stdout purity audit）
- [ ] `git diff --stat` 确认仅修改目标 5 文件
- [ ] 抽检 B6：`test_ai_connectivity.sh` 中不再有 `awk ...; [[ $? -eq 0 ]]` 模式
- [ ] 抽检 Q6：`clashctl.sh` 的 `_merge_build_runtime` 回退路径 2 之后有 `proxy-groups` 校验
- [ ] 抽检 Q11：`uninstall.sh` 包含 `clash-subscription-refresh` 清理

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 2 | 2 | 0 |
| R2 | 可执行性 | 3 | 3 | 0 |
| R3 | 风险与边缘 | 2 | 2 | 0 |
| **终止** | **T4 — 零缺陷快速通过** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整 — 问题描述、根因、目标、4 项非目标含理由、复用分析 |
| 技术方案 | 完整 — 方案概述、7 项设计决策、5 文件影响范围 |
| Error & Rescue Map | 已覆盖 5 条路径、0 CRITICAL GAP |
| 执行计划 | 5 Phase、6 Task |
| 回归检查清单 | 6 项（含 3 项目特定抽检） |
| 已知局限 | 无 |

### R1 Issues
- **Issue R1-1**: 缺少 Error & Rescue Map → 已添加 5 条路径映射 ✅ 已修正
- **Issue R1-2**: Task 2.1（Q6）修改内容描述缺少精确的插入位置定义 → 已补充现有 `if [ ! -s ...]` 之后的定位 ✅ 已修正

### R2 Issues
- **Issue R2-1**: Task 1.1 验证命令仅有 `bash -n`，缺少 B6/B7 修复的行为验证 → 已添加 `bash -c 'set -e; if awk ...'` 行为测试 ✅ 已修正
- **Issue R2-2**: Task 4.1 未说明 timer vs service 的 stop 顺序问题 → 已在潜在风险中说明 timer 必须先 stop ✅ 已修正
- **Issue R2-3**: Task 3.1 Q7 的 grep 检查用 AND 还是 OR 未明确 → 已在潜在风险中说明用 OR（任一匹配即通过）✅ 已修正

### R3 Issues
- **Issue R3-1**: Task 2.1（Q6）校验失败时回退到 raw config 会丢失 mixin 定制 → 已在潜在风险中说明"结构损坏 < 丢失定制" 的取舍 ✅ 已修正
- **Issue R3-2**: Task 4.2 的 `Wants=network-online.target` 在无 NetworkManager/systemd-networkd 时可能不 reach → 已在潜在风险中说明 `Wants` 是弱依赖 + `After=default.target` 兜底 ✅ 已修正
