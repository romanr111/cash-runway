import CashRunwayCore
import CashRunwayUIVM
import Foundation
import SwiftUI

struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ImportViewModel

    var body: some View {
        NavigationStack {
            Form {
                EmptyView().accessibilityIdentifier(CashRunwayAccessibilityID.csvImportScreen)
                Section("Source") {
                    summaryRow("File", value: viewModel.importFileName)
                    if !viewModel.isImportPreparing, viewModel.importPreparationError == nil {
                        summaryRow("Format", value: presetDisplayName)
                        summaryRow("Rows", value: "\(viewModel.importPreview.totalRows)")
                    }
                }

                if viewModel.isImportPreparing {
                    loadingSection
                } else if let preparationError = viewModel.importPreparationError {
                    Section("Import Error") {
                        Text(preparationError)
                            .foregroundStyle(CashRunwayTheme.negative)
                    }
                } else {
                    if let importResult = viewModel.importResult {
                        resultSection(importResult)
                    } else if let importError = viewModel.importError {
                        Section("Import Error") {
                            Text(importError)
                                .foregroundStyle(CashRunwayTheme.negative)
                        }
                    }

                    if viewModel.isImporting {
                        Section("Importing") {
                            ProgressView("Importing transactions...")
                        }
                    }

        if viewModel.importFormat == .cashRunwayCSV {
                        Section("Detected") {
                            summaryRow("Income / Expense", value: typeSummary)
                            summaryRow("Wallet", value: walletSummary)
                            summaryRow("Categories", value: viewModel.importMapping.categoryColumn == nil ? L10n.string("Fallback category") : L10n.string("Matched or created from CSV names"))
                            summaryRow("Labels", value: viewModel.importMapping.labelsColumn == nil ? L10n.string("Not imported") : L10n.string("Matched to existing names"))
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
                            requiredPicker("Date", selection: $viewModel.importMapping.dateColumn)
                            amountPickers
                        }

                        Section {
                            DisclosureGroup("Advanced Mapping", isExpanded: $viewModel.isAdvancedMappingExpanded) {
                                walletPicker(title: "Fallback Wallet")
                                Picker("Default Kind", selection: $viewModel.importMapping.defaultKind) {
                                    Text("Expense").tag(TransactionDraft.Kind.expense)
                                    Text("Income").tag(TransactionDraft.Kind.income)
                                }
                                optionalPicker("Type", selection: $viewModel.importMapping.typeColumn)
                                optionalPicker("Wallet", selection: $viewModel.importMapping.walletColumn)
                        optionalPicker("Currency", selection: $viewModel.importMapping.currencyColumn)
                        optionalPicker("Merchant", selection: $viewModel.importMapping.merchantColumn)
                        optionalPicker("Note", selection: $viewModel.importMapping.noteColumn)
                        categoryMappingRow
                        optionalPicker("Labels", selection: $viewModel.importMapping.labelsColumn)
                    }
                }
            }

                    Section("Import Scope") {
                        Toggle("Import expenses only", isOn: $viewModel.importExpensesOnly)

                        Text(importScopeMessage)
                            .font(.footnote)
                            .foregroundStyle(CashRunwayTheme.textSecondary)
                    }

                    if !reviewRows.isEmpty {
                        Section("Preview") {
                            ForEach(reviewRows) { row in
                                CSVImportPreviewRowView(row: row)
                                    .padding(.vertical, 4)
                            }
                        }
                    } else if viewModel.importExpensesOnly {
                        Section("Preview") {
                            Text(L10n.string("No expense rows found in the preview."))
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle(L10n.string("Import Bank Statement"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(viewModel.importResult == nil && viewModel.importPreparationError == nil ? L10n.string("Cancel") : L10n.string("Done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.isImportPreparing, viewModel.importPreparationError == nil, viewModel.importResult == nil {
                        Button("Import") {
                            Task { await viewModel.startImport() }
                        }
                        .disabled(!hasRequiredMapping || viewModel.isImporting)
                    }
                }
            }
        }
    }

    private var presetDisplayName: String {
        viewModel.importFormat.displayName
    }

    private var hasRequiredMapping: Bool {
        !viewModel.importMapping.dateColumn.isEmpty && (viewModel.importMapping.amountColumn != nil || viewModel.importMapping.debitColumn != nil || viewModel.importMapping.creditColumn != nil)
    }

    private var requiredMappingTitle: LocalizedStringKey {
        hasRequiredMapping ? "Ready To Import" : "Needs Mapping"
    }

    private var requiredMappingMessage: String {
        hasRequiredMapping ? L10n.string("Required fields are mapped.") : L10n.string("Select a date and amount source.")
    }

    private var defaultKindName: String {
        L10n.transactionKind(viewModel.importMapping.defaultKind)
    }

    private var typeSummary: String {
        if let typeColumn = viewModel.importMapping.typeColumn {
            L10n.string("From %@ column", typeColumn)
        } else {
            L10n.string("Default %@", defaultKindName)
        }
    }

    private var selectedWalletName: String {
        viewModel.wallets.first(where: { $0.id == viewModel.importMapping.walletID })?.name ?? L10n.string("Selected wallet")
    }

    private var walletSummary: String {
        if viewModel.importMapping.walletColumn != nil {
            L10n.string("CSV names; unmatched use %@", selectedWalletName)
        } else {
            L10n.string("All rows use %@", selectedWalletName)
        }
    }

    private var importScopeMessage: String {
        viewModel.importExpensesOnly
            ? L10n.string("Income rows will be skipped.")
            : L10n.string("All supported transactions will be imported.")
    }

    private var boundedPreparationProgress: Double {
        min(max(viewModel.importPreparationProgress, 0.0), 1.0)
    }

    private var amountPickers: some View {
        Group {
            optionalPicker("Amount", selection: Binding(
                get: { viewModel.importMapping.amountColumn },
                set: {
                    viewModel.importMapping.amountColumn = $0
                    if $0 != nil {
                        viewModel.importMapping.debitColumn = nil
                        viewModel.importMapping.creditColumn = nil
                    }
                }
            ))
            optionalPicker("Debit", selection: Binding(
                get: { viewModel.importMapping.debitColumn },
                set: {
                    viewModel.importMapping.debitColumn = $0
                    if $0 != nil { viewModel.importMapping.amountColumn = nil }
                }
            ))
            optionalPicker("Credit", selection: Binding(
                get: { viewModel.importMapping.creditColumn },
                set: {
                    viewModel.importMapping.creditColumn = $0
                    if $0 != nil { viewModel.importMapping.amountColumn = nil }
                }
            ))
        }
    }

    @ViewBuilder
    private var categoryMappingRow: some View {
        switch viewModel.importMapping.categoryMappingDisplayMode(for: viewModel.importFormat) {
        case .autoBankRules:
            summaryRow("Category", value: L10n.string("Auto: MCC / bank rules"))
        case .sourceColumn:
            optionalPicker("Category", selection: $viewModel.importMapping.categoryColumn)
        }
    }

    private var reviewRows: [CSVImportReviewRow] {
        if let preparedRows = try? viewModel.previewPreparedRows(
            data: viewModel.importData,
            mapping: viewModel.importMapping,
            rowFilter: viewModel.rowFilter,
            limit: 3
        ) {
            guard !preparedRows.isEmpty else {
                return viewModel.importExpensesOnly ? [] : fallbackPreviewRows
            }

            return preparedRows.enumerated().map { offset, row in
                let signedAmount = row.draft.kind == .expense ? -row.draft.amountMinor : row.draft.amountMinor
                let fallbackCategoryName = row.rawCategoryName ?? selectedWalletName
                let categoryName = row.categoryID.map {
                    BuiltInCategoryDisplayName.name(id: $0, fallback: fallbackCategoryName)
                } ?? fallbackCategoryName
                let merchant = row.draft.merchant
                let note = row.draft.note
                return CSVImportReviewRow(
                    id: offset,
                    date: row.draft.occurredAt.formatted(date: .numeric, time: .standard),
                    amount: MoneyFormatter.string(from: signedAmount),
                    amountColor: CashRunwayTheme.amountColor(signedAmount),
                    title: merchant.ifEmpty(note.ifEmpty(L10n.string("Uncategorized"))),
                    subtitle: categoryName.ifEmpty(selectedWalletName)
                )
            }
        }

        return fallbackPreviewRows
    }

    private var fallbackPreviewRows: [CSVImportReviewRow] {
        let headerIndex = Dictionary(uniqueKeysWithValues: viewModel.importPreview.headers.enumerated().map { ($1, $0) })
        return viewModel.importPreview.sampleRows.prefix(3).enumerated().map { offset, row in
            let signedAmount = previewAmount(row: row, headerIndex: headerIndex)
            let kind = previewKind(row: row, headerIndex: headerIndex, signedAmount: signedAmount)
            let displayMinor = previewDisplayAmount(signedAmount: signedAmount, kind: kind)
            let rawAmount = firstNonEmptyCell(row, columns: [viewModel.importMapping.amountColumn, viewModel.importMapping.debitColumn, viewModel.importMapping.creditColumn], headerIndex: headerIndex)
            return CSVImportReviewRow(
                id: offset,
                date: cell(row, viewModel.importMapping.dateColumn, headerIndex),
                amount: displayMinor.map(MoneyFormatter.string(from:)) ?? rawAmount,
                amountColor: displayMinor.map(CashRunwayTheme.amountColor) ?? (kind == .income ? CashRunwayTheme.positive : CashRunwayTheme.negative),
                title: firstNonEmptyCell(row, columns: [viewModel.importMapping.categoryColumn, viewModel.importMapping.noteColumn, viewModel.importMapping.merchantColumn], headerIndex: headerIndex).ifEmpty(L10n.string("Uncategorized")),
                subtitle: cell(row, viewModel.importMapping.walletColumn, headerIndex).ifEmpty(selectedWalletName)
            )
        }
    }

    private func resultSection(_ result: CSVImportResult) -> some View {
        Section("Result") {
            if result.insertedTransactions == 0, result.duplicateRows > 0 {
                SwiftUI.Label(L10n.string("No new transactions. This file appears to have already been imported."), systemImage: "checkmark.circle")
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            } else if result.insertedTransactions == 0, result.invalidRows > 0 {
                SwiftUI.Label(L10n.string("No transactions were imported. Review the row errors below."), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(CashRunwayTheme.negative)
            } else if result.insertedTransactions > 0, result.invalidRows > 0 {
                SwiftUI.Label(L10n.string("Imported valid rows. Some rows were skipped because they could not be parsed."), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CashRunwayTheme.positive)
            } else {
                SwiftUI.Label(L10n.string("Imported %d transactions", result.insertedTransactions), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CashRunwayTheme.positive)
            }

            if result.duplicateRows > 0 {
                Text(L10n.string("Skipped duplicates: %d", result.duplicateRows))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            if result.invalidRows > 0 {
                Text(L10n.string("Failed rows: %d", result.invalidRows))
                    .foregroundStyle(CashRunwayTheme.negative)
                ForEach(result.rowErrors) { rowError in
                    Text(L10n.string("Row %d: %@", rowError.rowNumber, rowError.message))
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
                Text(viewModel.importPreparationStatus.ifEmpty(L10n.string("Reading CSV...")))
                    .font(.footnote)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func summaryRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(CashRunwayTheme.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(CashRunwayTheme.textPrimary)
        }
    }

    private func walletPicker(title: LocalizedStringKey) -> some View {
        Picker(selection: $viewModel.importMapping.walletID) {
            ForEach(viewModel.wallets) { wallet in
                Text(wallet.name).tag(wallet.id)
            }
        } label: {
            Text(title)
        }
    }

    private func requiredPicker(_ title: LocalizedStringKey, selection: Binding<String>) -> some View {
        Picker(selection: selection) {
            ForEach(viewModel.importPreview.headers, id: \.self) { header in
                Text(header).tag(header)
            }
        } label: {
            Text(title)
        }
    }

    private func optionalPicker(_ title: LocalizedStringKey, selection: Binding<String?>) -> some View {
        Picker(selection: selection) {
            Text(L10n.string("None")).tag(String?.none)
            ForEach(viewModel.importPreview.headers, id: \.self) { header in
                Text(header).tag(String?.some(header))
            }
        } label: {
            Text(title)
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
        if let amountColumn = viewModel.importMapping.amountColumn {
            return try? MoneyFormatter.parseMinorUnits(cell(row, amountColumn, headerIndex))
        }
        let debit = try? MoneyFormatter.parseMinorUnits(cell(row, viewModel.importMapping.debitColumn, headerIndex))
        let credit = try? MoneyFormatter.parseMinorUnits(cell(row, viewModel.importMapping.creditColumn, headerIndex))
        if let debit, debit != 0 { return -abs(debit) }
        if let credit, credit != 0 { return abs(credit) }
        return nil
    }

    private func previewKind(row: [String], headerIndex: [String: Int], signedAmount: Int64?) -> TransactionDraft.Kind {
        let raw = cell(row, viewModel.importMapping.typeColumn, headerIndex).lowercased()
        if raw == "income" || raw == "inflow" || raw == "credit" {
            return .income
        }
        if raw == "expense" || raw == "outflow" || raw == "debit" {
            return .expense
        }
        if let signedAmount, signedAmount < 0 {
            return .expense
        }
        if let signedAmount, signedAmount > 0, viewModel.importMapping.typeColumn != nil {
            return .income
        }
        return viewModel.importMapping.defaultKind
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
