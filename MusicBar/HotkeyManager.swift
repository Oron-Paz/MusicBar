//
//  HotkeyManager.swift
//  MusicBar
//

import Carbon.HIToolbox

/// Registers global hotkeys using Carbon's RegisterEventHotKey.
/// Works from a sandboxed app without Accessibility permission.
final class HotkeyManager {

    static let shared = HotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                HotkeyManager.shared.handlers[hotkeyID.id]?()
                return noErr
            },
            1, &eventType, nil, &eventHandlerRef
        )
    }

    /// Register a global hotkey.
    /// - Parameters:
    ///   - keyCode: Virtual key code from Carbon (e.g. kVK_Space, kVK_ANSI_M)
    ///   - modifiers: Carbon modifier mask (e.g. optionKey | shiftKey)
    ///   - action: Closure to run on the main thread when the hotkey fires
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        let id = nextID
        nextID += 1
        handlers[id] = { Task { @MainActor in action() } }

        var ref: EventHotKeyRef?
        var hotkeyID = EventHotKeyID(signature: fourCC("MBHK"), id: id)
        RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &ref)
        if let ref { hotKeyRefs.append(ref) }
    }

    private func fourCC(_ s: String) -> FourCharCode {
        s.utf8.prefix(4).reduce(0) { $0 << 8 + FourCharCode($1) }
    }
}
