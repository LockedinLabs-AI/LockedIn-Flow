import SwiftUI
import VoiceCore

/// One-click learning: turn a mis-hearing into a permanent vocabulary rule.
struct TeachCorrectionView: View {
    let entry: HistoryEntry
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var heard: String
    @State private var written: String
    @State private var saved = false

    init(entry: HistoryEntry) {
        self.entry = entry
        _heard = State(initialValue: "")
        _written = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TEACH A CORRECTION")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.6)

            Text("“\(entry.final)”")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHEN YOU SAY")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    TextField("e.g. kimik", text: $heard)
                        .textFieldStyle(.roundedBorder)
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text("WRITES")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    TextField("e.g. Kimi K3", text: $written)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("Saved to your vocabulary and used in every future cleanup — on-device only.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(saved ? "Saved ✓" : "Save Rule") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        heard.trimmingCharacters(in: .whitespaces).isEmpty
                            || written.isEmpty
                            || saved
                            || !state.canChangeTranscriptPolicy
                    )
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private func save() {
        let normalizedHeard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        let normalizedWritten = written.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        let rule = VocabularyRule(
            spoken: normalizedHeard,
            written: normalizedWritten
        )
        do {
            try VocabularyStore.addRule(rule)
            state.controller.reloadVocabulary()
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}
