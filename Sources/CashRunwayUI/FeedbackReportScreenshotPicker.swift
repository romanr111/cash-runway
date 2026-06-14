import PhotosUI
import SwiftUI

struct FeedbackReportScreenshotPicker: View {
    @Binding var screenshots: [ReportIssueScreenshot]
    let isLocked: Bool

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var compressionAlertMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !screenshots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(screenshots.enumerated()), id: \.offset) { index, screenshot in
                            thumbnail(for: screenshot, at: index)
                        }
                    }
                }
                .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackScreenshotList)
            }

            let hasScreenshots = !screenshots.isEmpty
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: ReportIssueDraft.maxScreenshots,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                    if hasScreenshots {
                        Text("Change screenshots")
                    } else {
                        Text("Add screenshots")
                    }
                }
                .foregroundStyle(CashRunwayTheme.accent)
            }
            .disabled(isLocked || screenshots.count >= ReportIssueDraft.maxScreenshots)
            .accessibilityIdentifier(CashRunwayAccessibilityID.feedbackScreenshotPicker)
            .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await loadScreenshots(from: newItems) }
        }

            Text(
                L10n.string(
                    "You can attach up to %d screenshots. Images are compressed before sending.",
                    ReportIssueDraft.maxScreenshots
                )
            )
            .font(CashRunwayTheme.captionFont)
            .foregroundStyle(CashRunwayTheme.textSecondary)
        }
        .alert(
            L10n.string("Screenshots Not Attached"),
            isPresented: .init(
                get: { compressionAlertMessage != nil },
                set: { if !$0 { compressionAlertMessage = nil } }
            ),
            actions: {
                Button(L10n.string("OK")) { compressionAlertMessage = nil }
            },
            message: {
                Text(compressionAlertMessage ?? "")
            }
        )
    }

    @ViewBuilder
    private func thumbnail(for screenshot: ReportIssueScreenshot, at index: Int) -> some View {
        if let uiImage = UIImage(data: screenshot.data) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    screenshots.remove(at: index)
                    selectedItems.removeAll()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, CashRunwayTheme.negative)
                        .font(.system(size: 20))
                }
                .disabled(isLocked)
                .offset(x: 6, y: -6)
            }
        }
    }

    private func loadScreenshots(from items: [PhotosPickerItem]) async {
        var loaded: [ReportIssueScreenshot] = []
        var droppedCount = 0
        for item in items {
            guard loaded.count < ReportIssueDraft.maxScreenshots else { break }
            if let screenshot = await loadScreenshot(from: item) {
                loaded.append(screenshot)
            } else {
                droppedCount += 1
            }
        }
        await MainActor.run {
            self.screenshots = loaded
            self.selectedItems = []
            if droppedCount > 0 {
                compressionAlertMessage = L10n.string(
                    "%lld screenshot(s) could not be attached because they were too large after compression.",
                    droppedCount
                )
            }
        }
    }

    private func loadScreenshot(from item: PhotosPickerItem) async -> ReportIssueScreenshot? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        let inputBytes = data.count
        guard let compressed = compress(image: image, inputBytes: inputBytes) else { return nil }
        let filename = generateFilename(mimeType: .jpeg)
        return ReportIssueScreenshot(data: compressed, mimeType: .jpeg, filename: filename)
    }

    private func compress(image: UIImage, inputBytes: Int) -> Data? {
        let maxBytes = ReportIssueDraft.maxScreenshotBytes
        let targetBytes = Int(Double(maxBytes) * 0.85)

        if let data = compress(image: image, maxDimension: 1200, targetBytes: targetBytes, maxBytes: maxBytes, minQuality: 0.3) {
            logCompression(inputBytes: inputBytes, outputBytes: data.count, maxDimension: 1200, quality: nil)
            return data
        }

        if let data = compress(image: image, maxDimension: 800, targetBytes: targetBytes, maxBytes: maxBytes, minQuality: 0.2) {
            logCompression(inputBytes: inputBytes, outputBytes: data.count, maxDimension: 800, quality: nil)
            return data
        }

        return nil
    }

    private func compress(image: UIImage, maxDimension: CGFloat, targetBytes: Int, maxBytes: Int, minQuality: CGFloat) -> Data? {
        let resized = image.resized(toFit: maxDimension)
        var quality: CGFloat = 0.9
        guard var data = resized.jpegData(compressionQuality: quality) else { return nil }

        while data.count > targetBytes && quality > minQuality {
            quality -= 0.1
            if let smaller = resized.jpegData(compressionQuality: quality) {
                data = smaller
            }
        }

        return data.count <= maxBytes ? data : nil
    }

    private func logCompression(inputBytes: Int, outputBytes: Int, maxDimension: CGFloat, quality: CGFloat?) {
        #if DEBUG
        NSLog("[Screenshot] %dx%d JPEG: %d → %d bytes (%.1f:1 ratio)",
              Int(maxDimension), Int(maxDimension),
              inputBytes, outputBytes,
              outputBytes > 0 ? Double(inputBytes) / Double(outputBytes) : 0)
        #endif
    }

    private func generateFilename(mimeType: ReportIssueScreenshotMimeType) -> String {
        let ext = mimeType == .png ? "png" : "jpg"
        return "screenshot-\(UUID().uuidString).\(ext)"
    }
}

private extension UIImage {
    func resized(toFit maxDimension: CGFloat) -> UIImage {
        let width = size.width
        let height = size.height
        guard width > maxDimension || height > maxDimension else { return self }

        let ratio = min(maxDimension / width, maxDimension / height)
        let newSize = CGSize(width: width * ratio, height: height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
