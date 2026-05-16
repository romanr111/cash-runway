import XCTest

@MainActor
class CashRunwayUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @discardableResult
    func launchApp(reset: Bool = true, scenario: String = "transaction_core", monobankMode: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CASH_RUNWAY_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CASH_RUNWAY_UI_TEST_DB_PATH"] = "cash-runway-uitests.sqlite"
        app.launchEnvironment["CASH_RUNWAY_UI_TEST_SCENARIO"] = scenario
        if let monobankMode {
            app.launchEnvironment["CASH_RUNWAY_UI_TEST_MONOBANK_MODE"] = monobankMode
        }
        if reset {
            app.launchEnvironment["CASH_RUNWAY_UI_TEST_RESET"] = "1"
        }
        app.launch()

        self.app = app
        XCTAssertTrue(
            app.buttons[CashRunwayUITestIdentifiers.transactionAddButton].waitForExistence(timeout: 10),
            "Timeline did not finish bootstrapping."
        )
        return app
    }

    func openAddTransaction(file: StaticString = #filePath, line: UInt = #line) {
        let addButton = app.buttons[CashRunwayUITestIdentifiers.transactionAddButton]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), file: file, line: line)
        addButton.tap()

        let categorySheet = app.otherElements[CashRunwayUITestIdentifiers.transactionCategorySheet]
        XCTAssertTrue(categorySheet.waitForExistence(timeout: 5), file: file, line: line)
    }

    func openOverview(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[CashRunwayUITestIdentifiers.overviewOpenButton]
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        button.tap()
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.overviewExpensesCard].waitForExistence(timeout: 5), file: file, line: line)
    }

    func openSearch(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[CashRunwayUITestIdentifiers.timelineSearchButton]
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        button.tap()
        XCTAssertTrue(app.textFields[CashRunwayUITestIdentifiers.timelineSearchField].waitForExistence(timeout: 5), file: file, line: line)
    }

    func openMoreTab(file: StaticString = #filePath, line: UInt = #line) {
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5), file: file, line: line)
        moreTab.tap()
    }

    func openTransactionRow(note: String, walletName: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let row = transactionRowElement(note: note, walletName: walletName)
        XCTAssertTrue(waitForTransactionRow(note: note, walletName: walletName, timeout: 5, allowScroll: true), "Missing transaction row for note \(note)", file: file, line: line)
        row.tap()
    }

    func assertTransactionRowExists(note: String, walletName: String? = nil, allowScroll: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForTransactionRow(note: note, walletName: walletName, timeout: 5, allowScroll: allowScroll), file: file, line: line)
        if allowScroll {
            let row = transactionRowElement(note: note, walletName: walletName)
            XCTAssertTrue(row.isHittable, file: file, line: line)
        }
    }

    func assertTransactionRowDoesNotExist(note: String, walletName: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let row = transactionRowElement(note: note, walletName: walletName)
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), file: file, line: line)
    }

    func selectWallet(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        selectMenuOption(menuIdentifier: CashRunwayUITestIdentifiers.timelineWalletMenu, option: name, file: file, line: line)
    }

    func selectMenuOption(menuIdentifier: String, option: String, file: StaticString = #filePath, line: UInt = #line) {
        let menu = app.buttons[menuIdentifier]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), file: file, line: line)
        menu.tap()

        let optionButton = app.buttons[option].firstMatch
        if optionButton.waitForExistence(timeout: 2) {
            optionButton.tap()
            return
        }

        let menuItem = app.menuItems[option].firstMatch
        if menuItem.waitForExistence(timeout: 5) {
            menuItem.tap()
            return
        }

        let staticText = app.staticTexts[option].firstMatch
        XCTAssertTrue(staticText.waitForExistence(timeout: 5), file: file, line: line)
        staticText.tap()
    }

    func selectAllWallets(file: StaticString = #filePath, line: UInt = #line) {
        selectMenuOption(menuIdentifier: CashRunwayUITestIdentifiers.timelineWalletMenu, option: "All Wallets", file: file, line: line)
    }

    func hideKeyboardIfNeeded() {
        let candidates = [
            app.keyboards.buttons["Done"].firstMatch,
            app.buttons["Done"].firstMatch,
            app.toolbars.buttons["Done"].firstMatch
        ]
        for candidate in candidates where candidate.exists {
            candidate.tap()
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 5)
            return
        }
    }

    func moneyString(_ minorUnits: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "₴"
        formatter.currencyCode = "UAH"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "uk_UA")
        let value = NSDecimalNumber(value: minorUnits).dividing(by: 100)
        return formatter.string(from: value) ?? "\(minorUnits)"
    }

    func assertStaticTextExists(_ value: String, allowScroll: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForStaticText(value, timeout: 5, allowScroll: allowScroll), file: file, line: line)
    }

    func assertStaticTextDoesNotExist(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts[value].waitForNonExistence(timeout: 5), file: file, line: line)
    }

    @discardableResult
    func waitForTransactionRow(note: String, walletName: String? = nil, timeout: TimeInterval, allowScroll: Bool) -> Bool {
        let row = transactionRowElement(note: note, walletName: walletName)
        if row.waitForExistence(timeout: timeout) {
            return true
        }

        guard allowScroll else { return false }

        for _ in 0..<6 {
            app.swipeUp()
            if row.waitForExistence(timeout: 1) {
                return true
            }
        }

        return false
    }

    @discardableResult
    func waitForStaticText(_ value: String, timeout: TimeInterval, allowScroll: Bool) -> Bool {
        let text = app.staticTexts[value]
        if text.waitForExistence(timeout: timeout) {
            return true
        }

        guard allowScroll else { return false }

        for _ in 0..<6 {
            app.swipeUp()
            if text.waitForExistence(timeout: 1) {
                return true
            }
        }

        return false
    }

    func transactionRowElement(note: String, walletName: String? = nil) -> XCUIElement {
        let identifier = CashRunwayUITestIdentifiers.transactionRow(note: note)
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        guard let walletName else {
            return query.firstMatch
        }

        for index in 0..<query.count {
            let element = query.element(boundBy: index)
            if element.exists, element.label.contains(walletName) {
                return element
            }
        }

        return query.firstMatch
    }

    func buttonValue(_ identifier: String) -> String? {
        app.buttons[identifier].value as? String
    }

    func buttonLabel(_ identifier: String) -> String? {
        app.buttons[identifier].label
    }
}

enum CashRunwayUITestIdentifiers {
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

    static func transactionRow(note: String) -> String {
        "transaction.row.\(slug(note))"
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

extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        tap()

        let currentValue = value as? String ?? ""
        if !currentValue.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            typeText(deleteString)
        }

        typeText(text)
    }

    @discardableResult
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
