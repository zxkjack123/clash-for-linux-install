# Docker容器使用Clash代理指南

## 配置摘要

✅ **Clash代理已配置为允许LAN访问**
- 监听地址: `0.0.0.0:7890` (所有网络接口)
- 宿主机IP: `$(hostname -I | awk '{print $1}')`
- 配置文件已更新:
  - `/home/gw/.local/share/clash/runtime.yaml` (运行时配置)
  - `/home/gw/opt/clash-for-linux-install/resources/config.yaml` (源配置)

## 使用方法

### 方法1: 使用环境变量 (推荐)

```bash
HOST_IP=$(hostname -I | awk '{print $1}')

# HTTP代理
docker run --rm \
  -e HTTP_PROXY=http://${HOST_IP}:7890 \
  -e HTTPS_PROXY=http://${HOST_IP}:7890 \
  your-image

# 完整示例
docker run --rm \
  -e HTTP_PROXY=http://${HOST_IP}:7890 \
  -e HTTPS_PROXY=http://${HOST_IP}:7890 \
  -e NO_PROXY=localhost,127.0.0.1 \
  curlimages/curl curl https://api.github.com
```

### 方法2: 使用host.docker.internal

```bash
docker run --rm \
  --add-host=host.docker.internal:host-gateway \
  -e HTTP_PROXY=http://host.docker.internal:7890 \
  -e HTTPS_PROXY=http://host.docker.internal:7890 \
  your-image
```

### 方法3: Docker Compose配置

```yaml
version: '3.8'
services:
  your-service:
    image: your-image
    environment:
      HTTP_PROXY: http://172.28.130.97:7890
      HTTPS_PROXY: http://172.28.130.97:7890
      NO_PROXY: localhost,127.0.0.1
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

### 方法4: 构建时使用代理

```bash
docker build \
  --build-arg HTTP_PROXY=http://${HOST_IP}:7890 \
  --build-arg HTTPS_PROXY=http://${HOST_IP}:7890 \
  -t your-image .
```

## 测试代理连接

```bash
# 快速测试
HOST_IP=$(hostname -I | awk '{print $1}')
docker run --rm \
  -e HTTP_PROXY=http://${HOST_IP}:7890 \
  curlimages/curl curl -s http://httpbin.org/ip

# 使用测试脚本
cd /home/gw/opt/clash-for-linux-install/vpn-tools
bash test_docker_proxy.sh
```

## 验证配置

```bash
# 检查Clash监听端口
ss -tlnp | grep 7890
# 应该显示: *:7890 (而不是 127.0.0.1:7890)

# 检查allow-lan配置
grep "allow-lan" /home/gw/.local/share/clash/runtime.yaml
# 应该显示: allow-lan: true
```

## 常见问题

### Q: 容器无法访问代理?
A: 确认以下几点:
1. Clash服务正在运行: `ps aux | grep mihomo`
2. 端口监听在所有接口: `ss -tlnp | grep 7890` 应显示 `*:7890`
3. 防火墙没有阻止7890端口
4. 使用正确的宿主机IP地址

### Q: 某些容器需要直连?
A: 使用NO_PROXY环境变量排除某些域名:
```bash
-e NO_PROXY=localhost,127.0.0.1,.local,.internal,openxlab.org.cn
```

### Q: 需要恢复只监听本地?
A: 修改配置并重启:
```bash
sed -i 's/^allow-lan: true/allow-lan: false/' /home/gw/.local/share/clash/runtime.yaml
kill -HUP $(pgrep mihomo)
```

## 安全建议

⚠️ **重要**: 启用LAN访问后，局域网内其他设备也可以使用此代理。如果这不是你想要的:

1. 使用防火墙限制访问:
```bash
# 只允许Docker网桥访问
sudo iptables -A INPUT -p tcp --dport 7890 -s 172.17.0.0/16 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 7890 -j DROP
```

2. 或使用bind-address限制监听接口:
在config.yaml中添加:
```yaml
bind-address: "172.17.0.1"  # Docker网桥IP
```

## 相关工具

- `test_docker_proxy.sh` - 完整的Docker代理测试套件
- `docker_proxy_demo.sh` - Docker代理使用演示
- `quick_vpn_check.sh` - VPN和代理快速检查

---
更新日期: 2025-11-18
