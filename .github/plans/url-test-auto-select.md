# url-test 自动选最快节点 + tolerance 200ms

## 背景与目标

- **问题/需求描述**：当前 `PROXY` 和 `DOCKER` 组为 `select` 类型（纯手动），节点故障不会自动切换。`DEV`/`COPILOT`/`VSCODE` 为 `fallback` 类型（固定优先级，队首存活就不切），不能根据延迟自动选最快节点。用户希望所有代理组支持基于延迟的自动选择。
- **根因分析**：初始配置在只有 JP 单节点时设计，加入 US 节点后未统一更新组策略。
- **目标**：
  - 新建 `AUTO` 组（`url-test`，tolerance=200ms），自动选延迟最低的节点
  - 将 `PROXY`/`DEV`/`COPILOT`/`VSCODE`/`DOCKER` 改为引用 `AUTO` 组，保留手动覆盖能力
  - 保障故障自动切换 + 延迟优选
- **非目标（不做什么）**：
  - 不修改 `ACADEMIC` 组 — 学术站点直连优先，代理仅备用，保持 select 手动控制
  - 不修改 mixin.yaml — mixin 只含 rules，无 proxy-groups
  - 不修改 `clashctl.sh` / `sanitize_runtime.sh` 中的 merge 逻辑 — url-test 类型字段不会被 merge 过程剥离（已验证）
  - 不新增节点、不修改节点参数
- **已有代码/流程复用分析**：
  - `_merge_build_runtime()`：复用（url-test 组的 url/interval/tolerance 不被 merge 剥离，仅 select 类型的这些字段会被删除 — 已在 clashctl.sh L530/540/551/565 确认）
  - `sanitize_runtime.sh`：复用（仅做 rules 注入，不修改 proxy-groups 类型）
  - `restart_clash_service.sh --apply`：复用（触发 stop+start 即可加载新 runtime）
  - 已部署 config.yaml（`~/.local/share/clash/config.yaml`）：需同步更新（merge 从此文件读取，非 resources/config.yaml）

## 技术方案

- **方案概述**：在 `resources/config.yaml` 的 `proxy-groups` 中新增一个 `AUTO` 组（type: url-test, tolerance: 200），包含 US-Tailscale + JP-Tailscale。然后将现有组改为 fallback，优先走 AUTO，故障时降级到 DIRECT。PROXY/Proxy 保持 select 但加入 AUTO 作为首选项，保留 Proxy→PROXY→AUTO 的嵌套关系。
- **关键设计决策**：
  1. **新建 `AUTO` 组而非改造 `PROXY`**：PROXY 被多处规则和下游组引用（DOCKER、ACADEMIC 的 proxies 列表都包含 PROXY）。如果把 PROXY 改成 url-test，则 DOCKER/ACADEMIC 引用 PROXY 时失去手动覆盖能力。新建 AUTO 组可以让 PROXY 保持 select 类型（可手动覆盖），同时默认选中 AUTO 实现自动。
  2. **tolerance=200ms**：CN→US ~620ms, CN→JP ~500ms，差值 ~120ms。tolerance=200ms 意味着只要当前选中的节点延迟不超过最快节点 +200ms 就不切换，避免两节点之间频繁跳动。
  3. **DEV/COPILOT/VSCODE 改为 fallback(AUTO → DIRECT)**：AUTO 内部已做延迟选优，这些组的 fallback 链变为 `AUTO → DIRECT`。AUTO 挂了（双节点都挂）才降级 DIRECT。
  4. **DOCKER 改为 fallback(AUTO → DIRECT)**：Docker pull 需要稳定性，auto→DIRECT fallback 比手动 select 更可靠。
  5. **interval=120s 统一**：健康检查间隔 120 秒，兼顾及时性与节点负载。VSCODE 组也统一到 120s（原 300s 太长，之前的 15s 是 runtime 残留值非源配置）。
- **影响范围**：
  - `resources/config.yaml`：proxy-groups 部分（约 40 行变更）
  - `~/.local/share/clash/config.yaml`：同步更新（merge 读取此文件）
  - `~/.local/share/clash/runtime.yaml`：由 `_merge_sanitize_restart` 自动重建

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| mihomo 加载含 url-test 的 runtime.yaml | 配置语法错误导致 mihomo 拒绝启动 | 配置错误 | Y | Task 1.2 中 `mihomo -t` 预验证 | 若验证失败则不替换 runtime |
| `_merge_sanitize_restart` 合并 | yq eval-all 因新组名 AUTO 与旧 runtime 合并冲突 | merge 冲突 | Y | merge 函数有 3 级回退策略 | 极端情况回退到 RAW 直接拷贝 |
| AUTO 组的 url-test 探测 | 双节点同时不可达 | 网络故障 | Y | 各业务组 fallback 链末尾有 DIRECT | 降级直连 |
| 已部署 config.yaml 未同步更新 | runtime merge 仍读旧配置 | 人为遗漏 | Y | Task 1.2 明确要求同步更新两份文件 | merge 后 runtime 无 AUTO 组 |
| url-test 高频探测拖累小内存节点 | 每 120s 2 个节点各 1 次 HTTP HEAD ≈ 忽略不计 | 资源 | N/A | interval=120s 已足够低频 | 无影响 |

## 执行计划

### Phase 1: 修改配置

#### Task 1.1: 修改 `resources/config.yaml` proxy-groups

- **目标**：新增 AUTO 组，改造现有组引用 AUTO
- **修改内容**：
  - 文件 `resources/config.yaml`：
    1. 在 proxy-groups 首位新增 AUTO 组：
       ```yaml
       - name: "AUTO"
         type: url-test
         proxies:
           - "US-Tailscale"
           - "JP-Tailscale"
         url: "https://www.gstatic.com/generate_204"
         interval: 120
         tolerance: 200
       ```
    2. PROXY 组：保持 select，proxies 改为 `[AUTO, US-Tailscale, JP-Tailscale, DIRECT]`（AUTO 为默认选中项）
    3. Proxy 组：保持 select，proxies 改为 `[PROXY, DIRECT]`（不变）
    4. DEV 组：改为 `fallback`，proxies 改为 `[AUTO, DIRECT]`，url 保持 gstatic，interval=120
    5. COPILOT 组：改为 `fallback`，proxies 改为 `[AUTO, DIRECT]`，url 保持 copilot-proxy，interval=120
    6. VSCODE 组：改为 `fallback`，proxies 改为 `[AUTO, DIRECT]`，url 保持 vscode update，interval=120（从 300 改为 120）
    7. DOCKER 组：改为 `fallback`，proxies 改为 `[AUTO, DIRECT]`，url=gstatic，interval=120
    8. ACADEMIC 组：不变（select, [PROXY, DIRECT]）
- **修改边界**：不得修改 `proxies:` 节点定义部分、`rules:` 部分、文件头部端口/模式配置
- **测试要求**：
  - 运行 `~/.local/share/clash/bin/mihomo -t -d ~/.local/share/clash -f /tmp/_test_config.yaml`（先拷贝修改后的 config.yaml 到 /tmp 测试）
  - 预期输出：configuration file ... test is successful
- **验收标准**：
  - ✅ resources/config.yaml 中存在 `name: "AUTO"` + `type: url-test` + `tolerance: 200`
  - ✅ PROXY 组 proxies 列表首项为 `AUTO`
  - ✅ DEV/COPILOT/VSCODE/DOCKER 组 type 均为 `fallback`，proxies 均包含 `AUTO` 和 `DIRECT`
  - ✅ ACADEMIC 组保持 `type: select`，未被修改
  - ✅ `mihomo -t` 预验证通过
- **潜在风险**：YAML 缩进错误导致 mihomo 拒绝加载；通过 mihomo -t 预验证规避

#### Task 1.2: 同步更新已部署 config.yaml 并重建 runtime

- **目标**：将 resources/config.yaml 的变更同步到 `~/.local/share/clash/config.yaml`，然后触发 merge+restart 重建 runtime.yaml
- **修改内容**：
  - 文件 `~/.local/share/clash/config.yaml`：覆盖 proxy-groups 部分（与 resources/config.yaml 保持一致）
  - 操作：`cp resources/config.yaml ~/.local/share/clash/config.yaml`，然后 `CLASH_LIB_MODE=1 source script/clashctl.sh && _merge_sanitize_restart`
- **修改边界**：不得修改 `clashctl.sh`、`sanitize_runtime.sh`、`mixin.yaml`
- **测试要求**：
  - 运行 `grep -c 'name.*AUTO' ~/.local/share/clash/runtime.yaml`
  - 预期输出：`1`（AUTO 组存在于 runtime）
  - 运行 `grep 'type: url-test' ~/.local/share/clash/runtime.yaml` 
  - 预期输出：包含 `url-test`
- **验收标准**：
  - ✅ runtime.yaml 中存在 AUTO 组且 type=url-test、tolerance=200
  - ✅ mihomo 进程已重启（PID 变更）
  - ✅ `systemctl --user is-active mihomo.service` 返回 active
- **潜在风险**：merge 过程中 yq 对新组名处理异常 → merge 函数有 3 级回退，最差情况直接复制 RAW config

### Phase 2: 验证

#### Task 2.1: 验证 url-test 自动选择与 fallback 行为

- **目标**：确认 AUTO 组正确探测并选中延迟最低的节点，确认 fallback 组正确引用 AUTO
- **修改内容**：无文件修改，仅验证操作
- **修改边界**：不修改任何文件
- **测试要求**：
  1. 检查 AUTO 组状态：
     ```bash
     curl -s http://127.0.0.1:9090/proxies/AUTO | python3 -c "import sys,json; d=json.load(sys.stdin); print('type:', d['type']); print('now:', d.get('now','?')); print('alive:', d['alive'])"
     ```
     预期：type=URLTest, now=US-Tailscale 或 JP-Tailscale（取决于延迟）, alive=True
  2. 检查各业务组当前选中节点：
     ```bash
     for g in PROXY DEV COPILOT VSCODE DOCKER ACADEMIC; do
       curl -s "http://127.0.0.1:9090/proxies/$g" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'$g: type={d[\"type\"]} now={d.get(\"now\",\"?\")} alive={d[\"alive\"]}')"
     done
     ```
     预期：DEV/COPILOT/VSCODE/DOCKER 的 now=AUTO；PROXY 的 now=AUTO；ACADEMIC 的 now 不变
  3. 端到端 Copilot 延迟测试：
     ```bash
     curl -so /dev/null -w 'ttfb=%{time_starttransfer} http=%{http_code}' -x http://127.0.0.1:7890 --connect-timeout 5 --max-time 10 'https://copilot-proxy.githubusercontent.com/_ping'
     ```
     预期：ttfb < 1s, http=200
  4. 强制触发 AUTO 延迟测试并观察选中结果：
     ```bash
     curl -si 'http://127.0.0.1:9090/proxies/AUTO/delay?timeout=5000&url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204'
     ```
     预期：HTTP 200，返回 JSON 含延迟值
- **验收标准**：
  - ✅ AUTO 组 type=URLTest，alive=True，now 为两个节点之一
  - ✅ DEV/COPILOT/VSCODE/DOCKER 组 now=AUTO
  - ✅ Copilot TTFB < 1s, HTTP 200
  - ✅ ACADEMIC 组未受影响（仍为 Selector）
- **潜在风险**：AUTO 刚创建时节点未探测，now 可能为空 → 触发手动 delay 测试后应自动选中

#### Task 2.2: 提交变更

- **目标**：git commit 本次配置变更
- **修改内容**：
  - `git add resources/config.yaml && git commit`
- **修改边界**：仅提交 resources/config.yaml
- **测试要求**：
  - `git diff HEAD~1 --stat` 仅显示 resources/config.yaml
- **验收标准**：
  - ✅ commit 仅包含 resources/config.yaml
  - ✅ commit message 描述 url-test AUTO 组和 tolerance 配置
- **潜在风险**：无

## 回归检查清单

- [ ] mihomo 服务 active 且 API 可访问（`curl -s http://127.0.0.1:9090/version`）
- [ ] US-Tailscale 节点 alive=True
- [ ] JP-Tailscale 节点 alive=True
- [ ] AUTO 组 type=URLTest, alive=True, tolerance=200
- [ ] COPILOT 组 now=AUTO, alive=True
- [ ] DEV 组 now=AUTO, alive=True
- [ ] VSCODE 组 now=AUTO, alive=True
- [ ] DOCKER 组 now=AUTO, alive=True
- [ ] ACADEMIC 组保持 type=Selector, 未被修改
- [ ] Copilot TTFB via proxy < 1s, HTTP 200
- [ ] DIRECT 流量正常（`curl -so /dev/null -w '%{http_code}' https://www.baidu.com` → 200）
- [ ] `MATCH,DIRECT` 规则仍在 rules 末尾

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 3 | 3 | 0 |
| R2 | 可执行性 | 2 | 2 | 0 |
| R3 | 风险与边缘 | 1 | 1 | 0 |
| **终止** | **T1 — 收敛终止** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整 |
| 技术方案 | 完整 |
| Error & Rescue Map | 5 路径已覆盖, 0 CRITICAL GAP |
| 执行计划 | 2 Phase, 4 Task |
| 回归检查清单 | 12 项目特定检查 |
| 已知局限 | 无 |

### R1 Issues
- **Issue R1-1**: 缺少 Error & Rescue Map → 已添加 5 条失败路径映射 ✅ 已修正
- **Issue R1-2**: 缺少已有代码/流程复用分析 → 已添加 4 项复用分析 ✅ 已修正
- **Issue R1-3**: Task 1.1 缺少 mihomo -t 预验证步骤 → 已添加到测试要求 ✅ 已修正

### R2 Issues
- **Issue R2-1**: Task 1.2 "同步更新"操作描述不够明确（是 sed 还是 cp） → 明确为 `cp resources/config.yaml ~/.local/share/clash/config.yaml` ✅ 已修正
- **Issue R2-2**: 验收标准中缺少 ACADEMIC 组的不变性检查 → 已在 Task 2.1 和回归检查清单中添加 ✅ 已修正

### R3 Issues
- **Issue R3-1**: 双节点同时故障时 AUTO 组为空、业务组无可用上游 → 确认各 fallback 组末尾有 DIRECT，AUTO 不可达时自动降级 DIRECT ✅ 已修正（在方案设计中明确 fallback 链为 AUTO → DIRECT）

## Pre-Delivery Audit (Level: L1-Lite)

| § | Check | Status | Note |
|---|-------|--------|------|
| 1 | Unit consistency | ✅ PASS | interval 单位 = 秒, tolerance 单位 = 毫秒, 与 mihomo 文档一致 |

Auditor: Plan Architect | Date: 2026-04-13
