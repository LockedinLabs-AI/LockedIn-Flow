import SwiftUI

/// Side-by-side raw transcript vs. cleaned output, with one-click reversion.
/// Proof the cleanup layer never invents content.
struct CompareView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RAW VS FINAL")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.6)

            HStack(alignment: .top, spacing: 12) {
                column(title: "RAW (as heard)", text: state.lastRaw)
                column(title: "FINAL (as inserted)", text: state.lastFinal)
            }

            HStack {
                Button("Use Raw Instead") {
                    state.lastFinal = state.lastRaw
                    state.reinsertLastTranscript()
                    dismiss()
                }
                .disabled(
                    state.lastRaw.isEmpty
                        || state.lastRaw == state.lastFinal
                        || state.pendingReinsertInspection != nil
                )
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
    }

    private func column(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            ScrollView {
                Text(text.isEmpty ? "—" : text)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(width: 240, height: 180)
            .padding(8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
