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

test-filter PATTERN:
    swift test --filter {{PATTERN}} 2>&1 | tail -40

lint:
    swiftlint lint --strict

ui-check:
    Scripts/validate-ui-only.sh

check:
    Scripts/agent-validate.sh --all
