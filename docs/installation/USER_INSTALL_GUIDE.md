# Clash User Installation Guide

This modified version installs Clash as a user service instead of a system service, eliminating the need for sudo privileges during normal operation.

## Key Changes

1. **Installation Location**: `~/.local/share/clash` (user directory instead of `/opt/clash`)
2. **Service Type**: User systemd service instead of system service
3. **No sudo required**: Most operations no longer require password input
4. **Auto-start**: Kernel + system proxy can start automatically on login (and at boot if lingering is enabled)
5. **Service Stability** (2025-08-13): Fixed startup timeout issues and improved reliability

## Installation

Run the installation script normally:
```bash
bash install.sh
```

If you run it with sudo, it will properly install for the actual user (not root).

## What's Different

### No More Password Prompts
- All clash commands now work without sudo
- Configuration files are in your user directory
- Service management is done via `systemctl --user`

### Automatic Proxy Activation
- The kernel service (`mihomo`/`clash`) can start automatically on login via `systemctl --user`
- System proxy (GNOME/KDE) and Git proxy are applied by `clash-proxy-env.service`
- **Note**: Shell environment variables like `http_proxy` are **not** injected into every new bash/zsh shell by default.
	If you want terminal apps to automatically see `http_proxy`/`ALL_PROXY`, use the lightweight snippet in:
	`docs/development/CLASH_PROXY_STARTUP_BEST_PRACTICES.md`

### Service Management
```bash
# Recommended control entrypoint (works even if your shell has no functions loaded)
bash ~/.local/share/clash/script/clashctl.sh status

# Start/stop service
bash ~/.local/share/clash/script/clashctl.sh on
bash ~/.local/share/clash/script/clashctl.sh off

# View service logs
systemctl --user status mihomo
journalctl --user -u mihomo -f
```

### Configuration
All configuration files are now in `~/.local/share/clash/`:
- Runtime config: `~/.local/share/clash/runtime.yaml`
- Mixin config: `~/.local/share/clash/mixin.yaml`
- Raw config: `~/.local/share/clash/config.yaml`

### Uninstallation
Run the uninstall script normally:
```bash
bash uninstall.sh
```

It will properly clean up user services and configurations.

## Troubleshooting

### Service Startup Issues (Fixed in Latest Version)
If you're using an older version and experiencing service startup timeouts:
1. Update to the latest version which fixes the circular dependency issue
2. Or manually restart the service: `systemctl --user restart mihomo`

### General Issues
If the proxy doesn't start automatically:
1. Check if the user service is enabled: `systemctl --user is-enabled mihomo`
2. Check service status: `systemctl --user status mihomo`
3. View service logs: `journalctl --user -u mihomo -f`
4. Manually start: `bash ~/.local/share/clash/script/clashctl.sh on`

If you prefer a shorter command, create a symlink once:

```bash
mkdir -p ~/.local/bin
ln -sf ~/.local/share/clash/script/clashctl.sh ~/.local/bin/clashctl
```

Then you can use `clashctl on/off/status`.

If you need to enable boot-time startup:
```bash
sudo loginctl enable-linger $USER
```

This allows your user services to start even when you're not logged in.

### Service Log Analysis
To debug service issues:
```bash
# Check current service status
systemctl --user status mihomo --no-pager -l

# View recent logs
journalctl --user -u mihomo -n 50 --no-pager

# Follow logs in real-time
journalctl --user -u mihomo -f
```
