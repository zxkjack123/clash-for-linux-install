# Network Stability Review: JP-Node 30-Minute Continuous Monitoring

## Executive Summary
- Findings: 0 🔴 / 1 🟡 / 0 🟢
- Monitoring Window: 2026-04-04 09:10 – 09:45 CST (35 minutes)
- Link: Workstation → Tailscale WireGuard → jp-node (100.82.241.21) → Shadowsocks → Internet
- **Overall Health: STABLE — 单节点足够满足当前使用需求，备用机场节点为可选冗余**

## ① ICMP Layer (WireGuard Tunnel)

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Samples | 204 | — | — |
| Packet loss | 0 / 204 (0.0%) | < 1% | ✅ |
| Latency min / mean / max | 90.8 / 91.3 / 93.5 ms | — | ✅ |
| Latency p50 / p95 / p99 | 91.2 / 91.6 / 92.2 ms | p95 < 150ms | ✅ |
| Latency stdev | 0.26 ms | < 10ms | ✅ |
| Avg jitter | 0.22 ms | < 5ms | ✅ |
| Max jitter | 2.3 ms | < 20ms | ✅ |
| Max consecutive loss streak | 0 | < 3 | ✅ |
| Outliers (> 3σ = 92.1ms) | 3 (max 93.5ms) | — | 可忽略 |

**评价**: WireGuard 隧道**极度稳定**。延迟标准差仅 0.26ms，抖动 0.22ms，在跨境链路中属于优异水平。零丢包。

## ② Proxy Layer (Shadowsocks → Internet)

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Proxy samples | 34 | — | — |
| Google success rate | 34/34 (100%) | > 95% | ✅ |
| GitHub success rate | 34/34 (100%) | > 95% | ✅ |
| Node alive failures | 0/34 | 0 | ✅ |

### Latency Breakdown

| Target | min | mean | p50 | p95 | max | stdev | CV |
|--------|-----|------|-----|-----|-----|-------|----|
| Google | 586 | 669 | 628 | 934 | 1791 | 208 | 31% |
| GitHub API | 300 | 346 | 310 | 492 | 494 | 74 | 21% |
| Delay API (node) | 282 | 290 | 289 | 297 | 319 | 6.2 | 2.1% |

### Google Latency Distribution

| Bucket | Count | Percentage |
|--------|-------|------------|
| 500–600ms | 7 | 21% |
| 600–700ms | 24 | 71% |
| 700–800ms | 1 | 3% |
| 800–1000ms | 1 | 3% |
| > 1000ms | 1 | 3% |

### Outlier Analysis

仅 2 次 Google 延迟 > 800ms：
- `09:16:15` — 934ms
- `09:41:03` — 1791ms（单次尖峰）

剔除 >1s 的 1 个异常值后：mean=635ms, stdev=64ms, **CV=10%**（健康范围内）。

1791ms 尖峰极可能是 Google 服务端或中间网络的单次 TCP 重传，而非链路问题。Delay API 的 stdev 仅 6.2ms 证明 Tailscale+SS 链路本身极为稳定。

### Trend (前半段 vs 后半段)

| Half | Google mean |
|------|-------------|
| 前 17 样本 | 641ms |
| 后 17 样本 | 696ms |

后半段略高，但差异在正常波动范围内（可能与 Google CDN 节点轮换有关）。

## ③ Stability Verdict

### 量化评分

| 维度 | 权重 | 得分 (0-10) | 加权 |
|------|------|-------------|------|
| 隧道可用性 (丢包率) | 30% | 10 | 3.0 |
| 隧道稳定性 (抖动/stdev) | 20% | 10 | 2.0 |
| 代理可用性 (成功率) | 25% | 10 | 2.5 |
| 代理延迟 (p50) | 15% | 7 | 1.05 |
| 代理一致性 (CV) | 10% | 8 | 0.8 |
| **总分** | **100%** | — | **9.35 / 10** |

### 结论

**STABLE — 当前 JP-Tailscale + Shadowsocks 单节点链路质量优良，无需为稳定性原因构建备用机场节点。**

核心依据：
1. **零丢包**：35 分钟 204 次 ICMP 探测全部成功
2. **极低抖动**：0.22ms 平均抖动，跨境链路中属顶尖水平
3. **100% 代理成功率**：34/34 Google + GitHub 请求全部成功
4. **隧道本身 CV 仅 2.1%**：Delay API 证明 Tailscale→SS 路径本身非常稳定
5. **Google 延迟波动来自目标侧**：剔除 1 个 Google 服务端尖峰后 CV 降至 10%

## ④ 是否需要备用机场节点？

### 不需要的理由（当前场景）

- 链路稳定性远超一般商业机场节点（商业机场的共享带宽通常有更高的延迟波动）
- Tailscale WireGuard 提供端到端加密 + 自动路由优化
- 自建 SS 无流量限制、无审计、无共享拥塞

### 但可以考虑的场景（可选冗余）

| 场景 | 是否需要备用 | 建议方案 |
|------|-------------|---------|
| jp-node 宕机/维护 | 🟡 可选 | Mihomo fallback 配置 + 健康检查自动切换 |
| 阿里云日本区域性网络中断 | 🟡 可选 | 不同区域/不同云商的第二节点 |
| 需要多地区 IP 出口 | 🟡 按需 | 商业机场提供多节点选择 |
| 当前使用（Copilot/GitHub/Google） | ✅ 不需要 | 现有链路已满足 |

### 建议

如果希望增加冗余以防 jp-node 整机故障（概率低但影响大），最简方案是：
1. 在 Mihomo config 中配置 `url-test` 或 `fallback` 代理组
2. 将 JP-Tailscale 设为首选，备用节点（免费/低成本机场试用节点）作为 fallback
3. 设置 `interval: 300` + `tolerance: 100` 实现自动故障转移

**无需为了"稳定性"而加节点，仅需考虑"可用性冗余"。**

## ⑤ Migration Performance Comparison (Before → After SS)

| Metric | Before (Tinyproxy) | After (Shadowsocks) | Change |
|--------|--------------------|--------------------|--------|
| ICMP jitter | 21.7ms | 0.22ms | ↓99% |
| Google avg | 985ms | 669ms (635ms*) | ↓32-36% |
| GitHub API | 590ms | 346ms | ↓41% |
| Delay API | 804ms | 290ms | ↓64% |
| Google success | 7/10 (70%) | 34/34 (100%) | ↑30pp |

*剔除单次 Google 端尖峰后

---

**Report generated**: 2026-04-04 09:47 CST  
**Data sources**: `tmp/_monitor_icmp_20260404_091003.tsv`, `tmp/_monitor_proxy_20260404_091003.tsv`  
**Duration**: 35 minutes continuous monitoring (204 ICMP samples @ 10s, 34 proxy samples @ 60s)
