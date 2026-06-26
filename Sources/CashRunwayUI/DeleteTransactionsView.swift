import CashRunwayCore
import SwiftUI

struct DeleteTransactionsView: View {
    @Bindable var model: CashRunwayAppModel
    var requestBackupExport: () -> Void
    var onDismiss: () -> Void

    private enum Stage { case select, confirm }

    @State private var stage: Stage = .select
    @State private var selectedPeriod: DeletePeriod?
    @State private var selectedPlan: TransactionDeletionPlan?
    @State private var isLoadingPlan = false
    @State private var summaries: [DeletePeriod: TransactionDeletionSummary] = [:]
    @State private var confirmText: String = ""
    @State private var isBackupPromptPresented = false
    @State private var isDeleting = false
    @FocusState private var confirmFieldFocused: Bool

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
                warningCard

                switch stage {
                case .select:
                    periodSection
                case .confirm:
                    confirmSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(CashRunwayTheme.background)
        .scrollContentBackground(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isDeleting)
        .accessibilityIdentifier(CashRunwayAccessibilityID.deleteTransactionsSheet)
        .task { reloadSummaries() }
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

            VStack(spacing: 6) {
                Text("Delete Transactions")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text("Choose transactions to remove by date")
                    .font(CashRunwayTheme.bodyFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CashRunwayTheme.spaceS)
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
            sectionLabel("Select a period")
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

            primaryButton(title: "Continue", enabled: canContinue && !isLoadingPlan) {
                isBackupPromptPresented = true
            }
        }
        .task(id: selectedPeriod) {
            guard let period = selectedPeriod else {
                selectedPlan = nil
                return
            }
            isLoadingPlan = true
            selectedPlan = await model.transactionDeletionPlan(for: period)
            isLoadingPlan = false
        }
    }

    private var confirmSection: some View {
        VStack(alignment: .leading, spacing: CashRunwayTheme.spaceM) {
            sectionLabel("Confirm deletion")
            VStack(alignment: .leading, spacing: CashRunwayTheme.spaceS) {
                if let plan = selectedPlan {
                    impactCard(plan: plan)
                }
                VStack(alignment: .leading, spacing: 8) {

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
                        .focused($confirmFieldFocused)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.deleteTransactionsConfirmField)
                }
            }

            primaryButton(
                title: selectedPlan.map { L10n.deleteTransactionsButtonTitle($0.count) } ?? L10n.deleteTransactionsButtonTitle(0),
                enabled: confirmMatches && !isDeleting && hasSelectedTransactions,
                isLoading: isDeleting
            ) {
                performDelete()
            }
        }
    }

    private func impactCard(plan: TransactionDeletionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: CashRunwayTheme.spaceM) {
                periodGlyph(plan.period)
                VStack(alignment: .leading, spacing: 4) {
                    Text(periodTitle(plan.period))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                    Text(L10n.string("%@ will be permanently deleted.", L10n.transactionCount(plan.count)))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CashRunwayTheme.negative)
                }
                Spacer()
            }
            if plan.expenseMinor > 0 || plan.incomeMinor > 0 {
                HStack(spacing: 10) {
                    if plan.expenseMinor > 0 {
                        amountStat(label: "Expenses", value: plan.expenseMinor)
                    }
                    if plan.incomeMinor > 0 {
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
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textMuted)
                .textCase(.uppercase)
            Text(MoneyFormatter.string(from: value))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusS, style: .continuous))
    }

    private func periodRow(_ period: DeletePeriod) -> some View {
        let summary = summaries[period]
        let isSelected = selectedPeriod == period
        return Button {
            selectedPeriod = period
        } label: {
            HStack(spacing: 14) {
                periodGlyph(period)
                VStack(alignment: .leading, spacing: 3) {
                    Text(periodTitle(period))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                    Text(summary.map { L10n.transactionCount($0.count) } ?? L10n.transactionCount(0))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? CashRunwayTheme.negative : CashRunwayTheme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(CashRunwayAccessibilityID.deleteTransactionsPeriodRow)
    }

    private func periodGlyph(_ period: DeletePeriod) -> some View {
        ZStack {
            Circle()
                .fill(CashRunwayTheme.negative.opacity(0.14))
            Image(systemName: periodIcon(period))
                .font(.system(size: 18, weight: .semibold))
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

    private func primaryButton(title: String, enabled: Bool, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.system(size: 17, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background((enabled ? CashRunwayTheme.negative : CashRunwayTheme.textMuted), in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous))
        }
        .disabled(!enabled)
        .accessibilityIdentifier(CashRunwayAccessibilityID.deleteTransactionsConfirmButton)
    }

    private var rowDivider: some View {
        Divider().overlay(CashRunwayTheme.line).padding(.leading, 76)
    }

    private var canContinue: Bool {
        hasSelectedTransactions
    }

    private var hasSelectedTransactions: Bool {
        selectedPlan.map { $0.count > 0 } ?? false
    }

    private func periodTitle(_ period: DeletePeriod) -> String {
        switch period {
        case .today: L10n.string("This Day")
        case .thisMonth: L10n.string("This Month")
        case .thisYear: L10n.string("This Year")
        }
    }

    private func periodIcon(_ period: DeletePeriod) -> String {
        switch period {
        case .today: "sun.max.fill"
        case .thisMonth: "calendar"
        case .thisYear: "calendar.badge.clock"
        }
    }

    private func reloadSummaries() {
        var updated: [DeletePeriod: TransactionDeletionSummary] = [:]
        for period in DeletePeriod.allCases {
            updated[period] = model.transactionDeletionSummary(for: period)
        }
        summaries = updated
    }

    private func performDelete() {
        guard let plan = selectedPlan, confirmMatches, !isDeleting else { return }
        confirmFieldFocused = false
        isDeleting = true
        Task {
            let success = await model.deleteTransactions(plan: plan)
            isDeleting = false
            if success { onDismiss() }
        }
    }
}
