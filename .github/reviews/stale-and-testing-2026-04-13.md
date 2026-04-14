# Repository Review: clash-for-linux-install (Stale Content + Test Coverage)

## Executive Summary
- Findings: 3 🔴 / 6 🟡 / 4 🟢
- Project Profile: Bash (74 .sh files, 477 function defs), Python audit tools, YAML configs
- Review Focus: 过时内容残留 + 测试覆盖度
- Overall Health: Core scripts functional; subscription-to-self-hosted migration incomplete in `script/` layer and 14 vpn-tools scripts; zero unit test framework exists.

## Prior Review Status (codebase-2026-04-09)

| ID | Status | Note |
|----|--------|------|
| Q1 Credential history | ⚠️ Open | Passwords rotated, but git history still contains old backups |
| Q2 eval injection | ⚠️ Open | `runtime_guard.sh:545` — unchanged, accepted risk |
| Q3 Unsafe xargs | ✅ Fixed | `clashctl.sh:907` now uses `xargs -d '\n'` |
| B1 set-e unreachable | ✅ Fixed | `test_openxlab_direct_rules.sh:110` refactored to `if response=$(...)` |
| B2 Unquoted array slice | ✅ Fixed | `test_ai_connectivity.sh:79` |
| B3 Unquoted array slice | ✅ Fixed | `optimize_ai.sh:134` |
| B4 grep under set -e | ✅ Fixed | `network_dashboard.sh:287` now has `|| true` |
| B5 Arithmetic on jq | ✅ Fixed | `network_dashboard.sh:189` now validates `[[ "$score" =~ ^[0-9]+$ ]]` |

## ① Repository Overview

- `resources/config.yaml` — 当前实际组: AUTO, PROXY, Proxy, DEV, COPILOT, VSCODE, DOCKER, ACADEMIC; 节点: US-Tailscale, JP-Tailscale
- `script/*.sh` — 13 files, 核心运行逻辑 (clashctl, common, sanitize, diagnose, etc.)
- `vpn-tools/*.sh` — 61 files, 诊断/优化工具
- Static gates: `run_static_gates.sh` → 3 Python audit scripts, all PASS
- `bash -n` syntax: 全部 74 个 .sh 文件通过
- CI: 仅 `.github/workflows/auto-rebase.yml`，无自动化测试 pipeline

## ② Stale Content — 过时内容残留

### 🔴 script/ 核心层 (5 files, 功能性影响)

| ID | File | Line(s) | Stale Content | Impact |
|----|------|---------|---------------|--------|
| S1 | [clashctl.sh](../../script/clashctl.sh#L618) | 618 | `CLASH_MATCH_GROUP:-AUTO-SMART` → AUTO-SMART 不存在于当前 runtime | **MATCH 规则 + wikipedia + VS Code + microsoft.com 路由静默跳过**。整个 L618-645 代码块无效。 |
| S2 | [clashctl.sh](../../script/clashctl.sh#L601-L609) | 601-609 | `AUTO-SMART <-> 速云梯` 循环检测 | 死代码：两个旧组均不存在 |
| S3 | [auto_optimize_clash.sh](../../script/auto_optimize_clash.sh) | 全文 | 整个脚本围绕 `AUTO-SMART` + `西瓜加速` 组设计 | 完全不可用：写入 mixin 的分组名在当前配置不存在 |
| S4 | [sanitize_runtime.sh](../../script/sanitize_runtime.sh#L121-L167) | 121-167 | `AUTO-SMART` / `速云梯` fallback 候选列表 | Google Scholar 路由可能选错分组 (实际会 fallback 到 PROXY) |
| S5 | [clash_diagnose.sh](../../script/clash_diagnose.sh#L279) | 279 | `西瓜加速` in hijack rule detection | 不影响功能（grep 匹配范围足够宽），但误导阅读 |
| S6 | [runtime_guard.sh](../../script/runtime_guard.sh#L367) | 367 | `西瓜加速` in hijack detection | 同 S5 |

### 🟡 vpn-tools/ 用户工具层 (14 files, 已知延期)

上次 `fix-vpn-tools-stale-groups` 计划修复了 4 个 P0+P1 脚本。以下 14 个仍含过时引用：

| Severity | File | Key Stale Content |
|----------|------|-------------------|
| Critical | [customize_ai_group.sh](../../vpn-tools/customize_ai_group.sh#L33) | `GROUP="AI"`, `V1-美国` node names |
| Critical | [optimize_ai_enhanced.sh](../../vpn-tools/optimize_ai_enhanced.sh#L30) | `GROUP="AI"`, 6x `V1-` nodes |
| Critical | [merge_subscription.sh](../../vpn-tools/merge_subscription.sh#L11) | `GROUPS="GLOBAL,自动选择,故障转移"` |
| Critical | [use_jp_tailscale_only.sh](../../vpn-tools/use_jp_tailscale_only.sh) | `AUTO-SMART`, `故障转移`, `速云梯`, `AI`, `Streaming` — 全脚本 |
| Critical | [test_chinese_ai_platforms.sh](../../vpn-tools/test_chinese_ai_platforms.sh) | `proxies/AI`, `proxies/Streaming`, 6x `V1-` nodes |
| Critical | [test_braintrust_connectivity.sh](../../vpn-tools/test_braintrust_connectivity.sh) | `proxies/AI`, 3x `V1-` nodes |
| Medium | [jp_tailscale_single_node_test.sh](../../vpn-tools/jp_tailscale_single_node_test.sh#L35) | `GROUP_TO_SWITCH=AUTO-SMART`, `故障转移` |
| Medium | [optimize_dev_nodes.sh](../../vpn-tools/optimize_dev_nodes.sh#L50) | `速云梯`, `西瓜加速`, `GLOBAL`, `自动选择` |
| Medium | [optimize_mineru.sh](../../vpn-tools/optimize_mineru.sh#L34) | `GROUP_DEFAULT="西瓜加速"`, 同上候选列表 |
| Medium | [intelligent_rule_optimizer.sh](../../vpn-tools/intelligent_rule_optimizer.sh#L37) | `西瓜加速`, `速云梯`, `AUTO-SMART` |
| Medium | [network_dashboard.sh](../../vpn-tools/network_dashboard.sh#L138) | `西瓜加速`, `速云梯`, `GLOBAL`, `自动选择` |
| Medium | [probe_domain_across_nodes.sh](../../vpn-tools/probe_domain_across_nodes.sh#L30) | `西瓜加速`, `速云梯`, `自动选择`, `故障转移` |
| Low | [fix_openxlab_connectivity.sh](../../vpn-tools/fix_openxlab_connectivity.sh#L170) | `proxies/AI`, `V1-香港01` |
| Low | [select_youtube_node.sh](../../vpn-tools/select_youtube_node.sh#L55) | `YOUTUBE`, `Streaming`, `流媒体` |

### 🟡 Subscription-Era Dead Code

以下脚本专为订阅模式设计，在自建节点模式下功能已无意义，可考虑归档：

| File | Purpose | Status |
|------|---------|--------|
| [auto_optimize_clash.sh](../../script/auto_optimize_clash.sh) | 从 runtime 抓节点 → TCP/TLS 测速 → 写入 AUTO-SMART | 完全过时: AUTO url-test 已接管此功能 |
| [update_clash_subscription.sh](../../script/update_clash_subscription.sh) | 拉取订阅 URL → 覆盖 config.yaml | 保留价值低: 当前手动管理双节点 |
| [refresh_subscription_direct.sh](../../script/refresh_subscription_direct.sh) | 清理代理环境后调用 update_clash_subscription | 依赖 update_clash_subscription |
| [repair_subscription_and_restore.sh](../../script/repair_subscription_and_restore.sh) | 修复损坏的订阅 YAML | 保留价值低 |
| [merge_subscription.sh](../../vpn-tools/merge_subscription.sh) | 合并订阅 proxies | 保留价值低 |

## ③ Code Quality Issues (New)

| ID | Severity | Location | Category | Description | Remediation |
|----|----------|----------|----------|-------------|-------------|
| Q6 | 🔴 | [clashctl.sh](../../script/clashctl.sh#L618) | Broken default | `CLASH_MATCH_GROUP:-AUTO-SMART` → AUTO-SMART 不在 runtime → MATCH/wikipedia/VSCode/microsoft 规则注入整块静默跳过 | 改为 `CLASH_MATCH_GROUP:-PROXY` 或 `CLASH_MATCH_GROUP:-AUTO` |
| Q7 | 🟡 | [optimize_ai.sh](../../vpn-tools/optimize_ai.sh#L173) | Bash echo \n | `echo "\n🧪 ..."` 在 bash 下打印字面 `\n`，不换行 | 改为 `printf '\n🧪 Testing node: %s\n' "$node"` |
| Q8 | 🟡 | [optimize_ai.sh](../../vpn-tools/optimize_ai.sh) | Missing trap | 脚本中断时不恢复原始节点选择，手动 Ctrl-C 导致代理组停留在测试节点 | 添加 `trap 'switch_node "$original" 2>/dev/null' EXIT` |
| Q9 | 🟢 | [enable_vscode_fallback_direct.sh](../../vpn-tools/enable_vscode_fallback_direct.sh) | Missing shebang | 第一行无 `#!/usr/bin/env bash` | 添加 shebang |
| Q10 | 🟢 | [common.sh](../../script/common.sh) | Missing shebang | 已有 shellcheck disable 注释但无 shebang | 添加 `#!/usr/bin/env bash` (source-only 文件可加注释说明) |

## ④ Potential Bugs (New)

| ID | Severity | Location | Category | Description | Remediation |
|----|----------|----------|----------|-------------|-------------|
| B6 | 🔴 | [clashctl.sh](../../script/clashctl.sh#L618-L645) | Silent failure | MATCH_GROUP 默认 AUTO-SMART 不存在 → 整个代码块被 yq `-e` gate 跳过 → runtime 无 MATCH 兜底规则、无 wikipedia 路由、无 VS Code marketplace 路由 | 将默认值改为 `PROXY` 或 `AUTO` |
| B7 | 🟡 | [sanitize_runtime.sh](../../script/sanitize_runtime.sh#L121-L122) | Stale fallback | Google Scholar 路由 fallback 先查 AUTO-SMART/速云梯（不存在），最终 fallback 到 PROXY → 功能正常但经过无意义检查 | 更新 fallback 顺序为 `ACADEMIC → AUTO → PROXY` |
| B8 | 🟡 | [sanitize_runtime.sh](../../script/sanitize_runtime.sh#L167) | Stale fallback | 无 yq 时的 plain text fallback: `for cand in AUTO-SMART 速云梯 PROXY` → 前两个永远不匹配 | 同上 |
| B9 | 🟢 | [auto_optimize_clash.sh](../../script/auto_optimize_clash.sh#L121-L129) | Writes stale groups | 写入 `AUTO-SMART` + `西瓜加速` 到 mixin → 如果运行会在 mixin 中创建当前配置不认识的组 | 标记脚本为 deprecated 或删除 |

## ⑤ Test Coverage Analysis — 测试覆盖度

### 现有测试基础设施

| Component | Exists | Coverage | Quality |
|-----------|--------|----------|---------|
| Static analysis (Python audits) | ✅ | 74 files, 3 gates (curl blocks, errexit arith, JSON purity) | Good |
| `bash -n` syntax validation | ✅ (manual) | 74/74 scripts pass | Good, but not automated |
| Unit test framework (bats/shunit2) | ❌ | 0% | **无任何单元测试** |
| Integration tests | ❌ | vpn-tools/test_*.sh 为手动诊断脚本，非自动化测试 | 非测试 |
| CI pipeline | ❌ | 仅 auto-rebase.yml | 无测试自动化 |
| Test data | ✅ | `vpn-tools/testdata/sub_sample.yaml` | 仅 1 个样本文件 |

### 函数覆盖度分析

**477 个函数定义，0 个单元测试。** 以下高价值函数缺乏测试：

| Priority | Module | Functions | Risk |
|----------|--------|-----------|------|
| 🔴 Critical | `clashctl.sh` | `_merge_build_runtime()` — 核心 config 合并逻辑 | 合并错误导致服务不可用 |
| 🔴 Critical | `sanitize_runtime.sh` | Google Scholar / Copilot 路由注入逻辑 | 路由规则错误导致流量走错 |
| 🔴 Critical | `common.sh` | `_valid_config()`, `_get_proxy_port()`, `_clash_port_policy()` | 端口冲突/配置校验失败 |
| 🟡 High | `load_env.sh` | `clash_detect_secret()`, `clash_auth_header()`, `clash_api_get()` | Controller 认证失败 |
| 🟡 High | `lib/net_helpers.sh` | `nh_curl_t()`, `nh_grade_time()` | 诊断工具输出不准确 |
| 🟢 Medium | `clashctl.sh` | `_set_system_proxy()`, `_unset_system_proxy()` | GNOME proxy 设置残留 |

### 推荐的测试策略

1. **Phase 1 (Quick Win)**: CI pipeline 中添加 `bash -n` + `run_static_gates.sh`
2. **Phase 2 (Unit Tests)**: 引入 [bats-core](https://github.com/bats-core/bats-core) 框架
   - 优先为 `_merge_build_runtime()` 写集成测试（用 testdata 样本验证合并输出）
   - 为 `load_env.sh` 的 controller 探测函数写 mock 测试
   - 为 `sanitize_runtime.sh` 的路由注入写断言测试
3. **Phase 3 (Integration)**: 容器化测试环境（启动 mihomo → 验证路由 → 检查 runtime.yaml 产出）

## Remediation Roadmap

### Priority 1 — 🔴 Critical (立即修复)

1. **S1+Q6+B6 — `clashctl.sh` MATCH_GROUP 默认值**: 将 L618 `AUTO-SMART` 改为 `PROXY`（或 `AUTO`）。**这是功能性回归：MATCH 兜底规则、wikipedia/VSCode/microsoft 路由在当前配置下完全不生效。** Effort: 5 min.
2. **S2 — `clashctl.sh` 循环检测死代码**: 删除 L601-609 (AUTO-SMART↔速云梯 循环检测)。Effort: 2 min.
3. **S3+B9 — `auto_optimize_clash.sh`**: 标记 deprecated（添加 exit + 提示信息）或删除。当前运行会向 mixin 写入不存在的组名。Effort: 5 min.

### Priority 2 — 🟡 Warning (近期修复)

4. **S4+B7+B8 — `sanitize_runtime.sh` fallback 列表**: 更新候选列表为 `ACADEMIC → AUTO → PROXY`。Effort: 5 min.
5. **Q7+Q8 — `optimize_ai.sh` echo \n + missing trap**: 修复 printf + 添加 EXIT trap 恢复节点。Effort: 5 min.
6. **vpn-tools 14 files stale**: 分批修复（见上表），或对 Critical 级别的 6 个脚本优先处理。
7. **CI pipeline**: 添加 `.github/workflows/lint.yml` 运行 `bash -n` + `run_static_gates.sh`。Effort: 15 min.

### Priority 3 — 🟢 Enhancement (按需改进)

8. Subscription-era dead code 归档 (5 scripts)
9. Q9+Q10 shebang 修复
10. bats-core 单元测试框架引入
11. 高价值函数单元测试（`_merge_build_runtime`, `sanitize_runtime`, `load_env`）

## Pre-Delivery Audit (Level: L1-Lite)

| § | Check | Status | Note |
|---|-------|--------|------|
| 1 | File counts accurate | ✅ PASS | 74 .sh files, 477 functions — verified via `find` and `grep -c` |
| 1 | Stale file counts | ✅ PASS | 5 script/ + 14 vpn-tools/ files — each verified via grep |
| 1 | Prior fix status | ✅ PASS | B1-B5, Q3 verified by reading current file content at reported lines |
| 1 | B6 claim verified | ✅ PASS | Confirmed AUTO-SMART absent from `runtime.yaml` via yq query |

Auditor: Repo Reviewer | Date: 2026-04-13
