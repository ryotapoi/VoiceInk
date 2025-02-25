import SwiftUI
import AppKit

class NotchWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
    private var notchPanel: NotchRecorderPanel?
    private let whisperState: WhisperState
    private let audioEngine: AudioEngine
    
    init(whisperState: WhisperState, audioEngine: AudioEngine) {
        self.whisperState = whisperState
        self.audioEngine = audioEngine
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideNotification),
            name: NSNotification.Name("HideNotchRecorder"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleHideNotification() {
        hide()
    }
    
    func show() {
        if isVisible { return }
        
        // Get the active screen from the key window or fallback to main screen
        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        
        initializeWindow(screen: activeScreen)
        self.isVisible = true
        notchPanel?.show()
    }
    
    func hide() {
        guard isVisible else { return }
        
        // Remove animation for instant state change
        self.isVisible = false
        
        // Don't wait for animation, clean up immediately
        self.notchPanel?.hide { [weak self] in
            guard let self = self else { return }
            self.deinitializeWindow()
        }
    }
    
    private func initializeWindow(screen: NSScreen) {
        deinitializeWindow()
        
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        let panel = NotchRecorderPanel(contentRect: metrics.frame)
        
        // Create the NotchRecorderView and set it as the content
        let notchRecorderView = NotchRecorderView(whisperState: whisperState, audioEngine: audioEngine)
            .environmentObject(self)
        
        let hostingController = NotchRecorderHostingController(rootView: notchRecorderView)
        panel.contentView = hostingController.view
        
        self.notchPanel = panel
        self.windowController = NSWindowController(window: panel)
        
        // Only use orderFrontRegardless to show without activating
        panel.orderFrontRegardless()
    }
    
    private func deinitializeWindow() {
        windowController?.close()
        windowController = nil
        notchPanel = nil
    }
    
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
} 
