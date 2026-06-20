#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source_dir="Sources/CashRunwayCore"
mirror_dir="Modules/CashRunwayCorePackage/Sources/CashRunwayCore"

if [[ ! -d "$source_dir" ]]; then
    echo "Missing source directory: $source_dir" >&2
    exit 1
fi

mkdir -p "$mirror_dir"
rsync -a --delete "${source_dir}/" "${mirror_dir}/"

if diff -rq "$source_dir" "$mirror_dir" > /tmp/cash-runway-mirror-core-diff.log 2>&1; then
    echo "Core mirror synced: $source_dir -> $mirror_dir"
else
    echo "Core mirror sync failed drift check:" >&2
    cat /tmp/cash-runway-mirror-core-diff.log >&2
    exit 1
fi
