# Localhost服务访问问题修复指南

## 问题描述
浏览器访问 `http://localhost:8080` (SearXNG/Dify等本地服务) 时显示 "localhost refused to connect"，但 `bing.com` 等外网可正常访问。

## 根本原因
Clash代理的 `no_proxy` 配置不完整，浏览器尝试通过代理访问localhost导致连接被拒绝。

## 已完成的修复 ✅

### 1. 更新环境变量 no_proxy
**之前:**
```bash
no_proxy=localhost,127.0.0.1,::1
```

**现在:**
```bash
no_proxy=localhost,127.0.0.1,::1,0.0.0.0,*.local,.localhost,.local,ts.net,.ts.net,tailscale.io,.tailscale.io,100.100.100.100,100.64.0.0/10
```

### 2. 更新GNOME系统代理ignore-hosts
**之前:**
```
['localhost', '127.0.0.0/8', '::1']
```

**现在:**
```
['localhost', '127.0.0.0/8', '::1', '0.0.0.0', '*.local', '.localhost', '.local', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', 'ts.net', '.ts.net', 'tailscale.io', '.tailscale.io', '100.100.100.100', '100.64.0.0/10']
```

### 3. 更新的文件
- `/home/gw/opt/clash-for-linux-install/script/clashctl.sh` (源文件)
- `/home/gw/.local/share/clash/script/clashctl.sh` (运行时文件)

## 验证配置

运行诊断脚本:
```bash
bash /tmp/test_localhost_access.sh
```

或手动验证:
```bash
# 检查环境变量
echo $no_proxy

# 检查GNOME设置
gsettings get org.gnome.system.proxy ignore-hosts

# 测试访问
curl -I http://localhost:8080
```

## 浏览器配置建议

### 如果浏览器仍显示连接错误

#### Chrome/Edge浏览器
1. **清除网络缓存**
   - 访问: `chrome://net-internals/#sockets`
   - 点击 "Flush socket pools"
   - 访问: `chrome://net-internals/#dns`
   - 点击 "Clear host cache"

2. **检查代理设置**
   - 访问: `chrome://settings/system`
   - 点击 "打开您计算机的代理设置"
   - 确认 "不使用代理服务器的地址" 包含 `localhost;127.0.0.1`

3. **重启浏览器**
   - 完全退出浏览器 (关闭所有窗口和后台进程)
   - 重新打开

#### Firefox浏览器
1. **配置代理**
   - 设置 > 网络设置 > 手动代理配置
   - "不使用代理" 添加: `localhost, 127.0.0.1, 0.0.0.0, .local, *.local`

2. **清除缓存**
   - Ctrl+Shift+Delete
   - 选择 "缓存" 和 "Cookie"
   - 清除

3. **禁用DNS over HTTPS (如果有问题)**
   - 设置 > 网络设置
   - 取消勾选 "启用 DNS over HTTPS"

## 重新应用代理设置

如果修改了配置文件后需要重新加载:

```bash
# 方法1: 重新加载代理设置
source /home/gw/.local/share/clash/script/common.sh
source /home/gw/.local/share/clash/script/clashctl.sh
clashon

# 方法2: 在新终端中自动加载
# 关闭当前终端，打开新终端（会自动加载.bashrc）
```

## 服务管理

### SearXNG (端口8080)
```bash
# 查看状态
docker ps | grep searxng

# 重启服务
cd ~/searxng
docker-compose restart

# 查看日志
docker logs docker-searxng-1
```

### Dify (如果安装了)
```bash
# 查看状态
docker ps | grep dify

# 重启服务
cd ~/dify
docker-compose restart
```

## 测试访问

```bash
# 命令行测试
curl -I http://localhost:8080
curl -I http://127.0.0.1:8080

# 浏览器测试
# 打开: http://localhost:8080
# 或: http://127.0.0.1:8080
```

## 常见问题排查

### Q1: 命令行curl可以访问，但浏览器不行
**原因**: 浏览器使用了自己的代理设置，可能没有读取系统环境变量。

**解决**:
1. 重启浏览器
2. 检查浏览器代理设置
3. 清除浏览器DNS缓存和socket池

### Q2: 所有本地服务都无法访问
**原因**: Docker容器可能没有正确映射端口。

**解决**:
```bash
# 检查端口映射
docker ps
ss -tlnp | grep 8080

# 重启容器
docker restart <container-name>
```

### Q3: 代理设置丢失
**原因**: 新打开的终端没有加载代理设置。

**解决**:
```bash
# 确认.bashrc包含代理加载命令
grep "clashctl" ~/.bashrc

# 手动加载
source ~/.bashrc
```

### Q4: Tailscale域名也无法访问
**原因**: no_proxy配置已包含Tailscale域名，如果仍有问题可能是DNS解析问题。

**解决**:
```bash
# 检查Tailscale状态
tailscale status

# 测试DNS解析
nslookup your-device.tail69c12a.ts.net
```

## 配置持久化

修改已经持久化到源文件，下次系统重启或更新clash配置后仍然生效:
- ✅ `/home/gw/opt/clash-for-linux-install/script/clashctl.sh`
- ✅ `/home/gw/.local/share/clash/script/clashctl.sh`

## 附加的本地地址绕过规则

现在配置包含以下本地地址，确保所有本地服务都不走代理:
- `localhost` - 标准localhost
- `127.0.0.1` - IPv4回环地址
- `::1` - IPv6回环地址
- `0.0.0.0` - 所有接口
- `*.local` - mDNS/Bonjour域名
- `.localhost` - localhost子域
- `.local` - local子域
- `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` - 内网地址段
- Tailscale相关域名和地址段

## 总结

✅ **已完成**:
1. 更新 `no_proxy` 环境变量，添加更完整的本地地址
2. 更新GNOME `ignore-hosts` 设置
3. 同步更新源文件和运行时文件
4. 验证配置生效

📝 **下一步**:
1. **重启浏览器**（完全退出后重新打开）
2. 访问 `http://localhost:8080` 或 `http://127.0.0.1:8080`
3. 如仍有问题，清除浏览器缓存和DNS缓存

---
更新日期: 2025-11-19
修复问题: localhost/dify服务无法通过浏览器访问
