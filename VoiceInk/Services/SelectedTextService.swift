import Foundation
import AppKit

class SelectedTextService {
    static func fetchSelectedText() -> String? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.bundleIdentifier != "com.prakashjoshipax.VoiceInk" else {
            return nil
        }
        
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            return nil
        }
        
        return findSelectedText(in: element as! AXUIElement)
    }

    private static func findSelectedText(in element: AXUIElement) -> String? {
        var selectedTextValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success {
            if let selectedText = selectedTextValue as? String, !selectedText.isEmpty {
                return selectedText
            }
        }
        
        // Fallback for apps that use kAXValueAttribute for selected text (like some Electron apps)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success {
            if let selectedText = value as? String, !selectedText.isEmpty {
                return selectedText
            }
        }

        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
            if let axChildren = children as? [AXUIElement] {
                for child in axChildren {
                    if let foundText = findSelectedText(in: child) {
                        return foundText
                    }
                }
            }
        }
        
        return nil
    }
} 