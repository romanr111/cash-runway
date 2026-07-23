import Foundation
import SwiftUI
import CashRunwayCore
import CashRunwayUIVM

struct TimelineSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    let entryMode: TimelineFilterPresentation.EntryMode

    @State private var draftQuery = TransactionQuery()
    @State private var usesDateRange = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                searchSection
                filterSection
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("Cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchCancelButton)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("Reset")) {
                        applyReset()
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchResetButton)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("Apply")) {
                        applyQuery()
                    }
                    .disabled(!TimelineFilterPresentation.isDateRangeValid(
                        startDate: draftQuery.startDate,
                        endDate: draftQuery.endDate
                    ))
                    .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchApplyButton)
                }
            }
            .onAppear {
                draftQuery = model.transactionQuery
                usesDateRange = draftQuery.startDate != nil || draftQuery.endDate != nil
                if entryMode == .search {
                    isSearchFieldFocused = true
                }
            }
        }
    }

    private var navigationTitle: String {
        switch entryMode {
        case .search: L10n.string("Search")
        case .filters: L10n.string("Filters")
        }
    }

    private var searchSection: some View {
        Section(L10n.string("Search")) {
            HStack(spacing: 12) {
                TextField(
                    L10n.string("Merchant, note, wallet, label"),
                    text: $draftQuery.searchText
                )
                .focused($isSearchFieldFocused)
                .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchField)

                if !draftQuery.searchText.isEmpty {
                    Button {
                        draftQuery.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CashRunwayTheme.textMuted)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel(L10n.string("timeline.search.clear"))
                    .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchClearButton)
                }
            }
        }
    }

    private var filterSection: some View {
        Section(L10n.string("Filters")) {
            Picker(L10n.string("Type"), selection: Binding(
                get: { draftQuery.kinds },
                set: { draftQuery.kinds = $0 }
            )) {
                Text(L10n.string("All")).tag(Set(TransactionDraft.Kind.allCases))
                Text(L10n.string("Expenses")).tag(Set([TransactionDraft.Kind.expense]))
                Text(L10n.string("Income")).tag(Set([TransactionDraft.Kind.income]))
                Text(L10n.string("Transfer")).tag(Set([TransactionDraft.Kind.transfer]))
            }

            Picker(L10n.string("Category"), selection: Binding(
                get: { draftQuery.categoryID },
                set: { draftQuery.categoryID = $0 }
            )) {
                Text(L10n.string("All Categories")).tag(UUID?.none)
                ForEach(model.expenseCategories + model.incomeCategories) { category in
                    Text(BuiltInCategoryDisplayName.name(category)).tag(UUID?.some(category.id))
                }
            }

            Picker(L10n.string("Label"), selection: Binding(
                get: { draftQuery.labelID },
                set: { draftQuery.labelID = $0 }
            )) {
                Text(L10n.string("All Labels")).tag(UUID?.none)
                ForEach(model.labels) { label in
                    Text(label.name).tag(UUID?.some(label.id))
                }
            }

            Toggle(L10n.string("Date range"), isOn: Binding(
                get: { usesDateRange },
                set: { newValue in
                    usesDateRange = newValue
                    if !newValue {
                        draftQuery.startDate = nil
                        draftQuery.endDate = nil
                    }
                }
            ))
            if usesDateRange {
                DatePicker(L10n.string("From"), selection: Binding(
                    get: { draftQuery.startDate ?? .now },
                    set: { draftQuery.startDate = $0 }
                ), displayedComponents: [.date])

                DatePicker(L10n.string("To"), selection: Binding(
                    get: { draftQuery.endDate ?? .now },
                    set: { draftQuery.endDate = $0 }
                ), displayedComponents: [.date])

                if !TimelineFilterPresentation.isDateRangeValid(
                    startDate: draftQuery.startDate,
                    endDate: draftQuery.endDate
                ) {
                    Text(L10n.string("timeline.filter.dateRangeInvalid"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CashRunwayTheme.negative)
                }
            }
        }
    }

    private func applyReset() {
        switch entryMode {
        case .search:
            draftQuery = TimelineFilterPresentation.resetSearch(query: draftQuery)
        case .filters:
            draftQuery = TimelineFilterPresentation.resetFilters(query: draftQuery)
            usesDateRange = false
        }
    }

    private func applyQuery() {
        let applied = TimelineFilterPresentation.apply(
            draft: draftQuery,
            usesDateRange: usesDateRange,
            walletID: model.selectedWalletID
        )
        model.transactionQuery = applied
        Task { await model.reloadAll() }
        dismiss()
    }
}
