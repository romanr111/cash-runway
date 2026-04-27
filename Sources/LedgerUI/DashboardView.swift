import Charts
import SwiftUI
#if canImport(LedgerCore)
import LedgerCore
#endif

struct DashboardView: View {
    @Bindable var model: LedgerAppModel
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
            .background(LedgerTheme.background)
            .toolbar(.hidden, for: .navigationBar)
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
                        .background(LedgerTheme.accent, in: Circle())
                        .shadow(color: LedgerTheme.accent.opacity(0.25), radius: 16, y: 10)
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
                        .foregroundStyle(LedgerTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(LedgerTheme.surface, in: Circle())
                        .overlay(Circle().stroke(LedgerTheme.line, lineWidth: 1))
                }
            }

            VStack(spacing: 6) {
                Text(MoneyFormatter.string(from: model.timelineSnapshot?.heroCashFlowMinor ?? 0))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(LedgerTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Cash Flow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LedgerTheme.textMuted)
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
                ForEach(monthOptions, id: \.self) { monthKey in
                    Button(DateKeys.label(for: monthKey)) {
                        model.selectedMonthKey = monthKey
                        try? model.reloadAll()
                    }
                }
            } label: {
                pillLabel(text: "By months", systemImage: "chevron.down")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Chart(model.timelineSnapshot?.monthlyBars ?? []) { point in
                BarMark(
                    x: .value("Month", LedgerTheme.monthAbbreviation(for: point.monthKey)),
                    y: .value("Income", point.incomeMinor)
                )
                .foregroundStyle(LedgerTheme.accent.gradient)
                .position(by: .value("Series", "Income"))
                .cornerRadius(7)

                BarMark(
                    x: .value("Month", LedgerTheme.monthAbbreviation(for: point.monthKey)),
                    y: .value("Expense", -point.expenseMinor)
                )
                .foregroundStyle(LedgerTheme.negative.opacity(0.9))
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
                                .foregroundStyle(LedgerTheme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(LedgerTheme.chartGrid)
                    AxisValueLabel()
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LedgerTheme.textMuted)
                }
            }
            .chartLegend(.hidden)
            .frame(height: 210)
        }
        .padding(20)
        .background(LedgerTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(LedgerTheme.line, lineWidth: 1))
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
            .foregroundStyle(LedgerTheme.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(LedgerTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(LedgerTheme.line, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var transactionFeed: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let sections = model.timelineSnapshot?.sections, !sections.isEmpty {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(LedgerTheme.dayHeader(for: section.dayKey))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(LedgerTheme.textPrimary)
                            Spacer()
                            Text(MoneyFormatter.string(from: section.totalMinor))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(LedgerTheme.amountColor(section.totalMinor))
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
                                    .overlay(LedgerTheme.line)
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
                .foregroundStyle(LedgerTheme.textPrimary)
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LedgerTheme.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LedgerTheme.pill, in: Capsule())
    }

    private var monthOptions: [Int] {
        model.timelineSnapshot?.monthlyBars.map(\.monthKey) ?? [model.selectedMonthKey]
    }

    private func walletName(for id: UUID) -> String? {
        model.wallets.first(where: { $0.id == id })?.name
    }
}

private enum OverviewChartMetric: String, CaseIterable {
    case wealth = "Total Wealth"
    case cashFlow = "Monthly Cash Flow"
}

private struct TimelineOverviewView: View {
    @Bindable var model: LedgerAppModel
    @State private var chartMetric = OverviewChartMetric.wealth
    @State private var categoryKind: CategoryKind = .expense
    @State private var showsCategoryManagement = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                header
                filters
                monthStrip
                metricPicker
                overviewChart
                categoriesCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(LedgerTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Overview")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LedgerTheme.textPrimary)
            }
        }
        .sheet(isPresented: $showsCategoryManagement) {
            CategoryManagementView(model: model, initialKind: categoryKind)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.overviewSnapshot?.months ?? []) { point in
                    Button {
                        model.selectedMonthKey = point.monthKey
                        try? model.reloadAll()
                    } label: {
                        Text(LedgerTheme.monthAbbreviation(for: point.monthKey))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(point.monthKey == model.selectedMonthKey ? .white : LedgerTheme.textSecondary)
                            .frame(width: 52, height: 40)
                            .background(
                                Capsule()
                                    .fill(point.monthKey == model.selectedMonthKey ? LedgerTheme.textPrimary : LedgerTheme.surface)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(point.monthKey == model.selectedMonthKey ? .clear : LedgerTheme.line, lineWidth: 1)
                            )
                    }
                }
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
                    x: .value("Month", LedgerTheme.monthAbbreviation(for: point.monthKey)),
                    y: .value("Value", plottedValue(for: point))
                )
                .foregroundStyle(LedgerTheme.accent.opacity(0.18))

                LineMark(
                    x: .value("Month", LedgerTheme.monthAbbreviation(for: point.monthKey)),
                    y: .value("Value", plottedValue(for: point))
                )
                .foregroundStyle(LedgerTheme.accent)
                .lineStyle(.init(lineWidth: 3, lineCap: .round))

                if point.monthKey == model.selectedMonthKey {
                    PointMark(
                        x: .value("Month", LedgerTheme.monthAbbreviation(for: point.monthKey)),
                        y: .value("Value", plottedValue(for: point))
                    )
                    .foregroundStyle(LedgerTheme.textPrimary)
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
                                .foregroundStyle(LedgerTheme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(LedgerTheme.chartGrid)
                    AxisValueLabel()
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LedgerTheme.textMuted)
                }
            }
            .chartLegend(.hidden)
            .frame(height: 220)
        }
        .padding(20)
        .background(LedgerTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(LedgerTheme.line, lineWidth: 1))
    }

    private var categoriesCard: some View {
        let categories = (model.overviewSnapshot?.categories ?? []).filter { $0.kind == categoryKind }
        return VStack(alignment: .leading, spacing: 18) {
            Text("Categories")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(LedgerTheme.textPrimary)

            if categories.isEmpty {
                Text("No category totals for this month.")
                    .font(.system(size: 15))
                    .foregroundStyle(LedgerTheme.textSecondary)
            } else {
                Chart(categories.prefix(5)) { item in
                    SectorMark(angle: .value("Amount", item.amountMinor), innerRadius: .ratio(0.58))
                        .foregroundStyle(LedgerTheme.categoryColor(item.colorHex))
                }
                .frame(height: 220)

                ForEach(Array(categories.prefix(5))) { item in
                    HStack(spacing: 14) {
                        CategoryGlyph(iconName: item.iconName, colorHex: item.colorHex, size: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(LedgerTheme.textPrimary)
                            Text("\(item.transactionCount) transactions · \(Int(item.percentage * 100))%")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(LedgerTheme.textSecondary)
                        }
                        Spacer()
                        Text(MoneyFormatter.string(from: categoryKind == .expense ? -item.amountMinor : item.amountMinor))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(categoryKind == .expense ? LedgerTheme.negative : LedgerTheme.positive)
                    }
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
                .foregroundStyle(LedgerTheme.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(LedgerTheme.pill, in: Capsule())
            }
        }
        .padding(20)
        .background(LedgerTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(LedgerTheme.line, lineWidth: 1))
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
                    .foregroundStyle(isSelected ? LedgerTheme.textPrimary : LedgerTheme.textSecondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LedgerTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? LedgerTheme.surface : LedgerTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(isSelected ? LedgerTheme.accent.opacity(0.35) : LedgerTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func kindCard(title: String, value: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? LedgerTheme.textPrimary : LedgerTheme.textSecondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(title == "Expenses" ? LedgerTheme.negative : LedgerTheme.positive)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? LedgerTheme.surface : LedgerTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(isSelected ? LedgerTheme.accent.opacity(0.35) : LedgerTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(LedgerTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(LedgerTheme.pill, in: Capsule())
    }

    private func walletName(for id: UUID) -> String? {
        model.wallets.first(where: { $0.id == id })?.name
    }
}

private struct TimelineSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: LedgerAppModel
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
