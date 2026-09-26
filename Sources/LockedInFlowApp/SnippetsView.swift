import SwiftUI
import VoiceCore

struct SnippetsView: View {
    @EnvironmentObject var state: AppState
    @State private var library: SnippetLibrary = SnippetStore.load()
    @State private var newTrigger = ""
    @State private var newExpansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snippets")
                .font(.headline)
            Text(
                "Say the trigger as a complete utterance — the expansion is inserted instead. “insert signature” → your full signature block."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(alignment: .top) {
                TextField("Trigger phrase", text: $newTrigger)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
                TextField("Expansion (multi-line ok)", text: $newExpansion, axis: .vertical)
                    .lineLimit(2...4)
                Button("Add") { addSnippet() }
                    .disabled(
                        newTrigger.trimmingCharacters(in: .whitespaces).isEmpty
                            || newExpansion.isEmpty)
            }

            List {
                ForEach(library.snippets) { snippet in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(snippet.trigger)
                                .font(.callout.bold())
                            Spacer()
                            Button(role: .destructive) {
                                remove(snippet)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        Text(snippet.expansion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 140)
        }
        .padding(8)
    }

    private func addSnippet() {
        library.snippets.append(
            Snippet(
                trigger: newTrigger.trimmingCharacters(in: .whitespaces), expansion: newExpansion))
        newTrigger = ""
        newExpansion = ""
        save()
    }

    private func remove(_ snippet: Snippet) {
        library.snippets.removeAll { $0.id == snippet.id }
        save()
    }

    private func save() {
        SnippetStore.save(library)
        state.controller.reloadSnippets()
    }
}
