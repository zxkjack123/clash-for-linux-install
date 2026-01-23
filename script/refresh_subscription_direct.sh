#!/usr/bin/env bash
# refresh_subscription_direct.sh
# Wrapper that fetches Clash subscription without inheriting proxy env vars.
# Usage:
#   ./script/refresh_subscription_direct.sh
#   SUB_URL="https://..." ./script/refresh_subscription_direct.sh
#   ./script/refresh_subscription_direct.sh "https://..."
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
LOG_FILE="${ROOT_DIR}/.refresh_subscription.log"
RUN_OPTIMIZE_AFTER_REFRESH=${RUN_OPTIMIZE_AFTER_REFRESH:-1}
OPTIMIZE_DELAY=${OPTIMIZE_DELAY:-900}
OPTIMIZE_SCRIPT=${OPTIMIZE_SCRIPT:-${ROOT_DIR}/vpn-tools/optimize_all_network.sh}
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
# Load .env if present (export variables so that CLI overrides still win)
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=../.env
  source "${ENV_FILE}"
  set +a
fi
SUB_URL="${1:-${CLASH_SUBSCRIPTION_URL:-${SUB_URL:-}}}"
if [[ -z "${SUB_URL}" ]]; then
  log "ERROR: SUB_URL/CLASH_SUBSCRIPTION_URL 未设置"
  exit 1
fi
cd "${ROOT_DIR}"
log "Starting proxy-clean subscription refresh"
# Run update script with proxy-related env vars unset.
env -u https_proxy \
    -u http_proxy \
    -u HTTPS_PROXY \
    -u HTTP_PROXY \
    -u all_proxy \
    -u ALL_PROXY \
    -u no_proxy \
    -u NO_PROXY \
    SUB_URL="${SUB_URL}" \
    "${ROOT_DIR}/script/update_clash_subscription.sh"
log "Subscription refresh complete"

if [[ "${RUN_OPTIMIZE_AFTER_REFRESH}" == "1" && -x "${OPTIMIZE_SCRIPT}" ]]; then
  if (( OPTIMIZE_DELAY > 0 )); then
    log "Waiting ${OPTIMIZE_DELAY}s before running full optimization"
    sleep "${OPTIMIZE_DELAY}"
  fi
  log "Starting full optimization: ${OPTIMIZE_SCRIPT}"
  if bash "${OPTIMIZE_SCRIPT}" >>"${LOG_FILE}" 2>&1; then
    log "Full optimization completed"
  else
    log "Full optimization completed with errors (see ${LOG_FILE})"
  fi
else
  log "Skipping full optimization (RUN_OPTIMIZE_AFTER_REFRESH=${RUN_OPTIMIZE_AFTER_REFRESH})"
fi
