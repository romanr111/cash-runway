import SwiftUI

struct FeedbackReportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ReportIssueViewModel

    init(service: any FeedbackReportSubmitting = ConfiguredFeedbackReportService()) {
        _viewModel = StateObject(wrappedValue: ReportIssueViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: CashRunwayTheme.spaceL) {
                    privacyCard

                    whatHappenedCard

                    attachCard

                    if let unavailableMessage = viewModel.unavailableMessage {
                        unavailableCallout(message: unavailableMessage)
                    }

                    securityCallout

                    submitButton

                    stateSection
                }
                .padding(.horizontal, CashRunwayTheme.spaceM)
                .padding(.vertical, CashRunwayTheme.spaceM)
                .padding(.bottom, CashRunwayTheme.spaceXL)
            }
            .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackReportScreen)
            .background(CashRunwayTheme.background)
            .navigationTitle(L10n.string("Feedback"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(viewModel.submitState.isSuccess ? L10n.string("Done") : L10n.string("Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Privacy Card

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: CashRunwayTheme.spaceM) {
            HStack(spacing: CashRunwayTheme.spaceS) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(CashRunwayTheme.accent.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("Private by default"))
                        .font(CashRunwayTheme.subheadingFont)
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                }
            }

            VStack(alignment: .leading, spacing: CashRunwayTheme.spaceS) {
                privacyBullet(
                    icon: "text.alignleft",
                    text: L10n.string("Only the text you enter is sent.")
                )
                privacyBullet(
                    icon: "photo.stack",
                    text: L10n.string("Screenshots are optional and compressed.")
                )
                privacyBullet(
                    icon: "person.slash.fill",
                    text: L10n.string("Balances, transactions, and tokens are never uploaded.")
                )
            }
        }
        .padding(CashRunwayTheme.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }

    private func privacyBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.accent)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            Text(text)
                .font(CashRunwayTheme.captionFont)
                .foregroundStyle(CashRunwayTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - What Happened Card

    private var whatHappenedCard: some View {
        VStack(alignment: .leading, spacing: CashRunwayTheme.spaceM) {
            Text(L10n.string("What happened?"))
                .font(CashRunwayTheme.subheadingFont)
                .foregroundStyle(CashRunwayTheme.textPrimary)

            VStack(alignment: .leading, spacing: CashRunwayTheme.spaceS) {
                Text(L10n.string("Category"))
                    .font(CashRunwayTheme.captionFont)
                    .foregroundStyle(CashRunwayTheme.textMuted)

                Picker("Category", selection: $viewModel.draft.category) {
                    ForEach(ReportIssueCategory.allCases) { category in
                        Text(category.displayTitle).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackCategoryPicker)
                .disabled(viewModel.isLocked)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField(L10n.string("Title"), text: $viewModel.draft.title)
                    .font(CashRunwayTheme.bodyFont)
                    .textInputAutocapitalization(.sentences)
                    .padding(CashRunwayTheme.spaceS)
                    .background(CashRunwayTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusS, style: .continuous))
                    .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackTitleField)
                    .disabled(viewModel.isLocked)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $viewModel.draft.description)
                    .font(CashRunwayTheme.bodyFont)
                    .frame(minHeight: 120, maxHeight: 240)
                    .padding(CashRunwayTheme.spaceXS)
                    .background(CashRunwayTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusS, style: .continuous))
                    .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackDescriptionField)
                    .disabled(viewModel.isLocked)

                if let validationMessage = viewModel.draft.validationMessage,
                   !viewModel.draft.title.isEmpty || !viewModel.draft.description.isEmpty {
                    Text(validationMessage)
                        .font(CashRunwayTheme.captionFont)
                        .foregroundStyle(CashRunwayTheme.negative)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(CashRunwayTheme.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }

    // MARK: - Attach Card

    private var attachCard: some View {
        VStack(alignment: .leading, spacing: CashRunwayTheme.spaceM) {
            Text(L10n.string("Attach"))
                .font(CashRunwayTheme.subheadingFont)
                .foregroundStyle(CashRunwayTheme.textPrimary)

            FeedbackReportScreenshotPicker(
                screenshots: $viewModel.draft.screenshots,
                isLocked: viewModel.isLocked
            )

            VStack(alignment: .leading, spacing: CashRunwayTheme.spaceXS) {
                Toggle(
                    L10n.string("Include safe diagnostics"),
                    isOn: $viewModel.draft.includeDiagnostics
                )
                .disabled(viewModel.isLocked)
                .font(CashRunwayTheme.bodyFont)

                Text(L10n.string("Diagnostics include app version, build, iOS version, device model, locale, timezone, and an anonymous install hash."))
                    .font(CashRunwayTheme.captionFont)
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(CashRunwayTheme.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }

    // MARK: - Callouts

    private func unavailableCallout(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CashRunwayTheme.warning)

            Text(message)
                .font(CashRunwayTheme.captionFont)
                .foregroundStyle(CashRunwayTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(CashRunwayTheme.spaceM)
        .background(CashRunwayTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous).stroke(CashRunwayTheme.warning.opacity(0.25), lineWidth: 1))
    }

    private var securityCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.accentDark)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            Text(L10n.string("Do not include account numbers, balances, transaction details, Monobank tokens, or private financial information."))
                .font(CashRunwayTheme.captionFont)
                .foregroundStyle(CashRunwayTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(CashRunwayTheme.spaceM)
        .background(CashRunwayTheme.accentMuted, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous))
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            viewModel.submit()
        } label: {
            HStack(spacing: 10) {
                Spacer()
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(L10n.string("Send Report"))
                        .font(CashRunwayTheme.subheadingFont)
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .background(
                viewModel.canSubmit
                    ? CashRunwayTheme.accent
                    : CashRunwayTheme.accent.opacity(0.45),
                in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous)
            )
            .foregroundStyle(.white)
        }
        .disabled(!viewModel.canSubmit)
        .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackSubmitButton)
    }

    // MARK: - State Section

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.submitState {
        case .idle, .submitting:
            EmptyView()
        case let .success(issueNumber):
            successCard(issueNumber: issueNumber)
        case let .failure(message):
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(CashRunwayTheme.negative)
                Text(message)
                    .font(CashRunwayTheme.captionFont)
                    .foregroundStyle(CashRunwayTheme.negative)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(CashRunwayTheme.spaceM)
            .background(CashRunwayTheme.negative.opacity(0.08), in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous))
        }
    }

    private func successCard(issueNumber: Int) -> some View {
        VStack(spacing: CashRunwayTheme.spaceS) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.positive)

            Text(L10n.string("Report sent"))
                .font(CashRunwayTheme.subheadingFont)
                .foregroundStyle(CashRunwayTheme.textPrimary)

            Text(L10n.string("Report sent. Issue #%lld was created for triage.", issueNumber))
                .font(CashRunwayTheme.captionFont)
                .foregroundStyle(CashRunwayTheme.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackSuccessMessage)
        }
        .padding(CashRunwayTheme.spaceL)
        .frame(maxWidth: .infinity)
        .background(CashRunwayTheme.positive.opacity(0.08), in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusL, style: .continuous).stroke(CashRunwayTheme.positive.opacity(0.25), lineWidth: 1))
    }
}

#Preview {
    FeedbackReportView(service: MockFeedbackReportService())
}
