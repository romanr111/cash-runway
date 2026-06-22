set shell := ["bash", "-o", "pipefail", "-eu", "-c"]

scheme := "CashRunway"
dest := "platform=iOS Simulator,name=iPhone 17"

graph-bootstrap:
    Scripts/codegraph-bootstrap.sh

graph-init: graph-bootstrap

graph-sync: graph-bootstrap
    codegraph sync

graph-reindex: graph-bootstrap
    codegraph index --force

graph-status: graph-bootstrap
    codegraph status

build:
    xcodebuild -scheme {{scheme}} -sdk iphonesimulator -destination '{{dest}}' clean build 2>&1 | grep -E "(warning:|error:|BUILD SUCCEEDED|BUILD FAILED)"

test *args:
    swift test {{args}}

check-unit-parallel:
    swift test --parallel --filter '(ModelSerializationTests|UtilityAndModelTests|BankCategoryMapperTests|BankConnectionServiceTests|BankSyncServiceTests)'

check-integration:
    swift test --parallel --skip '(ModelSerializationTests|UtilityAndModelTests|BankCategoryMapperTests|BankConnectionServiceTests|BankSyncServiceTests)' --skip CashRunwayPerformanceTests

check-perf:
    Scripts/check-perf.sh

test-isolated *args:
    scratch="$(mktemp -d /tmp/cash-runway-swiftpm.XXXXXX)"; trap 'rm -rf "$scratch"' EXIT; swift test --scratch-path "$scratch" {{args}}

check-isolated:
    scratch="$(mktemp -d /tmp/cash-runway-swiftpm.XXXXXX)"; trap 'rm -rf "$scratch"' EXIT; swift test --scratch-path "$scratch"

test-filter PATTERN:
    swift test --filter {{PATTERN}} 2>&1 | tail -40

lint:
    swiftlint lint --strict

pr-status PR="":
    Scripts/pr-status.sh '{{PR}}'

pr-comment PR FILE:
    Scripts/pr-comment.sh '{{PR}}' '{{FILE}}'

ui-check:
    Scripts/validate-ui-only.sh

check:
    Scripts/agent-validate.sh --all

smoke:
    Scripts/smoke-seeded-simulator.sh

verify:
    just check
    just smoke
