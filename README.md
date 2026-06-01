# Cash Runway

iOS personal finance tracker with cash-flow forecasting, transaction management, CSV/Monobank import, encrypted local storage (GRDB/SQLite), and recurring transaction support.

## Stack

- Swift 6, SwiftUI
- GRDB (SQLite)
- Swift Testing
- Xcode 16

## Requirements

- iOS 18+

## Build & Test

```bash
swift test
xcodebuild -scheme CashRunway -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean build
```
