import Foundation
import SwiftUI
import CashRunwayCore

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var selectedKind: CategoryKind
    @State private var items: [CategoryManagementItem] = []
    @State private var showsEditor = false
    @State private var showsMergeSheet = false
        @State private var categoryDraft = CashRunwayCategory(
            id: UUID(),
            name: "",
            kind: .expense,
            iconName: CategoryAppearanceCatalog.defaultIcon,
            colorHex: CategoryAppearanceCatalog.defaultColor,
            parentID: nil,
            isSystem: false,
            isArchived: false,
            sortOrder: 0,
            createdAt: Date.now,
            updatedAt: Date.now
        )

    init(model: CashRunwayAppModel, initialKind: CategoryKind) {
        self.model = model
        _selectedKind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.string("%d total · %d visible · %d hidden", items.count, visibleCount, hiddenCount).uppercased(with: L10n.locale))
                        .font(CashRunwayTheme.captionFont)
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                        .padding(.horizontal, 2)

                    Picker("Kind", selection: $selectedKind) {
                        Text("Expenses").tag(CategoryKind.expense)
                        Text("Income").tag(CategoryKind.income)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.top, 8)
                .padding(.bottom, 2)
                .listRowBackground(CashRunwayTheme.background)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier(CashRunwayAccessibilityID.categoryManagementScreen)

                ForEach(items) { item in
                    CategoryManagementRow(
                        item: item,
                        onEdit: {
                            categoryDraft = item.category
                            showsEditor = true
                        },
                        onToggleVisibility: {
                            model.toggleCategoryVisibility(item.category)
                            reload()
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 10))
                    .listRowBackground(CashRunwayTheme.background)
                    .listRowSeparator(.hidden)
                }
                .onMove(perform: moveItems)

                Color.clear
                    .frame(height: 76)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(CashRunwayTheme.background)
                    .listRowSeparator(.hidden)
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(CashRunwayTheme.background)
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        categoryDraft = newCategoryDraft()
                        showsEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(CashRunwayTheme.accent, in: Circle())
                    }

                    Spacer()

                    Button("Merge categories...") {
                        showsMergeSheet = true
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(CashRunwayTheme.surface, in: Capsule())
                    .overlay(Capsule().stroke(CashRunwayTheme.line, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.regularMaterial)
            }
            .sheet(isPresented: $showsEditor, onDismiss: reload) {
                CategoryEditorView(model: model, category: $categoryDraft)
            }
            .sheet(isPresented: $showsMergeSheet, onDismiss: reload) {
                CategoryMergeView(model: model, kind: selectedKind)
            }
            .onAppear(perform: reload)
            .onChange(of: selectedKind) { _, _ in reload() }
        }
    }

    private func reload() {
        items = model.categoryManagementItems(kind: selectedKind)
    }

    private var visibleCount: Int {
        items.filter(\.isVisible).count
    }

    private var hiddenCount: Int {
        items.count - visibleCount
    }

    private func newCategoryDraft() -> CashRunwayCategory {
        CashRunwayCategory(
            id: UUID(),
            name: "",
            kind: selectedKind,
            iconName: CategoryAppearanceCatalog.defaultIcon,
            colorHex: CategoryAppearanceCatalog.defaultColor,
            parentID: nil,
            isSystem: false,
            isArchived: false,
            sortOrder: items.count,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        model.reorderCategories(kind: selectedKind, orderedCategoryIDs: items.map(\.category.id))
        reload()
    }
}

private struct CategoryManagementRow: View {
    let item: CategoryManagementItem
    let onEdit: () -> Void
    let onToggleVisibility: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    CategoryGlyph(iconName: item.category.iconName, colorHex: item.category.colorHex, size: 50)
                        .opacity(item.isVisible ? 1 : 0.58)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(BuiltInCategoryDisplayName.name(item.category))
                                .font(CashRunwayTheme.subheadingFont)
                                .foregroundStyle(item.isVisible ? CashRunwayTheme.textPrimary : CashRunwayTheme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            if !item.isVisible {
                                Text("Hidden")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(CashRunwayTheme.textMuted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(CashRunwayTheme.pill, in: Capsule())
                            }
                        }

                        Text("\(L10n.transactionCount(item.transactionCount)) · \(L10n.walletCount(item.walletCount))")
                            .font(CashRunwayTheme.captionFont)
                            .foregroundStyle(CashRunwayTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .layoutPriority(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("Edit %@", BuiltInCategoryDisplayName.name(item.category)))
            .layoutPriority(1)

            Spacer(minLength: 6)

            Menu {
                Button {
                    onEdit()
                } label: {
                    SwiftUI.Label("Edit", systemImage: "pencil")
                }

                Button {
                    onToggleVisibility()
                } label: {
                    SwiftUI.Label(item.isVisible ? "Hide" : "Show", systemImage: item.isVisible ? "eye.slash.fill" : "eye.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(CashRunwayTheme.pill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Category actions")
        }
        .padding(.vertical, 13)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 76)
        .background(item.isVisible ? CashRunwayTheme.surface : CashRunwayTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CashRunwayTheme.radiusM, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

private struct CategoryMergeView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    let kind: CategoryKind
    @State private var sourceID: UUID?
    @State private var destinationID: UUID?
    @State private var items: [CategoryManagementItem] = []
    @State private var mergeResult: CategoryMergeResult?
    @State private var isMerging = false
    @State private var mergeProgress = 0.0
    @State private var mergeStatus = L10n.string("Preparing merge")
    @State private var mergeTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if let mergeResult {
                    mergeSuccessView(mergeResult)
                } else {
                    mergeForm
                }
            }
            .navigationTitle(mergeResult == nil ? L10n.string("Merge Categories") : L10n.string("Merge Complete"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if mergeResult == nil {
                        Button(L10n.string("Cancel")) { dismiss() }
                            .disabled(isMerging)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if mergeResult != nil {
                        Button(L10n.string("Done")) { dismiss() }
                    }
                }
            }
            .onAppear(perform: reloadItems)
            .onDisappear {
                mergeTask?.cancel()
                mergeTask = nil
            }
        }
    }

    private var mergeForm: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.accentDark)
                        .frame(width: 48, height: 48)
                        .background(CashRunwayTheme.accentMuted, in: Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("Combine duplicate categories"))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(CashRunwayTheme.textPrimary)
                        Text(L10n.string("Transactions, recurring templates, and bank rules move to the category you keep. The source category is hidden after merge."))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CashRunwayTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))

                categoryPicker(
                    title: L10n.string("Merge from"),
                    subtitle: L10n.string("This category will be hidden"),
                    placeholder: L10n.string("Choose source category"),
                    selection: $sourceID,
                    excludedID: destinationID
                )
                .disabled(isMerging)

                Image(systemName: "arrow.down")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
                    .frame(width: 44, height: 44)
                    .background(CashRunwayTheme.pill, in: Circle())

                categoryPicker(
                    title: L10n.string("Keep as destination"),
                    subtitle: L10n.string("All linked records move here"),
                    placeholder: L10n.string("Choose destination category"),
                    selection: $destinationID,
                    excludedID: sourceID
                )
                .disabled(isMerging)

                if let sourceItem, let destinationItem {
                    mergePreview(sourceItem: sourceItem, destinationItem: destinationItem)
                    if isMerging {
                        mergeProgressView(sourceItem: sourceItem, destinationItem: destinationItem)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 108)
        }
        .scrollContentBackground(.hidden)
        .background(CashRunwayTheme.background)
        .safeAreaInset(edge: .bottom) {
            Button {
                mergeSelectedCategories()
            } label: {
                HStack(spacing: 10) {
                    if isMerging {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text(L10n.string("Merging Categories"))
                            .font(.system(size: 17, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                        Text(L10n.string("Merge Categories"))
                            .font(.system(size: 17, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(hasMergeSelection ? CashRunwayTheme.accentDark : CashRunwayTheme.textMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(!hasMergeSelection || isMerging)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var managementItems: [CategoryManagementItem] {
        items
    }

    private var sourceItem: CategoryManagementItem? {
        guard let sourceID else { return nil }
        return managementItems.first { $0.category.id == sourceID }
    }

    private var destinationItem: CategoryManagementItem? {
        guard let destinationID else { return nil }
        return managementItems.first { $0.category.id == destinationID }
    }

    private var hasMergeSelection: Bool {
        sourceID != nil && destinationID != nil && sourceID != destinationID
    }

    private func categoryPicker(
        title: String,
        subtitle: String,
        placeholder: String,
        selection: Binding<UUID?>,
        excludedID: UUID?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .textCase(.uppercase)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textMuted)
            }

            Menu {
                Button(L10n.string("Clear Selection")) {
                    selection.wrappedValue = nil
                }
                ForEach(managementItems.filter { $0.category.id != excludedID }) { item in
                    Button {
                        selection.wrappedValue = item.category.id
                    } label: {
                        SwiftUI.Label(BuiltInCategoryDisplayName.name(item.category), systemImage: item.category.iconName ?? "circle.fill")
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    if let selected = managementItems.first(where: { $0.category.id == selection.wrappedValue }) {
                        CategoryGlyph(iconName: selected.category.iconName, colorHex: selected.category.colorHex, size: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(BuiltInCategoryDisplayName.name(selected.category))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CashRunwayTheme.textPrimary)
                            Text(L10n.transactionCount(selected.transactionCount))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(CashRunwayTheme.textSecondary)
                        }
                    } else {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(CashRunwayTheme.textMuted)
                            .frame(width: 46, height: 46)
                            .background(CashRunwayTheme.pill, in: Circle())
                        Text(placeholder)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CashRunwayTheme.textSecondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CashRunwayTheme.textMuted)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
    }

    private func mergePreview(sourceItem: CategoryManagementItem, destinationItem: CategoryManagementItem) -> some View {
        let totalTransactions = sourceItem.transactionCount + destinationItem.transactionCount
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CategoryGlyph(iconName: sourceItem.category.iconName, colorHex: sourceItem.category.colorHex, size: 42)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
                CategoryGlyph(iconName: destinationItem.category.iconName, colorHex: destinationItem.category.colorHex, size: 42)
                Spacer()
                Text("\(totalTransactions)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                Text(L10n.string("tx"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
            }

            VStack(alignment: .leading, spacing: 8) {
                mergeFact(icon: "checkmark.seal.fill", text: L10n.string("Transactions are preserved; only category references change."))
                mergeFact(icon: "eye.slash.fill", text: L10n.string("%@ becomes hidden after merge.", BuiltInCategoryDisplayName.name(sourceItem.category)))
                mergeFact(icon: "chart.bar.fill", text: L10n.string("%@ keeps %@ total.", BuiltInCategoryDisplayName.name(destinationItem.category), L10n.transactionCount(totalTransactions)))
            }
        }
        .padding(18)
        .background(CashRunwayTheme.accentMuted, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CashRunwayTheme.accent.opacity(0.35), lineWidth: 1))
    }

    private func mergeFact(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.accentDark)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CashRunwayTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mergeProgressView(sourceItem: CategoryManagementItem, destinationItem: CategoryManagementItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.accentDark)
                    .frame(width: 40, height: 40)
                    .background(CashRunwayTheme.accentMuted, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(mergeStatus)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CashRunwayTheme.textPrimary)
                    Text(L10n.string("%@ is moving into %@", BuiltInCategoryDisplayName.name(sourceItem.category), BuiltInCategoryDisplayName.name(destinationItem.category)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CashRunwayTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(L10n.string("%lld%%", Int((mergeProgress * 100).rounded())))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .monospacedDigit()
            }

            ProgressView(value: mergeProgress, total: 1)
                .progressViewStyle(.linear)
                .tint(CashRunwayTheme.accentDark)
                .accessibilityLabel(L10n.string("Merge progress"))
                .accessibilityValue(L10n.string("%lld percent", Int((mergeProgress * 100).rounded())))

            Text(L10n.string("Transactions stay intact while category references are updated."))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CashRunwayTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    private func mergeSuccessView(_ result: CategoryMergeResult) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(CashRunwayTheme.accentMuted)
                    .frame(width: 112, height: 112)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(CashRunwayTheme.accentDark)
            }

            VStack(spacing: 10) {
                Text(L10n.string("Merged into %@", BuiltInCategoryDisplayName.name(result.destination)))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(CashRunwayTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(L10n.string("All existing transactions were preserved and now point to the destination category."))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CashRunwayTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                CategoryGlyph(iconName: result.source.iconName, colorHex: result.source.colorHex, size: 54)
                    .opacity(0.55)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CashRunwayTheme.textMuted)
                CategoryGlyph(iconName: result.destination.iconName, colorHex: result.destination.colorHex, size: 54)
            }
            .padding(.vertical, 4)

            VStack(spacing: 10) {
                successMetric(value: "\(result.totalTransactionCount)", label: L10n.string("transactions kept"))
                successMetric(value: result.source.name, label: L10n.string("hidden source"))
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(CashRunwayTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(CashRunwayTheme.line, lineWidth: 1))

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CashRunwayTheme.background)
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text(L10n.string("Done"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(CashRunwayTheme.accentDark, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private func successMetric(value: String, label: String) -> some View {
        HStack {
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer()
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CashRunwayTheme.textMuted)
        }
    }

    private func mergeSelectedCategories() {
        guard !isMerging, let sourceItem, let destinationItem else { return }
        let result = CategoryMergeResult(source: sourceItem.category, destination: destinationItem.category, totalTransactionCount: sourceItem.transactionCount + destinationItem.transactionCount)

        mergeTask?.cancel()
        mergeTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.18)) {
                isMerging = true
                mergeProgress = 0.35
                mergeStatus = L10n.string("Updating linked records")
            }
            await Task.yield()
            guard !Task.isCancelled else { return }

            let didMerge = model.mergeCategory(oldCategoryID: sourceItem.category.id, into: destinationItem.category.id)
            guard !Task.isCancelled else { return }

            if didMerge {
                withAnimation(.easeInOut(duration: 0.18)) {
                    mergeProgress = 0.82
                    mergeStatus = L10n.string("Refreshing totals")
                }

                reloadItems()
                withAnimation(.easeInOut(duration: 0.18)) {
                    mergeProgress = 1
                    mergeStatus = L10n.string("Merge complete")
                }

                sourceID = nil
                destinationID = nil
                isMerging = false
                mergeTask = nil
                mergeResult = result
            } else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isMerging = false
                    mergeProgress = 0
                    mergeStatus = L10n.string("Preparing merge")
                }
                mergeTask = nil
            }
        }
    }

    private func reloadItems() {
        items = model.categoryManagementItems(kind: kind)
    }
}

private struct CategoryMergeResult {
    let source: CashRunwayCategory
    let destination: CashRunwayCategory
    let totalTransactionCount: Int
}

