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
