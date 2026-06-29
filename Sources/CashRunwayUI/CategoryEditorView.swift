import Foundation
import SwiftUI
import CashRunwayCore

struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @Binding var category: CashRunwayCategory

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    CashRunwaySurface {
                        HStack(spacing: 16) {
                            CategoryGlyph(iconName: category.iconName, colorHex: category.colorHex, size: 70)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.name.isEmpty ? L10n.string("New Category") : BuiltInCategoryDisplayName.name(category))
                                    .font(CashRunwayTheme.headingFont)
                                    .foregroundStyle(CashRunwayTheme.textPrimary)
                                    .lineLimit(1)
                                Text(category.kind == .income ? "Income" : "Expense")
                                    .font(CashRunwayTheme.bodyFont)
                                    .foregroundStyle(CashRunwayTheme.textSecondary)
                            }
                        }
                    }

                    editorSection("Details") {
                        TextField("Name", text: $category.name)
                            .textFieldStyle(.roundedBorder)
                        Picker("Kind", selection: $category.kind) {
                            Text("Expense").tag(CategoryKind.expense)
                            Text("Income").tag(CategoryKind.income)
                        }
                        .pickerStyle(.segmented)
                    }

                    editorSection("Color") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 10)], spacing: 10) {
                            ForEach(CategoryAppearanceCatalog.colors) { choice in
                                Button {
                                    category.colorHex = choice.colorHex
                                } label: {
                                    CashRunwaySwatch(colorHex: choice.colorHex, isSelected: CategoryAppearanceCatalog.normalizedColorHex(category.colorHex) == choice.colorHex)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(choice.localizedName)
                            }
                        }
                    }

                    editorSection("Symbol") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 12)], spacing: 12) {
                            ForEach(CategoryAppearanceCatalog.icons) { choice in
                                Button {
                                    category.iconName = choice.iconName
                                } label: {
                                    VStack(spacing: 6) {
                                        CategoryGlyph(iconName: choice.iconName, colorHex: category.colorHex, size: 48)
                                        Text(choice.localizedName)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(CashRunwayTheme.textSecondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: CashRunwayTheme.radiusS, style: .continuous)
                                            .fill(CategoryAppearanceCatalog.normalizedIconName(category.iconName) == choice.iconName ? CashRunwayTheme.accentMuted : CashRunwayTheme.pill)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(CashRunwayTheme.background)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        category.iconName = CategoryAppearanceCatalog.normalizedIconName(category.iconName)
                        category.colorHex = CategoryAppearanceCatalog.normalizedColorHex(category.colorHex)
                        category.updatedAt = .now
                        model.saveCategory(category)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            category.iconName = CategoryAppearanceCatalog.normalizedIconName(category.iconName)
            category.colorHex = CategoryAppearanceCatalog.normalizedColorHex(category.colorHex)
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
