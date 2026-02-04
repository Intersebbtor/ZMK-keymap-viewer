import Cocoa
import Carbon

class GlobalShortcutManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    
    static let shared = GlobalShortcutManager()
    
    private init() {}
    
    func setup(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        unregister()
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5a4d4b56) // 'ZMKV'
        hotKeyID.id = UInt32(1)
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)
        
        // Use a wrapper to keep the callback alive and pass it to the C-style handler
        let handler = ShortcutHandler(callback: callback)
        let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(handler).toOpaque())
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let handler = Unmanaged<ShortcutHandler>.fromOpaque(userData).takeUnretainedValue()
            handler.callback()
            return OSStatus(noErr)
        }, 1, &eventType, ptr, &eventHandler)
        
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if status == noErr {
            print("[Shortcut] Successfully registered shortcut (code: \(keyCode), mods: \(modifiers))")
        } else {
            print("[Shortcut] Failed to register hotkey: \(status)")
        }
    }
    
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
    
    deinit {
        unregister()
    }
}

private class ShortcutHandler {
    let callback: () -> Void
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
}
