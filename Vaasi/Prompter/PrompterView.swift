import AppKit
import SwiftUI
import VaasiCore

/// Black shape that grows out of the camera notch: flush with the top edge,
/// small inward curves where it meets the menu bar, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat = 10
    var bottomRadius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.minY + t), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + t + b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.maxY - b), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Glow at the bottom of the prompter that swells with your voice.
struct VoiceBeam: View {
    let meter: VoiceMeter
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let level = meter.level
            Ellipse()
                .fill(RadialGradient(colors: [color.opacity(0.95), color.opacity(0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: geo.size.width * 0.38))
                .frame(width: geo.size.width * (0.55 + 0.35 * level), height: 70 + 90 * level)
                .position(x: geo.size.width / 2, y: geo.size.height + 10)
                .opacity(0.12 + 0.88 * level)
                .blur(radius: 14)
                .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
    }
}

struct PrompterView: View {
    let controller: PrompterController

    private var preferences: Preferences { controller.preferences }

    var body: some View {
        switch controller.placement {
        case .notch: notchLayout
        case .floating: floatingLayout
        }
    }

    // MARK: Notch

    private var notchLayout: some View {
        let notch = controller.notchMetrics
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape().fill(.black)
                if preferences.showsVoiceBeam {
                    VoiceBeam(meter: controller.meter, color: preferences.beamColor)
                        .clipShape(NotchShape())
                }
                VStack(spacing: 0) {
                    HStack {
                        controls(leading: true)
                        Spacer(minLength: notch.width + 8)
                        controls(leading: false)
                    }
                    .frame(height: notch.height)
                    .padding(.horizontal, 18)
                    textArea
                        .padding(.horizontal, 22)
                        .padding(.bottom, 10)
                }
                resizeHandles
            }
            accessoryBand
                .frame(height: PrompterLayout.accessoryHeight)
        }
        // No accessibilityIdentifier on these layout roots: on macOS 27 a
        // container that carries one collapses into a leaf element and drops
        // its children from the accessibility tree. The NSPanel already sets
        // the window identifier natively.
        .overlay(alignment: .topLeading) { testProbe }
    }

    private var resizeHandles: some View {
        ZStack {
            // Bottom edge: taller or shorter.
            VStack {
                Spacer()
                ResizeHandle(cursor: .resizeUpDown) { delta in
                    controller.resizeNotch(widthDelta: 0, heightDelta: delta.height)
                }
                .frame(height: 8)
                .accessibilityIdentifier("prompter.resize.bottom")
            }
            // Side edges: wider or narrower, symmetric around the notch.
            HStack {
                ResizeHandle(cursor: .resizeLeftRight) { delta in
                    controller.resizeNotch(widthDelta: -delta.width * 2, heightDelta: 0)
                }
                .frame(width: 10)
                Spacer()
                ResizeHandle(cursor: .resizeLeftRight) { delta in
                    controller.resizeNotch(widthDelta: delta.width * 2, heightDelta: 0)
                }
                .frame(width: 10)
                .accessibilityIdentifier("prompter.resize.right")
            }
        }
    }

    // MARK: Floating

    private var floatingLayout: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.88))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
            if preferences.showsVoiceBeam {
                VoiceBeam(meter: controller.meter, color: preferences.beamColor)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            VStack(spacing: 4) {
                HStack {
                    controls(leading: true)
                    Spacer()
                    controls(leading: false)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                textArea
                    .padding(.horizontal, 26)
                    .padding(.bottom, 14)
                if controller.script.sections.count > 1 || controller.silenceHint != nil {
                    accessoryBand
                        .padding(.bottom, 10)
                }
            }
        }
        // No accessibilityIdentifier on these layout roots: on macOS 27 a
        // container that carries one collapses into a leaf element and drops
        // its children from the accessibility tree. The NSPanel already sets
        // the window identifier natively.
        .overlay(alignment: .topLeading) { testProbe }
    }

    // MARK: Pieces

    private var textArea: some View {
        ZStack {
            PrompterTextView(
                text: controller.script.promptText,
                style: PrompterTextStyle(font: preferences.font, size: preferences.textSize,
                                         lineSpacing: preferences.lineSpacing, colorHex: preferences.textColorHex),
                controller: controller
            )
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .opacity(isCountingDown ? 0.25 : 1)

            if case .countdown(let n) = controller.phase {
                Text("\(n)")
                    .font(.system(size: 64, weight: .light, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.45), .white], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: n)
                    .accessibilityIdentifier("prompter.countdown")
            }
        }
    }

    private var isCountingDown: Bool {
        if case .countdown = controller.phase { return true }
        return false
    }

    /// Hover controls. Leading: pause. Trailing: placement switch and stop.
    @ViewBuilder
    private func controls(leading: Bool) -> some View {
        let visible = controller.isHovered || controller.isPaused
        HStack(spacing: 6) {
            if leading {
                RoundIconButton(symbol: controller.isPaused ? "play.fill" : "pause.fill",
                                help: controller.isPaused ? "Resume" : "Pause",
                                identifier: "prompter.pause") {
                    controller.togglePause()
                }
            } else {
                RoundIconButton(symbol: controller.placement == .notch ? "macwindow" : "arrow.up.left",
                                help: controller.placement == .notch ? "Float the prompter" : "Back to the notch",
                                identifier: "prompter.placement") {
                    controller.togglePlacement()
                }
                RoundIconButton(symbol: "stop.fill", help: "Stop", identifier: "prompter.stop") {
                    controller.stop()
                }
            }
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: visible)
    }

    /// Cue bar and silence hint under the prompter.
    private var accessoryBand: some View {
        VStack(spacing: 6) {
            if controller.script.sections.count > 1 {
                CueBar(controller: controller)
            }
            if let hint = controller.silenceHint {
                HStack(spacing: 8) {
                    Image(systemName: "mic.slash")
                    Text(hint)
                        // Identifier on the text, not the HStack: macOS 27
                        // collapses a container that carries an identifier
                        // into a leaf element, hiding the Settings button.
                        .accessibilityIdentifier("prompter.silenceHint")
                    Button("Settings") { controller.openSettings?() }
                        .buttonStyle(.link)
                        // macOS 27 flattens link-style buttons into static
                        // text; re-state the role and name for accessibility.
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("prompter.settings")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.85), in: Capsule())
            } else if let error = controller.voiceError {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.85), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    /// Invisible element exposing live state to UI tests. The state travels as
    /// the text's value; a plain `accessibilityValue` modifier does not
    /// round-trip over accessibility on macOS 27.
    @ViewBuilder
    private var testProbe: some View {
        if !controller.testState.isEmpty {
            Text(verbatim: controller.testState)
                .font(.system(size: 1))
                .foregroundStyle(.white.opacity(0.02))
                .frame(width: 10, height: 4)
                .accessibilityIdentifier("prompter.state")
        }
    }
}

/// "‹ 2/5 ›" with a menu listing every section.
struct CueBar: View {
    let controller: PrompterController

    var body: some View {
        let sections = controller.script.sections
        HStack(spacing: 4) {
            RoundIconButton(symbol: "chevron.up", help: "Previous cue", identifier: "cue.previous") {
                controller.perform(.previousCue)
            }
            .disabled(controller.currentSection == 0)
            Menu {
                ForEach(sections) { section in
                    Button("\(section.id + 1)  \(section.name)") { controller.goToSection(section.id) }
                }
            } label: {
                Text("\(controller.currentSection + 1)/\(sections.count)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.visible)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.12), in: Capsule())
            .accessibilityIdentifier("cue.menu")
            RoundIconButton(symbol: "chevron.down", help: "Next cue", identifier: "cue.next") {
                controller.perform(.nextCue)
            }
            .disabled(controller.currentSection >= sections.count - 1)
        }
        .padding(4)
        .background(.black.opacity(0.88), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
    }
}

struct RoundIconButton: View {
    let symbol: String
    let help: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.14), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(identifier)
    }
}

/// Invisible strip that resizes the prompter when dragged.
struct ResizeHandle: View {
    let cursor: NSCursor
    let onDrag: (CGSize) -> Void
    @State private var last: CGSize = .zero

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { cursor.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let delta = CGSize(width: value.translation.width - last.width,
                                           height: value.translation.height - last.height)
                        last = value.translation
                        onDrag(delta)
                    }
                    .onEnded { _ in last = .zero }
            )
    }
}
