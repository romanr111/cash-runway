import Foundation
import SwiftUI
import CashRunwayCore

struct RecurringTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var template: RecurringTemplate
    @State private var amountText = ""
    @State private var usesEndDate = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    editorHeader(title: "Recurring Template", subtitle: "Define the repeat rule and transaction defaults.", icon: "repeat")
                }
                Picker("Kind", selection: $template.kind) {
                    Text("Expense").tag(RecurringTemplateKind.expense)
                    Text("Income").tag(RecurringTemplateKind.income)
                    Text("Transfer").tag(RecurringTemplateKind.transfer)
                }
                Picker("Wallet", selection: $template.walletID) {
                    ForEach(model.wallets) { wallet in
                        Text(wallet.name).tag(wallet.id)
                    }
                }
                if template.kind == .transfer {
                    Picker("Counterparty", selection: Binding(get: { template.counterpartyWalletID ?? model.wallets.dropFirst().first?.id ?? template.walletID }, set: { template.counterpartyWalletID = $0 })) {
                        ForEach(model.wallets.filter { $0.id != template.walletID }) { wallet in
                            Text(wallet.name).tag(wallet.id)
                        }
                    }
                } else {
                    Picker("Category", selection: Binding(get: { template.categoryID ?? model.expenseCategories.first?.id ?? UUID() }, set: { template.categoryID = $0 })) {
                        ForEach(template.kind == .income ? model.incomeCategories : model.expenseCategories) { category in
                            Text(BuiltInCategoryDisplayName.name(category)).tag(category.id)
                        }
                    }
                }
                TextField("Amount", text: $amountText)
                TextField("Merchant", text: Binding(get: { template.merchant ?? "" }, set: { template.merchant = $0.isEmpty ? nil : $0 }))
                TextField("Note", text: Binding(get: { template.note ?? "" }, set: { template.note = $0.isEmpty ? nil : $0 }))
                Picker("Rule", selection: $template.ruleType) {
                    ForEach(RecurrenceRuleType.allCases, id: \.self) { rule in
                        Text(rule.rawValue.capitalized).tag(rule)
                    }
                }
                Stepper("Interval \(template.ruleInterval)", value: $template.ruleInterval, in: 1...12)
                if template.ruleType == .monthly || template.ruleType == .yearly {
                    Stepper("Day \(template.dayOfMonth ?? 1)", value: Binding(
                        get: { template.dayOfMonth ?? 1 },
                        set: { template.dayOfMonth = $0 }
                    ), in: 1...28)
                }
                if template.ruleType == .weekly {
                    Picker("Weekday", selection: Binding(
                        get: { template.weekday ?? 1 },
                        set: { template.weekday = $0 }
                    )) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                        }
                    }
                }
                DatePicker("Start", selection: $template.startDate, displayedComponents: [.date])
                Toggle("End date", isOn: $usesEndDate)
                if usesEndDate {
                    DatePicker("End", selection: Binding(
                        get: { template.endDate ?? template.startDate },
                        set: { template.endDate = $0 }
                    ), displayedComponents: [.date])
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        template.amountMinor = (try? MoneyFormatter.parseMinorUnits(amountText)) ?? 0
                        template.updatedAt = .now
                        model.saveTemplate(template)
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CashRunwayTheme.background)
        }
        .onAppear {
            amountText = template.amountMinor == 0 ? "" : MoneyFormatter.plainString(from: template.amountMinor)
            usesEndDate = template.endDate != nil
        }
    }

    private func editorHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.accentDark)
                .frame(width: 48, height: 48)
                .background(CashRunwayTheme.accentMuted, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(CashRunwayTheme.headingFont)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text(subtitle)
                    .font(CashRunwayTheme.bodyFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct RecurringInstanceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var instance: RecurringInstance
    let categories: [CashRunwayCategory]
    @State private var amountText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    editorHeader(title: "Occurrence", subtitle: "Adjust this scheduled instance only.", icon: "calendar.badge.clock")
                }
                DatePicker("Due Date", selection: $instance.dueDate, displayedComponents: [.date])
                Picker("Status", selection: $instance.status) {
                    ForEach(RecurringInstanceStatus.allCases, id: \.self) { status in
                        Text(status.rawValue.capitalized).tag(status)
                    }
                }
                TextField("Override Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                Picker("Override Category", selection: Binding(
                    get: { instance.overrideCategoryID },
                    set: { instance.overrideCategoryID = $0 }
                )) {
                    Text("Keep Template Category").tag(UUID?.none)
                    ForEach(categories) { category in
                        Text(BuiltInCategoryDisplayName.name(category)).tag(UUID?.some(category.id))
                    }
                }
                TextField("Override Merchant", text: Binding(
                    get: { instance.overrideMerchant ?? "" },
                    set: { instance.overrideMerchant = $0.isEmpty ? nil : $0 }
                ))
                TextField("Override Note", text: Binding(
                    get: { instance.overrideNote ?? "" },
                    set: { instance.overrideNote = $0.isEmpty ? nil : $0 }
                ))
            }
            .navigationTitle("Occurrence")
            .scrollContentBackground(.hidden)
            .background(CashRunwayTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        instance.overrideAmountMinor = amountText.isEmpty ? nil : (try? MoneyFormatter.parseMinorUnits(amountText))
                        instance.dayKey = DateKeys.dayKey(for: instance.dueDate)
                        instance.updatedAt = .now
                        if instance.status == .scheduled, instance.dueDate != Calendar.current.startOfDay(for: instance.dueDate) {
                            instance.status = .postponed
                        }
                        model.saveInstance(instance)
                        dismiss()
                    }
                }
            }
            .onAppear {
                amountText = instance.overrideAmountMinor.map(MoneyFormatter.plainString(from:)) ?? ""
            }
        }
    }

    private func editorHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.accentDark)
                .frame(width: 48, height: 48)
                .background(CashRunwayTheme.accentMuted, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(CashRunwayTheme.headingFont)
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text(subtitle)
                    .font(CashRunwayTheme.bodyFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
        }
        .padding(.vertical, 6)
    }
}
