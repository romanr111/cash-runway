# Code Location Guide

This is a navigation aid, not a substitute for `rg -n` and bounded reads.

| Concern | Primary location |
| --- | --- |
| Root navigation, onboarding, lock screen | `Sources/CashRunwayUI/RootView.swift` |
| Dashboard and timeline | `Sources/CashRunwayUI/DashboardView.swift` |
| Editors | `Sources/CashRunwayUI/Editors.swift` |
| Settings and More | `Sources/CashRunwayUI/SettingsView.swift` |
| UI application state | `Sources/CashRunwayUI/AppModel.swift` |
| Database and Keychain | `Sources/CashRunwayCore/DatabaseManager.swift` |
| Repository operations | `Sources/CashRunwayCore/CashRunwayRepository.swift` |
| Models | `Sources/CashRunwayCore/Models.swift` |
| App entry and background tasks | `AppHost/CashRunwayApp.swift` |
| UI-test seeding and runtime | `AppHost/UITestRuntime.swift` |

Verify every path against the current repository before committing.
Use `rg -n` to locate the current symbol and exact line range.
