#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <pr-number-or-url> <markdown-file>" >&2
}

if [[ $# -ne 2 ]]; then
    usage
    exit 2
fi

pr="$1"
body_file="$2"

if [[ ! -f "$body_file" ]]; then
    echo "Comment body file not found: $body_file" >&2
    exit 1
fi

if [[ ! -s "$body_file" ]]; then
    echo "Comment body file is empty: $body_file" >&2
    exit 1
fi

gh pr comment "$pr" --body-file "$body_file"
