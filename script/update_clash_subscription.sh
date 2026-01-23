#!/usr/bin/env bash
# Update Clash subscription safely, without committing secret URL.
# Usage: SUB_URL='http://host:port/api/v1/client/subscribe?token=xxxx' ./script/update_clash_subscription.sh
# Or: ./script/update_clash_subscription.sh "URL"
set -euo pipefail

# Safety-first: preview by default.
APPLY=0
RESTART=0
URL=""

usage() {
  cat <<'EOF'
Update Clash subscription (preview by default)

Usage:
  SUB_URL='https://example/sub?token=***' ./script/update_clash_subscription.sh [--apply] [--restart]
  ./script/update_clash_subscription.sh [--apply] [--restart] <URL>

Options:
  --apply    Write the downloaded subscription into resources/config.yaml (creates a backup)
  --restart  Rebuild+restart kernel after writing (requires --apply)
  -h, --help Show this help

Notes:
  - This script never prints the URL (to avoid leaking tokens), but your shell history may.
  - Network timeouts can be tuned via env:
      CLASH_SUBSCRIPTION_CONNECT_TIMEOUT (default 4)
      CLASH_SUBSCRIPTION_MAX_TIME (default 45)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --restart) RESTART=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [ -z "$URL" ]; then
        URL="$1"; shift
      else
        echo "Unknown arg: $1" >&2
        usage
        exit 2
      fi
      ;;
  esac
done

URL="${URL:-${SUB_URL:-}}"
[ -z "$URL" ] && { echo "Subscription URL required (pass as arg or SUB_URL env)" >&2; exit 1; }

if [ "$RESTART" -eq 1 ] && [ "$APPLY" -ne 1 ]; then
  echo "ERROR: --restart requires --apply (preview mode will not restart)." >&2
  exit 2
fi

CURL_CONNECT_TIMEOUT="${CLASH_SUBSCRIPTION_CONNECT_TIMEOUT:-4}"
CURL_MAX_TIME="${CLASH_SUBSCRIPTION_MAX_TIME:-45}"
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CFG_DIR="$ROOT_DIR/resources"
BASE_CFG="$CFG_DIR/config.yaml"
BACKUP_DIR="$CFG_DIR/backup"
mkdir -p "$BACKUP_DIR"
TMP_RAW=$(mktemp)
TMP_DECODE=$(mktemp)
cleanup() { rm -f "$TMP_RAW" "$TMP_DECODE"; }
trap cleanup EXIT
echo "[*] Fetching subscription..."
HTTP_CODE=$(curl -w '%{http_code}' -fsSL \
  --connect-timeout "$CURL_CONNECT_TIMEOUT" \
  --max-time "$CURL_MAX_TIME" \
  "$URL" -o "$TMP_RAW" || echo 000)
[ "$HTTP_CODE" = 200 ] || { echo "Fetch failed: HTTP $HTTP_CODE" >&2; exit 2; }
RAW_SIZE=$(wc -c < "$TMP_RAW")
# Heuristic: detect base64 (no yaml markers, only base64 charset, length %4==0)
if grep -qE '(^mixed-port:|^port:|^proxies:|^proxy-groups:)' "$TMP_RAW"; then
  cp "$TMP_RAW" "$TMP_DECODE"
else
  if grep -qE '^[A-Za-z0-9+/=]+$' "$TMP_RAW" && [ $((RAW_SIZE % 4)) -eq 0 ]; then
    if base64 -d "$TMP_RAW" > "$TMP_DECODE" 2>/dev/null; then
      :
    else
      cp "$TMP_RAW" "$TMP_DECODE"
    fi
  else
    cp "$TMP_RAW" "$TMP_DECODE"
  fi
fi
# Validate YAML minimally
if command -v yq >/dev/null 2>&1; then
  yq e '.' "$TMP_DECODE" >/dev/null || { echo "YAML parse failed" >&2; exit 3; }
fi
TS=$(date +%Y%m%d_%H%M%S)

if [ "$APPLY" -ne 1 ]; then
  echo "[dry-run] Subscription fetched & validated (raw bytes: $RAW_SIZE, http: $HTTP_CODE)"
  if [ -f "$BASE_CFG" ]; then
    echo "[dry-run] Would backup: $BACKUP_DIR/config_${TS}.yaml"
  fi
  echo "[dry-run] Would write:  $BASE_CFG"
  if [ "$RESTART" -eq 1 ]; then
    echo "[dry-run] Would rebuild+restart kernel"
  fi
  exit 0
fi

if [ -f "$BASE_CFG" ]; then
  cp -f "$BASE_CFG" "$BACKUP_DIR/config_${TS}.yaml"
  echo "[*] Backup saved: $BACKUP_DIR/config_${TS}.yaml"
fi
mv "$TMP_DECODE" "$BASE_CFG"
chmod 600 "$BASE_CFG"
echo "[*] Subscription written to $BASE_CFG"

# Merge with mixin & restart kernel (opt-in)
if [ "$RESTART" -eq 1 ] && [ -f "$ROOT_DIR/script/clashctl.sh" ]; then
  (cd "$ROOT_DIR"; CLASH_LIB_MODE=1 bash -lc '. script/common.sh 2>/dev/null || true; . script/clashctl.sh 2>/dev/null || true; _merge_sanitize_restart' || true)
fi
echo "[*] Done."