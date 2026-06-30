import CashRunwayCore
import Foundation

public enum ImportFileReader {
    public static func readData(from url: URL) throws -> Data {
        try readData(
            from: url,
            protect: { FileProtectionService().protect($0) },
            read: { try Data(contentsOf: $0) }
        )
    }

    static func readData(
        from url: URL,
        protect: (URL) -> Void,
        read: (URL) throws -> Data
    ) throws -> Data {
        let copyURL = try temporaryAccessibleCopy(from: url, protect: protect)
        defer {
            try? FileManager.default.removeItem(at: copyURL)
        }
        return try read(copyURL)
    }

    public static func readCSVData(from url: URL) throws -> (data: Data, fileKind: StatementFileKind) {
        let data = try readData(from: url)
        if url.pathExtension.lowercased() == "xlsx" {
            let csvText = try XLSXConverter.convertToCSV(data: data)
            return (Data(csvText.utf8), .xlsx)
        }

        return (data, .csv)
    }

    private static func temporaryAccessibleCopy(from url: URL, protect: (URL) -> Void) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent("CashRunwayImports", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileName = url.lastPathComponent.isEmpty ? "import" : url.lastPathComponent
        let destinationURL = directoryURL.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var coordinatedError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinatedError
        ) { coordinatedURL in
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: coordinatedURL, to: destinationURL)
                protect(destinationURL)
            } catch {
                copyError = error
            }
        }

        if let copyError {
            throw copyError
        }
        if let coordinatedError {
            throw coordinatedError
        }
        return destinationURL
    }
}
