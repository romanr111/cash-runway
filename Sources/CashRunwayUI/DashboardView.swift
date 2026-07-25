import CashRunwayCore
import CashRunwayUIVM
import Charts
import Foundation
import SwiftUI

struct DashboardView: View {
    @Bindable var model: CashRunwayAppModel
    @State private var isComposerPresented = false
    @State private var isSearchPresented = false
    @State private var isFiltersPresented = false
    @State private var isPeriodPickerPresented = false
    @State private var showsOverview = false
    @State private var draft = TransactionDraft(kind: .expense, walletID: UUID(), amountMinor: 0, occurredAt: .now)
    @State private var isWalletEditorPresented = false
    @State private var walletDraft = Wallet(id: UUID(), name: "", kind: .cash, colorHex: "#60788A", iconName: "wallet.pass.fill", startingBalanceMinor: 0, currentBalanceMinor: 0, isArchived: false, sortOrder: 0, createdAt: .now, updatedAt: .now)
    @State private var collapsedDayKeys: Set<Int> = []

    private var presentation: TimelinePresentation {
        TimelinePresentation(
            snapshot: model.timelineSnapshot,
            allBars: model.allBars,
            currencyCode: model.aggregateCurrencyCode,
            locale: L10n.locale
        )
    }

    private var filterPresentation: TimelineFilterPresentation {
        TimelineFilterPresentation(query: model.transactionQuery)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if model.hasBootstrapped && model.wallets.isEmpty {
                        emptyState
                    } else {
                        timelineHeader
                        summaryCard
                        filters
                        transactionFeed
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 140)
            }
            .background(CashRunwayTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                if !model.wallets.isEmpty {
                    addButton
                }
            }
            .overlay {
                if model.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(CashRunwayTheme.background.opacity(0.72))
                }
            }
            .navigationDestination(isPresented: $showsOverview) {
                TimelineOverviewView(model: model)
            }
            .sheet(isPresented: $isSearchPresented) {
                TimelineSearchSheet(model: model, entryMode: .search)
            }
            .sheet(isPresented: $isFiltersPresented) {
                TimelineSearchSheet(model: model, entryMode: .filters)
            }
            .sheet(isPresented: $isPeriodPickerPresented) {
                TimelinePeriodPickerSheet(model: model)
            }
            .fullScreenCover(isPresented: $isComposerPresented) {
                TransactionEditorView(model: model, draft: $draft)
            }
            .sheet(isPresented: $isWalletEditorPresented) {
                WalletEditorView(model: model, wallet: $walletDraft)
            }
        }
    }

    private var addButton: some View {
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
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(CashRunwayTheme.accent, in: Circle())
                .shadow(color: CashRunwayTheme.accent.opacity(0.25), radius: 16, y: 10)
        }
        .accessibilityIdentifier(CashRunwayAccessibilityID.transactionAddButton)
        .padding(.trailing, 20)
        .padding(.bottom, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 60)
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 56))
                .foregroundStyle(CashRunwayTheme.textMuted)
            Text(L10n.string("Create your first wallet"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(CashRunwayTheme.textPrimary)
            Text(L10n.string("Add a wallet to start tracking transactions and see your cash flow."))
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
                    Text(L10n.string("Add Wallet"))
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

    private var timelineHeader: some View {
        HStack(alignment: .center) {
            Text(L10n.string("Cash Flow"))
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            searchButton
        }
    }

    private var searchButton: some View {
        Button {
            isSearchPresented = true
        } label: {
            ZStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(filterPresentation.isSearchActive ? .white : CashRunwayTheme.accentDark)
                    .frame(width: 38, height: 38)
                    .background(filterPresentation.isSearchActive ? CashRunwayTheme.accent : CashRunwayTheme.accentMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if filterPresentation.isSearchActive {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                        .offset(x: 8, y: -8)
                }
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineSearchButton)
        .accessibilityLabel(filterPresentation.isSearchActive ? L10n.string("timeline.accessibility.searchActive") : L10n.string("Search"))
    }

    private var summaryCard: some View {
        Group {
            if model.wallets.filter({ !$0.isArchived }).count > 1, model.wallets.aggregateCurrencyCode(selectedWalletID: model.selectedWalletID) == nil {
                ContentUnavailableView(
                    L10n.string("Mixed-currency cash flow unavailable"),
                    systemImage: "chart.bar",
                    description: Text(L10n.string("timeline.wallet.singleCurrencyHint"))
                )
                .frame(height: 260)
                .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                TimelineSummaryCard(
                    presentation: presentation,
                    period: model.selectedTimelinePeriod,
                    locale: L10n.locale,
                    onSelectPeriod: { periodKey in
                        let newMonthKey = DateKeys.monthKey(fromPeriodKey: periodKey, period: model.selectedTimelinePeriod)
                        guard newMonthKey != model.selectedMonthKey else { return }
                        model.selectedMonthKey = newMonthKey
                        collapsedDayKeys.removeAll()
                        model.reloadTimeline()
                    }
                )
                .simultaneousGesture(periodSwipeGesture)

                spendingOverviewButton
            }
        }
    }

    // Standalone, elevated action card beneath the summary, matching the reference
    // where "Spending Overview" is its own tappable card rather than an inline row.
    private var spendingOverviewButton: some View {
        Button {
            showsOverview = true
        } label: {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.accent)
                Text(L10n.string("Spending Overview"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Spacer(minLength: 0)
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity)
            .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: CashRunwayTheme.softShadow, radius: 12, y: 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(CashRunwayAccessibilityID.overviewOpenButton)
    }

    // Horizontal swipe across the summary card navigates one period at a time
    // (swipe left -> newer, swipe right -> older), matching the legacy timeline.
    // Guarded to fire only on predominantly-horizontal drags so vertical scrolling
    // is preserved. Navigation is clamped at the current period by the model.
    private var periodSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 44, abs(horizontal) > abs(vertical) * 1.4 else { return }
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                collapsedDayKeys.removeAll()
                model.navigatePeriod(by: horizontal < 0 ? 1 : -1)
            }
    }

    // The three controls must fit one non-scrolling row without clipping in any
    // language. ViewThatFits picks the largest pill font whose row actually fits the
    // available width (Ukrainian labels are longer than English), degrading on narrow
    // devices instead of truncating or pushing a control offscreen.
    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            filterRow(fontSize: 15)
            filterRow(fontSize: 14)
            filterRow(fontSize: 13)
            filterRow(fontSize: 12)
            filterRow(fontSize: 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filterRow(fontSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            walletMenu(fontSize: fontSize)
            Spacer(minLength: 8)
            periodMenu(fontSize: fontSize)
            Spacer(minLength: 8)
            filtersButton(fontSize: fontSize)
        }
    }

    private func walletMenu(fontSize: CGFloat) -> some View {
        Menu {
            if model.wallets.aggregateCurrencyCode(selectedWalletID: nil) != nil {
                Button(L10n.string("All Wallets")) {
                    collapsedDayKeys.removeAll()
                    Task { await model.selectWallet(nil) }
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.timelineWallet("All Wallets"))
            }
            ForEach(model.wallets) { wallet in
                Button(wallet.name) {
                    collapsedDayKeys.removeAll()
                    Task { await model.selectWallet(wallet.id) }
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.timelineWallet(wallet.name))
            }
        } label: {
            pillLabel(
                iconName: "wallet.bifold.fill",
                text: model.selectedWalletID.flatMap(walletName(for:)) ?? L10n.string("All Wallets"),
                fontSize: fontSize
            )
        }
        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineWalletMenu)
    }

    private func periodMenu(fontSize: CGFloat) -> some View {
        Button {
            isPeriodPickerPresented = true
        } label: {
            pillLabel(
                iconName: "calendar",
                text: periodDisplayLabel,
                fontSize: fontSize
            )
        }
        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineMonthPicker)
    }

    private var periodDisplayLabel: String {
        switch model.selectedTimelinePeriod {
        case .month:
            return CashRunwayTheme.monthFullLabel(for: model.selectedMonthKey)
        case .year:
            return "\(model.selectedMonthKey / 100)"
        }
    }

    private func filtersButton(fontSize: CGFloat) -> some View {
        Button {
            isFiltersPresented = true
        } label: {
            ZStack(alignment: .topTrailing) {
                pillLabel(
                    iconName: "line.3.horizontal.decrease",
                    text: L10n.string("Filters"),
                    showsChevron: false,
                    fontSize: fontSize
                )

                if filterPresentation.activeAdvancedFilterCount > 0 {
                    Text("\(filterPresentation.activeAdvancedFilterCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(CashRunwayTheme.accent, in: Circle())
                        .offset(x: 4, y: -4)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineFilterBadge)
                }
            }
        }
        .accessibilityIdentifier(CashRunwayAccessibilityID.timelineFilterButton)
        .accessibilityLabel(filterButtonAccessibilityLabel)
    }

    private var filterButtonAccessibilityLabel: String {
        let count = filterPresentation.activeAdvancedFilterCount
        if count > 0 {
            return L10n.string("timeline.filter.activeCount", count)
        }
        return L10n.string("Filters")
    }

    private var transactionFeed: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            if let sections = model.timelineSnapshot?.sections, !sections.isEmpty {
                ForEach(sections) { section in
                    TimelineDayCard(
                        section: section,
                        totalText: model.aggregateMoneyString(from: section.totalMinor),
                        isMixedCurrency: model.aggregateCurrencyCode == nil,
                        onSelectItem: openEditor(for:),
                        isCollapsed: Binding(
                            get: { collapsedDayKeys.contains(section.periodKey) },
                            set: { isCollapsed in
                                if isCollapsed {
                                    collapsedDayKeys.insert(section.periodKey)
                                } else {
                                    collapsedDayKeys.remove(section.periodKey)
                                }
                            }
                        )
                    )
                }
            } else {
                emptyFeed
            }
        }
    }

    private var emptyFeed: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 20)
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(CashRunwayTheme.textMuted)

            Text(emptyFeedTitle)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(emptyFeedDescription)
                .font(.system(size: 14))
                .foregroundStyle(CashRunwayTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if filterPresentation.hasAnyFeedFilter {
                Button {
                    let cleared = TimelineFilterPresentation.clearAll(query: model.transactionQuery)
                    model.transactionQuery = cleared
                    Task { await model.reloadAll() }
                } label: {
                    HStack {
                        Image(systemName: "xmark")
                        Text(L10n.string("Clear filters"))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CashRunwayTheme.accent, lineWidth: 1)
                    )
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyFeedTitle: String {
        if filterPresentation.hasAnyFeedFilter {
            return L10n.string("No transactions found")
        }
        return L10n.string("No Transactions")
    }

    private var emptyFeedDescription: String {
        if filterPresentation.hasAnyFeedFilter {
            return L10n.string("No transactions match the active filters.")
        }
        return L10n.string("timeline.noTransactions.addOrFilter")
    }

    private func pillLabel(iconName: String, text: String, showsChevron: Bool = true, fontSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.accent)
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: fontSize * 0.78, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .background(CashRunwayTheme.surface, in: Capsule())
        .overlay(Capsule().stroke(CashRunwayTheme.line, lineWidth: 1))
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
