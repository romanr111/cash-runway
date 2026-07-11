import Foundation
import SwiftUI
import CashRunwayCore

struct LabelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var label: CashRunwayLabel

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    CashRunwaySurface {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(CashRunwayTheme.categoryColor(label.colorHex))
                                .frame(width: 26, height: 26)
                                .frame(width: 64, height: 64)
                                .background(CashRunwayTheme.pill, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label.name.isEmpty ? "New Label" : label.name)
                                    .font(CashRunwayTheme.headingFont)
                                    .foregroundStyle(CashRunwayTheme.textPrimary)
                                    .lineLimit(1)
                                Text("Transaction label")
                                    .font(CashRunwayTheme.bodyFont)
                                    .foregroundStyle(CashRunwayTheme.textSecondary)
                            }
                        }
                    }

                    editorSection("Details") {
                        TextField("Name", text: $label.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    editorSection("Color") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 10)], spacing: 10) {
                            ForEach(CategoryAppearanceCatalog.colors) { choice in
                                Button {
                                    label.colorHex = choice.colorHex
                                } label: {
                                    CashRunwaySwatch(colorHex: choice.colorHex, isSelected: CategoryAppearanceCatalog.normalizedColorHex(label.colorHex) == choice.colorHex)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(choice.localizedName)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(CashRunwayTheme.background)
            .navigationTitle("Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        label.colorHex = CategoryAppearanceCatalog.normalizedColorHex(label.colorHex)
                        label.updatedAt = .now
                        model.saveLabel(label)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            label.colorHex = CategoryAppearanceCatalog.normalizedColorHex(label.colorHex)
        }
    }

    private func editorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textMuted)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .ledgerSurface()
        }
    }
}
