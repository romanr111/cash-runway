import Foundation

enum CashRunwayAccessibilityID {
    static let transactionAddButton = "transaction.addButton"
    static let transactionCategorySheet = "transaction.categorySheet"
    static let transactionCategoryButton = "transaction.categoryButton"
    static let transactionCategorySheetDoneButton = "transaction.categorySheetDoneButton"
    static let transactionKindPicker = "transaction.kindPicker"
    static let transactionAmountField = "transaction.amountField"
    static let transactionNoteField = "transaction.noteField"
    static let transactionWalletMenu = "transaction.walletMenu"
    static let transactionTransferDestinationMenu = "transaction.transferDestinationMenu"
    static let transactionLabelsButton = "transaction.labelsButton"
    static let transactionLabelsSummary = "transaction.labelsSummary"
    static let transactionLabelsSheet = "transaction.labelsSheet"
    static let transactionRepeatButton = "transaction.repeatButton"
    static let transactionRepeatSummary = "transaction.repeatSummary"
    static let transactionRecurringSheet = "transaction.recurringSheet"
    static let transactionDateTodayButton = "transaction.date.todayButton"
    static let transactionDateYesterdayButton = "transaction.date.yesterdayButton"
    static let transactionLabelsSheetDoneButton = "transaction.labelsSheet.doneButton"
    static let transactionRecurringSheetDoneButton = "transaction.recurringSheet.doneButton"
    static let transactionSaveButton = "transaction.saveButton"
    static let transactionValidationAmount = "transaction.validation.amount"
    static let transactionCloseButton = "transaction.closeButton"
    static let transactionDetailsEditButton = "transaction.details.editButton"
    static let transactionDetailsDeleteButton = "transaction.details.deleteButton"
    static let transactionDetailsDoneButton = "transaction.details.doneButton"
    static let transactionDetailsAmountRow = "transaction.details.amountRow"
    static let transactionDetailsDestinationRow = "transaction.details.destinationRow"

    static let timelineSearchButton = "timeline.searchButton"
    static let timelineSearchField = "timeline.searchField"
    static let timelineSearchApplyButton = "timeline.searchApplyButton"
    static let timelineSearchResetButton = "timeline.searchResetButton"
    static let timelineWalletMenu = "timeline.walletMenu"
    static let timelineCashFlowValue = "timeline.cashFlowValue"

    static let overviewOpenButton = "overview.openButton"
    static let overviewExpensesCard = "overview.expensesCard"
    static let overviewIncomeCard = "overview.incomeCard"
    static let overviewCategoryDetailTransactionList = "overview.categoryDetail.transactionList"
    static let overviewMonthPreviousButton = "overview.month.previousButton"
    static let overviewMonthNextButton = "overview.month.nextButton"

    static let settingsMonobankRow = "settings.monobank.row"
    static let monobankIntroContinueButton = "monobank.intro.continueButton"
    static let monobankTokenField = "monobank.token.field"
    static let monobankPasteTokenButton = "monobank.token.pasteButton"
    static let monobankValidateButton = "monobank.token.validateButton"
    static let monobankValidationError = "monobank.token.validationError"
    static let monobankAccountsContinueButton = "monobank.accounts.continueButton"
    static let monobankStartSyncButton = "monobank.confirmation.startSyncButton"
    static let monobankConnectionError = "monobank.confirmation.connectionError"
    static let monobankStatusScreen = "monobank.status.screen"
    static let monobankLastResultValue = "monobank.status.lastResult"
    static let monobankImportedExpensesValue = "monobank.status.importedExpenses"
    static let monobankSyncNowButton = "monobank.status.syncNowButton"
    static let monobankManageAccountsButton = "monobank.status.manageAccountsButton"
    static let monobankDisconnectButton = "monobank.status.disconnectButton"

    static func transactionCategory(_ name: String) -> String {
        "transaction.category.\(slug(name))"
    }

    static func transactionRow(note: String, fallbackID: UUID? = nil) -> String {
        let preferred = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = preferred.isEmpty ? fallbackID?.uuidString ?? "row" : preferred
        return "transaction.row.\(slug(token))"
    }

    static func transactionRow(_ item: TransactionListItem) -> String {
        transactionRow(note: item.note, fallbackID: item.id)
    }

    static func timelineWallet(_ name: String) -> String {
        "timeline.wallet.\(slug(name))"
    }

    static func overviewCategory(_ name: String) -> String {
        "overview.category.\(slug(name))"
    }

    static func monobankAccountRow(_ id: String) -> String {
        "monobank.account.row.\(slug(id))"
    }

    static func monobankAccountToggle(_ id: String) -> String {
        "monobank.account.toggle.\(slug(id))"
    }

    private static func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let mapped = lowered.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        let collapsed = String(mapped)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "item" : collapsed
    }
}
