#!/usr/bin/env bash
# use_jp_tailscale_only.sh
#
# Goal:
#   Convert local ~/.local/share/clash/mixin.yaml to a JP-Tailscale-only setup.
#   This removes references to subscription nodes (e.g. V4-*, region selectors) from proxy-groups,
#   while keeping a compatibility group named "速云梯" (optional) so existing rule-sets keep working.
#
# Safety:
#   - Creates a timestamped backup of mixin.yaml.
#   - Does NOT print any secrets.
#   - Default mode is preview only (no file changes, no restart).
#   - Rebuild/restart is opt-in because it can interrupt VS Code / Copilot.
#
# Usage (safe, no changes):
#   bash vpn-tools/use_jp_tailscale_only.sh
#
# Apply changes (still no restart):
#   bash vpn-tools/use_jp_tailscale_only.sh --apply
#
# Apply + rebuild runtime (will restart mihomo):
#   bash vpn-tools/use_jp_tailscale_only.sh --apply --rebuild
#
# Aggressively prune all select groups (optional):
#   bash vpn-tools/use_jp_tailscale_only.sh --apply --prune-all-selectors

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

MIXIN_DEFAULT="$HOME/.local/share/clash/mixin.yaml"
MIXIN="${MIXIN:-$MIXIN_DEFAULT}"

KEEP_COMPAT_SUYUNTI=1
DO_REBUILD=0
DO_APPLY=0
PRUNE_ALL_SELECTORS=0
WITH_DIRECT_FALLBACK=0

usage() {
  cat <<'EOF'
Use JP-Tailscale only (prune subscription nodes from proxy-groups)

Options:
  --apply              Write changes to mixin.yaml (default: preview only)
  --rebuild            Rebuild runtime + restart mihomo (requires --apply)
  --no-compat-suyunti   Do not keep/create the compatibility group named "速云梯"
  --prune-all-selectors Aggressively prune ALL select groups to only safe entries
  --with-direct-fallback Allow DIRECT as a fallback option in AUTO-SMART/故障转移
  --mixin PATH          Override mixin path (default: ~/.local/share/clash/mixin.yaml)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) DO_APPLY=1; shift;;
    --rebuild) DO_REBUILD=1; shift;;
    --no-compat-suyunti) KEEP_COMPAT_SUYUNTI=0; shift;;
    --prune-all-selectors) PRUNE_ALL_SELECTORS=1; shift;;
    --with-direct-fallback) WITH_DIRECT_FALLBACK=1; shift;;
    --mixin)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --mixin requires a path" >&2
        exit 2
      fi
      MIXIN="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [ "$DO_REBUILD" = 1 ] && [ "$DO_APPLY" != 1 ]; then
  echo "ERROR: --rebuild requires --apply (preview mode will not restart)." >&2
  exit 2
fi

[ -f "$MIXIN" ] || { echo "mixin.yaml not found: $MIXIN" >&2; exit 1; }

# Pick yq
YQ_BIN=""
if [ -x "$HOME/.local/share/clash/bin/yq" ]; then
  YQ_BIN="$HOME/.local/share/clash/bin/yq"
elif command -v yq >/dev/null 2>&1; then
  YQ_BIN="yq"
fi

[ -n "$YQ_BIN" ] || { echo "yq is required (not found)." >&2; exit 1; }

# This script relies on mikefarah/yq v4 (Go binary). The Python yq wrapper is incompatible.
if ! "$YQ_BIN" --version 2>/dev/null | grep -Eqi '(mikefarah|version v4|v4\.)'; then
  echo "ERROR: yq found but not compatible. This script requires mikefarah/yq v4 (Go binary)." >&2
  echo "       Expected: ~/.local/share/clash/bin/yq (installed by this repo's install.sh)" >&2
  echo "       Found: $YQ_BIN" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  # Safety guard: only delete mktemp directories under /tmp or /var/tmp
  [ -n "${tmp_dir:-}" ] || return 0
  case "$tmp_dir" in
    /tmp/*|/var/tmp/*) rm -rf "$tmp_dir" ;;
    *) : ;;
  esac
}
trap cleanup EXIT

stage="$tmp_dir/mixin.stage.yaml"
cp -f "$MIXIN" "$stage"

# Helper: print the proxies list of a group (safe: does not show node secrets)
print_group_proxies() {
  local file="$1"
  local name="$2"
  # Keep output small: show count + a short head list.
  "$YQ_BIN" -o=json ".\"proxy-groups\"[]? | select(.name==\"${name}\") | {\"name\": .name, \"type\": .type, \"proxies_count\": (.proxies // [] | length), \"proxies_head\": (.proxies // [] | .[0:15])}" "$file" 2>/dev/null \
    | sed -e 's/[[:space:]]\+$//' \
    || true
}

# Helper: ensure a select group exists
ensure_select_group() {
  local name="$1"
  # If group doesn't exist, append a minimal selector.
  if ! "$YQ_BIN" -e ".\"proxy-groups\"[]? | select(.name==\"${name}\")" "$stage" >/dev/null 2>&1; then
    "$YQ_BIN" -i ".\"proxy-groups\" = (.\"proxy-groups\" // []) | .\"proxy-groups\" += [{\"name\":\"${name}\",\"type\":\"select\",\"proxies\":[\"JP-Tailscale\"]}]" "$stage" >/dev/null 2>&1 || true
  fi
}

# Ensure core groups exist (some rules or tools expect them)
ensure_select_group "AUTO-SMART"
ensure_select_group "故障转移"
ensure_select_group "AI"
ensure_select_group "Development"
ensure_select_group "Gaming"
ensure_select_group "Streaming"

if [ "$KEEP_COMPAT_SUYUNTI" = 1 ]; then
  ensure_select_group "速云梯"
fi

# Sanity check: JP-Tailscale proxy should exist (warn-only; some setups define it elsewhere).
if ! "$YQ_BIN" -e '(.proxies // []) | any(.name == "JP-Tailscale")' "$stage" >/dev/null 2>&1; then
  echo "WARN: proxy named 'JP-Tailscale' not found under .proxies in $MIXIN" >&2
  echo "      If your JP-Tailscale node comes from another merged config, preview may still be OK." >&2
fi

# Rewrite groups to JP-Tailscale only (and minimal internal references)
# NOTE: Keep order stable and avoid creating cycles.
if [ "$WITH_DIRECT_FALLBACK" = 1 ]; then
  "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="AUTO-SMART")).proxies = ["JP-Tailscale","DIRECT"]' "$stage" >/dev/null 2>&1 || true
  "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="故障转移")).proxies = ["JP-Tailscale","DIRECT"]' "$stage" >/dev/null 2>&1 || true
else
  "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="AUTO-SMART")).proxies = ["JP-Tailscale"]' "$stage" >/dev/null 2>&1 || true
  "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="故障转移")).proxies = ["JP-Tailscale"]' "$stage" >/dev/null 2>&1 || true
fi

"$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="AI")).proxies = ["JP-Tailscale","AUTO-SMART"]' "$stage" >/dev/null 2>&1 || true
"$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="Development")).proxies = ["JP-Tailscale","AUTO-SMART"]' "$stage" >/dev/null 2>&1 || true
"$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="Gaming")).proxies = ["JP-Tailscale","AUTO-SMART"]' "$stage" >/dev/null 2>&1 || true
"$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="Streaming")).proxies = ["JP-Tailscale","AUTO-SMART"]' "$stage" >/dev/null 2>&1 || true

if [ "$KEEP_COMPAT_SUYUNTI" = 1 ]; then
  # Compatibility: keep 速云梯 pointing to JP only (via AUTO-SMART)
  "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="速云梯")).proxies = ["AUTO-SMART","JP-Tailscale"]' "$stage" >/dev/null 2>&1 || true
else
  # Remove the group if requested
  "$YQ_BIN" -i 'del(."proxy-groups"[] | select(.name=="速云梯"))' "$stage" >/dev/null 2>&1 || true
fi

if [ "$PRUNE_ALL_SELECTORS" = 1 ]; then
  # Optional aggressive mode: prune ALL selector groups.
  # We keep only known-safe entries (including core group names).
  "$YQ_BIN" -i '
    (."proxy-groups"[] | select(.type=="select")).proxies |= ((. // [])
      | map(select(
          . == "JP-Tailscale"
          or . == "AUTO-SMART"
          or . == "故障转移"
          or . == "速云梯"
          or . == "DIRECT"
          or . == "REJECT"
      ))
    )
  ' "$stage" >/dev/null 2>&1 || true
fi

# Ensure each selector has at least one option
"$YQ_BIN" -i '(."proxy-groups"[] | select(.type=="select")).proxies |= (if ((. // []) | length) > 0 then (. // []) else ["JP-Tailscale"] end)' "$stage" >/dev/null 2>&1 || true

# Validate YAML (best effort)
"$YQ_BIN" '.' "$stage" >/dev/null 2>&1 || { echo "Staged mixin.yaml is invalid YAML; no changes were applied." >&2; exit 1; }

printf '\n=== Preview (safe, no secrets) ===\n'
printf 'mixin: %s\n' "$MIXIN"
printf "keep compat group '速云梯': %s\n" "$KEEP_COMPAT_SUYUNTI"
printf 'prune all selectors: %s\n' "$PRUNE_ALL_SELECTORS"
printf 'direct fallback: %s\n' "$WITH_DIRECT_FALLBACK"
printf 'apply changes: %s\n' "$DO_APPLY"
printf 'rebuild runtime: %s\n' "$DO_REBUILD"

printf '\n--- Before -> After (proxy-groups only) ---\n'
for g in "AUTO-SMART" "故障转移" "AI" "Development" "Gaming" "Streaming" "速云梯"; do
  if [ "$g" = "速云梯" ] && [ "$KEEP_COMPAT_SUYUNTI" != 1 ]; then
    continue
  fi
  printf '\n[%s] BEFORE:\n' "$g"
  print_group_proxies "$MIXIN" "$g"
  printf '[%s] AFTER:\n' "$g"
  print_group_proxies "$stage" "$g"
done

if [ "$PRUNE_ALL_SELECTORS" != 1 ]; then
  # Highlight remaining selectors that still reference common subscription-like names.
  # This does not modify anything; it's a hint for the user.
  printf '\n--- Note ---\n'
  printf '%s\n' "Preview mode is conservative by default and does NOT rewrite every selector group."
  printf '%s\n' "If you still see subscription nodes (e.g. V4-*) inside other select groups, rerun with: --prune-all-selectors"
fi

if [ "$DO_APPLY" != 1 ]; then
  printf '\nNOTE: preview only. No files were changed. Use --apply to write changes.\n'
  exit 0
fi

backup="${MIXIN}.bak.$(date +%Y%m%d_%H%M%S)"
cp -f "$MIXIN" "$backup"
cp -f "$stage" "$MIXIN"

printf '\nOK: updated mixin.yaml (backup: %s)\n' "$backup"

if [ "$DO_REBUILD" = 1 ]; then
  echo "Rebuilding runtime + restarting mihomo... (this may briefly interrupt proxy-dependent apps)"
  # Reuse repo merge/sanitize/restart pipeline.
  set +e
  # Avoid printing potentially sensitive info to the terminal; capture logs to a local file.
  mkdir -p "$REPO_DIR/tmp" >/dev/null 2>&1 || true
  rebuild_log="$REPO_DIR/tmp/use_jp_tailscale_only.rebuild.$(date +%Y%m%d_%H%M%S).log"
  ( cd "$REPO_DIR" && bash -c 'set -e; export CLASH_LIB_MODE=1 CLASH_ERROR_MODE=exit; source script/common.sh; source script/clashctl.sh; _merge_sanitize_restart' ) >"$rebuild_log" 2>&1
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    # Some environments may return non-zero even when runtime has been applied; verify via service/API health.
    if bash "$REPO_DIR/script/clash_diagnose.sh" --fast --json >/dev/null 2>&1; then
      echo "WARN: runtime rebuild returned rc=$rc, but service appears healthy"
      echo "      Rebuild log saved to: $rebuild_log"
    else
      echo "ERROR: runtime rebuild failed (rc=$rc). You can restore: $backup" >&2
      echo "Rebuild log saved to: $rebuild_log" >&2
      exit $rc
    fi
  else
    echo "OK: rebuilt runtime"
    echo "Rebuild log saved to: $rebuild_log"
  fi
else
  echo "NOTE: runtime not rebuilt (use --rebuild if you want to restart mihomo)"
fi
