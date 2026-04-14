# Repository Review: network-monitoring

## Executive Summary

- Findings: 3 🔴 / 5 🟡 / 3 🟢
- Review Scope: `vpn-tools/network_health_monitor.sh`, `vpn-tools/alert_notification.sh`, cron 配置, 健康评分模型
- Data Basis: 922 次历史评分记录 (2026-03-26 ~ 2026-04-14)
- Overall Health: 核心监控逻辑可用，但评分模型存在系统性偏低（延迟全丢 30 分）、cron 任务重叠、以及两处除零风险

---

## ① Repository Overview

网络监控子系统由以下组件构成：
- `network_health_monitor.sh` — 主监控脚本，检测 AI/Dev/Streaming/Domestic 四类服务
- `alert_notification.sh` — 多通道告警（桌面/Webhook/邮件/日志），含 300s 频率限制
- cron — `*/10 --auto-fix` + `0 * * * * --check-only` + 日志清理
- 评分模型 — 成功率 70% + 延迟 30%（二值阈值）

---

## ② Incomplete Tasks

| ID | Type | Location | Description |
|----|------|----------|-------------|
| T1 | technical_debt | `check_streaming_services()` L256 | 除零防护缺失（ai/dev 已修复，streaming/domestic 未同步） |
| T2 | technical_debt | `check_ai_services()` L180 | unstable-skip 时仍将 latency 累加至 `total_latency`，平均延迟被膨胀 |
| T3 | planned_work | cron | `0 * * * * --check-only` 与 `*/10 --auto-fix` 在整点重叠（证据：:00 分钟有 260 次检查，其余约 130 次） |

---

## ③ Code Quality Issues

| ID | Severity | Location | Category | Description | Remediation |
|----|----------|----------|----------|-------------|-------------|
| Q1 | 🔴 Critical | `check_streaming_services()` L270–L271 | Division by zero | `$((total_latency / total))` 和 `$((success * 100 / total))` 未做 `total > 0` 防护。如果所有 streaming 端点均标记 unstable 或列表为空则会崩溃 | 同 `check_ai_services()` 模式添加 `$(( total > 0 ? ... : 0 ))` |
| Q2 | 🔴 Critical | `check_domestic_sites()` L296–L297 | Division by zero | 同 Q1，domestic 函数也无防护 | 同上 |
| Q3 | 🔴 Critical | `calculate_health_score()` L307–L311 | Scoring cliff | 延迟分使用二值阈值（<500ms → 满分，≥500ms → 0），无渐变。实证：所有端点 100% 成功但延迟均 800ms 时，得分仅 69/D。用户实际观测到常态分数在 57–64 区间，主因是海外延迟经常 >500ms | 改用分段线性或 sigmoid 映射（如 <300ms=满分, 300-800ms 线性衰减, >800ms=0） |
| Q4 | 🟡 Warning | `check_ai_services()` L180 | Latency inflation | unstable 站点检测失败时（超时 10s），其延迟仍累加到 `total_latency` 但 `total` 不递增。若超时 10000ms，导致 `avg_latency` 被显著拉高 | skip 时同时跳过 `total_latency` 累加 |
| Q5 | 🟡 Warning | `check_ai_services()` L165 | Routing mismatch | SCNET (`api.scnet.cn`) 使用 `proxy=yes` 但该服务是国内 API。经实测 direct 返回 200（<100ms），proxy 返回 200 但多绕一跳。增加不必要的延迟并消耗代理额度 | 改为 `direct` |
| Q6 | 🟡 Warning | cron | Overlap | `*/10 --auto-fix` 在 :00 触发，`0 * * * * --check-only` 也在 :00 触发。同一分钟执行两个实例产生重复日志、重复告警、竞态修改 `health_metrics.json` | 删除 `0 * * * * --check-only` 行，或改为 `5 * * * *` 避开 |
| Q7 | 🟡 Warning | cron | Duplicate cleanup | `find ... -mtime +30 -delete` 出现两次（但 crontab 输出仅显示一次——以实际 `crontab -l` 为准） | 确认并去重 |

---

## ④ Potential Bugs

| ID | Severity | Location | Category | Description | Remediation |
|----|----------|----------|----------|-------------|-------------|
| B1 | 🔴 (ref Q1/Q2) | L270, L296 | Division by zero | 如果未来 streaming/domestic 列表动态配置且变为空列表，`total=0` 触发 bash 算术错误导致 `set -e` 终止进程 | 防护三元表达式 |
| B2 | 🟡 Warning | `perform_health_check()` L410 | Concurrent write | 两个 cron 实例同时写 `health_metrics.json`，可能导致 JSON 截断 | 使用临时文件 + `mv` 原子写入（已有 `cat >` 非原子） |
| B3 | 🟡 Warning | `check_ai_services()` L157 | HTTP pattern | Copilot 使用 `^(20[0-9]|40[0-9])$` 匹配 404 作为"存活"信号。这在 Copilot API 正常时可行，但若端点真正不可达（如 DNS 劫持返回 404），会误判为成功 | 考虑改用更精确的模式 `^(200|404)$` 或直接用 `copilot-proxy.githubusercontent.com/v1/engines` |

---

## ⑤ Optimization Opportunities

| ID | Impact | Location | Category | Description | Remediation |
|----|--------|----------|----------|-------------|-------------|
| O1 | 🟢 Enhancement | `calculate_health_score()` | Accuracy | 将延迟评分从二值改为连续函数。建议对海外:<br>- <300ms → 100%<br>- 300-1000ms → 线性衰减<br>- >1000ms → 0<br>对国内:<br>- <150ms → 100%<br>- 150-500ms → 线性衰减<br>- >500ms → 0 | 大幅减少「全部成功但得分仅 69」的反直觉场景。历史数据显示 387/922 次得分 99，但一旦延迟偏高就断崖跌到 60-80 |
| O2 | 🟢 Enhancement | `check_ai_services()` | Efficiency | SCNET 改为 `direct` 可节省 ~200-500ms 延迟，同时减少代理流量 | 将 SCNET 条目的 `proxy_pref` 从 `yes` 改为 `direct` |
| O3 | 🟢 Enhancement | 日志管理 | Maintenance | `health_history.log` 已达 2.0MB/38K 行（19 天），`monitor_cron.log` 类似。`find -mtime +30 -delete` 只删整文件不轮转。建议按天轮转或使用 logrotate | 添加 `logrotate.d` 配置或在 cron 清理中改用 `truncate` + 归档策略 |

---

## Remediation Roadmap

### Priority 1 — 🔴 Critical

1. **Q1 + Q2**: `check_streaming_services()` 和 `check_domestic_sites()` 的除零防护。与 `check_ai_services()` / `check_dev_services()` 保持一致，添加三元表达式。预计改动 4 行。
2. **Q3 + O1**: 评分模型从二值阈值改为分段线性。这是常态分数偏低（57-69 区间频繁出现）的根本原因。改动集中在 `calculate_health_score()` 函数。

### Priority 2 — 🟡 Warning

3. **Q4**: unstable-skip 时同时跳过 `total_latency` 累加（`check_ai_services()` + `check_dev_services()` 两处）。
4. **Q5 + O2**: SCNET 改为 direct 路由。
5. **Q6**: 删除或错开 `0 * * * * --check-only` cron 条目，消除整点重叠。
6. **B2**: `health_metrics.json` 写入改用临时文件 + `mv` 原子操作。

### Priority 3 — 🟢 Enhancement

7. **O3**: 日志轮转策略（logrotate 或脚本内 truncate + archive）。
8. **B3**: Copilot 端点匹配模式收紧。

---

## Next Steps

- Priority 1/2 项可直接实施，6 项改动均为局部修改（不超过 20 行/项）。
- 评分模型改造（Q3+O1）建议先用历史数据回测新公式，确认分布合理后再上线。可用 `health_history.log` 中的原始 `ai_latency`/`dev_latency` 等数据回放。

---

## Pre-Delivery Audit (Level: L1-Lite)

| § | Check | Status | Note |
|---|-------|--------|------|
| 1 | Quantitative claims accuracy | ✅ PASS | 922 次记录数、:00 分钟 260 次 vs ~130 次、score=69 for all-100%-rate-800ms-latency 均经工具验证 |

Auditor: Repo Reviewer | Date: 2026-04-14
