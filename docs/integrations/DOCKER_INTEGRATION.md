# Docker Integration Guide for Clash

## Summary

Clash has been successfully configured to allow connections from Docker containers. Both the proxy service and the web dashboard are now accessible from within Docker containers.

## Configuration Changes Made

### 1. Clash Configuration Updates

#### Main Config (`/home/gw/opt/clash-for-linux-install/resources/config.yaml`)
- ✅ `external-controller: "0.0.0.0:9090"` - Web dashboard accessible from all interfaces
- ✅ `allow-lan: true` - LAN access enabled
- ✅ `bind-address: "*"` - Proxy binds to all interfaces

#### Mixin Config (`/home/gw/opt/clash-for-linux-install/resources/mixin.yaml`)
- ✅ `allow-lan: true` - LAN access enabled for Docker containers
- ✅ `bind-address: "0.0.0.0"` - Explicit binding to all interfaces

#### Runtime Config (`/home/gw/.local/share/clash/runtime.yaml`)
- ✅ Updated to reflect allow-lan: true

### 2. Firewall Rules Added

The following iptables rules have been configured to allow Docker container access:

```bash
# Allow Docker networks to access Clash proxy (7890) and dashboard (9090)
iptables -I DOCKER-USER -s 172.16.0.0/12 -d 172.28.130.97 -p tcp --dport 7890 -j ACCEPT
iptables -I DOCKER-USER -s 172.16.0.0/12 -d 172.28.130.97 -p tcp --dport 9090 -j ACCEPT
iptables -I INPUT -s 172.16.0.0/12 -d 172.28.130.97 -p tcp --dport 7890 -j ACCEPT
iptables -I INPUT -s 172.16.0.0/12 -d 172.28.130.97 -p tcp --dport 9090 -j ACCEPT
```

**Rules saved to:** `/etc/iptables/rules.v4` for persistence across reboots.

### 3. Service Status

- ✅ Clash (mihomo) service is running
- ✅ Port 7890 (proxy) listening on `:::7890` (all interfaces)
- ✅ Port 9090 (dashboard) listening on `:::9090` (all interfaces)

## Usage for Docker Containers

### Method 1: Using Host IP Address
```bash
# For containers needing proxy access
docker run --rm curlimages/curl:latest curl -x http://172.28.130.97:7890 http://example.com

# For accessing the dashboard
docker run --rm curlimages/curl:latest curl http://172.28.130.97:9090/version
```

### Method 2: Using host.docker.internal (recommended)
```bash
# Add host alias and use proxy
docker run --rm --add-host=host.docker.internal:172.28.130.97 curlimages/curl:latest curl -x http://host.docker.internal:7890 http://example.com

# Access dashboard
docker run --rm --add-host=host.docker.internal:172.28.130.97 curlimages/curl:latest curl http://host.docker.internal:9090/version
```

### Method 3: In Docker Compose
```yaml
version: '3.8'
services:
  your-app:
    image: your-image
    environment:
      - HTTP_PROXY=http://172.28.130.97:7890
      - HTTPS_PROXY=http://172.28.130.97:7890
      - NO_PROXY=localhost,127.0.0.1
    extra_hosts:
      - "host.docker.internal:172.28.130.97"
```

### Method 4: Using Network Mode Host
```bash
docker run --network host your-image
# Then use localhost:7890 as proxy
```

## Verification

The following tests confirm successful configuration:

1. **Dashboard Access Test:**
   ```bash
   docker run --rm curlimages/curl:latest curl http://172.28.130.97:9090/version
   # Returns: {"meta":true,"version":"v1.19.2"}
   ```

2. **Proxy Functionality Test:**
   ```bash
   docker run --rm curlimages/curl:latest curl -x http://172.28.130.97:7890 http://httpbin.org/ip
   # Returns: {"origin": "85.234.83.184"} (shows proxy IP)
   ```

## Security Notes

- ⚠️ Clash is now accessible from all Docker networks (172.16.0.0/12)
- ⚠️ If you have containers you don't trust, consider more restrictive firewall rules
- ⚠️ The dashboard (port 9090) is accessible without authentication
- ✅ Only private Docker networks can access Clash (not external networks)

## Troubleshooting

### If Docker containers can't access Clash:

1. **Check service status:**
   ```bash
   bash /home/gw/opt/clash-for-linux-install/vpn-tools/restart_clash_service.sh
   ```

2. **Verify ports are listening:**
   ```bash
   sudo netstat -tlnp | grep -E ":(7890|9090)"
   # Should show: :::7890 and :::9090
   ```

3. **Check firewall rules:**
   ```bash
   sudo iptables -L DOCKER-USER -n
   ```

4. **Test from host:**
   ```bash
   curl http://localhost:9090/version
   curl -x http://localhost:7890 http://httpbin.org/ip
   ```

## Rollback Instructions

If you need to restrict access back to localhost only:

1. **Update configs:**
   ```bash
   sed -i 's/allow-lan: true/allow-lan: false/' /home/gw/opt/clash-for-linux-install/resources/mixin.yaml
   sed -i 's/external-controller: "0.0.0.0:9090"/external-controller: "127.0.0.1:9090"/' /home/gw/opt/clash-for-linux-install/resources/config.yaml
   ```

2. **Remove firewall rules:**
   ```bash
   sudo iptables -D DOCKER-USER -s 172.16.0.0/12 -d 172.28.130.97 -p tcp --dport 7890 -j ACCEPT
   sudo iptables -D DOCKER-USER -s 172.16.0.0/12 -d 172.28.130.97 -p tcp --dport 9090 -j ACCEPT
   sudo iptables -D INPUT -s 172.16.0.0/12 -d 172.28.130.97 -p tcp --dport 7890 -j ACCEPT
   sudo iptables -D INPUT -s 172.16.0.0/12 -d 172.28.130.97 -p tcp --dport 9090 -j ACCEPT
   ```

3. **Restart service:**
   ```bash
   bash /home/gw/opt/clash-for-linux-install/vpn-tools/restart_clash_service.sh
   ```

---

**Configuration completed on:** August 14, 2025  
**Host IP:** 172.28.130.97  
**Clash Version:** v1.19.2  
**Status:** ✅ Fully functional for Docker container access
