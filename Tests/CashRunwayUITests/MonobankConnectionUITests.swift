import UIKit
import XCTest

final class MonobankConnectionUITests: CashRunwayUITestCase {
    func testFirstStartMonobankConnectionImportsOnlyNewExpenses() {
        launchApp(scenario: "monobank_first_start", monobankMode: "happy_path")

        openMonobankConnection()
        completeTokenValidation()

        XCTAssertTrue(app.staticTexts["Black card ****1111 · UAH"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["White card ****8888 · 840"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not supported in MVP"].waitForExistence(timeout: 5))

        createMonobankWallet()
        app.buttons[CashRunwayUITestIdentifiers.monobankAccountsContinueButton].tap()
        app.buttons[CashRunwayUITestIdentifiers.monobankStartSyncButton].tap()

        XCTAssertTrue(app.staticTexts["Monobank connected"].waitForExistence(timeout: 10))
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
        pasteToken("BAD-UITEST-TOKEN")
        app.buttons[CashRunwayUITestIdentifiers.monobankValidateButton].tap()

        let error = app.staticTexts[CashRunwayUITestIdentifiers.monobankValidationError]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("Bank token is invalid"))
        XCTAssertFalse(app.staticTexts["Monobank connected"].exists)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.monobankValidateButton].exists)
    }

    func testFirstSyncFailureCanRecoverWithManualSync() {
        launchApp(scenario: "monobank_first_start", monobankMode: "first_sync_fails_then_recovers")

        openMonobankConnection()
        completeTokenValidation()
        createMonobankWallet()
        app.buttons[CashRunwayUITestIdentifiers.monobankAccountsContinueButton].tap()
        app.buttons[CashRunwayUITestIdentifiers.monobankStartSyncButton].tap()

        XCTAssertTrue(app.staticTexts["Monobank connected"].waitForExistence(timeout: 10))
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
        pasteToken("UITEST-MONOBANK-TOKEN", file: file, line: line)
        app.buttons[CashRunwayUITestIdentifiers.monobankValidateButton].tap()
        XCTAssertTrue(app.staticTexts["Black card ****1111 · UAH"].waitForExistence(timeout: 5), file: file, line: line)
    }

    private func pasteToken(_ token: String, file: StaticString = #filePath, line: UInt = #line) {
        UIPasteboard.general.string = token
        let pasteButton = app.buttons[CashRunwayUITestIdentifiers.monobankPasteTokenButton]
        XCTAssertTrue(pasteButton.waitForExistence(timeout: 5), file: file, line: line)
        pasteButton.tap()
        let validateButton = app.buttons[CashRunwayUITestIdentifiers.monobankValidateButton]
        XCTAssertTrue(waitForEnabled(validateButton, timeout: 5), file: file, line: line)
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isEnabled {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.exists && element.isEnabled
    }

    private func createMonobankWallet(file: StaticString = #filePath, line: UInt = #line) {
        let createWalletButton = app.buttons["Create Monobank wallet"].firstMatch
        XCTAssertTrue(createWalletButton.waitForExistence(timeout: 5), file: file, line: line)
        createWalletButton.tap()
    }
}
