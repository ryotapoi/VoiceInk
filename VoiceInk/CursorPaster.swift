import Foundation
import AppKit
import OSLog

class CursorPaster {
    private static let pasteCompletionDelay: TimeInterval = 0.3
    private static let logger = Logger(subsystem: "com.voiceink", category: "CursorPaster")
    
    static func pasteAtCursor(_ text: String) {
        guard AXIsProcessTrusted() else {
            print("Accessibility permissions not granted. Cannot paste at cursor.")
            return
        }
        
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems ?? []
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        if UserDefaults.standard.bool(forKey: "UseAppleScriptPaste") {
            _ = pasteUsingAppleScript()
        } else {
            pasteUsingCommandV()
        }
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + pasteCompletionDelay) {
            if !savedItems.isEmpty {
                pasteboard.clearContents()
                pasteboard.writeObjects(savedItems)
            }
        }
    }
    
    private static func pasteUsingAppleScript() -> Bool {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            _ = scriptObject.executeAndReturnError(&error)
            if error != nil {
                logger.notice("AppleScript paste failed with error: \(error?.description ?? "Unknown error")")
                return false
            }
            return true
        }
        return false
    }
    
    private static func pasteUsingCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
}

