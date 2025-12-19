#!/usr/bin/env bash
# Hardening helper: reduce Clash/Mihomo controller exposure.
#
# What it does (safe defaults):
# - Ensure a non-empty `secret` is set (required if controller is LAN-exposed).
# - Bind `external-controller` to 127.0.0.1 by default (keeps local UI/API working).
#
# It edits the user's mixin.yaml (NOT the repo resources/mixin.yaml):
#   ~/.local/share/clash/mixin.yaml
# then triggers a merge+restart via clashctl.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLASHCTL="$REPO_ROOT/script/clashctl.sh"

MIXIN="${CLASH_CONFIG_MIXIN:-$HOME/.local/share/clash/mixin.yaml}"
RUNTIME="${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}"
YQ_BIN="${BIN_YQ:-$HOME/.local/share/clash/bin/yq}"

BIND_LOCALHOST=1
SET_SECRET=1
NO_RESTART=0

usage(){
  cat <<'EOF'
Usage:
  bash vpn-tools/harden_controller_security.sh [--keep-bind] [--no-secret] [--no-restart]

Options:
  --keep-bind    Do not change external-controller bind address (only set secret if needed)
  --no-secret    Do not touch secret (only change bind address)
  --no-restart   Only edit mixin.yaml, do NOT restart/merge

Notes:
  - This will modify: ~/.local/share/clash/mixin.yaml (with a timestamp backup)
  - If your controller is used from other machines (phone/LAN), --keep-bind may be preferable.
EOF
}

for a in "$@"; do
  case "$a" in
    -h|--help) usage; exit 0;;
    --keep-bind) BIND_LOCALHOST=0;;
    --no-secret) SET_SECRET=0;;
    --no-restart) NO_RESTART=1;;
    *) echo "Unknown arg: $a" >&2; usage; exit 2;;
  esac
done

[ -f "$MIXIN" ] || { echo "mixin.yaml not found: $MIXIN" >&2; exit 1; }
[ -x "$YQ_BIN" ] || { echo "yq not found/executable: $YQ_BIN" >&2; exit 1; }
[ -f "$RUNTIME" ] || echo "warning: runtime.yaml not found (will still update mixin): $RUNTIME" >&2

backup="$MIXIN.bak.$(date +%Y%m%d_%H%M%S)"
cp -f "$MIXIN" "$backup"

# Determine current controller port from runtime if possible
ui_port=9090
if [ -f "$RUNTIME" ]; then
  ui_addr=$("$YQ_BIN" '."external-controller" // "127.0.0.1:9090"' "$RUNTIME" 2>/dev/null || echo '127.0.0.1:9090')
  ui_addr=$(printf '%s' "$ui_addr" | tr -d "\"'")
  ui_port=${ui_addr##*:}
  case "$ui_port" in ''|*[!0-9]*) ui_port=9090;; esac
fi

changed=0

if [ $BIND_LOCALHOST -eq 1 ]; then
  cur=$("$YQ_BIN" '."external-controller" // ""' "$MIXIN" 2>/dev/null || echo "")
  cur=$(printf '%s' "$cur" | tr -d "\"'")
  target="127.0.0.1:${ui_port}"
  if [ "$cur" != "$target" ]; then
    TARGET="$target" "$YQ_BIN" -i '."external-controller" = strenv(TARGET)' "$MIXIN" 2>/dev/null || true
    changed=1
  fi
fi

if [ $SET_SECRET -eq 1 ]; then
  cur_secret=$("$YQ_BIN" '.secret // ""' "$MIXIN" 2>/dev/null || echo "")
  cur_secret=$(printf '%s' "$cur_secret" | tr -d "\"'")
  if [ -z "$cur_secret" ]; then
    if command -v openssl >/dev/null 2>&1; then
      new_secret=$(openssl rand -hex 16)
    else
      new_secret=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
    SECRET="$new_secret" "$YQ_BIN" -i '.secret = strenv(SECRET)' "$MIXIN" 2>/dev/null || true
    echo "Controller secret generated and written to mixin.yaml (not printed for safety)."
    changed=1
  fi
fi

if [ $changed -eq 0 ]; then
  echo "No changes needed. (Backup: $backup)"
  exit 0
fi

echo "Updated mixin.yaml (backup: $backup)"

if [ $NO_RESTART -eq 1 ]; then
  echo "--no-restart set; skipping merge/restart. Run: clash update (or restart service) when ready."
  exit 0
fi

# Trigger merge+restart without downloading a subscription.
# This leverages clashupdate's fallback to local raw config.
export CLASH_ERROR_MODE=exit
bash "$CLASHCTL" update "file://$HOME/.local/share/clash/config.yaml" >/dev/null

echo "Applied and restarted."