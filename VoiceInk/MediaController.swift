import AppKit
import Combine
import Foundation
import SwiftUI

/// Controls system audio management during recording
class MediaController: ObservableObject {
    static let shared = MediaController()
    private var didMuteAudio = false
    
    @Published var isSystemMuteEnabled: Bool = UserDefaults.standard.bool(forKey: "isSystemMuteEnabled") {
        didSet {
            UserDefaults.standard.set(isSystemMuteEnabled, forKey: "isSystemMuteEnabled")
        }
    }
    
    private init() {
        // Set default if not already set
        if !UserDefaults.standard.contains(key: "isSystemMuteEnabled") {
            UserDefaults.standard.set(true, forKey: "isSystemMuteEnabled")
        }
    }
    
    /// Mutes system audio during recording
    func muteSystemAudio() async -> Bool {
        guard isSystemMuteEnabled else { return false }
        
        let success = executeAppleScript(command: "set volume with output muted")
        didMuteAudio = success
        return success
    }
    
    /// Restores system audio after recording
    func unmuteSystemAudio() async {
        guard isSystemMuteEnabled, didMuteAudio else { return }
        
        _ = executeAppleScript(command: "set volume without output muted")
        didMuteAudio = false
    }
    
    /// Executes an AppleScript command
    private func executeAppleScript(command: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", command]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}

extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
    
    var isSystemMuteEnabled: Bool {
        get { bool(forKey: "isSystemMuteEnabled") }
        set { set(newValue, forKey: "isSystemMuteEnabled") }
    }
}
