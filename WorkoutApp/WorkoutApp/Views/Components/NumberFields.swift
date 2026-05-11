import SwiftUI

struct OptionalDoubleField: View {
    let label: String
    @Binding var value: Double?
    var width: CGFloat = 80
    @State private var text: String = ""

    var body: some View {
        TextField(label, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .onAppear { syncFromValue() }
            .onChange(of: value) { _, _ in syncFromValue() }
            .onChange(of: text) { _, newValue in
                let next: Double? = newValue.isEmpty ? nil : Double(newValue)
                if value != next { value = next }
            }
    }

    private func syncFromValue() {
        let next = value.map { String(format: "%.4g", $0) } ?? ""
        if text != next { text = next }
    }
}

struct OptionalIntField: View {
    let label: String
    @Binding var value: Int?
    var width: CGFloat = 80
    @State private var text: String = ""

    var body: some View {
        TextField(label, text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .onAppear { syncFromValue() }
            .onChange(of: value) { _, _ in syncFromValue() }
            .onChange(of: text) { _, newValue in
                let next: Int? = newValue.isEmpty ? nil : Int(newValue)
                if value != next { value = next }
            }
    }

    private func syncFromValue() {
        let next = value.map(String.init) ?? ""
        if text != next { text = next }
    }
}

struct RequiredIntField: View {
    let label: String
    @Binding var value: Int
    var width: CGFloat = 80
    @State private var text: String = ""

    var body: some View {
        TextField(label, text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .onAppear { syncFromValue() }
            .onChange(of: value) { _, _ in syncFromValue() }
            .onChange(of: text) { _, newValue in
                guard let parsed = Int(newValue), parsed >= 0 else { return }
                if value != parsed { value = parsed }
            }
    }

    private func syncFromValue() {
        let next = String(value)
        if text != next { text = next }
    }
}

struct OptionalDurationField: View {
    @Binding var value: Int?
    var hourWidth: CGFloat = 44
    var minuteWidth: CGFloat = 52
    var secondWidth: CGFloat = 52

    @State private var showsHours = false
    @State private var hoursPart: Int?
    @State private var minutesPart: Int?
    @State private var secondsPart: Int?
    @State private var isSyncing = false

    var body: some View {
        HStack(spacing: 8) {
            if showsHours {
                durationPartField(label: "hr", value: hoursBinding, width: hourWidth)
            }
            durationPartField(label: "min", value: minutesBinding, width: minuteWidth)
            durationPartField(label: "sec", value: secondsBinding, width: secondWidth)
            Button {
                toggleHours()
            } label: {
                Image(systemName: showsHours ? "minus.circle" : "plus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(showsHours ? "Hide hours" : "Add hours")
            Button {
                clear()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(value == nil ? .tertiary : .secondary)
            .disabled(value == nil)
            .accessibilityLabel("Clear duration")
        }
        .onAppear { syncFromValue(adjustHoursVisibility: true) }
        .onChange(of: value) { _, _ in syncFromValue(adjustHoursVisibility: false) }
        .onChange(of: hoursPart) { _, _ in writeValueFromParts() }
        .onChange(of: minutesPart) { _, _ in writeValueFromParts() }
        .onChange(of: secondsPart) { _, _ in writeValueFromParts() }
    }

    private var hoursBinding: Binding<Int?> {
        Binding(
            get: { hoursPart },
            set: { hoursPart = Self.clamp($0, max: 99) }
        )
    }

    private var minutesBinding: Binding<Int?> {
        Binding(
            get: { minutesPart },
            set: { minutesPart = Self.clamp($0, max: showsHours ? 59 : 999) }
        )
    }

    private var secondsBinding: Binding<Int?> {
        Binding(
            get: { secondsPart },
            set: { secondsPart = Self.clamp($0, max: 59) }
        )
    }

    private func durationPartField(
        label: String,
        value: Binding<Int?>,
        width: CGFloat
    ) -> some View {
        HStack(spacing: 3) {
            OptionalIntField(label: label, value: value, width: width)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private func syncFromValue(adjustHoursVisibility: Bool) {
        isSyncing = true
        defer { isSyncing = false }

        guard let value else {
            hoursPart = nil
            minutesPart = nil
            secondsPart = nil
            if adjustHoursVisibility { showsHours = false }
            return
        }

        let safeValue = max(0, value)
        if adjustHoursVisibility {
            showsHours = safeValue >= 3_600
        }

        if showsHours {
            hoursPart = safeValue / 3_600
            minutesPart = (safeValue % 3_600) / 60
        } else {
            hoursPart = nil
            minutesPart = safeValue / 60
        }
        secondsPart = safeValue % 60
    }

    private func writeValueFromParts() {
        guard !isSyncing else { return }

        guard hoursPart != nil || minutesPart != nil || secondsPart != nil else {
            if value != nil { value = nil }
            return
        }

        let total = ((showsHours ? hoursPart : nil) ?? 0) * 3_600
            + (minutesPart ?? 0) * 60
            + (secondsPart ?? 0)
        if value != total {
            value = total
        }
    }

    private func toggleHours() {
        showsHours.toggle()
        syncFromValue(adjustHoursVisibility: false)
    }

    private func clear() {
        value = nil
        syncFromValue(adjustHoursVisibility: true)
    }

    private static func clamp(_ value: Int?, max upperBound: Int) -> Int? {
        guard let value else { return nil }
        return min(max(value, 0), upperBound)
    }
}
