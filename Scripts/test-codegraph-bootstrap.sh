#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_SCRIPT="$PROJECT_ROOT/Scripts/codegraph-bootstrap.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cash-runway-codegraph-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

make_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init --quiet
}

install_fake_codegraph() {
  local bin_dir="$1"
  local status_project="$2"
  local init_log="$3"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/codegraph" <<'FAKE_CODEGRAPH'
#!/bin/bash
set -euo pipefail

case "${1:-}" in
  init)
    shift
    if [[ "${1:-}" != "-i" ]]; then
      echo "unexpected init args: $*" >&2
      exit 2
    fi
    mkdir -p .codegraph
    : > .codegraph/codegraph.db
    echo "init $(pwd)" >> "$CODEGRAPH_FAKE_INIT_LOG"
    ;;
  status)
    echo "CodeGraph Status"
    echo "Project: $CODEGRAPH_FAKE_STATUS_PROJECT"
    ;;
  *)
    echo "unexpected codegraph command: ${1:-}" >&2
    exit 2
    ;;
esac
FAKE_CODEGRAPH
  chmod +x "$bin_dir/codegraph"

  export PATH="$bin_dir:$PATH"
  export CODEGRAPH_FAKE_STATUS_PROJECT="$status_project"
  export CODEGRAPH_FAKE_INIT_LOG="$init_log"
}

assert_file_exists() {
  if [[ ! -f "$1" ]]; then
    echo "expected file to exist: $1" >&2
    exit 1
  fi
}

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -Fq "$expected" "$file"; then
    echo "expected $file to contain: $expected" >&2
    exit 1
  fi
}

test_initializes_missing_db_for_current_worktree() {
  local repo="$TMP_ROOT/repo-initializes"
  local bin_dir="$TMP_ROOT/bin-initializes"
  local init_log="$TMP_ROOT/init.log"

  make_repo "$repo"
  repo="$(cd "$repo" && pwd -P)"
  install_fake_codegraph "$bin_dir" "$repo" "$init_log"

  (cd "$repo" && "$BOOTSTRAP_SCRIPT") >/tmp/codegraph-bootstrap-test.out

  assert_file_exists "$repo/.codegraph/codegraph.db"
  assert_contains "$init_log" "init $repo"
}

test_rejects_running_from_subdirectory() {
  local repo="$TMP_ROOT/repo-subdir"
  local bin_dir="$TMP_ROOT/bin-subdir"
  local init_log="$TMP_ROOT/subdir-init.log"

  make_repo "$repo"
  repo="$(cd "$repo" && pwd -P)"
  install_fake_codegraph "$bin_dir" "$repo" "$init_log"
  mkdir -p "$repo/subdir"

  if (cd "$repo/subdir" && "$BOOTSTRAP_SCRIPT") >/tmp/codegraph-bootstrap-subdir.out 2>&1; then
    echo "expected bootstrap to fail outside the worktree root" >&2
    exit 1
  fi

  assert_contains /tmp/codegraph-bootstrap-subdir.out "Run from the git worktree root"
}

test_rejects_mismatched_codegraph_project() {
  local repo="$TMP_ROOT/repo-mismatch"
  local other="$TMP_ROOT/other-worktree"
  local bin_dir="$TMP_ROOT/bin-mismatch"
  local init_log="$TMP_ROOT/mismatch-init.log"

  make_repo "$repo"
  mkdir -p "$other"
  other="$(cd "$other" && pwd -P)"
  install_fake_codegraph "$bin_dir" "$other" "$init_log"

  if (cd "$repo" && "$BOOTSTRAP_SCRIPT") >/tmp/codegraph-bootstrap-mismatch.out 2>&1; then
    echo "expected bootstrap to fail for mismatched CodeGraph project" >&2
    exit 1
  fi

  assert_contains /tmp/codegraph-bootstrap-mismatch.out "does not match this worktree"
}

test_initializes_missing_db_for_current_worktree
test_rejects_running_from_subdirectory
test_rejects_mismatched_codegraph_project

echo "CodeGraph bootstrap tests passed"
