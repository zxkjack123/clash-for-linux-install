# 修复 vpn-tools 过时代理组引用

## 背景与目标

- **问题/需求描述**：vpn-tools/ 中的脚本仍引用旧订阅时代的代理组名（AI、Streaming、AI-Claude、AI-Manual、AUTO-SMART、速云梯、西瓜加速、GLOBAL、自动选择、故障转移）和旧节点名（V1-美国01 等），导致多个脚本功能失效或输出误导信息。当前实际组名为 AUTO/PROXY/DEV/COPILOT/VSCODE/DOCKER/ACADEMIC，节点为 US-Tailscale/JP-Tailscale。
- **根因分析**：配置从订阅模式切换到自建双节点后，vpn-tools 脚本未同步更新。
- **目标**：修复所有 **launcher 可达** 的用户交互脚本中的过时引用，使其输出正确且功能正常。
- **非目标（不做什么）**：
  - 不修复历史报告 markdown 文件（`batch_report_*.md`, `batch_diagnostics_*.md` 等）— 它们是历史快照，无运行时影响
  - 不重构脚本架构或添加新功能 — 最小修复原则
  - 不修改 `script/*.sh`（clashctl.sh 等核心脚本）— 不在本次范围
  - 不修改 `resources/config.yaml` 或 `resources/mixin.yaml` — 已在前序计划中完成
  - 不修改 `optimize_vscode_copilot.sh` / `trace_mihomo_connections.sh` — 已验证无过时引用
- **已有代码/流程复用分析**：
  - `clash_pick_selector_group()`（定义在 `load_env.sh` 或 `common.sh`）：复用，仅更新传入的候选组名列表
  - `clash_auth_header()`：复用，不修改
  - mihomo controller API `/proxies/<name>`：复用，仅更新查询的组名

## 技术方案

- **方案概述**：按 launcher 菜单分类，逐个修复脚本中的过时引用。对每个脚本：(1) 替换 `GROUP="AI"` 类硬编码为当前组名，(2) 替换 `clash_pick_selector_group` 的候选列表为当前组名，(3) 替换硬编码节点名为当前节点名或动态发现，(4) 修正输出文本。
- **关键设计决策**：
  1. **GROUP 默认值映射规则**：`AI` → `COPILOT`（AI 流量现在走 COPILOT 组）；`Streaming` → `PROXY`（无独立流媒体组，通用代理即可）；`GLOBAL`/`自动选择` → `AUTO`；`故障转移` → `PROXY`
  2. **`clash_pick_selector_group` 候选列表统一为** `"COPILOT" "DEV" "PROXY" "AUTO"`（按优先级：特定组 → 通用代理 → 自动选择）
  3. **AI 服务测试必须走代理**：`restart_clash_service.sh` 中测试 `api.openai.com` 等必须加 `-x http://127.0.0.1:7890`
  4. **REDUCTION 策略**：25 个受影响脚本中，仅修复 **launcher 直接可达的 14 个** + `restart_clash_service.sh` 本身。其余脚本标记为可延期。
- **影响范围**：
  - `vpn-tools/restart_clash_service.sh`（主入口）
  - Launcher AI 菜单：`optimize_ai.sh`, `optimize_ai_enhanced.sh`, `test_ai_connectivity.sh`, `test_braintrust_connectivity.sh`, `customize_ai_group.sh`
  - Launcher Streaming 菜单：`select_youtube_node.sh`, `optimize_youtube_streaming.sh`, `streaming_manager.sh`, `fix_zoom_connectivity.sh`
  - Launcher Network 菜单：`show_vpn_status.sh`
  - Launcher CN 菜单：`fix_openxlab_connectivity.sh`, `test_chinese_ai_platforms.sh`
  - 其他用户可达：`merge_subscription.sh`, `use_jp_tailscale_only.sh`, `intelligent_rule_optimizer.sh`

## Scope Mode: REDUCTION

25 个受影响脚本太多，按以下规则精简到最小可交付版本：

| 优先级 | 脚本 | 理由 |
|--------|------|------|
| **P0 必修** | `restart_clash_service.sh` | 每次 --apply 都执行，输出全部过时 |
| **P1 高频** | `optimize_ai.sh`, `test_ai_connectivity.sh`, `show_vpn_status.sh` | launcher 直达 + clash_diagnose 引用 |
| **P2 中频** | `customize_ai_group.sh`, `optimize_ai_enhanced.sh`, `merge_subscription.sh` | launcher/手动可达但使用频率较低 |
| **可延期** | streaming 系列 5 个, `use_jp_tailscale_only.sh`, `optimize_mineru.sh`, `intelligent_rule_optimizer.sh`, `test_braintrust_connectivity.sh`, `test_chinese_ai_platforms.sh`, `fix_openxlab_connectivity.sh` 等 | 功能已被其他脚本覆盖或用户极少使用 |

**本次计划仅覆盖 P0 + P1（4 个脚本）。** P2 及可延期项列入"已知局限"，后续按需追加。

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| sed 替换组名 | 匹配模式写错导致多替换或漏替换 | 编辑错误 | Y | 每个 Task 有 grep 验证步骤 | 脚本输出仍含旧组名 |
| controller API 查询新组名 | mihomo 未运行时查询失败 | 运行时 | Y | 脚本已有 `\|\| echo "Unknown"` fallback | 显示 "Unknown" |
| AI 服务测试加 -x proxy 后 | 代理不可用时全部超时 | 网络 | Y | 保留 timeout + 已有错误信息 | 显示 "⚠️ Connection timeout" |
| 修改 `show_vpn_status.sh` | 脚本结构不熟悉导致误删 | 编辑错误 | Y | 只做 sed 替换组名字符串，不改结构 | N/A |

## 执行计划

### Phase 1: 修复主入口脚本

#### ✅ Task 1.1: 修复 `restart_clash_service.sh`

- **目标**：更新所有过时代理组引用和 AI 服务测试方式
- **修改内容**：
  - 文件 `vpn-tools/restart_clash_service.sh`：
    1. **L98-120 配置验证段**：移除 OpenXLab/Braintrust 规则检查（当前 config 不含这些规则，检查无意义），替换为查询实际组状态：AUTO 存活、COPILOT 存活
    2. **L238-243 代理组显示段**：替换 `proxies/AI` → `proxies/AUTO`，`proxies/Streaming` → 删除。改为显示 AUTO（url-test 自动选择）、COPILOT、DEV 的当前节点
    3. **L282-312 AI 服务测试段**：curl 加 `-x http://127.0.0.1:7890` 走代理测试；移除 `api.openai.com`（从中国走代理也可能被 IP 封锁，不稳定），改为测 `copilot-proxy.githubusercontent.com/_ping`（Copilot 核心服务）
    4. **L316-331 最终摘要段**：移除 AI-Claude/AI-Manual 硬编码文本；替换为动态读取各组 `.now` 显示
- **修改边界**：不得修改 L1-97（脚本头部、参数解析、配色、路径解析、备份逻辑）、L123-230（服务停止/启动/验证逻辑 — 这些是正确的）
- **测试要求**：
  - 运行 `bash -n vpn-tools/restart_clash_service.sh` → 预期退出码 0
  - 运行 `grep -c 'AI-Manual\|AI-Claude\|proxies/AI"\|proxies/Streaming' vpn-tools/restart_clash_service.sh` → 预期输出 `0`
  - 运行 `./vpn-tools/restart_clash_service.sh`（不加 --apply，preview 模式）→ 预期：无 "Unknown" 输出，显示实际组名和节点
- **验收标准**：
  - ✅ 脚本中不含 `proxies/AI"`、`proxies/Streaming`、`AI-Manual`、`AI-Claude` 字符串
  - ✅ AI 服务测试段走代理（`-x` 参数存在）
  - ✅ preview 模式运行不报错、不显示 "Unknown"
  - ✅ `bash -n` 语法检查通过
- **潜在风险**：修改范围较大（~100 行），需小心保留 set -euo pipefail 下的错误处理模式

#### ✅ Task 1.2: 修复 `optimize_ai.sh`

- **目标**：更新 PREF_GROUPS 候选列表
- **修改内容**：
  - 文件 `vpn-tools/optimize_ai.sh`：
    1. 替换 `PREF_GROUPS=("AI" "西瓜加速" "GLOBAL" "自动选择")` 为 `PREF_GROUPS=("COPILOT" "DEV" "PROXY" "AUTO")`
    2. 搜索并替换其他过时组名引用（如有）
- **修改边界**：不得修改脚本核心测试逻辑和 `clash_pick_selector_group` 函数本身
- **测试要求**：
  - `bash -n vpn-tools/optimize_ai.sh` → 退出码 0
  - `grep -c '西瓜加速\|GLOBAL\|自动选择' vpn-tools/optimize_ai.sh` → 0
- **验收标准**：
  - ✅ PREF_GROUPS 包含且仅包含当前存在的组名
  - ✅ `bash -n` 通过
- **潜在风险**：PREF_GROUPS 可能在脚本中被多处引用，需确认只有一处定义

### Phase 2: 修复高频脚本

#### ✅ Task 2.1: 修复 `test_ai_connectivity.sh`

- **目标**：更新默认 GROUP 变量
- **修改内容**：
  - 文件 `vpn-tools/test_ai_connectivity.sh`：
    1. 替换 `GROUP=AI` 为 `GROUP=COPILOT`
    2. 搜索并替换其他过时引用（如有）
- **修改边界**：不得修改 API 调用逻辑和输出格式
- **测试要求**：
  - `bash -n vpn-tools/test_ai_connectivity.sh` → 退出码 0
  - `grep -c 'GROUP=AI\b' vpn-tools/test_ai_connectivity.sh` → 0
- **验收标准**：
  - ✅ 默认 GROUP 为当前存在的组名
  - ✅ `bash -n` 通过
- **潜在风险**：脚本可能接受 `--group` 参数覆盖，需确认默认值修改不影响参数解析

#### ✅ Task 2.2: 修复 `show_vpn_status.sh`

- **目标**：更新过时组名引用
- **修改内容**：
  - 文件 `vpn-tools/show_vpn_status.sh`：
    1. 替换所有 `西瓜加速`/`速云梯`/`GLOBAL`/`自动选择`/`故障转移`/`AUTO-SMART` 引用为当前组名
    2. 更新显示逻辑中的组名列表
- **修改边界**：不得修改 controller API 调用框架和输出格式结构
- **测试要求**：
  - `bash -n vpn-tools/show_vpn_status.sh` → 退出码 0
  - `grep -c '西瓜加速\|速云梯\|GLOBAL\|自动选择\|故障转移\|AUTO-SMART' vpn-tools/show_vpn_status.sh` → 0
- **验收标准**：
  - ✅ 不含任何旧订阅组名
  - ✅ `bash -n` 通过
- **潜在风险**：组名可能在 yq 查询表达式中出现，替换需保留 YAML 语法

### Phase 3: 验证与提交

#### ✅ Task 3.1: 全量回归验证

- **目标**：确认所有修复后的脚本可运行且输出正确
- **修改内容**：无文件修改
- **修改边界**：不修改任何文件
- **测试要求**：
  1. 语法检查：`for f in restart_clash_service.sh optimize_ai.sh test_ai_connectivity.sh show_vpn_status.sh; do bash -n vpn-tools/$f && echo "$f: OK"; done`
  2. 残留检查：`grep -rn 'AI-Manual\|AI-Claude\|proxies/AI"\|proxies/Streaming\|西瓜加速\|速云梯\|GLOBAL.*自动选择\|V1-美国' vpn-tools/restart_clash_service.sh vpn-tools/optimize_ai.sh vpn-tools/test_ai_connectivity.sh vpn-tools/show_vpn_status.sh` → 无输出
  3. 运行 `./vpn-tools/restart_clash_service.sh`（preview 模式）→ 输出正确的组名和节点
  4. 确认 mihomo 服务仍正常：`curl -s http://127.0.0.1:9090/version`
- **验收标准**：
  - ✅ 4 个脚本 `bash -n` 全通过
  - ✅ 无旧组名残留
  - ✅ restart_clash_service.sh preview 模式输出无 "Unknown"
  - ✅ mihomo 服务正常
- **潜在风险**：无

#### ✅ Task 3.2: 提交变更

- **目标**：git commit
- **修改内容**：`git add vpn-tools/restart_clash_service.sh vpn-tools/optimize_ai.sh vpn-tools/test_ai_connectivity.sh vpn-tools/show_vpn_status.sh && git commit`
- **修改边界**：仅提交这 4 个文件
- **测试要求**：`git show --stat HEAD` 仅显示这 4 个文件
- **验收标准**：
  - ✅ commit 仅包含修复的 4 个脚本
  - ✅ commit message 描述修复内容
- **潜在风险**：无

## 回归检查清单

- [ ] `bash -n` 通过：restart_clash_service.sh, optimize_ai.sh, test_ai_connectivity.sh, show_vpn_status.sh
- [ ] 无旧组名残留（grep 验证）
- [ ] restart_clash_service.sh preview 模式输出正确
- [ ] mihomo 服务 active
- [ ] API 可访问
- [ ] Copilot via proxy 正常（TTFB < 1s）

## 已知局限 / 可延期项

以下脚本仍含过时引用，但使用频率低或功能已被其他脚本覆盖，建议后续按需修复：

| 脚本 | 严重度 | 说明 |
|------|--------|------|
| `customize_ai_group.sh` | Critical | `GROUP="AI"` — 整个脚本不可用 |
| `optimize_ai_enhanced.sh` | Critical | `GROUP="AI"` + 旧节点名 |
| `merge_subscription.sh` | Critical | `GROUPS="GLOBAL,自动选择,故障转移"` |
| `use_jp_tailscale_only.sh` | Medium | AUTO-SMART/速云梯 等 |
| `intelligent_rule_optimizer.sh` | Medium | 西瓜加速/速云梯 候选列表 |
| `select_youtube_node.sh` | Medium | YOUTUBE/Streaming 组 |
| `optimize_youtube_streaming.sh` | Medium | 同上 |
| `streaming_manager.sh` | Medium | YOUTUBE 组 |
| `fix_zoom_connectivity.sh` | Medium | Streaming 候选 |
| `test_braintrust_connectivity.sh` | Low | AI-Manual 引用 |
| `test_chinese_ai_platforms.sh` | Low | AI 组引用 |
| `fix_openxlab_connectivity.sh` | Low | AI 组引用 |
| `optimize_mineru.sh` | Low | 西瓜加速 候选 |
| `network_dashboard.sh` | Low | 旧组名显示 |

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 2 | 2 | 0 |
| R2 | 可执行性 | 2 | 2 | 0 |
| R3 | 风险与边缘 | 1 | 1 | 0 |
| **终止** | **T1 — 收敛终止** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整 |
| 技术方案 | 完整（REDUCTION 模式，4 脚本） |
| Error & Rescue Map | 4 路径已覆盖, 0 CRITICAL GAP |
| 执行计划 | 3 Phase, 6 Task |
| 回归检查清单 | 6 项目特定检查 |
| 已知局限 | 14 个可延期脚本 |

### R1 Issues
- **Issue R1-1**: 初稿覆盖 25 个脚本，触达 >15 文件，强制 REDUCTION → 已精简到 4 个 P0+P1 脚本 ✅ 已修正
- **Issue R1-2**: Error & Rescue Map 缺失 → 已添加 4 条 ✅ 已修正

### R2 Issues
- **Issue R2-1**: Task 1.1 修改边界不够精确（"Step 6-8"太模糊）→ 改为明确行号范围 ✅ 已修正
- **Issue R2-2**: 缺少"已知局限"记录被 REDUCTION 排除的脚本 → 已添加 14 个可延期项表格 ✅ 已修正

### R3 Issues
- **Issue R3-1**: `restart_clash_service.sh` 在 `set -euo pipefail` 下修改 curl 命令时，如果 proxy 不可用会导致整个脚本退出 → 确认脚本已对 curl 用 `timeout ... 2>/dev/null` 包裹，不会触发 set -e ✅ 已修正

## Pre-Delivery Audit (Level: L1-Lite)

| § | Check | Status | Note |
|---|-------|--------|------|
| 1 | Unit consistency | ✅ PASS | 无数值/物理量，纯脚本修复 |

Auditor: Plan Architect | Date: 2026-04-13
