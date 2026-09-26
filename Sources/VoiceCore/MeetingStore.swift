import Foundation

public struct Meeting: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var createdAt: Date
    public var durationSeconds: TimeInterval
    public var rawTranscript: String
    public var note: MeetingNote

    public init(
        id: UUID = UUID(), createdAt: Date = Date(), durationSeconds: TimeInterval,
        rawTranscript: String, note: MeetingNote
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.rawTranscript = rawTranscript
        self.note = note
    }

    public var markdown: String {
        var lines = [
            "# \(note.title)",
            "",
            "\(createdAt.formatted(date: .long, time: .shortened)) · \(Int(durationSeconds / 60)) min",
            "",
            "## Summary",
            note.summary,
        ]
        if !note.keyPoints.isEmpty {
            lines.append("")
            lines.append("## Key points")
            lines.append(contentsOf: note.keyPoints.map { "- \($0)" })
        }
        if !note.actionItems.isEmpty {
            lines.append("")
            lines.append("## Action items")
            lines.append(contentsOf: note.actionItems.map { "- [ ] \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}

public struct MeetingNote: Codable, Sendable, Hashable {
    public var title: String
    public var summary: String
    public var keyPoints: [String]
    public var actionItems: [String]

    public init(title: String, summary: String, keyPoints: [String], actionItems: [String]) {
        self.title = title
        self.summary = summary
        self.keyPoints = keyPoints
        self.actionItems = actionItems
    }
}

/// Encrypted meeting storage — meetings never leave the device.
public final class MeetingStore: @unchecked Sendable {
    public static let shared = MeetingStore(
        fileURL: AppPaths.supportDirectory.appendingPathComponent("meetings.enc"))

    private var meetings: [Meeting] = []
    private let fileURL: URL
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(label: "ai.lockedin.flow.meeting-store")

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    /// Adds a meeting and does not return until the encrypted snapshot is
    /// durably written. Callers may safely release any in-memory rescue audio
    /// only after this method succeeds.
    public func record(_ meeting: Meeting) async throws {
        let snapshot = snapshotAfterRecording(meeting)
        do {
            try await persist(snapshot)
        } catch {
            removeFromMemory(id: meeting.id)
            throw error
        }
    }

    /// Replaces a preserved transcript with completed notes. If the user deleted
    /// the placeholder while notes were being prepared, it stays deleted.
    @discardableResult
    public func update(_ meeting: Meeting) async throws -> Bool {
        guard let update = snapshotAfterUpdating(meeting) else { return false }
        do {
            try await persist(update.snapshot)
        } catch {
            restoreInMemory(update.previous, for: meeting.id)
            throw error
        }
        return true
    }

    private func snapshotAfterRecording(_ meeting: Meeting) -> [Meeting] {
        lock.lock()
        meetings.insert(meeting, at: 0)
        let snapshot = meetings
        lock.unlock()
        return snapshot
    }

    private func snapshotAfterUpdating(_ meeting: Meeting) -> (
        previous: Meeting,
        snapshot: [Meeting]
    )? {
        lock.lock()
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else {
            lock.unlock()
            return nil
        }
        let previous = meetings[index]
        meetings[index] = meeting
        let snapshot = meetings
        lock.unlock()
        return (previous, snapshot)
    }

    private func removeFromMemory(id: UUID) {
        lock.lock()
        meetings.removeAll { $0.id == id }
        lock.unlock()
    }

    private func restoreInMemory(_ previous: Meeting, for id: UUID) {
        lock.lock()
        if let index = meetings.firstIndex(where: { $0.id == id }) {
            meetings[index] = previous
        }
        lock.unlock()
    }

    public func all() -> [Meeting] {
        lock.lock()
        defer { lock.unlock() }
        return meetings
    }

    public func delete(id: UUID) {
        lock.lock()
        meetings.removeAll { $0.id == id }
        let snapshot = meetings
        lock.unlock()
        persistInBackground(snapshot)
    }

    private func persist(_ snapshot: [Meeting]) async throws {
        let fileURL = self.fileURL
        try await withCheckedThrowingContinuation { continuation in
            persistenceQueue.async {
                do {
                    let data = try JSONEncoder().encode(snapshot)
                    try SecureStore.writeEncrypted(data, to: fileURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func persistInBackground(_ snapshot: [Meeting]) {
        let fileURL = self.fileURL
        persistenceQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try SecureStore.writeEncrypted(data, to: fileURL)
            } catch {
                FlowLog.error("meeting persist failed code=\(errorCode: error)")
            }
        }
    }

    private func load() {
        do {
            guard let data = try SecureStore.readEncrypted(from: fileURL) else { return }
            meetings = try JSONDecoder().decode([Meeting].self, from: data)
        } catch {
            FlowLog.error("meeting load failed code=\(errorCode: error)")
        }
    }

    /// Makes background deletion writes deterministic for focused store tests.
    func waitForPendingWrites() {
        persistenceQueue.sync {}
    }
}
