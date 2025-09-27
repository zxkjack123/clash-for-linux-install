#!/usr/bin/env bash
# Update Clash subscription safely, without committing secret URL.
# Usage: SUB_URL='http://host:port/api/v1/client/subscribe?token=xxxx' ./script/update_clash_subscription.sh
# Or: ./script/update_clash_subscription.sh "URL"
set -euo pipefail
URL="${1:-${SUB_URL:-}}"
[ -z "$URL" ] && { echo "Subscription URL required (pass as arg or SUB_URL env)" >&2; exit 1; }
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
HTTP_CODE=$(curl -w '%{http_code}' -fsSL "$URL" -o "$TMP_RAW" || echo 000)
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
  yq e 'tag = "validate"' "$TMP_DECODE" >/dev/null || { echo "YAML parse failed" >&2; exit 3; }
fi
TS=$(date +%Y%m%d_%H%M%S)
if [ -f "$BASE_CFG" ]; then
  cp -f "$BASE_CFG" "$BACKUP_DIR/config_${TS}.yaml"
  echo "[*] Backup saved: $BACKUP_DIR/config_${TS}.yaml"
fi
mv "$TMP_DECODE" "$BASE_CFG"
chmod 600 "$BASE_CFG"
echo "[*] Subscription written to $BASE_CFG"
# Merge with mixin & restart kernel
if [ -f "$ROOT_DIR/script/clashctl.sh" ]; then
  (cd "$ROOT_DIR"; CLASH_LIB_MODE=1 bash -lc '. script/common.sh 2>/dev/null || true; . script/clashctl.sh 2>/dev/null || true; _merge_sanitize_restart' || true)
fi
echo "[*] Done."