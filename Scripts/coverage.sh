#!/bin/bash
set -euo pipefail

# Cash Runway Local Coverage Script
# Runs tests with code coverage and prints a summary.
#
# Usage:
#   Scripts/coverage.sh                   # full test suite + coverage
#   Scripts/coverage.sh --focused 'Filter'  # targeted tests + coverage
#   Scripts/coverage.sh --minimum 80        # override 85% minimum
#   Scripts/coverage.sh --help              # usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COVERAGE_DIR="$PROJECT_DIR/Coverage"

MINIMUM_PERCENT=85.0
FOCUSED_FILTER=""

show_usage() {
    echo "Usage: $0 [--focused '<filter>'] [--minimum <percent>] [--help]"
    echo ""
    echo "  --focused '<filter>'  Run targeted tests matching filter"
    echo "  --minimum <percent>   Set minimum coverage threshold (default: 85)"
    echo "  --help                Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --focused)
            FOCUSED_FILTER="$2"
            shift 2
            ;;
        --minimum)
            MINIMUM_PERCENT="$2"
            shift 2
            ;;
        --help)
            show_usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_usage
            ;;
    esac
done

cd "$PROJECT_DIR"

echo "==> Cleaning previous coverage data..."
rm -rf "$COVERAGE_DIR"
mkdir -p "$COVERAGE_DIR"

if [[ -n "$FOCUSED_FILTER" ]]; then
    echo "==> Running targeted tests: $FOCUSED_FILTER"
    swift test --filter "$FOCUSED_FILTER" --enable-code-coverage 2>&1 | tee "$COVERAGE_DIR/swift-coverage-test.log"
else
    echo "==> Running full test suite with code coverage..."
    swift test --enable-code-coverage 2>&1 | tee "$COVERAGE_DIR/swift-coverage-test.log"
fi

echo ""
echo "==> Generating coverage summary..."

coverage_path="$(swift test --show-codecov-path)"
cp "${coverage_path}" "$COVERAGE_DIR/coverage.json"

ruby <<RUBY
require "json"

report = JSON.parse(File.read("Coverage/coverage.json"))
minimum_percent = $MINIMUM_PERCENT
source_root = "/Sources/CashRunwayCore/"
files = report.fetch("data").first.fetch("files").select do |file|
  file.fetch("filename").include?(source_root)
end

if files.empty?
  warn "No CashRunwayCore source files found in coverage report"
  exit 1
end

total_lines = files.sum { |file| file.dig("summary", "lines", "count").to_i }
covered_lines = files.sum { |file| file.dig("summary", "lines", "covered").to_i }
percent = total_lines.positive? ? (covered_lines.to_f / total_lines * 100.0) : 0.0

low_files = files
  .select { |file| file.dig("summary", "lines", "count").to_i.positive? }
  .sort_by { |file| [file.dig("summary", "lines", "percent").to_f, -file.dig("summary", "lines", "count").to_i] }
  .first(10)

puts ""
puts "Coverage Summary"
puts "================"
puts "  Total: %.2f%% (minimum: %.2f%%)" % [percent, minimum_percent]
puts "  Covered lines: #{covered_lines} / #{total_lines}"
puts ""

if low_files.any?
  puts "Lowest-covered files:"
  puts "  #{'%-70s' % "File"}  #{'%8s' % "Coverage"}  #{'%6s' % "Covered"}  #{'%6s' % "Total"}"
  puts "  #{'-' * 70}  #{'-' * 8}  #{'-' * 6}  #{'-' * 6}"
  low_files.each do |file|
    lines = file.fetch("summary").fetch("lines")
    relative_path = file.fetch("filename").split("/Cash Runway/").last
    puts "  #{'%-70s' % relative_path}  #{'%7.2f%%' % lines.fetch("percent").to_f}  #{'%6d' % lines.fetch("covered").to_i}  #{'%6d' % lines.fetch("count").to_i}"
  end
  puts ""
end

if percent < minimum_percent
  warn "ERROR: Line coverage %.2f%% is below the %.2f%% minimum." % [percent, minimum_percent]
  exit 1
else
  puts "==> Coverage threshold met: %.2f%% >= %.2f%%" % [percent, minimum_percent]
end
RUBY

echo "==> Coverage report: $COVERAGE_DIR/coverage.json"