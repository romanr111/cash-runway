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
    @State private var draft = TransactionDraft(kind: .expense, walletID: UUID(), amountMinor: 0, occurredAt: .now)
    @State private var isWalletEditorPresented = false
    @State private var walletDraft = Wallet(id: UUID(), name: "", kind: .cash, colorHex: "#60788A", iconName: "wallet.pass.fill", startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    if model.hasBootstrapped && model.wallets.isEmpty {
                        emptyState
                    } else {
                        hero
                        filters
                        chartCard
                        overviewButton
                        transactionFeed
                    }
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
                if !model.wallets.isEmpty {
                    Button {
                        if let walletID = model.wallets.first?.id {
                            draft = TransactionDraft(
                                kind: .expense,
                                walletID: walletID,
                                amountMinor: 0,
                                occurredAt: .now,
                                categoryID: model.expenseCategories.first?.id
                            )
                            isComposerPresented = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(CashRunwayTheme.accent, in: Circle())
                            .shadow(color: CashRunwayTheme.accent.opacity(0.25), radius: 16, y: 10)
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.transactionAddButton)
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                }
            }
            .navigationDestination(isPresented: $showsOverview) {
                TimelineOverviewView(model: model)
            }
            .sheet(isPresented: $isSearchPresented) {
                TimelineSearchSheet(model: model)
            }
            .fullScreenCover(isPresented: $isComposerPresented) {
                TransactionEditorView(model: model, draft: $draft)
            }
            .sheet(isPresented: $isWalletEditorPresented) {
                WalletEditorView(model: model, wallet: $walletDraft)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 60)
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 56))
                .foregroundStyle(CashRunwayTheme.textMuted)
            Text("Create your first wallet")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)
            Text("Add a wallet to start tracking transactions and see your cash flow.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(CashRunwayTheme.textSecondary)
                .padding(.horizontal, 24)
            Button {
                walletDraft = Wallet(
                    id: UUID(),
                    name: "",
                    kind: .cash,
                    colorHex: "#60788A",
                    iconName: "wallet.pass.fill",
                    startingBalanceMinor: 0,
                    currentBalanceMinor: 0,
                    isArchived: false,
                    sortOrder: 0,
                    createdAt: .now,
                    updatedAt: .now
                )
                isWalletEditorPresented = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Wallet")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(CashRunwayTheme.accent, in: Capsule())
            }
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
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
                .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchButton)
            }

            VStack(spacing: 6) {
                Group {
                    if model.isTimelineLoading {
                        ProgressView()
                            .controlSize(.regular)
                            .accessibilityLabel("Loading cash flow")
                    } else {
                        Text(MoneyFormatter.string(from: model.currentCashFlowMinor))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .accessibilityIdentifier(CashRunwayAccessibilityID.timelineCashFlowValue)
                    }
                }
                .frame(height: 52)
                .frame(maxWidth: .infinity)
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
                    Task { await model.selectWallet(nil) }
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.timelineWallet("All Wallets"))
                ForEach(model.wallets) { wallet in
                    Button(wallet.name) {
                        Task { await model.selectWallet(wallet.id) }
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.timelineWallet(wallet.name))
                }
            } label: {
                pillLabel(text: model.selectedWalletID.flatMap(walletName(for:)) ?? "All Wallets", systemImage: "chevron.down")
            }
            .accessibilityIdentifier(CashRunwayAccessibilityID.timelineWalletMenu)

            Menu {
                ForEach(TimelinePeriod.allCases, id: \.self) { period in
                    Button(period.displayName) {
                        model.selectTimelinePeriod(period)
                        Task { await model.reloadAll() }
                    }
                }
            } label: {
                pillLabel(text: model.selectedTimelinePeriod.displayName, systemImage: "chevron.down")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var chartCard: some View {
        let bars = model.allBars
        let maxValue = bars.map { max($0.incomeBarMinor, $0.expenseBarMinor) }.max() ?? 0
        let selectedPeriodKey = switch model.selectedTimelinePeriod {
        case .month: model.selectedMonthKey
        case .year: model.selectedMonthKey / 100
        }

        return VStack(alignment: .leading, spacing: 16) {
            if bars.isEmpty {
                ContentUnavailableView("No Data", systemImage: "chart.bar")
                    .frame(height: 210)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .bottom, spacing: 16) {
                            ForEach(bars) { bar in
                                let isSelected = bar.periodKey == selectedPeriodKey
                                MonthChartColumn(
                                    bar: bar,
                                    isSelected: isSelected,
                                    maxValue: maxValue
                                )
                                .id(bar.periodKey)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !isSelected else { return }
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    let newMonthKey = DateKeys.monthKey(fromPeriodKey: bar.periodKey, period: model.selectedTimelinePeriod)
                                    guard newMonthKey != model.selectedMonthKey else { return }
                                    model.selectedMonthKey = newMonthKey
                                    model.reloadTimeline()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(height: 210)
                    .onAppear {
                        proxy.scrollTo(selectedPeriodKey, anchor: .center)
                    }
                    .onChange(of: model.selectedMonthKey) { _, _ in
                        let target = switch model.selectedTimelinePeriod {
                        case .month: model.selectedMonthKey
                        case .year: model.selectedMonthKey / 100
                        }
                        withAnimation(.smooth) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
        .accessibilityIdentifier(CashRunwayAccessibilityID.overviewOpenButton)
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
                                openEditor(for: item)
                            } label: {
                                TransactionRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(CashRunwayAccessibilityID.transactionRow(item))
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

    private func openEditor(for item: TransactionListItem) {
        if let loadedDraft = try? model.repository.transactionDraft(id: item.id) {
            draft = loadedDraft
            isComposerPresented = true
        }
    }
}

private struct MonthChartColumn: View {
    let bar: TimelineBarPoint
    let isSelected: Bool
    let maxValue: Int64

    private var incomeHeight: CGFloat {
        barHeight(for: bar.incomeBarMinor)
    }

    private var expenseHeight: CGFloat {
        barHeight(for: bar.expenseBarMinor)
    }

    private func barHeight(for value: Int64) -> CGFloat {
        guard maxValue > 0 else { return 4 }
        let height = CGFloat(value) / CGFloat(maxValue) * 140
        return max(height, 4)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 5) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(CashRunwayTheme.accent.opacity(isSelected ? 1.0 : 0.75))
                    .frame(width: 16, height: incomeHeight)

                RoundedRectangle(cornerRadius: 4)
                    .fill(CashRunwayTheme.negative.opacity(isSelected ? 0.95 : 0.7))
                    .frame(width: 16, height: expenseHeight)
            }

            Text(bar.xLabel)
                .font(.system(size: isSelected ? 12 : 11, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? CashRunwayTheme.textPrimary : CashRunwayTheme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 50)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? CashRunwayTheme.accent.opacity(0.08) : Color.clear)
        )
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

    static func compactNumber(from minorUnits: Int64) -> String {
        let value = Double(abs(minorUnits)) / 100
        if value >= 1_000_000 {
            return "\(trimmed(value / 1_000_000))M"
        }
        if value >= 1_000 {
            return "\(trimmed(value / 1_000))k"
        }
        return trimmed(value)
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

private struct CategoryDonutChart: View {
    let categories: [OverviewCategoryRow]
    let kind: CategoryKind
    let totalAmountMinor: Int64

    private var centerText: String {
        MoneyFormatter.string(from: kind == .expense ? -totalAmountMinor : totalAmountMinor)
    }

    private var centerSubtext: String {
        kind == .expense ? "Expenses" : "Income"
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let center = CGPoint(x: width / 2, y: height / 2)
            let size = min(width, height)
            let outerRadius = size / 2 - 52
            let innerRadius = outerRadius * 0.55

            ZStack {
                Canvas { context, _ in
                    var startAngle = Angle.degrees(-90)
                    for category in categories {
                        let sweep = Angle.degrees(max(category.percentage / 100.0 * 360.0, 0.5))
                        let endAngle = startAngle + sweep
                        let midAngle = Angle.degrees(startAngle.degrees + sweep.degrees / 2)
                        let color = CashRunwayTheme.categoryColor(category.colorHex)

                        var path = Path()
                        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
                        path.closeSubpath()

                        context.fill(path, with: .color(color))

                        if category.percentage >= 5 {
                            let lineStart = CGPoint(
                                x: center.x + cos(midAngle.radians) * outerRadius,
                                y: center.y + sin(midAngle.radians) * outerRadius
                            )
                            let lineEnd = CGPoint(
                                x: center.x + cos(midAngle.radians) * (outerRadius + 38),
                                y: center.y + sin(midAngle.radians) * (outerRadius + 38)
                            )
                            var linePath = Path()
                            linePath.move(to: lineStart)
                            linePath.addLine(to: lineEnd)
                            context.stroke(linePath, with: .color(color), lineWidth: 1.5)
                        }

                        startAngle = endAngle
                    }
                }

                VStack(spacing: 4) {
                    Text(centerText)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text(centerSubtext)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                }
                .frame(width: innerRadius * 1.8)

                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    let midAngle = midAngleForCategory(at: index, categories: categories)
                    let color = CashRunwayTheme.categoryColor(category.colorHex)

                    let labelRadius = outerRadius + 18
                    let labelX = center.x + cos(midAngle.radians) * labelRadius
                    let labelY = center.y + sin(midAngle.radians) * labelRadius

                    Text(OverviewDisplayFormatter.percentage(category.percentage))
                        .font(.system(size: fontSizeForPercentage(category.percentage), weight: .bold))
                        .foregroundStyle(color)
                        .position(x: labelX, y: labelY)

                    if category.percentage >= 5 {
                        let iconRadius = outerRadius + 38
                        let iconX = center.x + cos(midAngle.radians) * iconRadius
                        let iconY = center.y + sin(midAngle.radians) * iconRadius

                        CategoryGlyph(iconName: category.iconName, colorHex: category.colorHex, size: 34)
                            .position(x: iconX, y: iconY)
                    }
                }
            }
            .frame(width: width, height: height)
        }
    }

    private func midAngleForCategory(at index: Int, categories: [OverviewCategoryRow]) -> Angle {
        var startDegrees = -90.0
        for i in 0..<index {
            startDegrees += max(categories[i].percentage / 100.0 * 360.0, 0.5)
        }
        let sweepDegrees = max(categories[index].percentage / 100.0 * 360.0, 0.5)
        return Angle.degrees(startDegrees + sweepDegrees / 2)
    }

    private func fontSizeForPercentage(_ percentage: Double) -> CGFloat {
        if percentage >= 10 { return 13 }
        if percentage >= 5 { return 12 }
        if percentage >= 2 { return 11 }
        return 9
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
            VStack(spacing: 20) {
                overviewHero
                filters
                monthStrip
                metricPicker
                categoriesCard
                overviewChart
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
        .navigationDestination(item: $selectedCategory) { category in
            CategoryDetailOverviewView(
                model: model,
                category: category,
                monthKey: model.selectedMonthKey,
                walletID: model.selectedWalletID
            )
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
            Text(chartMetric.rawValue)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Menu {
                Button("All Wallets") {
                    model.selectedWalletID = nil
                    Task { await model.reloadAll() }
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
                    metricCard(title: metric.rawValue, value: chartValue(for: metric), isSelected: chartMetric == metric) { chartMetric = metric }
                }
            }

            HStack(spacing: 8) {
                kindCard(title: "Expenses", value: MoneyFormatter.string(from: -(model.overviewSnapshot?.monthExpenseMinor ?? 0)), isSelected: categoryKind == .expense) {
                    categoryKind = .expense
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.overviewExpensesCard)
                kindCard(title: "Income", value: MoneyFormatter.string(from: model.overviewSnapshot?.monthIncomeMinor ?? 0), isSelected: categoryKind == .income) {
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
        let categories = (model.overviewSnapshot?.categories ?? []).filter { $0.kind == categoryKind }
        let topCategories = Array(categories.prefix(5))
        return VStack(alignment: .leading, spacing: 18) {
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

            if categories.isEmpty {
                Text("No category totals for this month.")
                    .font(.system(size: 15))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            } else {
                CategoryDonutChart(
                    categories: categories,
                    kind: categoryKind,
                    totalAmountMinor: categoryKind == .expense
                        ? (model.overviewSnapshot?.monthExpenseMinor ?? 0)
                        : (model.overviewSnapshot?.monthIncomeMinor ?? 0)
                )
                .frame(height: 320)

                VStack(spacing: 14) {
                    ForEach(topCategories) { item in
                        Button {
                            selectedCategory = item
                        } label: {
                            categoryLegendRow(item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.overviewCategory(item.name))
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(transactionCountText(item.transactionCount))
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

private struct CategoryDetailOverviewView: View {
    @Bindable var model: CashRunwayAppModel
    let category: OverviewCategoryRow
    @State private var selectedMonthKey: Int
    @State private var selectedWalletID: UUID?
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
        .fullScreenCover(isPresented: $isComposerPresented) {
            TransactionEditorView(model: model, draft: $draft)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = abs(value.translation.width) > abs(value.translation.height)
                    guard horizontal else { return }
                    let threshold: CGFloat = 50
                    if value.translation.width < -threshold {
                        navigateMonth(by: 1)
                    } else if value.translation.width > threshold {
                        navigateMonth(by: -1)
                    }
                }
        )
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

            HStack(spacing: 0) {
                Button {
                    navigateMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hasPrevMonth ? CashRunwayTheme.textPrimary : CashRunwayTheme.textMuted.opacity(0.3))
                        .frame(width: 44, height: 44)
                }
                .disabled(!hasPrevMonth)
                .buttonStyle(.plain)
                .accessibilityIdentifier(CashRunwayAccessibilityID.overviewMonthPreviousButton)

                Spacer()

                if let prev = prevMonthKey {
                    categoryMonthButton(monthKey: prev, isSelected: false)
                } else {
                    Color.clear.frame(width: 90)
                }

                categoryMonthButton(monthKey: selectedMonthKey, isSelected: true)

                if let next = nextMonthKey, hasNextMonth {
                    categoryMonthButton(monthKey: next, isSelected: false)
                } else {
                    Color.clear.frame(width: 90)
                }

                Spacer()

                Button {
                    if hasNextMonth {
                        navigateMonth(by: 1)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hasNextMonth ? CashRunwayTheme.textPrimary : CashRunwayTheme.textMuted.opacity(0.3))
                        .frame(width: 44, height: 44)
                }
                .disabled(!hasNextMonth)
                .buttonStyle(.plain)
                .accessibilityIdentifier(CashRunwayAccessibilityID.overviewMonthNextButton)
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
                        openEditor(for: item)
                    } label: {
                        TransactionRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.transactionRow(item))
                    if item.id != items.last?.id {
                        Divider()
                            .overlay(CashRunwayTheme.line)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CashRunwayAccessibilityID.overviewCategoryDetailTransactionList)
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

    private var prevMonthKey: Int? {
        DateKeys.calendar.date(byAdding: .month, value: -1, to: DateKeys.startOfMonth(for: selectedMonthKey)).map(DateKeys.monthKey(for:))
    }

    private var nextMonthKey: Int? {
        DateKeys.calendar.date(byAdding: .month, value: 1, to: DateKeys.startOfMonth(for: selectedMonthKey)).map(DateKeys.monthKey(for:))
    }

    private var hasPrevMonth: Bool {
        prevMonthKey != nil
    }

    private var hasNextMonth: Bool {
        (nextMonthKey ?? 0) <= model.maxMonthKey
    }

    private func navigateMonth(by offset: Int) {
        guard let newDate = DateKeys.calendar.date(byAdding: .month, value: offset, to: DateKeys.startOfMonth(for: selectedMonthKey)) else { return }
        let newMonthKey = DateKeys.monthKey(for: newDate)
        guard newMonthKey <= model.maxMonthKey else { return }
        selectedMonthKey = newMonthKey
    }

    private func categoryMonthButton(monthKey: Int, isSelected: Bool) -> some View {
        Button {
            guard !isSelected else { return }
            selectedMonthKey = monthKey
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

    private func openEditor(for item: TransactionListItem) {
        if let loadedDraft = try? model.repository.transactionDraft(id: item.id) {
            draft = loadedDraft
            isComposerPresented = true
        }
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
