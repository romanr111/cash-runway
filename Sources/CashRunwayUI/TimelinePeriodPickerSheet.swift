import CashRunwayCore
import SwiftUI

struct TimelinePeriodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: CashRunwayAppModel

    @State private var mode: TimelinePeriod
    @State private var selectedMonthKey: Int

    private var maxMonthKey: Int { model.maxMonthKey }

    init(model: CashRunwayAppModel) {
        self.model = model
        _mode = State(initialValue: model.selectedTimelinePeriod)
        _selectedMonthKey = State(initialValue: model.selectedMonthKey)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L10n.string("Period mode"), selection: $mode) {
                        Text(L10n.timelinePeriod(.month)).tag(TimelinePeriod.month)
                        Text(L10n.timelinePeriod(.year)).tag(TimelinePeriod.year)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }

                Section {
                    switch mode {
                    case .month:
                        monthList
                    case .year:
                        yearList
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(L10n.string("Select Period"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.string("Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("Done")) {
                        applySelection()
                    }
                }
            }
        }
    }

    private var monthList: some View {
        ForEach(monthKeys, id: \.self) { monthKey in
            Button {
                selectedMonthKey = monthKey
            } label: {
                HStack {
                    Text(CashRunwayTheme.monthFullLabel(for: monthKey))
                    Spacer()
                    if monthKey == selectedMonthKey {
                        Image(systemName: "checkmark")
                            .foregroundStyle(CashRunwayTheme.accent)
                    }
                }
            }
            .foregroundStyle(CashRunwayTheme.textPrimary)
            .accessibilityIdentifier(CashRunwayAccessibilityID.timelineMonthPickerOption(monthKey))
        }
    }

    private var yearList: some View {
        ForEach(years, id: \.self) { year in
            Button {
                selectedMonthKey = year * 100 + 1
            } label: {
                HStack {
                    Text("\(year)")
                    Spacer()
                    if isYearSelected(year) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(CashRunwayTheme.accent)
                    }
                }
            }
            .foregroundStyle(CashRunwayTheme.textPrimary)
            .accessibilityIdentifier(CashRunwayAccessibilityID.timelineYearPickerOption(year))
        }
    }

    private var monthKeys: [Int] {
        let end = maxMonthKey
        var keys: [Int] = []
        let calendar = DateKeys.calendar
        let endDate = DateKeys.startOfMonth(for: end)
        var currentDate = calendar.date(byAdding: .month, value: -23, to: endDate) ?? endDate
        let minKey = DateKeys.monthKey(for: currentDate)
        var currentKey = minKey
        while currentKey <= end {
            keys.append(currentKey)
            currentDate = calendar.date(byAdding: .month, value: 1, to: DateKeys.startOfMonth(for: currentKey)) ?? currentDate
            currentKey = DateKeys.monthKey(for: currentDate)
            if currentKey <= minKey { break }
        }
        if keys.isEmpty { keys.append(end) }
        return keys.sorted()
    }

    private var years: [Int] {
        let maxYear = maxMonthKey / 100
        let minYear = max(2024, maxYear - 4)
        return Array(minYear...maxYear)
    }

    private func isYearSelected(_ year: Int) -> Bool {
        mode == .year && selectedMonthKey / 100 == year
    }

    private func applySelection() {
        guard selectedMonthKey != model.selectedMonthKey || mode != model.selectedTimelinePeriod else {
            dismiss()
            return
        }
        if model.selectedTimelinePeriod != mode {
            model.selectTimelinePeriod(mode)
        }
        model.selectedMonthKey = selectedMonthKey
        dismiss()
        model.reloadTimeline()
    }
}
