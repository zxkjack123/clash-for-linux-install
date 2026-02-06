#!/usr/bin/env bash
# run_static_gates.sh
#
# Local "static gate" runner for common reliability lint checks.
#
# Gates currently included:
#   1) curl block audit (timeouts, curl|jq under pipefail, webhook POST)
#   2) errexit arithmetic trap audit: ((var++))/((var--)) under set -e
#   3) JSON stdout purity audit: JSON mode should keep stdout machine-readable

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

python3 script/audit_curl_blocks.py --strict
python3 script/audit_errexit_arith.py --strict
python3 script/audit_json_stdout_purity.py --strict

echo "OK: all static gates passed" >&2
