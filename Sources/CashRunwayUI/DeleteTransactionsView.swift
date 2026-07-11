import CashRunwayCore
import SwiftUI

struct DeleteTransactionsView: View {
    @Bindable var model: CashRunwayAppModel
    var requestBackupExport: () -> Void
    var onDismiss: () -> Void

    private enum Stage: Equatable { case select, confirm, done }
    private enum ConfirmField: Hashable { case confirm }

    @State private var stage: Stage = .select
    @State private var selectedPeriod: DeletePeriod?
    @State private var selectedPlan: TransactionDeletionPlan?
    @State private var isLoadingPlan = false
    @State private var summaries: [DeletePeriod: TransactionDeletionSummary] = [:]
    @State private var isLoadingSummaries = false
    @State private var confirmText: String = ""
    @State private var isBackupPromptPresented = false
    @State private var isDeleting = false
    @State private var deletionCompleted = false
    @State private var deletedCount = 0
    @State private var planRequestID: UUID?
    @FocusState private var focusedField: ConfirmField?

    private var confirmWord: String {
        L10n.languageCode == "uk" ? "ВИДАЛИТИ" : "DELETE"
    }

    private var confirmMatches: Bool {
        let trimmed = confirmText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "delete" || trimmed == "видалити"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CashRunwayTheme.spaceL) {
                header
                switch stage {
                case .select:
                    if deletionCompleted {
                        deletionCompletedNotice
                    }
                    warningCard
                    periodSection
                case .confirm:
                    confirmSection
                case .done:
                    doneSection
                }
            }
            .padding(.horizontal, CashRunwayTheme.spaceL)
            .padding(.top, CashRunwayTheme.spaceS)
            .padding(.bottom, CashRunwayTheme.spaceXL)
        }
        .background(CashRunwayTheme.background)
        .scrollContentBackground(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isDeleting)
        .accessibilityIdentifier(CashRunwayAccessibilityID.deleteTransactionsSheet)
        .task { await reloadSummaries() }
        .alert("Back up first?", isPresented: $isBackupPromptPresented) {
            Button("Back up") { requestBackupExport() }
            Button("Skip", role: .cancel) { stage = .confirm }
        } message: {
            Text("Deleting is permanent. We recommend exporting an unencrypted backup you can restore from later.")
        }
    }

    private var header: some View {
        VStack(spacing: CashRunwayTheme.spaceM) {
            ZStack {
                Circle()
                    .fill(CashRunwayTheme.negative.opacity(0.14))
                Circle()
                    .stroke(CashRunwayTheme.negative.opacity(0.22), lineWidth: 1)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.negative)
            }
            .frame(width: 76, height: 76)

            VStack(spacing: CashRunwayTheme.spaceXS) {
                Text("Delete Transactions")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text("Choose transactions to remove")
                    .font(CashRunwayTheme.bodyFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CashRunwayTheme.spaceS)
    }

    private var deletionCompletedNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.negative)
            VStack(alignment: .leading, spacing: 4) {
                Text("Transactions were deleted, but the screen couldn't refresh.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text("Close and reopen this screen if the data looks stale.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(CashRunwayTheme.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CashRunwayTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }

    private var warningCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "trash.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.negative)
            Text("This permanently deletes the selected transactions. This cannot be undone.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CashRunwayTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(CashRunwayTheme.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CashRunwayTheme.negative.opacity(0.10), in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous).stroke(CashRunwayTheme.negative.opacity(0.30), lineWidth: 1))
    }

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: CashRunwayTheme.spaceM) {
            sectionLabel("Choose a scope")
            VStack(spacing: 0) {
                ForEach(DeletePeriod.allCases) { period in
                    periodRow(period)
                    if period != DeletePeriod.allCases.last {
                        rowDivider
                    }
                }
            }
            .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))

            primaryButton(
                title: "Continue",
                identifier: CashRunwayAccessibilityID.deleteTransactionsContinueButton,
                enabled: canContinue && !isLoadingPlan && !isLoadingSummaries
            ) {
                isBackupPromptPresented = true
            }
        }
        .task(id: selectedPeriod) {
            guard let period = selectedPeriod else {
                selectedPlan = nil
                planRequestID = nil
                isLoadingPlan = false
                return
            }

            let requestID = UUID()
            planRequestID = requestID
            selectedPlan = nil
            isLoadingPlan = true
            defer {
                if planRequestID == requestID {
                    isLoadingPlan = false
                }
            }

            let plan = await model.transactionDeletionPlan(for: period)

            guard !Task.isCancelled,
                  planRequestID == requestID,
                  selectedPeriod == period,
                  plan?.period == period
            else {
                return
            }

            selectedPlan = plan
            isLoadingPlan = false
        }
    }

    private var confirmSection: some View {
        VStack(alignment: .leading, spacing: CashRunwayTheme.spaceM) {
            sectionLabel("Confirm deletion")
            VStack(alignment: .leading, spacing: CashRunwayTheme.spaceS) {
                if let plan = selectedPlan {
                    impactCard(plan: plan)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                VStack(alignment: .leading, spacing: CashRunwayTheme.spaceS) {
                    Text(L10n.string("Type %@ to confirm", confirmWord))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.negative)
                    TextField(confirmWord, text: $confirmText)
                        .font(.system(size: 17, weight: .semibold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textCase(.uppercase)
                        .padding(CashRunwayTheme.spaceM)
                        .background(CashRunwayTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusS, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusS, style: .continuous).stroke(confirmMatches ? CashRunwayTheme.negative : CashRunwayTheme.line, lineWidth: confirmMatches ? 2 : 1))
                        .focused($focusedField, equals: .confirm)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.deleteTransactionsConfirmField)
                }
            }

            primaryButton(
                title: selectedPlan.map { L10n.deleteTransactionsButtonTitle($0.displayCount) } ?? L10n.deleteTransactionsButtonTitle(0),
                identifier: CashRunwayAccessibilityID.deleteTransactionsConfirmButton,
                enabled: confirmMatches && !isDeleting && hasSelectedTransactions,
                isLoading: isDeleting
            ) {
                performDelete()
            }
        }
        .animation(.default, value: selectedPlan != nil)
    }

    private var doneSection: some View {
        VStack(spacing: CashRunwayTheme.spaceL) {
            VStack(spacing: CashRunwayTheme.spaceM) {
                ZStack {
                    Circle()
                        .fill(CashRunwayTheme.accentMuted)
                        .frame(width: 112, height: 112)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.accentDark)
                }
                .transition(.scale.combined(with: .opacity))

                VStack(spacing: CashRunwayTheme.spaceS) {
                    Text(L10n.deletedTransactionsMessage(deletedCount))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(L10n.string("Wallets, categories, and recurring templates were preserved."))
                        .font(CashRunwayTheme.bodyFont)
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                onDismiss()
            } label: {
                Text(L10n.string("Done"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(CashRunwayTheme.accentDark, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous))
            }
            .accessibilityIdentifier(CashRunwayAccessibilityID.deleteTransactionsDoneButton)
        }
        .padding(.top, CashRunwayTheme.spaceL)
        .frame(maxWidth: .infinity)
    }

    private func impactCard(plan: TransactionDeletionPlan) -> some View {
        VStack(alignment: .leading, spacing: CashRunwayTheme.spaceM) {
            HStack(spacing: CashRunwayTheme.spaceM) {
                periodGlyph(plan.period)
                VStack(alignment: .leading, spacing: CashRunwayTheme.spaceXS) {
                    Text(periodTitle(plan.period))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                    Text(L10n.string("%@ will be permanently deleted.", L10n.transactionCount(plan.displayCount)))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CashRunwayTheme.negative)
                }
                Spacer()
            }
            if plan.hasFinancialImpact {
                HStack(spacing: CashRunwayTheme.spaceM) {
                    if plan.hasExpenseImpact {
                        amountStat(label: "Expenses", value: plan.expenseMinor)
                    }
                    if plan.hasIncomeImpact {
                        amountStat(label: "Income", value: plan.incomeMinor)
                    }
                }
            }
        }
        .padding(CashRunwayTheme.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CashRunwayTheme.negative.opacity(0.10), in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous).stroke(CashRunwayTheme.negative.opacity(0.28), lineWidth: 1))
    }

    private func amountStat(label: LocalizedStringKey, value: Int64) -> some View {
        VStack(alignment: .leading, spacing: CashRunwayTheme.spaceXS) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textMuted)
                .textCase(.uppercase)
            Text(MoneyFormatter.string(from: value))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textPrimary)
        }
        .padding(.horizontal, CashRunwayTheme.spaceM)
        .padding(.vertical, CashRunwayTheme.spaceS)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusS, style: .continuous))
    }

    private func periodRow(_ period: DeletePeriod) -> some View {
        let summary = summaries[period]
        let isSelected = selectedPeriod == period
        return Button {
            selectedPeriod = period
        } label: {
            HStack(spacing: CashRunwayTheme.spaceM) {
                periodGlyph(period)
                VStack(alignment: .leading, spacing: CashRunwayTheme.spaceXS) {
                    HStack(spacing: CashRunwayTheme.spaceS) {
                        Text(periodTitle(period))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                        if period == .allHistory {
                            Text(L10n.string("DANGER"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(CashRunwayTheme.negative)
                                .padding(.horizontal, CashRunwayTheme.spaceS)
                                .padding(.vertical, 2)
                                .background(CashRunwayTheme.negative.opacity(0.08), in: Capsule())
                                .overlay(Capsule().stroke(CashRunwayTheme.negative.opacity(0.40), lineWidth: 1))
                        }
                    }
                    Text(periodRowDetail(summary))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? CashRunwayTheme.negative : CashRunwayTheme.textMuted)
            }
            .padding(.horizontal, CashRunwayTheme.spaceM)
            .padding(.vertical, CashRunwayTheme.spaceM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(CashRunwayAccessibilityID.deleteTransactionsPeriodRow).\(period.rawValue)")
        .accessibilityLabel(periodTitle(period))
        .accessibilityValue(periodRowDetail(summary))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func periodRowDetail(_ summary: TransactionDeletionSummary?) -> String {
        guard let summary, summary.count > 0 else {
            return L10n.transactionCount(0)
        }
        var parts: [String] = [L10n.transactionCount(summary.displayCount)]
        if summary.isMixedCurrency {
            return parts.joined(separator: " · ")
        }
        if summary.hasExpenseImpact {
            parts.append("\(L10n.string("Expenses")) \(MoneyFormatter.string(from: summary.expenseMinor))")
        }
        if summary.hasIncomeImpact {
            parts.append("\(L10n.string("Income")) \(MoneyFormatter.string(from: summary.incomeMinor))")
        }
        return parts.joined(separator: " · ")
    }

    private func periodGlyph(_ period: DeletePeriod) -> some View {
        ZStack {
            Circle()
                .fill(period == .allHistory
                      ? CashRunwayTheme.negative.opacity(0.18)
                      : CashRunwayTheme.negative.opacity(0.14))
            if period == .allHistory {
                Circle()
                    .stroke(CashRunwayTheme.negative.opacity(0.40), lineWidth: 1)
            }
            Image(systemName: periodIcon(period))
                .font(.system(size: period == .allHistory ? 20 : 18, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.negative)
        }
        .frame(width: 46, height: 46)
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(CashRunwayTheme.textMuted)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    private func primaryButton(title: String, identifier: String, enabled: Bool, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CashRunwayTheme.spaceM) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.system(size: 17, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, CashRunwayTheme.spaceM)
            .foregroundStyle(.white)
            .background((enabled ? CashRunwayTheme.negative : CashRunwayTheme.textMuted), in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous))
        }
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }

    private var rowDivider: some View {
        Divider()
            .overlay(CashRunwayTheme.line)
            .padding(.leading, CashRunwayTheme.spaceXL + CashRunwayTheme.spaceM)
    }

    private var canContinue: Bool {
        hasSelectedTransactions
    }

    private var hasSelectedTransactions: Bool {
        guard let selectedPeriod, let selectedPlan else { return false }

        return selectedPlan.period == selectedPeriod &&
               selectedPlan.count > 0
    }

    private func periodTitle(_ period: DeletePeriod) -> String {
        switch period {
        case .allHistory: L10n.string("All History")
        case .today: L10n.string("This Day")
        case .thisMonth: L10n.string("This Month")
        case .thisYear: L10n.string("This Year")
        }
    }

    private func periodIcon(_ period: DeletePeriod) -> String {
        switch period {
        case .allHistory: "trash.fill"
        case .today: "sun.max.fill"
        case .thisMonth: "calendar"
        case .thisYear: "calendar.badge.clock"
        }
    }

    private func reloadSummaries() async {
        isLoadingSummaries = true
        defer { isLoadingSummaries = false }
        var updated: [DeletePeriod: TransactionDeletionSummary] = [:]
        for period in DeletePeriod.allCases {
            updated[period] = await model.transactionDeletionSummary(for: period)
        }
        summaries = updated
    }

    private func performDelete() {
        guard let period = selectedPeriod,
              let plan = selectedPlan,
              plan.period == period,
              confirmMatches,
              !isDeleting,
              !deletionCompleted
        else {
            return
        }
        focusedField = nil
        isDeleting = true
        Task {
            let result = await model.deleteTransactions(plan: plan)
            isDeleting = false
            if result.refreshSuccess {
                deletedCount = result.deletedCount
                withAnimation(.bouncy) {
                    stage = .done
                }
            } else if result.deletedCount > 0 {
                // Deletion succeeded but refresh failed — prevent re-submission
                // by clearing the plan and returning to the selection stage.
                deletionCompleted = true
                selectedPlan = nil
                confirmText = ""
                stage = .select
                Task { await reloadSummaries() }
            }
        }
    }
}
