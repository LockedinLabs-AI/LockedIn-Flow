import FluidAudio
import Foundation
import VoiceCore

/// A replaceable seam around speech detection so voice-aware audio preparation
/// can be tested without loading a Core ML model.
public protocol SpeechActivityDetecting: Sendable {
    func prepare() async throws
    func speechBounds(in samples: [Float]) async throws -> Range<Int>?
}

/// The result of preparing a captured utterance for speech recognition.
///
/// `.fallback` is deliberately distinct from `.speech`: it records that optional
/// voice detection was unavailable while preserving the original audio. Voice
/// detection must never become a new point of failure for dictation.
public enum PreparedSpeechAudio: Sendable {
    case speech(samples: [Float], originalSampleCount: Int)
    case noSpeech
    case fallback(samples: [Float], originalSampleCount: Int)

    public var samplesForTranscription: [Float]? {
        switch self {
        case .speech(let samples, _), .fallback(let samples, _):
            return samples
        case .noSpeech:
            return nil
        }
    }

    public var usedVoiceActivityDetection: Bool {
        if case .speech = self { return true }
        return false
    }
}

/// On-device Silero speech detection through FluidAudio.
///
/// The detector returns one continuous range from the first detected speech to
/// the last. Internal pauses are intentionally preserved so words and sentence
/// timing are never spliced together.
public actor SileroSpeechActivityDetector: SpeechActivityDetecting {
    private var manager: VadManager?

    public init() {}

    public func prepare() async throws {
        guard manager == nil else { return }
        SpeechModelRuntimePolicy.enforceOfflineOnly()
        let modelDirectory = try await PinnedModelStore.shared.prepare(PinnedModelCatalog.sileroVAD)
        // FluidAudio's VAD initializer expects the directory immediately above
        // `Models`, not the verified `Models/silero-vad` folder itself. Derive
        // that base from the selected search root so managed-system models and
        // the per-user evaluation cache follow the same verified path.
        let fluidAudioDirectory =
            modelDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        manager = try await VadManager(modelDirectory: fluidAudioDirectory)
        FlowLog.info("silero vad: model ready")
    }

    public func speechBounds(in samples: [Float]) async throws -> Range<Int>? {
        guard !samples.isEmpty else { return nil }
        try await prepare()
        guard let manager else { return nil }

        let config = VadSegmentationConfig(
            minSpeechDuration: 0.15,
            minSilenceDuration: 0.75,
            maxSpeechDuration: .infinity,
            speechPadding: 0.15
        )
        let segments = try await manager.segmentSpeech(samples, config: config)
        return Self.continuousBounds(
            for: segments,
            sampleCount: samples.count,
            sampleRate: VadManager.sampleRate
        )
    }

    static func continuousBounds(
        for segments: [VadSegment],
        sampleCount: Int,
        sampleRate: Int
    ) -> Range<Int>? {
        guard sampleCount > 0, sampleRate > 0, let first = segments.first, let last = segments.last
        else {
            return nil
        }

        let start = max(0, min(first.startSample(sampleRate: sampleRate), sampleCount))
        let end = max(start, min(last.endSample(sampleRate: sampleRate), sampleCount))
        return start < end ? start..<end : nil
    }
}

/// Applies optional speech detection to a completed recording.
///
/// Silero is used only to trim the leading and trailing non-speech edges. A
/// detector error returns the untouched recording, and disabling the feature
/// bypasses the detector entirely.
public actor VoiceAwareAudioPreparer {
    public static let minimumTranscriptionSamples = 4_800

    private let detector: any SpeechActivityDetecting
    private var unavailableForSession = false

    public init(detector: any SpeechActivityDetecting = SileroSpeechActivityDetector()) {
        self.detector = detector
    }

    /// Best-effort warmup. Readiness is never required for dictation.
    public func prewarm() async {
        guard !unavailableForSession else { return }
        do {
            try await detector.prepare()
        } catch is CancellationError {
            return
        } catch {
            unavailableForSession = true
            FlowLog.info("silero vad: optional warmup unavailable code=\(errorCode: error)")
        }
    }

    public func prepare(
        _ samples: [Float],
        enabled: Bool
    ) async -> PreparedSpeechAudio {
        guard enabled else {
            return .fallback(samples: samples, originalSampleCount: samples.count)
        }
        guard !unavailableForSession else {
            return .fallback(samples: samples, originalSampleCount: samples.count)
        }

        let startedAt = Date()
        do {
            guard let detectedBounds = try await detector.speechBounds(in: samples) else {
                guard samples.count < Self.minimumTranscriptionSamples else {
                    FlowLog.pipeline(
                        "vad completed result=fallback-no-speech samples=\(samples.count) elapsedMs=\(elapsedMilliseconds(since: startedAt))"
                    )
                    return .fallback(samples: samples, originalSampleCount: samples.count)
                }
                FlowLog.pipeline(
                    "vad completed result=no-speech samples=\(samples.count) elapsedMs=\(elapsedMilliseconds(since: startedAt))"
                )
                return .noSpeech
            }

            let safeBounds = Self.expandedBounds(
                detectedBounds,
                sampleCount: samples.count,
                minimumCount: Self.minimumTranscriptionSamples
            )
            let trimmed = Array(samples[safeBounds])
            FlowLog.pipeline(
                "vad completed result=speech originalSamples=\(samples.count) preparedSamples=\(trimmed.count) elapsedMs=\(elapsedMilliseconds(since: startedAt))"
            )
            return .speech(samples: trimmed, originalSampleCount: samples.count)
        } catch is CancellationError {
            return .fallback(samples: samples, originalSampleCount: samples.count)
        } catch {
            unavailableForSession = true
            FlowLog.info(
                "silero vad: optional detection unavailable; using original audio code=\(errorCode: error)"
            )
            return .fallback(samples: samples, originalSampleCount: samples.count)
        }
    }

    static func expandedBounds(
        _ proposed: Range<Int>,
        sampleCount: Int,
        minimumCount: Int
    ) -> Range<Int> {
        guard sampleCount > 0 else { return 0..<0 }

        var lower = max(0, min(proposed.lowerBound, sampleCount))
        var upper = max(lower, min(proposed.upperBound, sampleCount))
        let targetCount = min(max(0, minimumCount), sampleCount)

        guard upper - lower < targetCount else { return lower..<upper }

        let missing = targetCount - (upper - lower)
        lower = max(0, lower - (missing / 2))
        upper = min(sampleCount, lower + targetCount)
        lower = max(0, upper - targetCount)
        return lower..<upper
    }

    private func elapsedMilliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1_000)
    }
}
