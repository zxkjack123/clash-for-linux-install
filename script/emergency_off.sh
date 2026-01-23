#!/usr/bin/env bash
# emergency_off.sh
# One-click fallback to DIRECT (no proxy): stop user services + unset system proxy.
# Safe defaults:
#   - Does NOT disable/stop permanently (no disable/mask), only stops now.
#   - Best-effort: continues even if some units or desktop settings are missing.
# Notes:
#   - Running as a separate process cannot clear proxy env vars in your *current* shell.
#     Use --print-unset with `eval`/`source` if you need to clean the current terminal.

set -euo pipefail

FORCE_KILL=false
PRINT_UNSET=false
STOP_REFRESH_TIMER=true
# Default: preview only. Use --apply (or --trial) for real changes.
# When applying, stop services AND unset proxy settings so the system returns to
# a normal no-proxy network state (most users only have this one proxy).
UNSET_PROXY_MODE="always"   # auto|always|never
DRY_RUN=true
REPORT=true
TRIAL_SECONDS=0
REQUIRE_URLS=()
REQUIRE_TIMEOUT=${REQUIRE_TIMEOUT:-6}
DEFAULT_REQUIRE_URLS=("https://www.baidu.com" "https://www.bing.com" "https://www.qq.com")
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply|--yes)
      DRY_RUN=false
      REPORT=false
      shift
      ;;
    --force|--force-kill)
      FORCE_KILL=true
      shift
      ;;
    --unset-proxy|--unset-system-proxy)
      UNSET_PROXY_MODE="always"
      shift
      ;;
    --no-unset-proxy|--no-unset-system-proxy)
      UNSET_PROXY_MODE="never"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      REPORT=true
      shift
      ;;
    --report)
      REPORT=true
      shift
      ;;
    --trial)
      TRIAL_SECONDS="${2:-0}"
      DRY_RUN=false
      REPORT=true
      shift 2
      ;;
    --require-url)
      REQUIRE_URLS+=("${2:-}")
      shift 2
      ;;
    --require-timeout)
      REQUIRE_TIMEOUT="${2:-6}"
      shift 2
      ;;
    --print-unset)
      PRINT_UNSET=true
      shift
      ;;
    --keep-refresh)
      STOP_REFRESH_TIMER=false
      shift
      ;;
    --quiet)
      QUIET=true
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  bash script/emergency_off.sh [OPTIONS]

Options:
  --apply          Apply actions now (stop services + unset proxies). Default is preview.
  --force-kill     Also kill leftover clash/mihomo processes (best-effort)
  --unset-proxy    Always unset system/git proxy settings (default)
  --no-unset-proxy Never touch system/git proxy settings (only stop services)
  --report         Print current proxy/service state (no changes)
  --dry-run        Show what would be done (no changes)
  --trial SECONDS  Apply actions, wait SECONDS, then auto-rollback (safer testing)
  --require-url URL
                  (With --trial) Extra URL to verify direct connectivity (no proxy).
                  Default trial checks already include: baidu.com, bing.com, qq.com.
                  If any check fails, rollback immediately and exit non-zero. Can be repeated.
  --require-timeout SECONDS
                  (With --require-url) Per-URL max time (default: 6)
  --print-unset    Print shell lines to unset proxy env (for current terminal)
  --keep-refresh   Do not stop clash-subscription-refresh.timer (if present)
  --quiet          Less output

Examples:
  bash script/emergency_off.sh --apply
  bash script/emergency_off.sh --dry-run
  bash script/emergency_off.sh --trial 20
  bash script/emergency_off.sh --trial 20
  bash script/emergency_off.sh --trial 20 --require-url https://www.taobao.com
  eval "$(bash script/emergency_off.sh --print-unset)"
EOF
      exit 0
      ;;
    *)
      echo "[emergency_off] Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if $PRINT_UNSET; then
  # Do not print anything else in this mode.
  cat <<'EOF'
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
EOF
  exit 0
fi

say() { $QUIET || echo "$*"; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Load repo/installed helpers if available.
# common.sh may temporarily disable `set -u` when CLASH_LIB_MODE=1.
CLASH_LIB_MODE=1
if [ -f "$SCRIPT_DIR/common.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/common.sh" 2>/dev/null || true
fi
if [ -f "$SCRIPT_DIR/clashctl.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/clashctl.sh" 2>/dev/null || true
fi

# Restore strict mode for this script.
set -euo pipefail

CLASH_BASE_DIR_DEFAULT="$HOME/.local/share/clash"
CLASH_BASE_DIR_EFFECTIVE="${CLASH_BASE_DIR:-$CLASH_BASE_DIR_DEFAULT}"

stop_unit() {
  local unit="$1"
  [ -z "$unit" ] && return 0
  command -v systemctl >/dev/null 2>&1 || return 0
  # Best-effort; ignore missing units.
  if $DRY_RUN; then
    say "[dry-run] systemctl --user stop --no-block $unit"
    return 0
  fi
  systemctl --user stop --no-block "$unit" >/dev/null 2>&1 || true
}

unit_state() {
  # Print: <unit>: <LoadState>/<ActiveState>
  # Never fails.
  local unit="$1"
  command -v systemctl >/dev/null 2>&1 || { echo "$unit: systemctl-missing"; return 0; }
  if systemctl --user show "$unit" -p LoadState -p ActiveState --value >/dev/null 2>&1; then
    local load active
    load=$(systemctl --user show "$unit" -p LoadState --value 2>/dev/null || echo "?")
    active=$(systemctl --user show "$unit" -p ActiveState --value 2>/dev/null || echo "?")
    echo "$unit: ${load}/${active}"
  else
    echo "$unit: not-found"
  fi
}

report_state() {
  echo "## systemd(user)"
  unit_state mihomo.service
  unit_state clash.service
  unit_state clash-proxy-env.service
  unit_state clash-subscription-refresh.timer
  unit_state clash-subscription-refresh.service
  echo
  echo "## gsettings"
  if command -v gsettings >/dev/null 2>&1; then
    echo "mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo '?')"
    echo "http_host=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null || echo '?')"
    echo "http_port=$(gsettings get org.gnome.system.proxy.http port 2>/dev/null || echo '?')"
  else
    echo "no-gnome"
  fi
  echo
  echo "## git proxy"
  if command -v git >/dev/null 2>&1; then
    echo "http.proxy=$(git config --global --get http.proxy 2>/dev/null || echo '(none)')"
    echo "https.proxy=$(git config --global --get https.proxy 2>/dev/null || echo '(none)')"
  else
    echo "git-missing"
  fi
}

should_unset_proxy_auto() {
  # Return 0 if current proxy settings look like Clash-local (127.0.0.1/localhost).
  # This avoids wiping user's real upstream proxy configuration.
  
  # 1) State file written by clashctl fast-path
  if [ -f "${CLASH_PROXY_STATE_FILE:-/tmp/.clash_system_proxy_state}" ]; then
    return 0
  fi
  # 2) APT temp proxy file generated by _set_system_proxy
  if [ -f /tmp/95clash-proxy ]; then
    return 0
  fi
  # 3) GNOME proxy set to 127.0.0.1
  if command -v gsettings >/dev/null 2>&1; then
    local mode http_host https_host socks_host
    mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo "")
    http_host=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null || echo "")
    https_host=$(gsettings get org.gnome.system.proxy.https host 2>/dev/null || echo "")
    socks_host=$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null || echo "")
    if [ "$mode" = "'manual'" ] && { [ "$http_host" = "'127.0.0.1'" ] || [ "$https_host" = "'127.0.0.1'" ] || [ "$socks_host" = "'127.0.0.1'" ]; }; then
      return 0
    fi
  fi
  # 4) KDE kioslaverc proxy points to 127.0.0.1
  if [ -f "$HOME/.config/kioslaverc" ] && grep -Eq '^(httpProxy|httpsProxy|socksProxy)=127\.0\.0\.1:' "$HOME/.config/kioslaverc" 2>/dev/null; then
    return 0
  fi
  # 5) Git proxy points to localhost/127.0.0.1
  if command -v git >/dev/null 2>&1; then
    local g
    g=$(git config --global --get http.proxy 2>/dev/null || true)
    if printf '%s' "$g" | grep -Eq '^(http|https)://(127\.0\.0\.1|localhost):'; then
      return 0
    fi
    g=$(git config --global --get https.proxy 2>/dev/null || true)
    if printf '%s' "$g" | grep -Eq '^(http|https)://(127\.0\.0\.1|localhost):'; then
      return 0
    fi
  fi
  # 6) mixin.yaml indicates system-proxy.enable=true
  if [ -n "${BIN_YQ:-}" ] && [ -x "${BIN_YQ:-}" ] && [ -f "${CLASH_CONFIG_MIXIN:-}" ]; then
    if "${BIN_YQ}" -e '.system-proxy.enable == true' "${CLASH_CONFIG_MIXIN}" >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

# 4) Unset system proxy settings (desktop + git + mixin flag) best-effort.
do_unset_proxy=false
case "$UNSET_PROXY_MODE" in
  always) do_unset_proxy=true ;;
  never) do_unset_proxy=false ;;
  auto)
    if should_unset_proxy_auto; then do_unset_proxy=true; fi
    ;;
  *) do_unset_proxy=true ;;
esac

if $REPORT; then
  report_state
  echo
  if $DRY_RUN; then
    echo "## planned"
    echo "will_stop_services=yes"
    echo "will_unset_proxy=$do_unset_proxy (UNSET_PROXY_MODE=$UNSET_PROXY_MODE)"
    echo "will_force_kill=$FORCE_KILL"
    echo "will_stop_refresh_timer=$STOP_REFRESH_TIMER"
    exit 0
  fi

  # Report-only should not modify the system.
  if [ "$TRIAL_SECONDS" -le 0 ] 2>/dev/null; then
    exit 0
  fi
fi

# Trial mode: capture minimal state and auto-rollback after a short window.
rollback() {
  # Only for --trial
  [ "$TRIAL_SECONDS" -gt 0 ] 2>/dev/null || return 0
  say "[trial] 正在回滚..."

  # Restore GNOME proxy
  if command -v gsettings >/dev/null 2>&1; then
    if [ -n "${_RB_GNOME_MODE:-}" ]; then
      if [ "${_RB_GNOME_MODE:-}" = "'manual'" ]; then
        gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null || true
        [ -n "${_RB_GNOME_HTTP_HOST:-}" ] && gsettings set org.gnome.system.proxy.http host "${_RB_GNOME_HTTP_HOST}" 2>/dev/null || true
        [ -n "${_RB_GNOME_HTTP_PORT:-}" ] && gsettings set org.gnome.system.proxy.http port "${_RB_GNOME_HTTP_PORT}" 2>/dev/null || true
      else
        # 'none' or 'auto'
        gsettings set org.gnome.system.proxy mode ${_RB_GNOME_MODE} 2>/dev/null || true
      fi
    fi
  fi

  # Restore Git proxy
  if command -v git >/dev/null 2>&1; then
    if [ -n "${_RB_GIT_HTTP_PROXY_SET:-}" ]; then
      git config --global http.proxy "${_RB_GIT_HTTP_PROXY_SET}" 2>/dev/null || true
    else
      git config --global --unset http.proxy 2>/dev/null || true
    fi
    if [ -n "${_RB_GIT_HTTPS_PROXY_SET:-}" ]; then
      git config --global https.proxy "${_RB_GIT_HTTPS_PROXY_SET}" 2>/dev/null || true
    else
      git config --global --unset https.proxy 2>/dev/null || true
    fi
  fi

  # Restore services that were active
  if command -v systemctl >/dev/null 2>&1; then
    [ "${_RB_MIHOMO_ACTIVE:-0}" = 1 ] && systemctl --user start mihomo.service >/dev/null 2>&1 || true
    [ "${_RB_CLASH_ACTIVE:-0}" = 1 ] && systemctl --user start clash.service >/dev/null 2>&1 || true
    [ "${_RB_PROXYENV_ACTIVE:-0}" = 1 ] && systemctl --user start clash-proxy-env.service >/dev/null 2>&1 || true
    [ "${_RB_REFRESH_TIMER_ACTIVE:-0}" = 1 ] && systemctl --user start clash-subscription-refresh.timer >/dev/null 2>&1 || true
  fi
}

_ROLLED_BACK=0
rollback_once() {
  [ "$_ROLLED_BACK" -eq 1 ] && return 0
  _ROLLED_BACK=1
  rollback || true
}

require_direct_ok() {
  # $1 url
  # Returns 0 if curl can fetch headers directly (no proxy) with a sane HTTP code.
  local url="$1"
  [ -z "$url" ] && return 1
  command -v curl >/dev/null 2>&1 || return 1

  # Make sure we don't inherit env proxy even if caller has it.
  local code
  code=$(
    env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY -u no_proxy -u NO_PROXY \
      curl -sS -I -L \
        --noproxy '*' \
        --connect-timeout 3 \
        --max-time "$REQUIRE_TIMEOUT" \
        --retry 0 \
        -o /dev/null -w '%{http_code}' \
        "$url" 2>/dev/null || echo 000
  )
  # Treat 2xx/3xx as OK.
  if [[ "$code" =~ ^[0-9]+$ ]] && [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
    return 0
  fi
  return 1
}

if [ "$TRIAL_SECONDS" -gt 0 ] 2>/dev/null; then
  # Snapshot state (best-effort)
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user is-active --quiet mihomo.service && _RB_MIHOMO_ACTIVE=1 || _RB_MIHOMO_ACTIVE=0
    systemctl --user is-active --quiet clash.service && _RB_CLASH_ACTIVE=1 || _RB_CLASH_ACTIVE=0
    systemctl --user is-active --quiet clash-proxy-env.service && _RB_PROXYENV_ACTIVE=1 || _RB_PROXYENV_ACTIVE=0
    systemctl --user is-active --quiet clash-subscription-refresh.timer && _RB_REFRESH_TIMER_ACTIVE=1 || _RB_REFRESH_TIMER_ACTIVE=0
  fi
  if command -v gsettings >/dev/null 2>&1; then
    _RB_GNOME_MODE=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo "")
    _RB_GNOME_HTTP_HOST=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null || echo "")
    _RB_GNOME_HTTP_PORT=$(gsettings get org.gnome.system.proxy.http port 2>/dev/null || echo "")
  fi
  if command -v git >/dev/null 2>&1; then
    _RB_GIT_HTTP_PROXY_SET=$(git config --global --get http.proxy 2>/dev/null || echo "")
    _RB_GIT_HTTPS_PROXY_SET=$(git config --global --get https.proxy 2>/dev/null || echo "")
  fi

  trap rollback_once EXIT
fi

# ------------------------------
# Apply actions (stop services + unset proxies)
# IMPORTANT: must run AFTER trial snapshot is captured.
# ------------------------------

# 1) Stop auto-refresh timer/service to prevent it from restarting mihomo later (optional).
if $STOP_REFRESH_TIMER; then
  stop_unit clash-subscription-refresh.timer
  stop_unit clash-subscription-refresh.service
fi

# 2) Stop proxy env unit (may exist in both legacy and hardened variants).
stop_unit clash-proxy-env.service

# 3) Stop kernel unit (mihomo/clash); prefer detected BIN_KERNEL_NAME.
#    Fallback to common unit names to be resilient.
UNITS_TO_STOP=()
if [ -n "${BIN_KERNEL_NAME:-}" ]; then
  UNITS_TO_STOP+=("$BIN_KERNEL_NAME")
fi
UNITS_TO_STOP+=(mihomo clash)

# De-duplicate units.
declare -A _seen=()
for u in "${UNITS_TO_STOP[@]}"; do
  [ -z "$u" ] && continue
  if [ -z "${_seen[$u]:-}" ]; then
    _seen[$u]=1
    stop_unit "$u"
    stop_unit "${u}.service"
  fi
done

if $do_unset_proxy; then
  # Prefer shared implementation when available, but never let it abort the emergency flow.
  if declare -F _unset_system_proxy >/dev/null 2>&1; then
    if $DRY_RUN; then
      say "[dry-run] _unset_system_proxy"
    else
      ( set +e; _unset_system_proxy >/dev/null 2>&1 ) || true
    fi
  fi

  # Fallback unset (covers cases where clashctl isn't available or yq edits fail).
  # Disable GNOME proxy (only if it points to local; in always mode, we still do it)
  if command -v gsettings >/dev/null 2>&1; then
    mode=""
    http_host=""
    https_host=""
    socks_host=""
    mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo "")
    http_host=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null || echo "")
    https_host=$(gsettings get org.gnome.system.proxy.https host 2>/dev/null || echo "")
    socks_host=$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null || echo "")
    if [ "$UNSET_PROXY_MODE" = "always" ] || { [ "$mode" = "'manual'" ] && { [ "$http_host" = "'127.0.0.1'" ] || [ "$https_host" = "'127.0.0.1'" ] || [ "$socks_host" = "'127.0.0.1'" ]; }; }; then
      if $DRY_RUN; then
        say "[dry-run] gsettings set org.gnome.system.proxy mode 'none'"
      else
        gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null || true
      fi
    fi
  fi

  # Disable KDE proxy if kioslaverc indicates local proxy (or always mode)
  if command -v kwriteconfig5 >/dev/null 2>&1; then
    if [ "$UNSET_PROXY_MODE" = "always" ] || { [ -f "$HOME/.config/kioslaverc" ] && grep -Eq '^(httpProxy|httpsProxy|socksProxy)=127\.0\.0\.1:' "$HOME/.config/kioslaverc" 2>/dev/null; }; then
      if $DRY_RUN; then
        say "[dry-run] kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 0"
      else
        kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 0 2>/dev/null || true
      fi
    fi
  fi

  # Unset Git proxy only if it points to localhost/127.0.0.1 (or always mode)
  if command -v git >/dev/null 2>&1; then
    g=""
    g=$(git config --global --get http.proxy 2>/dev/null || true)
    if [ "$UNSET_PROXY_MODE" = "always" ] || printf '%s' "$g" | grep -Eq '^(http|https)://(127\.0\.0\.1|localhost):'; then
      if $DRY_RUN; then
        say "[dry-run] git config --global --unset http.proxy"
      else
        git config --global --unset http.proxy 2>/dev/null || true
      fi
    fi
    g=$(git config --global --get https.proxy 2>/dev/null || true)
    if [ "$UNSET_PROXY_MODE" = "always" ] || printf '%s' "$g" | grep -Eq '^(http|https)://(127\.0\.0\.1|localhost):'; then
      if $DRY_RUN; then
        say "[dry-run] git config --global --unset https.proxy"
      else
        git config --global --unset https.proxy 2>/dev/null || true
      fi
    fi
  fi

  # Remove APT temp proxy file (our own) if present
  if $DRY_RUN; then
    say "[dry-run] rm -f /tmp/95clash-proxy"
  else
    rm -f /tmp/95clash-proxy 2>/dev/null || true
  fi

  # Try to flip mixin system-proxy flag off if yq + mixin exist.
  if [ -n "${BIN_YQ:-}" ] && [ -x "${BIN_YQ:-}" ] && [ -f "${CLASH_CONFIG_MIXIN:-}" ]; then
    if $DRY_RUN; then
      say "[dry-run] yq: set .system-proxy.enable=false in ${CLASH_CONFIG_MIXIN}"
    else
      "${BIN_YQ}" -i '.system-proxy.enable = false' "${CLASH_CONFIG_MIXIN}" 2>/dev/null || true
    fi
  fi
else
  say "[emergency_off] 已按需停止服务；根据当前检测结果，本次未改动系统代理/Git 代理设置 (UNSET_PROXY_MODE=$UNSET_PROXY_MODE)。"
fi

# 5) Optional force kill (for stuck processes not controlled by systemd)
if $FORCE_KILL; then
  # Tight patterns to reduce collateral damage.
  if $DRY_RUN; then
    say "[dry-run] pkill -f ${CLASH_BASE_DIR_EFFECTIVE}/bin/mihomo"
    say "[dry-run] pkill -f ${CLASH_BASE_DIR_EFFECTIVE}/bin/clash"
  else
    pkill -f "${CLASH_BASE_DIR_EFFECTIVE}/bin/mihomo" 2>/dev/null || true
    pkill -f "${CLASH_BASE_DIR_EFFECTIVE}/bin/clash" 2>/dev/null || true
  fi
fi

say "[emergency_off] 已尝试停止 clash/mihomo 用户服务。"
if $do_unset_proxy; then
  say "[emergency_off] 已按需卸载系统代理/Git 代理设置 (UNSET_PROXY_MODE=$UNSET_PROXY_MODE)。"
fi
if $STOP_REFRESH_TIMER; then
  say "[emergency_off] 已停止 clash-subscription-refresh.timer (如存在) 以避免自动重启。"
else
  say "[emergency_off] 已保留 clash-subscription-refresh.timer (如存在)。"
fi
say "[emergency_off] 提示：如果你当前终端仍然走代理，请执行：eval \"\$(bash script/emergency_off.sh --print-unset)\""

if [ "$TRIAL_SECONDS" -gt 0 ] 2>/dev/null; then
  # Trial self-checks: defaults + user-specified (deduped)
  declare -A _url_seen=()
  URLS_TO_CHECK=()
  for u in "${DEFAULT_REQUIRE_URLS[@]}" "${REQUIRE_URLS[@]}"; do
    [ -z "$u" ] && continue
    if [ -z "${_url_seen[$u]:-}" ]; then
      _url_seen[$u]=1
      URLS_TO_CHECK+=("$u")
    fi
  done

  if [ ${#URLS_TO_CHECK[@]} -gt 0 ]; then
    say "[trial] 正在进行直连自检 (noproxy), 超时=${REQUIRE_TIMEOUT}s ..."
    for u in "${URLS_TO_CHECK[@]}"; do
      if require_direct_ok "$u"; then
        say "[trial] OK: $u"
      else
        say "[trial] FAIL: $u -> 立即回滚" >&2
        rollback_once
        exit 1
      fi
    done
  fi
  say "[trial] 已应用变更，将在 ${TRIAL_SECONDS}s 后自动回滚。"
  sleep "$TRIAL_SECONDS" 2>/dev/null || true
fi
