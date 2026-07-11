@testable import CashRunwayCore
@testable import CashRunwayUIVM
import Foundation

final class FakeBackupService: BackupServicing, @unchecked Sendable {
    var exportedBackups: [CashRunwayBackup] = []
    var encodedData = Data()
    var decodedBackup: CashRunwayBackup?
    var validationSummary = BackupValidationSummary(
        createdAt: Date(),
        walletCount: 0,
        categoryCount: 0,
        labelCount: 0,
        transactionCount: 0,
        recurringTemplateCount: 0
    )
    var restoreResult = BackupRestoreResult(summary: BackupValidationSummary(
        createdAt: Date(),
        walletCount: 0,
        categoryCount: 0,
        labelCount: 0,
        transactionCount: 0,
        recurringTemplateCount: 0
    ))
    var restoreShouldFail = false
    var validateShouldFail = false

    func exportFullBackup() throws -> CashRunwayBackup {
        exportedBackups.last ?? CashRunwayBackup(
            metadata: CashRunwayBackupMetadata(
                format: "cash-runway-backup",
                version: 1,
                createdAt: Date(),
                appVersion: "1.0",
                currency: "UAH"
            ),
            wallets: [],
            walletCategories: [],
            categories: [],
            labels: [],
            transactions: [],
            transactionLabels: [],
            budgets: [],
            recurringTemplates: [],
            recurringInstances: [],
            importJobs: []
        )
    }

    func encode(_ backup: CashRunwayBackup) throws -> Data {
        encodedData
    }

    func decode(data: Data) throws -> CashRunwayBackup {
        if let decodedBackup { return decodedBackup }
        return CashRunwayBackup(
            metadata: CashRunwayBackupMetadata(
                format: "cash-runway-backup",
                version: 1,
                createdAt: Date(),
                appVersion: "1.0",
                currency: "UAH"
            ),
            wallets: [],
            walletCategories: [],
            categories: [],
            labels: [],
            transactions: [],
            transactionLabels: [],
            budgets: [],
            recurringTemplates: [],
            recurringInstances: [],
            importJobs: []
        )
    }

    func validate(_ backup: CashRunwayBackup) throws -> BackupValidationSummary {
        if validateShouldFail { throw BackupError.unsupportedFormat }
        return validationSummary
    }

    func restore(_ backup: CashRunwayBackup) throws -> BackupRestoreResult {
        if restoreShouldFail { throw BackupError.unsupportedFormat }
        return restoreResult
    }
}

final class FakeCSVService: CSVImportServicing, @unchecked Sendable {
    var previewResult = CSVImportPreview(headers: [], sampleRows: [], totalRows: 0)
    var importResult = CSVImportResult(
        job: ImportJob(
            id: UUID(),
            sourceName: "test",
            sourceFormatID: nil,
            fileName: "import.csv",
            status: .committed,
            totalRows: 1,
            validRows: 1,
            invalidRows: 0,
            duplicateRows: 0,
            startedAt: Date(),
            finishedAt: Date(),
            errorSummary: nil
        ),
        insertedTransactions: 0,
        duplicateRows: 0,
        invalidRows: 0,
        affectedMonths: [],
        rowErrors: []
    )
    var preparedRows: [PreparedImportRow] = []
    var previewShouldFail = false
    var defaultMappingResult = CSVImportMapping(
        dateColumn: "",
        amountColumn: nil,
        debitColumn: nil,
        creditColumn: nil,
        merchantColumn: nil,
        noteColumn: nil,
        categoryColumn: nil,
        labelsColumn: nil,
        walletID: nil,
        defaultKind: .expense
    )
    var importShouldFail = false

    func preview(data: Data) throws -> CSVImportPreview {
        if previewShouldFail { throw CashRunwayError.validation("preview failed") }
        return previewResult
    }

    func detectPreset(headers: [String]) -> CSVPreset {
        .generic
    }

    func detectFormat(headers: [String], fileKind: StatementFileKind) -> BankStatementFormat {
        .genericBankCSV
    }

    func previewPreparedRows(
        data: Data,
        mapping: CSVImportMapping,
        rowFilter: CSVImportRowFilter,
        limit: Int
    ) throws -> [PreparedImportRow] {
        preparedRows
    }

    func defaultMapping(headers: [String], format: BankStatementFormat, walletID: UUID?) -> CSVImportMapping {
        defaultMappingResult
    }

    func exportCSV(query: TransactionQuery) throws -> String {
        ""
    }

    func importStatement(
        normalizedData: Data,
        fileName: String,
        format: BankStatementFormat,
        mapping: CSVImportMapping,
        rowFilter: CSVImportRowFilter
    ) throws -> CSVImportResult {
        if importShouldFail { throw CashRunwayError.validation("import failed") }
        return importResult
    }
}

final class FakeBankSyncRepository: BankSyncRepositorying, @unchecked Sendable {
    var integrations: [BankIntegration] = []
    var accounts: [BankAccount] = []
    var status = BankConnectionStatusSnapshot(
        integration: nil,
        enabledAccountCount: 0,
        syncStartAt: nil,
        lastSuccessfulSyncAt: nil,
        lastSyncError: nil,
        importedExpenseCount: 0
    )

    func bankIntegrations() throws -> [BankIntegration] { integrations }
    func activeBankIntegrations() throws -> [BankIntegration] { integrations.filter { $0.status == .active } }
    func bankAccounts(integrationID: UUID) throws -> [BankAccount] { accounts }
    func enabledBankAccounts(integrationID: UUID) throws -> [BankAccount] { accounts.filter { $0.isEnabled } }
    func saveBankIntegration(_ integration: BankIntegration) throws {}
    func saveBankAccount(_ account: BankAccount) throws {}
    func saveBankConnection(integration: BankIntegration, accounts: [BankAccount]) throws {}
    func markBankAccountSynced(_ accountID: UUID, at date: Date) throws {}
    func markBankIntegrationSynced(_ integrationID: UUID, at date: Date) throws {}
    func recordBankSyncError(integrationID: UUID, error: String, at date: Date) throws {}
    func disableBankIntegration(_ integrationID: UUID, at date: Date) throws {}
    func importedBankExpenseCount(integrationID: UUID) throws -> Int { 0 }
    func bankConnectionStatus(provider: BankProvider) throws -> BankConnectionStatusSnapshot { status }
    func learnBankMerchantCategoryRule(transactionID: UUID, categoryID: UUID) throws {}
    func existingBankImport(provider: BankProvider, providerAccountID: String, statementItemID: String) throws -> BankTransactionImport? { nil }
    func importBankExpense(
        provider: BankProvider,
        integration: BankIntegration,
        account: BankAccount,
        externalItem: BankExternalExpenseItem,
        draft: TransactionDraft
    ) throws {}
    func importMonobankExpenseItems(
        _ items: [MonobankStatementItem],
        account: BankAccount,
        integration: BankIntegration
    ) throws -> BankSyncImportResult {
        BankSyncImportResult()
    }
}

final class FakeBankSyncPerformer: BankSyncPerforming, @unchecked Sendable {
    var result = BankSyncResult()
    var shouldFail = false

    func syncOnDemand() async throws -> BankSyncResult {
        if shouldFail { throw BankSyncError.invalidResponse }
        return result
    }

    func syncOnForeground() async throws -> BankSyncResult {
        try await syncOnDemand()
    }

    func syncIntegration(_ integrationID: UUID) async throws -> BankSyncResult {
        try await syncOnDemand()
    }
}

final class FakeMonobankConnectionService: MonobankConnectionServicing, @unchecked Sendable {
    var clientInfo = MonobankClientInfo(name: "Test", accounts: [])
    var connectedIntegration = BankIntegration(
        id: UUID(),
        provider: .monobank,
        displayName: "Monobank",
        status: .active,
        syncStartAt: Date(),
        tokenKeychainAccount: "token",
        lastClientInfoSyncAt: nil,
        lastSuccessfulSyncAt: nil,
        lastSyncError: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
    var validateShouldFail = false
    var connectShouldFail = false
    var disconnectShouldFail = false

    func validateToken(_ token: String) async throws -> MonobankClientInfo {
        if validateShouldFail { throw BankSyncError.tokenInvalid }
        return clientInfo
    }

    func connectMonobank(
        token: String,
        selections: [MonobankAccountConnectionSelection]
    ) async throws -> BankIntegration {
        if connectShouldFail { throw BankSyncError.tokenInvalid }
        return connectedIntegration
    }

    func disconnectIntegration(_ integrationID: UUID) throws {
        if disconnectShouldFail { throw CashRunwayError.notFound }
    }
}
