set shell := ["bash", "-o", "pipefail", "-eu", "-c"]

scheme := "CashRunway"
dest := "platform=iOS Simulator,name=iPhone 17"

graph-init:
    codegraph init -i

graph-sync:
    codegraph sync

graph-reindex:
    codegraph index --force

graph-status:
    codegraph status

build:
    xcodebuild -scheme {{scheme}} -sdk iphonesimulator -destination '{{dest}}' clean build 2>&1 | grep -E "(warning:|error:|BUILD SUCCEEDED|BUILD FAILED)"

test *args:
    swift test {{args}}

lint:
    swiftlint lint --strict

ui-check:
    Scripts/validate-ui-only.sh

check:
    Scripts/agent-validate.sh --all
