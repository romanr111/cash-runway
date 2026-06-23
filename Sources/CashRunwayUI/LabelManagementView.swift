import Foundation
import SwiftUI
import CashRunwayCore

struct LabelManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel
    @State private var isEditorPresented = false
    @State private var labelDraft = CashRunwayLabel(id: UUID(), name: "", colorHex: "#60788A", createdAt: Date.now, updatedAt: Date.now)

    var body: some View {
        NavigationStack {
            List {
                EmptyView().accessibilityIdentifier(CashRunwayAccessibilityID.labelManagementScreen)
                ForEach(model.labels) { label in
                    Button(label.name) {
                        labelDraft = label
                        isEditorPresented = true
                    }
                }
            }
            .navigationTitle("Labels")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        labelDraft = CashRunwayLabel(id: UUID(), name: "", colorHex: "#60788A", createdAt: .now, updatedAt: .now)
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                LabelEditorView(model: model, label: $labelDraft)
            }
        }
    }
}
