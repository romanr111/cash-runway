import Charts
import Foundation
import SwiftUI
#if canImport(CashRunwayCore)
import CashRunwayCore
#endif

struct DashboardView: View {
    @Bindable var model: CashRunwayAppModel
    @State private var isComposerPresented = false
    @State private var isSearchPresented = false
    @State private var showsOverview = false
    @State private var selectedItem: TransactionListItem?
    @State private var draft = TransactionDraft(kind: .expense, walletID: UUID(), amountMinor: 0, occurredAt: .now)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    hero
                    filters
                    chartCard
                    overviewButton
                    transactionFeed
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .background(CashRunwayTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if model.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(CashRunwayTheme.background.opacity(0.72))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    draft = TransactionDraft(
                        kind: .expense,
                        walletID: model.wallets.first?.id ?? UUID(),
                        amountMinor: 0,
                        occurredAt: .now,
                        categoryID: model.expenseCategories.first?.id
                    )
                    isComposerPresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(CashRunwayTheme.accent, in: Circle())
                        .shadow(color: CashRunwayTheme.accent.opacity(0.25), radius: 16, y: 10)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
            .navigationDestination(isPresented: $showsOverview) {
                TimelineOverviewView(model: model)
            }
            .sheet(isPresented: $isSearchPresented) {
                TimelineSearchSheet(model: model)
            }
            .sheet(item: $selectedItem) { item in
                TransactionDetailsView(
                    item: item,
                    model: model,
                    onEdit: {
                        if let loadedDraft = try? model.repository.transactionDraft(id: item.id) {
                            draft = loadedDraft
                            selectedItem = nil
                            isComposerPresented = true
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $isComposerPresented) {
                TransactionEditorView(model: model, draft: $draft)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button {
                    isSearchPresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(CashRunwayTheme.surface, in: Circle())
                        .overlay(Circle().stroke(CashRunwayTheme.line, lineWidth: 1))
                }
            }

            VStack(spacing: 6) {
                Text(MoneyFormatter.string(from: model.timelineSnapshot?.heroCashFlowMinor ?? 0))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Cash Flow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Menu {
                Button("All Wallets") {
                    model.selectedWalletID = nil
                    try? model.reloadAll()
                }
                ForEach(model.wallets) { wallet in
                    Button(wallet.name) {
                        model.selectedWalletID = wallet.id
                        try? model.reloadAll()
                    }
                }
            } label: {
                pillLabel(text: model.selectedWalletID.flatMap(walletName(for:)) ?? "All Wallets", systemImage: "chevron.down")
            }

            Menu {
                ForEach(TimelinePeriod.allCases, id: \.self) { period in
                    Button(period.displayName) {
                        model.selectedTimelinePeriod = period
                        try? model.reloadAll()
                    }
                }
            } label: {
                pillLabel(text: model.selectedTimelinePeriod.displayName, systemImage: "chevron.down")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Chart(model.timelineSnapshot?.bars ?? []) { point in
                BarMark(
                    x: .value("Period", point.xLabel),
                    y: .value("Income", point.incomeBarMinor)
                )
                .foregroundStyle(CashRunwayTheme.accent.gradient)
                .position(by: .value("Series", "Income"))
                .cornerRadius(7)

                BarMark(
                    x: .value("Period", point.xLabel),
                    y: .value("Expense", point.expenseBarMinor)
                )
                .foregroundStyle(CashRunwayTheme.negative.opacity(0.9))
                .position(by: .value("Series", "Expense"))
                .cornerRadius(7)
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
            .frame(height: 210)
        }
        .padding(20)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }

    private var overviewButton: some View {
        Button {
            showsOverview = true
        } label: {
            HStack(spacing: 8) {
                Text("Spending Overview")
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(CashRunwayTheme.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(CashRunwayTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(CashRunwayTheme.line, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var transactionFeed: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let sections = model.timelineSnapshot?.sections, !sections.isEmpty {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.periodLabel)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CashRunwayTheme.textPrimary)
                            Spacer()
                            Text(MoneyFormatter.string(from: section.totalMinor))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.amountColor(section.totalMinor))
                        }
                        ForEach(section.items) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                TransactionRow(item: item)
                            }
                            .buttonStyle(.plain)
                            if item.id != section.items.last?.id {
                                Divider()
                                    .overlay(CashRunwayTheme.line)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "tray",
                    description: Text("Add a transaction or broaden the search filters.")
                )
                .padding(.top, 40)
            }
        }
    }

    private func pillLabel(text: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textPrimary)
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(CashRunwayTheme.pill, in: Capsule())
    }

    private func walletName(for id: UUID) -> String? {
        model.wallets.first(where: { $0.id == id })?.name
    }
}

private enum OverviewChartMetric: String, CaseIterable {
    case wealth = "Total Wealth"
    case cashFlow = "Monthly Cash Flow"
}

private enum OverviewDisplayFormatter {
    static func compactMoney(from minorUnits: Int64) -> String {
        let sign = minorUnits < 0 ? "-" : ""
        let value = Double(abs(minorUnits)) / 100
        if value >= 1_000_000 {
            return "\(sign)₴\(trimmed(value / 1_000_000))M"
        }
        if value >= 1_000 {
            return "\(sign)₴\(trimmed(value / 1_000))k"
        }
        return "\(sign)₴\(trimmed(value))"
    }

    static func percentage(_ value: Double) -> String {
        let percent = value * 100
        if percent > 0, percent < 1 {
            return "<1%"
        }
        return "\(Int(percent.rounded()))%"
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}

private struct TimelineOverviewView: View {
    @Bindable var model: CashRunwayAppModel
    @State private var chartMetric = OverviewChartMetric.wealth
    @State private var categoryKind: CategoryKind = .expense
    @State private var showsCategoryManagement = false
    @State private var selectedCategory: OverviewCategoryRow?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                header
                filters
                monthStrip
                metricPicker
                overviewChart
                categoriesCard
                labelsCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
        .navigationDestination(item: $selectedCategory) { category in
            CategoryDetailOverviewView(
                model: model,
                category: category,
                monthKey: model.selectedMonthKey,
                walletID: model.selectedWalletID
            )
        }
    }

    private var header: some View {
        Color.clear
            .frame(height: 0)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Menu {
                Button("All Wallets") {
                    model.selectedWalletID = nil
                    try? model.reloadAll()
                }
                ForEach(model.wallets) { wallet in
                    Button(wallet.name) {
                        model.selectedWalletID = wallet.id
                        try? model.reloadAll()
                    }
                }
            } label: {
                pill(model.selectedWalletID.flatMap(walletName(for:)) ?? "All Wallets")
            }

            pill("By months")
        }
    }

    private var monthStrip: some View {
        let months = model.overviewSnapshot?.months.map(\.monthKey) ?? [model.selectedMonthKey]
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(months, id: \.self) { monthKey in
                        Button {
                            guard monthKey != model.selectedMonthKey else { return }
                            model.selectedMonthKey = monthKey
                            try? model.reloadSnapshots()
                        } label: {
                            VStack(spacing: 6) {
                                Text(CashRunwayTheme.monthFullLabel(for: monthKey))
                                    .font(.system(size: 14, weight: monthKey == model.selectedMonthKey ? .bold : .medium))
                                    .foregroundStyle(monthKey == model.selectedMonthKey ? CashRunwayTheme.textPrimary : CashRunwayTheme.textMuted)
                                if monthKey == model.selectedMonthKey {
                                    Capsule()
                                        .fill(CashRunwayTheme.accent)
                                        .frame(width: 20, height: 3)
                                } else {
                                    Color.clear.frame(width: 20, height: 3)
                                }
                            }
                            .frame(minWidth: 80)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .id(monthKey)
                    }
                }
                .padding(.horizontal, 20)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let threshold: CGFloat = 40
                        if value.translation.width < -threshold {
                            model.navigateMonth(by: 1)
                        } else if value.translation.width > threshold {
                            model.navigateMonth(by: -1)
                        }
                    }
            )
            .onChange(of: model.selectedMonthKey) { _, new in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(model.selectedMonthKey, anchor: .center)
            }
        }
    }

    private var metricPicker: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(OverviewChartMetric.allCases, id: \.self) { metric in
                    metricCard(title: metric.rawValue, value: chartValue(for: metric), isSelected: chartMetric == metric) {
                        chartMetric = metric
                    }
                }
            }

            HStack(spacing: 12) {
                kindCard(title: "Expenses", value: MoneyFormatter.string(from: -(model.overviewSnapshot?.monthExpenseMinor ?? 0)), isSelected: categoryKind == .expense) {
                    categoryKind = .expense
                }
                kindCard(title: "Income", value: MoneyFormatter.string(from: model.overviewSnapshot?.monthIncomeMinor ?? 0), isSelected: categoryKind == .income) {
                    categoryKind = .income
                }
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
        let categories = (model.overviewSnapshot?.categories ?? []).filter { $0.kind == categoryKind }
        return VStack(alignment: .leading, spacing: 18) {
            Text("Categories")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)

            if categories.isEmpty {
                Text("No category totals for this month.")
                    .font(.system(size: 15))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            } else {
                ZStack {
                    Chart(categories) { item in
                        SectorMark(angle: .value("Amount", item.amountMinor), innerRadius: .ratio(0.58))
                            .foregroundStyle(CashRunwayTheme.categoryColor(item.colorHex))
                    }
                    .chartLegend(.hidden)
                    .frame(height: 220)

                    VStack(spacing: 4) {
                        Text(categoryKind == .expense ? MoneyFormatter.string(from: -(model.overviewSnapshot?.monthExpenseMinor ?? 0)) : MoneyFormatter.string(from: model.overviewSnapshot?.monthIncomeMinor ?? 0))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(categoryKind == .expense ? "Expenses" : "Income")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CashRunwayTheme.textSecondary)
                    }
                    .frame(width: 116)
                }

                ForEach(categories) { item in
                    Button {
                        selectedCategory = item
                    } label: {
                        categoryLegendRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                showsCategoryManagement = true
            } label: {
                HStack {
                    Text("All Categories (\(categories.count))")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(CashRunwayTheme.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(CashRunwayTheme.pill, in: Capsule())
            }
        }
        .padding(20)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
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

    private func categoryLegendRow(_ item: OverviewCategoryRow) -> some View {
        HStack(spacing: 14) {
            CategoryGlyph(iconName: item.iconName, colorHex: item.colorHex, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text("\(transactionCountText(item.transactionCount)) · \(OverviewDisplayFormatter.percentage(item.percentage))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            Spacer()
            Text(MoneyFormatter.string(from: signedAmount(item.amountMinor)))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(categoryKind == .expense ? CashRunwayTheme.negative : CashRunwayTheme.positive)
        }
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
            Text(MoneyFormatter.string(from: signedAmount(item.amountMinor)))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(categoryKind == .expense ? CashRunwayTheme.negative : CashRunwayTheme.positive)
        }
    }

    private func signedAmount(_ amountMinor: Int64) -> Int64 {
        categoryKind == .expense ? -amountMinor : amountMinor
    }

    private func transactionCountText(_ count: Int) -> String {
        count == 1 ? "1 transaction" : "\(count) transactions"
    }

    private func chartValue(for metric: OverviewChartMetric) -> String {
        switch metric {
        case .wealth:
            MoneyFormatter.string(from: model.overviewSnapshot?.totalWealthMinor ?? 0)
        case .cashFlow:
            MoneyFormatter.string(from: model.overviewSnapshot?.monthCashFlowMinor ?? 0)
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

    private func kindCard(title: String, value: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? CashRunwayTheme.textPrimary : CashRunwayTheme.textSecondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(title == "Expenses" ? CashRunwayTheme.negative : CashRunwayTheme.positive)
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

    private func pill(_ text: String) -> some View {
        Text(text)
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

private struct CategoryDetailOverviewView: View {
    @Bindable var model: CashRunwayAppModel
    let category: OverviewCategoryRow
    @State private var selectedMonthKey: Int
    @State private var selectedWalletID: UUID?
    @State private var selectedItem: TransactionListItem?
    @State private var isComposerPresented = false
    @State private var draft: TransactionDraft

    init(model: CashRunwayAppModel, category: OverviewCategoryRow, monthKey: Int, walletID: UUID?) {
        self.model = model
        self.category = category
        _selectedMonthKey = State(initialValue: monthKey)
        _selectedWalletID = State(initialValue: walletID)
        _draft = State(initialValue: TransactionDraft(
            kind: category.kind == .income ? .income : .expense,
            walletID: model.wallets.first?.id ?? UUID(),
            amountMinor: 0,
            occurredAt: .now,
            categoryID: category.id
        ))
    }

    var body: some View {
        let items = transactions
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                filters
                totalHeader(totalMinor: totalMinor(in: items))
                dayChart(items: items)
                transactionList(items: items)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.bottom, 80)
        }
        .background(CashRunwayTheme.background)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in
            TransactionDetailsView(
                item: item,
                model: model,
                onEdit: {
                    if let loadedDraft = try? model.repository.transactionDraft(id: item.id) {
                        draft = loadedDraft
                        selectedItem = nil
                        isComposerPresented = true
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $isComposerPresented) {
            TransactionEditorView(model: model, draft: $draft)
        }
    }

    private var filters: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Menu {
                    Button("All Wallets") {
                        selectedWalletID = nil
                    }
                    ForEach(model.wallets) { wallet in
                        Button(wallet.name) {
                            selectedWalletID = wallet.id
                        }
                    }
                } label: {
                    pill(selectedWalletID.flatMap(walletName(for:)) ?? "All Wallets")
                }
                pill("By months")
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(monthOptions, id: \.self) { monthKey in
                            Button {
                                guard monthKey != selectedMonthKey else { return }
                                selectedMonthKey = monthKey
                            } label: {
                                VStack(spacing: 6) {
                                    Text(CashRunwayTheme.monthFullLabel(for: monthKey))
                                        .font(.system(size: 14, weight: monthKey == selectedMonthKey ? .bold : .medium))
                                        .foregroundStyle(monthKey == selectedMonthKey ? CashRunwayTheme.textPrimary : CashRunwayTheme.textMuted)
                                    if monthKey == selectedMonthKey {
                                        Capsule()
                                            .fill(CashRunwayTheme.accent)
                                            .frame(width: 20, height: 3)
                                    } else {
                                        Color.clear.frame(width: 20, height: 3)
                                    }
                                }
                                .frame(minWidth: 80)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .id(monthKey)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            let threshold: CGFloat = 40
                            if value.translation.width < -threshold {
                                navigateMonth(by: 1)
                            } else if value.translation.width > threshold {
                                navigateMonth(by: -1)
                            }
                        }
                )
                .onChange(of: selectedMonthKey) { _, new in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(selectedMonthKey, anchor: .center)
                }
            }
        }
    }

    private func totalHeader(totalMinor: Int64) -> some View {
        VStack(spacing: 8) {
            CategoryGlyph(iconName: category.iconName, colorHex: category.colorHex, size: 58)
            Text(MoneyFormatter.string(from: signedTotal(totalMinor)))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(category.kind == .expense ? CashRunwayTheme.negative : CashRunwayTheme.positive)
            Text("Total")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func dayChart(items: [TransactionListItem]) -> some View {
        let points = dayPoints(from: items)
        return VStack(alignment: .leading, spacing: 12) {
            Chart(points) { point in
                BarMark(
                    x: .value("Day", dayLabel(for: point.dayKey)),
                    y: .value("Amount", point.amountMinor)
                )
                .foregroundStyle(CashRunwayTheme.categoryColor(category.colorHex))
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.system(size: 11, weight: .semibold))
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
            .frame(height: 250)
        }
    }

    private func transactionList(items: [TransactionListItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Transactions")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)

            if items.isEmpty {
                Text("No transactions for this category and month.")
                    .font(.system(size: 15))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ForEach(items) { item in
                    Button {
                        selectedItem = item
                    } label: {
                        TransactionRow(item: item)
                    }
                    .buttonStyle(.plain)
                    if item.id != items.last?.id {
                        Divider()
                            .overlay(CashRunwayTheme.line)
                    }
                }
            }
        }
    }

    private var transactions: [TransactionListItem] {
        (try? model.repository.transactions(query: transactionQuery, limit: nil)) ?? []
    }

    private var transactionQuery: TransactionQuery {
        TransactionQuery(
            walletID: selectedWalletID,
            categoryID: category.id,
            startDate: DateKeys.startOfMonth(for: selectedMonthKey),
            endDate: monthEnd(for: selectedMonthKey),
            kinds: Set([category.kind == .income ? TransactionDraft.Kind.income : .expense])
        )
    }

    private var monthOptions: [Int] {
        model.overviewSnapshot?.months.map(\.monthKey) ?? [selectedMonthKey]
    }

    private func navigateMonth(by offset: Int) {
        guard let newDate = DateKeys.calendar.date(byAdding: .month, value: offset, to: DateKeys.startOfMonth(for: selectedMonthKey)) else { return }
        let newMonthKey = DateKeys.monthKey(for: newDate)
        guard newMonthKey <= model.maxMonthKey else { return }
        selectedMonthKey = newMonthKey
    }

    private func totalMinor(in items: [TransactionListItem]) -> Int64 {
        items.reduce(into: Int64.zero) { total, item in
            total += abs(item.amountMinor)
        }
    }

    private func signedTotal(_ totalMinor: Int64) -> Int64 {
        category.kind == .expense ? -totalMinor : totalMinor
    }

    private func dayPoints(from items: [TransactionListItem]) -> [CategoryDayPoint] {
        Dictionary(grouping: items, by: \.dayKey)
            .map { dayKey, values in
                CategoryDayPoint(
                    dayKey: dayKey,
                    amountMinor: values.reduce(into: Int64.zero) { $0 += abs($1.amountMinor) }
                )
            }
            .sorted { $0.dayKey < $1.dayKey }
    }

    private func monthEnd(for monthKey: Int) -> Date {
        let start = DateKeys.startOfMonth(for: monthKey)
        return DateKeys.calendar.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-0.001) ?? start
    }

    private func dayLabel(for dayKey: Int) -> String {
        "\(dayKey % 100)"
    }

    private func walletName(for id: UUID) -> String? {
        model.wallets.first(where: { $0.id == id })?.name
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(CashRunwayTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(CashRunwayTheme.pill, in: Capsule())
    }
}

private struct CategoryDayPoint: Identifiable, Hashable {
    var id: Int { dayKey }
    var dayKey: Int
    var amountMinor: Int64
}

private struct TimelineSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var draftQuery = TransactionQuery()
    @State private var usesDateRange = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    TextField("Merchant, note, wallet, label", text: $draftQuery.searchText)
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
                            Text(category.name).tag(UUID?.some(category.id))
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
                    Button("Reset") {
                        draftQuery = .init()
                        usesDateRange = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        if !usesDateRange {
                            draftQuery.startDate = nil
                            draftQuery.endDate = nil
                        }
                        draftQuery.walletID = model.selectedWalletID
                        model.transactionQuery = draftQuery
                        try? model.reloadAll()
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftQuery = model.transactionQuery
                usesDateRange = draftQuery.startDate != nil || draftQuery.endDate != nil
            }
        }
    }
}
