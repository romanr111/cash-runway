import XCTest

final class OverviewFlowUITests: CashRunwayUITestCase {
    func testSearchAndWalletFilterCanBeClearedWithoutLosingFeedState() {
        launchApp()

        openSearch()
        let searchField = app.textFields[CashRunwayUITestIdentifiers.timelineSearchField]
        searchField.tap()
        searchField.clearAndEnterText("SEARCH")
        app.buttons[CashRunwayUITestIdentifiers.timelineSearchApplyButton].tap()

        assertTransactionRowExists(note: "UITEST-SEARCH-001")
        assertTransactionRowDoesNotExist(note: "UITEST-DELETE-001")
        assertTransactionRowDoesNotExist(note: "UITEST-EDIT-001")

        openSearch()
        app.buttons[CashRunwayUITestIdentifiers.timelineSearchResetButton].tap()
        app.buttons[CashRunwayUITestIdentifiers.timelineSearchApplyButton].tap()

        assertTransactionRowExists(note: "UITEST-DELETE-001")
        assertTransactionRowExists(note: "UITEST-EDIT-001")
        assertTransactionRowExists(note: "UITEST-SEARCH-001")

        selectWallet("Savings")
        XCTAssertTrue((buttonLabel(CashRunwayUITestIdentifiers.timelineWalletMenu) ?? "").contains("Savings"))
        assertTransactionRowExists(note: "UITEST-SEARCH-001")
        assertTransactionRowDoesNotExist(note: "UITEST-DELETE-001")
        assertTransactionRowDoesNotExist(note: "UITEST-EDIT-001")

        selectAllWallets()
        XCTAssertTrue((buttonLabel(CashRunwayUITestIdentifiers.timelineWalletMenu) ?? "").contains("All Wallets"))
        assertTransactionRowExists(note: "UITEST-SEARCH-001")
        assertTransactionRowExists(note: "UITEST-DELETE-001")
        assertTransactionRowExists(note: "UITEST-EDIT-001")
    }

    func testSpendingOverviewReflectsNewExpenseAndCategoryDetailDrillsDown() {
        let note = "UITEST-OVERVIEW-GROCERIES-001"
        launchApp()

        openOverview()
        let initialExpensesLabel = app.buttons[CashRunwayUITestIdentifiers.overviewExpensesCard].label
        let initialGroceriesLabel = app.buttons[CashRunwayUITestIdentifiers.overviewCategory("Groceries")].label
        app.navigationBars.buttons.element(boundBy: 0).tap()

        openAddTransaction()
        app.buttons[CashRunwayUITestIdentifiers.transactionCategory("Groceries")].tap()
        let amountField = app.textFields[CashRunwayUITestIdentifiers.transactionAmountField]
        amountField.tap()
        amountField.typeText("77.70")
        let noteField = app.textFields[CashRunwayUITestIdentifiers.transactionNoteField]
        noteField.tap()
        noteField.typeText(note)
        hideKeyboardIfNeeded()
        app.buttons[CashRunwayUITestIdentifiers.transactionSaveButton].tap()

        openOverview()
        XCTAssertNotEqual(app.buttons[CashRunwayUITestIdentifiers.overviewExpensesCard].label, initialExpensesLabel)
        XCTAssertNotEqual(app.buttons[CashRunwayUITestIdentifiers.overviewCategory("Groceries")].label, initialGroceriesLabel)
        app.buttons[CashRunwayUITestIdentifiers.overviewCategory("Groceries")].tap()
        XCTAssertTrue(app.navigationBars["Groceries"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Transactions"].waitForExistence(timeout: 5))
        assertStaticTextExists(note, allowScroll: true)
    }

    func testOverviewMonthNavigationUpdatesVisibleTotals() {
        launchApp()

        openOverview()
        let initialExpensesLabel = app.buttons[CashRunwayUITestIdentifiers.overviewExpensesCard].label
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.overviewCategory("Groceries")].waitForExistence(timeout: 5))

        app.buttons[CashRunwayUITestIdentifiers.overviewMonthPreviousButton].tap()
        XCTAssertNotEqual(app.buttons[CashRunwayUITestIdentifiers.overviewExpensesCard].label, initialExpensesLabel)
        XCTAssertNotEqual(app.buttons[CashRunwayUITestIdentifiers.overviewExpensesCard].label, "")
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.overviewCategory("Groceries")].waitForNonExistence(timeout: 5))

        app.buttons[CashRunwayUITestIdentifiers.overviewMonthNextButton].tap()
        XCTAssertEqual(app.buttons[CashRunwayUITestIdentifiers.overviewExpensesCard].label, initialExpensesLabel)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.overviewCategory("Groceries")].waitForExistence(timeout: 5))
    }
}
