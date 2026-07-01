import Charts
import Foundation
import SwiftUI
import CashRunwayCore

private enum OverviewChartMetric: String, CaseIterable {
    case wealth = "Total Wealth"
    case cashFlow = "Monthly Cash Flow"
}

struct TimelineOverviewView: View {
    @Bindable var model: CashRunwayAppModel
    @State private var chartMetric = OverviewChartMetric.wealth
    @State private var categoryKind: CategoryKind = .expense
    @State private var showsCategoryManagement = false
    @State private var showsAllCategories = false
    @State private var selectedCategoryID: UUID?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                overviewHero
                filters
                monthStrip
                metricPicker
                if model.wallets.filter({ !$0.isArchived }).count > 1, model.wallets.aggregateCurrencyCode(selectedWalletID: nil) == nil {
                    ContentUnavailableView(
                        "Mixed-currency overview unavailable",
                        systemImage: "chart.bar",
                        description: Text("Select a single wallet to view spending charts.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    categoriesCard
                    overviewChart
                }
                labelsCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.bottom, 28)
        }
        .background(CashRunwayTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Overview")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
            }
        }
        .sheet(isPresented: $showsCategoryManagement) {
            CategoryManagementView(model: model, initialKind: categoryKind)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = abs(value.translation.width) > abs(value.translation.height)
                    guard horizontal else { return }
                    let threshold: CGFloat = 50
                    if value.translation.width < -threshold {
                        model.navigateMonth(by: 1)
                    } else if value.translation.width > threshold {
                        model.navigateMonth(by: -1)
                    }
                }
        )
    }

    private var overviewHero: some View {
        VStack(spacing: 6) {
            Text(chartValue(for: chartMetric))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(CashRunwayTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(L10n.string(chartMetric.rawValue))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Menu {
                if model.wallets.aggregateCurrencyCode(selectedWalletID: nil) != nil {
                    Button("All Wallets") {
                        model.selectedWalletID = nil
                        Task { await model.reloadAll() }
                    }
                }
                ForEach(model.wallets) { wallet in
                    Button(wallet.name) {
                        model.selectedWalletID = wallet.id
                        Task { await model.reloadAll() }
                    }
                }
            } label: {
                pill(model.selectedWalletID.flatMap(walletName(for:)) ?? "All Wallets", icon: "wallet.pass")
            }

            pill("By months", icon: "calendar")
        }
    }

    private var monthStrip: some View {
        let calendar = DateKeys.calendar
        let prevMonthKey = calendar.date(byAdding: .month, value: -1, to: DateKeys.startOfMonth(for: model.selectedMonthKey)).map(DateKeys.monthKey(for:))
        let nextMonthKey = calendar.date(byAdding: .month, value: 1, to: DateKeys.startOfMonth(for: model.selectedMonthKey)).map(DateKeys.monthKey(for:))
        let hasNext = (nextMonthKey ?? 0) <= model.maxMonthKey

        return HStack(spacing: 0) {
            Button {
                model.navigateMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(prevMonthKey != nil ? CashRunwayTheme.textPrimary : CashRunwayTheme.textMuted.opacity(0.3))
                    .frame(width: 44, height: 44)
            }
            .disabled(prevMonthKey == nil)
            .buttonStyle(.plain)
            .accessibilityIdentifier(CashRunwayAccessibilityID.overviewMonthPreviousButton)

            Spacer()

            if let prevMonthKey {
                monthButton(monthKey: prevMonthKey, isSelected: false)
            } else {
                Color.clear.frame(width: 80)
            }

            monthButton(monthKey: model.selectedMonthKey, isSelected: true)

            if let nextMonthKey, hasNext {
                monthButton(monthKey: nextMonthKey, isSelected: false)
            } else {
                Color.clear.frame(width: 80)
            }

            Spacer()

            Button {
                if hasNext {
                    model.navigateMonth(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hasNext ? CashRunwayTheme.textPrimary : CashRunwayTheme.textMuted.opacity(0.3))
                    .frame(width: 44, height: 44)
            }
            .disabled(!hasNext)
            .buttonStyle(.plain)
            .accessibilityIdentifier(CashRunwayAccessibilityID.overviewMonthNextButton)
        }
    }

    private func monthButton(monthKey: Int, isSelected: Bool) -> some View {
        Button {
            guard !isSelected else { return }
            model.selectedMonthKey = monthKey
            Task { await model.reloadOverview() }
        } label: {
            VStack(spacing: 6) {
                Text(CashRunwayTheme.monthFullLabel(for: monthKey))
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? CashRunwayTheme.textPrimary : CashRunwayTheme.textMuted)
                if isSelected {
                    Capsule()
                        .fill(CashRunwayTheme.accent)
                        .frame(width: 20, height: 3)
                } else {
                    Color.clear.frame(width: 20, height: 3)
                }
            }
            .frame(minWidth: 90)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var metricPicker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(OverviewChartMetric.allCases, id: \.self) { metric in
                    metricCard(title: L10n.string(metric.rawValue), value: chartValue(for: metric), isSelected: chartMetric == metric) { chartMetric = metric }
                }
            }

            HStack(spacing: 8) {
                kindCard(title: L10n.string("Expenses"), value: aggregateValue(for: -(model.overviewSnapshot?.monthExpenseMinor ?? 0), currencyCode: model.aggregateCurrencyCode), kind: .expense, isSelected: categoryKind == .expense) {
                    categoryKind = .expense
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.overviewExpensesCard)
                kindCard(title: L10n.string("Income"), value: aggregateValue(for: model.overviewSnapshot?.monthIncomeMinor ?? 0, currencyCode: model.aggregateCurrencyCode), kind: .income, isSelected: categoryKind == .income) {
                    categoryKind = .income
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.overviewIncomeCard)
            }
        }
    }

    private var overviewChart: some View {
        let months = model.overviewSnapshot?.months ?? []
        return VStack(alignment: .leading, spacing: 16) {
            Chart(months) { point in
                AreaMark(
                    x: .value("Month", CashRunwayTheme.monthAbbreviation(for: point.monthKey)),
                    y: .value("Value", plottedValue(for: point))
                )
                .foregroundStyle(CashRunwayTheme.accent.opacity(0.18))

                LineMark(
                    x: .value("Month", CashRunwayTheme.monthAbbreviation(for: point.monthKey)),
                    y: .value("Value", plottedValue(for: point))
                )
                .foregroundStyle(CashRunwayTheme.accent)
                .lineStyle(.init(lineWidth: 3, lineCap: .round))

                if point.monthKey == model.selectedMonthKey {
                    PointMark(
                        x: .value("Month", CashRunwayTheme.monthAbbreviation(for: point.monthKey)),
                        y: .value("Value", plottedValue(for: point))
                    )
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .symbolSize(90)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(CashRunwayTheme.chartGrid)
                    AxisValueLabel {
                        if let amount = value.as(Int64.self) {
                            Text(OverviewDisplayFormatter.compactMoney(from: amount))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CashRunwayTheme.textMuted)
                        } else if let amount = value.as(Int.self) {
                            Text(OverviewDisplayFormatter.compactMoney(from: Int64(amount)))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CashRunwayTheme.textMuted)
                        } else if let amount = value.as(Double.self) {
                            Text(OverviewDisplayFormatter.compactMoney(from: Int64(amount)))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CashRunwayTheme.textMuted)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 220)
        }
        .padding(20)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }

    private var categoriesCard: some View {
        let sourceCategories = (model.overviewSnapshot?.categories ?? []).filter { $0.kind == categoryKind }
        let distribution = OverviewCategoryDistributionLayout.distribution(for: sourceCategories)
        let categories = distribution.segments.map(\.category)
        let displayedCategories = OverviewCategoryDisplayLayout.displayedCategories(
            in: categories,
            showsAllCategories: showsAllCategories
        )
        let remainingCategoryCount = max(categories.count - 5, 0)
        let currentSelection = selectedCategory(from: categories, showsAllCategories: showsAllCategories)
        return VStack(alignment: .leading, spacing: 20) {
            categoriesHeader
            categoriesCardContent(
                distribution: distribution,
                categories: categories,
                displayedCategories: displayedCategories,
                currentSelection: currentSelection,
                remainingCategoryCount: remainingCategoryCount
            )
        }
        .padding(20)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
        .onAppear {
            syncSelectedCategoryID(with: categories)
        }
        .onChange(of: categoryKind) { _, _ in
            showsAllCategories = false
            selectedCategoryID = categories.first?.id
        }
        .onChange(of: model.selectedMonthKey) { _, _ in
            showsAllCategories = false
            selectedCategoryID = categories.first?.id
        }
        .onChange(of: model.selectedWalletID) { _, _ in
            showsAllCategories = false
            selectedCategoryID = categories.first?.id
        }
        .onChange(of: categories.map(\.id)) { _, _ in
            syncSelectedCategoryID(with: categories)
        }
    }

    private var categoriesHeader: some View {
        HStack {
            Text("Categories")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)
            Spacer()
            Button {
                showsCategoryManagement = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(CashRunwayTheme.pill, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func categoriesCardContent(
        distribution: OverviewCategoryDistribution,
        categories: [OverviewCategoryRow],
        displayedCategories: [OverviewCategoryRow],
        currentSelection: OverviewCategoryRow?,
        remainingCategoryCount: Int
    ) -> some View {
        if categories.isEmpty {
            CategoryDonutChart(
                distribution: distribution,
                kind: categoryKind,
                selectedCategory: nil
            ) { _ in }
        } else {
            CategoryDonutChart(
                distribution: distribution,
                kind: categoryKind,
                selectedCategory: currentSelection
            ) { category in
                selectCategory(category, from: categories)
            }

            VStack(spacing: 10) {
                ForEach(displayedCategories) { item in
                    Button {
                        selectCategory(item, from: categories)
                    } label: {
                        categoryLegendRow(item, isSelected: item.id == currentSelection?.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.overviewCategory(item.name))
                }
            }

            if remainingCategoryCount > 0 {
                showMoreCategoriesButton(categories: categories, remainingCategoryCount: remainingCategoryCount)
            }
        }
    }

    private func showMoreCategoriesButton(
        categories: [OverviewCategoryRow],
        remainingCategoryCount: Int
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                let nextShowsAllCategories = !showsAllCategories
                showsAllCategories = nextShowsAllCategories
                selectedCategoryID = selectedCategory(
                    from: categories,
                    showsAllCategories: nextShowsAllCategories
                )?.id
            }
        } label: {
            HStack {
                Text(showsAllCategories ? L10n.string("Show Less") : L10n.string("Show More (%d)", remainingCategoryCount))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Image(systemName: showsAllCategories ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(CashRunwayTheme.accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(CashRunwayTheme.accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var labelsCard: some View {
        let labels = (model.overviewSnapshot?.labels ?? []).filter { $0.kind == categoryKind }
        return VStack(alignment: .leading, spacing: 16) {
            Text("Labels")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)

            if labels.isEmpty {
                Text("No label totals for this month.")
                    .font(.system(size: 15))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            } else {
                ForEach(labels) { item in
                    labelLegendRow(item)
                }
            }
        }
        .padding(20)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }

    private func categoryLegendRow(_ item: OverviewCategoryRow, isSelected: Bool) -> some View {
        HStack(spacing: 14) {
            CategoryGlyph(iconName: item.iconName, colorHex: item.colorHex, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(BuiltInCategoryDisplayName.name(item))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(transactionCountText(item.transactionCount)) · \(OverviewDisplayFormatter.percentage(item.percentage))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            Spacer()
            Text(aggregateValue(for: signedAmount(item.amountMinor), currencyCode: model.aggregateCurrencyCode))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(categoryKind == .expense ? CashRunwayTheme.negative : CashRunwayTheme.positive)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 66)
        .background(
            isSelected
                ? CashRunwayTheme.categoryColor(item.colorHex).opacity(0.12)
                : CashRunwayTheme.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isSelected ? CashRunwayTheme.categoryColor(item.colorHex).opacity(0.36) : CashRunwayTheme.line.opacity(0.55),
                    lineWidth: 1
                )
        )
    }

    private func labelLegendRow(_ item: OverviewLabelRow) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(CashRunwayTheme.categoryColor(item.colorHex))
                .frame(width: 18, height: 18)
                .frame(width: 46, height: 46)
                .background(CashRunwayTheme.pill, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text("\(transactionCountText(item.transactionCount)) · \(OverviewDisplayFormatter.percentage(item.percentage))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            Spacer()
            Text(aggregateValue(for: signedAmount(item.amountMinor), currencyCode: model.aggregateCurrencyCode))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(categoryKind == .expense ? CashRunwayTheme.negative : CashRunwayTheme.positive)
        }
    }

    private func signedAmount(_ amountMinor: Int64) -> Int64 {
        categoryKind == .expense ? -amountMinor : amountMinor
    }

    private func selectedCategory(
        from categories: [OverviewCategoryRow],
        showsAllCategories: Bool
    ) -> OverviewCategoryRow? {
        OverviewCategoryDisplayLayout.selectedCategory(
            in: categories,
            selectedCategoryID: selectedCategoryID,
            showsAllCategories: showsAllCategories
        )
    }

    private func syncSelectedCategoryID(with categories: [OverviewCategoryRow]) {
        guard let selected = selectedCategory(from: categories, showsAllCategories: showsAllCategories) else {
            selectedCategoryID = nil
            return
        }
        selectedCategoryID = selected.id
    }

    private func selectCategory(_ category: OverviewCategoryRow, from categories: [OverviewCategoryRow]) {
        if OverviewCategoryDisplayLayout.shouldExpandForSelection(
            categoryID: category.id,
            in: categories,
            showsAllCategories: showsAllCategories
        ) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                showsAllCategories = true
            }
        }
        selectedCategoryID = category.id
    }

    private func transactionCountText(_ count: Int) -> String {
        L10n.transactionCount(count)
    }

    private func chartValue(for metric: OverviewChartMetric) -> String {
        switch metric {
        case .wealth:
            aggregateValue(for: model.overviewSnapshot?.totalWealthMinor ?? 0, currencyCode: model.aggregateCurrencyCode)
        case .cashFlow:
            aggregateValue(for: model.overviewSnapshot?.monthCashFlowMinor ?? 0, currencyCode: model.aggregateCurrencyCode)
        }
    }

    private func plottedValue(for point: OverviewMonthPoint) -> Int64 {
        switch chartMetric {
        case .wealth:
            point.totalWealthMinor
        case .cashFlow:
            point.cashFlowMinor
        }
    }

    private func aggregateValue(for minorUnits: Int64, currencyCode: CurrencyCode?) -> String {
        guard let currencyCode else {
            return L10n.string("Mixed-currency totals unavailable")
        }

        return MoneyFormatter.string(from: minorUnits, currencyCode: currencyCode)
    }

    private func metricCard(title: String, value: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? CashRunwayTheme.textPrimary : CashRunwayTheme.textSecondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? CashRunwayTheme.surface : CashRunwayTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(isSelected ? CashRunwayTheme.accent.opacity(0.35) : CashRunwayTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func kindCard(title: String, value: String, kind: CategoryKind, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? CashRunwayTheme.textPrimary : CashRunwayTheme.textSecondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(kind == .expense ? CashRunwayTheme.negative : CashRunwayTheme.positive)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? CashRunwayTheme.surface : CashRunwayTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(isSelected ? CashRunwayTheme.accent.opacity(0.35) : CashRunwayTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(text)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(CashRunwayTheme.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(CashRunwayTheme.pill, in: Capsule())
    }

    private func walletName(for id: UUID) -> String? {
        model.wallets.first(where: { $0.id == id })?.name
    }
}
