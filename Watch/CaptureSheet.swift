import SwiftUI

/// Used when capture is triggered programmatically (from the complication deep link),
/// where `TextFieldLink` cannot be tapped for us. Focusing the field on appear brings up
/// the system input sheet with dictation already offered.
struct CaptureSheet: View {
    @Environment(CraftStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            TextField(store.destination.label, text: $text)
                .focused($isFocused)
                .onSubmit(submit)

            Button("Save", action: submit)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 4)
        .onAppear { isFocused = true }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        dismiss()
    }
}
