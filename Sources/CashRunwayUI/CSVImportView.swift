import Foundation
import SwiftUI
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var coordinator: CSVImportCoordinator

    var body: some View {
        NavigationStack {
            Form {
                EmptyView().accessibilityIdentifier(CashRunwayAccessibilityID.csvImportScreen)
                Section("Source") {
                    summaryRow("File", value: coordinator.importFileName)
                    if !coordinator.isImportPreparing, coordinator.importPreparationError == nil {
                        summaryRow("Format", value: presetDisplayName)
                        summaryRow("Rows", value: "\(coordinator.importPreview.totalRows)")
                    }
                }

                if coordinator.isImportPreparing {
                    loadingSection
                } else if let preparationError = coordinator.importPreparationError {
                    Section("Import Error") {
                        Text(preparationError)
                            .foregroundStyle(CashRunwayTheme.negative)
                    }
                } else {
                    if let importResult = coordinator.importResult {
                        resultSection(importResult)
                    } else if let importError = coordinator.importError {
                        Section("Import Error") {
                            Text(importError)
                                .foregroundStyle(CashRunwayTheme.negative)
                        }
                    }

                    if coordinator.isImporting {
                        Section("Importing") {
                            ProgressView("Importing transactions...")
                        }
                    }

                    if coordinator.importPreset == .cashRunwayWallet {
                        Section("Detected") {
                            summaryRow("Income / Expense", value: typeSummary)
                            summaryRow("Wallet", value: walletSummary)
                            summaryRow("Categories", value: coordinator.importMapping.categoryColumn == nil ? "Fallback category" : "Matched or created from CSV names")
                            summaryRow("Labels", value: coordinator.importMapping.labelsColumn == nil ? "Not imported" : "Matched to existing names")
                        }

                        Section {
                            walletPicker(title: "Fallback Wallet")
                        } header: {
                            Text("Import Settings")
                        } footer: {
                            Text("Used when the CSV wallet is empty or does not match an existing wallet.")
                        }
                    } else {
                        Section(requiredMappingTitle) {
                            Text(requiredMappingMessage)
                                .font(.footnote)
                                .foregroundStyle(hasRequiredMapping ? CashRunwayTheme.textSecondary : CashRunwayTheme.negative)
                            requiredPicker("Date", selection: $coordinator.importMapping.dateColumn)
                            amountPickers
                        }

                        Section {
                            DisclosureGroup("Advanced Mapping", isExpanded: $coordinator.isAdvancedMappingExpanded) {
                                walletPicker(title: "Fallback Wallet")
                                Picker("Default Kind", selection: $coordinator.importMapping.defaultKind) {
                                    Text("Expense").tag(TransactionDraft.Kind.expense)
                                    Text("Income").tag(TransactionDraft.Kind.income)
                                }
                                optionalPicker("Type", selection: $coordinator.importMapping.typeColumn)
                                optionalPicker("Wallet", selection: $coordinator.importMapping.walletColumn)
                                optionalPicker("Currency", selection: $coordinator.importMapping.currencyColumn)
                                optionalPicker("Merchant", selection: $coordinator.importMapping.merchantColumn)
                                optionalPicker("Note", selection: $coordinator.importMapping.noteColumn)
                                optionalPicker("Category", selection: $coordinator.importMapping.categoryColumn)
                                optionalPicker("Labels", selection: $coordinator.importMapping.labelsColumn)
                            }
                        }
                    }

                    if !reviewRows.isEmpty {
                        Section("Preview") {
                            ForEach(reviewRows) { row in
                                CSVImportPreviewRowView(row: row)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import CSV")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(coordinator.importResult == nil && coordinator.importPreparationError == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !coordinator.isImportPreparing, coordinator.importPreparationError == nil, coordinator.importResult == nil {
                        Button("Import") {
                            coordinator.startImport()
                        }
                        .disabled(!hasRequiredMapping || coordinator.isImporting)
                    }
                }
            }
        }
    }

    private var presetDisplayName: String {
        coordinator.importPreset == .cashRunwayWallet ? "Cash Runway Wallet CSV" : coordinator.importPreset.rawValue
    }

    private var hasRequiredMapping: Bool {
        !coordinator.importMapping.dateColumn.isEmpty && (coordinator.importMapping.amountColumn != nil || coordinator.importMapping.debitColumn != nil || coordinator.importMapping.creditColumn != nil)
    }

    private var requiredMappingTitle: String {
        hasRequiredMapping ? "Ready To Import" : "Needs Mapping"
    }

    private var requiredMappingMessage: String {
        hasRequiredMapping ? "Required fields are mapped." : "Select a date and amount source."
    }

    private var defaultKindName: String {
        coordinator.importMapping.defaultKind == .income ? "Income" : "Expense"
    }

    private var typeSummary: String {
        if let typeColumn = coordinator.importMapping.typeColumn {
            "From \(typeColumn) column"
        } else {
            "Default \(defaultKindName)"
        }
    }

    private var selectedWalletName: String {
        coordinator.model.wallets.first(where: { $0.id == coordinator.importMapping.walletID })?.name ?? "Selected wallet"
    }

    private var walletSummary: String {
        if coordinator.importMapping.walletColumn != nil {
            "CSV names; unmatched use \(selectedWalletName)"
        } else {
            "All rows use \(selectedWalletName)"
        }
    }

    private var boundedPreparationProgress: Double {
        min(max(coordinator.importPreparationProgress, 0.0), 1.0)
    }

    private var amountPickers: some View {
        Group {
            optionalPicker("Amount", selection: Binding(
                get: { coordinator.importMapping.amountColumn },
                set: {
                    coordinator.importMapping.amountColumn = $0
                    if $0 != nil {
                        coordinator.importMapping.debitColumn = nil
                        coordinator.importMapping.creditColumn = nil
                    }
                }
            ))
            optionalPicker("Debit", selection: Binding(
                get: { coordinator.importMapping.debitColumn },
                set: {
                    coordinator.importMapping.debitColumn = $0
                    if $0 != nil { coordinator.importMapping.amountColumn = nil }
                }
            ))
            optionalPicker("Credit", selection: Binding(
                get: { coordinator.importMapping.creditColumn },
                set: {
                    coordinator.importMapping.creditColumn = $0
                    if $0 != nil { coordinator.importMapping.amountColumn = nil }
                }
            ))
        }
    }

    private var reviewRows: [CSVImportReviewRow] {
        let headerIndex = Dictionary(uniqueKeysWithValues: coordinator.importPreview.headers.enumerated().map { ($1, $0) })
        return coordinator.importPreview.sampleRows.prefix(3).enumerated().map { offset, row in
            let signedAmount = previewAmount(row: row, headerIndex: headerIndex)
            let kind = previewKind(row: row, headerIndex: headerIndex, signedAmount: signedAmount)
            let displayMinor = previewDisplayAmount(signedAmount: signedAmount, kind: kind)
            let rawAmount = firstNonEmptyCell(row, columns: [coordinator.importMapping.amountColumn, coordinator.importMapping.debitColumn, coordinator.importMapping.creditColumn], headerIndex: headerIndex)
            return CSVImportReviewRow(
                id: offset,
                date: cell(row, coordinator.importMapping.dateColumn, headerIndex),
                amount: displayMinor.map(MoneyFormatter.string(from:)) ?? rawAmount,
                amountColor: displayMinor.map(CashRunwayTheme.amountColor) ?? (kind == .income ? CashRunwayTheme.positive : CashRunwayTheme.negative),
                title: firstNonEmptyCell(row, columns: [coordinator.importMapping.categoryColumn, coordinator.importMapping.noteColumn, coordinator.importMapping.merchantColumn], headerIndex: headerIndex).ifEmpty("Uncategorized"),
                subtitle: cell(row, coordinator.importMapping.walletColumn, headerIndex).ifEmpty(selectedWalletName)
            )
        }
    }

    private func resultSection(_ result: CSVImportResult) -> some View {
        Section("Result") {
            if result.insertedTransactions == 0, result.duplicateRows > 0 {
                SwiftUI.Label("No new transactions. This file appears to have already been imported.", systemImage: "checkmark.circle")
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            } else if result.insertedTransactions == 0, result.invalidRows > 0 {
                SwiftUI.Label("No transactions were imported. Review the row errors below.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(CashRunwayTheme.negative)
            } else if result.insertedTransactions > 0, result.invalidRows > 0 {
                SwiftUI.Label("Imported valid rows. Some rows were skipped because they could not be parsed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CashRunwayTheme.positive)
            } else {
                SwiftUI.Label("Imported \(result.insertedTransactions) transactions", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CashRunwayTheme.positive)
            }

            if result.duplicateRows > 0 {
                Text("Skipped duplicates: \(result.duplicateRows)")
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            if result.invalidRows > 0 {
                Text("Failed rows: \(result.invalidRows)")
                    .foregroundStyle(CashRunwayTheme.negative)
                ForEach(result.rowErrors) { rowError in
                    Text("Row \(rowError.rowNumber): \(rowError.message)")
                        .font(.footnote)
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                }
            }
        }
    }

    private var loadingSection: some View {
        Section("Loading") {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: boundedPreparationProgress)
                    .progressViewStyle(.linear)
                Text(coordinator.importPreparationStatus.ifEmpty("Reading CSV..."))
                    .font(.footnote)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(CashRunwayTheme.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(CashRunwayTheme.textPrimary)
        }
    }

    private func walletPicker(title: String) -> some View {
        Picker(title, selection: $coordinator.importMapping.walletID) {
            ForEach(coordinator.model.wallets) { wallet in
                Text(wallet.name).tag(wallet.id)
            }
        }
    }

    private func requiredPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(coordinator.importPreview.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        }
    }

    private func optionalPicker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(String?.none)
            ForEach(coordinator.importPreview.headers, id: \.self) { header in
                Text(header).tag(String?.some(header))
            }
        }
    }

    private func cell(_ row: [String], _ column: String?, _ headerIndex: [String: Int]) -> String {
        guard let column, let index = headerIndex[column], row.indices.contains(index) else { return "" }
        return row[index]
    }

    private func firstNonEmptyCell(_ row: [String], columns: [String?], headerIndex: [String: Int]) -> String {
        columns.lazy.map { cell(row, $0, headerIndex).trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
    }

    private func previewAmount(row: [String], headerIndex: [String: Int]) -> Int64? {
        if let amountColumn = coordinator.importMapping.amountColumn {
            return try? MoneyFormatter.parseMinorUnits(cell(row, amountColumn, headerIndex))
        }
        let debit = try? MoneyFormatter.parseMinorUnits(cell(row, coordinator.importMapping.debitColumn, headerIndex))
        let credit = try? MoneyFormatter.parseMinorUnits(cell(row, coordinator.importMapping.creditColumn, headerIndex))
        if let debit, debit != 0 { return -abs(debit) }
        if let credit, credit != 0 { return abs(credit) }
        return nil
    }

    private func previewKind(row: [String], headerIndex: [String: Int], signedAmount: Int64?) -> TransactionDraft.Kind {
        let raw = cell(row, coordinator.importMapping.typeColumn, headerIndex).lowercased()
        if raw == "income" || raw == "inflow" || raw == "credit" {
            return .income
        }
        if raw == "expense" || raw == "outflow" || raw == "debit" {
            return .expense
        }
        if let signedAmount, signedAmount < 0 {
            return .expense
        }
        if let signedAmount, signedAmount > 0, coordinator.importMapping.typeColumn != nil {
            return .income
        }
        return coordinator.importMapping.defaultKind
    }

    private func previewDisplayAmount(signedAmount: Int64?, kind: TransactionDraft.Kind) -> Int64? {
        guard let signedAmount else { return nil }
        if kind == .expense, signedAmount > 0 {
            return -signedAmount
        }
        if kind == .income, signedAmount < 0 {
            return abs(signedAmount)
        }
        return signedAmount
    }
}

private struct CSVImportReviewRow: Identifiable {
    let id: Int
    let date: String
    let amount: String
    let amountColor: Color
    let title: String
    let subtitle: String
}

private struct CSVImportPreviewRowView: View {
    let row: CSVImportReviewRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                HStack(spacing: 6) {
                    Text(row.date)
                    Text(row.subtitle)
                }
                .font(.footnote)
                .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            Spacer(minLength: 12)
            Text(row.amount)
                .font(.body.weight(.semibold))
                .foregroundStyle(row.amountColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
