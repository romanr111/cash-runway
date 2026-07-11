@testable import CashRunwayUIVM
import Testing

@Suite("BackupImportFlowState")
struct BackupImportFlowStateTests {
    @Test("beginImport shows picker before backup view")
    func beginImportShowsPickerBeforeBackupView() {
        var flow = BackupImportFlowState()

        flow.beginImport()
        #expect(flow.isBackupImporterPresented)
        #expect(!flow.isBackupImportViewPresented)

        flow.presentBackupView()
        #expect(!flow.isBackupImporterPresented)
        #expect(flow.isBackupImportViewPresented)
    }
}
