# Clash User Installation Guide

This modified version installs Clash as a user service instead of a system service, eliminating the need for sudo privileges during normal operation.

## Key Changes

1. **Installation Location**: `~/.local/share/clash` (user directory instead of `/opt/clash`)
2. **Service Type**: User systemd service instead of system service
3. **No sudo required**: Most operations no longer require password input
4. **Auto-start**: Proxy automatically starts when you open a new terminal

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
- The proxy automatically starts when you login or open a new terminal
- Your shell environment variables are set automatically
- No manual intervention needed for daily use

### Service Management
```bash
# Check service status
clash status

# Start/stop service
clash on
clash off

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

If the proxy doesn't start automatically:
1. Check if the user service is enabled: `systemctl --user is-enabled mihomo`
2. Check service status: `systemctl --user status mihomo`
3. Manually start: `clash on`

If you need to enable boot-time startup:
```bash
sudo loginctl enable-linger $USER
```

This allows your user services to start even when you're not logged in.
