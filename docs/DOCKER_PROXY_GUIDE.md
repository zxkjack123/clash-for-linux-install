# Docker 容器使用 Clash/Mihomo 代理指南

本仓库默认更偏向**安全默认**：代理端口通常只监听在 `127.0.0.1`（避免把本机代理暴露到局域网）。

因此，Docker 容器要用代理时，首选 **Linux host networking**；只有在必须 bridge 模式时，才考虑显式暴露端口，并配合防火墙。

## 推荐（Linux）：host networking（无需开启 allow-lan）

原理：容器与宿主机共享网络栈，容器里访问 `127.0.0.1:7890` 就等于访问宿主机的代理端口。

### docker run

```bash
docker run --rm --network host \
  -e HTTP_PROXY=http://127.0.0.1:7890 \
  -e HTTPS_PROXY=http://127.0.0.1:7890 \
  -e NO_PROXY=localhost,127.0.0.1 \
  curlimages/curl:latest curl -fsS https://api.github.com
```

### docker compose（仅 Linux）

```yaml
version: '3.8'
services:
  your-service:
    image: your-image
    network_mode: host
    environment:
      HTTP_PROXY: http://127.0.0.1:7890
      HTTPS_PROXY: http://127.0.0.1:7890
      NO_PROXY: localhost,127.0.0.1
```

## 可选：bridge 模式（需要显式暴露端口，风险更高）

bridge 模式下，容器无法直接访问宿主机的 `127.0.0.1`。你通常需要：

1) 让 Clash/Mihomo 的 proxy 端口监听在可被容器访问的地址（例如 `0.0.0.0` 或宿主机局域网 IP）；
2) 用防火墙限制只允许 Docker 网段访问 `7890`。

> ⚠️ 不建议把 `7890` 直接暴露给整个局域网。

### docker run（bridge + host.docker.internal）

```bash
docker run --rm \
  --add-host=host.docker.internal:host-gateway \
  -e HTTP_PROXY=http://host.docker.internal:7890 \
  -e HTTPS_PROXY=http://host.docker.internal:7890 \
  -e NO_PROXY=localhost,127.0.0.1 \
  curlimages/curl:latest curl -fsS https://api.github.com
```

### 防火墙建议（示例）

```bash
# 仅允许 Docker 私网访问 7890（网段请按实际 Docker network 调整）
sudo iptables -I DOCKER-USER -s 172.16.0.0/12 -p tcp --dport 7890 -j ACCEPT
sudo iptables -I DOCKER-USER -p tcp --dport 7890 -j DROP
```

## 验证

在宿主机检查端口监听（显示 `127.0.0.1:7890` 或 `*:7890` 都可能是正常，取决于你的配置/模式）：

```bash
ss -tlnp | grep ':7890'
```

容器侧验证：

- host networking：`--network host` 后直接用 `127.0.0.1:7890`。
- bridge：用 `host.docker.internal:7890` 或 `<HOST_IP>:7890`（仅在端口确实对外监听时）。

## 恢复安全默认（建议）

如你之前为了 bridge 模式临时放开了监听，建议事后恢复为仅本机：

- `allow-lan: false`
- `bind-address: "127.0.0.1"`

然后重新合并/重启生效（安装后推荐使用 `clashctl`）：

> `clashctl mixin -e` 会打开 mixin 配置并在保存后自动合并 + 重启。

## 相关工具

- `vpn-tools/test_docker_proxy.sh`：Docker 代理完整测试（支持 controller `secret`）
- `vpn-tools/docker_proxy_demo.sh`：Docker 代理演示
- `vpn-tools/quick_vpn_check.sh`：VPN/代理快速检查

---
更新日期: 2026-01-19
