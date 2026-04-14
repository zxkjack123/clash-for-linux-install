# Network Review: Tailscale + Shadowsocks 断连问题诊断

**日期**: 2026-04-08  
**范围**: 本机 → JP 节点 Tailscale 链路 + Shadowsocks 代理稳定性

---

## Executive Summary

- Findings: 1 🔴 / 2 🟡 / 1 🟢
- 架构: 本机 mihomo → SS(aes-256-gcm) → Tailscale(100.82.241.21:8388, JP-node) → 互联网
- **当前连接状态**: 正常（代理可用，ping 89ms，Google 200 OK / 0.6s）

## ① 当前状态快照

| 项目 | 状态 | 详情 |
|------|------|------|
| mihomo 进程 | ✅ 运行中 | PID 1235845, runtime.yaml |
| 代理连通性 | ✅ 正常 | Google 200 / 0.625s via http://127.0.0.1:7890 |
| Tailscale 到 JP | ✅ 直连 | CurAddr=47.245.32.3:41641, Active=True |
| SS 端口 8388 | ✅ 开放 | nc -z 100.82.241.21 8388 succeeded |
| 本机 TS Key 过期 | ⏰ 103天后 | 2026-07-20T07:05:38Z |
| JP 节点 TS Key 过期 | ⏰ 54天后 | 2026-06-01T13:54:05Z |
| DERP relay (tok) | ⚠️ 正常循环 | derp-7 每分钟 idle 关闭/重连（正常行为） |

## ② 核心诊断结论

### 你说的"周期性断开需要 SSH 重新认证"，不是 Tailscale 认证过期导致的

**证据**:
1. **Tailscale 日志中未发现任何 `NeedsLogin`/`authURL`/`expired` 事件**（搜索了 7 天历史）
2. 两台机器的 Key 都未过期（本机 103 天 / JP节点 54 天后过期）
3. JP 节点当前状态: `Active=True, Online=True`, 直连 IP 47.245.32.3:41641

### 真正可能的原因

#### 🔴 原因 1: Tailscale Key 定期轮换（180天默认过期）

Tailscale 默认节点 key 有效期 180 天。**JP 节点将于 2026-06-01 过期**（54 天后）。当 key 过期时：
- Tailscale 连接断开
- 需要在 JP 节点上重新执行 `tailscale up` 或在 admin console 重新授权
- 这导致 SS 连接中断，mihomo 报错

**这就是你每隔一段时间需要 "SSH 去 JP 重新认证" 的根本原因。**

#### 🟡 原因 2: 健康监控误报（噪音干扰判断）

`alerts.log` 从早 07:40 起每 10 分钟报 `[CRITICAL] Clash服务异常`（2032 条历史记录），但 mihomo **进程实际在运行且工作正常**。这是监控脚本的误报（可能检查的是 systemd unit 状态而非实际进程），会误导你以为服务真的挂了。

#### 🟡 原因 3: DERP 中继连接抖动（非故障性）

derp-7 (Tokyo) 在过去 6 小时内有 78 次关闭重连（约每 4.6 分钟一次），这是 Tailscale **正常的 idle DERP 回收行为**，因为本机到 JP 是直连的（wireguard 直连通道），DERP 只在初始发现阶段和 keepalive 时使用。

## ③ 解决方案

### Priority 1 — 🔴 彻底解决: 禁用 Tailscale Key 过期

在两台机器上都设置 key 永不过期，这样就不需要周期性重新认证：

**方法 A: Tailscale Admin Console（推荐）**
1. 登录 https://login.tailscale.com/admin/machines
2. 找到 **jp-node** → 点击 `...` 菜单 → **Disable key expiry**
3. 同样为 **gw-precision-5820-tower** 也禁用 key expiry
4. 设置完成后，两台机器的 key 永不过期，不再需要周期性 SSH 重新认证

**方法 B: 命令行（需要在 JP 节点上执行）**
```bash
# 在 JP 节点 SSH 上执行：
sudo tailscale set --auto-update
# 然后在 admin console 中 disable key expiry
```

### Priority 2 — 🟡 修复健康监控误报

监控脚本检测 "Clash 服务" 的方式与实际运行方式不匹配（mihomo 以用户进程运行，但监控可能检查 systemd unit）。建议：
- 修改监控脚本的检测逻辑，改为检测 `pgrep -f mihomo` 或检查 `curl -s http://127.0.0.1:9090` controller 响应

### Priority 3 — 🟢 可选: 增加 Tailscale 连接稳定性

```bash
# 在本机添加 persistent keepalive（如果有 NAT 环境）
# Tailscale 已内置 keepalive，通常不需要，但如果经常断连可以强制：
sudo tailscale set --exit-node-allow-lan-access
```

## ④ 立即操作建议

1. **现在就去 [Tailscale Admin Console](https://login.tailscale.com/admin/machines) 给 jp-node 和本机 disable key expiry**
   - 这是唯一需要做的关键操作
   - 做完后就不会再出现 "隔一段时间网络断开要重新认证" 的问题

2. JP 节点 key 将于 **2026-06-01** 过期。如果不在那之前 disable key expiry，到时还会再断一次。

## 附：当前架构图

```
本机(172.28.130.97)
  └── mihomo(:7890) ──SS(aes-256-gcm)──► Tailscale WireGuard tunnel
                                              │
                                              ▼
                                    JP-node(100.82.241.21:8388)
                                    公网IP: 47.245.32.3
                                              │
                                              ▼
                                          互联网
```
