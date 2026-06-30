#!/bin/bash
set -euo pipefail

fail() {
  echo "codegraph-bootstrap: $*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || fail "git is not available"
command -v codegraph >/dev/null 2>&1 || fail "codegraph is not available on PATH"

git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git worktree"
git_root_real="$(cd "$git_root" && pwd -P)"
current_dir_real="$(pwd -P)"

if [[ "$current_dir_real" != "$git_root_real" ]]; then
  fail "Run from the git worktree root: $git_root_real"
fi

mkdir -p "$git_root_real/.codegraph"

owner_marker="$git_root_real/.codegraph/worktree-root"

if [[ -f "$git_root_real/.codegraph/codegraph.db" ]]; then
  if [[ ! -f "$owner_marker" ]]; then
    echo "codegraph-bootstrap: existing DB is missing worktree marker; reindexing for current worktree" >&2
    codegraph index --force
    printf '%s\n' "$git_root_real" > "$owner_marker"
  else
    owner_root="$(sed -n '1p' "$owner_marker")"
    owner_root_real="$(cd "$owner_root" 2>/dev/null && pwd -P)" ||
      {
        echo "codegraph-bootstrap: marker points to missing path; reindexing for current worktree" >&2
        codegraph index --force
        printf '%s\n' "$git_root_real" > "$owner_marker"
        owner_root_real="$git_root_real"
      }

    if [[ "$owner_root_real" != "$git_root_real" ]]; then
      echo "codegraph-bootstrap: DB belongs to another worktree; reindexing for current worktree" >&2
      codegraph index --force
      printf '%s\n' "$git_root_real" > "$owner_marker"
    fi
  fi
else
  echo "codegraph-bootstrap: initializing CodeGraph index for $git_root_real"
  codegraph init -i
  printf '%s\n' "$git_root_real" > "$owner_marker"
fi

if ! status_output="$(codegraph status 2>&1)"; then
  printf '%s\n' "$status_output" >&2
  fail "CodeGraph status failed"
fi

printf '%s\n' "$status_output"
