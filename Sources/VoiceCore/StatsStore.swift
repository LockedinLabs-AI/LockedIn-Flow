import Foundation

/// Local, encrypted usage statistics — words, dictations, speaking time.
/// Powers the menu-bar stats row. Never leaves the device.
public final class StatsStore: @unchecked Sendable {
    public static let shared = StatsStore()

    private struct Stats: Codable {
        var wordsTotal = 0
        var dictationsTotal = 0
        var secondsTotal: Double = 0
        var firstUseAt = Date()
    }

    private var stats = Stats()
    private let lock = NSLock()

    private init() { load() }

    public func record(words: Int, seconds: TimeInterval) {
        guard words > 0 else { return }
        lock.lock()
        stats.wordsTotal += words
        stats.dictationsTotal += 1
        stats.secondsTotal += seconds
        let snapshot = stats
        lock.unlock()
        persist(snapshot)
    }

    public var wordsTotal: Int { lock.lock(); defer { lock.unlock() }; return stats.wordsTotal }
    public var dictationsTotal: Int {
        lock.lock(); defer { lock.unlock() }; return stats.dictationsTotal
    }
    public var secondsTotal: Double {
        lock.lock(); defer { lock.unlock() }; return stats.secondsTotal
    }

    /// Words per minute of *speaking* time (not wall time).
    public var averageWPM: Int {
        lock.lock()
        defer { lock.unlock() }
        guard stats.secondsTotal > 30 else { return 0 }
        return Int((Double(stats.wordsTotal) / (stats.secondsTotal / 60)).rounded())
    }

    public var firstUseAt: Date { lock.lock(); defer { lock.unlock() }; return stats.firstUseAt }

    /// Consecutive days with at least one dictation, ending today (or yesterday).
    public func currentStreak(from entries: [HistoryEntry]) -> Int {
        let calendar = Calendar.current
        var days = Set<Date>()
        for entry in entries {
            days.insert(calendar.startOfDay(for: entry.createdAt))
        }
        var streak = 0
        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return 0
            }
            cursor = yesterday
        }
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    public func reset() {
        lock.lock()
        stats = Stats()
        lock.unlock()
        try? FileManager.default.removeItem(at: file)
    }

    private var file: URL { AppPaths.supportDirectory.appendingPathComponent("stats.enc") }

    private func persist(_ snapshot: Stats) {
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try SecureStore.writeEncrypted(data, to: self.file)
            } catch {
                FlowLog.error("usage statistics persist failed code=\(errorCode: error)")
            }
        }
    }

    private func load() {
        do {
            guard let data = try SecureStore.readEncrypted(from: file) else { return }
            stats = try JSONDecoder().decode(Stats.self, from: data)
        } catch {
            FlowLog.error("usage statistics load failed code=\(errorCode: error)")
        }
    }
}
