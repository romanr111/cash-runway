import Foundation
import SwiftUI
import CashRunwayCore

// DEPRECATED — Budgets feature is de-prioritized. Work stopped; do not modify or add tests until resumed.
struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var budget: Budget
    @State private var limitText = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $budget.categoryID) {
                    ForEach(model.expenseCategories) { category in
                        Text(BuiltInCategoryDisplayName.name(category)).tag(category.id)
                    }
                }
                TextField("Limit", text: $limitText)
                    .keyboardType(.decimalPad)
                Toggle("Archive budget", isOn: $budget.isArchived)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        budget.limitMinor = (try? MoneyFormatter.parseMinorUnits(limitText)) ?? 0
                        budget.updatedAt = .now
                        model.saveBudget(budget)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            limitText = budget.limitMinor == 0 ? "" : MoneyFormatter.plainString(from: budget.limitMinor)
        }
    }
}
