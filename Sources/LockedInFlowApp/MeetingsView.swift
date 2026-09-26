import SwiftUI
import VoiceCore

struct MeetingsView: View {
    @EnvironmentObject var state: AppState
    @State private var selected: Meeting?

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(state.meetings) { meeting in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meeting.note.title)
                            .font(.callout.bold())
                            .lineLimit(1)
                        Text(
                            "\(meeting.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(meeting.durationSeconds / 60)) min"
                        )
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    }
                    .tag(meeting)
                }
            }
            .frame(width: 190)

            Divider()

            if let meeting = selected {
                MeetingDetailView(meeting: meeting)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("Select a meeting")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

struct MeetingDetailView: View {
    let meeting: Meeting
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(meeting.markdown)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            HStack(spacing: 8) {
                Button("Copy Markdown") { copy(meeting.markdown) }
                Button("Copy Transcript") { copy(meeting.rawTranscript) }
                Button("Export .md…") { export(meeting) }
                Spacer()
                Button("Delete", role: .destructive) {
                    MeetingStore.shared.delete(id: meeting.id)
                    state.refreshMeetings()
                }
            }
            .controlSize(.small)
            .padding([.horizontal, .bottom], 16)
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        state.statusMessage = "Copied"
    }

    private func export(_ meeting: Meeting) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue =
            "\(meeting.note.title.replacingOccurrences(of: " ", with: "-").lowercased()).md"
        if panel.runModal() == .OK, let url = panel.url {
            try? meeting.markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
