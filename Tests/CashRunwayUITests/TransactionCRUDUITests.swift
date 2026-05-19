import XCTest

@MainActor
final class TransactionFlowUITests: CashRunwayUITestCase {
    override class func setUp() {
        launchSharedApp(reset: true, scenario: "transaction_core", dbPath: "cash-runway-transaction-flow.sqlite")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    func testAddExpenseTransactionHappyPath() {
        prepareSharedApp()
        let note = "UITEST-GROCERIES-001"

        openAddTransaction()
        XCTAssertTrue(app.otherElements[CashRunwayUITestIdentifiers.transactionCategorySheet].exists)
        app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].tap()

        let amountField = app.textFields[CashRunwayUITestIdentifiers.transactionAmountField]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.tap()
        amountField.typeText("123.45")

        let noteField = app.textFields[CashRunwayUITestIdentifiers.transactionNoteField]
        noteField.tap()
        noteField.typeText(note)
        hideKeyboardIfNeeded()

        app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].tap()
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].waitForNonExistence(timeout: 5))

        assertTransactionRowExists(note: note)
        let savedRow = app.buttons[CashRunwayUITestIdentifiers.transactionRow(note: note)]
        XCTAssertTrue(savedRow.label.contains(moneyString(12_345)))
        XCTAssertTrue(savedRow.label.contains("Groceries"))
        XCTAssertTrue(savedRow.label.contains("Main Wallet"))

        openTransactionRow(note: note)
        let amountRow = app.descendants(matching: .any).matching(identifier: CashRunwayUITestIdentifiers.transactionDetailsAmountRow).firstMatch
        XCTAssertTrue(amountRow.waitForExistence(timeout: 5))
        XCTAssertTrue(amountRow.label.contains(moneyString(12_345)))
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Main Wallet"].waitForExistence(timeout: 5))
    }

    func testAddTransactionInvalidAmountShowsRecoverableError() {
        prepareSharedApp()
        let note = "UITEST-INVALID-RECOVERY-001"
        openAddTransaction()
        app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].tap()

        app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].tap()
        let amountError = app.staticTexts[CashRunwayUITestIdentifiers.transactionValidationAmount]
        XCTAssertTrue(amountError.waitForExistence(timeout: 5))
        XCTAssertEqual(amountError.label, "Enter a valid amount greater than zero.")
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].exists)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionCloseButton].exists)

        let amountField = app.textFields[CashRunwayUITestIdentifiers.transactionAmountField]
        amountField.clearAndEnterText("0")
        app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].tap()
        XCTAssertTrue(amountError.waitForExistence(timeout: 5))
        XCTAssertEqual(amountError.label, "Enter a valid amount greater than zero.")
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].exists)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionCloseButton].exists)

        amountField.clearAndEnterText("19.50")
        let noteField = app.textFields[CashRunwayUITestIdentifiers.transactionNoteField]
        noteField.tap()
        noteField.typeText(note)
        hideKeyboardIfNeeded()

        app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].tap()
        assertTransactionRowExists(note: note)
    }

    func testDismissComposerDoesNotCreateTransaction() {
        prepareSharedApp()
        let note = "UITEST-DISMISS-001"
        openAddTransaction()
        app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].tap()
        let amountField = app.textFields[CashRunwayUITestIdentifiers.transactionAmountField]
        amountField.tap()
        amountField.typeText("9.99")
        let noteField = app.textFields[CashRunwayUITestIdentifiers.transactionNoteField]
        noteField.tap()
        noteField.typeText(note)
        hideKeyboardIfNeeded()

        app.buttons[CashRunwayUITestIdentifiers.transactionCloseButton].tap()
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionCloseButton].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionAddButton].exists)
        assertTransactionRowDoesNotExist(note: note)
    }

    func testSwitchingTransactionKindsKeepsDraftValid() {
        prepareSharedApp()
        openAddTransaction()
        let kindPicker = app.segmentedControls[CashRunwayUITestIdentifiers.transactionKindPicker]
        XCTAssertTrue(kindPicker.waitForExistence(timeout: 5))

        app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].tap()
        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 5))

        app.buttons[CashRunwayUITestIdentifiers.transactionCategoryButton].tap()
        XCTAssertTrue(kindPicker.waitForExistence(timeout: 5))
        kindPicker.buttons["Income"].tap()
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Salary")].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].exists)

        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Salary")].waitForExistence(timeout: 5))

        kindPicker.buttons["Transfer"].tap()
        XCTAssertTrue(app.staticTexts["Transfers do not use categories."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Salary")].exists)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionTransferDestinationMenu].waitForExistence(timeout: 5))

        kindPicker.buttons["Expenses"].tap()
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[CashRunwayUITestIdentifiers.transactionTransferDestinationMenu].exists)
    }

    func testComposerPreservesDraftWhenOpeningLabelsAndRepeatSheets() {
        prepareSharedApp()
        let note = "UITEST-DRAFT-SHEETS-001"
        openAddTransaction()
        app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].tap()

        let amountField = app.textFields[CashRunwayUITestIdentifiers.transactionAmountField]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.clearAndEnterText("27.40")

        let noteField = app.textFields[CashRunwayUITestIdentifiers.transactionNoteField]
        noteField.clearAndEnterText(note)
        hideKeyboardIfNeeded()

        app.buttons[CashRunwayUITestIdentifiers.transactionLabelsButton].tap()
        let labelControl = labeledControl(named: "UITEST-LABEL-001")
        tapControl(labelControl)
        tapSheetDoneButton(identifier: CashRunwayUITestIdentifiers.transactionLabelsSheetDoneButton)

        XCTAssertEqual((app.textFields[CashRunwayUITestIdentifiers.transactionAmountField].value as? String) ?? "", "27.40")
        XCTAssertEqual((app.textFields[CashRunwayUITestIdentifiers.transactionNoteField].value as? String) ?? "", note)
        XCTAssertTrue(app.staticTexts[CashRunwayUITestIdentifiers.transactionLabelsSummary].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts[CashRunwayUITestIdentifiers.transactionLabelsSummary].label, "UITEST-LABEL-001")
        XCTAssertTrue(app.staticTexts["Main Wallet"].waitForExistence(timeout: 5))

        app.buttons[CashRunwayUITestIdentifiers.transactionLabelsButton].tap()
        let reopenedLabelControl = labeledControl(named: "UITEST-LABEL-001")
        assertControlIsSelected(reopenedLabelControl)
        tapSheetDoneButton(identifier: CashRunwayUITestIdentifiers.transactionLabelsSheetDoneButton)

        app.buttons[CashRunwayUITestIdentifiers.transactionRepeatButton].tap()
        let recurringToggle = app.switches["Save as recurring template"]
        XCTAssertTrue(recurringToggle.waitForExistence(timeout: 5))
        setSwitch(recurringToggle, on: true)
        tapSheetDoneButton(identifier: CashRunwayUITestIdentifiers.transactionRecurringSheetDoneButton)

        XCTAssertTrue(app.staticTexts[CashRunwayUITestIdentifiers.transactionRepeatSummary].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts[CashRunwayUITestIdentifiers.transactionRepeatSummary].label, "Monthly every 1")

        app.buttons[CashRunwayUITestIdentifiers.transactionRepeatButton].tap()
        XCTAssertTrue(app.switches["Save as recurring template"].waitForExistence(timeout: 5))
        assertSwitchIsOn(app.switches["Save as recurring template"])
        tapSheetDoneButton(identifier: CashRunwayUITestIdentifiers.transactionRecurringSheetDoneButton)

        // Scroll to ensure the Save button is fully visible after sheet dismissals.
        let saveButton = app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        if !saveButton.isHittable {
            app.swipeUp()
            _ = saveButton.waitForExistence(timeout: 3)
        }
        saveButton.tap()
        assertTransactionRowExists(note: note)

        openTransactionRow(note: note)
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UITEST-LABEL-001"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Main Wallet"].waitForExistence(timeout: 5))
    }

    func testDateShortcutsChangeSavedTransactionDate() {
        prepareSharedApp()
        let note = "UITEST-DATE-001"
        openAddTransaction()
        app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].tap()

        let amountField = app.textFields[CashRunwayUITestIdentifiers.transactionAmountField]
        amountField.tap()
        amountField.typeText("18.20")

        let noteField = app.textFields[CashRunwayUITestIdentifiers.transactionNoteField]
        noteField.tap()
        noteField.typeText(note)
        hideKeyboardIfNeeded()

        app.buttons[CashRunwayUITestIdentifiers.transactionDateYesterdayButton].tap()
        XCTAssertEqual(buttonValue(CashRunwayUITestIdentifiers.transactionDateYesterdayButton), "selected")
        XCTAssertEqual(buttonValue(CashRunwayUITestIdentifiers.transactionDateTodayButton), "not selected")

        app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].tap()
        assertTransactionRowExists(note: note)

        openTransactionRow(note: note)
        app.buttons[CashRunwayUITestIdentifiers.transactionDetailsEditButton].tap()

        XCTAssertEqual(buttonValue(CashRunwayUITestIdentifiers.transactionDateYesterdayButton), "selected")
        XCTAssertEqual(buttonValue(CashRunwayUITestIdentifiers.transactionDateTodayButton), "not selected")
    }

    func testEditTransactionUpdatesExistingRow() {
        prepareSharedApp()
        let originalNote = "UITEST-EDIT-001"
        let updatedNote = "UITEST-EDIT-001-UPDATED"
        openTransactionRow(note: originalNote)
        app.buttons[CashRunwayUITestIdentifiers.transactionDetailsEditButton].tap()

        XCTAssertTrue(app.staticTexts["Edit Transaction"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields[CashRunwayUITestIdentifiers.transactionAmountField].waitForExistence(timeout: 5))
        XCTAssertEqual((app.textFields[CashRunwayUITestIdentifiers.transactionNoteField].value as? String) ?? "", originalNote)
        XCTAssertTrue(app.staticTexts["Main Wallet"].waitForExistence(timeout: 5))

        let amountField = app.textFields[CashRunwayUITestIdentifiers.transactionAmountField]
        amountField.clearAndEnterText("88.80")

        let noteField = app.textFields[CashRunwayUITestIdentifiers.transactionNoteField]
        noteField.clearAndEnterText(updatedNote)
        hideKeyboardIfNeeded()

        app.buttons[CashRunwayUITestIdentifiers.transactionCategoryButton].tap()
        XCTAssertTrue(app.otherElements[CashRunwayUITestIdentifiers.transactionCategorySheet].waitForExistence(timeout: 5))
        app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].tap()

        app.buttons[CashRunwayUITestIdentifiers.transactionDateTodayButton].tap()
        app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].tap()

        assertTransactionRowDoesNotExist(note: originalNote)
        assertTransactionRowExists(note: updatedNote)
        let updatedRow = app.buttons[CashRunwayUITestIdentifiers.transactionRow(note: updatedNote)]
        XCTAssertTrue(updatedRow.label.contains(moneyString(8_880)))
        XCTAssertTrue(updatedRow.label.contains("Groceries"))
        XCTAssertTrue(updatedRow.label.contains("Main Wallet"))

        openTransactionRow(note: updatedNote)
        let amountRow = app.descendants(matching: .any).matching(identifier: CashRunwayUITestIdentifiers.transactionDetailsAmountRow).firstMatch
        XCTAssertTrue(amountRow.waitForExistence(timeout: 5))
        XCTAssertTrue(amountRow.label.contains(moneyString(8_880)))
        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[updatedNote].waitForExistence(timeout: 5))

        // Dismiss detail view to leave app in clean state for subsequent tests
        app.buttons[CashRunwayUITestIdentifiers.transactionDetailsDoneButton].tap()
        _ = app.buttons[CashRunwayUITestIdentifiers.transactionDetailsDoneButton].waitForNonExistence(timeout: 2)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    func testTransferRequiresDestinationWalletAndDoesNotExposeCategories() {
        // Fresh launch to avoid state accumulation from previous tests in this class
        launchApp()
        let note = "UITEST-TRANSFER-001"
        openAddTransaction()
        let kindPicker = app.segmentedControls[CashRunwayUITestIdentifiers.transactionKindPicker]
        XCTAssertTrue(kindPicker.waitForExistence(timeout: 5))
        kindPicker.buttons["Transfer"].tap()

        XCTAssertTrue(app.staticTexts["Transfers do not use categories."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].exists)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionCategorySheetDoneButton].waitForExistence(timeout: 5))
        app.buttons[CashRunwayUITestIdentifiers.transactionCategorySheetDoneButton].tap()

        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionTransferDestinationMenu].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionTransferDestinationMenu].label.contains("Savings"))

        let amountField = app.textFields[CashRunwayUITestIdentifiers.transactionAmountField]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.clearAndEnterText("150.00")
        let noteField = app.textFields[CashRunwayUITestIdentifiers.transactionNoteField]
        noteField.clearAndEnterText(note)
        hideKeyboardIfNeeded()

        app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].tap()
        assertTransactionRowExists(note: note, walletName: "Main Wallet")

        openTransactionRow(note: note, walletName: "Main Wallet")
        XCTAssertTrue(app.staticTexts["Destination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Savings"].waitForExistence(timeout: 5))
        app.buttons[CashRunwayUITestIdentifiers.transactionDetailsEditButton].tap()
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionTransferDestinationMenu].label.contains("Savings"))

        app.buttons[CashRunwayUITestIdentifiers.transactionCategoryButton].tap()
        XCTAssertTrue(app.staticTexts["Transfers do not use categories."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].exists)
    }

    private func assertSwitchIsOn(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            waitForSwitch(element, toBeOn: true, timeout: 3),
            "Switch did not become on. value=\(switchValue(element))",
            file: file,
            line: line
        )
    }

    private func assertSwitchIsOff(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            waitForSwitch(element, toBeOn: false, timeout: 3),
            "Switch did not become off. value=\(switchValue(element))",
            file: file,
            line: line
        )
    }

    private func setSwitch(
        _ element: XCUIElement,
        on expectedValue: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if switchIsOn(element) == expectedValue {
            return
        }

        XCTAssertTrue(element.isHittable, "Switch is not hittable.", file: file, line: line)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(
            waitForSwitch(element, toBeOn: expectedValue, timeout: 5),
            "Switch value did not change after tap. value=\(switchValue(element))",
            file: file,
            line: line
        )
    }

    private func waitForSwitch(_ element: XCUIElement, toBeOn expectedValue: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if switchIsOn(element) == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return switchIsOn(element) == expectedValue
    }

    private func switchIsOn(_ element: XCUIElement) -> Bool {
        !["0", "off", "false", "not selected", ""].contains(switchValue(element))
    }

    private func switchValue(_ element: XCUIElement) -> String {
        (element.value as? String ?? "").lowercased()
    }

    private func labeledControl(named identifier: String) -> XCUIElement {
        let visibleSheet = app.sheets.firstMatch
        let sheet = app.sheets[CashRunwayUITestIdentifiers.transactionLabelsSheet].firstMatch
        let table = app.tables[CashRunwayUITestIdentifiers.transactionLabelsSheet].firstMatch
        let container = app.otherElements[CashRunwayUITestIdentifiers.transactionLabelsSheet].firstMatch
        let scrollView = app.scrollViews[CashRunwayUITestIdentifiers.transactionLabelsSheet].firstMatch
        let sheetContainer: XCUIElement
        if visibleSheet.waitForExistence(timeout: 3) {
            sheetContainer = visibleSheet
        } else if sheet.waitForExistence(timeout: 3) {
            sheetContainer = sheet
        } else if table.waitForExistence(timeout: 3) {
            sheetContainer = table
        } else if container.waitForExistence(timeout: 3) {
            sheetContainer = container
        } else {
            dumpAccessibilityTree(
                fileName: "/tmp/cashrunway-labels-sheet-debug.txt",
                note: "Missing labels sheet container for \(identifier)"
            )
            XCTAssertTrue(scrollView.waitForExistence(timeout: 5), "Missing labels sheet container.")
            sheetContainer = scrollView
        }

        let control = sheetContainer.buttons[identifier].firstMatch
        XCTAssertTrue(
            control.waitForExistence(timeout: 5),
            "Missing button \(identifier) inside labels sheet. buttons=\(sheetContainer.buttons.matching(identifier: identifier).count) staticTexts=\(sheetContainer.staticTexts.matching(identifier: identifier).count)"
        )

        if !control.isHittable {
            for _ in 0..<8 {
                sheetContainer.swipeUp()
                if control.isHittable {
                    break
                }
            }
        }
        return control
    }

    private func tapControl(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.isHittable, "Control is not hittable.", file: file, line: line)
        element.tap()
    }

    private func assertControlIsSelected(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let value = (element.value as? String ?? "").lowercased()
        XCTAssertFalse(["0", "off", "false", "not selected", ""].contains(value), file: file, line: line)
    }

    private func tapSheetDoneButton(identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let navigationBarDone = app.navigationBars.buttons["Done"].firstMatch
        if navigationBarDone.waitForExistence(timeout: 2) {
            XCTAssertTrue(navigationBarDone.isHittable, "Sheet Done button is not hittable.", file: file, line: line)
            navigationBarDone.tap()
            return
        }

        let toolbarDone = app.toolbars.buttons["Done"].firstMatch
        if toolbarDone.waitForExistence(timeout: 2) {
            XCTAssertTrue(toolbarDone.isHittable, "Sheet Done button is not hittable.", file: file, line: line)
            toolbarDone.tap()
            return
        }

        let doneButton = app.buttons["Done"].firstMatch
        if doneButton.waitForExistence(timeout: 2) {
            XCTAssertTrue(doneButton.isHittable, "Sheet Done button is not hittable.", file: file, line: line)
            doneButton.tap()
            return
        }

        let identifierButton = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(identifierButton.waitForExistence(timeout: 5), "Could not find sheet Done button.", file: file, line: line)
        XCTAssertTrue(identifierButton.isHittable, "Sheet Done button is not hittable.", file: file, line: line)
        identifierButton.tap()
    }

    private func dumpAccessibilityTree(fileName: String, note: String) {
        let output = """
        \(note)
        sheets count: \(app.sheets.count)
        sheets matching labelsSheet: \(app.sheets.matching(identifier: CashRunwayUITestIdentifiers.transactionLabelsSheet).count)
        buttons matching labelsSheet: \(app.buttons.matching(identifier: CashRunwayUITestIdentifiers.transactionLabelsSheet).count)
        otherElements matching labelsSheet: \(app.otherElements.matching(identifier: CashRunwayUITestIdentifiers.transactionLabelsSheet).count)
        tables matching labelsSheet: \(app.tables.matching(identifier: CashRunwayUITestIdentifiers.transactionLabelsSheet).count)
        scrollViews matching labelsSheet: \(app.scrollViews.matching(identifier: CashRunwayUITestIdentifiers.transactionLabelsSheet).count)
        staticTexts matching UITEST-LABEL-001: \(app.staticTexts.matching(identifier: "UITEST-LABEL-001").count)
        buttons matching UITEST-LABEL-001: \(app.buttons.matching(identifier: "UITEST-LABEL-001").count)
        otherElements matching UITEST-LABEL-001: \(app.otherElements.matching(identifier: "UITEST-LABEL-001").count)
        tables matching UITEST-LABEL-001: \(app.tables.matching(identifier: "UITEST-LABEL-001").count)
        scrollViews matching UITEST-LABEL-001: \(app.scrollViews.matching(identifier: "UITEST-LABEL-001").count)
        \(app.debugDescription)
        """

        try? output.write(toFile: fileName, atomically: true, encoding: .utf8)
    }
}
