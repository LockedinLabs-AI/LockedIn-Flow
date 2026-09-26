import Foundation

public struct HistoryEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var raw: String
    public var final: String
    public var duration: TimeInterval
    public var profileID: String
    public var targetAppName: String?
    public var modelID: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        raw: String,
        final: String,
        duration: TimeInterval,
        profileID: String,
        targetAppName: String?,
        modelID: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.raw = raw
        self.final = final
        self.duration = duration
        self.profileID = profileID
        self.targetAppName = targetAppName
        self.modelID = modelID
    }
}

/// Encrypted, retention-aware dictation history. Audio is never stored — text only,
/// and only when the user's retention policy allows it.
public final class HistoryStore: @unchecked Sendable {
    public static let shared = HistoryStore(
        defaults: AppRuntime.userDefaults,
        fileURL: AppPaths.historyFile
    )

    private let maxEntries = 500
    private var entries: [HistoryEntry] = []
    private let defaults: UserDefaults
    private let fileURL: URL
    private let lock = NSLock()
    private let persistenceQueue = DispatchQueue(label: "ai.lockedin.flow.history-store")

    public var retention: RetentionPolicy {
        get {
            let raw =
                defaults.string(forKey: "historyRetention")
                ?? RetentionPolicy.sessionOnly.rawValue
            return RetentionPolicy(rawValue: raw) ?? .sessionOnly
        }
        set {
            defaults.set(newValue.rawValue, forKey: "historyRetention")
            switch newValue {
            case .off, .sessionOnly:
                // A non-persistent policy must leave no transcript from a
                // previous session in memory or on disk.
                deleteAll()
            case .oneHour, .oneDay, .sevenDays, .thirtyDays, .forever:
                purgeExpired()
                persist(all())
            }
        }
    }

    init(defaults: UserDefaults, fileURL: URL) {
        self.defaults = defaults
        self.fileURL = fileURL
        if retention.persistsAcrossLaunches {
            load()
        } else {
            removePersistedFile()
        }
        purgeExpired()
    }

    public func record(_ entry: HistoryEntry) {
        guard retention != .off else { return }
        lock.lock()
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        let snapshot = entries
        lock.unlock()
        persist(snapshot)
        purgeExpired()
    }

    public func all() -> [HistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func search(_ query: String) -> [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all() }
        let needle = trimmed.lowercased()
        return all().filter {
            $0.final.lowercased().contains(needle) || $0.raw.lowercased().contains(needle)
        }
    }

    public func delete(id: UUID) {
        lock.lock()
        entries.removeAll { $0.id == id }
        let snapshot = entries
        lock.unlock()
        persist(snapshot)
    }

    public func deleteAll() {
        lock.lock()
        entries = []
        lock.unlock()
        removePersistedFile()
    }

    /// Removes entries older than the retention cutoff. Session-only entries are
    /// kept in memory but never written to disk.
    public func purgeExpired(now: Date = Date()) {
        guard let cutoff = retention.cutoff(now: now) else { return }
        lock.lock()
        let before = entries.count
        entries.removeAll { $0.createdAt < cutoff }
        let changed = entries.count != before
        let snapshot = entries
        lock.unlock()
        if changed { persist(snapshot) }
    }

    private func persist(_ snapshot: [HistoryEntry]) {
        guard retention.persistsAcrossLaunches else { return }
        let fileURL = self.fileURL
        persistenceQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try SecureStore.writeEncrypted(data, to: fileURL)
            } catch {
                FlowLog.error("history persist failed code=\(errorCode: error)")
            }
        }
    }

    private func load() {
        do {
            guard let data = try SecureStore.readEncrypted(from: fileURL) else { return }
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            FlowLog.error("history load failed code=\(errorCode: error)")
        }
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
