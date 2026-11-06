import AppKit
import AVFoundation
import Observation
import QuartzCore
import Synchronization
import SwiftUI
import VaasiCore

/// Smoothed microphone level and speech state, observed only by the beam and
/// meters so per-frame updates don't redraw the rest of the prompter.
@MainActor @Observable
final class VoiceMeter {
    var level: Double = 0
    var isSpeaking = false
}

/// Holds the recognizer's feeder so audio can start before the recognizer is ready.
final class FeederSlot: Sendable {
    private let slot = Mutex<SpeechFeeder?>(nil)
    func set(_ feeder: SpeechFeeder?) { slot.withLock { $0 = feeder } }
    func feed(_ buffer: AVAudioPCMBuffer) { slot.withLock { $0 }?.feed(buffer) }
}



@MainActor @Observable
final class PrompterController {
    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case running
    }

    private(set) var phase: Phase = .idle
    private(set) var title = ""
    private(set) var script = Script(body: "")
    private(set) var currentSection = 0
    private(set) var isPaused = false
    private(set) var isHovered = false
    private(set) var speedIndex = ScrollEngine.defaultSpeedIndex
    private(set) var isAtEnd = false
    private(set) var placement: PrompterPlacement = .notch
    private(set) var silenceHint: String?
    private(set) var voiceError: String?
    /// Compact state string for UI tests (only maintained during UI testing).
    private(set) var testState = ""
    let meter = VoiceMeter()

    var isActive: Bool { phase != .idle }

    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored let devices: AudioDevices
    @ObservationIgnored private let options: LaunchOptions
    @ObservationIgnored private var engine = ScrollEngine()
    @ObservationIgnored private var vad = VoiceActivityDetector()
    @ObservationIgnored private var gain = AutoGain()
    @ObservationIgnored private var follower = ScriptFollower(text: "")
    @ObservationIgnored private weak var textHost: PrompterTextHost?
    @ObservationIgnored private var panel: PrompterPanel?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastFrame: CFTimeInterval = 0
    @ObservationIgnored private let hotKeys = HotKeys()
    @ObservationIgnored private var audioSource: (any AudioSource)?
    @ObservationIgnored private var speech: SpeechSession?
    @ObservationIgnored private let levelMeter = LevelMeter()
    @ObservationIgnored private let feederSlot = FeederSlot()
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var voiceTime: Double = 0
    @ObservationIgnored private var loudestDB: Double = -120
    @ObservationIgnored private var lastTestStateUpdate: CFTimeInterval = 0
    @ObservationIgnored private var frameObserver: (any NSObjectProtocol)?

    /// The library window, hidden while presenting and restored on stop.
    @ObservationIgnored weak var mainWindow: NSWindow?
    /// Opens Settings (set by the app, which owns the SwiftUI environment).
    @ObservationIgnored var openSettings: (() -> Void)?

    init(preferences: Preferences, devices: AudioDevices, options: LaunchOptions) {
        self.preferences = preferences
        self.devices = devices
        self.options = options
        devices.onChange = { [weak self] in self?.inputDevicesChanged() }
        devices.startObserving()
    }

    // MARK: Lifecycle

    func start(title: String, body: String) {
        if isActive { stop() }
        self.title = title
        script = Script(body: body)
        follower = ScriptFollower(text: script.promptText)
        engine = ScrollEngine(mode: preferences.scrollMode, speedIndex: preferences.speedIndex)
        vad = VoiceActivityDetector(sensitivity: preferences.sensitivity)
        gain = AutoGain()
        speedIndex = engine.speedIndex
        currentSection = 0
        isPaused = false
        isAtEnd = false
        silenceHint = nil
        voiceError = nil
        voiceTime = 0
        loudestDB = -120
        placement = preferences.placement

        showPanel()
        mainWindow?.orderOut(nil)
        hotKeys.register { [weak self] command in self?.perform(command) }
        if engine.mode == .voice { startVoice() }
        startDisplayLink()

        let seconds = preferences.countdownSeconds
        if seconds > 0 {
            phase = .countdown(seconds)
            countdownTask = Task { [weak self] in
                for remaining in stride(from: seconds, through: 1, by: -1) {
                    self?.phase = .countdown(remaining)
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                }
                self?.phase = .running
            }
        } else {
            phase = .running
        }
        updateTestState(force: true)
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        displayLink?.invalidate()
        displayLink = nil
        hotKeys.unregister()
        stopVoice()
        saveFloatingFrame()
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        frameObserver = nil
        panel?.orderOut(nil)
        panel = nil
        phase = .idle
        updateTestState(force: true)
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    // MARK: Commands

    func perform(_ command: PrompterCommand) {
        guard isActive else { return }
        switch command {
        case .togglePause: togglePause()
        case .faster: engine.faster(); speedChanged()
        case .slower: engine.slower(); speedChanged()
        case .lineBack: jump(to: engine.offset - (textHost?.lineHeight ?? 30))
        case .lineForward: jump(to: engine.offset + (textHost?.lineHeight ?? 30))
        case .previousCue: goToSection(currentSection - 1)
        case .nextCue: goToSection(currentSection + 1)
        case .stop: stop()
        }
        updateTestState(force: true)
    }

    func togglePause() {
        engine.isPaused.toggle()
        isPaused = engine.isPaused
    }

    func goToSection(_ index: Int) {
        guard script.sections.indices.contains(index),
              let target = textHost?.offset(forCharacterRange: script.sections[index].range) else { return }
        jump(to: target)
        currentSection = index
        updateTestState(force: true)
    }

    func togglePlacement() {
        // Save while `placement` still names the mode we're leaving: leaving
        // floating must persist its frame, and leaving notch must not record
        // the notch frame as the floating frame.
        saveFloatingFrame()
        preferences.placement = placement == .notch ? .floating : .notch
        placement = preferences.placement
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        panel?.orderOut(nil)
        panel = nil
        showPanel()
        if displayLink != nil { startDisplayLink() }
        updateTestState(force: true)
    }

    /// Notch prompter edge drag: grows symmetrically around the notch.
    func resizeNotch(widthDelta: Double, heightDelta: Double) {
        preferences.notchWidth = min(max(preferences.notchWidth + widthDelta, PrompterLayout.minNotchSize.width), PrompterLayout.maxNotchSize.width)
        preferences.notchHeight = min(max(preferences.notchHeight + heightDelta, PrompterLayout.minNotchSize.height), PrompterLayout.maxNotchSize.height)
        positionPanel()
    }

    private func speedChanged() {
        speedIndex = engine.speedIndex
        preferences.speedIndex = engine.speedIndex
    }

    private func jump(to offset: Double) {
        engine.setOffset(offset)
        engine.followTarget = nil
        textHost?.setOffset(engine.offset)
        reanchorFollower()
    }

    private func reanchorFollower() {
        guard let host = textHost else { return }
        follower.reset(toUTF16Offset: host.characterIndex(atOffset: engine.offset + host.readingLine))
        speech?.resetTranscript()
    }

    // MARK: Text host

    func attach(textHost host: PrompterTextHost) {
        textHost = host
        host.onLayout = { [weak self] maxOffset in
            self?.engine.maxOffset = maxOffset
        }
        host.onUserScroll = { [weak self] offset in
            guard let self else { return }
            self.engine.setOffset(offset)
            self.engine.followTarget = nil
            self.reanchorFollower()
        }
    }

    // MARK: Window

    private var screen: NSScreen {
        mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func showPanel() {
        let panel = PrompterPanel(placement: placement)
        let root = PrompterView(controller: self)
        panel.contentView = FirstMouseHostingView(rootView: root)
        self.panel = panel
        positionPanel()
        panel.orderFrontRegardless()
        if placement == .floating {
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.saveFloatingFrame() } }
        }
    }

    private func positionPanel() {
        guard let panel else { return }
        switch placement {
        case .notch:
            let size = CGSize(width: preferences.notchWidth, height: preferences.notchHeight)
            panel.setFrame(PrompterPanel.notchFrame(on: screen, size: size), display: true)
        case .floating:
            let saved = NSRectFromString(preferences.floatingFrame)
            let frame = saved.width >= PrompterLayout.minFloatingSize.width && NSScreen.screens.contains(where: { $0.frame.intersects(saved) })
                ? saved : PrompterPanel.defaultFloatingFrame(on: screen)
            panel.setFrame(frame, display: true)
        }
    }

    private func saveFloatingFrame() {
        guard placement == .floating, let panel else { return }
        preferences.floatingFrame = NSStringFromRect(panel.frame)
    }

    var notchMetrics: NotchMetrics { NotchMetrics.of(panel?.screen ?? screen) }

    // MARK: Voice

    private func startVoice() {
        let source: any AudioSource
        if let spec = options.synthesizedAudio {
            source = SynthesizedSource(spec: spec)
        } else if let device = devices.resolve(uid: preferences.microphoneUID) {
            source = MicrophoneSource(device: device, noiseSuppression: preferences.noiseSuppression)
        } else {
            voiceError = AudioInputError.noInputDevice.localizedDescription
            return
        }
        audioSource = source
        let slot = feederSlot
        let sink = AudioSink(meter: levelMeter, onBuffer: { slot.feed($0) })
        Task {
            do {
                try await source.start(sink: sink)
            } catch {
                voiceError = error.localizedDescription
            }
        }
        if preferences.adaptiveTempo {
            let speech = SpeechSession()
            self.speech = speech
            speech.onWords = { [weak self] words in self?.heard(words) }
            Task {
                do {
                    let feeder = try await speech.start(localeIdentifier: preferences.speechLocale)
                    if self.speech === speech { slot.set(feeder) }
                } catch {
                    // Without recognition, voice mode still scrolls at the set speed while you talk.
                }
            }
        }
    }

    private func stopVoice() {
        feederSlot.set(nil)
        audioSource?.stop()
        audioSource = nil
        speech?.stop()
        speech = nil
        meter.level = 0
        meter.isSpeaking = false
    }

    private func inputDevicesChanged() {
        // Hot-swap: rebuild the input on the newly resolved device.
        guard isActive, engine.mode == .voice, options.synthesizedAudio == nil else { return }
        audioSource?.stop()
        guard let device = devices.resolve(uid: preferences.microphoneUID) else { return }
        let source = MicrophoneSource(device: device, noiseSuppression: preferences.noiseSuppression)
        audioSource = source
        let slot = feederSlot
        Task { try? await source.start(sink: AudioSink(meter: levelMeter, onBuffer: { slot.feed($0) })) }
    }

    private func heard(_ words: [String]) {
        guard phase == .running, let token = follower.update(transcriptWords: words),
              let target = textHost?.offset(forCharacterRange: token.range) else { return }
        engine.followTarget = target
    }

    // MARK: Frame loop

    private func startDisplayLink() {
        displayLink?.invalidate()
        guard let view = panel?.contentView else { return }
        let link = view.displayLink(target: FrameTarget(owner: self), selector: #selector(FrameTarget.frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrame = 0
    }

    fileprivate func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastFrame == 0 ? 0 : min(0.1, now - lastFrame)
        lastFrame = now

        // Hover pause.
        let hovered = panel.map { $0.frame.contains(NSEvent.mouseLocation) } ?? false
        if hovered != isHovered { isHovered = hovered }
        engine.isHoverPaused = hovered && preferences.hoverToPause

        // Voice.
        if let raw = levelMeter.take() {
            let db = preferences.autoGain ? gain.apply(levelDB: raw, dt: max(dt, 0.016)) : raw
            vad.sensitivity = preferences.sensitivity
            vad.process(levelDB: db, dt: max(dt, 0.016))
            let target = AudioLevel.normalized(db: db)
            meter.level += (target - meter.level) * (target > meter.level ? 0.5 : 0.15)
            if vad.isSpeaking != meter.isSpeaking { meter.isSpeaking = vad.isSpeaking }
            trackSilence(db: raw, dt: dt)
        }

        if phase == .running {
            engine.mode = preferences.scrollMode
            engine.tick(dt: dt, isSpeaking: vad.isSpeaking)
            textHost?.setOffset(engine.offset)
            if let host = textHost {
                let section = script.sectionIndex(containing: host.characterIndex(atOffset: engine.offset + host.readingLine))
                if section != currentSection { currentSection = section }
            }
            if engine.isAtEnd != isAtEnd { isAtEnd = engine.isAtEnd }
        }
        updateTestState(force: false, now: now)
    }

    /// Names the input when a voice session hears nothing, so a wrong or muted
    /// microphone is easy to spot.
    private func trackSilence(db: Double, dt: Double) {
        guard phase == .running, engine.mode == .voice else { return }
        voiceTime += dt
        loudestDB = max(loudestDB, db)
        if vad.isSpeaking {
            if silenceHint != nil { silenceHint = nil }
        } else if voiceTime > 8, loudestDB < -55, silenceHint == nil, let source = audioSource {
            silenceHint = "Not hearing anything from \(source.inputName)."
        }
    }

    private func updateTestState(force: Bool, now: CFTimeInterval = CACurrentMediaTime()) {
        guard options.isUITesting, force || now - lastTestStateUpdate > 0.1 else { return }
        lastTestStateUpdate = now
        let phaseName: String = switch phase {
        case .idle: "idle"
        case .countdown(let n): "countdown\(n)"
        case .running: "running"
        }
        testState = [
            "phase=\(phaseName)",
            "offset=\(Int(engine.offset))",
            "max=\(Int(engine.maxOffset))",
            "paused=\(engine.isPaused ? 1 : 0)",
            "hover=\(engine.isHoverPaused ? 1 : 0)",
            "speaking=\(vad.isSpeaking ? 1 : 0)",
            "speed=\(Int(engine.speed))",
            "section=\(currentSection + 1)/\(script.sections.count)",
            "follow=\(follower.lastMatchedIndex)",
            "end=\(isAtEnd ? 1 : 0)",
            "placement=\(placement.rawValue)",
            "captureHidden=\(panel?.sharingType == NSWindow.SharingType.none ? 1 : 0)",
            "mainCaptureHidden=\(mainWindow?.sharingType == NSWindow.SharingType.none ? 1 : 0)",
            "allSpaces=\(panel?.collectionBehavior.contains(.canJoinAllSpaces) == true ? 1 : 0)",
            "mainVisible=\(mainWindow?.isVisible == true ? 1 : 0)",
        ].joined(separator: ";")
    }
}

/// CADisplayLink needs an NSObject target; this forwards to the controller.
private final class FrameTarget: NSObject {
    weak var owner: PrompterController?
    init(owner: PrompterController) { self.owner = owner }

    @MainActor @objc func frame(_ link: CADisplayLink) {
        owner?.frame(link)
    }
}
