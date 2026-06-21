#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source_dir="Sources/CashRunwayCore"
mirror_dir="Modules/CashRunwayCorePackage/Sources/CashRunwayCore"
force=false

usage() {
    echo "Usage: $0 [--force]" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            force=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [[ ! -d "$source_dir" ]]; then
    echo "Missing source directory: $source_dir" >&2
    exit 1
fi

if [[ "$force" == false ]]; then
    mirror_status="$(git status --porcelain -- "$mirror_dir")"
    if [[ -n "$mirror_status" ]]; then
        echo "Refusing to overwrite local package mirror edits:" >&2
        printf '%s\n' "$mirror_status" >&2
        echo "Edit canonical sources in $source_dir, or rerun with --force after reviewing the mirror edits." >&2
        exit 1
    fi
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
