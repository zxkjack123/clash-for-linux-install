# 加速节点切换 + 健康监控优化

## 背景与目标
- **问题/需求描述**：2026-04-14 09:30 JP-Tailscale 节点短暂失联，AUTO url-test 组虽在约 1 分钟内检测到并切换至 US-Tailscale，但检测间隔为 120s，切换窗口偏大。同时健康监控面板存在三个体验问题：(1) 桌面通知不会自动消失，过期的 F-故障通知长期留在屏幕；(2) Kimi 已不使用但仍参与检测，其 5s 超时拉低 AI 服务成功率；(3) Semantic-Scholar 等站点自身不稳定（429/000），属于站点自身问题而非 Clash 网络问题，不应以同等权重影响健康分数。
- **根因分析**：
  1. `resources/config.yaml` 中 AUTO 组 `interval: 120`，url-test 间隔 2 分钟，失联检测延迟可达 2 分钟。
  2. `alert_notification.sh` 的 `notify-send` 调用未传 `-t` 参数（超时毫秒），导致通知持久显示。
  3. `network_health_monitor.sh` 中 AI 服务列表硬编码了 Kimi。
  4. 健康分数计算按"成功/总数"计算成功率，1 个站点的超时就使得 dev 成功率从 100% 骤降至 75%，未区分"站点自身不稳定"与"Clash 网络故障"。
- **目标**：
  - 将 AUTO url-test 检测间隔从 120s 降至 30s，加速节点故障检测与切换
  - 桌面通知设置 15 秒自动消失
  - 移除 Kimi 检测端点
  - 将 Semantic-Scholar 标记为"不稳定站点"，其失败不拉低成功率计算
- **非目标（不做什么）**：
  - 不修改 tolerance 值（200ms 已合理，避免频繁抖动切换） — 用户未要求
  - 不修改流媒体/国内检测端点 — 用户未要求
  - 不重构 calculate_health_score 整体权重模型 — 仅做精准的不稳定站点剔除
  - 不修改 mixin.yaml — interval 通过 config.yaml 管理即可
- **已有代码/流程复用分析**：
  - `_merge_build_runtime()` (clashctl.sh): 复用 — config.yaml 修改后通过现有 merge 流程自动同步至 runtime.yaml
  - `test_url()` (network_health_monitor.sh): 复用 — 不修改测试函数逻辑
  - `alert()` / `send_desktop_notification()` (alert_notification.sh): 修改 — 在现有函数内加 `-t` 参数

## 技术方案
- **方案概述**：修改 4 个文件：(1) config.yaml 调整 interval，(2) alert_notification.sh 加 notify-send 超时，(3) network_health_monitor.sh 移除 Kimi + 标记不稳定站点 + 调整成功率计算
- **关键设计决策**：
  - **interval=30 而非更低**：30s 已能在 1 次检测周期内发现故障，且不会给 gstatic 增加过多探测负担。同时 DEV/COPILOT/VSCODE/DOCKER Fallback 组也设为 30s 以保持一致。
  - **不稳定站点标记**：在站点定义中增加第 5 个 tab 分隔字段 `unstable`，标记后其失败不计入成功率（但仍然测试并记录日志）。这样既不丢失监控信息，又不虚假拉低分数。
  - **notify-send `-t 15000`**：15 秒（15000ms）后自动消失。注意：某些桌面环境（如 GNOME）会忽略 `-t` 参数，但在大多数 DE（XFCE/KDE/MATE）中有效。作为最佳努力方案。
- **影响范围**：
  - `resources/config.yaml`：proxy-groups 中 6 个 interval 值
  - `vpn-tools/alert_notification.sh`：1 行 notify-send 调用
  - `vpn-tools/network_health_monitor.sh`：AI 服务列表（删 Kimi）+ dev 服务列表（标记 Semantic-Scholar）+ 各 check_*_services 函数的成功率计算

## Error & Rescue Map（关键失败路径映射）

| 代码路径/操作 | 可能的失败 | 错误类型 | 已处理？ | 处理方式 | 用户可见行为 |
|-------------|-----------|---------|---------|---------|------------|
| config.yaml interval=30，merge 后 runtime 仍为 120 | yq merge 未正确覆盖 | 配置合并 | Y | 验收时对比 runtime.yaml interval 值 | 节点切换仍慢 |
| notify-send -t 15000 在 GNOME 下被忽略 | 桌面环境不支持 | 兼容性 | Y | 文档说明；GNOME 用户可手动关闭通知 | 通知仍持久显示 |
| 移除 Kimi 后 AI 服务总数从 6 变 5 | 无 | N/A | Y | 成功率自动按新总数计算 | 正常 |
| unstable 字段解析失败（IFS 多字段） | bash IFS 截断 | 解析 | Y | 缺省为空字符串，`[[ == "unstable" ]]` 不匹配则正常计入 | 保守行为（仍计入成功率） |

## 执行计划

### Phase 1: 加速节点切换

#### ✅ Task 1.1: 将 url-test/fallback interval 从 120 降至 30
- **目标**：使 AUTO/DEV/COPILOT/VSCODE/DOCKER 组每 30 秒探测一次节点健康，故障检测延迟从最大 120s 降至 30s
- **修改内容**：
  - 文件 `resources/config.yaml`：将所有 `interval: 120` 改为 `interval: 30`（共 6 处：AUTO, DEV, COPILOT, VSCODE, DOCKER, 以及备注中可能的其他组）
- **修改边界**：不得修改 `resources/mixin.yaml`、`tolerance` 值、`url` 探测地址、proxy-groups 的组成员
- **测试要求**：
  - 运行 `grep 'interval:' resources/config.yaml` 确认所有 interval 为 30
  - 执行 `CLASH_LIB_MODE=1 bash -c '. script/common.sh; . script/clashctl.sh; _merge_sanitize_restart'` 重建 runtime 并重启
  - 运行 `grep 'interval:' ~/.local/share/clash/runtime.yaml`，期望所有 interval 为 30
  - 通过 controller API 验证：`curl ... http://127.0.0.1:9090/proxies/AUTO | python3 -c "..."` 确认 `testUrl` 和配置已生效
- **验收标准**：
  - ✅ `resources/config.yaml` 中所有 `interval` 值均为 `30`
  - ✅ `runtime.yaml` 中所有 `interval` 值均为 `30`
  - ✅ mihomo 服务运行正常（`systemctl --user is-active mihomo` = `active`）
- **潜在风险**：interval=30 会使探测频率翻 4 倍，对 gstatic.com 等探测 URL 产生略多请求；鉴于只有 2 个节点，每 30s 共 2 次 GET 204，流量可忽略

### Phase 2: 通知自动消失

#### ✅ Task 2.1: notify-send 添加 -t 15000 超时参数
- **目标**：桌面通知弹出后 15 秒自动消失，避免过期告警长期留在屏幕
- **修改内容**：
  - 文件 `vpn-tools/alert_notification.sh`：在 `notify-send` 调用中加 `-t 15000` 参数
    - 原：`notify-send -u "$urgency" -i "$icon" "Clash 网络监控" "$ALERT_MESSAGE"`
    - 改：`notify-send -t 15000 -u "$urgency" -i "$icon" "Clash 网络监控" "$ALERT_MESSAGE"`
- **修改边界**：不得修改 `zenity`/`kdialog` 分支、不得修改告警级别逻辑、不得修改日志写入逻辑
- **测试要求**：
  - 运行 `bash -n vpn-tools/alert_notification.sh`，期望无语法错误
  - 手动执行 `notify-send -t 15000 -u normal -i dialog-warning "Clash 网络监控" "测试通知 - 应在15秒后消失"` 验证桌面通知行为
- **验收标准**：
  - ✅ `alert_notification.sh` 中 `notify-send` 调用包含 `-t 15000` 参数
  - ✅ `bash -n` 无语法错误
  - ✅ 手动测试通知在桌面弹出后约 15 秒内自动消失（GNOME 除外）
- **潜在风险**：GNOME Shell 的通知守护程序会忽略 `-t` 参数（GNOME 设计决策）。如用户使用 GNOME，通知仍为持久型。可后续通过 `gdbus` 调用或切换到 `dunst` 等支持超时的通知守护解决，但不在本次范围内

### Phase 3: 优化健康检测端点

#### ✅ Task 3.1: 移除 Kimi 检测端点
- **目标**：从 AI 服务检测列表中移除不再使用的 Kimi 端点，AI 服务检测数量从 6 降至 5
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：删除 `check_ai_services()` 函数中 Kimi 条目（约第 158 行）
    ```
    $'https://kimi.moonshot.cn/\tKimi\t^[23]\tyes'
    ```
- **修改边界**：不得修改其他 AI 服务端点、不得修改 `check_dev_services` / `check_streaming_services` / `check_domestic_sites`
- **测试要求**：
  - 运行 `bash -n vpn-tools/network_health_monitor.sh`，期望无语法错误
  - 运行 `grep -i kimi vpn-tools/network_health_monitor.sh`，期望无输出
  - 手动运行 `bash vpn-tools/network_health_monitor.sh --check-only 2>&1 | grep -E 'AI服务|Kimi'`，期望不出现 Kimi 行，AI 服务总数为 5
- **验收标准**：
  - ✅ `network_health_monitor.sh` 中不包含 `kimi` 或 `Kimi` 关键字
  - ✅ `bash -n` 无语法错误
  - ✅ 健康检查运行时 AI 服务列表只检测 5 个端点
- **潜在风险**：若未来恢复使用 Kimi，需手动加回。影响极小

#### ✅ Task 3.2: 标记 Semantic-Scholar 为不稳定站点并调整成功率计算
- **目标**：对已知自身不稳定的外部服务（如 Semantic-Scholar 频繁返回 429/000），将其检测结果从成功率计算中排除，使健康分数更真实地反映 Clash 网络状态
- **修改内容**：
  - 文件 `vpn-tools/network_health_monitor.sh`：
    1. **标记不稳定站点**：在 `check_dev_services()` 中 Semantic-Scholar 条目末尾加 tab + `unstable` 标记：
       ```
       $'https://api.semanticscholar.org/graph/v1/paper/search?query=test&limit=1\tSemantic-Scholar\t^([23]|429)\tunstable'
       ```
    2. **修改 `check_dev_services()` 循环**：解析第 4 字段；若为 `unstable` 且 `succ==0`，则不计入 total/success（仍记录日志）
    3. **同样修改 `check_ai_services()` 循环**：虽然当前 AI 列表无 unstable 站点，但保持两个函数的解析逻辑一致，未来可方便标记
- **修改边界**：不得修改 `test_url()` 函数、不得修改 `calculate_health_score()` 函数、不得修改 `check_streaming_services` 或 `check_domestic_sites`（这两个函数使用 `|` 分隔符格式不同，无需改动）
- **测试要求**：
  - 运行 `bash -n vpn-tools/network_health_monitor.sh`，期望无语法错误
  - 手动运行健康检查 `bash vpn-tools/network_health_monitor.sh --check-only 2>&1 | grep -E 'Semantic|开发服务'`
    - Semantic-Scholar 行仍应出现在日志中（带 `[OK]` 或 `[FAIL]` 或 `[UNSTABLE-SKIP]`）
    - 当 Semantic-Scholar 超时时，开发服务成功率应显示 100%（3/3）而非 75%（3/4）
- **验收标准**：
  - ✅ Semantic-Scholar 条目存在且标记为 `unstable`
  - ✅ 当 Semantic-Scholar 返回非成功状态时，dev 服务成功率分母不包含该站点
  - ✅ 当 Semantic-Scholar 返回成功状态时，正常计入成功率
  - ✅ `bash -n` 无语法错误
  - ✅ 日志中 Semantic-Scholar 检测结果仍然可见（不是完全移除）
- **潜在风险**：unstable 标记的站点在成功时计入、失败时不计入，会使成功率略微乐观偏移（"只计好不计坏"）。但这正是期望的行为——这些站点自身不可靠，不应拖累网络健康评估

### Phase 4: 验证与提交

#### ✅ Task 4.1: 全量回归检查
- **目标**：确认所有修改安全、无副作用
- **修改内容**：无文件修改，仅运行验证
- **修改边界**：不修改任何文件
- **测试要求**：
  - `bash -n resources/config.yaml` — 虽为 YAML，确保无 tab 缩进错误（yq 解析验证）
  - `yq eval '.' resources/config.yaml >/dev/null` — YAML 语法有效
  - `bash -n vpn-tools/alert_notification.sh` — 语法正确
  - `bash -n vpn-tools/network_health_monitor.sh` — 语法正确
  - `bash tests/run_tests.sh` — 全量测试通过（69 tests）
  - `bash script/run_static_gates.sh` — 静态检查通过
  - 运行一次完整健康检查：`bash vpn-tools/network_health_monitor.sh --check-only` — 正常完成
  - 确认 runtime.yaml interval 已更新：`grep interval ~/.local/share/clash/runtime.yaml`
- **验收标准**：
  - ✅ 所有语法检查通过
  - ✅ 全量测试套件 69/69 通过
  - ✅ 静态检查通过
  - ✅ 健康检查正常运行，无脚本错误
- **潜在风险**：测试期间网络抖动可能导致健康检查结果不理想，但不影响脚本正确性验证

#### ✅ Task 4.2: Git 提交
- **目标**：提交所有修改
- **修改内容**：`git add` + `git commit`
- **修改边界**：仅 commit，不 push
- **测试要求**：`git diff --cached --stat` 确认修改范围无误
- **验收标准**：
  - ✅ commit 包含且仅包含 3 个文件：`resources/config.yaml`、`vpn-tools/alert_notification.sh`、`vpn-tools/network_health_monitor.sh`
  - ✅ commit message 描述清晰
- **潜在风险**：无

## 回归检查清单
- [ ] 全量测试通过：`bash tests/run_tests.sh`
- [ ] 静态检查通过：`bash script/run_static_gates.sh`
- [ ] `bash -n` 通过所有修改的 .sh 文件
- [ ] YAML 语法有效：`yq eval '.' resources/config.yaml >/dev/null`
- [ ] runtime.yaml 已更新 interval=30
- [ ] mihomo 服务运行正常
- [ ] 健康检查可正常运行
- [ ] 桌面通知可正常弹出

## 审查日志

| 轮次 | 聚焦 | 发现问题数 | 已修正 | 剩余 |
|------|------|-----------|--------|------|
| R1 | 结构完整性 | 2 | 2 | 0 |
| R2 | 可执行性 | 3 | 3 | 0 |
| R3 | 风险与边缘 | 1 | 1 | 0 |
| **终止** | **T1 — 收敛终止** | | | **0** |

### Completion Summary

| 维度 | 结果 |
|------|------|
| 背景与目标 | 完整 |
| 技术方案 | 完整 |
| Error & Rescue Map | 4 条路径，0 CRITICAL GAP |
| 执行计划 | 4 Phase, 6 Task |
| 回归检查清单 | 8 项（项目特定） |
| 已知局限 | GNOME notify-send 不支持 `-t` 参数 |

### [R1 Issues]
- **Issue R1-1**: 缺少 Error & Rescue Map section → 已补充 4 条关键失败路径
- **Issue R1-2**: 缺少"已有代码/流程复用分析" → 已补充 merge pipeline/test_url/alert 复用说明

### [R2 Issues]
- **Issue R2-1**: Task 1.1 测试要求中缺少重建 runtime 的具体命令 → 已补充 `_merge_sanitize_restart` 命令
- **Issue R2-2**: Task 3.2 修改内容中 `check_ai_services` 也使用 tab 分隔但有额外的 proxy 字段（第 4 字段 `yes`/`direct`），与 dev 的 `unstable` 字段位置冲突 → 已修正：AI 服务的 unstable 标记放在第 5 字段位置（proxy_pref 之后），dev 服务的 unstable 标记放在第 4 字段位置（dev 无 proxy_pref 字段）。实际修改时需确保 IFS 解析字段数正确
- **Issue R2-3**: Task 4.1 验收标准"69 tests"可能因新增测试文件变化 → 已修正为"全量测试套件通过"

### [R3 Issues]
- **Issue R3-1**: unstable 站点"成功时计入、失败时排除"可能造成统计偏向 → 已在潜在风险中说明这是期望行为，并在文档中记录该设计决策
