#!/usr/bin/env bash
# enable_copilot_fallback_direct.sh
#
# Goal:
#   Make GitHub Copilot traffic prefer JP-Tailscale, but automatically fall back to DIRECT
#   during the short JP-Tailscale restart window.
#
# How it works:
#   1) Create/update a proxy-group named "COPILOT" of type "fallback":
#        proxies: ["JP-Tailscale", "DIRECT"]
#        url:      health-check URL used to determine availability
#        interval: probe interval seconds
#   2) (Optional) rebuild runtime + restart mihomo so the change takes effect.
#
# Notes:
#   - This script edits ~/.local/share/clash/mixin.yaml (or --mixin PATH).
#   - It does NOT print any secrets.
#   - Actual Copilot domain rules are injected/kept high-priority by script/sanitize_runtime.sh
#     during rebuild; you don't need to hand-edit rules.
#
# Usage:
#   Preview:
#     bash vpn-tools/enable_copilot_fallback_direct.sh
#   Apply (no restart):
#     bash vpn-tools/enable_copilot_fallback_direct.sh --apply
#   Apply + rebuild (will restart mihomo):
#     bash vpn-tools/enable_copilot_fallback_direct.sh --apply --rebuild
#
# Options:
#   --url URL          Probe URL (default: https://api.github.com/)
#   --interval SEC     Probe interval seconds (default: 15)
#   --mixin PATH       Override mixin path (default: ~/.local/share/clash/mixin.yaml)

set -euo pipefail

DEBUG="${DEBUG:-0}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

MIXIN_DEFAULT="$HOME/.local/share/clash/mixin.yaml"
MIXIN="${MIXIN:-$MIXIN_DEFAULT}"

DO_APPLY=0
DO_REBUILD=0
PROBE_URL="https://api.github.com/"
INTERVAL=15

usage() {
  cat <<'EOF'
Enable Copilot fallback: JP-Tailscale -> DIRECT

Options:
  --apply           Write changes to mixin.yaml (default: preview only)
  --rebuild         Rebuild runtime + restart mihomo (requires --apply)
  --url URL         Health-check URL (default: https://api.github.com/)
  --interval SEC    Health-check interval seconds (default: 15)
  --mixin PATH      Override mixin path (default: ~/.local/share/clash/mixin.yaml)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) DO_APPLY=1; shift;;
    --rebuild) DO_REBUILD=1; shift;;
    --url)
      [[ $# -ge 2 ]] || { echo "ERROR: --url requires a value" >&2; exit 2; }
      PROBE_URL="$2"; shift 2;;
    --interval)
      [[ $# -ge 2 ]] || { echo "ERROR: --interval requires a value" >&2; exit 2; }
      INTERVAL="$2"; shift 2;;
    --mixin)
      [[ $# -ge 2 ]] || { echo "ERROR: --mixin requires a path" >&2; exit 2; }
      MIXIN="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [ "$DO_REBUILD" = 1 ] && [ "$DO_APPLY" != 1 ]; then
  echo "ERROR: --rebuild requires --apply (preview mode will not restart)." >&2
  exit 2
fi

case "$INTERVAL" in
  ''|*[!0-9]*) echo "ERROR: --interval must be an integer (seconds)" >&2; exit 2;;
esac

[ -f "$MIXIN" ] || { echo "mixin.yaml not found: $MIXIN" >&2; exit 1; }

# Pick yq
YQ_BIN=""
if [ -x "$HOME/.local/share/clash/bin/yq" ]; then
  YQ_BIN="$HOME/.local/share/clash/bin/yq"
elif command -v yq >/dev/null 2>&1; then
  YQ_BIN="yq"
fi

[ -n "$YQ_BIN" ] || { echo "yq is required (not found)." >&2; exit 1; }

# Require mikefarah/yq v4
if ! "$YQ_BIN" --version 2>/dev/null | grep -Eqi '(mikefarah|version v4|v4\.)'; then
  echo "ERROR: yq found but not compatible. Need mikefarah/yq v4 (Go binary)." >&2
  exit 1
fi

stage="$(mktemp -t copilot-mixin.XXXXXX.yaml)"
KEEP_STAGE=0
[ "$DEBUG" = "1" ] && KEEP_STAGE=1
trap 'if [ "${KEEP_STAGE:-0}" != "1" ]; then rm -f "$stage"; fi' EXIT
cp -f "$MIXIN" "$stage"

# yq's strenv() reads environment variables, not shell locals.
export PROBE_URL
export INTERVAL

# Ensure proxy-groups exists
"$YQ_BIN" -i '."proxy-groups" = (."proxy-groups" // [])' "$stage"

# Create/update COPILOT group
# We deliberately keep it minimal and do not touch other groups.
if "$YQ_BIN" -e '."proxy-groups"[]? | select(.name=="COPILOT")' "$stage" >/dev/null 2>&1; then
  "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="COPILOT")) |= {"name":"COPILOT","type":"fallback","proxies":["JP-Tailscale","DIRECT"],"url": strenv(PROBE_URL),"interval": (strenv(INTERVAL)|tonumber)}' "$stage"
else
  "$YQ_BIN" -i '."proxy-groups" += [{"name":"COPILOT","type":"fallback","proxies":["JP-Tailscale","DIRECT"],"url": strenv(PROBE_URL),"interval": (strenv(INTERVAL)|tonumber)}]' "$stage"
fi

# Best-effort YAML validation
"$YQ_BIN" '.' "$stage" >/dev/null || { echo "Staged mixin.yaml is invalid YAML; aborting." >&2; exit 1; }

# Safe preview output (no secrets)
printf '\n=== Preview (safe) ===\n'
printf 'mixin: %s\n' "$MIXIN"
printf 'apply changes: %s\n' "$DO_APPLY"
printf 'rebuild runtime: %s\n' "$DO_REBUILD"

mask_secrets_in_text() {
  # Best-effort masking for common secret-like URL parts.
  sed -E 's#^(https?://)[^/@]+@#\1***@#' \
    | sed -E 's#/(link|subscribe)/[^/?#]{8,}#\/\1\/***#g' \
    | sed -E 's/([?&](token|access_token|apikey|api_key|key|secret)=)[^&#]*/\1***/gI'
}

preview_err="$(mktemp -t copilot-preview.err.XXXXXX)"
if preview_json=$("$YQ_BIN" -o=json '."proxy-groups"[]? | select(.name=="COPILOT") | {"name": .name, "type": .type, "proxies": (.proxies // []), "interval": (.interval // 0)}' "$stage" 2>"$preview_err"); then
  printf '%s\n' "$preview_json" | sed -e 's/[[:space:]]\+$//'
else
  echo "WARN: failed to render preview (yq error)." >&2
  if [ "$DEBUG" = "1" ]; then
    echo "--- yq stderr (redacted best-effort) ---" >&2
    mask_secrets_in_text <"$preview_err" >&2 || true
    echo "(DEBUG=1) Staged file kept at: $stage" >&2
  fi
fi
rm -f "$preview_err" 2>/dev/null || true

if [ "$DO_APPLY" != 1 ]; then
  printf '\nNOTE: preview only. Use --apply to write changes.\n'
  exit 0
fi

backup="${MIXIN}.bak.$(date +%Y%m%d_%H%M%S)"
cp -f "$MIXIN" "$backup"
cp -f "$stage" "$MIXIN"
printf '\nOK: updated mixin.yaml (backup: %s)\n' "$backup"

if [ "$DO_REBUILD" = 1 ]; then
  echo "Rebuilding runtime + restarting mihomo... (may briefly interrupt proxy-dependent apps)"
  mkdir -p "$REPO_DIR/tmp" >/dev/null 2>&1 || true
  rebuild_log="$REPO_DIR/tmp/enable_copilot_fallback_direct.rebuild.$(date +%Y%m%d_%H%M%S).log"
  rebuild_rc=0
  ( cd "$REPO_DIR" && bash -lc 'export CLASH_ERROR_MODE=exit; . script/common.sh 2>/dev/null || true; . script/clashctl.sh 2>/dev/null || true; _merge_sanitize_restart' ) >"$rebuild_log" 2>&1 || rebuild_rc=$?
  echo "Rebuild log saved to: $rebuild_log"
  if [ "${rebuild_rc:-0}" -ne 0 ]; then
    echo "WARN: rebuild returned non-zero (${rebuild_rc}). See: $rebuild_log" >&2
  fi
  # Quick health check
  if bash "$REPO_DIR/script/clash_diagnose.sh" --fast --json >/dev/null 2>&1; then
    echo "OK: service appears healthy after rebuild"
  else
    echo "WARN: health check reported issues; see: $rebuild_log" >&2
  fi
  echo "Tip: run vpn-tools/trace_mihomo_connections.sh to confirm Copilot now hits rule=... and chains=..."
else
  echo "NOTE: runtime not rebuilt. Run with --rebuild to apply immediately."
fi
