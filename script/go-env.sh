#!/usr/bin/env bash
# go-env.sh — Configure Go environment for mainland China
#
# This script sets GOPROXY to a fast mirror (goproxy.cn) that proxies the
# upstream Go module registry.  It also configures GONOSUMDB/GONOSUMCHECK
# so that the mirror does not cause checksum-database failures, and
# GONOPROXY for private repos.
#
# Why two layers:
#   1. mixin.yaml DOMAIN rules route golang.org / proxy.golang.org / sum.golang.org
#      through the Clash proxy — this covers go get/install import-path resolution
#      and the occasional fallback to the Go upstream.
#   2. GOPROXY='https://goproxy.cn,direct' uses a domestic Go module mirror as the
#      primary source, which is significantly faster than going through a proxy for
#      every module zip download.
#
# Usage:
#   source script/go-env.sh
#   # or in your shell profile:
#   [ -f /path/to/clash-for-linux-install/script/go-env.sh ] && source /path/to/clash-for-linux-install/script/go-env.sh

set -euo pipefail

echo "==> Configuring Go environment for mainland China..."

export GOPROXY='https://goproxy.cn,direct'
export GONOSUMCHECK='*'
export GONOSUMDB='*'
export GOFLAGS='-mod=mod'

# Allow private repos to bypass the proxy mirror (set your own if needed)
if [ -z "${GONOPROXY:-}" ]; then
    export GONOPROXY=''
fi

echo "    GOPROXY=$GOPROXY"
echo "    GONOSUMCHECK=$GONOSUMCHECK"
echo "    GONOSUMDB=$GONOSUMDB"
echo "    GOFLAGS=$GOFLAGS"

# Quick smoke test — verify the proxy is reachable
if command -v go >/dev/null 2>&1; then
    echo "    Go version: $(go version)"
    if timeout 5 curl -sI --connect-timeout 3 'https://goproxy.cn' >/dev/null 2>&1; then
        echo "    ✅ goproxy.cn reachable"
    else
        echo "    ⚠️  goproxy.cn unreachable — Go module proxy may fail without Clash"
    fi
else
    echo "    ⚠️  go not found in PATH — install Go first"
fi

echo "==> Done. Run 'go env GOPROXY' to verify."
