import Foundation
import SwiftUI
import CashRunwayCore

struct TimelineSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var draftQuery = TransactionQuery()
    @State private var usesDateRange = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    TextField("Merchant, note, wallet, label", text: $draftQuery.searchText)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchField)
                }

                Section("Filters") {
                    Picker("Type", selection: Binding(
                        get: { draftQuery.kinds },
                        set: { draftQuery.kinds = $0 }
                    )) {
                        Text("All").tag(Set(TransactionDraft.Kind.allCases))
                        Text("Expenses").tag(Set([TransactionDraft.Kind.expense]))
                        Text("Income").tag(Set([TransactionDraft.Kind.income]))
                        Text("Transfers").tag(Set([TransactionDraft.Kind.transfer]))
                    }

                    Picker("Category", selection: Binding(
                        get: { draftQuery.categoryID },
                        set: { draftQuery.categoryID = $0 }
                    )) {
                        Text("All Categories").tag(UUID?.none)
                        ForEach(model.expenseCategories + model.incomeCategories) { category in
                            Text(BuiltInCategoryDisplayName.name(category)).tag(UUID?.some(category.id))
                        }
                    }

                    Picker("Label", selection: Binding(
                        get: { draftQuery.labelID },
                        set: { draftQuery.labelID = $0 }
                    )) {
                        Text("All Labels").tag(UUID?.none)
                        ForEach(model.labels) { label in
                            Text(label.name).tag(UUID?.some(label.id))
                        }
                    }

                    Toggle("Date range", isOn: $usesDateRange)
                    if usesDateRange {
                        DatePicker("From", selection: Binding(
                            get: { draftQuery.startDate ?? Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now },
                            set: { draftQuery.startDate = $0 }
                        ), displayedComponents: [.date])
                        DatePicker("To", selection: Binding(
                            get: { draftQuery.endDate ?? .now },
                            set: { draftQuery.endDate = $0 }
                        ), displayedComponents: [.date])
                    }
                }
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchCancelButton)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        draftQuery = .init()
                        usesDateRange = false
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchResetButton)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        if !usesDateRange {
                            draftQuery.startDate = nil
                            draftQuery.endDate = nil
                        }
                        draftQuery.walletID = model.selectedWalletID
                        model.transactionQuery = draftQuery
                        Task { await model.reloadAll() }
                        dismiss()
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchApplyButton)
                }
            }
            .onAppear {
                draftQuery = model.transactionQuery
                usesDateRange = draftQuery.startDate != nil || draftQuery.endDate != nil
            }
        }
    }
}
