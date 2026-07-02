#!/usr/bin/env bash
# go-env.sh — Optional Go speed-up via domestic mirror
#
# The mixin.yaml proxy rules already route golang.org / proxy.golang.org /
# sum.golang.org / go.dev through the Clash proxy, so Go works out of the box
# with its default GOPROXY='https://proxy.golang.org,direct'.
#
# This script is an OPTIONAL optimisation: it switches GOPROXY to the fast
# Chinese mirror (goproxy.cn), which reduces latency and proxy bandwidth for
# module zip downloads.  Import-path resolution for vanity domains
# (e.g. go.uber.org/multierr) still goes through the proxy.
#
# Usage (optional):
#   source script/go-env.sh

set -euo pipefail

echo "==> Speeding up Go with domestic mirror (optional)..."

export GOPROXY='https://goproxy.cn,direct'
export GONOSUMCHECK='*'
export GONOSUMDB='*'

echo "    GOPROXY=$GOPROXY"
echo "    GONOSUMCHECK=$GONOSUMCHECK"
echo "    GONOSUMDB=$GONOSUMDB"

if command -v go >/dev/null 2>&1; then
    echo "    Go version: $(go version)"
fi

echo "==> Done. 纯代理模式也完全可用（不 source 本脚本即可）。"
