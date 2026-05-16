import XCTest

final class MonobankConnectionUITests: CashRunwayUITestCase {
    func testFirstStartMonobankConnectionImportsOnlyNewExpenses() {
        launchApp(scenario: "monobank_first_start", monobankMode: "happy_path")

        openMonobankConnection()
        completeTokenValidation()

        XCTAssertTrue(app.switches[CashRunwayUITestIdentifiers.monobankAccountToggle("uitest-uah-card")].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements[CashRunwayUITestIdentifiers.monobankAccountRow("uitest-usd-card")].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not supported in MVP"].waitForExistence(timeout: 5))

        app.buttons[CashRunwayUITestIdentifiers.monobankAccountsContinueButton].tap()
        app.buttons[CashRunwayUITestIdentifiers.monobankStartSyncButton].tap()

        XCTAssertTrue(app.staticTexts[CashRunwayUITestIdentifiers.monobankStatusScreen].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts[CashRunwayUITestIdentifiers.monobankImportedExpensesValue].label, "1")
        XCTAssertEqual(app.staticTexts[CashRunwayUITestIdentifiers.monobankLastResultValue].label, "success")

        app.buttons["Done"].tap()
        app.tabBars.buttons["Timeline"].tap()
        assertTransactionRowExists(note: "UITEST-MONO-NEW", allowScroll: true)
        assertTransactionRowDoesNotExist(note: "UITEST-MONO-OLD")
        assertTransactionRowDoesNotExist(note: "UITEST-MONO-INCOME")
    }

    func testInvalidMonobankTokenShowsRetryableValidationError() {
        launchApp(scenario: "monobank_first_start", monobankMode: "invalid_token")

        openMonobankConnection()
        app.buttons[CashRunwayUITestIdentifiers.monobankIntroContinueButton].tap()

        let tokenField = app.secureTextFields[CashRunwayUITestIdentifiers.monobankTokenField]
        XCTAssertTrue(tokenField.waitForExistence(timeout: 5))
        tokenField.tap()
        tokenField.typeText("BAD-UITEST-TOKEN")
        hideKeyboardIfNeeded()
        app.buttons[CashRunwayUITestIdentifiers.monobankValidateButton].tap()

        let error = app.staticTexts[CashRunwayUITestIdentifiers.monobankValidationError]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("Bank token is invalid"))
        XCTAssertFalse(app.staticTexts[CashRunwayUITestIdentifiers.monobankStatusScreen].exists)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.monobankValidateButton].exists)
    }

    func testFirstSyncFailureCanRecoverWithManualSync() {
        launchApp(scenario: "monobank_first_start", monobankMode: "first_sync_fails_then_recovers")

        openMonobankConnection()
        completeTokenValidation()
        app.buttons[CashRunwayUITestIdentifiers.monobankAccountsContinueButton].tap()
        app.buttons[CashRunwayUITestIdentifiers.monobankStartSyncButton].tap()

        XCTAssertTrue(app.staticTexts[CashRunwayUITestIdentifiers.monobankStatusScreen].waitForExistence(timeout: 10))
        let lastResult = app.staticTexts[CashRunwayUITestIdentifiers.monobankLastResultValue]
        XCTAssertTrue(lastResult.waitForExistence(timeout: 5))
        XCTAssertTrue(lastResult.label.contains("UITEST first sync failed"))

        app.buttons[CashRunwayUITestIdentifiers.monobankSyncNowButton].tap()
        XCTAssertTrue(waitForStaticText("success", timeout: 10, allowScroll: false))
        XCTAssertEqual(app.staticTexts[CashRunwayUITestIdentifiers.monobankImportedExpensesValue].label, "2")

        app.buttons["Done"].tap()
        app.tabBars.buttons["Timeline"].tap()
        assertTransactionRowExists(note: "UITEST-MONO-NEW", allowScroll: true)
        assertTransactionRowExists(note: "UITEST-MONO-FOREGROUND", allowScroll: true)
    }

    private func openMonobankConnection(file: StaticString = #filePath, line: UInt = #line) {
        openMoreTab(file: file, line: line)
        let row = app.buttons[CashRunwayUITestIdentifiers.settingsMonobankRow]
        XCTAssertTrue(row.waitForExistence(timeout: 5), file: file, line: line)
        row.tap()
        XCTAssertTrue(app.navigationBars["Monobank"].waitForExistence(timeout: 5), file: file, line: line)
    }

    private func completeTokenValidation(file: StaticString = #filePath, line: UInt = #line) {
        app.buttons[CashRunwayUITestIdentifiers.monobankIntroContinueButton].tap()
        let tokenField = app.secureTextFields[CashRunwayUITestIdentifiers.monobankTokenField]
        XCTAssertTrue(tokenField.waitForExistence(timeout: 5), file: file, line: line)
        tokenField.tap()
        tokenField.typeText("UITEST-MONOBANK-TOKEN")
        hideKeyboardIfNeeded()
        app.buttons[CashRunwayUITestIdentifiers.monobankValidateButton].tap()
        XCTAssertTrue(app.otherElements[CashRunwayUITestIdentifiers.monobankAccountRow("uitest-uah-card")].waitForExistence(timeout: 5), file: file, line: line)
    }
}
