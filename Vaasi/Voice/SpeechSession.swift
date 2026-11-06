@preconcurrency import AVFoundation
import Foundation
import Speech
import Synchronization
import VaasiCore

/// Converts captured audio to the recognizer's format and hands it over.
/// Used only from the audio thread, one buffer at a time.
final class SpeechFeeder: @unchecked Sendable {
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(continuation: AsyncStream<AnalyzerInput>.Continuation, targetFormat: AVAudioFormat) {
        self.continuation = continuation
        self.targetFormat = targetFormat
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        if buffer.format == targetFormat {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if out.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: out)) }
    }

    func finish() { continuation.finish() }
}

/// On-device streaming transcription with SpeechAnalyzer. Reports the running
/// transcript as normalized words.
@MainActor
final class SpeechSession {
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var feeder: SpeechFeeder?
    private var transcript = TranscriptBuffer()

    var onWords: (([String]) -> Void)?

    /// Locales the recognizer can handle on this Mac.
    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted { $0.identifier < $1.identifier }
    }

    /// Prepares the recognizer (downloading the language model the first time)
    /// and returns the feeder to pass audio into.
    func start(localeIdentifier: String) async throws -> SpeechFeeder {
        let requested = Locale(identifier: localeIdentifier)
        var locale = requested
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            locale = match
        } else if let english = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) {
            locale = english
        }
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults],
                                            attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw CocoaError(.featureUnsupported)
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(256))
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        transcript.clear()

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    self.transcript.apply(text: String(result.text.characters), isFinal: result.isFinal)
                    self.onWords?(self.transcript.words)
                }
            } catch {
                // Session ended or the recognizer stopped; nothing to recover.
            }
        }
        try await analyzer.start(inputSequence: stream)
        let feeder = SpeechFeeder(continuation: continuation, targetFormat: format)
        self.feeder = feeder
        return feeder
    }

    /// Clears the transcript, e.g. after the reader jumps to another cue.
    func resetTranscript() {
        transcript.clear()
    }

    func stop() {
        feeder?.finish()
        feeder = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
    }
}
