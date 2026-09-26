import AVFoundation

/// A started capture graph that can be replaced without coupling lifecycle
/// policy to AVAudioEngine. Tests inject inert sessions through this seam, so
/// recovery behavior never opens a microphone.
protocol AudioCaptureEngineSession: AnyObject {
    var activation: VoiceProcessingActivation { get }
    var nativeSampleRate: Double { get }

    func observeConfigurationChanges(_ handler: @escaping () -> Void)
    func stop()
}

protocol AudioCaptureEngineStarting: AnyObject {
    func start(
        preference: VoiceProcessingPreference,
        onSamples: @escaping (_ samples: [Float], _ level: Float, _ peak: Float) -> Void
    ) throws -> any AudioCaptureEngineSession
}

final class SystemAudioCaptureEngineFactory: AudioCaptureEngineStarting {
    func start(
        preference: VoiceProcessingPreference,
        onSamples: @escaping ([Float], Float, Float) -> Void
    ) throws -> any AudioCaptureEngineSession {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let activation = VoiceProcessingConfigurator.activate(
            on: input,
            preference: preference
        )

        guard activation != .unavailable else {
            // A partially switched I/O node is not a reliable standard-path
            // fallback. The manager creates a fresh graph for that attempt.
            throw AudioCaptureError.engineFailed(
                "System voice processing is unavailable for this input device."
            )
        }

        // Voice-processing activation can change the input format, so query it
        // only after the configuration request.
        let nativeFormat = input.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw AudioCaptureError.noInputDevice
        }
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AudioCaptureManager.targetSampleRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        else {
            throw AudioCaptureError.converterUnavailable
        }

        input.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: nativeFormat
        ) { buffer, _ in
            Self.convert(
                buffer,
                with: converter,
                to: targetFormat,
                onSamples: onSamples
            )
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            throw AudioCaptureError.engineFailed(error.localizedDescription)
        }

        return SystemAudioCaptureEngineSession(
            engine: engine,
            input: input,
            activation: activation,
            nativeSampleRate: nativeFormat.sampleRate
        )
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to targetFormat: AVAudioFormat,
        onSamples: ([Float], Float, Float) -> Void
    ) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard
            let output = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: capacity
            )
        else { return }

        var conversionError: NSError?
        var provided = false
        let status = converter.convert(to: output, error: &conversionError) {
            _, outputStatus in
            if provided {
                outputStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outputStatus.pointee = .haveData
            return buffer
        }
        guard conversionError == nil,
            status != .error,
            output.frameLength > 0,
            let data = output.floatChannelData?[0]
        else { return }

        let count = Int(output.frameLength)
        var sum: Float = 0
        var peak: Float = 0
        for index in 0..<count {
            sum += data[index] * data[index]
            peak = max(peak, abs(data[index]))
        }
        let rms = sqrtf(sum / Float(count))
        let samples = Array(UnsafeBufferPointer(start: data, count: count))
        onSamples(samples, min(1, rms * 5), peak)
    }
}

private final class SystemAudioCaptureEngineSession: AudioCaptureEngineSession {
    let activation: VoiceProcessingActivation
    let nativeSampleRate: Double

    private let engine: AVAudioEngine
    private let input: AVAudioInputNode
    private let lifecycleLock = NSLock()
    private var configurationObserver: NSObjectProtocol?
    private var stopped = false

    init(
        engine: AVAudioEngine,
        input: AVAudioInputNode,
        activation: VoiceProcessingActivation,
        nativeSampleRate: Double
    ) {
        self.engine = engine
        self.input = input
        self.activation = activation
        self.nativeSampleRate = nativeSampleRate
    }

    func observeConfigurationChanges(_ handler: @escaping () -> Void) {
        lifecycleLock.lock()
        guard !stopped, configurationObserver == nil else {
            lifecycleLock.unlock()
            return
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { _ in
            // Deliberately only signal policy state here. AVAudioEngine can
            // still be uninitializing when this notification is delivered.
            handler()
        }
        lifecycleLock.unlock()
    }

    func stop() {
        lifecycleLock.lock()
        guard !stopped else {
            lifecycleLock.unlock()
            return
        }
        stopped = true
        let observer = configurationObserver
        configurationObserver = nil
        lifecycleLock.unlock()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        input.removeTap(onBus: 0)
        engine.stop()
    }

    deinit {
        stop()
    }
}
