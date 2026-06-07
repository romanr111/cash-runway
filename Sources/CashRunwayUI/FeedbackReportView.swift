import SwiftUI

struct FeedbackReportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ReportIssueViewModel

    init(service: any FeedbackReportSubmitting = ConfiguredFeedbackReportService()) {
        _viewModel = StateObject(wrappedValue: ReportIssueViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Form {
                EmptyView().accessibilityIdentifier(CashRunwayAccessibilityID.feedbackReportScreen)

                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(CashRunwayTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(CashRunwayTheme.accent.opacity(0.14), in: Circle())

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Private by default")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.textPrimary)
                            Text("Only the text you enter and basic app/device diagnostics are sent. Screenshots, logs, CSV files, databases, balances, transactions, and Monobank tokens are never uploaded.")
                                .font(CashRunwayTheme.captionFont)
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Type") {
                    Picker("Category", selection: $viewModel.draft.category) {
                        ForEach(ReportIssueCategory.allCases) { category in
                            Text(category.displayTitle).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackCategoryPicker)
                    .disabled(viewModel.isLocked)
                }

                Section {
                    TextField("Title", text: $viewModel.draft.title)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackTitleField)
                        .disabled(viewModel.isLocked)

                    TextEditor(text: $viewModel.draft.description)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackDescriptionField)
                        .disabled(viewModel.isLocked)
                } header: {
                    Text("Details")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let validationMessage = viewModel.draft.validationMessage,
                           !viewModel.draft.title.isEmpty || !viewModel.draft.description.isEmpty {
                            Text(validationMessage)
                                .foregroundStyle(CashRunwayTheme.negative)
                        }
                        Text("Do not include account numbers, balances, transaction details, Monobank tokens, or private financial information.")
                    }
                }

                Section {
                    Toggle("Include safe diagnostics", isOn: $viewModel.draft.includeDiagnostics)
                        .disabled(viewModel.isLocked)
                    Text("Diagnostics include app version, build, iOS version, device model, locale, timezone, and an anonymous install hash.")
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                }

                if let unavailableMessage = viewModel.unavailableMessage {
                    Section("Unavailable") {
                        Text(unavailableMessage)
                            .foregroundStyle(CashRunwayTheme.textSecondary)
                    }
                }

                stateSection

                Section {
                    Button {
                        viewModel.submit()
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isSubmitting {
                                ProgressView()
                            } else {
                                Text("Send Report")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackSubmitButton)
                }
            }
            .navigationTitle("Report Feedback")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(viewModel.submitState.isSuccess ? "Done" : "Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.submitState {
        case .idle:
            EmptyView()
        case .submitting:
            Section("Sending") {
                ProgressView("Creating report...")
            }
        case let .success(issueNumber):
            Section("Sent") {
                Text("Report sent. Issue #\(issueNumber) was created for triage.")
                    .foregroundStyle(CashRunwayTheme.positive)
                    .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackSuccessMessage)
            }
        case let .failure(message):
            Section("Error") {
                Text(message)
                    .foregroundStyle(CashRunwayTheme.negative)
            }
        }
    }
}

#Preview {
    FeedbackReportView(service: MockFeedbackReportService())
}
