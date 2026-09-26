import SwiftUI
import UniformTypeIdentifiers
import VoiceCore

struct VocabularyView: View {
    @EnvironmentObject var state: AppState
    @State private var vocabulary: Vocabulary = VocabularyStore.load()
    @State private var newSpoken = ""
    @State private var newWritten = ""
    @State private var newCaseSensitive = false
    @State private var importStatus: String?

    private var suggestions: [VocabularySuggestion] {
        VocabularySuggester.suggest(from: state.historyEntries, vocabulary: vocabulary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom vocabulary")
                .font(.headline)
            Text("Whole-word replacements applied after cleanup. “super base” → “Supabase”.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Learn corrections from my edits", isOn: $state.learnFromEditsEnabled)
            Text(
                "After a dictation is inserted, LockedIn Flow re-checks only that exact field for 30 seconds to notice a fix you make — like correcting a name — and saves it as a rule you can undo. Values are compared in memory on this Mac and never sent. Off by default and never active in secure fields."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LEARNED FROM YOUR DICTATIONS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .tracking(1.2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(suggestions) { suggestion in
                                Button {
                                    addSuggested(suggestion)
                                } label: {
                                    Text("\(suggestion.term) ×\(suggestion.count)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Color(nsColor: .systemTeal).opacity(0.15), in: Capsule()
                                        )
                                        .overlay(
                                            Capsule().strokeBorder(
                                                Color(nsColor: .systemTeal).opacity(0.4),
                                                lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                                .help("Add “\(suggestion.term)” to your vocabulary")
                            }
                        }
                    }
                }
            }

            HStack {
                TextField("Spoken (as heard)", text: $newSpoken)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                TextField("Written (as inserted)", text: $newWritten)
                Toggle("Aa", isOn: $newCaseSensitive)
                    .toggleStyle(.button)
                    .help("Case-sensitive match")
                Button("Add") { addRule() }
                    .disabled(
                        newSpoken.isEmpty || newWritten.isEmpty
                            || vocabulary.rules.count >= VocabularyStore.maximumVocabularyRules
                    )
            }

            List {
                ForEach(vocabulary.rules) { rule in
                    HStack {
                        Text(rule.spoken)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Text(rule.written)
                            .bold()
                        if rule.caseSensitive {
                            Text("Aa")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            remove(rule)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 140)

            HStack {
                Button("Import CSV…") { importCSV() }
                Button("Export CSV…") { exportCSV() }
                Spacer()
                if let importStatus {
                    Text(importStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
    }

    private func addRule() {
        let spoken = newSpoken.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        let written = newWritten.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        do {
            vocabulary = try VocabularyStore.addRule(
                VocabularyRule(
                    spoken: spoken,
                    written: written,
                    caseSensitive: newCaseSensitive
                ))
            newSpoken = ""
            newWritten = ""
            newCaseSensitive = false
            importStatus = nil
            state.controller.reloadVocabulary()
        } catch {
            vocabulary = VocabularyStore.load()
            importStatus = error.localizedDescription
        }
    }

    private func addSuggested(_ suggestion: VocabularySuggestion) {
        guard
            !vocabulary.rules.contains(where: {
                $0.spoken.lowercased() == suggestion.term.lowercased()
            })
        else { return }
        do {
            vocabulary = try VocabularyStore.addRule(
                VocabularyRule(spoken: suggestion.term, written: suggestion.term)
            )
            importStatus = nil
            state.controller.reloadVocabulary()
        } catch {
            vocabulary = VocabularyStore.load()
            importStatus = error.localizedDescription
        }
    }

    private func remove(_ rule: VocabularyRule) {
        do {
            vocabulary = try VocabularyStore.removeRule(id: rule.id)
            importStatus = nil
            state.controller.reloadVocabulary()
        } catch {
            vocabulary = VocabularyStore.load()
            importStatus = error.localizedDescription
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= VocabularyStore.maximumImportBytes else {
                throw VocabularyImportError.fileTooLarge
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            let report = try VocabularyStore.importCSVAndSave(text)
            vocabulary = report.vocabulary
            state.controller.reloadVocabulary()
            let skipped = report.skippedCount > 0 ? "; skipped \(report.skippedCount)" : ""
            importStatus =
                "Imported \(report.importedCount) rule\(report.importedCount == 1 ? "" : "s")\(skipped)"
        } catch {
            importStatus = error.localizedDescription
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "lockedinflow-vocabulary.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try VocabularyStore.exportCSV(vocabulary).write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
            let exportedCount = vocabulary.rules.lazy.filter { $0.sourceID == nil }.count
            importStatus = "Exported \(exportedCount) rule\(exportedCount == 1 ? "" : "s")"
        } catch {
            importStatus = "Export failed: \(error.localizedDescription)"
        }
    }
}
