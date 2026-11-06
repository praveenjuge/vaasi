import AppKit
import Carbon.HIToolbox

/// Prompter actions reachable from the keyboard, the on-screen controls, and
/// menus.
enum PrompterCommand: String, CaseIterable, Identifiable {
    case togglePause, faster, slower, lineBack, lineForward, previousCue, nextCue, stop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .togglePause: "Pause or resume"
        case .faster: "Faster"
        case .slower: "Slower"
        case .lineBack: "Back one line"
        case .lineForward: "Forward one line"
        case .previousCue: "Previous cue"
        case .nextCue: "Next cue"
        case .stop: "Stop"
        }
    }

    /// Global shortcut while the prompter is running.
    var shortcut: (keyCode: Int, modifiers: Int, label: String) {
        switch self {
        case .togglePause: (kVK_Space, optionKey | shiftKey, "⌥⇧Space")
        case .faster: (kVK_RightArrow, shiftKey, "⇧→")
        case .slower: (kVK_LeftArrow, shiftKey, "⇧←")
        case .lineBack: (kVK_UpArrow, shiftKey, "⇧↑")
        case .lineForward: (kVK_DownArrow, shiftKey, "⇧↓")
        case .previousCue: (kVK_UpArrow, optionKey | shiftKey, "⌥⇧↑")
        case .nextCue: (kVK_DownArrow, optionKey | shiftKey, "⌥⇧↓")
        case .stop: (kVK_Escape, optionKey | shiftKey, "⌥⇧Esc")
        }
    }
}

/// System-wide hot keys via Carbon. They work while other apps are in front and
/// don't need Accessibility access.
@MainActor
final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static var action: ((PrompterCommand) -> Void)?

    func register(_ action: @escaping (PrompterCommand) -> Void) {
        unregister()
        HotKeys.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let index = Int(id.id)
            MainActor.assumeIsolated {
                if PrompterCommand.allCases.indices.contains(index) {
                    HotKeys.action?(PrompterCommand.allCases[index])
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)

        for (index, command) in PrompterCommand.allCases.enumerated() {
            let shortcut = command.shortcut
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5641_4153), id: UInt32(index)) // "VAAS"
            if RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), id,
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            }
        }
    }

    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        HotKeys.action = nil
    }
}
