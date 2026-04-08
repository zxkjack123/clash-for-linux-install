# Fix Review Findings (2026-04-09)

## 背景与目标
- **问题/需求描述**：代码审查（`.github/reviews/codebase-2026-04-09.md`）发现 2 🔴 + 5 🟡 可操作问题，集中在 shell 脚本的 `set -e` 兼容性、数组引用、和安全卫生。
- **根因分析**：多为早期脚本未充分考虑 `set -euo pipefail` 下的命令退出码传播，以及数组展开的 word-splitting 行为。
- **目标**：修复 B1（🔴）、B2、B3、B4、B5（🟡/🟢）五个 bug + Q3（🟡 unsafe xargs）+ O2（🟢 unquoted variable），共 7 项代码修复。全部通过 `bash -n` 语法检查 + `run_static_gates.sh` 静态门禁。
- **非目标（不做什么）**：
  - Q1 credential history purge — 需要用户决策（rotate passwords / git filter-repo），不在本计划范围
  - Q2 eval 文档增强 — 运行时已有 flag 保护，低优先级
  - Q4 HTTP Bearer guard — 仅 localhost 使用，低风险
  - Q5 legacy /tmp migration — 涉及面广，单独计划
  - O1 CI pipeline — 独立功能增强，单独计划
- **已有代码/流程复用分析**：
  - `run_static_gates.sh`（3 个 Python 审计脚本）：复用，作为回归验证
  - `bash -n` 语法检查：复用，每个 task 的最小验证

## 技术方案
- **方案概述**：逐文件精确修补，每次修改 ≤1 个文件，修改后立即验证。所有修改为行级局部替换，不改变逻辑流/输出格式。
- **关键设计决策**：
  - B1：用 `if response=$(...); then` 模式替代 `response=$(...); if [ $? -eq 0 ]`，这是 `set -e` 下的标准惯用法。
  - B2/B3：给数组切片加双引号 `("${arr[@]:0:$N}")`。
  - B4：给 `grep` 管道追加 `|| true`。
  - B5：在算术前加数值校验 `[[ "$var" =~ ^[0-9]+$ ]] || var=0`。
  - Q3：给 `xargs` 加 `-d '\n'` 避免空格切割文件名。
  - O2：给 `echo $response` 加双引号。
- **影响范围**：
  - `vpn-tools/test_openxlab_direct_rules.sh`（B1 + O2）
  - `vpn-tools/test_ai_connectivity.sh`（B2）
  - `vpn-tools/optimize_ai.sh`（B3）
  - `vpn-tools/network_dashboard.sh`（B4 + B5）
  - `script/clashctl.sh`（Q3）

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| B1: `timeout curl` 目标域名不可达 | curl 超时 exit 非0 | 命令退出码 | N → Y | 改用 `if response=$(...); then` 包裹 | 修复前：脚本中断。修复后：显示"Connection timeout" 继续下一域名 |
| B4: `grep "健康分数"` 无匹配 | grep exit 1 | 管道失败 | N → Y | 追加 `\|\| true` | 修复前：dashboard 崩溃。修复后：显示"暂无历史数据" |
| B5: `jq` 返回 `null` 进入算术 | bash arithmetic error | shell 错误 | N → Y | 数值校验兜底 | 修复前：dashboard 崩溃。修复后：bar 显示为 0 分 |
| Q3: diff 索引文件名含空格 | xargs 错误切割 | word-splitting | N → Y | `-d '\n'` | 修复前：删错文件。修复后：按行正确处理 |

## 执行计划

### Phase 1: Critical Bug Fix

#### ✅ Task 1.1: Fix B1 + O2 — `set -e` unreachable branch in test_openxlab_direct_rules.sh
- **目标**：让 curl 失败时走 else 分支而非脚本中断；同时修复 O2 unquoted `$response`
- **修改内容**：
  - 文件 `vpn-tools/test_openxlab_direct_rules.sh`：
    - L110-115: 将 `response=$(timeout 10 curl ...); if [ $? -eq 0 ]; then` 改为 `if response=$(timeout 10 curl ... 2>/dev/null); then`
    - L116-117: 将 `echo $response | cut` 改为 `echo "$response" | cut`
- **修改边界**：不得修改该脚本的其他函数、配置加载逻辑、或输出格式
- **测试要求**：
  - 运行 `bash -n vpn-tools/test_openxlab_direct_rules.sh` — 预期 exit 0 无输出
  - 运行 `python3 script/run_static_gates.sh` — 预期 "OK: all static gates passed"
- **验收标准**：
  - ✅ `bash -n` 通过
  - ✅ 代码中不再有 `response=$(...)` 后跟独立的 `if [ $? -eq 0 ]` 模式
  - ✅ `echo $response` 改为 `echo "$response"`（两处）
- **潜在风险**：`if response=$(...)` 结构在 subshell 中可能捕获不到 `timeout` 的退出码 — 但实测 bash 4+ 下 `if var=$(timeout ... cmd)` 正确传播 timeout 的退出码

### Phase 2: Array Quoting Fixes

#### ✅ Task 2.1: Fix B2 — Unquoted array slice in test_ai_connectivity.sh
- **目标**：防止节点名包含空格/glob 字符时破坏数组
- **修改内容**：
  - 文件 `vpn-tools/test_ai_connectivity.sh`：
    - L79: `NODES=(${NODES[@]:0:$LIMIT})` → `NODES=("${NODES[@]:0:$LIMIT}")`
- **修改边界**：不得修改该脚本的 jq/sed 解析逻辑、endpoint 列表、或测试循环
- **测试要求**：
  - 运行 `bash -n vpn-tools/test_ai_connectivity.sh` — 预期 exit 0
- **验收标准**：
  - ✅ `bash -n` 通过
  - ✅ L79 数组切片有双引号包裹
- **潜在风险**：无 — 双引号保留数组元素的原始边界，行为严格兼容

#### Task 2.2: Fix B3 — Unquoted array slice in optimize_ai.sh
- **目标**：同 Task 2.1，防止候选节点名切割错误
- **修改内容**：
  - 文件 `vpn-tools/optimize_ai.sh`：
    - L138: `filtered=(${available[@]:0:$LIMIT})` → `filtered=("${available[@]:0:$LIMIT}")`
- **修改边界**：不得修改该脚本的节点评估逻辑、切换逻辑、或输出格式
- **测试要求**：
  - 运行 `bash -n vpn-tools/optimize_ai.sh` — 预期 exit 0
- **验收标准**：
  - ✅ `bash -n` 通过
  - ✅ L138 数组切片有双引号包裹
- **潜在风险**：无

### Phase 3: Dashboard Robustness

#### Task 3.1: Fix B4 + B5 — grep under set -e + arithmetic guard in network_dashboard.sh
- **目标**：让 dashboard 在无历史数据或 jq 返回非数值时优雅降级而非崩溃
- **修改内容**：
  - 文件 `vpn-tools/network_dashboard.sh`：
    - L285: `local scores=($(grep "健康分数" "$HISTORY_LOG" | tail -n 10 | grep -oP '\d+/100' | cut -d'/' -f1))` → 追加 `|| true` 使 grep 无匹配时不触发 `set -e`
    - L189（`score` 赋值之后、L196 算术之前）: 插入 `[[ "$score" =~ ^[0-9]+$ ]] || score=0`
- **修改边界**：不得修改 dashboard 的 TUI 布局、颜色方案、交互键绑定
- **测试要求**：
  - 运行 `bash -n vpn-tools/network_dashboard.sh` — 预期 exit 0
  - 运行 `python3 script/run_static_gates.sh` — 预期 "OK: all static gates passed"
- **验收标准**：
  - ✅ `bash -n` 通过
  - ✅ L285 的 grep 管道末尾有 `|| true`
  - ✅ `$score` 在进入 `$((score * ...))` 之前有数值校验
- **潜在风险**：`|| true` 会导致 `scores` 数组在 grep 无匹配时为空 — 但紧接着 L287 `if [ ${#scores[@]} -eq 0 ]` 已处理此情况，行为正确

### Phase 4: Safe xargs

#### Task 4.1: Fix Q3 — Unsafe xargs in clashctl.sh
- **目标**：防止 diff 索引文件路径含空格时 xargs 错误切割
- **修改内容**：
  - 文件 `script/clashctl.sh`：
    - L901: `head -n "$remove_count" "$CLASH_DIFF_INDEX_FILE" | awk -F '\t' '{print $3}' | xargs -r rm -f --` → 改为 `... | xargs -d '\n' -r rm -f --`
- **修改边界**：不得修改 `clashctl.sh` 的订阅更新逻辑、diff 生成逻辑、或指纹校验逻辑
- **测试要求**：
  - 运行 `bash -n script/clashctl.sh` — 预期 exit 0
  - 运行 `python3 script/run_static_gates.sh` — 预期 "OK: all static gates passed"
- **验收标准**：
  - ✅ `bash -n` 通过
  - ✅ xargs 调用包含 `-d '\n'`
- **潜在风险**：`-d '\n'` 是 GNU xargs 扩展，非 POSIX — 但本项目目标平台为 Linux (Ubuntu/Debian)，GNU coreutils 始终可用

### Phase 5: Regression Verification

#### Task 5.1: Full static gate + syntax check
- **目标**：确认所有修改未引入新问题
- **修改内容**：无代码修改
- **测试要求**：
  - 运行 `bash -n` 对全部已修改文件：
    ```
    bash -n vpn-tools/test_openxlab_direct_rules.sh
    bash -n vpn-tools/test_ai_connectivity.sh
    bash -n vpn-tools/optimize_ai.sh
    bash -n vpn-tools/network_dashboard.sh
    bash -n script/clashctl.sh
    ```
    预期：全部 exit 0
  - 运行 `python3 script/run_static_gates.sh` — 预期 "OK: all static gates passed"
  - 运行 `git diff --stat` — 确认只有 5 个文件被修改
- **验收标准**：
  - ✅ 5 个文件 `bash -n` 全部通过
  - ✅ 静态门禁全部通过
  - ✅ `git diff --stat` 显示恰好 5 个文件变更
  - ✅ 无 untracked 新增文件（除 `.github/` 下的计划/审查文件）
- **潜在风险**：静态门禁的 Python 审计脚本可能对修改后的代码行产生新告警 — 如出现需逐条确认是误报还是真实问题

## 回归检查清单
- [ ] 全部已修改文件 `bash -n` 语法检查通过
- [ ] `python3 script/run_static_gates.sh` 通过（含 curl block audit、errexit arithmetic audit、JSON stdout purity audit）
- [ ] `git diff --stat` 确认仅修改目标 5 文件
- [ ] 抽检：`vpn-tools/test_openxlab_direct_rules.sh` 对不可达域名不再中断（可用 `timeout 1 curl https://192.0.2.1/` 模拟）
- [ ] 抽检：`vpn-tools/network_dashboard.sh` 在空 HISTORY_LOG 下不崩溃

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 3 | 3 | 0 |
| R2 | 可执行性 | 2 | 2 | 0 |
| R3 | 风险与边缘 | 1 | 1 | 0 |
| **终止** | **T4 — 零缺陷快速通过** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整 — 问题描述、目标、5 项非目标均含理由、复用分析 |
| 技术方案 | 完整 — 方案概述、6 项设计决策、5 文件影响范围 |
| Error & Rescue Map | 已覆盖 4 条路径、0 CRITICAL GAP |
| 执行计划 | 5 Phase、6 Task |
| 回归检查清单 | 5 项（含 2 项目特定抽检） |
| 已知局限 | 无 |

### R1 Issues
- **Issue R1-1**: 缺少 Error & Rescue Map section → 已添加 4 条失败路径映射 ✅ 已修正
- **Issue R1-2**: 缺少"已有代码/流程复用分析"字段 → 已添加 `run_static_gates.sh` 和 `bash -n` 复用说明 ✅ 已修正
- **Issue R1-3**: Phase 编号不连续（原 Phase 1/2/3 跳过了独立回归验证阶段）→ 已拆为 5 Phase ✅ 已修正

### R2 Issues
- **Issue R2-1**: Task 1.1 测试要求原写"运行脚本观察输出"，非具体命令 → 改为 `bash -n` + `run_static_gates.sh` 具体命令和预期输出 ✅ 已修正
- **Issue R2-2**: Task 5.1 验收标准原缺"untracked 文件"检查 → 已添加 ✅ 已修正

### R3 Issues
- **Issue R3-1**: Task 4.1 未说明 `-d '\n'` 的可移植性风险 → 已在潜在风险中说明 GNU xargs 依赖 + 项目平台保证 ✅ 已修正
