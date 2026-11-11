import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Carbon's `RegisterEventHotKey` delivers only
/// the registered combination, so unlike a global `NSEvent` monitor it needs no
/// Accessibility permission.
final class GlobalHotKey {

    struct Shortcut: Equatable {
        /// A virtual key code (`kVK_…`)
        let keyCode: UInt32
        /// Carbon modifier flags (`cmdKey`, `optionKey`…)
        let modifiers: UInt32
    }

    /// ⌃⌥⌘S opens and closes the popover
    static let togglePopover = Shortcut(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    private static let signature: OSType = 0x5354_4154 // 'STAT'
    private static var nextID: UInt32 = 1

    private let id: EventHotKeyID
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Nil when the shortcut cannot be registered, e.g. another app already owns it.
    /// `action` runs on the main thread.
    init?(_ shortcut: Shortcut, action: @escaping () -> Void) {
        id = EventHotKeyID(signature: Self.signature, id: Self.nextID)
        Self.nextID += 1
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                // Every hot key of the app reaches every handler: only answer for ours
                guard status == noErr, pressed.signature == hotKey.id.signature, pressed.id == hotKey.id.id else {
                    return OSStatus(eventNotHandledErr)
                }
                hotKey.action()
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installed == noErr else { return nil }

        let registered = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registered == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
