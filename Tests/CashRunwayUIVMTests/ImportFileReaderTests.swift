@testable import CashRunwayUIVM
import Foundation
import Testing

@Suite("ImportFileReader")
struct ImportFileReaderTests {
    @Test("readData protects copied temp file before reading")
    func readDataProtectsBeforeReading() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).csv")
        let sourceData = Data("date,amount\n2024-01-01,100".utf8)
        try sourceData.write(to: sourceURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
        }

        var protectCalled = false
        var readObservedProtection = false

        let data = try ImportFileReader.readData(
            from: sourceURL,
            protect: { _ in protectCalled = true },
            read: { copyURL in
                readObservedProtection = protectCalled
                return try Data(contentsOf: copyURL)
            }
        )

        #expect(protectCalled)
        #expect(readObservedProtection)
        #expect(data == sourceData)
    }
}
