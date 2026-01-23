# Docker Integration Guide for Clash/Mihomo

## Summary

On Linux, the safest/easiest way to let Docker containers use Clash/Mihomo is **host networking** for test containers:

- Keep the proxy/controller bound to localhost (`127.0.0.1`) by default.
- Run containers with `--network host` so they can reach `127.0.0.1` on the host.

Only use bridged networking access (`<HOST_IP>:7890/9090`) when you *must*, and then require a controller `secret` + firewall rules.

## Notes on config files

- `~/.local/share/clash/runtime.yaml` is the effective runtime config generated/used by the service.
- `/path/to/clash-for-linux-install/resources/mixin.yaml` is the recommended place to control safe defaults.
- The controller address/secret can vary by deployment; prefer **auto-detection** (e.g. scripts under `vpn-tools/` source `vpn-tools/load_env.sh`).

## Usage for Docker Containers

### Method 1: Using Network Mode Host (recommended on Linux)
```bash
docker run --rm --network host curlimages/curl:latest \
   curl -x http://127.0.0.1:7890 http://example.com

docker run --rm --network host curlimages/curl:latest \
   curl http://127.0.0.1:9090/version

# If your controller has a secret enabled, add:
#   -H "Authorization: Bearer <your-secret>"
```

### Method 2: Using host.docker.internal (bridge mode)
```bash
# Add host alias and use proxy
docker run --rm --add-host=host.docker.internal:host-gateway curlimages/curl:latest curl -x http://host.docker.internal:7890 http://example.com

# Access dashboard
docker run --rm --add-host=host.docker.internal:host-gateway curlimages/curl:latest curl http://host.docker.internal:9090/version
```

### Method 3: In Docker Compose
```yaml
version: '3.8'
services:
  your-app:
    image: your-image
    environment:
         - HTTP_PROXY=http://HOST_IP:7890
         - HTTPS_PROXY=http://HOST_IP:7890
         - NO_PROXY=localhost,127.0.0.1
    extra_hosts:
         - "host.docker.internal:host-gateway"
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
   docker run --rm --network host curlimages/curl:latest curl http://127.0.0.1:9090/version
   # Returns: {"meta":true,"version":"v1.19.2"}
   ```

2. **Proxy Functionality Test:**
   ```bash
   docker run --rm --network host curlimages/curl:latest curl -x http://127.0.0.1:7890 http://httpbin.org/ip
   # Returns: {"origin": "85.234.83.184"} (shows proxy IP)
   ```

3. **End-to-end script test (recommended):**
   ```bash
   cd /path/to/clash-for-linux-install
   DOCKER_NET_MODE=host bash vpn-tools/test_docker_proxy.sh
   # For bridge mode:
   # DOCKER_NET_MODE=bridge bash vpn-tools/test_docker_proxy.sh
   ```

## Security Notes

- ✅ Prefer keeping the controller on localhost (`127.0.0.1:9090`).
- ⚠️ If you expose the controller (e.g., `0.0.0.0:9090`) you should set a `secret` and restrict access with firewall rules.
- ⚠️ If you have containers you don't trust, avoid bridged access to the proxy/controller ports.

## Troubleshooting

### If Docker containers can't access Clash:

1. **Check service status:**
   ```bash
   bash /path/to/clash-for-linux-install/vpn-tools/restart_clash_service.sh
   ```

2. **Verify ports are listening:**
   ```bash
   sudo ss -tlnp | grep -E ":(7890|9090)"
   # Bind address may be 127.0.0.1 (safe default) or 0.0.0.0/host IP (bridge mode).
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

If you previously enabled bridge-mode exposure and want to restrict access back to localhost only:

1. Edit `/path/to/clash-for-linux-install/resources/mixin.yaml` and restore safe values, for example:
   - `allow-lan: false`
   - `bind-address: "127.0.0.1"`
   - keep controller on localhost unless you truly need remote access

2. Re-merge + restart:
   - Preferred: run `clashctl mixin -e` and save/exit (it merges and restarts automatically)
   - Or use the helper: `bash /path/to/clash-for-linux-install/vpn-tools/restart_clash_service.sh`

3. Remove any temporary firewall rules you added.

---

**Tip:** For production-like setups, prefer keeping the controller/proxy bound to localhost and use Docker host networking for ad-hoc containers.
