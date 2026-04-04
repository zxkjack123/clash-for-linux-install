# Network & JP-Tailscale Connectivity Review

**Date**: 2026-04-03  
**Scope**: Local network, Tailscale mesh, Mihomo proxy chain via JP-Tailscale

---

## Executive Summary

| Metric | Value | Assessment |
|--------|-------|------------|
| Local network | 172.28.130.97/18 via eno1 | 🟢 正常 |
| DNS | systemd-resolved stub | 🟢 正常 |
| Tailscale → jp-node | **直连** 47.245.32.3:41641 (非 relay) | 🟢 已建立 |
| ICMP 延迟 (20 packets) | avg 97.5ms, max 187.1ms, **StDev 21.7ms** | 🟡 抖动偏高 |
| NAT 类型 | **Symmetric NAT** (MappingVariesByDestIP=true) | 🟡 连接受限 |
| 代理链响应 (Google ×10) | 792–1252ms, 全部成功 | 🟡 勉强可用 |
| 下载带宽 (via jp-node) | ~2.8 MB/s (5MB 文件) | 🟡 中等 |
| GitHub API via proxy | 590ms | 🟢 可接受 |
| Mihomo 运行 | PID 2048931, 自 Mar31 运行 | 🟢 稳定 |

**整体评估**：链路已通但质量中偏下。核心问题在于 **单点依赖 + 双层代理叠加开销 + Symmetric NAT 限制**。

---

## ① 网络拓扑现状

```
[本机 172.28.130.97] 
  ├── eno1 → 校园网/局域网 (gateway 172.28.191.254)
  ├── tailscale0 → 100.94.75.11 (WireGuard mesh)
  └── Mihomo (127.0.0.1:7890)
         └── JP-Tailscale (type: http, server: 100.82.241.21:8888)
               └── jp-node (Tinyproxy on Tailscale)
                     └── 日本出口 (47.245.32.3, 阿里云日本)
```

流量路径：`App → Mihomo → Tailscale WG tunnel → jp-node Tinyproxy → 目标网站`

---

## ② 稳定性诊断

### 延迟抖动分析

| 指标 | 值 |
|------|-----|
| ICMP min | 91.1ms |
| ICMP avg | 97.5ms |
| ICMP max | **187.1ms** |
| ICMP StDev | **21.7ms** |
| Worst/Best 比 | 2.05x |

- 最大延迟比平均高近一倍，与 Tailscale 的 WireGuard 隧道偶发重传有关。
- 基础延迟 ~91ms 对中国→日本的路径是合理的，但 **jitter 21ms** 对实时场景（Copilot streaming）会造成可感知的卡顿。

### NAT 限制

- **Symmetric NAT** 使得 Tailscale **无法** 对所有 peer 建立直连（direct path）。
- 当前 jp-node 虽显示有 `CurAddr`（直连 IP），但 `Addrs: null` 说明本机对外暴露的端点穿透能力受限。
- 一旦直连失败会 fallback 到 **DERP relay (tok)**，延迟会从 91ms 跳到 228ms+。

### 单点风险

- PROXY group 仅有 `JP-Tailscale` 和 `DIRECT` 两个选项，无备用节点。
- VSCODE group 配置为 Fallback 但只有 JP-Tailscale 一个代理，实际无 fallback 效果。
- jp-node 宕机或链路中断时，所有代理流量**无自动切换**。

---

## ③ 问题汇总

| ID | Severity | Category | Description |
|----|----------|----------|-------------|
| N1 | 🟡 Warning | 稳定性 | Symmetric NAT 导致 Tailscale 直连不可靠，可能随时降级到 DERP relay（228ms） |
| N2 | 🟡 Warning | 单点故障 | 只有一个 jp-node 代理节点，无冗余 |
| N3 | 🟡 Warning | 延迟叠加 | 双层代理（Tailscale WG + Tinyproxy HTTP）引入额外开销，Google 响应 ~1s |
| N4 | 🟢 Info | UDP | JP-Tailscale 配置为 HTTP 代理 (type: http)，不支持 UDP，DNS 和 QUIC 无法走该链路 |
| N5 | 🟢 Info | 带宽 | 下载速度 ~2.8 MB/s，对 Copilot/Dev 工作流够用，但大文件传输偏慢 |

---

## ④ 优化建议（按优先级排序）

### Priority 1 — 🟡 解决单点故障与稳定性

#### 方案 A：增加机场/商业代理节点（推荐）

**收益**：多节点负载均衡 + 自动故障转移，最直接有效。

```yaml
# 在 Mihomo config 中添加订阅或手动节点
proxies:
  - name: "JP-Tailscale"
    type: http
    server: 100.82.241.21
    port: 8888
  - name: "JP-Commercial-1"   # 商业机场节点
    type: ss/vmess/trojan
    server: ...
    ...

proxy-groups:
  - name: "PROXY"
    type: url-test            # 自动选择延迟最低的
    proxies:
      - "JP-Tailscale"
      - "JP-Commercial-1"
    url: "https://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50
```

- `url-test` 会自动切换到延迟最低的节点。
- 即使 jp-node 挂了，也会自动 fallback 到商业节点。

#### 方案 B：在 jp-node 上运行 SOCKS5/Shadowsocks 替代 Tinyproxy

**收益**：减少一层 HTTP 代理开销，支持 UDP。

```yaml
# jp-node 上部署 shadowsocks-rust 或 xray
proxies:
  - name: "JP-Tailscale-SS"
    type: ss
    server: 100.82.241.21
    port: 18388
    cipher: aes-256-gcm
    password: "<your-password>"
    udp: true
```

- 相比 HTTP proxy，SS/SOCKS5 协议开销更小。
- `udp: true` 可以支持 DNS over proxy 和 QUIC。

#### 方案 C：启用 Tailscale Exit Node 直接出口

**收益**：消除 Tinyproxy 层，流量直接通过 WireGuard 出日本。

```bash
# 在本机启用 jp-node 作为 exit node
tailscale set --exit-node=jp-node
```

- jp-node 已配置 `ExitNodeOption: true`，可以直接用。
- **但缺点是全量流量走日本**（包括国内网站），需配合 `--exit-node-allow-lan-access` 和 Tailscale ACL 或 split routing。
- 适合短期使用或特定场景。

### Priority 2 — 🟡 改善 NAT 穿透

#### 方案 D：在路由器/防火墙上配置 UPnP 或固定端口映射

```bash
# 检查当前是否有 UPnP
tailscale netcheck  # PortMapping: (空) 说明未启用
```

- 如果网络环境允许，在路由器上映射 UDP 端口给 Tailscale（默认 41641）。
- 可以将 NAT 从 Symmetric 降级为 Full Cone，大幅改善直连成功率。

#### 方案 E：在本机或 jp-node 配置 DERP 自建节点

- 如果有香港/国内云服务器，自建 DERP relay 可以将 relay 延迟从 228ms (tok) 降到更低。
- Tailscale 自定义 DERP：https://tailscale.com/kb/1118/custom-derp-servers

### Priority 3 — 🟢 优化 Mihomo 配置

#### 方案 F：优化 VSCODE/Fallback group

```yaml
# 当前配置（实际无冗余效果）
- name: "VSCODE"
  type: fallback
  proxies:
    - "JP-Tailscale"

# 建议改为（如果有多节点）
- name: "VSCODE"
  type: fallback
  proxies:
    - "JP-Tailscale"
    - "JP-Commercial-1"     # 备用
    - "DIRECT"              # 最后 fallback
  url: "https://update.code.visualstudio.com/api/update/linux-x64/stable/latest"
  interval: 300
```

#### 方案 G：启用 Mihomo 的 TCP 并发和连接优化

```yaml
# 在 mixin 或 config 中
tcp-concurrent: true        # TCP 并发连接，提高首包速度
keep-alive-interval: 30     # 保持连接活跃
```

---

## ⑤ 推荐实施路径

| 阶段 | 动作 | 预期效果 |
|------|------|----------|
| **立即** | 方案 G：启用 `tcp-concurrent` | 小幅改善首包延迟 |
| **短期** | 方案 B：jp-node → SS/SOCKS5 替代 Tinyproxy | 减少协议开销，支持 UDP |
| **中期** | 方案 A：增加商业节点 + url-test 组 | 解决单点故障，自动切换 |
| **可选** | 方案 D：改善 NAT 穿透 | 降低 Tailscale 抖动 |

---

## Next Steps

- 就方案 A/B/C 选择方向后，可切换到实施模式进行具体配置修改。
- 若选择增加商业节点，需提供订阅链接或节点信息。
- 若选择升级 jp-node 代理协议，需要 SSH 到 jp-node 操作。
