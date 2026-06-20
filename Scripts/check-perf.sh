#!/usr/bin/env bash
set -euo pipefail

tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"
perf_tmp="${tmp_root}/cash-runway-perf-tests"

case "$perf_tmp" in
    */cash-runway-perf-tests)
        rm -rf "$perf_tmp"
        ;;
    *)
        echo "Refusing to clean unexpected performance temp path: $perf_tmp" >&2
        exit 1
        ;;
esac

trap 'rm -rf "$perf_tmp"' EXIT

swift test --filter CashRunwayPerformanceTests
