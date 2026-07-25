#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "usage: summarize_cash_runway_validation_logs.sh /tmp/cash-runway-agent-validation/<run-id> [...]" >&2
  exit 64
fi

status=0

for dir in "$@"; do
  echo "== ${dir} =="
  if [[ ! -d "$dir" ]]; then
    echo "missing directory"
    status=1
    echo
    continue
  fi

  validation_log="$dir/validation.log"
  if [[ -f "$validation_log" ]]; then
    if grep -qiE "failed|❌|BUILD FAILED|TEST BUILD FAILED" "$validation_log"; then
      echo "validation: failed"
      status=1
    elif grep -q "✅" "$validation_log"; then
      echo "validation: passed"
    else
      echo "validation: present, inconclusive"
    fi
  else
    echo "validation: no validation.log"
  fi

  shopt -s nullglob
  error_logs=("$dir"/errors-found.log)
  if [[ "${#error_logs[@]}" -eq 0 ]]; then
    echo "smoke errors: no errors-found.log"
  else
    for log in "${error_logs[@]}"; do
      if [[ -s "$log" ]]; then
        echo "smoke errors: non-empty $(basename "$log")"
        sed -n '1,20p' "$log"
        status=1
      else
        echo "smoke errors: empty $(basename "$log")"
      fi
    done
  fi
  shopt -u nullglob

  xcode_log="$dir/xcodebuild.log"
  if [[ -f "$xcode_log" ]]; then
    app_icon_count=$(grep -c "AppIcon\\.appiconset.*warning:" "$xcode_log" || true)
    sqlcipher_count=$(grep -c "not stripping binary because it is signed: .*SQLCipher" "$xcode_log" || true)
    appintents_count=$(grep -c "Metadata extraction skipped.*No AppIntents.framework dependency found" "$xcode_log" || true)
    uitest_actor_count=$(grep -c "CashRunwayUITests.*main actor-isolated" "$xcode_log" || true)

    echo "known warnings:"
    echo "  AppIcon size: ${app_icon_count}"
    echo "  SQLCipher signed strip: ${sqlcipher_count}"
    echo "  AppIntents metadata: ${appintents_count}"
    echo "  UI-test main-actor: ${uitest_actor_count}"

    unexpected=$(grep -nE "error:|BUILD FAILED|TEST BUILD FAILED" "$xcode_log" | grep -vE "AppIcon\\.appiconset|Metadata extraction skipped|not stripping binary because it is signed|main actor-isolated" || true)
    if [[ -n "$unexpected" ]]; then
      echo "unexpected build issues:"
      echo "$unexpected" | sed -n '1,30p'
      status=1
    else
      echo "unexpected build issues: none"
    fi
  else
    echo "xcodebuild: no xcodebuild.log"
  fi

  echo
done

exit "$status"
