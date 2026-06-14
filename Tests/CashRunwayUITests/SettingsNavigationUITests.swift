import XCTest

@MainActor
final class SettingsNavigationUITests: CashRunwayUITestCase {

    // swiftlint:disable:next static_over_final_class
    override class func setUp() {
        super.setUp()
        launchSharedApp(reset: true, scenario: "transaction_core")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        prepareSharedApp()
    }

    // MARK: - Helpers

    private func openMoreTabAndAssertSettings() {
        openMoreTab()
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.settingsCategoriesRow].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.settingsLabelsRow].exists)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.settingsScheduledTransactionsRow].exists)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.settingsMainCurrencyRow].exists)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.settingsWalletsRow].exists)
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.settingsMonobankRow].exists)
    }

    private func dismissSheetAndAssertSettingsVisible() {
        // Sheets in Settings use either Back, Done, or Cancel in the nav bar.
        let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 2) {
            backButton.tap()
        } else {
            let doneButton = app.navigationBars.buttons["Done"].firstMatch
            if doneButton.waitForExistence(timeout: 2) {
                doneButton.tap()
            } else {
                let cancelButton = app.navigationBars.buttons["Cancel"].firstMatch
                if cancelButton.waitForExistence(timeout: 2) {
                    cancelButton.tap()
                }
            }
        }
        // Verify we are back on Settings by waiting for a known row.
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.settingsCategoriesRow].waitForExistence(timeout: 3))
    }

    // MARK: - Tests

    func testSettingsRowsAreVisibleFromMoreTab() {
        openMoreTabAndAssertSettings()
    }

    func testSettingsToCategoriesAndBack() {
        openMoreTabAndAssertSettings()
        app.buttons[CashRunwayUITestIdentifiers.settingsCategoriesRow].tap()
        XCTAssertTrue(app.otherElements[CashRunwayUITestIdentifiers.categoryManagementScreen].waitForExistence(timeout: 3))
        dismissSheetAndAssertSettingsVisible()
    }

    func testSettingsToLabelsAndBack() {
        openMoreTabAndAssertSettings()
        app.buttons[CashRunwayUITestIdentifiers.settingsLabelsRow].tap()
        XCTAssertTrue(app.otherElements[CashRunwayUITestIdentifiers.labelManagementScreen].waitForExistence(timeout: 3))
        dismissSheetAndAssertSettingsVisible()
    }

    func testSettingsToScheduledTransactionsAndBack() {
        openMoreTabAndAssertSettings()
        app.buttons[CashRunwayUITestIdentifiers.settingsScheduledTransactionsRow].tap()
        XCTAssertTrue(app.otherElements[CashRunwayUITestIdentifiers.scheduledTransactionsScreen].waitForExistence(timeout: 3))
        dismissSheetAndAssertSettingsVisible()
    }

    func testSettingsToWalletsAndBack() {
        openMoreTabAndAssertSettings()
        app.buttons[CashRunwayUITestIdentifiers.settingsWalletsRow].tap()
        XCTAssertTrue(app.otherElements[CashRunwayUITestIdentifiers.walletManagementScreen].waitForExistence(timeout: 3))
        dismissSheetAndAssertSettingsVisible()
    }

    func testSettingsToMonobankAndBack() {
        openMoreTabAndAssertSettings()
        app.buttons[CashRunwayUITestIdentifiers.settingsMonobankRow].tap()
        // Monobank wizard shows the intro screen first when no token is stored.
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.monobankIntroContinueButton].waitForExistence(timeout: 3))
        dismissSheetAndAssertSettingsVisible()
    }

    func testSettingsToFeedbackReportAndBack() {
        openMoreTab()
        let feedbackRow = app.buttons[CashRunwayUITestIdentifiers.settingsFeedbackReportRow]
        if !feedbackRow.waitForExistence(timeout: 1) || !feedbackRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(feedbackRow.waitForExistence(timeout: 3))
        feedbackRow.tap()
        XCTAssertTrue(app.navigationBars["Report Feedback"].waitForExistence(timeout: 3))
        dismissSheetAndAssertSettingsVisible()
    }

    func testFeedbackReportShowsConfigurationErrorWhenBackendIsMissing() {
        openMoreTab()
        let feedbackRow = app.buttons[CashRunwayUITestIdentifiers.settingsFeedbackReportRow]
        if !feedbackRow.waitForExistence(timeout: 1) || !feedbackRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(feedbackRow.waitForExistence(timeout: 3))
        feedbackRow.tap()
        XCTAssertTrue(app.navigationBars["Report Feedback"].waitForExistence(timeout: 3))

        let title = "UITEST feedback report"
        let description = "This issue report was filled from the Cash Runway feedback form UI."
        app.textFields[CashRunwayUITestIdentifiers.feedbackTitleField].fastEnterText(title)
        app.textViews[CashRunwayUITestIdentifiers.feedbackDescriptionField].fastEnterText(description)
        hideKeyboardIfNeeded()

        app.buttons[CashRunwayUITestIdentifiers.feedbackSubmitButton].tap()
        XCTAssertTrue(app.staticTexts["Reporting is not configured yet."].waitForExistence(timeout: 5))
    }
}
