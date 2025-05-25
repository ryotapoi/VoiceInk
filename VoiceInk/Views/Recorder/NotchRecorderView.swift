import SwiftUI

struct NotchRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @State private var isHovering = false
    @State private var showPowerModePopover = false
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    
    private var menuBarHeight: CGFloat {
        if let screen = NSScreen.main {
            if screen.safeAreaInsets.top > 0 {
                return screen.safeAreaInsets.top
            }
            return NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
        }
        return NSStatusBar.system.thickness
    }
    
    // Calculate exact notch width
    private var exactNotchWidth: CGFloat {
        if let screen = NSScreen.main {
            // On MacBooks with notch, safeAreaInsets.left represents half the notch width
            if screen.safeAreaInsets.left > 0 {
                // Multiply by 2 because safeAreaInsets.left is half the notch width
                return screen.safeAreaInsets.left * 2
            }
            // Fallback for non-notched Macs - use a standard width
            return 200
        }
        return 200 // Default fallback
    }
    
    var body: some View {
        Group {
            if windowManager.isVisible {
                HStack(spacing: 0) {
                    // Left side group with fixed width
                    HStack(spacing: 8) {
                        // Record Button
                        NotchRecordButton(
                            isRecording: whisperState.isRecording,
                            isProcessing: whisperState.isProcessing
                        ) {
                            Task { await whisperState.toggleRecord() }
                        }
                        .frame(width: 22)
                        
                        // Power Mode Button - moved from right side
                        NotchToggleButton(
                            isEnabled: powerModeManager.isPowerModeEnabled,
                            icon: powerModeManager.currentActiveConfiguration.emoji,
                            color: .orange
                        ) {
                            showPowerModePopover.toggle()
                        }
                        .frame(width: 22)
                        .popover(isPresented: $showPowerModePopover, arrowEdge: .bottom) {
                            PowerModePopover()
                        }
                        
                        Spacer()
                    }
                    .frame(width: 64) // Increased width for both controls
                    .padding(.leading, 16)
                    
                    // Center section with exact notch width
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: exactNotchWidth)
                        .contentShape(Rectangle()) // Make the entire area tappable
                    
                    // Right side group with visualizer only
                    HStack(spacing: 0) {
                        Spacer() // Push visualizer to the right
                        
                        // Visualizer - contained within right area with scaling
                        Group {
                            if whisperState.isProcessing {
                                StaticVisualizer(color: .white)
                            } else {
                                AudioVisualizer(
                                    audioMeter: recorder.audioMeter,
                                    color: .white,
                                    isActive: whisperState.isRecording
                                )
                                // Apply a vertical scale transform to fit within the menu bar
                                .scaleEffect(y: min(1.0, (menuBarHeight - 8) / 25), anchor: .center)
                            }
                        }
                        .frame(width: 30)
                        .padding(.trailing, 8) // Add padding to keep it away from the edge
                    }
                    .frame(width: 64) // Increased width to match left side
                    .padding(.trailing, 16)
                }
                .frame(height: menuBarHeight)
                .frame(maxWidth: windowManager.isVisible ? .infinity : 0)
                .background(Color.black)
                .mask {
                    NotchShape(cornerRadius: 10)
                }
                .clipped()
                .onHover { hovering in
                    isHovering = hovering
                }
                .opacity(windowManager.isVisible ? 1 : 0)
            }
        }
    }
}

// Popover view for prompt selection
struct NotchPromptPopover: View {
    @ObservedObject var enhancementService: AIEnhancementService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Mode")
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal)
                .padding(.top, 8)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(enhancementService.allPrompts) { prompt in
                        NotchPromptRow(prompt: prompt, isSelected: enhancementService.selectedPromptId == prompt.id) {
                            enhancementService.setActivePrompt(prompt)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 180)
        .frame(maxHeight: 300)
        .padding(.vertical, 8)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

// Row view for each prompt
struct NotchPromptRow: View {
    let prompt: CustomPrompt
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: prompt.icon.rawValue)
                    .foregroundColor(isSelected ? .green : .white.opacity(0.8))
                    .font(.system(size: 12))
                Text(prompt.title)
                    .foregroundColor(.white.opacity(0.9))
                    .font(.system(size: 13))
                    .lineLimit(1)
                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}

// New toggle button component matching the notch aesthetic
struct NotchToggleButton: View {
    let isEnabled: Bool
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(icon)
                .font(.system(size: 12))
                .foregroundColor(isEnabled ? .white : .white.opacity(0.6))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CustomScaleModifier: ViewModifier {
    let scale: CGFloat
    let opacity: CGFloat
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .center)
            .opacity(opacity)
    }
}

// Notch-specific button styles
struct NotchRecordButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(buttonColor)
                    .frame(width: 22, height: 22)
                
                if isProcessing {
                    ProcessingIndicator(color: .white)
                        .frame(width: 14, height: 14)
                } else if isRecording {
                    // Show white square for recording state
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                } else {
                    // Show white circle for idle state
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isProcessing)
    }
    
    private var buttonColor: Color {
        if isProcessing {
            return Color(red: 0.4, green: 0.4, blue: 0.45)
        } else if isRecording {
            return .red
        } else {
            // Neutral gray for idle state
            return Color(red: 0.3, green: 0.3, blue: 0.35)
        }
    }
}

struct ProcessingIndicator: View {
    @State private var rotation: Double = 0
    let color: Color
    
    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(color, lineWidth: 1.5)
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
} 
