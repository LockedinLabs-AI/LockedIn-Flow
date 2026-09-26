/// A session-scoped retry slot for raw dictation audio.
///
/// This type deliberately has no persistence, encoding, or filesystem API. The
/// samples live only in the owning controller's memory and disappear when the
/// buffer is discarded or the app process exits.
public struct InMemoryDictationRetryBuffer: Sendable {
    private var samples: [Float]?

    public init() {}

    public var hasRecording: Bool {
        samples != nil
    }

    public var sampleCount: Int {
        samples?.count ?? 0
    }

    /// Keeps the most recent failed recording available for another pipeline
    /// attempt. Empty captures never replace a usable retry.
    @discardableResult
    public mutating func retain(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        self.samples = samples
        return true
    }

    /// Returns the retained recording without consuming it. The controller may
    /// therefore retain it again if a retry also fails.
    public func recordingForRetry() -> [Float]? {
        samples
    }

    public mutating func discard() {
        samples = nil
    }
}
