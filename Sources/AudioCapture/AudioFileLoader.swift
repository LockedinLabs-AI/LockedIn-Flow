import AVFoundation
import Foundation

/// Loads an audio file and converts it to 16 kHz mono Float32 samples.
/// Used by the headless self-test harness; no microphone required.
public enum AudioFileLoader {
    public enum LoaderError: Error {
        case cannotOpen(String)
        case conversionFailed
    }

    public static func load16kMono(url: URL) throws -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else {
            throw LoaderError.cannotOpen(url.path)
        }
        let sourceFormat = file.processingFormat
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else {
            throw LoaderError.conversionFailed
        }

        let frameCount = AVAudioFrameCount(file.length)
        guard
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount)
        else {
            throw LoaderError.conversionFailed
        }
        try file.read(into: sourceBuffer)

        let ratio = 16_000.0 / sourceFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            throw LoaderError.conversionFailed
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        guard error == nil, status != .error, out.frameLength > 0,
            let data = out.floatChannelData?[0]
        else {
            throw LoaderError.conversionFailed
        }
        return Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
    }
}
