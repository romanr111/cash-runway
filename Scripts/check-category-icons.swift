#!/usr/bin/env swift
import Foundation

// Cash Runway Category Icon Catalog Validator
// Checks Theme.swift for duplicate non-nil iconNames, required labels, and resolvable SF Symbols.

let projectDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let themePath = projectDir.appendingPathComponent("Sources/CashRunwayUI/Theme.swift")

let requiredLabels: [String] = [
    // Add required labels here when a new use case demands them.
    // Example: "Gas Station"
]

struct IconEntry: Hashable {
    let name: String
    let iconName: String?
}

guard let content = try? String(contentsOf: themePath, encoding: .utf8) else {
    print("❌ Could not read Theme.swift at \(themePath.path)")
    exit(1)
}

var entries: [IconEntry] = []
var inIconsArray = false
var braceDepth = 0

for line in content.components(separatedBy: .newlines) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.contains("static let icons: [CategoryAppearanceChoice] = [") {
        inIconsArray = true
        braceDepth = 1
        continue
    }
    if inIconsArray {
        braceDepth += trimmed.filter { $0 == "[" }.count
        braceDepth -= trimmed.filter { $0 == "]" }.count
        if braceDepth <= 0 {
            inIconsArray = false
            continue
        }
        // Extract name: look for name: "..."
        if let nameRange = trimmed.range(of: #"name:\s*"([^"]*)""#, options: .regularExpression) {
            let matched = String(trimmed[nameRange])
            if let q1 = matched.range(of: "\"")?.upperBound,
               let q2 = matched[q1...].range(of: "\"")?.lowerBound {
                let name = String(matched[q1..<q2])
                var iconName: String?
                if let iconRange = trimmed.range(of: #"iconName:\s*"([^"]*)""#, options: .regularExpression) {
                    let iconMatched = String(trimmed[iconRange])
                    if let iq1 = iconMatched.range(of: "\"")?.upperBound,
                       let iq2 = iconMatched[iq1...].range(of: "\"")?.lowerBound {
                        iconName = String(iconMatched[iq1..<iq2])
                    }
                }
                entries.append(IconEntry(name: name, iconName: iconName))
            }
        }
    }
}

var pass = true

// Check for duplicate non-nil iconName
var seenIconNames: [String: String] = [:]
for entry in entries {
    if let icon = entry.iconName {
        if let existing = seenIconNames[icon] {
            print("❌ Duplicate non-nil iconName '\(icon)' used by '\(existing)' and '\(entry.name)'")
            pass = false
        } else {
            seenIconNames[icon] = entry.name
        }
    }
}

// Check required labels
for label in requiredLabels {
    if !entries.contains(where: { $0.name == label }) {
        print("❌ Required label '\(label)' not found in CategoryAppearanceCatalog.icons")
        pass = false
    }
}

// Check that every non-nil iconName resolves as an SF Symbol
#if canImport(UIKit)
import UIKit
for entry in entries {
    if let icon = entry.iconName {
        if UIImage(systemName: icon) == nil {
            print("❌ SF Symbol '\(icon)' for '\(entry.name)' does not resolve via UIImage(systemName:)")
            pass = false
        }
    }
}
#elseif canImport(AppKit)
import AppKit
for entry in entries {
    if let icon = entry.iconName {
        if NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil {
            print("❌ SF Symbol '\(icon)' for '\(entry.name)' does not resolve via NSImage(systemSymbolName:)")
            pass = false
        }
    }
}
#else
print("⚠️ Skipping live SF Symbol resolution on this platform")
#endif

if pass {
    print("✅ Category icon catalog checks passed (\(entries.count) entries)")
    exit(0)
} else {
    exit(1)
}
