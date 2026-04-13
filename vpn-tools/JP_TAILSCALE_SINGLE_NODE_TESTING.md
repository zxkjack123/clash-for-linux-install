# JP‑Tailscale 单节点专项测试

这个脚本用于把 **JP‑Tailscale** 当作“主出口”时，快速回答几个关键问题：

1. **是否走 DERP**（而不是直连）——这直接决定抖动/吞吐上限。
2. 在 **mihomo 代理链路**下的：
   - 延迟分布（p50/p95）
   - 吞吐（B/s）
   - 并发稳定性（成功率 + p50/p95）
3. 给出**mihomo / 系统参数建议**。
4. 可选：把 `PROXY` 分组收敛为「JP‑Tailscale 优先 + 可控兜底」。

> 安全：脚本不会打印 mihomo 的 `secret`，也会对 URL 中可能包含的 token 进行脱敏。

---

## 使用方法

在仓库根目录执行：

```bash
cd vpn-tools
bash jp_tailscale_single_node_test.sh --quick
bash jp_tailscale_single_node_test.sh --full --concurrency 30
```

### 只测试、不切换分组

默认会通过 Mihomo API 临时把 `PROXY` 切到 `JP-Tailscale`，结束后恢复。

如果你不希望它影响当前路由：

```bash
bash jp_tailscale_single_node_test.sh --no-switch
```

### 指定分组/节点/对端

```bash
# 切换 Development 分组到 JP-Tailscale 再测试
bash jp_tailscale_single_node_test.sh --group Development --proxy-name JP-Tailscale

# tailscale ping 目标改成其它 peer（支持 IP / MagicDNS 名称）
bash jp_tailscale_single_node_test.sh --ts-peer 100.82.241.21
```

---

## 如何解读输出

### 1) TAILSCALE HEALTH

- `tailscale netcheck`：关注 `UDP: true/false`、DERP 延迟。
- `tailscale ping`：输出里如果出现 `via DERP`，说明这段链路可能被 NAT/防火墙限制，直连不稳定。

### 2) PROXY LATENCY

会对若干公共 endpoint 做 N 次采样并给出 p50/p95。

经验阈值（仅供参考）：
- p95 < 3s：整体可用
- p95 > 5s：建议保留兜底节点，排查 DERP/丢包/拥塞

### 3) PROXY THROUGHPUT

会尝试多个下载源，选到可用的一个，给出 `speed_download`。

### 4) PROXY CONCURRENCY

会以 `--concurrency N` 并发访问一个轻量 endpoint，给出成功率和 time_total 的 p50/p95。

---

## 一键“收敛”分组（已弃用）

> **注意**: `--apply-tighten` 已弃用，因为旧的 `AUTO-SMART` 分组已不存在。当前配置使用 `AUTO` (url-test) + `PROXY` (select) 分组，无需手动收敛。

- `minimal`：仅 `JP-Tailscale + 故障转移`
- `balanced`：`JP-Tailscale` 优先 + 少量地域兜底

命令：

```bash
bash jp_tailscale_single_node_test.sh --apply-tighten --fallback balanced
# 或
bash jp_tailscale_single_node_test.sh --apply-tighten --fallback minimal
```

该操作会：
1. 备份 `~/.local/share/clash/mixin.yaml`
2. 修改相关分组，避免循环引用
3. 调用仓库内的合并+清洗逻辑重建 `runtime.yaml` 并重启 mihomo

---

## 常见问题

### 1) 为什么会出现“DERP”？

通常是当前网络（校园网/酒店 Wi‑Fi/公司网络）阻断/劣化了 UDP 或 NAT 打洞。
解决思路：
- 确保允许出站 UDP（常见是 UDP 41641）
- 检查本机防火墙（ufw/firewalld）
- 换网络验证（手机热点 vs 校园网）

### 2) 为什么吞吐测试选的下载源会变化？

脚本会尝试多个 URL，选第一个能成功下载且下载量足够的目标，避免因为单一站点被墙/限速导致误判。
