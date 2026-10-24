import XCTest

@MainActor
final class SettingsNavigationUITests: CashRunwayUITestCase {

    // swiftlint:disable:next static_over_final_class
    override class func setUp() {
        super.setUp()
        launchSharedApp(reset: true, scenario: "retrospective_qa", dbPath: "cash-runway-pr124-shots.sqlite")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        prepareSharedApp()
    }

    // MARK: - Helpers (pre-existing navigation tests)

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

    // MARK: - PR 124: retrospective export screenshot evidence
    //
    // These tests capture real screenshots of the Issue #123 export flow for
    // docs/evidence. Captures go through XCUIScreen and are stored with
    // lifetime .keepAlways so `xcrun xcresulttool export attachments` (CI step)
    // can pull the PNG files out of the .xcresult bundle.

    /// Exports a screenshot of `screen` as a named PNG attachment that survives
    /// result-bundle pruning and is exported by the CI post-test step.
    @discardableResult
    private func attachScreenshot(name: String, screen: XCUIScreen) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: screen.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return attachment
    }

    /// Navigates to the More tab and scrolls until the retrospective export
    /// row is visible; returns a settled hittable row.
    private func hittableRetrospectiveExportRow(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        openMoreTab()
        let row = app.buttons[CashRunwayUITestIdentifiers.settingsExportRetrospectiveRow]
        if !row.waitForExistence(timeout: 3) || !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 3), file: file, line: line)
        return row
    }

    @discardableResult
    private func openRetrospectiveFormatPicker(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let row = hittableRetrospectiveExportRow(file: file, line: line)
        row.tap()

        let pickerTitle = app.otherElements["Export Monthly Retrospective"]
        let dialog = app.otherElements["Export Monthly Retrospective"].firstMatch
        if !dialog.waitForExistence(timeout: 3) {
            // Fall back to the actions sheet container (older iOS wording).
            _ = app.otherElements["Actions"].waitForExistence(timeout: 3)
        }
        XCTAssertTrue(
            app.buttons["Spreadsheet (.xlsx)"].waitForExistence(timeout: 3),
            "Retrospective export format picker did not appear.",
            file: file,
            line: line
        )
        XCTAssertTrue(app.buttons["CSV (.csv)"].waitForExistence(timeout: 3), file: file, line: line)
        return pickerTitle
    }

    /// Dismisses the confirmation dialog without starting an export.
    private func dismissFormatPicker(file: StaticString = #filePath, line: UInt = #line) {
        let cancelButton = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3), file: file, line: line)
        cancelButton.tap()
        let row = app.buttons[CashRunwayUITestIdentifiers.settingsExportRetrospectiveRow]
        XCTAssertTrue(row.waitForExistence(timeout: 3), file: file, line: line)
    }

    /// Screenshots the Dashboard (Timeline) seeded with the deterministic
    /// retrospective dataset: two complete prior months plus fixed NBU-style
    /// month-end rates in `exchange_rates`, so the summary card renders the
    /// persisted `≈ $` secondary lines for the selected month. The timeline
    /// snapshot itself always renders; the USD lines render exactly when the
    /// stored snapshot row for that month exists (honest either way).
    func testPR124DashboardScreenshot() throws {
        prepareSharedApp()
        // The Timeline tab is shared-app root; settle animation before capture.
        XCTAssertTrue(app.buttons[CashRunwayUITestIdentifiers.transactionAddButton].waitForExistence(timeout: 3))
        attachScreenshot(name: "pr124-dashboard", screen: XCUIScreen.main)
        returnToRoot()
    }

    /// Screenshots the Settings sheet scrolled to the Data section so the new
    /// "Export Monthly Retrospective" row (Issue #123) is visible alongside
    /// the existing CSV / backup rows.
    func testPR124SettingsDataSectionScreenshot() throws {
        prepareSharedApp()
        _ = hittableRetrospectiveExportRow()
        attachScreenshot(name: "pr124-settings-data-export-row", screen: XCUIScreen.main)
        returnToRoot()
    }

    /// Screenshots the retrospective export format picker (confirmationDialog)
    /// including the xlsx and csv options, then dismisses it.
    func testPR124RetrospectiveFormatPickerScreenshot() throws {
        prepareSharedApp()
        _ = openRetrospectiveFormatPicker()
        attachScreenshot(name: "pr124-format-picker", screen: XCUIScreen.main)
        dismissFormatPicker()
        returnToRoot()
    }
}
