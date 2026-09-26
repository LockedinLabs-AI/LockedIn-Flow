import Foundation

public struct RecoveryEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var raw: String
    public var final: String
    public var targetAppName: String?
    public var status: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        raw: String,
        final: String,
        targetAppName: String?,
        status: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.raw = raw
        self.final = final
        self.targetAppName = targetAppName
        self.status = status
    }
}

/// Bounded recovery log that follows the History retention policy. Persistent
/// entries are encrypted; session-only entries remain in memory; Off stores none.
public final class RecoveryStore: @unchecked Sendable {
    public static let shared = RecoveryStore(
        defaults: AppRuntime.userDefaults,
        fileURL: AppPaths.recoveryFile
    )

    private let maxEntries = 100
    private var entries: [RecoveryEntry] = []
    private let defaults: UserDefaults
    private let fileURL: URL
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(label: "ai.lockedin.flow.recovery-store")

    init(defaults: UserDefaults, fileURL: URL) {
        self.defaults = defaults
        self.fileURL = fileURL

        if retention.persistsAcrossLaunches {
            load()
            persist(pruneExpired(for: retention))
        } else {
            removePersistedFile()
        }
    }

    /// Records a transcript after its delivery attempt reaches a known outcome.
    /// Callers persist one completed success or failure entry rather than an
    /// in-flight attempt that could be mistaken for the final delivery state.
    @discardableResult
    public func record(raw: String, final: String, targetAppName: String?, status: String) -> UUID {
        let entry = RecoveryEntry(
            raw: raw, final: final, targetAppName: targetAppName, status: status)
        let policy = retention
        guard policy != .off else {
            clear()
            return entry.id
        }

        lock.lock()
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        if let cutoff = policy.cutoff() {
            entries.removeAll { $0.timestamp < cutoff }
        }
        let snapshot = entries
        lock.unlock()

        if policy.persistsAcrossLaunches {
            persist(snapshot)
        } else {
            // Session-only recovery remains available until quit but never leaves
            // an older persistent recovery file behind.
            removePersistedFile()
        }
        FlowLog.pipeline("recovery recorded")
        return entry.id
    }

    /// Updates the outcome of an existing recovery entry in place. If retention
    /// was disabled after the entry was created, the selected policy still wins.
    public func update(
        id: UUID,
        targetAppName: String?,
        status: String
    ) {
        let policy = retention
        guard policy != .off else {
            clear()
            return
        }

        lock.lock()
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        entries[index].targetAppName = targetAppName
        entries[index].status = status
        let snapshot = entries
        lock.unlock()

        if policy.persistsAcrossLaunches {
            persist(snapshot)
        } else {
            removePersistedFile()
        }
        FlowLog.pipeline("recovery updated")
    }

    public var latest: RecoveryEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first
    }

    public func all() -> [RecoveryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// Removes every recovery copy of a transcript when the user deletes its
    /// matching History row. Exact raw/final matching intentionally removes
    /// duplicate attempts too, so the privacy action cannot leave hidden copies.
    public func deleteMatching(raw: String, final: String) {
        let policy = retention
        lock.lock()
        let before = entries.count
        entries.removeAll { $0.raw == raw && $0.final == final }
        let changed = entries.count != before
        let snapshot = entries
        lock.unlock()
        guard changed else { return }

        if policy.persistsAcrossLaunches {
            persist(snapshot)
        } else {
            removePersistedFile()
        }
    }

    public func clear() {
        lock.lock()
        entries = []
        lock.unlock()
        removePersistedFile()
    }

    /// Reconciles recovery with the History retention selected by the user.
    /// Off clears memory and disk; session-only keeps current-session entries in
    /// memory but removes the encrypted file; persistent modes write the snapshot.
    public func applyRetention(_ policy: RetentionPolicy) {
        switch policy {
        case .off:
            clear()
        case .sessionOnly:
            lock.lock()
            entries = []
            lock.unlock()
            removePersistedFile()
        case .oneHour, .oneDay, .sevenDays, .thirtyDays, .forever:
            persist(pruneExpired(for: policy))
        }
    }

    private func persist(_ snapshot: [RecoveryEntry]) {
        let fileURL = self.fileURL
        persistenceQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try SecureStore.writeEncrypted(data, to: fileURL)
            } catch {
                FlowLog.error("recovery persist failed code=\(errorCode: error)")
            }
        }
    }

    private func load() {
        do {
            guard let data = try SecureStore.readEncrypted(from: fileURL) else { return }
            entries = try JSONDecoder().decode([RecoveryEntry].self, from: data)
        } catch {
            FlowLog.error("recovery load failed code=\(errorCode: error)")
        }
    }

    private func pruneExpired(for policy: RetentionPolicy, now: Date = Date()) -> [RecoveryEntry] {
        lock.lock()
        defer { lock.unlock() }
        if let cutoff = policy.cutoff(now: now) {
            entries.removeAll { $0.timestamp < cutoff }
        }
        return entries
    }

    private var retention: RetentionPolicy {
        let raw =
            defaults.string(forKey: "historyRetention")
            ?? RetentionPolicy.sessionOnly.rawValue
        return RetentionPolicy(rawValue: raw) ?? .sessionOnly
    }

    private func removePersistedFile() {
        let fileURL = self.fileURL
        persistenceQueue.sync {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Makes asynchronous persistence deterministic for focused store tests.
    func waitForPendingWrites() {
        persistenceQueue.sync {}
    }
}
