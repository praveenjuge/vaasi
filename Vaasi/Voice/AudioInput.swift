@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import Synchronization
import VaasiCore

/// Latest input level, written on the audio thread and read once per frame.
final class LevelMeter: Sendable {
    private let state = Mutex<(db: Double, updated: Bool)>((-120, false))

    func record(db: Double) {
        state.withLock { $0 = (db, true) }
    }

    /// The most recent level, or nil if no audio arrived since the last read.
    func take() -> Double? {
        state.withLock { value in
            guard value.updated else { return nil }
            value.updated = false
            return value.db
        }
    }
}

/// Where audio buffers go once captured: the level meter, and optionally the
/// speech recognizer.
struct AudioSink: Sendable {
    let meter: LevelMeter
    let onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func process(_ buffer: AVAudioPCMBuffer) {
        if let channel = buffer.floatChannelData?[0] {
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            meter.record(db: AudioLevel.rmsDB(samples))
        }
        onBuffer?(buffer)
    }
}

enum AudioInputError: LocalizedError {
    case permissionDenied
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Vaasi doesn't have access to the microphone. Allow it in System Settings › Privacy & Security › Microphone."
        case .noInputDevice: "No microphone is connected."
        }
    }
}

/// Something that produces audio for a session.
@MainActor
protocol AudioSource: AnyObject {
    /// Human-readable input name, used in the silence hint.
    var inputName: String { get }
    func start(sink: AudioSink) async throws
    func stop()
}

/// Captures a microphone through AVAudioEngine.
@MainActor
final class MicrophoneSource: AudioSource {
    private let engine = AVAudioEngine()
    private let device: AudioInputDevice
    private let noiseSuppression: Bool
    private var configObserver: (any NSObjectProtocol)?
    private var sink: AudioSink?

    init(device: AudioInputDevice, noiseSuppression: Bool) {
        self.device = device
        self.noiseSuppression = noiseSuppression
    }

    var inputName: String { device.name }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(sink: AudioSink) async throws {
        guard await MicrophoneSource.requestPermission() else { throw AudioInputError.permissionDenied }
        self.sink = sink
        try startEngine()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // Sample rate or route changed underneath us: rebuild the tap.
            MainActor.assumeIsolated { try? self?.restart() }
        }
    }

    private func startEngine() throws {
        let input = engine.inputNode
        if noiseSuppression {
            try input.setVoiceProcessingEnabled(true)
        }
        if let unit = input.audioUnit {
            // Listen to the microphone picked in Settings, not just the system default.
            var deviceID = device.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioInputError.noInputDevice }
        let sink = self.sink
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            sink?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func restart() throws {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try startEngine()
    }

    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        sink = nil
    }
}

/// Plays synthesized speech and silence through the pipeline in real time,
/// for verification runs. Spec: `speak:Some words|silence:2|speak:More`.
@MainActor
final class SynthesizedSource: AudioSource {
    private let spec: String
    private var task: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()

    init(spec: String) { self.spec = spec }

    var inputName: String { "Synthesized speech" }

    func start(sink: AudioSink) async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
        var segments: [AVAudioPCMBuffer] = []
        for part in spec.split(separator: "|") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            if pieces[0] == "silence", let seconds = Double(pieces[1]) {
                segments.append(SynthesizedSource.silence(seconds: seconds, format: format))
            } else if pieces[0] == "speak" {
                segments.append(await render(text: pieces[1], format: format))
            }
        }
        task = Task.detached(priority: .userInitiated) {
            await SynthesizedSource.play(segments, format: format, sink: sink)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Feeds 20 ms chunks on the wall clock, like a live microphone.
    private nonisolated static func play(_ segments: [AVAudioPCMBuffer], format: AVAudioFormat, sink: AudioSink) async {
        let chunkFrames = AVAudioFrameCount(format.sampleRate * 0.02)
        let clock = ContinuousClock()
        var next = clock.now
        for segment in segments {
            var position: AVAudioFrameCount = 0
            while position < segment.frameLength {
                if Task.isCancelled { return }
                let count = min(chunkFrames, segment.frameLength - position)
                guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return }
                chunk.frameLength = count
                memcpy(chunk.floatChannelData![0], segment.floatChannelData![0].advanced(by: Int(position)),
                       Int(count) * MemoryLayout<Float>.size)
                sink.process(chunk)
                position += count
                next = next.advanced(by: .milliseconds(20))
                try? await clock.sleep(until: next)
            }
        }
        // Keep the line open with silence, like a mic in a quiet room.
        let quiet = silence(seconds: 0.02, format: format)
        while !Task.isCancelled {
            sink.process(quiet)
            next = next.advanced(by: .milliseconds(20))
            try? await clock.sleep(until: next)
        }
    }

    private nonisolated static func silence(seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        memset(buffer.floatChannelData![0], 0, Int(frames) * MemoryLayout<Float>.size)
        return buffer
    }

    private func render(text: String, format: AVAudioFormat) async -> AVAudioPCMBuffer {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        let collected = SampleCollector()
        // Callbacks below run on audio/synthesis threads, hence @Sendable (nonisolated).
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let finished = OnceFlag()
            synthesizer.write(utterance) { @Sendable buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    if finished.claim() { done.resume() }
                    return
                }
                collected.append(SynthesizedSource.floatSamples(pcm, to: format))
            }
        }
        let samples = collected.samples
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }

    private nonisolated static func floatSamples(_ pcm: AVAudioPCMBuffer, to format: AVAudioFormat) -> [Float] {
        guard let converter = AVAudioConverter(from: pcm.format, to: format) else { return [] }
        let ratio = format.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return [] }
        let supplied = OnceFlag()
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            guard supplied.claim() else {
                status.pointee = .endOfStream
                return nil
            }
            status.pointee = .haveData
            return pcm
        }
        return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }
}

/// True exactly once, from any thread.
final class OnceFlag: Sendable {
    private let state = Mutex(false)

    /// Returns true the first time it's called.
    func claim() -> Bool {
        state.withLock { claimed in
            defer { claimed = true }
            return !claimed
        }
    }
}

private final class SampleCollector: Sendable {
    private let state = Mutex<[Float]>([])
    func append(_ samples: [Float]) { state.withLock { $0.append(contentsOf: samples) } }
    var samples: [Float] { state.withLock { $0 } }
}
