import PhotosUI
import SwiftUI

struct FeedbackReportScreenshotPicker: View {
    @Binding var screenshots: [ReportIssueScreenshot]
    let isLocked: Bool

    @State private var selectedItems: [PhotosPickerItem] = []

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
        for item in items {
            guard loaded.count < ReportIssueDraft.maxScreenshots else { break }
            if let screenshot = await loadScreenshot(from: item) {
                loaded.append(screenshot)
            }
        }
        await MainActor.run {
            self.screenshots = loaded
            self.selectedItems = []
        }
    }

    private func loadScreenshot(from item: PhotosPickerItem) async -> ReportIssueScreenshot? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        guard let compressed = compress(image: image) else { return nil }
        let filename = generateFilename(mimeType: .jpeg)
        return ReportIssueScreenshot(data: compressed, mimeType: .jpeg, filename: filename)
    }

    private func compress(image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1200
        let maxBytes = ReportIssueDraft.maxScreenshotBytes
        let targetBytes = Int(Double(maxBytes) * 0.85)

        let resized = image.resized(toFit: maxDimension)
        var quality: CGFloat = 0.9
        guard var data = resized.jpegData(compressionQuality: quality) else { return nil }

        while data.count > targetBytes && quality > 0.3 {
            quality -= 0.1
            if let smaller = resized.jpegData(compressionQuality: quality) {
                data = smaller
            }
        }

        return data.count <= maxBytes ? data : nil
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
