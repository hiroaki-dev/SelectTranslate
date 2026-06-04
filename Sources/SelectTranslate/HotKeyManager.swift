import Carbon
import Foundation

enum HotKeyError: LocalizedError {
    case installHandlerFailed(OSStatus)
    case registerFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .installHandlerFailed(status):
            return "InstallEventHandler failed with OSStatus \(status)."
        case let .registerFailed(status):
            return "RegisterEventHotKey failed with OSStatus \(status)."
        }
    }
}

final class HotKeyManager {
    private let id: UInt32
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let handler: () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    deinit {
        unregister()
    }

    func register() throws {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.handler()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw HotKeyError.installHandlerFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature("SLTR"), id: id)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            throw HotKeyError.registerFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private static func signature(_ string: String) -> OSType {
        string.utf8.prefix(4).reduce(0) { partial, byte in
            (partial << 8) + OSType(byte)
        }
    }
}
