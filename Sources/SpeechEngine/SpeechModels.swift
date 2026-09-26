import FluidAudio
import Foundation
import VoiceCore

enum SpeechModelRuntimePolicy {
    static var fluidAudioOfflineMode: Bool { ModelHub.offlineMode }

    static func enforceOfflineOnly() {
        // Models are provisioned outside the application and verified against
        // the compiled manifest before loading. FluidAudio must never fall back
        // to a registry lookup from the running application.
        ModelHub.offlineMode = true
    }
}

/// The small, commercially reviewed model set exposed by LockedIn Flow.
///
/// Model choice is intentionally curated. A large catalog creates provisioning,
/// support, quality, and licensing risk without necessarily improving dictation.
public enum SpeechModelChoice: String, CaseIterable, Identifiable, Sendable {
    case multilingual = "parakeet-tdt-0.6b-v3"
    case englishPrecision = "parakeet-unified-en-0.6b"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .multilingual: return "Multilingual"
        case .englishPrecision: return "English Precision"
        }
    }

    public var shortName: String {
        switch self {
        case .multilingual: return "Parakeet v3"
        case .englishPrecision: return "Parakeet Unified"
        }
    }

    public var technicalName: String {
        switch self {
        case .multilingual: return "Parakeet TDT v3 (0.6B)"
        case .englishPrecision: return "Parakeet Unified EN (0.6B)"
        }
    }

    public var languageSummary: String {
        switch self {
        case .multilingual: return "25 European languages"
        case .englishPrecision: return "English"
        }
    }

    public var detail: String {
        switch self {
        case .multilingual:
            return "Best when you dictate in more than one language. This remains the default."
        case .englishPrecision:
            return "Optimized for higher English accuracy, punctuation, and throughput."
        }
    }

    public var modelPageURL: URL {
        switch self {
        case .multilingual:
            return URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!
        case .englishPrecision:
            return URL(
                string: "https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml")!
        }
    }
}

public enum SpeechModelFactory {
    public static func make(_ choice: SpeechModelChoice) -> any STTProviding {
        switch choice {
        case .multilingual:
            return ParakeetSTT()
        case .englishPrecision:
            return ParakeetUnifiedSTT()
        }
    }
}

/// Parakeet Unified EN 0.6B through FluidAudio's full-attention offline path.
/// It is an optional English-specialized alternative to the multilingual default.
public actor ParakeetUnifiedSTT: @preconcurrency STTProviding {
    public private(set) var isReady = false
    public let modelDisplayName = "Parakeet Unified EN · 0.6B · ANE"
    public let modelID = SpeechModelChoice.englishPrecision.rawValue

    private var asr: UnifiedAsrManager?

    public init() {}

    public func prepare() async throws {
        if isReady { return }
        SpeechModelRuntimePolicy.enforceOfflineOnly()
        FlowLog.info("parakeet unified: verifying/loading pinned offline models")
        let modelDirectory = try await PinnedModelStore.shared.prepare(
            PinnedModelCatalog.parakeetUnified
        )
        let manager = UnifiedAsrManager()
        try await manager.loadModels(from: modelDirectory)
        self.asr = manager
        self.isReady = true
        FlowLog.info("parakeet unified: models ready")
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        guard let asr else { throw STTError.notReady }
        guard samples.count >= VoiceAwareAudioPreparer.minimumTranscriptionSamples else {
            throw STTError.audioTooShort
        }
        let text = try await asr.transcribe(samples)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
