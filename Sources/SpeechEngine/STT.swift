import FluidAudio
import Foundation
import VoiceCore

public enum STTError: Error, LocalizedError {
    case notReady
    case audioTooShort

    public var errorDescription: String? {
        switch self {
        case .notReady: return "The speech model is not loaded yet."
        case .audioTooShort: return "The recording was too short to transcribe."
        }
    }
}

/// Abstraction over local speech-to-text providers.
/// Implementations load only pre-provisioned models and run fully on-device.
public protocol STTProviding: Sendable {
    var isReady: Bool { get }
    var modelDisplayName: String { get }
    var modelID: String { get }
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

/// Parakeet TDT v3 (0.6B) running on the Apple Neural Engine via FluidAudio.
/// Default engine: ~190x real-time factor on M4 Pro and 25 European languages.
/// The model is CC BY 4.0; the FluidAudio runtime is Apache 2.0.
public actor ParakeetSTT: @preconcurrency STTProviding {
    public private(set) var isReady = false
    public let modelDisplayName = "Parakeet TDT v3 · 0.6B · ANE"
    public let modelID = SpeechModelChoice.multilingual.rawValue

    private var asr: AsrManager?

    public init() {}

    public func prepare() async throws {
        if isReady { return }
        SpeechModelRuntimePolicy.enforceOfflineOnly()
        FlowLog.info("parakeet: verifying/loading pinned models (v3)")
        let modelDirectory = try await PinnedModelStore.shared.prepare(
            PinnedModelCatalog.parakeetTDT
        )
        let models = try await AsrModels.load(
            from: modelDirectory,
            version: .v3,
            encoderPrecision: .int8
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.asr = manager
        self.isReady = true
        FlowLog.info("parakeet: models ready")
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        guard let asr else { throw STTError.notReady }
        guard samples.count >= 4_800 else { throw STTError.audioTooShort }  // < 0.3 s of audio
        // Fresh decoder state per utterance: dictations are independent.
        var decoderState = try TdtDecoderState()
        let result = try await asr.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
