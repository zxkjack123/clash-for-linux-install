# Changelog

All notable changes to this project will be documented in this file.

## [2025-08-13] - Service Startup Fix

### Fixed
- **Critical**: Fixed mihomo service startup timeout issue
  - Removed problematic `ExecStartPost` command that caused circular dependency
  - Added `TimeoutStartSec=30` to prevent long startup hangs
  - Updated clash-proxy-env.service to use `BindsTo` instead of `Requisite`
  - Added timeout protection to proxy environment service

### Changed
- **Service Configuration**: Improved systemd service reliability
  - Main service now starts faster and more reliably
  - Proxy environment service properly depends on main service
  - Better error handling and timeout management

### Technical Details
- The previous version had a circular dependency where:
  1. mihomo.service would start
  2. ExecStartPost would try to restart clash-proxy-env.service
  3. clash-proxy-env.service would wait for mihomo.service
  4. This caused a 90-second timeout and service failure

- The fix involves:
  1. Removing the ExecStartPost command from mihomo.service
  2. Using `BindsTo` dependency instead of `Requisite` in clash-proxy-env.service
  3. Adding appropriate timeouts to prevent hangs
  4. Allowing the proxy environment service to start independently

### Testing
- ✅ Proxy connectivity tested for local (China) and global sites
- ✅ Service starts reliably without timeouts
- ✅ Automatic restart functionality works correctly
- ✅ Web UI accessible at http://localhost:9090/ui
- ✅ All proxy groups and nodes functioning properly

## Previous Versions

### [Original] - User Space Installation
- Initial implementation of user-space Clash installation
- No sudo required for daily operations
- User systemd service management
- Automatic proxy environment setup
