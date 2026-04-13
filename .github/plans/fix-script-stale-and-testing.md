# 修复 script/ 核心层过时引用 + optimize_ai 缺陷 + 测试基础设施

## 背景与目标

- **问题/需求描述**：2026-04-13 全面审阅（`.github/reviews/stale-and-testing-2026-04-13.md`）发现三类问题：(1) `script/` 核心层 5 个文件含 AUTO-SMART/速云梯等订阅时代旧组名，其中 `clashctl.sh` 的 MATCH_GROUP 默认值 `AUTO-SMART` 导致 MATCH 兜底规则/wikipedia/VSCode/microsoft 路由静默失效——这是功能性回归；(2) `optimize_ai.sh` 有 `echo "\n"` 不换行 bug + 中断时不恢复节点的缺陷；(3) 477 个函数零单元测试，无 CI 测试 pipeline。
- **根因分析**：配置从订阅模式迁移到自建双节点后，`script/` 层的旧组名引用未同步更新。`optimize_ai.sh` 的 echo/trap 问题是原始编写时的缺陷。测试基础设施从未建立。
- **目标**：
  1. 修复 `script/` 核心层全部过时引用（S1–S6, Q6, B6–B9）
  2. 修复 `optimize_ai.sh` 的 echo \n + missing trap（Q7, Q8）
  3. 添加 CI lint pipeline + bats-core 测试框架 + 首批高价值函数测试
- **非目标（不做什么）**：
  - 不修复 vpn-tools/ 14 个延期脚本 — 已有延期清单，本计划不重复
  - 不删除/归档订阅时代脚本（`update_clash_subscription.sh` 等）— 仅标记 deprecated，保持向后兼容
  - 不重构 `_merge_build_runtime()` 架构 — 仅修复其中的过时默认值
  - 不添加容器化集成测试 — 超出本次范围
- **已有代码/流程复用分析**：
  - `sanitize_runtime.sh` 的 ACADEMIC → COPILOT 检测链：复用（仅更新 fallback 候选列表）
  - `run_static_gates.sh`：复用（CI pipeline 直接调用它）
  - `vpn-tools/testdata/sub_sample.yaml`：复用（作为 bats 测试的输入样本）

## 技术方案

- **方案概述**：分 4 阶段：(P1) `clashctl.sh` 关键回归修复 + dead code 删除；(P2) `sanitize_runtime.sh` + `clash_diagnose.sh` + `runtime_guard.sh` fallback 更新；(P3) `optimize_ai.sh` + `auto_optimize_clash.sh` 缺陷修复；(P4) CI pipeline + bats 测试框架 + 首批测试用例。
- **关键设计决策**：
  1. **MATCH_GROUP 默认值**：改为 `PROXY`（而非 `AUTO`）。原因：PROXY 是 select 类型，用户可手动控制；AUTO 是 url-test 类型，可能在双节点都不稳定时无法手动覆盖。PROXY 默认选择 AUTO，形成 `PROXY → AUTO → 最优节点` 链路。
  2. **auto_optimize_clash.sh 处理**：不删除，在入口处添加 deprecation guard（检测 AUTO-SMART 分组是否存在，不存在则提示并 exit），保持向后兼容。
  3. **clashctl.sh 循环检测**：删除整个 if 块（L601-609），因为依赖的两个分组均不存在。保留上方注释改为说明"已移除旧分组循环检测"。
  4. **bats-core 引入方式**：git submodule 在 `tests/bats-core/`，避免 system-level 安装依赖。
  5. **clash_diagnose.sh / runtime_guard.sh 中的 `西瓜加速`**：仅在 grep pattern 中替换/扩展，不改变逻辑。将 `西瓜加速` 替换为 `AUTO`（当前实际代理组名），grep 模式保持宽泛。
- **影响范围**：
  - `script/clashctl.sh`
  - `script/sanitize_runtime.sh`
  - `script/clash_diagnose.sh`
  - `script/runtime_guard.sh`
  - `script/auto_optimize_clash.sh`
  - `vpn-tools/optimize_ai.sh`
  - `.github/workflows/lint.yml`（新建）
  - `tests/`（新建目录）

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| clashctl.sh MATCH_GROUP 改为 PROXY | PROXY 分组不存在（极端场景） | 运行时 | Y | yq `-e` gate 会跳过整块 → 无 MATCH 注入（同现在） | 无变化（降级安全） |
| 循环检测块删除 | 未来若有新循环分组 | 运行时 | N → 低风险 | mihomo -t 验证会捕获循环 | mihomo 启动失败，用户看到明确报错 |
| sanitize fallback 列表改为 ACADEMIC→AUTO→PROXY | 三者都不存在 | 运行时 | Y | 已有空字符串检查 → 不注入规则 | Google Scholar 无代理路由（降级安全） |
| auto_optimize_clash deprecation guard | 用户强制运行 | 用户操作 | Y | exit 1 + 明确提示 | 脚本拒绝执行 |
| bats 测试失败 | 测试环境缺少依赖 | CI | Y | CI workflow 有 `continue-on-error: false` | PR check 失败，阻止合并 |

## 执行计划

### Phase 1: 修复 clashctl.sh 关键回归

#### ✅ Task 1.1: 修复 MATCH_GROUP 默认值 + 更新注释

- **目标**：将 `CLASH_MATCH_GROUP` 默认值从 `AUTO-SMART` 改为 `PROXY`，恢复 MATCH/wikipedia/VSCode/microsoft 路由注入
- **修改内容**：
  - 文件 `script/clashctl.sh`：
    1. L618: `${CLASH_MATCH_GROUP:-AUTO-SMART}` → `${CLASH_MATCH_GROUP:-PROXY}`
    2. L611 注释: `若存在 AUTO-SMART 分组` → `若存在目标分组`
    3. L633 注释: `通常为 AUTO-SMART` → `通常为 PROXY`
- **修改边界**：不得修改 L619-645 的 yq 逻辑本身（规则注入模板）
- **测试要求**：
  - `bash -n script/clashctl.sh` → 退出码 0
  - `grep -c 'AUTO-SMART' script/clashctl.sh` → 数值比修改前减少 3（L611, L618, L633）
  - 运行 `CLASH_LIB_MODE=1 source script/clashctl.sh && _merge_sanitize_restart` → runtime.yaml 包含 `MATCH,PROXY` 规则
  - `grep 'MATCH,PROXY' ~/.local/share/clash/runtime.yaml` → 有输出
  - `grep 'wikipedia.org,PROXY' ~/.local/share/clash/runtime.yaml` → 有输出
- **验收标准**：
  - ✅ `CLASH_MATCH_GROUP` 默认值为 `PROXY`
  - ✅ runtime.yaml 中存在 `MATCH,PROXY` 兜底规则
  - ✅ runtime.yaml 中存在 `wikipedia.org,PROXY` 路由
  - ✅ runtime.yaml 中存在 `update.code.visualstudio.com,PROXY` 路由
  - ✅ mihomo 正常运行（`curl -s --noproxy '*' http://127.0.0.1:9090/version`）
- **潜在风险**：merge_sanitize_restart 会重建 runtime 并重启 mihomo — 短暂代理中断（< 3s）

#### ✅ Task 1.2: 删除 AUTO-SMART ↔ 速云梯循环检测死代码

- **目标**：移除引用已不存在分组的死代码块
- **修改内容**：
  - 文件 `script/clashctl.sh`：
    1. 删除 L601-609 的 `# 防御性修复：ProxyGroup 循环 (AUTO-SMART <-> 速云梯)` 整个 if 块（注释 + 代码）
    2. 在原位置添加单行注释：`# NOTE: 旧订阅时代 AUTO-SMART↔速云梯循环检测已移除 (2026-04, 不再需要)`
- **修改边界**：不得修改 L595-599（DIRECT 规则注入）和 L610+（MATCH 路由注入）
- **测试要求**：
  - `bash -n script/clashctl.sh` → 退出码 0
  - `grep -c '速云梯' script/clashctl.sh` → 0
  - `grep -c 'AUTO-SMART' script/clashctl.sh` → 0（Task 1.1 + 1.2 合计清零）
- **验收标准**：
  - ✅ `script/clashctl.sh` 中不含 `AUTO-SMART` 或 `速云梯` 字符串
  - ✅ `bash -n` 通过
  - ✅ mihomo 正常运行
- **潜在风险**：无（移除的代码在当前配置下永远不执行）

### Phase 2: 修复其他 script/ 过时引用

#### ✅ Task 2.1: 更新 sanitize_runtime.sh fallback 候选列表

- **目标**：将 Google Scholar 路由的 fallback 候选从 `AUTO-SMART → 速云梯 → PROXY` 更新为 `ACADEMIC → AUTO → PROXY`
- **修改内容**：
  - 文件 `script/sanitize_runtime.sh`：
    1. L121-122: yq jq-style fallback 中的 `AUTO-SMART` → `AUTO`，`速云梯` → 删除该行（ACADEMIC 已在首位）
    2. L167: bash fallback 中的 `for cand in AUTO-SMART 速云梯 PROXY` → `for cand in ACADEMIC AUTO PROXY`
- **修改边界**：不得修改 Copilot routing 逻辑（L139-160）— 该段已正确检测 COPILOT 分组
- **测试要求**：
  - `bash -n script/sanitize_runtime.sh` → 退出码 0
  - `grep -c 'AUTO-SMART\|速云梯' script/sanitize_runtime.sh` → 0
  - 运行 sanitize_runtime（通过 `_merge_sanitize_restart`）→ runtime.yaml 中 `scholar.google.com` 规则指向 `ACADEMIC`（因为 ACADEMIC 存在于 config）
- **验收标准**：
  - ✅ `sanitize_runtime.sh` 中不含 `AUTO-SMART` 或 `速云梯`
  - ✅ runtime.yaml 中 `scholar.google.com,ACADEMIC` 规则存在
  - ✅ `bash -n` 通过
- **潜在风险**：如果 ACADEMIC 分组被移除（当前存在），会 fallback 到 AUTO → PROXY，安全降级

#### ✅ Task 2.2: 更新 clash_diagnose.sh + runtime_guard.sh 中的过时组名

- **目标**：将 hijack 检测中的 `西瓜加速` 更新为当前组名
- **修改内容**：
  - 文件 `script/clash_diagnose.sh`：
    1. L279: grep pattern `(PROXY|西瓜加速)` → `(PROXY|AUTO|COPILOT|DEV)`
  - 文件 `script/runtime_guard.sh`：
    1. L367: grep pattern `(西瓜加速|PROXY|Proxy|proxy)` → `(AUTO|PROXY|Proxy|proxy|COPILOT|DEV)`
- **修改边界**：不得修改 grep 命令的结构或 surrounding logic，仅替换 pattern 中的组名
- **测试要求**：
  - `bash -n script/clash_diagnose.sh` → 退出码 0
  - `bash -n script/runtime_guard.sh` → 退出码 0
  - `grep -c '西瓜加速' script/clash_diagnose.sh script/runtime_guard.sh` → 0 + 0
- **验收标准**：
  - ✅ 两个文件中不含 `西瓜加速`
  - ✅ hijack 检测 pattern 包含当前实际代理组名
  - ✅ `bash -n` 通过
- **潜在风险**：grep pattern 更宽（多了 AUTO/COPILOT/DEV），理论上可能匹配更多规则 — 但 hijack 规则本身有 IP-CIDR 限定，误报风险极低

#### ✅ Task 2.3: 标记 auto_optimize_clash.sh 为 deprecated

- **目标**：防止用户意外运行一个会向 mixin 写入不存在分组名的脚本
- **修改内容**：
  - 文件 `script/auto_optimize_clash.sh`：
    1. 在 `set -euo pipefail` 之后（L12）、`BASE_DIR=` 之前（L14）插入 deprecation guard：
       ```bash
       # DEPRECATED: 此脚本围绕旧订阅模式的 AUTO-SMART/西瓜加速 分组设计。
       # 当前配置使用 AUTO (url-test) 分组自动选择最优节点，无需手动测速。
       # 若确需运行，设置环境变量 FORCE_LEGACY=1 绕过此检查。
       if [[ "${FORCE_LEGACY:-}" != "1" ]]; then
         echo "⚠️  此脚本已弃用。当前 AUTO (url-test) 分组已自动完成节点选择。" >&2
         echo "    若确需运行旧测速逻辑，请设置 FORCE_LEGACY=1。" >&2
         exit 1
       fi
       ```
- **修改边界**：不得修改脚本其余逻辑（保持代码原样，仅添加 guard）
- **测试要求**：
  - `bash -n script/auto_optimize_clash.sh` → 退出码 0
  - `bash script/auto_optimize_clash.sh 2>&1` → 包含 "已弃用" 且退出码 1
  - `FORCE_LEGACY=1 bash script/auto_optimize_clash.sh --dry 2>&1 | head -3` → 不含 "已弃用"（进入正常逻辑，可能因缺少 runtime 而报错 — 这是正常行为）
- **验收标准**：
  - ✅ 不带 FORCE_LEGACY 运行时，脚本 exit 1 并显示弃用提示
  - ✅ `FORCE_LEGACY=1` 可绕过检查
  - ✅ `bash -n` 通过
- **潜在风险**：无（仅添加入口 guard）

### Phase 3: 修复 optimize_ai.sh 缺陷

#### ✅ Task 3.1: 修复 echo "\n" + 添加 EXIT trap

- **目标**：修复 bash 下 `echo "\n"` 不换行的 bug，并添加 EXIT trap 恢复中断时的节点选择
- **修改内容**：
  - 文件 `vpn-tools/optimize_ai.sh`：
    1. L173: `echo "\n🧪 Testing node: $node"` → `printf '\n🧪 Testing node: %s\n' "$node"`
    2. L185: `echo "\n🏆 Best node: $best_node (score $best_score)"` → `printf '\n🏆 Best node: %s (score %s)\n' "$best_node" "$best_score"`
    3. 在 `original=""` 行（L137）之前插入 trap：
       ```bash
       # Restore original node selection on exit/interrupt
       _restore_original() {
         if [[ -n "${original:-}" ]]; then
           switch_node "$original" >/dev/null 2>&1 || true
         fi
       }
       trap _restore_original EXIT
       ```
       注意：`switch_node` 定义在 L145，但 trap 在 EXIT 时才执行，不影响定义顺序。
    4. 在 APPLY==1 分支（L192-200）中，在 `switch_node "$best_node"` 之前添加 `trap - EXIT`（卸载 trap，因为已决定应用结果而非恢复）
- **修改边界**：不得修改 `switch_node()`、`test_platform()`、`pick_group()` 函数逻辑
- **测试要求**：
  - `bash -n vpn-tools/optimize_ai.sh` → 退出码 0
  - `grep -c 'echo "\\n' vpn-tools/optimize_ai.sh` → 0
  - `grep -c 'trap.*EXIT' vpn-tools/optimize_ai.sh` → ≥ 1
  - `grep -c 'printf.*Testing node' vpn-tools/optimize_ai.sh` → 1
- **验收标准**：
  - ✅ 无 `echo "\n` 模式
  - ✅ 存在 EXIT trap
  - ✅ APPLY 分支在切换前卸载 trap
  - ✅ `bash -n` 通过
- **潜在风险**：trap 中 `switch_node` 调用发生在脚本退出时，此时 controller 可能不可达 — 已有 `|| true` 容错

#### ✅ Task 3.2: 添加缺失的 shebang（Q9 + Q10）

- **目标**：为 `enable_vscode_fallback_direct.sh` 和 `common.sh` 添加 shebang
- **修改内容**：
  - 文件 `vpn-tools/enable_vscode_fallback_direct.sh`：在第 1 行前插入 `#!/usr/bin/env bash`
  - 文件 `script/common.sh`：在第 1 行 `# shellcheck disable=SC2148` 之前插入 `#!/usr/bin/env bash`（保留 shellcheck 注释）
- **修改边界**：仅修改文件首行
- **测试要求**：
  - `head -1 vpn-tools/enable_vscode_fallback_direct.sh` → `#!/usr/bin/env bash`
  - `head -1 script/common.sh` → `#!/usr/bin/env bash`
  - `bash -n vpn-tools/enable_vscode_fallback_direct.sh` + `bash -n script/common.sh` → 退出码 0
- **验收标准**：
  - ✅ 两个文件首行为 `#!/usr/bin/env bash`
  - ✅ `bash -n` 通过
- **潜在风险**：`common.sh` 已有 `# shellcheck disable=SC2148`（SC2148 = missing shebang），添加 shebang 后该注释可移除但不强制

### Phase 4: 测试基础设施

#### ✅ Task 4.1: 添加 CI lint workflow

- **目标**：在 GitHub Actions 中自动化运行 `bash -n` + `run_static_gates.sh`
- **修改内容**：
  - 新建文件 `.github/workflows/lint.yml`：
    ```yaml
    name: Lint & Static Gates
    on: [push, pull_request]
    jobs:
      lint:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - name: bash -n syntax check
            run: |
              shopt -s globstar
              for f in script/*.sh vpn-tools/*.sh vpn-tools/lib/*.sh; do
                bash -n "$f" || exit 1
              done
          - uses: actions/setup-python@v5
            with:
              python-version: '3.x'
          - name: Static gates
            run: bash script/run_static_gates.sh
    ```
- **修改边界**：不修改任何已有文件
- **测试要求**：
  - `yamllint .github/workflows/lint.yml` → 无错误（若有 yamllint 可用）
  - 手动检查 YAML 语法正确
- **验收标准**：
  - ✅ `.github/workflows/lint.yml` 存在且语法合法
  - ✅ workflow 包含 `bash -n` 和 `run_static_gates.sh` 两个步骤
- **潜在风险**：如果 repo 从未 push 到 GitHub，workflow 不会被触发 — 但文件仍可作为文档记录 CI 期望

#### ✅ Task 4.2: 引入 bats-core 测试框架 + 首批测试

- **目标**：建立测试目录结构，为 `sanitize_runtime.sh` 的路由注入逻辑编写首批验证测试
- **修改内容**：
  - 新建目录 `tests/`
  - 新建文件 `tests/README.md`：简要说明如何运行测试
  - 新建文件 `tests/run_tests.sh`：简易测试运行器脚本（不依赖外部 bats 安装，用纯 bash 实现 assert 函数）
  - 新建文件 `tests/test_sanitize_runtime.sh`：
    1. 测试 Google Scholar fallback 在当前 config 下选择 ACADEMIC
    2. 测试 Copilot routing 在 COPILOT 分组存在时选择 COPILOT
    3. 测试 fallback 在分组都不存在时不注入危险规则
  - 新建文件 `tests/testdata/config_minimal.yaml`：最小化测试用 config（含 ACADEMIC, PROXY, AUTO 分组）
  - 新建文件 `tests/testdata/config_no_groups.yaml`：无分组测试用 config
- **修改边界**：不修改任何已有文件。测试通过 source 方式加载被测函数。
- **测试要求**：
  - `bash tests/run_tests.sh` → 全部测试通过
  - 测试在无 mihomo 运行的环境下也能执行（使用静态 YAML 文件，不依赖 controller API）
- **验收标准**：
  - ✅ `tests/` 目录存在
  - ✅ `bash tests/run_tests.sh` 输出全部 PASS
  - ✅ 测试不依赖网络或运行中的 mihomo
  - ✅ 首批 ≥ 3 个测试用例覆盖 sanitize_runtime 路由选择
- **潜在风险**：`sanitize_runtime.sh` 中部分逻辑依赖全局变量（`$RUNTIME`, `$YQ_BIN`），测试需 mock 这些变量 — 可通过 export + 临时文件实现

### Phase 5: 验证与提交

#### ✅ Task 5.1: 全量回归验证

- **目标**：确认所有修改后系统正常运行
- **修改内容**：无
- **修改边界**：不修改任何文件
- **测试要求**：
  1. 语法检查：`for f in script/*.sh; do bash -n "$f"; done` → 全通过
  2. 残留检查：`grep -rn 'AUTO-SMART\|速云梯' script/*.sh` → 仅 `auto_optimize_clash.sh` 中 deprecation 注释
  3. Static gates：`bash script/run_static_gates.sh` → 全通过
  4. 测试框架：`bash tests/run_tests.sh` → 全通过
  5. mihomo 正常：`curl -s --noproxy '*' http://127.0.0.1:9090/version` → 返回版本
  6. runtime.yaml 验证：
     - `grep 'MATCH,PROXY' ~/.local/share/clash/runtime.yaml` → 有输出
     - `grep 'scholar.google.com,ACADEMIC' ~/.local/share/clash/runtime.yaml` → 有输出
     - `grep 'copilot-proxy.githubusercontent.com,COPILOT' ~/.local/share/clash/runtime.yaml` → 有输出
  7. Copilot 连通：`curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 -x http://127.0.0.1:7890 https://copilot-proxy.githubusercontent.com/_ping` → 200
- **验收标准**：
  - ✅ 全部 7 项检查通过
  - ✅ 无回归
- **潜在风险**：`_merge_sanitize_restart` 重启 mihomo 可能导致短暂代理中断

#### ✅ Task 5.2: 提交变更

- **目标**：git commit
- **修改内容**：
  - Commit 1（核心修复）：`script/clashctl.sh`, `script/sanitize_runtime.sh`, `script/clash_diagnose.sh`, `script/runtime_guard.sh`, `script/auto_optimize_clash.sh`
  - Commit 2（optimize_ai + shebang）：`vpn-tools/optimize_ai.sh`, `vpn-tools/enable_vscode_fallback_direct.sh`, `script/common.sh`
  - Commit 3（测试基础设施）：`.github/workflows/lint.yml`, `tests/` 目录
- **修改边界**：仅提交上述文件
- **测试要求**：
  - `git show --stat HEAD~2..HEAD` → 仅列出上述文件
- **验收标准**：
  - ✅ 3 个 commit，每个有清晰的 commit message
  - ✅ 无意外修改的文件
- **潜在风险**：无

## 回归检查清单

- [ ] `bash -n` 通过：所有 `script/*.sh` 文件
- [ ] `bash -n` 通过：`vpn-tools/optimize_ai.sh`, `vpn-tools/enable_vscode_fallback_direct.sh`
- [ ] `grep -rn 'AUTO-SMART\|速云梯' script/*.sh` → 仅 `auto_optimize_clash.sh` 内的注释/字符串
- [ ] `grep -c '西瓜加速' script/clash_diagnose.sh script/runtime_guard.sh` → 0 + 0
- [ ] Static gates：`bash script/run_static_gates.sh` → all pass
- [ ] 测试：`bash tests/run_tests.sh` → all pass
- [ ] runtime.yaml 包含 `MATCH,PROXY`
- [ ] runtime.yaml 包含 `scholar.google.com,ACADEMIC`
- [ ] runtime.yaml 包含 `update.code.visualstudio.com,PROXY`
- [ ] mihomo 服务 active
- [ ] Copilot via proxy 正常（TTFB < 1s）
- [ ] `auto_optimize_clash.sh` 直接运行 → exit 1 + 弃用提示

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 3 | 3 | 0 |
| R2 | 可执行性 | 4 | 4 | 0 |
| R3 | 风险与边缘 | 2 | 2 | 0 |
| **终止** | **T1 — 收敛终止** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整 |
| 技术方案 | 完整 |
| Error & Rescue Map | 5 路径已覆盖，0 CRITICAL GAP |
| 执行计划 | 5 Phases, 9 Tasks |
| 回归检查清单 | 12 项目特定检查 |
| 已知局限 | vpn-tools 14 个延期脚本不在本计划范围；订阅时代脚本仅标记 deprecated 未删除 |

### R1 Issues
- **Issue R1-1**: 缺少 Error & Rescue Map → 已补充 5 条失败路径 ✅ 已修正
- **Issue R1-2**: 缺少已有代码/流程复用分析 → 已补充 3 条复用说明 ✅ 已修正
- **Issue R1-3**: Phase 4 Task 4.2 缺少 testdata 文件的具体内容说明 → 已补充 config_minimal.yaml / config_no_groups.yaml 说明 ✅ 已修正

### R2 Issues
- **Issue R2-1**: Task 1.1 测试要求中 `_merge_sanitize_restart` 需要说明它会重启 mihomo → 已在潜在风险中标注 ✅ 已修正
- **Issue R2-2**: Task 4.2 bats-core git submodule 方案增加操作复杂度 → 改为纯 bash 测试运行器（无外部依赖） ✅ 已修正
- **Issue R2-3**: Task 1.2 "grep AUTO-SMART 应为 0" 依赖 Task 1.1 先完成 → 已在验收标准中明确"Task 1.1 + 1.2 合计清零" ✅ 已修正
- **Issue R2-4**: Task 5.2 分 3 个 commit，需说明每个 commit 的范围 → 已补充 ✅ 已修正

### R3 Issues
- **Issue R3-1**: MATCH_GROUP 改为 PROXY 后，如果用户手动设置 `CLASH_MATCH_GROUP=AUTO`（url-test 组），规则能否注入？→ 可以：yq `-e` 检查组是否存在于 proxy-groups，AUTO 存在即可。非 Task 改动范围，无影响。 ✅ 已验证
- **Issue R3-2**: Task 3.1 trap 中 `switch_node` 引用 `$original`，但 `original` 在 trap 定义之后才赋值 → trap 在 EXIT 时才执行（惰性绑定），此时 `original` 已赋值。若脚本在赋值前就退出（如 pick_group 失败），`original` 为空，trap 内有 `-n` 检查，安全。 ✅ 已验证
