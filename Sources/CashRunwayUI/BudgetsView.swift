import SwiftUI
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

struct BudgetsView: View {
    @Bindable var model: CashRunwayAppModel
    @State private var isBudgetEditorPresented = false
    @State private var draftBudget = Budget(id: UUID(), categoryID: SeedCategories.all.first!.id, monthKey: DateKeys.monthKey(for: .now), limitMinor: 0, isArchived: false, createdAt: .now, updatedAt: .now)
    @State private var instanceDraft: RecurringInstance?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenTitle(title: "Budgets")

                    monthPicker

                    if model.budgets.isEmpty {
                        ContentUnavailableView(
                            "No Budgets",
                            systemImage: "chart.pie.fill",
                            description: Text("Create a monthly category budget to track progress.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(model.budgets) { progress in
                            Button {
                                draftBudget = progress.budget
                                isBudgetEditorPresented = true
                            } label: {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(spacing: 14) {
                                        CategoryGlyph(iconName: progress.category.iconName, colorHex: progress.category.colorHex, size: 52)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(progress.category.name)
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundStyle(CashRunwayTheme.textPrimary)
                                            Text("Limit \(MoneyFormatter.string(from: progress.budget.limitMinor))")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(CashRunwayTheme.textSecondary)
                                        }
                                        Spacer()
                                        Text(MoneyFormatter.string(from: -progress.spentMinor))
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundStyle(progress.remainingMinor < 0 ? CashRunwayTheme.negative : CashRunwayTheme.textPrimary)
                                    }

                                    ProgressView(value: Double(progress.percentUsedBP), total: 10_000)
                                        .tint(progress.remainingMinor < 0 ? CashRunwayTheme.negative : CashRunwayTheme.accent)

                                    Text(progress.remainingMinor < 0 ? "Over budget by \(MoneyFormatter.string(from: abs(progress.remainingMinor)))" : "Remaining \(MoneyFormatter.string(from: progress.remainingMinor))")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(progress.remainingMinor < 0 ? CashRunwayTheme.negative : CashRunwayTheme.textSecondary)
                                }
                                .padding(20)
                                .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Edit") {
                                    draftBudget = progress.budget
                                    isBudgetEditorPresented = true
                                }
                                Button("Archive", role: .destructive) {
                                    model.archiveBudget(progress.budget)
                                }
                            }
                        }
                    }

                    scheduledCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 36)
            }
            .background(CashRunwayTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draftBudget = Budget(
                            id: UUID(),
                            categoryID: model.expenseCategories.first?.id ?? SeedCategories.all.first!.id,
                            monthKey: model.selectedMonthKey,
                            limitMinor: 0,
                            isArchived: false,
                            createdAt: .now,
                            updatedAt: .now
                        )
                        isBudgetEditorPresented = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(CashRunwayTheme.accentDark)
                    }
                }
            }
            .sheet(isPresented: $isBudgetEditorPresented) {
                BudgetEditorView(model: model, budget: $draftBudget)
            }
            .sheet(item: $instanceDraft) { _ in
                if let binding = Binding($instanceDraft) {
                    RecurringInstanceEditorView(model: model, instance: binding, categories: model.expenseCategories + model.incomeCategories)
                }
            }
        }
    }

    private var monthPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(monthOptions, id: \.self) { monthKey in
                    Button {
                        model.selectedMonthKey = monthKey
                        try? model.reloadAll()
                    } label: {
                        Text(CashRunwayTheme.monthAbbreviation(for: monthKey))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(model.selectedMonthKey == monthKey ? .white : CashRunwayTheme.textSecondary)
                            .frame(width: 52, height: 40)
                            .background(
                                Capsule()
                                    .fill(model.selectedMonthKey == monthKey ? CashRunwayTheme.textPrimary : CashRunwayTheme.surface)
                            )
                            .overlay(Capsule().stroke(model.selectedMonthKey == monthKey ? .clear : CashRunwayTheme.line, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var scheduledCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scheduled Transactions")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)

            if model.instances.isEmpty {
                Text("No scheduled occurrences.")
                    .font(.system(size: 15))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            } else {
                ForEach(model.instances.prefix(8)) { instance in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(instance.dueDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.textPrimary)
                            Text(instance.status.rawValue.capitalized)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                        }
                        Spacer()
                        if instance.status == .scheduled {
                            HStack(spacing: 10) {
                                Button("Post") { model.postInstance(instance) }
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(CashRunwayTheme.accentDark, in: Capsule())
                                Button("Skip") { model.skipInstance(instance) }
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(CashRunwayTheme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(CashRunwayTheme.pill, in: Capsule())
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        instanceDraft = instance
                    }
                    if instance.id != model.instances.prefix(8).last?.id {
                        Divider().overlay(CashRunwayTheme.line)
                    }
                }
            }
        }
        .padding(20)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }

    private var monthOptions: [Int] {
        let current = DateKeys.monthKey(for: .now)
        return (0..<6).map { offset in
            let date = Calendar.current.date(byAdding: .month, value: -offset, to: DateKeys.startOfMonth(for: current)) ?? .now
            return DateKeys.monthKey(for: date)
        }
    }
}
