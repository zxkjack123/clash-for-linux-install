---
plan_schema_version: "1.1"
scope_mode: HOLD
waves:
  - wave: 1
    tasks: [T1.1]
  - wave: 2
    tasks: [T1.2]
    depends_on: [wave:1]
phases:
  - id: "Phase 1"
    title: "翻转 MATCH 默认策略 + 验证"
    tasks:
      - id: "T1.1"
        phase: 1
        title: "修改 clashctl.sh：MATCH 默认 DIRECT + 被封锁域名固定 PROXY"
        goal: "将 MATCH 默认策略从 PROXY 翻转为 DIRECT，同时保持 Wikipedia/Wikimedia/Wikidata 和 Microsoft/VS Code 域名固定路由到 PROXY。"
        dependencies: []
        modifications:
          - "script/clashctl.sh"
        modify_specs:
          - {action: "replace_line", file: "script/clashctl.sh", target: "L609", description: "将 CLASH_MATCH_GROUP 默认值从 PROXY 改为 DIRECT"}
          - {action: "replace_line", file: "script/clashctl.sh", target: "L610", description: "DIRECT 是 mihomo 内置指令（非 proxy-group），需绕过 L610 proxy-group 存在性检查；否则整个 MATCH 重写块被静默跳过，计划成 NO-OP"}
          - {action: "replace_line", file: "script/clashctl.sh", target: "L625-L631", description: "将 7 处 strenv(CLASH_MATCH_GROUP) 替换为字面量 PROXY，仅对 Wikipedia/Microsoft 域名固定走代理；MATCH 行 (L633) 保持 strenv(CLASH_MATCH_GROUP) 不变"}
        boundaries:
          - "不得修改 script/sanitize_runtime.sh"
          - "不得修改 resources/mixin.yaml"
          - "不得修改 resources/config.yaml"
          - "不得修改 script/ 下的其他文件"
        test_commands:
          - "bash -n script/clashctl.sh"
          - "grep -n 'MATCH_GROUP:-DIRECT' script/clashctl.sh"
          - "grep -c 'strenv(CLASH_MATCH_GROUP)' script/clashctl.sh"
          - "grep -c 'match_group.*=.*\"DIRECT\"' script/clashctl.sh"
        test_expected:
          - "bash -n: exit 0"
          - "grep L609: 显示 local match_group=\"${CLASH_MATCH_GROUP:-DIRECT}\""
          - "grep -c: 结果为 1（仅 MATCH 行保留 strenv，其余 7 处已替换为 PROXY）"
          - "grep L610: 结果为 >=1（DIRECT 内置指令 bypass 条件存在）"
        suggested_executor: "Task Executor"
        input_contracts: []
        output_contracts:
          - {type: "file", identifier: "script/clashctl.sh", contract_signature: "exports _merge_sanitize_restart() with MATCH→DIRECT default"}
          - {type: "state_change", identifier: "clashctl.sh:L609:CLASH_MATCH_GROUP default", verification_hint: {type: "grep", pattern: "CLASH_MATCH_GROUP:-DIRECT", file: "script/clashctl.sh", expected_count: "1"}}
          - {type: "state_change", identifier: "clashctl.sh:strenv replaced with PROXY literals", verification_hint: {type: "grep", pattern: "strenv\\(CLASH_MATCH_GROUP\\)", file: "script/clashctl.sh", expected_count: "1"}}
          - {type: "state_change", identifier: "clashctl.sh:L610:DIRECT bypass", verification_hint: {type: "grep", pattern: "match_group.*=.*\"DIRECT\"", file: "script/clashctl.sh", expected_count: "1"}}
        acceptance_criteria:
          - {claim: "CLASH_MATCH_GROUP 默认值改为 DIRECT", verify: "grep 'CLASH_MATCH_GROUP:-DIRECT' script/clashctl.sh", expected: ">=1"}
          - {claim: "L610 if 条件绕过 DIRECT 的 proxy-group 存在性检查", verify: "grep -c 'match_group.*=.*\"DIRECT\"' script/clashctl.sh", expected: ">=1"}
          - {claim: "仅 MATCH 行保留 strenv(CLASH_MATCH_GROUP)，其余 7 处已替换为字面量 PROXY", verify: "grep -c 'strenv(CLASH_MATCH_GROUP)' script/clashctl.sh", expected: "1"}
          - {claim: "bash 语法无错误", verify: "bash -n script/clashctl.sh", expected: "exit 0"}

      - id: "T1.2"
        phase: 1
        title: "重建 runtime 并验证路由策略"
        goal: "触发 merge+restart 管道将修改后的 clashctl.sh 逻辑应用到 runtime.yaml，然后验证 MATCH,DIRECT 生效且被封锁域名仍走 PROXY。"
        dependencies: ["T1.1"]
        modifications:
          - "无代码修改（仅验证 + 触发重建）"
        boundaries:
          - "不得直接编辑 runtime.yaml"
          - "已修改的 clashctl.sh 不再改动"
        test_commands:
          - "clashctl update"
          - "grep 'MATCH,' ~/.local/share/clash/runtime.yaml"
          - "grep 'wikipedia\\.org,' ~/.local/share/clash/runtime.yaml"
          - "grep 'microsoft\\.com,' ~/.local/share/clash/runtime.yaml"
          - "curl -o /dev/null -s -w '%{http_code}' --connect-timeout 5 https://indico.kit.edu/"
        test_expected:
          - "clashctl update: exit 0，输出含 '✓' / 'OK'"
          - "grep MATCH: 显示 MATCH,DIRECT"
          - "grep wikipedia.org: 显示 DOMAIN-SUFFIX,wikipedia.org,PROXY"
          - "grep microsoft.com: 显示 DOMAIN-SUFFIX,microsoft.com,PROXY"
          - "curl indico.kit.edu: HTTP 200 或 302"
        suggested_executor: "Task Executor"
        input_contracts:
          - {type: "file", identifier: "script/clashctl.sh", contract_signature: "exports _merge_sanitize_restart() with MATCH→DIRECT default"}
          - {type: "state_change", identifier: "clashctl.sh:L609:CLASH_MATCH_GROUP default", verification_hint: {type: "grep", pattern: "CLASH_MATCH_GROUP:-DIRECT", file: "script/clashctl.sh", expected_count: "1"}}
        output_contracts:
          - {type: "file", identifier: "~/.local/share/clash/runtime.yaml", contract_signature: "mihomo runtime config with MATCH,DIRECT"}
          - {type: "state_change", identifier: "runtime.yaml:MATCH rule", verification_hint: {type: "grep", pattern: "^  - MATCH,DIRECT$", file: "/home/gw/.local/share/clash/runtime.yaml", expected_count: "1"}}
        acceptance_criteria:
          - {claim: "runtime.yaml 的 MATCH 规则为 DIRECT", verify: "grep -c 'MATCH,DIRECT' ~/.local/share/clash/runtime.yaml", expected: ">=1"}
          - {claim: "Wikipedia 域名路由到 PROXY", verify: "grep -c 'wikipedia.org,PROXY' ~/.local/share/clash/runtime.yaml", expected: ">=1"}
          - {claim: "Microsoft 域名路由到 PROXY", verify: "grep -c 'microsoft.com,PROXY' ~/.local/share/clash/runtime.yaml", expected: ">=1"}
          - {claim: "之前被 US-Tailscale TLS 阻断的 indico.kit.edu 可通过 DIRECT 访问", verify: "curl -o /dev/null -s -w '%{http_code}' --connect-timeout 5 https://indico.kit.edu/ | grep -E '^(200|302|301)$'", expected: "exit 0"}
---

# 翻转 mihomo 默认路由策略：MATCH → DIRECT

## 背景与目标

- **问题描述**：US-Tailscale 代理节点对大量境外站点（德国 indico.kit.edu、阿里云 CDN 托管的 conferencesvc.com、casmart.com.cn 等）TLS 握手失败（`SSL_ERROR_SYSCALL`, 5s 超时），但这些站点直连完全正常。当前策略 `MATCH,PROXY` 使所有未显式匹配的流量走代理 → 任何不在 DIRECT 规则列表中的新站点都有概率被代理阻断，需要手动添加到 GNOME ignore-hosts，不可持续。

- **根因分析**：
  1. `clashctl.sh` `_merge_sanitize_restart()` 第 609 行：`CLASH_MATCH_GROUP` 默认为 `PROXY`
  2. 该函数的 yq 表达式（第 610-640 行）移除所有现有 MATCH 规则后，以 `CLASH_MATCH_GROUP` 重写 MATCH
  3. `config.yaml` 模板中虽有 `MATCH,DIRECT`，但被订阅更新管道的 clashctl.sh 覆盖
  4. 同一 yq 表达式还将 Wikipedia/Microsoft 域名规则也用 `CLASH_MATCH_GROUP` 重写（覆盖了 mixin 中已有的 `wikipedia.org,PROXY`）

- **目标**：翻转默认策略为 `MATCH → DIRECT`，仅对已知被墙域名（Wikipedia、Microsoft/VS Code）保持 PROXY 路由。

- **非目标（不做什么）**：
  - 不修改 mixin.yaml — mixin 已有正确的 PROXY/DIRECT 规则，保持不动
  - 不清理 GNOME ignore-hosts — 用户自行判断哪些可移除
  - 不修改 sanitize_runtime.sh — 它在 MATCH 逻辑之前运行，不涉入
  - 不修改订阅原始配置

- **已有代码/流程复用分析**：
  - `clashctl.sh` L609 `CLASH_MATCH_GROUP` 变量机制：**复用**，改默认值即可
  - `clashctl.sh` yq 表达式 L610-640：**复用**，仅替换 7 处 `strenv(CLASH_MATCH_GROUP)` 为字面量 `PROXY`
  - `sanitize_runtime.sh`：不涉入
  - `mixin.yaml` PROXY 规则：不涉入

## 技术方案

- **方案概述**：编辑 `clashctl.sh` 两处：
  1. L609：`PROXY` → `DIRECT`（变更默认值）
  2. L625-631：7 处 `strenv(CLASH_MATCH_GROUP)` → 字面量 `"PROXY"`（Wikipedia/Microsoft 域名不受 MATCH 默认值影响）
  
  然后触发 `clashctl update` 重建 runtime.yaml，验证。

- **关键设计决策**：
  - **Wikipedia/Microsoft 固定 PROXY**：当前 clashctl.sh 的 yq 表达式会将 mixin 中已有的 `wikipedia.org,PROXY` 移除并用 `CLASH_MATCH_GROUP` 重写。若仅改 L609 默认值为 DIRECT，Wikipedia 也会变成 DIRECT（国内被墙，会断）。因此必须将 Wikipedia/Microsoft 域名与 MATCH 策略解耦。
  - **MATCH 行保留 strenv(CLASH_MATCH_GROUP)**：允许用户通过环境变量临时切回 PROXY（`CLASH_MATCH_GROUP=PROXY bash clashctl.sh update`），保持灵活性。

- **影响范围**：仅 `script/clashctl.sh`（2 处修改，7 行内），影响范围极窄。

- **DECISION**: 编辑 clashctl.sh 变更 MATCH 默认值 + 解耦 Wikipedia/Microsoft 规则
- **ALTERNATIVES CONSIDERED**:
  1. 设 `CLASH_MATCH_GROUP=DIRECT` 环境变量 → Wikipedia 也会走 DIRECT（国内被墙），不可行
  2. 编辑 config.yaml → 被订阅更新覆盖，不可行
- **RATIONALE**: clashctl.sh 是配置管道的唯一权威合并点，改这里一处生效，且已有 CLASH_MATCH_GROUP 机制只需改默认值
- **RISK**: 若 Wikipedia 在国内确实被墙且 DIRECT 不通，则 PROXY 规则不生效（但 mixin 已有 PROXY 规则，clashctl.sh 会移除后重建）。缓解：已在修改中硬编码 PROXY。

## Error & Rescue Map

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| L610 proxy-group 存在性检查 | DIRECT 不在 proxy-groups 列表中 → `contains()` 返回 false → if 块跳过 → MATCH 不变 | 逻辑错误 | Y | L610 增加 DIRECT/REJECT/REJECT-DROP 短路绕过 | clashctl update 输出成功但 runtime 未变（静默 NO-OP） |
| yq 表达式 `strenv(CLASH_MATCH_GROUP)` 替换 | 替换不完整（某处遗漏） | 逻辑错误 | Y | T1.1 验收标准要求学生 grep -c 结果为 1 | — |
| `clashctl update` 执行 | 订阅下载失败 | 网络 | N（已有） | 原有错误处理保持不变，用户看到原有错误信息 | "订阅下载失败" |
| `clashctl update` 执行 | yq 合并失败 | 配置 | N（已有） | `_valid_config` 验证失败则回滚，不覆盖 runtime | "合并后验证失败" |
| mihomo 重启后 MATCH→DIRECT | 某些之前靠代理才能通的站点现在不通 | 可达性 | N | 用户自行判断是否加 PROXY 规则到 mixin；这是预期行为，不是 bug | 浏览器显示"无法连接" |

## 执行计划

### Phase 1: 修改 + 验证

#### Task 1.1: 修改 clashctl.sh 默认策略
- **目标**：`CLASH_MATCH_GROUP` 默认值 PROXY → DIRECT；Wikipedia/Microsoft 域名固定 PROXY；L610 绕过 DIRECT 的 proxy-group 存在性检查
- **依赖**：无
- **修改内容**：
  - `script/clashctl.sh` L609：`"${CLASH_MATCH_GROUP:-PROXY}"` → `"${CLASH_MATCH_GROUP:-DIRECT}"`
  - `script/clashctl.sh` L610：if 条件增加 DIRECT/REJECT/REJECT-DROP 短路绕过，避免 proxy-group `contains()` 检查将 DIRECT 判定为不存在而跳过整个 MATCH 重写块
  - `script/clashctl.sh` L625-631：7 处 `strenv(CLASH_MATCH_GROUP)` → 字面量 `"PROXY"`（L633 的 MATCH 行不动）
- **修改边界**：不得修改 script/ 下的其他文件，不得修改 resources/
- **测试要求**：
  - `bash -n script/clashctl.sh` — 语法检查
  - `grep -n 'CLASH_MATCH_GROUP:-DIRECT' script/clashctl.sh` — 确认默认值已改
  - `grep -c 'strenv(CLASH_MATCH_GROUP)' script/clashctl.sh` — 确认只余 1 处（MATCH 行）
- **验收标准**：
  - ✅ bash -n 通过
  - ✅ `MATCH_GROUP:-DIRECT` 恰好 1 处
  - ✅ `strenv(CLASH_MATCH_GROUP)` 恰好 1 处（仅 MATCH 行保留）
- **潜在风险**：无

#### Task 1.2: 重建 runtime 并验证路由
- **目标**：触发 merge+restart，验证 runtime.yaml 的 MATCH→DIRECT，且 Wikipedia/Microsoft → PROXY
- **依赖**：T1.1
- **修改内容**：无（仅验证+触发）
- **修改边界**：不直接编辑 runtime.yaml
- **测试要求**：
  - 运行 `clashctl update` 触发全管道
  - `grep 'MATCH,' ~/.local/share/clash/runtime.yaml`
  - `grep 'wikipedia\.org,' ~/.local/share/clash/runtime.yaml`
  - `grep 'microsoft\.com,' ~/.local/share/clash/runtime.yaml`
- **验收标准**：
  - ✅ runtime.yaml 含 `MATCH,DIRECT`
  - ✅ runtime.yaml 含 `DOMAIN-SUFFIX,wikipedia.org,PROXY`
  - ✅ runtime.yaml 含 `DOMAIN-SUFFIX,microsoft.com,PROXY`
  - ✅ 之前被 US-Tailscale 阻断的 indico.kit.edu 可通过浏览器直连访问
- **潜在风险**：订阅下载可能因网络问题失败（原本就有的风险，非本次引入）

## Execution Wave

| Wave | 可并行 Task | 依赖已完成 |
|------|------------|------------|
| W1 | T1.1 | — |
| W2 | T1.2 | W1 |

## 回归检查清单
- [ ] `bash -n script/clashctl.sh` 通过
- [ ] runtime.yaml 中 MATCH 规则为 DIRECT
- [ ] Wikipedia/Wikimedia/Wikidata 域名的 PROXY 规则保留在 runtime.yaml 中
- [ ] Microsoft/VS Code 域名的 PROXY 规则保留在 runtime.yaml 中
- [ ] 之前被阻断的境外站点（indico.kit.edu 等）可通过 DIRECT 访问
- [ ] mihomo 正常运行，controller 可访问
- [ ] 运行 `script/clash_diagnose.sh --fast --json` 无异常

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 0 | 0 | 0 |
| R1.5 | 外部引用事实核查 | 0 | 0 | 0 |
| R2 | 可执行性（含脚本干跑） | 0 | 0 | 0 |
| R2.8 | LLM 可执行性审查 | 0 | 0 | 0 |
| R3 | 风险与边缘（含跨轮一致性） | 1 | 1 | 0 |
| **R3.5** | **实战模拟审查（DIRECT proxy-group 存在性）** | **1** | **1** | **0** |
| **终止** | **T4 — 零缺陷快速通过** | | | **0** |

### R1 结构完整性
- 背景与目标、技术方案、Error & Rescue Map：均存在且非空
- Task 必需字段：goal/dependencies/modifications/boundaries/test_commands/test_expected/acceptance_criteria 全部非空
- 回归检查清单：7 项项目特定检查
- 编号连续性：T1.1 → T1.2 无跳号
- Error & Rescue Map：覆盖 4 条路径，0 CRITICAL GAP
- 已有代码复用分析：clashctl.sh 变量机制复用，yq 表达式复用，L610 if 条件扩展（短路绕过内置指令）
- Constitution Alignment：无项目原则文件，跳过

### R1.5 外部引用事实核查
- `script/clashctl.sh`：已验证存在 [verified: L609 read 确认]
- `CLASH_MATCH_GROUP` 变量：已验证存在于 clashctl.sh L609 [verified: grep 确认]
- `strenv(CLASH_MATCH_GROUP)`：已验证存在于 clashctl.sh L625-633 [verified: grep 确认 8 处]
- `~/.local/share/clash/runtime.yaml`：已验证路径存在 [verified: earlier read confirmed]
- `bash -n`：已验证是有效的 bash 语法检查选项 [verified: bash --help]
- R1.5 全部通过，0 未验证项

### R2 可执行性
- 任务粒度：T1.1 修改 1 文件，T1.2 无代码修改，均 ≤3 文件
- 依赖关系：T1.2 → T1.1，无循环
- 修改边界：明确列出不得修改的文件
- 测试要求：有具体命令 + 预期输出
- 验收标准：每条二元可验证
- 脚本干跑：`bash -n` 已在测试要求中

### R2.8 LLM 可执行性审查
- 文件路径歧义：`script/clashctl.sh` 从 repo root 唯一定位 ✓
- 修改动作歧义：三个 modify_specs 均含精确 action + target L# + description ✓
- 验收 grep 歧义：`grep -c 'strenv(CLASH_MATCH_GROUP)'` 期望 1 — 精确，无歧义 ✓
- 边界漏项：修改边界覆盖 sanitize_runtime.sh / mixin.yaml / config.yaml ✓
- contract 可执行性：T1.1 output → T1.2 input 可定位 ✓
- 数值精度：expected 均为 `1` / `exit 0` / `>=1`，二元明确 ✓

### R3 风险与边缘
- 潜在风险：T1.1 含 L610 条件修改（bash 多行 if），T1.2 已标注订阅下载可能网络失败
- 跨 Task 交互：T1.1 产出修改后的 clashctl.sh → T1.2 使用它触发重建，一致
- 回滚安全性：若 T1.2 失败，T1.1 的修改可通过 git checkout 回滚
- 遗漏场景：R3.5 实战模拟发现 L610 DIRECT 短路绕过遗漏 — 已补充
- 跨轮一致性：无前后矛盾
- What-If Preview：clashctl.sh 的 `_merge_sanitize_restart` 函数 — 检查引用方：仅 clashctl.sh 内部调用（`clashupdate`、`_merge_config_restart`、TUN 切换等），无跨文件引用 [影响预览: 无跨文件引用]

### R3.5 实战模拟审查（2026-06-12）
- **方法**：逐行模拟 `_merge_sanitize_restart()` 执行路径，设定 `match_group=DIRECT`，追踪完整数据流
- **关键发现**：L610 yq 检查 `contains([strenv(CLASH_MATCH_GROUP)])` 在 proxy-groups 列表中查找 `DIRECT`。当前运行时 proxy-groups = `[AUTO, PROXY, Proxy, DEV, COPILOT, VSCODE, DOCKER, ACADEMIC]`，不含 `DIRECT` → `contains()` 返回 false → 整个 MATCH 重写 if 块跳过 → runtime 不变 → 计划完全 NO-OP
- **验证证据**：
  - `yq '.["proxy-groups"] | map(.name)' ~/.local/share/clash/runtime.yaml` 输出不含 `DIRECT`
  - `yq -e 'contains(["DIRECT"])'` 返回 `false`
- **修复**：L610 if 条件增加 `[ "$match_group" = "DIRECT" ] || [ "$match_group" = "REJECT" ] ||` 短路绕过
- **确认修复完整性**：L610 bypass + L609 default=DIRECT + L625-631 7 处 strenv→PROXY 三者组合 → MATCH→DIRECT 且 Wikipedia/Microsoft→PROXY 同时生效

### R4 跳过（T4 触发）

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整 |
| 技术方案 | 完整 |
| Error & Rescue Map | 4 条路径，0 CRITICAL GAP |
| 执行计划 | 1 Phase，2 Tasks |
| 回归检查清单 | 7 项 |
| 已知局限 | 无 |

[Schema: WARN — validate_plan unavailable (agent_workflows not in this workspace)]

## Pre-Delivery Audit (Level: L1-Lite)

| § | Check | Status | Note |
|---|-------|--------|------|
| 1 | Unit consistency | ✅ N/A | 纯配置修改，无物理量 |
Auditor: Plan Architect | Date: 2026-06-10
