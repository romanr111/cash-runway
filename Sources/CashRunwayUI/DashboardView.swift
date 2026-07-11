import Charts
import Foundation
import SwiftUI
import CashRunwayCore

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
                        currencyCode: model.wallets.first?.currencyCode ?? model.defaultCurrencyCode,
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
                    currencyCode: model.defaultCurrencyCode,
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
                    if let cashFlowText = model.aggregateMoneyString(from: model.currentCashFlowMinor) {
                        Text(cashFlowText)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .accessibilityIdentifier(CashRunwayAccessibilityID.timelineCashFlowValue)
                    } else {
                        Text("Mixed-currency cash flow unavailable")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CashRunwayTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
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
                if model.wallets.aggregateCurrencyCode(selectedWalletID: nil) != nil {
                    Button("All Wallets") {
                        Task { await model.selectWallet(nil) }
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.timelineWallet("All Wallets"))
                }
                ForEach(model.wallets) { wallet in
                    Button(wallet.name) {
                        Task { await model.selectWallet(wallet.id) }
                    }
                    .accessibilityIdentifier(CashRunwayAccessibilityID.timelineWallet(wallet.name))
                }
            } label: {
                pillLabel(text: model.selectedWalletID.flatMap(walletName(for:)) ?? L10n.string("All Wallets"), systemImage: "chevron.down")
            }
            .accessibilityIdentifier(CashRunwayAccessibilityID.timelineWalletMenu)

            Menu {
                ForEach(TimelinePeriod.allCases, id: \.self) { period in
                    Button(L10n.timelinePeriod(period)) {
                        model.selectTimelinePeriod(period)
                        Task { await model.reloadAll() }
                    }
                }
            } label: {
                pillLabel(text: L10n.timelinePeriod(model.selectedTimelinePeriod), systemImage: "chevron.down")
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
            if model.wallets.filter({ !$0.isArchived }).count > 1, model.wallets.aggregateCurrencyCode(selectedWalletID: nil) == nil {
                ContentUnavailableView(
                    "Mixed-currency cash flow unavailable",
                    systemImage: "chart.bar",
                    description: Text("Select a single wallet to view the timeline chart.")
                )
                .frame(height: 210)
            } else if bars.isEmpty {
                ContentUnavailableView("No Data", systemImage: "chart.bar")
                    .frame(height: 210)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .bottom, spacing: 16) {
                            ForEach(bars) { bar in
                                let isSelected = bar.periodKey == selectedPeriodKey
                                Button {
                                    guard !isSelected else { return }
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    let newMonthKey = DateKeys.monthKey(fromPeriodKey: bar.periodKey, period: model.selectedTimelinePeriod)
                                    guard newMonthKey != model.selectedMonthKey else { return }
                                    model.selectedMonthKey = newMonthKey
                                    model.reloadTimeline()
                                } label: {
                                    MonthChartColumn(
                                        bar: bar,
                                        period: model.selectedTimelinePeriod,
                                        isSelected: isSelected,
                                        maxValue: maxValue
                                    )
                                    .id(bar.periodKey)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
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
        LazyVStack(alignment: .leading, spacing: 18) {
            if let sections = model.timelineSnapshot?.sections, !sections.isEmpty {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(CashRunwayTheme.dayHeader(for: section.periodKey))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CashRunwayTheme.textPrimary)
                            Spacer()
                            if let sectionTotalText = model.aggregateMoneyString(from: section.totalMinor) {
                                Text(sectionTotalText)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(CashRunwayTheme.amountColor(section.totalMinor))
                            } else {
                                Text("Mixed-currency totals unavailable")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(CashRunwayTheme.textMuted)
                            }
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
        if let loadedDraft = model.loadTransactionDraft(id: item.id) {
            draft = loadedDraft
            isComposerPresented = true
        }
    }
}

private struct MonthChartColumn: View {
    let bar: TimelineBarPoint
    let period: TimelinePeriod
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

    private var displayLabel: String {
        switch period {
        case .month:
            "\(CashRunwayTheme.monthAbbreviation(for: bar.periodKey))\n\(bar.periodKey / 100)"
        case .year:
            "\(bar.periodKey)"
        }
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

            Text(displayLabel)
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
        .accessibilityLabel("\(displayLabel), income \(MoneyFormatter.string(from: bar.incomeMinor)), expense \(MoneyFormatter.string(from: bar.expenseMinor))")
        .accessibilityAddTraits(.isButton)
    }
}

enum OverviewDisplayFormatter {
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

private struct DonutSegmentShape: Shape {
    let startDegrees: Double
    let endDegrees: Double
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = max(outerRadius - thickness, 0)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let adjustedEndDegrees = endDegrees - startDegrees >= 360 ? startDegrees + 359.99 : endDegrees

        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(adjustedEndDegrees),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(adjustedEndDegrees),
            endAngle: .degrees(startDegrees),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

struct CategoryDonutChart: View {
    let distribution: OverviewCategoryDistribution
    let kind: CategoryKind
    let selectedCategory: OverviewCategoryRow?
    let onSelectCategory: (OverviewCategoryRow) -> Void

    private let diameter: CGFloat = 204
    private let thickness: CGFloat = 24
    private let badgeSize: CGFloat = 46
    private let badgeRadius: CGFloat = 92
    private let chartExtent: CGFloat = 250

    var body: some View {
        ZStack {
            Circle()
                .stroke(CashRunwayTheme.pill, lineWidth: thickness)
                .frame(width: diameter, height: diameter)

            ForEach(distribution.segments) { segment in
                let isSelected = segment.category.id == selectedCategory?.id
                DonutSegmentShape(
                    startDegrees: segment.startDegrees,
                    endDegrees: segment.endDegrees,
                    thickness: thickness
                )
                .fill(CashRunwayTheme.categoryColor(segment.category.colorHex))
                .frame(width: diameter, height: diameter)
                .opacity(isSelected ? 1 : 0.42)
                .overlay {
                    DonutSegmentShape(
                        startDegrees: segment.startDegrees,
                        endDegrees: segment.endDegrees,
                        thickness: thickness
                    )
                    .stroke(CashRunwayTheme.surface, lineWidth: 1.5)
                    .frame(width: diameter, height: diameter)
                }
                .scaleEffect(isSelected ? 1.025 : 1)
                .animation(.spring(response: 0.24, dampingFraction: 0.82), value: selectedCategory?.id)
                .contentShape(
                    DonutSegmentShape(
                        startDegrees: segment.startDegrees,
                        endDegrees: segment.endDegrees,
                        thickness: thickness
                    )
                )
                .onTapGesture {
                    onSelectCategory(segment.category)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(BuiltInCategoryDisplayName.name(segment.category)), \(OverviewDisplayFormatter.percentage(segment.category.percentage))")
                .accessibilityAddTraits(.isButton)
            }

            ForEach(badgeSegments) { segment in
                let angle = Angle.degrees(segment.midDegrees)
                let isSelected = segment.category.id == selectedCategory?.id
                CategoryDonutBadge(
                    iconName: segment.category.iconName,
                    colorHex: segment.category.colorHex,
                    size: badgeSize,
                    isSelected: isSelected
                )
                .offset(
                    x: cos(angle.radians) * badgeRadius,
                    y: sin(angle.radians) * badgeRadius
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            centerContent
                .frame(width: 126)
        }
        .frame(width: chartExtent, height: chartExtent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var badgeSegments: [OverviewCategoryDistributionSegment] {
        let selectedSegment = distribution.segments.first { $0.category.id == selectedCategory?.id }
        let candidates = [selectedSegment].compactMap { $0 }
            + distribution.segments.filter { $0.category.percentage >= 0.08 }
        var result: [OverviewCategoryDistributionSegment] = []

        for segment in candidates {
            guard !result.contains(where: { $0.id == segment.id }) else { continue }
            let isSelected = segment.id == selectedSegment?.id
            let hasRoom = result.allSatisfy { angularDistance($0.midDegrees, segment.midDegrees) >= 30 }
            if isSelected || hasRoom {
                result.append(segment)
            }
            if result.count >= 5 { break }
        }

        return result
    }

    private func angularDistance(_ first: Double, _ second: Double) -> Double {
        let rawDifference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(rawDifference, 360 - rawDifference)
    }

    @ViewBuilder
    private var centerContent: some View {
        if let selectedCategory {
            VStack(spacing: 4) {
                Text(BuiltInCategoryDisplayName.name(selectedCategory))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(MoneyFormatter.string(from: signedAmount(selectedCategory.amountMinor)))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(kind == .expense ? CashRunwayTheme.negative : CashRunwayTheme.positive)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(OverviewDisplayFormatter.percentage(selectedCategory.percentage))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
        } else {
            Text(kind == .expense ? L10n.string("No expenses yet") : L10n.string("No income yet"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func signedAmount(_ amountMinor: Int64) -> Int64 {
        kind == .expense ? -amountMinor : amountMinor
    }

private func aggregateValue(for minorUnits: Int64, currencyCode: CurrencyCode?) -> String {
    guard let currencyCode else {
        return L10n.string("Mixed-currency totals unavailable")
    }

    return MoneyFormatter.string(from: minorUnits, currencyCode: currencyCode)
}
}

private struct CategoryDonutBadge: View {
    let iconName: String?
    let colorHex: String?
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        let color = CashRunwayTheme.categoryColor(colorHex)
        ZStack {
            Circle()
                .fill(color)
            Circle()
                .stroke(CashRunwayTheme.surface, lineWidth: 4)
            Image(systemName: CategoryAppearanceCatalog.renderableIconName(iconName))
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(isSelected ? 0.28 : 0.16), radius: isSelected ? 12 : 8, x: 0, y: 6)
        .scaleEffect(isSelected ? 1.08 : 1)
    }
}
